-- init_spec exercises the public API of `require("pim")`. We:
--   - Wipe buffer + module state between tests so a leftover
--     `pim://conversation` buffer never collides with a fresh one.
--   - Stub bridge (no TCP), buffer (no real windows / timers), rpc (no
--     subprocess), and transcript (no disk writes) where it makes sense.
--   - Use `pi_config_dir` as a public setup knob so tests never touch the
--     user's real `~/.pi/agent`.

local function wipe_pim_buffer()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == "pim://conversation" then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

local function reload_modules_with_stubs(stubs)
  -- Drop every pim submodule so require() picks up our stubs.
  for _, mod in ipairs({
    "pim", "pim.bridge", "pim.buffer", "pim.context", "pim.rpc",
    "pim.transcript", "pim.settings_editor", "pim.jsonl",
  }) do
    package.loaded[mod] = nil
  end
  for mod, stub in pairs(stubs or {}) do
    package.loaded[mod] = stub
  end
end

-- Default stubs: real bridge is replaced with a no-op (no TCP socket), and
-- buffer / transcript are replaced with no-ops so tests can exercise pim's
-- own logic without leaving background timers / writing real files.
local function reset_state(tmpdir)
  wipe_pim_buffer()
  reload_modules_with_stubs({
    ["pim.bridge"] = {
      setup = function() return nil end,
      stop = function() end,
      info = function() return { port = nil, token = nil } end,
    },
    ["pim.buffer"] = {
      setup = function() end,
      ensure = function() return -1 end,
      open = function() return -1 end,
      close = function() end,
      append_line = function() end,
      append_block = function() end,
      start_working = function() end,
      stop_working = function() end,
      latest = function() end,
      next_message = function() end,
      prev_message = function() end,
      finish_assistant_message = function() end,
      set_lines = function() end,
      append_delta = function() end,
      start_assistant_message = function() end,
    },
    ["pim.transcript"] = {
      setup = function() end,
      attach_session = function() end,
      ensure_current = function() end,
      append_markdown = function() end,
      append_block = function() end,
      append_event = function() end,
      read_markdown_lines = function() return {} end,
      paths = function() return {} end,
    },
    -- Allow caller to override these by passing a tmpdir.
    ["pim"] = nil,
  })
end

describe("pim.setup", function()
  before_each(function() reset_state(nil) end)

  it("accepts an empty setup with no errors", function()
    local pim = require("pim")
    assert.has_no.errors(function() pim.setup({}) end)
  end)

  it("honors keymaps = false by not registering <leader>p* defaults", function()
    -- Run default setup first to register ` pm`, then re-setup with
    -- keymaps=false and verify that no FUTURE setup adds new maps under the
    -- default prefix. We can only assert that pim.setup({keymaps = false})
    -- does not throw and does not register any ` pm` map itself (which we
    -- can detect by running this test against a clean keymap set first).
    vim.api.nvim_del_keymap("n", " pm")
    local pim = require("pim")
    pim.setup({ keymaps = false })
    local has_pm = false
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.lhs == " pm" then
        has_pm = true
      end
    end
    assert.is_false(has_pm, "expected ` pm` NOT to be pim-registered with keymaps=false")
  end)

  it("uses the configured prefix for keymaps", function()
    local pim = require("pim")
    pim.setup({ keymaps = { prefix = "<leader>x" } })
    local found_xs = false
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.lhs == " xs" then
        found_xs = true
      end
    end
    assert.is_true(found_xs, "expected ` xs` keymap for prefix <leader>x")
  end)

  it("bridge.enabled = false does not call bridge.setup with a real socket", function()
    local called = false
    package.loaded["pim.bridge"] = {
      setup = function() called = true; return nil end,
      stop = function() end, info = function() return {} end,
    }
    package.loaded["pim"] = nil
    local pim = require("pim")
    pim.setup({ bridge = { enabled = false } })
    assert.is_false(called, "expected bridge.setup not to be called when bridge.enabled=false")
  end)
end)

