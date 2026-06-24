local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  assistant_streaming = false,
  opts = {},
  message_namespace = nil,
  messages = {},
  status_namespace = nil,
  status_timer = nil,
  status_label = nil,
  status_hl = "Comment",
  spinner_index = 1,
}

local function with_buffer_mutation(fn)
  local bufnr = M.ensure()
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  local result = fn(bufnr)
  vim.bo[bufnr].modifiable = was_modifiable
  return result
end

local function scroll_to_bottom()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    local line_count = vim.api.nvim_buf_line_count(state.bufnr)
    vim.api.nvim_win_set_cursor(state.winid, { line_count, 0 })
  end
end

local function message_namespace()
  if not state.message_namespace then
    state.message_namespace = vim.api.nvim_create_namespace("pim-messages")
  end
  return state.message_namespace
end

local function role_for_title(title)
  local lower = tostring(title or ""):lower()
  if lower:match("^you") then
    return "user"
  end
  if lower == "pi" or lower:match("^pi%s") then
    return "assistant"
  end
  if lower:match("error") or lower:match("stderr") or lower:match("parse") then
    return "error"
  end
  if lower:match("tool") then
    return "tool"
  end
  return "system"
end

local function highlight_for_role(role)
  return ({
    user = "PimUserHeader",
    assistant = "PimAssistantHeader",
    tool = "PimToolHeader",
    muted = "PimMuted",
    error = "PimErrorHeader",
    system = "PimSystemHeader",
  })[role] or "PimSystemHeader"
end

local function add_message_mark(bufnr, line, role, title, opts)
  opts = opts or {}
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local row = math.max(0, line - 1)
  local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local ns = message_namespace()
  local id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
    end_row = row,
    end_col = math.max(0, #text),
    hl_group = highlight_for_role(role),
    priority = 120,
    right_gravity = false,
  })
  if opts.navigate ~= false then
    table.insert(state.messages, {
      id = id,
      role = role,
      title = title,
    })
  end
  return id
end

local function classify_line(line)
  if type(line) ~= "string" then
    return nil
  end

  local title = line:match("^##%s+(.+)$")
  if title then
    return role_for_title(title), title
  end

  local tool = line:match("^▶%s+tool:%s*(.+)$") or line:match("^■%s+tool%s+[%w%-]+:%s*(.+)$")
  if tool then
    return "tool", tool
  end

  if line:match("^%s+args:%s+") or line:match("^%s+command:%s+") or line:match("^%s+path:%s+") then
    return "muted", "tool detail"
  end

  return nil
end

local function clear_message_marks(bufnr)
  state.messages = {}
  if state.message_namespace and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, state.message_namespace, 0, -1)
  end
end

local function rebuild_message_marks(bufnr)
  clear_message_marks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local role, title = classify_line(line)
    if role then
      add_message_mark(bufnr, i, role, title, { navigate = role == "user" or role == "assistant" })
    end
  end
end

local function append_lines(lines)
  return with_buffer_mutation(function(bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]
    local insert_at = (line_count == 1 and last == "") and 0 or line_count
    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, lines)
    return insert_at + 1
  end)
end

local function current_message_entries()
  local bufnr = M.ensure()
  local ns = message_namespace()
  local entries = {}
  for _, message in ipairs(state.messages) do
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns, message.id, {})
    if ok and pos and #pos >= 2 then
      table.insert(entries, {
        line = pos[1] + 1,
        col = pos[2],
        role = message.role,
        title = message.title,
      })
    end
  end
  table.sort(entries, function(a, b)
    if a.line == b.line then
      return a.col < b.col
    end
    return a.line < b.line
  end)
  return entries
end

local function jump_to_line(line)
  local bufnr = M.ensure()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      vim.api.nvim_set_current_win(winid)
      vim.api.nvim_win_set_cursor(winid, { line, 0 })
      vim.cmd.normal({ args = { "zz" }, bang = true })
      return true
    end
  end
  M.open()
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd.normal({ args = { "zz" }, bang = true })
  return true
end

local function jump_message(direction)
  local bufnr = M.ensure()
  local entries = current_message_entries()
  if #entries == 0 then
    rebuild_message_marks(bufnr)
    entries = current_message_entries()
  end
  if #entries == 0 then
    return false
  end

  local current = 1
  if vim.api.nvim_get_current_buf() == bufnr then
    current = vim.api.nvim_win_get_cursor(0)[1]
  end

  if direction > 0 then
    for _, entry in ipairs(entries) do
      if entry.line > current then
        return jump_to_line(entry.line)
      end
    end
  else
    for i = #entries, 1, -1 do
      if entries[i].line < current then
        return jump_to_line(entries[i].line)
      end
    end
  end

  return false
end

local function set_default_keymaps(bufnr)
  if state.opts.default_keymaps == false then
    return
  end
  vim.keymap.set("n", "<leader>j", function()
    M.next_message()
  end, { buffer = bufnr, silent = true, desc = "pim next message" })
  vim.keymap.set("n", "<leader>k", function()
    M.prev_message()
  end, { buffer = bufnr, silent = true, desc = "pim previous message" })
end

local function apply_window_options(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].wrap = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
end

local function set_window_autocmds(bufnr)
  local group = vim.api.nvim_create_augroup("pim-buffer-window-options", { clear = false })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function(args)
      for _, winid in ipairs(vim.fn.win_findbuf(args.buf)) do
        apply_window_options(winid)
      end
    end,
    desc = "Keep pim conversation window options readable",
  })
end

