-- helpers/fake_pi.lua — minimal stand-in for `pi --mode rpc` used by rpc_spec.
--
-- Driven by a "behavior" file passed as argv[1]. Lines:
--   EVENT <json>   emit a frame on stdout (e.g. agent_start, message_update)
--   SLEEP <ms>     os.execute("sleep ...") so the test can interleave events
--   EXIT           terminate
--
-- After the directive stream completes, the fake stays alive and reads JSONL
-- from stdin. Each line is echoed back as a synthetic `response` frame whose
-- `id` is taken from the request. We do not implement a full JSON parser
-- here: we just regex out the `id` and `command` fields, which is enough for
-- rpc_spec to assert round-trip behavior.
--
-- Lua 5.5 ships on this box, so we prefer `load(...)` (and tolerate
-- `loadstring` on older interpreters) but we never feed it JSON.

local behavior = arg[1]
if not behavior then
  io.stderr:write("fake_pi: missing behavior file argv[1]\n")
  os.exit(2)
end

io.stdout:setvbuf("no")

local function emit(json_text)
  io.stdout:write(json_text .. "\n")
  io.stdout:flush()
end

-- Pull field values out of a JSON or Lua-ish object literal. Handles both
-- `"foo": "bar"` (JSON) and `"foo" = "bar"` (Lua). Returns the field value
-- in JSON-encoded form (quoted string, raw number, or `null`-equivalent) so the
-- caller can splat it straight into a response template.
local function field(line, key)
  local sval = line:match('"' .. key .. '"%s*[=:]%s*"([^"]*)"')
  if sval then
    -- JSON-encode: keep double-quotes, escape backslashes / control chars.
    return '"' .. sval:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  end
  local nval = line:match('"' .. key .. '"%s*[=:]%s*(%-?%d+%.?%d*)')
  if nval then
    return nval
  end
  return "null"
end

for line in io.lines(behavior) do
  local kind, payload = line:match("^(%S+)%s*(.*)$")
  if kind == "EVENT" then
    emit(payload)
  elseif kind == "SLEEP" then
    local ms = tonumber(payload) or 0
    if ms > 0 then os.execute(string.format("sleep %.3f", ms / 1000)) end
  elseif kind == "EXIT" then
    os.exit(0)
  end
end

for raw_line in io.lines() do
  local line = raw_line:gsub("\r$", "")
  if line ~= "" then
    local id = field(line, "id")
    -- Try `command` first (response-shaped requests), fall back to `type`
    -- (e.g. prompt messages). field() returns "null" when the key isn't
    -- present.
    local cmd = field(line, "command")
    if cmd == "null" then
      cmd = field(line, "type")
    end
    emit(string.format(
      '{"type":"response","id":%s,"command":%s,"success":true,"data":{}}',
      id, cmd
    ))
  end
end
