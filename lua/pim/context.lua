local M = {}

local function current_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return name
end

function M.range(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local line1 = opts.line1 or vim.fn.line("'<")
  local line2 = opts.line2 or vim.fn.line("'>")
  if line1 > line2 then
    line1, line2 = line2, line1
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local diagnostics = vim.diagnostic.get(bufnr, {
    lnum = nil,
  })

  local range_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local lnum = diagnostic.lnum + 1
    if lnum >= line1 and lnum <= line2 then
      table.insert(range_diagnostics, {
        line = lnum,
        severity = diagnostic.severity,
        source = diagnostic.source,
        message = diagnostic.message,
      })
    end
  end

  return {
    file = current_file(bufnr),
    range = { start = line1, finish = line2 },
    text = table.concat(lines, "\n"),
    diagnostics = range_diagnostics,
  }
end

function M.current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return M.range({ bufnr = bufnr, line1 = 1, line2 = line_count })
end

function M.prompt_for_range(comment, ctx)
  local file = ctx.file or "[No file name]"
  local range = ctx.range.start == ctx.range.finish
      and tostring(ctx.range.start)
      or (ctx.range.start .. "-" .. ctx.range.finish)

  local chunks = {
    "Editor context:",
    "",
    "File: " .. file,
    "Range: " .. range,
    "",
    "Selected text:",
    "```",
    ctx.text,
    "```",
  }

  if ctx.diagnostics and #ctx.diagnostics > 0 then
    table.insert(chunks, "")
    table.insert(chunks, "Diagnostics in range:")
    for _, diagnostic in ipairs(ctx.diagnostics) do
      table.insert(chunks, string.format(
        "- line %s: %s%s",
        diagnostic.line,
        diagnostic.message or "",
        diagnostic.source and (" [" .. diagnostic.source .. "]") or ""
      ))
    end
  end

  if comment and comment ~= "" then
    table.insert(chunks, "")
    table.insert(chunks, "User comment/question:")
    table.insert(chunks, comment)
  else
    table.insert(chunks, "")
    table.insert(chunks, "Please use this editor context for the next response.")
  end

  return table.concat(chunks, "\n")
end

-- Build a single structured prompt from a batch of inline annotations (as
-- produced by `annotations.list()`), each with its file, range, text, and
-- comment. `intro` is an optional overarching instruction/question.
function M.prompt_for_annotations(annotations, intro)
  local chunks = {
    "Editor context: inline comments attached to code ranges.",
  }

  if intro and intro ~= "" then
    table.insert(chunks, "")
    table.insert(chunks, "Overall request:")
    table.insert(chunks, intro)
  end

  for index, ann in ipairs(annotations) do
    local file = ann.file or "[No file name]"
    local range = ann.range.start == ann.range.finish
        and tostring(ann.range.start)
        or (ann.range.start .. "-" .. ann.range.finish)
    table.insert(chunks, "")
    table.insert(chunks, string.format("Comment %d — %s:%s", index, file, range))
    table.insert(chunks, "```")
    table.insert(chunks, ann.text or "")
    table.insert(chunks, "```")
    table.insert(chunks, "Comment: " .. (ann.comment or ""))
  end

  return table.concat(chunks, "\n")
end

return M
