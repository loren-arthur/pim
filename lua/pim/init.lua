local bridge = require("pim.bridge")
local buffer = require("pim.buffer")
local context = require("pim.context")
local rpc = require("pim.rpc")
local transcript = require("pim.transcript")

local M = {}

local state = {
  opts = {
    pi_cmd = { "pi", "--mode", "rpc" },
    pane = {
      width = 80,
    },
    -- When pi is already processing, queue new user input as a steering
    -- message by default. Pi RPC requires an explicit streamingBehavior in
    -- this state; without it, it returns "Agent is already processing".
    streaming_behavior = "steer",
  },
  is_streaming = false,
  session_id = nil,
  assistant_open_in_transcript = false,
}

local function plugin_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return source:gsub("/lua/pim/init%.lua$", "")
end

local function list_contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then
      return true
    end
  end
  return false
end

local function merge_opts(opts)
  state.opts = vim.tbl_deep_extend("force", state.opts, opts or {})
end

local function prepare_bridge()
  if state.opts.bridge and state.opts.bridge.enabled == false then
    return
  end

  local bridge_opts = vim.tbl_deep_extend("force", {
    highlights = state.opts.highlights or {},
  }, state.opts.bridge or {})
  local info = bridge.setup(bridge_opts)
  if not info then
    return
  end

  state.opts.env = vim.tbl_extend("force", state.opts.env or {}, {
    PIM_NVIM_BRIDGE_PORT = tostring(info.port),
    PIM_NVIM_BRIDGE_TOKEN = tostring(info.token),
  })

  if not (state.opts.bridge and state.opts.bridge.auto_extension == false) then
    local extension_path = plugin_root() .. "/pi/nvim-bridge.ts"
    if not list_contains(state.opts.pi_cmd, extension_path) then
      local next_cmd = vim.deepcopy(state.opts.pi_cmd)
      table.insert(next_cmd, "-e")
      table.insert(next_cmd, extension_path)
      state.opts.pi_cmd = next_cmd
    end
  end
end

local function render_session_state(data)
  if not data then
    return
  end
  local session_id = tostring(data.sessionId or data.sessionFile or "unknown")
  local changed = state.session_id ~= session_id
  state.session_id = session_id
  transcript.attach_session(data)
  if changed then
    local lines = transcript.read_markdown_lines()
    if #lines > 0 then
      buffer.set_lines(lines)
    end
    local line = string.format(
      "pim attached: session=%s file=%s",
      tostring(data.sessionId or "unknown"),
      tostring(data.sessionFile or "unknown")
    )
    buffer.append_line(line)
    transcript.append_markdown("\n\n<!-- " .. line .. " -->\n")
  end
end

local function truncate(text, max_len)
  text = tostring(text or "")
  max_len = max_len or 220
  text = text:gsub("\n", "\\n")
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 1) .. "…"
end

