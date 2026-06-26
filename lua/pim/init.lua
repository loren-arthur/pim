local bridge = require("pim.bridge")
local buffer = require("pim.buffer")
local composer = require("pim.composer")
local context = require("pim.context")
local rpc = require("pim.rpc")
local settings_editor = require("pim.settings_editor")
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
    -- Default keymaps under a prefix. Set `keymaps = false` to disable, or
    -- override `keymaps.prefix`.
    keymaps = {
      prefix = "<leader>p",
    },
    -- By default, pim remembers the last session file for each cwd and resumes
    -- that exact file on the next open, unless pi_cmd already contains an
    -- explicit session choice like --session, --continue, --resume, or
    --no-session.
    session = {
      resume = "workspace",
    },
  },
  is_streaming = false,
  session_id = nil,
  session_file = nil,
  pending_new_session_name = nil,
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

local function workspace_key()
  local cwd = vim.fn.getcwd()
  local ok, hashed = pcall(vim.fn.sha256, cwd)
  if ok and hashed and hashed ~= "" then
    return hashed
  end
  local sanitized = cwd:gsub("[^%w%._%-]+", "-"):gsub("%-+", "-")
  return sanitized ~= "" and sanitized or "unknown"
end

local function workspace_session_path()
  return vim.fn.stdpath("state") .. "/pim/workspaces/" .. workspace_key() .. ".json"
end

local function pi_session_dir_for_cwd()
  local agent_dir = vim.fn.expand(state.opts.pi_config_dir or "~/.pi/agent")
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("[/\\]$", "")
  local safe = "--" .. cwd:gsub("^[/\\]", ""):gsub("[/\\:]", "-") .. "--"
  return agent_dir .. "/sessions/" .. safe
end