describe("pim.set_model", function()
  local tmpdir
  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    reset_state(tmpdir)
  end)
  after_each(function()
    if tmpdir then vim.fn.delete(tmpdir, "rf") end
    tmpdir = nil
  end)

  it("writes provider and model to a fresh settings.json", function()
    -- Pre-create an empty settings file so vim.fn.readfile doesn't error
    -- inside set_model (matches what a real user would have on disk).
    vim.fn.writefile({ "{}" }, tmpdir .. "/settings.json")
    local pim = require("pim")
    pim.setup({ keymaps = false, pi_config_dir = tmpdir })
    -- Stub rpc here too so set_model's call to M.reload doesn't spawn a
    -- subprocess between tests.
    local rpc_started = 0
    package.loaded["pim.rpc"] = {
      setup = function() end,
      start = function() rpc_started = rpc_started + 1 end,
      stop = function() end,
      send = function() end, prompt = function() end, steer = function() end,
      follow_up = function() end, get_state = function() end, abort = function() end,
      is_running = function() return false end,
    }
    package.loaded["pim"] = nil
    pim = require("pim")
    pim.setup({ keymaps = false, pi_config_dir = tmpdir })
    pim.set_model("openai", "gpt-5")

    local path = tmpdir .. "/settings.json"
    assert.are.same(1, vim.fn.filereadable(path))
    local content = table.concat(vim.fn.readfile(path), "\n")
    assert.is_truthy(content:find("defaultProvider", 1, true))
    assert.is_truthy(content:find("openai", 1, true))
    assert.is_truthy(content:find("defaultModel", 1, true))
    assert.is_truthy(content:find("gpt-5", 1, true))
  end)

  it("preserves nested objects when editing settings.json", function()
    local initial = [[{
  "defaultProvider": "anthropic",
  "theme": "dark",
  "tools": {
    "bash": true,
    "custom": { "level": 3 }
  }
}]]
    vim.fn.writefile(vim.split(initial, "\n"), tmpdir .. "/settings.json")

    -- Stub rpc so set_model's reload doesn't spawn a real subprocess.
    package.loaded["pim.rpc"] = {
      setup = function() end, start = function() end, stop = function() end,
      send = function() end, prompt = function() end, steer = function() end,
      follow_up = function() end, get_state = function() end, abort = function() end,
      is_running = function() return false end,
    }
    package.loaded["pim"] = nil
    local pim = require("pim")
    pim.setup({ keymaps = false, pi_config_dir = tmpdir })
    pim.set_model("openai", "gpt-5")

    local content = table.concat(vim.fn.readfile(tmpdir .. "/settings.json"), "\n")
    assert.is_truthy(content:find('"bash":%s*true', 1, false))
    assert.is_truthy(content:find('"level":%s*3', 1, false))
    assert.is_truthy(content:find('"defaultModel"', 1, true))
    assert.is_truthy(content:find('"gpt-5"', 1, true))
  end)
end)

describe("pim.reload", function()
  local tmpdir
  local rpc_state
  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    reset_state(tmpdir)
    rpc_state = { start_n = 0, stop_n = 0, last_args = nil }
    package.loaded["pim.rpc"] = {
      setup = function() end,
      start = function(args)
        rpc_state.start_n = rpc_state.start_n + 1
        rpc_state.last_args = args
      end,
      stop = function() rpc_state.stop_n = rpc_state.stop_n + 1 end,
      send = function() end, prompt = function() end, steer = function() end,
      follow_up = function() end, get_state = function() end, abort = function() end,
      is_running = function() return false end,
    }
  end)
  after_each(function()
    if tmpdir then vim.fn.delete(tmpdir, "rf") end
    tmpdir = nil
    rpc_state = nil
  end)

  it("stops the existing process and starts a new one with provider/model from settings", function()
    vim.fn.writefile(vim.split([[{
  "defaultProvider": "openai",
  "defaultModel": "gpt-5",
  "defaultThinkingLevel": "high"
}]], "\n"), tmpdir .. "/settings.json")

    local pim = require("pim")
    pim.setup({ keymaps = false, pi_config_dir = tmpdir })
    pim.reload()

    vim.wait(500, function()
      return rpc_state.start_n >= 1 and rpc_state.stop_n >= 1
    end, 10)
    assert.is_true(rpc_state.stop_n >= 1)
    assert.is_true(rpc_state.start_n >= 1)
    local args = rpc_state.last_args or {}
    assert.is_truthy(vim.tbl_contains(args, "--provider"), "--provider")
    assert.is_truthy(vim.tbl_contains(args, "openai"), "openai")
    assert.is_truthy(vim.tbl_contains(args, "--model"), "--model")
    assert.is_truthy(vim.tbl_contains(args, "gpt-5"), "gpt-5")
    assert.is_truthy(vim.tbl_contains(args, "--thinking"), "--thinking")
  end)
end)

describe("pim public surface", function()
  local tmpdir
  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    reset_state(tmpdir)
  end)
  after_each(function()
    if tmpdir then vim.fn.delete(tmpdir, "rf") end
    tmpdir = nil
  end)

  it("every documented command is callable", function()
    local pim = require("pim")
    for _, fn in ipairs({
      "open", "close", "toggle", "stop", "abort", "send", "steer",
      "follow_up", "send_selection", "send_buffer", "transcript_paths",
      "bridge_info", "clear_highlights", "next_message", "prev_message",
      "latest", "open_transcript", "reload", "pick_model",
      "edit_model_config", "set_model",
      "comment", "send_comments", "list_comments", "clear_comments",
      "help",
    }) do
      assert.is_function(pim[fn], "pim." .. fn .. " should be a function")
    end
  end)

  it("pick_model is a no-op when models.json is missing", function()
    -- Point pi_config_dir at an empty tmpdir that has no models.json;
    -- pick_model should then notify and exit without invoking vim.ui.select
    -- (which would otherwise hang in headless mode since there's no UI to
    -- read from).
    local pim = require("pim")
    pim.setup({ keymaps = false, pi_config_dir = tmpdir })
    assert.has_no.errors(function() pim.pick_model() end)
  end)
end)
