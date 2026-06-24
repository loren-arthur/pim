local M = {}

local state = {
  server = nil,
  port = nil,
  token = nil,
  namespace = nil,
  opts = {},
  highlight_marks = {},
}

local uv = vim.uv or vim.loop

local function json_response(id, ok, result_or_error)
  if ok then
    return vim.json.encode({ id = id, ok = true, result = result_or_error }) .. "\n"
  end
  return vim.json.encode({ id = id, ok = false, error = tostring(result_or_error) }) .. "\n"
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function find_buf_by_path(path)
  path = normalize_path(path)
  if not path then
    return nil
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and normalize_path(vim.api.nvim_buf_get_name(bufnr)) == path then
      return bufnr
    end
  end
  return nil
end

local function is_pim_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return vim.api.nvim_buf_get_name(bufnr) == "pim://conversation"
    or vim.bo[bufnr].filetype == "pim"
end

local function focus_non_pim_window_or_split()
  if not is_pim_buffer(vim.api.nvim_get_current_buf()) then
    return
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and not is_pim_buffer(vim.api.nvim_win_get_buf(winid)) then
      vim.api.nvim_set_current_win(winid)
      return
    end
  end

  -- If the only visible window is pim, split it; the next :edit will replace
  -- the new split while the original pim pane remains visible.
  vim.cmd.split()
end

local function open_file(params)
  params = params or {}
  local path = assert(params.path, "path is required")
  local mode = params.mode or "edit"
  local line = tonumber(params.line or params.lnum or 1) or 1
  local col = tonumber(params.col or 1) or 1

  if mode == "split" then
    vim.cmd.split()
  elseif mode == "vsplit" or mode == "vertical" then
    vim.cmd.vsplit()
  elseif mode == "tab" then
    vim.cmd.tabnew()
  elseif mode == "edit" then
    focus_non_pim_window_or_split()
  else
    error("unknown open mode: " .. tostring(mode))
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  line = math.max(1, math.min(line, line_count))
  col = math.max(0, col - 1)
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.cmd.normal({ args = { "zz" }, bang = true })

  return {
    bufnr = bufnr,
    path = vim.api.nvim_buf_get_name(bufnr),
    line = line,
    col = col + 1,
    winid = vim.api.nvim_get_current_win(),
  }
end

local function ensure_namespace()
  if not state.namespace then
    state.namespace = vim.api.nvim_create_namespace("pim-bridge")
  end
  return state.namespace
end

local function highlight_opts()
  return state.opts.highlights or {}
end

local function should_clear_before_new(params)
  if params.clearExisting ~= nil then
    return params.clearExisting ~= false
  end
  local opts = highlight_opts()
  if opts.clear_before_new ~= nil then
    return opts.clear_before_new ~= false
  end
  return true
end

local function should_show_virtual_text(params)
  if params.virtualText ~= nil then
    return params.virtualText ~= false
  end
  local opts = highlight_opts()
  if opts.virtual_text ~= nil then
    return opts.virtual_text ~= false
  end
  return true
end

local function highlight_label(params)
  if params.label ~= nil then
    return tostring(params.label)
  end
  local opts = highlight_opts()
  if opts.default_label ~= nil then
    return tostring(opts.default_label)
  end
  return "pi"
end

local function forget_marks_for_buffer(bufnr)
  local kept = {}
  for _, mark in ipairs(state.highlight_marks) do
    if mark.bufnr ~= bufnr then
      table.insert(kept, mark)
    end
  end
  state.highlight_marks = kept
end

local function highlight_range(params)
  params = params or {}
  local path = params.path
  local start_line = assert(tonumber(params.startLine or params.line or params.lnum), "startLine is required")
  local end_line = tonumber(params.endLine or start_line) or start_line
  local hl = params.hlGroup or "PimHighlight"

  local bufnr
  if path and path ~= "" then
    bufnr = find_buf_by_path(path)
    if not bufnr then
      local opened = open_file({ path = path, line = start_line, mode = params.openMode or "edit" })
      bufnr = opened.bufnr
    end
  else
    bufnr = vim.api.nvim_get_current_buf()
  end

  local ns = ensure_namespace()

  if should_clear_before_new(params) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    forget_marks_for_buffer(bufnr)
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(1, math.min(end_line, line_count))

  local label = highlight_label(params)
  local show_virtual_text = should_show_virtual_text(params) and label ~= ""
  local ids = {}
  for lnum = start_line, end_line do
    local opts = {
      line_hl_group = hl,
      hl_eol = true,
      priority = 150,
      right_gravity = false,
    }
    if show_virtual_text and lnum == start_line then
      opts.virt_text = { { "  " .. label, params.labelHlGroup or "PimMuted" } }
      opts.virt_text_pos = params.labelPosition or "eol"
    end
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, opts)
    table.insert(ids, id)
    table.insert(state.highlight_marks, {
      bufnr = bufnr,
      id = id,
      startLine = start_line,
      endLine = end_line,
      label = label,
    })
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      vim.api.nvim_win_set_cursor(winid, { start_line, 0 })
      break
    end
  end

  return {
    bufnr = bufnr,
    path = vim.api.nvim_buf_get_name(bufnr),
    startLine = start_line,
    endLine = end_line,
    namespace = ns,
    extmarks = ids,
    label = show_virtual_text and label or nil,
  }
