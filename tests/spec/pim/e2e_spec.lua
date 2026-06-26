-- e2e_spec: drive the full pim pipeline from a fake pi subprocess to the
-- conversation buffer + transcript. We spawn the helpers/fake_pi.lua script
-- as `pi_cmd` and script the event stream via a behavior file. The only
-- modules stubbed are bridge (no real TCP) and jsonl / settings_editor (we
-- still want them loaded fresh, so they participate in the chain).

local function wipe_pim_buffer()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == "pim://conversation" then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

local function fake_pi_path()
  -- Walk up from the spec file to find tests/helpers/fake_pi.lua. This lets
  -- the spec work regardless of CWD when invoked via PlenaryBustedDirectory.
  local candidates = {
    "tests/helpers/fake_pi.lua",
    "./tests/helpers/fake_pi.lua",
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
      .. "/helpers/fake_pi.lua",
  }
  for _, c in ipairs(candidates) do
    if vim.fn.filereadable(c) == 1 then return vim.fn.fnamemodify(c, ":p") end
  end
  error("could not find tests/helpers/fake_pi.lua")
end

local function write_behavior(lines)
  local path = vim.fn.tempname()
  local f = assert(io.open(path, "w"))
  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()
  return path
end

describe("pim end-to-end (fake_pi → buffer + transcript)", function()
  local bridge_module -- re-stubbed per-test
  local tmpdir
  local behavior

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    behavior = write_behavior({
      'EVENT {"type":"response","command":"get_state","success":true,"data":{"sessionId":"sess-1","sessionFile":"/tmp/sess-1.jsonl"}}',
      'SLEEP 60',
      'EVENT {"type":"agent_start"}',
      'EVENT {"type":"message_update","assistantMessageEvent":{"type":"text_start"}}',
      'EVENT {"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"Hello "}}',
      'EVENT {"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"world!"}}',
      'EVENT {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"Hello world!"}]}}',
      'EVENT {"type":"agent_end"}',
      'SLEEP 200',
      'EXIT',
    })

    -- Drop modules so we get fresh state, plus stub bridge to skip TCP.
    for _, mod in ipairs({
      "pim", "pim.bridge", "pim.buffer", "pim.context", "pim.rpc",
      "pim.transcript", "pim.settings_editor", "pim.jsonl",
    }) do
      package.loaded[mod] = nil
    end
    wipe_pim_buffer()
    bridge_module = {
      setup = function() return nil end,
      stop = function() end,
      info = function() return { port = nil, token = nil } end,
    }
    package.loaded["pim.bridge"] = bridge_module
  end)

  after_each(function()
    if tmpdir then
      vim.fn.delete(tmpdir, "rf")
      tmpdir = nil
    end
    if behavior then
      vim.fn.delete(behavior)
      behavior = nil
    end
    -- Be sure to stop any still-running RPC subprocess between tests.
    pcall(function() require("pim.rpc").stop() end)
    -- Close any leftover pim windows/buffers from real buffer module.
    pcall(function() require("pim.buffer").close() end)
    wipe_pim_buffer()
  end)

  it("get_state response triggers an attached session line in the buffer", function()
    local pim = require("pim")
    pim.setup({
      keymaps = false,
      pi_cmd = { "lua", fake_pi_path(), behavior },
      transcript = { dir = tmpdir },
      bridge = { enabled = false },
    })
    pim.open()
    -- Wait until the buffer contains the attached-session line.
    local bufnr
    vim.wait(3000, function()
      bufnr = vim.fn.bufnr("pim://conversation")
      if bufnr == -1 then return false end
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:find("pim attached", 1, true) then return true end
      end
      return false
    end, 20)
    assert.is_truthy(bufnr > 0, "expected pim://conversation buffer to exist")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found = false
    for _, line in ipairs(lines) do
      if line:find("pim attached", 1, true) and line:find("sess%-1", 1, false) then
        found = true
        break
      end
    end
    assert.is_true(found, "expected attached-session line in conversation buffer")
  end)

  it("text_delta events accumulate into a single assistant block", function()
    local pim = require("pim")
    pim.setup({
      keymaps = false,
      pi_cmd = { "lua", fake_pi_path(), behavior },
      transcript = { dir = tmpdir },
      bridge = { enabled = false },
    })
    pim.open()
    local bufnr
    vim.wait(3000, function()
      bufnr = vim.fn.bufnr("pim://conversation")
      if bufnr == -1 then return false end
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:find("Hello world!", 1, true) then return true end
      end
      return false
    end, 20)
    assert.is_truthy(bufnr > 0)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- The conversation must contain the streamed assistant text.
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("Hello world!", 1, true), "expected streamed text in buffer")
    -- And only ONE assistant heading — successive deltas should NOT each open a
    -- new `## pi` block.
    local headings = 0
    for _, l in ipairs(lines) do
      if l == "## pi" then headings = headings + 1 end
    end
    assert.are.same(1, headings)
  end)

  it("transcript writes raw JSONL events under the configured directory", function()
    local pim = require("pim")
    pim.setup({
      keymaps = false,
      pi_cmd = { "lua", fake_pi_path(), behavior },
      transcript = { dir = tmpdir },
      bridge = { enabled = false },
    })
    pim.open()
    -- Wait for the JSONL log to contain all the events we scripted.
    vim.wait(3000, function()
      local jsonl = tmpdir .. "/sess-1.jsonl"
      if vim.fn.filereadable(jsonl) == 0 then return false end
      local count = #vim.fn.readfile(jsonl)
      return count >= 6 -- one response + agent_start + agent_end + 3 message updates
    end, 20)
    local jsonl = tmpdir .. "/sess-1.jsonl"
    local lines = vim.fn.readfile(jsonl)
    assert.is_truthy(#lines >= 6)
    -- Decode each line and assert one is `agent_start` and one is `agent_end`.
    local types = {}
    for _, l in ipairs(lines) do
      local ok, decoded = pcall(vim.json.decode, l)
      if ok and type(decoded) == "table" then
        types[decoded.type or "?"] = (types[decoded.type or "?"] or 0) + 1
      end
    end
    assert.is_truthy(types.agent_start and types.agent_start >= 1)
    assert.is_truthy(types.agent_end and types.agent_end >= 1)
    assert.is_truthy(types["message_update"] and types["message_update"] >= 3)
  end)
end)