local function read_workspace_session()
  local path = workspace_session_path()
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, content = pcall(function()
    return table.concat(vim.fn.readfile(path), "\n")
  end)
  if not ok or content == "" then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.json.decode, content)
  if not decoded_ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local function write_workspace_session(session)
  if not session or not session.sessionFile then
    return
  end
  local path = workspace_session_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local payload = {
    cwd = vim.fn.getcwd(),
    sessionFile = session.sessionFile,
    sessionId = session.sessionId,
    sessionName = session.sessionName,
    updatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  pcall(vim.fn.writefile, { vim.json.encode(payload) }, path)
end

local function pi_cmd_has_explicit_session_choice()
  local cmd = state.opts.pi_cmd or {}
  for _, arg in ipairs(cmd) do
    if arg == "--session" or arg == "--continue" or arg == "-c" or arg == "--resume" or arg == "-r"
      or arg == "--no-session" or arg == "--fork" then
      return true
    end
  end
  return false
end

local function startup_session_args()
  local session_opts = state.opts.session or {}
  if session_opts.resume == false or session_opts.resume == "none" then
    return {}
  end
  if pi_cmd_has_explicit_session_choice() then
    return {}
  end

  local saved = read_workspace_session()
  if saved and saved.sessionFile and vim.fn.filereadable(saved.sessionFile) == 1 then
    state.workspace_session_file = saved.sessionFile
    return { "--session", saved.sessionFile }
  end
  return {}
end

local function first_user_text(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  for _ = 1, 80 do
    local line = file:read("*l")
    if not line then
      break
    end
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == "table" and entry.type == "message" and entry.message and entry.message.role == "user" then
      local content = entry.message.content
      if type(content) == "table" then
        for _, item in ipairs(content) do
          if type(item) == "table" and item.type == "text" and item.text then
            file:close()
            return item.text:gsub("\n", " ")
          end
        end
      end
    end
  end
  file:close()
  return nil
end

local function session_summary(path)
  local session = {}
  local file = io.open(path, "r")
  if file then
    local first = file:read("*l")
    file:close()
    if first then
      local ok, entry = pcall(vim.json.decode, first)
      if ok and type(entry) == "table" then
        session.id = entry.id
        session.timestamp = entry.timestamp
      end
    end
  end
  session.path = path
  session.mtime = vim.fn.getftime(path)
  session.preview = first_user_text(path)
  return session
end

local function workspace_sessions(limit)
  limit = limit or 20
  local dir = pi_session_dir_for_cwd()
  local files = vim.fn.globpath(dir, "*.jsonl", false, true)
  table.sort(files, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)
  local out = {}
  for _, path in ipairs(files) do
    table.insert(out, session_summary(path))
    if #out >= limit then
      break
    end
  end
  return out
end

local function format_session_choice(session)
  local when = session.timestamp or os.date("%Y-%m-%d %H:%M", session.mtime)
  local name = session.preview or session.id or vim.fn.fnamemodify(session.path, ":t")
  if #name > 80 then
    name = name:sub(1, 79) .. "…"
  end
  return when .. "  " .. name
end

local function default_session_name()
  local base = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  if base == "" then
    base = "pim"
  end
  return string.format("%s %s", base, os.date("%Y-%m-%d %H:%M"))
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
  state.session_file = data.sessionFile
  state.session_name = data.sessionName
  write_workspace_session(data)
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

  if event.type == "response" and event.command == "new_session" and event.success then
    local cancelled = event.data and event.data.cancelled
    if cancelled then
      buffer.append_line("pim new session cancelled")
      state.pending_new_session_name = nil
      rpc.get_state()
      return
    end

    buffer.append_line("pim started a fresh pi session")
    if state.pending_new_session_name and state.pending_new_session_name ~= "" then
      rpc.set_session_name(state.pending_new_session_name)
    end
    state.pending_new_session_name = nil
    rpc.get_state()
    return
  end

  if event.type == "response" and event.command == "set_session_name" and event.success then
    rpc.get_state()
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
      -- Surface model/provider errors (e.g. a 400) instead of going silently
      -- idle with an empty assistant message.
      local err = event.message.errorMessage
      if (err and err ~= "") or event.message.stopReason == "error" then
        local detail = err or "model returned an error"
        local model = event.message.model and (" [" .. tostring(event.message.model) .. "]") or ""
        buffer.append_block("pi error" .. model, detail)
        transcript.append_block("pi error" .. model, detail)
      end
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

-- Global keymaps under a configurable prefix (default `<leader>p`). Disabled by
-- `keymaps = false`.
local function apply_keymaps(cfg)
  if not cfg then
    return
  end
  local prefix = (type(cfg) == "table" and cfg.prefix) or "<leader>p"
  local function map(mode, suffix, rhs, desc)
    vim.keymap.set(mode, prefix .. suffix, rhs, { desc = "pim: " .. desc, silent = true })
  end

  map("n", "p", function() M.toggle() end, "toggle conversation pane")
  map("n", "s", function() M.send() end, "send a prompt")
  map("x", "s", ":PimSendSelection<CR>", "send selection")
  map("n", "c", function() M.compose() end, "compose prompt")
  map("x", "c", ":PimComposeSelection<CR>", "compose with selection")
  map("n", "S", function() M.steer() end, "steer")
  map("n", "f", function() M.follow_up() end, "follow up")
  map("n", "m", function() M.pick_model() end, "pick model")
  map("n", "r", function() M.reload() end, "reload pi")
  map("n", "a", function() M.abort() end, "abort")
  map("n", "x", function() M.stop() end, "stop pi")
  map("n", "t", function() M.open_transcript() end, "open transcript")
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
  apply_keymaps(state.opts.keymaps)
end

local function open_with_args(args)
  buffer.open()
  rpc.start(args)
  rpc.get_state()
end

function M.open_select()
  buffer.open()
  if rpc.is_running() then
    M.session_info()
    return
  end

  local choices = {}
  local pinned = read_workspace_session()
  if pinned and pinned.sessionFile and vim.fn.filereadable(pinned.sessionFile) == 1 then
    table.insert(choices, {
      kind = "session",
      path = pinned.sessionFile,
      label = "● pinned workspace session  " .. (pinned.sessionName or pinned.sessionId or vim.fn.fnamemodify(pinned.sessionFile, ":t")),
    })
  end

  table.insert(choices, { kind = "fresh", label = "+ start fresh session" })
  for _, session in ipairs(workspace_sessions(15)) do
    local already_pinned = pinned and pinned.sessionFile == session.path
    if not already_pinned then
      table.insert(choices, {
        kind = "session",
        path = session.path,
        label = "  " .. format_session_choice(session),
      })
    end
  end

  vim.ui.select(choices, {
    prompt = "pim: choose session for " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice.kind == "fresh" then
      M.open_fresh()
      return
    end
    open_with_args({ "--session", choice.path })
  end)
end

function M.open()
  local session_opts = state.opts.session or {}
  if session_opts.on_open == "select" and not rpc.is_running() and not pi_cmd_has_explicit_session_choice() then
    M.open_select()
    return
  end
  open_with_args(startup_session_args())
end

function M.new_session(name)
  buffer.open({ focus = false })
  if not name or name == "" then
    name = default_session_name()
  end
  state.pending_new_session_name = name
  buffer.append_line("pim starting a fresh pi session…")
  transcript.append_markdown("\npim starting a fresh pi session…\n")
  rpc.new_session(state.session_file)
end

function M.open_fresh(name)
  buffer.open()
  rpc.start()
  rpc.get_state()
  M.new_session(name)
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

function M.compose(opts)
  opts = opts or {}
  composer.open({
    title = opts.title or "pim compose — <C-s> submit, q cancel",
    initial = opts.initial,
    on_submit = function(text)
      send_prompt_with_behavior(text, opts.behavior or (state.is_streaming and state.opts.streaming_behavior or nil))
    end,
  })
end

function M.compose_selection(opts)
  opts = opts or {}
  local ctx = context.range({ line1 = opts.line1, line2 = opts.line2 })
  composer.open({
    title = opts.title or "pim selection comment — <C-s> submit, q cancel",
    on_submit = function(comment)
      local prompt = context.prompt_for_range(comment, ctx)
      send_prompt_with_behavior(prompt, state.is_streaming and state.opts.streaming_behavior or nil)
    end,
  })
end

function M.send(message)
  if not message or message == "" then
    M.compose()
    return
  end

  send_prompt_with_behavior(message, state.is_streaming and state.opts.streaming_behavior or nil)
end

function M.steer(message)
  if not message or message == "" then
    M.compose({ title = "pim steer — <C-s> submit, q cancel", behavior = "steer" })
    return
  end
  send_prompt_with_behavior(message, "steer")
end

function M.follow_up(message)
  if not message or message == "" then
    M.compose({ title = "pim follow-up — <C-s> submit, q cancel", behavior = "followUp" })
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

  M.compose_selection({ line1 = opts.line1, line2 = opts.line2 })
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

function M.session_info()
  local saved = read_workspace_session()
  local lines = {
    "Current pi session:",
    "  name: " .. tostring(state.session_name or ""),
    "  id: " .. tostring(state.session_id or ""),
    "  file: " .. tostring(state.session_file or ""),
    "Workspace pinned session:",
    "  file: " .. tostring(saved and saved.sessionFile or ""),
    "  name: " .. tostring(saved and saved.sessionName or ""),
  }
  local text = table.concat(lines, "\n")
  buffer.append_block("pim session", text)
  vim.notify(text, vim.log.levels.INFO, { title = "pim session" })
end

function M.forget_workspace_session()
  local path = workspace_session_path()
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
  state.workspace_session_file = nil
  vim.notify("forgot pim workspace session", vim.log.levels.INFO, { title = "pim" })
end

function M.open_transcript()
  local paths = transcript.paths()
  vim.cmd.edit(vim.fn.fnameescape(paths.markdown))
end

local function pi_config_dir()
  return vim.fn.expand(state.opts.pi_config_dir or "~/.pi/agent")
end

-- Collect available models from pi's models.json as rich entries
-- ({provider, id, key="provider/id", label}).
local function model_entries(models_path)
  local read_ok, content = pcall(function()
    return table.concat(vim.fn.readfile(models_path), "\n")
  end)
  if not read_ok then
    return {}
  end
  local decode_ok, decoded = pcall(vim.json.decode, content)
  if not decode_ok or type(decoded) ~= "table" or type(decoded.providers) ~= "table" then
    return {}
  end
  local out = {}
  for provider, pdata in pairs(decoded.providers) do
    if type(pdata) == "table" and type(pdata.models) == "table" then
      for _, model in ipairs(pdata.models) do
        if type(model) == "table" and model.id then
          local key = provider .. "/" .. tostring(model.id)
          local label = key
          if model.name then
            label = label .. "  (" .. tostring(model.name) .. ")"
          end
          table.insert(out, {
            provider = provider,
            id = tostring(model.id),
            key = key,
            label = label,
          })
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

local function available_models(models_path)
  return vim.tbl_map(function(entry)
    return entry.key
  end, model_entries(models_path))
end

-- Open pi's settings, jump to the model fields, and surface the valid values.
function M.edit_model_config()
  local dir = pi_config_dir()
  local settings = dir .. "/settings.json"
  if vim.fn.filereadable(settings) == 0 then
    vim.notify("pi settings not found at " .. settings, vim.log.levels.WARN, { title = "pim" })
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(settings))
  vim.fn.cursor(1, 1)
  if vim.fn.search([["defaultModel"]], "cw") == 0 then
    vim.fn.search([["defaultProvider"]], "cw")
  end

  local hint = 'Edit "defaultProvider" / "defaultModel", then :PimReload to apply.'
  local models = available_models(dir .. "/models.json")
  if #models > 0 then
    hint = hint .. "\nAvailable: " .. table.concat(models, ", ")
  end
  vim.notify(hint, vim.log.levels.INFO, { title = "pim" })
end

local function settings_table()
  local read_ok, content = pcall(function()
    return table.concat(vim.fn.readfile(pi_config_dir() .. "/settings.json"), "\n")
  end)
  if not read_ok then
    return {}
  end
  local decode_ok, settings = pcall(vim.json.decode, content)
  if not decode_ok or type(settings) ~= "table" then
    return {}
  end
  return settings
end

-- Restart pi so configuration/model changes take effect. The current provider
-- and model are read from settings and passed explicitly so a resumed session
-- actually adopts the new model rather than keeping its old one; the session is
-- resumed so the conversation is preserved.
function M.reload()
  local args = {}
  local settings = settings_table()
  if settings.defaultProvider then
    vim.list_extend(args, { "--provider", tostring(settings.defaultProvider) })
  end
  if settings.defaultModel then
    vim.list_extend(args, { "--model", tostring(settings.defaultModel) })
  end
  if settings.defaultThinkingLevel then
    vim.list_extend(args, { "--thinking", tostring(settings.defaultThinkingLevel) })
  end
  if state.session_file then
    vim.list_extend(args, { "--session", tostring(state.session_file) })
  end

  buffer.open({ focus = false })
  local applied = settings.defaultModel and (" → " .. tostring(settings.defaultModel)) or ""
  buffer.append_line("↻ reloading pi" .. applied .. "…")
  transcript.append_markdown("\n↻ reloading pi" .. applied .. "…\n")

  rpc.stop()
  -- Surface that we are actively waiting for the old process to release the
  -- session file and for the new one to come up, instead of leaving the
  -- previous "pi working…" spinner stale across the gap.
  buffer.start_working("reloading pi" .. applied .. "…")
  state.is_streaming = false
  state.assistant_open_in_transcript = false

  -- Let the old process exit and release the session file before resuming it.
  vim.defer_fn(function()
    rpc.start(args)
    rpc.get_state()
  end, 200)
end

-- Forward to the in-place editor module so tests can call it directly
-- without going through the public API; behavior and tests live in
-- lua/pim/settings_editor.lua.
local update_string_setting = settings_editor.update_string_setting
local insert_string_setting = settings_editor.insert_string_setting

-- Persist a provider/model choice to pi's settings and reload so it takes
-- effect. Edits the file in-place so unrelated formatting (nested objects,
-- key ordering, indentation) is preserved.
function M.set_model(provider, model)
  local path = pi_config_dir() .. "/settings.json"
  local read_ok, content = pcall(function()
    return table.concat(vim.fn.readfile(path), "\n")
  end)
  if not read_ok then
    vim.notify("pim: failed to read " .. path, vim.log.levels.ERROR, { title = "pim" })
    return
  end

  local updated = content
  local p_found
  updated, p_found = update_string_setting(updated, "defaultProvider", provider)
  if not p_found then
    updated, _ = insert_string_setting(updated, "defaultProvider", provider)
  end
  local m_found
  updated, m_found = update_string_setting(updated, "defaultModel", model)
  if not m_found then
    updated, _ = insert_string_setting(updated, "defaultModel", model)
  end

  local write_ok = pcall(vim.fn.writefile, vim.split(updated, "\n"), path)
  if not write_ok then
    vim.notify("pim: failed to write " .. path, vim.log.levels.ERROR, { title = "pim" })
    return
  end
  vim.notify(
    "pi model → " .. provider .. "/" .. model .. " (reloading…)",
    vim.log.levels.INFO,
    { title = "pim" }
  )
  M.reload()
end

-- Interactive model picker. Uses vim.ui.select, so it respects telescope/fzf/
-- snacks if the user has themed it; the current model is marked.
function M.pick_model()
  local entries = model_entries(pi_config_dir() .. "/models.json")
  if #entries == 0 then
    vim.notify(
      "pim: no models found in " .. pi_config_dir() .. "/models.json",
      vim.log.levels.WARN,
      { title = "pim" }
    )
    return
  end

  local settings = settings_table()
  local current
  if settings.defaultProvider and settings.defaultModel then
    current = settings.defaultProvider .. "/" .. settings.defaultModel
  end

  vim.ui.select(entries, {
    prompt = "pim: select pi model",
    format_item = function(entry)
      local marker = entry.key == current and "● " or "  "
      return marker .. entry.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice.key == current then
      vim.notify("pi model unchanged (" .. choice.key .. ")", vim.log.levels.INFO, { title = "pim" })
      return
    end
    M.set_model(choice.provider, choice.id)
  end)
end

return M
