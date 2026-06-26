local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  origin_winid = nil,
  on_submit = nil,
}

local function trim_lines(lines)
  local first = 1
  local last = #lines
  while first <= last and lines[first]:match("^%s*$") do
    first = first + 1
  end
  while last >= first and lines[last]:match("^%s*$") do
    last = last - 1
  end
  local out = {}
  for i = first, last do
    table.insert(out, lines[i])
  end
  return out
end

local function close_window()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
  state.bufnr = nil
end

local function restore_origin()
  if state.origin_winid and vim.api.nvim_win_is_valid(state.origin_winid) then
    vim.api.nvim_set_current_win(state.origin_winid)
  end
  state.origin_winid = nil
end

function M.cancel()
  close_window()
  restore_origin()
end

function M.submit()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local lines = trim_lines(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false))
  local text = table.concat(lines, "\n")
  local on_submit = state.on_submit

  close_window()
  restore_origin()

  if text ~= "" and on_submit then
    on_submit(text)
  end
end

local function set_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    M.submit()
  end, vim.tbl_extend("force", opts, { desc = "pim submit composer" }))
  vim.keymap.set("n", "<leader>s", function()
    M.submit()
  end, vim.tbl_extend("force", opts, { desc = "pim submit composer" }))
  vim.keymap.set("n", "q", function()
    M.cancel()
  end, vim.tbl_extend("force", opts, { desc = "pim cancel composer" }))
end

function M.open(opts)
  opts = opts or {}

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return state.bufnr
  end

  state.origin_winid = vim.api.nvim_get_current_win()
  state.on_submit = opts.on_submit

  local width = opts.width or math.min(96, math.max(50, math.floor(vim.o.columns * 0.7)))
  local height = opts.height or math.min(18, math.max(8, math.floor(vim.o.lines * 0.35)))
  local row = math.max(0, math.floor((vim.o.lines - height) / 3))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local bufnr = vim.api.nvim_create_buf(false, true)
  state.bufnr = bufnr
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = opts.filetype or "markdown"
  vim.bo[bufnr].modifiable = true

  local initial = opts.initial_lines or opts.initial or { "" }
  if type(initial) == "string" then
    initial = vim.split(initial, "\n", { plain = true })
  end
  if #initial == 0 then
    initial = { "" }
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial)

  state.winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or "pim compose") .. " ",
    title_pos = "center",
  })

  vim.wo[state.winid].wrap = true
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].signcolumn = "no"

  set_keymaps(bufnr)
  vim.cmd.startinsert()
  return bufnr
end

return M
