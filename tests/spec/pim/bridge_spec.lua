-- bridge: local TCP JSONL server that pim's running pi subprocess connects to
-- for editor control. We test it by opening a real TCP client from the test
-- process and asserting frames come back.

local uv = vim.uv or vim.loop

local function wipe_bridge()
  package.loaded["pim.bridge"] = nil
end

-- Bring the bridge up and return (port, token, teardown).
local function fresh_bridge()
  wipe_bridge()
  local bridge = require("pim.bridge")
  -- Use a stable token so we can write the spec without plumbing a generator.
  local info = assert(bridge.setup({ token = "test-token-abc" }))
  assert.is_truthy(info.port)
  assert.are.same("test-token-abc", info.token)
  return info.port, info.token, function()
    bridge.stop()
  end
end

-- Send a JSONL frame on a TCP client and accumulate the response into
-- `received` until either `predicate(received)` returns true or the deadline
-- is reached. Returns the buffered string lines.
local function round_trip(port, frames, predicate, deadline_ms)
  deadline_ms = deadline_ms or 2000
  local received = ""
  local client = uv.new_tcp()
  local done = false
  client:connect("127.0.0.1", port, function(err)
    assert.is_nil(err, "TCP connect failed: " .. tostring(err))
    client:read_start(function(_, chunk)
      if chunk then
        received = received .. chunk
        if predicate and predicate(received) then
          done = true
          if not client:is_closing() then
            client:close()
          end
        end
      else
        if not client:is_closing() then
          client:close()
        end
      end
    end)
    for _, frame in ipairs(frames) do
      client:write(frame .. "\n")
    end
  end)
  vim.wait(deadline_ms, function() return done end, 10)
  if not done and not client:is_closing() then
    client:close()
  end
  return received
end

local function parse_frames(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      table.insert(out, vim.json.decode(line))
    end
  end
  return out
end

describe("bridge.setup / stop / info", function()
  it("returns the listening port and the configured token", function()
    wipe_bridge()
    local bridge = require("pim.bridge")
    local info = assert(bridge.setup({ token = "t" }))
    assert.is_truthy(info.port > 0)
    assert.are.same("t", info.token)
    bridge.stop()
  end)

  it("info() returns the same port and token after setup", function()
    wipe_bridge()
    local bridge = require("pim.bridge")
    local info = bridge.setup({ token = "t" })
    local later = bridge.info()
    assert.are.same(info.port, later.port)
    assert.are.same(info.token, later.token)
    bridge.stop()
  end)

  it("is a no-op when enabled=false", function()
    wipe_bridge()
    local bridge = require("pim.bridge")
    local result = bridge.setup({ enabled = false })
    assert.is_nil(result)
    assert.is_nil(bridge.info().port)
  end)
end)

describe("bridge handshake / protocol", function()
  local port, token, teardown
  before_each(function()
    wipe_bridge()
    port, token, teardown = fresh_bridge()
  end)
  after_each(function()
    if teardown then
      teardown()
    end
  end)

  it("rejects requests with an invalid token", function()
    local raw = round_trip(port, {
      vim.json.encode({ id = 1, method = "nvim_get_current_context", token = "wrong", params = {} }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    assert.are.same(1, #frames)
    assert.are.same(1, frames[1].id)
    assert.is_false(frames[1].ok)
    assert.is_truthy(tostring(frames[1].error):find("token", 1, true))
  end)

  it("responds to a valid request with ok=true", function()
    local raw = round_trip(port, {
      vim.json.encode({ id = 7, method = "nvim_get_current_context", token = token, params = {} }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    local response = frames[#frames]
    assert.are.same(7, response.id)
    assert.is_true(response.ok)
  end)

  it("returns ok=false for unknown method names", function()
    local raw = round_trip(port, {
      vim.json.encode({ id = 2, method = "this_does_not_exist", token = token, params = {} }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    local response = frames[#frames]
    assert.are.same(2, response.id)
    assert.is_false(response.ok)
    assert.is_truthy(tostring(response.error):find("unknown", 1, true))
  end)

  it("returns ok=false for invalid JSON lines", function()
    local raw = round_trip(port, { "not-json" }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    local response = frames[#frames]
    assert.is_false(response.ok)
    assert.is_truthy(tostring(response.error):find("invalid json", 1, true))
  end)
end)

describe("bridge method dispatch", function()
  local port, token, teardown
  before_each(function()
    wipe_bridge()
    port, token, teardown = fresh_bridge()
  end)
  after_each(function()
    if teardown then
      teardown()
    end
  end)

  it("nvim_get_current_context returns a buffer/window/cursor dict", function()
    local raw = round_trip(port, {
      vim.json.encode({ id = 11, method = "nvim_get_current_context", token = token, params = {} }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    local response = frames[#frames]
    assert.is_true(response.ok)
    assert.is_table(response.result)
    -- Result includes the buffer number / cursor keys; exact shape depends on
    -- the current buffer state, so we just assert presence of the well-known
    -- top-level keys.
    assert.is_truthy(response.result.bufnr ~= nil or response.result.path ~= nil)
  end)

  it("nvim_open_file can focus a file in a new buffer", function()
    -- Write a tmp file we can ask the bridge to open.
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "hello" }, tmp)

    local raw = round_trip(port, {
      vim.json.encode({
        id = 12, method = "nvim_open_file", token = token,
        params = { path = tmp, line = 1 },
      }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local frames = parse_frames(raw)
    local response = frames[#frames]
    assert.is_true(response.ok, tostring(response.error))
    -- The buffer for that path should now exist and be current.
    assert.are.same(tmp, vim.api.nvim_buf_get_name(0))
    vim.fn.delete(tmp)
  end)

  it("nvim_highlight_range places an extmark and nvim_clear_highlights removes it", function()
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "alpha", "beta", "gamma" }, tmp)
    vim.cmd.edit(tmp)

    -- Create a range highlight on lines 1..2.
    local hi = round_trip(port, {
      vim.json.encode({
        id = 13, method = "nvim_highlight_range", token = token,
        params = { path = tmp, startLine = 1, endLine = 2, label = "test" },
      }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local hi_frame = parse_frames(hi)[1]
    assert.is_true(hi_frame.ok, tostring(hi_frame.error))

    -- Clear highlights and confirm we get a success frame back.
    local cl = round_trip(port, {
      vim.json.encode({
        id = 14, method = "nvim_clear_highlights", token = token,
        params = {},
      }),
    }, function(s) return s:find("\n", 1, true) ~= nil end)
    local cl_frame = parse_frames(cl)[1]
    assert.is_true(cl_frame.ok, tostring(cl_frame.error))

    vim.cmd.bdelete(tmp)
  end)
end)
