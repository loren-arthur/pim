local M = {}

local state = {
  dir = nil,
  md_path = nil,
  jsonl_path = nil,
  session = nil,
}

local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

local function append_file(path, text)
  if not path then
    return
  end
  local file = io.open(path, "a")
  if not file then
    vim.schedule(function()
      vim.notify("failed to open transcript: " .. path, vim.log.levels.WARN, { title = "pim" })
    end)
    return
  end
  file:write(text)
  file:close()
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function sanitize(value)
  value = tostring(value or "unknown")
  value = value:gsub("[^%w%._%-]+", "-")
  value = value:gsub("%-+", "-")
  value = value:gsub("^%-", "")
  value = value:gsub("%-$", "")
  if value == "" then
    return "unknown"
  end
  return value
end

function M.setup(opts)
  opts = opts or {}
  state.dir = opts.dir or (vim.fn.stdpath("state") .. "/pim/sessions")
  ensure_dir(state.dir)
end

function M.attach_session(session)
  session = session or {}
  state.session = session
  local id = sanitize(session.sessionId or session.sessionFile or "current")
  state.md_path = state.dir .. "/" .. id .. ".md"
  state.jsonl_path = state.dir .. "/" .. id .. ".jsonl"

  if vim.fn.filereadable(state.md_path) == 0 then
    local header = {
      "# pim conversation",
      "",
      "- Session ID: " .. tostring(session.sessionId or "unknown"),
      "- Session file: " .. tostring(session.sessionFile or "unknown"),
      "- Session name: " .. tostring(session.sessionName or ""),
      "- Created: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
      "",
    }
    append_file(state.md_path, table.concat(header, "\n"))
  end
end

function M.ensure_current()
  if state.md_path then
    return
  end
  M.attach_session({ sessionId = "current" })
end

function M.append_markdown(text)
  M.ensure_current()
  append_file(state.md_path, text)
end

function M.append_block(title, text)
  M.ensure_current()
  M.append_markdown("\n\n## " .. title .. "\n\n" .. (text or "") .. "\n")
end

function M.append_event(event)
  M.ensure_current()
  local ok, encoded = pcall(vim.json.encode, event)
  if ok then
    append_file(state.jsonl_path, encoded .. "\n")
  end
end

function M.read_markdown_lines()
  M.ensure_current()
  local text = read_file(state.md_path)
  if not text or text == "" then
    return {}
  end
  return vim.split(text:gsub("\n$", ""), "\n", { plain = true })
end

function M.paths()
  M.ensure_current()
  return {
    dir = state.dir,
    markdown = state.md_path,
    jsonl = state.jsonl_path,
    session = state.session,
  }
end

return M