end

local function clear_highlights(params)
  params = params or {}
  if not state.namespace then
    return { cleared = false }
  end
  local bufs = {}
  if params.path then
    local bufnr = find_buf_by_path(params.path)
    if bufnr then
      table.insert(bufs, bufnr)
    end
  else
    bufs = vim.api.nvim_list_bufs()
  end
  local cleared_buffers = 0
  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, state.namespace, 0, -1)
      forget_marks_for_buffer(bufnr)
      cleared_buffers = cleared_buffers + 1
    end
  end
  return { cleared = true, buffers = cleared_buffers }
end

local function open_terminal(params)
  params = params or {}
  local cmd = params.cmd or vim.o.shell
  local mode = params.mode or "split"
  if mode == "vsplit" or mode == "vertical" then
    vim.cmd.vsplit()
  elseif mode == "tab" then
    vim.cmd.tabnew()
  else
    vim.cmd.split()
  end
  if params.cwd and params.cwd ~= "" then
    vim.cmd.lcd(vim.fn.fnameescape(params.cwd))
  end
  vim.fn.termopen(cmd)
  vim.cmd.startinsert()
  return {
    bufnr = vim.api.nvim_get_current_buf(),
    winid = vim.api.nvim_get_current_win(),
    cmd = cmd,
  }
end

local function get_current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local diagnostics = vim.diagnostic.get(bufnr)
  local compact_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    table.insert(compact_diagnostics, {
      line = diagnostic.lnum + 1,
      col = diagnostic.col + 1,
      severity = diagnostic.severity,
      source = diagnostic.source,
      message = diagnostic.message,
    })
  end
  return {
    cwd = vim.fn.getcwd(),
    bufnr = bufnr,
    path = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    cursor = { line = cursor[1], col = cursor[2] + 1 },
    diagnostics = compact_diagnostics,
  }
end

local methods = {
  nvim_open_file = open_file,
  nvim_highlight_range = highlight_range,
  nvim_clear_highlights = clear_highlights,
  nvim_open_terminal = open_terminal,
  nvim_get_current_context = get_current_context,
}

local function dispatch(request, write)
  if request.token ~= state.token then
    write(json_response(request.id, false, "invalid bridge token"))
    return
  end
  local fn = methods[request.method]
  if not fn then
    write(json_response(request.id, false, "unknown bridge method: " .. tostring(request.method)))
    return
  end

  vim.schedule(function()
    local ok, result = pcall(fn, request.params or {})
    write(json_response(request.id, ok, result))
  end)
end

local function start_server()
  local server = assert(uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  assert(server:listen(64, function(err)
    if err then
      vim.schedule(function()
        vim.notify("pim bridge listen error: " .. tostring(err), vim.log.levels.ERROR, { title = "pim" })
      end)
      return
    end

    local client = assert(uv.new_tcp())
    server:accept(client)
    local pending = ""

    local function write(text)
      if client and not client:is_closing() then
        client:write(text)
      end
    end

    client:read_start(function(read_err, chunk)
      if read_err then
        if client and not client:is_closing() then
          client:close()
        end
        return
      end
      if not chunk then
        if client and not client:is_closing() then
          client:close()
        end
        return
      end
      pending = pending .. chunk
      while true do
        local idx = pending:find("\n", 1, true)
        if not idx then
          break
        end
        local line = pending:sub(1, idx - 1)
        pending = pending:sub(idx + 1)
        if line:sub(-1) == "\r" then
          line = line:sub(1, -2)
        end
        local ok, request = pcall(vim.json.decode, line)
        if not ok then
          write(json_response(nil, false, "invalid json: " .. tostring(request)))
        else
          dispatch(request, write)
        end
      end
    end)
  end))

  state.server = server
  local sock = server:getsockname()
  state.port = sock and sock.port
  if not state.port then
    error("failed to determine pim bridge port")
  end
end

function M.setup(opts)
  opts = opts or {}
  state.opts = opts
  if opts.enabled == false then
    return nil
  end
  if state.server then
    return { port = state.port, token = state.token }
  end
  state.token = opts.token or (tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)))
  start_server()
  return { port = state.port, token = state.token }
end

function M.stop()
  if state.server and not state.server:is_closing() then
    state.server:close()
  end
  state.server = nil
  state.port = nil
end

function M.info()
  return { port = state.port, token = state.token }
end

function M.clear_highlights(params)
  return clear_highlights(params or {})
end

function M.highlight_range(params)
  return highlight_range(params or {})
end

return M
