-- Inline annotations attached to code ranges via extmarks.
--
-- Users attach free-text comments to a line/range in any buffer. The comment
-- is anchored with an extmark so it tracks edits, and rendered with a sign plus
-- eol virtual text. Annotations can later be collected and sent to pi as one
-- structured batch (see `pim.send_comments`).

local M = {}

local state = {
  namespace = nil,
  -- ordered list of { bufnr, id, comment }
  items = {},
}

local function namespace()
  if not state.namespace then
    state.namespace = vim.api.nvim_create_namespace("pim-annotations")
  end
  return state.namespace
end

local function truncate(text, width)
  width = width or 60
  local oneline = (text or ""):gsub("%s+", " "):gsub("^%s+", "")
  if vim.fn.strchars(oneline) > width then
    oneline = vim.fn.strcharpart(oneline, 0, width - 1) .. "…"
  end
  return oneline
end

-- Add an annotation over the given 1-based line range in `bufnr`.
function M.add(comment, opts)
  opts = opts or {}
  if not comment or comment == "" then
    return nil
  end
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local line1 = (opts.line1 or vim.fn.line(".")) - 1
  local line2 = (opts.line2 or opts.line1 or vim.fn.line(".")) - 1
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local last = vim.api.nvim_buf_line_count(bufnr) - 1
  line1 = math.max(0, math.min(line1, last))
  line2 = math.max(0, math.min(line2, last))

  local id = vim.api.nvim_buf_set_extmark(bufnr, namespace(), line1, 0, {
    end_row = line2,
    end_col = 0,
    hl_group = "PimAnnotation",
    sign_text = "▌",
    sign_hl_group = "PimAnnotationSign",
    virt_text = { { " 💬 " .. truncate(comment), "PimAnnotationText" } },
    virt_text_pos = "eol",
    right_gravity = false,
    end_right_gravity = true,
  })
  table.insert(state.items, { bufnr = bufnr, id = id, comment = comment })
  return id
end

-- Collect live annotations, resolving each extmark's current range and text.
-- Stale entries (deleted buffers/extmarks) are pruned as a side effect.
function M.list()
  local ns = namespace()
  local out = {}
  local kept = {}
  for _, item in ipairs(state.items) do
    if vim.api.nvim_buf_is_valid(item.bufnr) then
      local pos = vim.api.nvim_buf_get_extmark_by_id(item.bufnr, ns, item.id, { details = true })
      if pos and pos[1] ~= nil then
        local srow = pos[1]
        local details = pos[3] or {}
        local erow = details.end_row or srow
        if erow < srow then
          erow = srow
        end
        local lines = vim.api.nvim_buf_get_lines(item.bufnr, srow, erow + 1, false)
        local name = vim.api.nvim_buf_get_name(item.bufnr)
        table.insert(out, {
          file = name ~= "" and name or nil,
          range = { start = srow + 1, finish = erow + 1 },
          text = table.concat(lines, "\n"),
          comment = item.comment,
        })
        table.insert(kept, item)
      end
    end
  end
  state.items = kept
  return out
end

function M.count()
  return #M.list()
end

-- Clear annotations. With `bufnr`, clear only that buffer; otherwise clear all.
function M.clear(bufnr)
  local ns = namespace()
  local kept = {}
  for _, item in ipairs(state.items) do
    local match = bufnr == nil or item.bufnr == bufnr
    if match then
      if vim.api.nvim_buf_is_valid(item.bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, item.bufnr, ns, item.id)
      end
    else
      table.insert(kept, item)
    end
  end
  state.items = kept
end

return M