local function json_compact(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if ok then
    return encoded
  end
  return tostring(value)
end

local function tool_arg_lines(tool_name, args)
  if type(args) ~= "table" then
    if args == nil then
      return {}
    end
    return { "  args: " .. truncate(json_compact(args)) }
  end

  if tool_name == "bash" and args.command then
    return { "  command: " .. truncate(args.command, 300) }
  end

  if (tool_name == "read" or tool_name == "write" or tool_name == "edit") and args.path then
    return { "  path: " .. truncate(args.path) }
  end

  if tool_name == "nvim_open_file" and args.path then
    local location = args.path
    if args.line then
      location = location .. ":" .. tostring(args.line)
    end
    return { "  path: " .. truncate(location) }
  end

  if tool_name == "nvim_highlight_range" then
    local target = args.path or "current buffer"
    if args.startLine then
      target = target .. ":" .. tostring(args.startLine)
      if args.endLine and args.endLine ~= args.startLine then
        target = target .. "-" .. tostring(args.endLine)
      end
    end
    return { "  range: " .. truncate(target) }
  end

  if tool_name == "nvim_open_terminal" and args.cmd then
    return { "  command: " .. truncate(args.cmd, 300) }
  end

  return { "  args: " .. truncate(json_compact(args), 300) }
end

local function tool_display_lines(prefix, tool_name, args)
  local lines = { string.format("%s tool: %s", prefix, tool_name or "?") }
  vim.list_extend(lines, tool_arg_lines(tool_name, args))
  return lines
end

local function result_text(result)
  if type(result) ~= "table" then
    return result ~= nil and tostring(result) or nil
  end
  if type(result.content) == "table" then
    for _, item in ipairs(result.content) do
      if type(item) == "table" and item.type == "text" and item.text then
        return item.text
      end
    end
  end
  if result.details ~= nil then
    return json_compact(result.details)
  end
  return nil
end

local function tool_result_lines(event)
  local text = result_text(event.result)
  if not text or text == "" then
    return {}
  end
  local label = event.isError and "  error: " or "  result: "
  return { label .. truncate(text, 300) }
end

local function append_tool_lines(lines)
  for _, line in ipairs(lines) do
    buffer.append_line(line)
  end
  transcript.append_markdown("\n" .. table.concat(lines, "\n") .. "\n")
end

local function handle_event(event)
  transcript.append_event(event)

  if event.type == "response" and event.command == "get_state" and event.success then
    render_session_state(event.data)
    return
  end

  if event.type == "agent_start" then
    state.is_streaming = true
    buffer.start_working("pi working…")
    return
  end

  if event.type == "agent_end" then
    state.is_streaming = false
    state.assistant_open_in_transcript = false
    buffer.finish_assistant_message()
    buffer.stop_working("pi idle")
    return
  end

  if event.type == "message_update" then
    local update = event.assistantMessageEvent or {}
    if update.type == "text_start" then
      state.assistant_open_in_transcript = true
      transcript.append_markdown("\n\n## pi\n\n")
    elseif update.type == "text_delta" then
      if not state.assistant_open_in_transcript then
        state.assistant_open_in_transcript = true
        transcript.append_markdown("\n\n## pi\n\n")
      end
      buffer.append_delta(update.delta)
      transcript.append_markdown(update.delta or "")
    elseif update.type == "thinking_delta" and state.opts.show_thinking then
      if not state.assistant_open_in_transcript then
        state.assistant_open_in_transcript = true
        transcript.append_markdown("\n\n## pi\n\n")
      end
      buffer.append_delta(update.delta)
      transcript.append_markdown(update.delta or "")
    end
    return
  end

  if event.type == "message_end" then
    if event.message and event.message.role == "assistant" then
      state.assistant_open_in_transcript = false
      buffer.finish_assistant_message()
    end
    return
  end

  if event.type == "tool_execution_start" then
    local tool_name = event.toolName or "?"
    buffer.start_working("pi running tool: " .. tool_name)
    append_tool_lines(tool_display_lines("▶", tool_name, event.args))
    return
  end

  if event.type == "tool_execution_end" then
    local status = event.isError and "failed" or "done"
    local lines = { string.format("■ tool %s: %s", status, event.toolName or "?") }
    vim.list_extend(lines, tool_result_lines(event))
    append_tool_lines(lines)
    if state.is_streaming then
      buffer.start_working("pi working…")
    end
    return
  end

  if event.type == "response" and event.success == false then
    buffer.append_block("pim error", event.error or "RPC command failed")
    return
  end

  if event.type == "pim_stderr" then
    buffer.append_block("pi stderr", event.text or "")
    return
  end

  if event.type == "pim_parse_error" then
    buffer.append_block("pim parse error", (event.error or "") .. "\n" .. (event.line or ""))
    return
  end

  if event.type == "pim_exit" then
    local line = string.format("pi RPC exited: code=%s signal=%s", tostring(event.code), tostring(event.signal))
    buffer.append_line(line)
    transcript.append_markdown("\n" .. line .. "\n")
  end
end

function M.setup(opts)
  merge_opts(opts)
  prepare_bridge()
  buffer.setup(vim.tbl_extend("force", state.opts.pane or {}, {
    highlights = state.opts.highlights or {},
  }))
  transcript.setup(state.opts.transcript or {})
  rpc.setup({
    pi_cmd = state.opts.pi_cmd,
    env = state.opts.env,
    on_event = handle_event,
  })
end

function M.open()
  buffer.open()
  rpc.start()
  rpc.get_state()
end

function M.close()
  buffer.close()
end

function M.toggle()
  buffer.toggle()
end

function M.stop()
  rpc.stop()
end

function M.abort()
  buffer.append_line("↯ abort requested")
  transcript.append_markdown("\n↯ abort requested\n")
  rpc.abort()
end

local function send_prompt_with_behavior(message, behavior)
  buffer.open({ focus = false })
  local label = behavior and ("you [" .. behavior .. "]") or "you"
  buffer.append_block(label, message)
  transcript.append_block(label, message)

  if behavior == "steer" then
    rpc.steer(message)
  elseif behavior == "followUp" then
    rpc.follow_up(message)
  else
    rpc.prompt(message, state.is_streaming and state.opts.streaming_behavior or nil)
  end
end

function M.send(message)
  if not message or message == "" then
    vim.ui.input({ prompt = "pim> " }, function(input)
      if input and input ~= "" then
        M.send(input)
      end
    end)
    return
  end

  send_prompt_with_behavior(message, state.is_streaming and state.opts.streaming_behavior or nil)
end

function M.steer(message)
  if not message or message == "" then
    vim.ui.input({ prompt = "pim steer> " }, function(input)
      if input and input ~= "" then
        M.steer(input)
      end
    end)
    return
  end
  send_prompt_with_behavior(message, "steer")
end

function M.follow_up(message)
  if not message or message == "" then
    vim.ui.input({ prompt = "pim follow-up> " }, function(input)
      if input and input ~= "" then
        M.follow_up(input)
      end
    end)
    return
  end
  send_prompt_with_behavior(message, "followUp")
end

function M.send_selection(opts)
  opts = opts or {}
  local ctx = context.range({ line1 = opts.line1, line2 = opts.line2 })

  local function submit(comment)
    local prompt = context.prompt_for_range(comment, ctx)
    send_prompt_with_behavior(prompt, state.is_streaming and state.opts.streaming_behavior or nil)
  end

  if opts.comment and opts.comment ~= "" then
    submit(opts.comment)
    return
  end

  vim.ui.input({ prompt = "pim comment for selection> " }, function(input)
    submit(input or "")
  end)
end

function M.send_buffer(comment)
  local ctx = context.current_buffer()
  local prompt = context.prompt_for_range(comment, ctx)
  send_prompt_with_behavior(prompt, state.is_streaming and state.opts.streaming_behavior or nil)
end

function M.transcript_paths()
  return transcript.paths()
end

function M.bridge_info()
  return bridge.info()
end

function M.clear_highlights()
  bridge.clear_highlights()
end

function M.next_message()
  buffer.next_message()
end

function M.prev_message()
  buffer.prev_message()
end

function M.latest()
  buffer.latest()
end

function M.open_transcript()
  local paths = transcript.paths()
  vim.cmd.edit(vim.fn.fnameescape(paths.markdown))
end

return M