local function update_status_extmark(text, hl)
  local bufnr = M.ensure()
  if not state.status_namespace then
    state.status_namespace = vim.api.nvim_create_namespace("pim-status")
  end
  vim.api.nvim_buf_clear_namespace(bufnr, state.status_namespace, 0, -1)
  if not text or text == "" then
    return
  end
  vim.api.nvim_buf_set_extmark(bufnr, state.status_namespace, 0, 0, {
    virt_text = { { text, hl or "Comment" } },
    virt_text_pos = "right_align",
    priority = 200,
  })
end

local function stop_status_timer()
  if state.status_timer then
    state.status_timer:stop()
    state.status_timer:close()
    state.status_timer = nil
  end
end

local function start_status_spinner(label, hl)
  stop_status_timer()
  state.status_label = label
  state.status_hl = hl or "WarningMsg"
  state.spinner_index = 1
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local function tick()
    local frame = frames[state.spinner_index]
    state.spinner_index = (state.spinner_index % #frames) + 1
    update_status_extmark(frame .. " " .. state.status_label, state.status_hl)
  end
  tick()
  state.status_timer = (vim.uv or vim.loop).new_timer()
  state.status_timer:start(120, 120, vim.schedule_wrap(tick))
end

local function setup_highlights()
  local defaults = {
    PimHighlight = { link = "CursorLine", default = true },
    PimUserHeader = { fg = "#268bd2", ctermfg = "Blue", bold = true, default = true },
    PimAssistantHeader = { fg = "#6c71c4", ctermfg = "Magenta", bold = true, default = true },
    PimToolHeader = { link = "Type", default = true },
    PimErrorHeader = { link = "ErrorMsg", default = true },
    PimSystemHeader = { link = "Comment", default = true },
    PimMuted = { link = "Comment", default = true },
    PimStatusWorking = { link = "DiagnosticWarn", default = true },
    PimStatusIdle = { link = "Comment", default = true },
  }

  for group, spec in pairs(defaults) do
    local user_spec = state.opts.highlights and state.opts.highlights[group]
    vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", spec, user_spec or {}))
  end
end

function M.setup(opts)
  state.opts = opts or {}
  setup_highlights()
end

function M.ensure()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    return state.bufnr
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.bufnr, "pim://conversation")
  vim.bo[state.bufnr].buftype = "nofile"
  vim.bo[state.bufnr].bufhidden = "hide"
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].filetype = "pim"
  vim.bo[state.bufnr].modifiable = false

  set_default_keymaps(state.bufnr)
  set_window_autocmds(state.bufnr)

  return state.bufnr
end

function M.open(opts)
  opts = opts or {}
  local focus = opts.focus ~= false
  local previous_win = vim.api.nvim_get_current_win()
  local bufnr = M.ensure()

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    -- The window may have been reused by an agent-driven editor action.
    -- Always restore the pim conversation buffer before optionally focusing it.
    if vim.api.nvim_win_get_buf(state.winid) ~= bufnr then
      vim.api.nvim_win_set_buf(state.winid, bufnr)
    end
    apply_window_options(state.winid)
    if focus then
      vim.api.nvim_set_current_win(state.winid)
    end
    return bufnr
  end

  local width = state.opts.width or 80
  vim.cmd("botright vertical new")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, bufnr)
  vim.api.nvim_win_set_width(state.winid, width)
  apply_window_options(state.winid)

  if not focus and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end

  return bufnr
end

function M.close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

function M.toggle()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    M.close()
  else
    M.open()
  end
end

function M.set_lines(lines)
  with_buffer_mutation(function(bufnr)
    if not lines or #lines == 0 then
      lines = { "" }
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    rebuild_message_marks(bufnr)
  end)
  scroll_to_bottom()
end

function M.append_line(line)
  state.assistant_streaming = false
  local start_line = append_lines({ line })
  local bufnr = M.ensure()
  local role, title = classify_line(line)
  if role then
    add_message_mark(bufnr, start_line, role, title, { navigate = role == "user" or role == "assistant" })
  end
  scroll_to_bottom()
end

function M.append_block(title, text)
  state.assistant_streaming = false
  local lines = vim.split(text or "", "\n", { plain = true })
  local out = { "", "## " .. title }
  vim.list_extend(out, lines)
  local start_line = append_lines(out)
  local role = role_for_title(title)
  add_message_mark(M.ensure(), start_line + 1, role, title, { navigate = role == "user" or role == "assistant" })
  scroll_to_bottom()
end

function M.start_assistant_message()
  if state.assistant_streaming then
    return
  end
  state.assistant_streaming = true
  local start_line = append_lines({ "", "## pi", "" })
  add_message_mark(M.ensure(), start_line + 1, "assistant", "pi", { navigate = true })
  scroll_to_bottom()
end

function M.append_delta(delta)
  if not delta or delta == "" then
    return
  end
  M.start_assistant_message()
  with_buffer_mutation(function(bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
    local parts = vim.split(delta, "\n", { plain = true })
    if #parts == 1 then
      vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { last .. parts[1] })
      return
    end

    local replacement = { last .. parts[1] }
    for i = 2, #parts do
      table.insert(replacement, parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, replacement)
  end)
  scroll_to_bottom()
end

function M.finish_assistant_message()
  state.assistant_streaming = false
end

function M.set_status(label, hl)
  stop_status_timer()
  state.status_label = label
  state.status_hl = hl or "Comment"
  update_status_extmark(label, state.status_hl)
end

function M.start_working(label)
  start_status_spinner(label or "pi working…", "PimStatusWorking")
end

function M.stop_working(label)
  M.set_status(label or "pi idle", "PimStatusIdle")
end

function M.next_message()
  jump_message(1)
end

function M.prev_message()
  jump_message(-1)
end

function M.latest()
  local bufnr = M.ensure()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  jump_to_line(line_count)
end

return M
