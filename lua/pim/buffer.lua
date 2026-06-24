local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  assistant_streaming = false,
  opts = {},
}

local function with_buffer_mutation(fn)
  local bufnr = M.ensure()
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  fn(bufnr)
  vim.bo[bufnr].modifiable = was_modifiable
end

local function scroll_to_bottom()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    local line_count = vim.api.nvim_buf_line_count(state.bufnr)
    vim.api.nvim_win_set_cursor(state.winid, { line_count, 0 })
  end
end

function M.setup(opts)
  state.opts = opts or {}
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

  return state.bufnr
end

function M.open()
  local bufnr = M.ensure()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    -- The window may have been reused by an agent-driven editor action.
    -- Always restore the pim conversation buffer before focusing it.
    if vim.api.nvim_win_get_buf(state.winid) ~= bufnr then
      vim.api.nvim_win_set_buf(state.winid, bufnr)
    end
    vim.api.nvim_set_current_win(state.winid)
    return bufnr
  end

  local width = state.opts.width or 80
  vim.cmd("botright vertical new")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, bufnr)
  vim.api.nvim_win_set_width(state.winid, width)
  vim.wo[state.winid].wrap = true
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
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
  end)
  scroll_to_bottom()
end

function M.append_line(line)
  state.assistant_streaming = false
  with_buffer_mutation(function(bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]
    local insert_at = (line_count == 1 and last == "") and 0 or line_count
    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { line })
  end)
  scroll_to_bottom()
end

function M.append_block(title, text)
  state.assistant_streaming = false
  local lines = vim.split(text or "", "\n", { plain = true })
  with_buffer_mutation(function(bufnr)
    local out = { "", "## " .. title }
    vim.list_extend(out, lines)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, out)
  end)
  scroll_to_bottom()
end

function M.start_assistant_message()
  if state.assistant_streaming then
    return
  end
  state.assistant_streaming = true
  with_buffer_mutation(function(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "## pi", "" })
  end)
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

return M
