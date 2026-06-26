-- In-place editor for pi's settings.json. Replaces top-level string-typed
-- key values line-by-line so unrelated formatting (nested objects, key
-- ordering, indentation, trailing comma, surrounding comments) is preserved
-- across writes.
local M = {}

-- Replace the value of a top-level string-typed key in pi's settings JSON.
-- Walks lines while tracking brace depth so a key of the same name nested
-- inside another object (e.g. `theme.defaultProvider`) is left alone. Trailing
-- whitespace on the matched line is stripped (intentional normalization — most
-- editors display trailing spaces as noise).
-- Returns the rewritten text and whether the key was already present.
function M.update_string_setting(text, key, value)
  local quoted_key = '"' .. key .. '"'
  local new_value = vim.json.encode(value)
  local lines = vim.split(text, "\n", { plain = true })
  local depth = 0
  for i, line in ipairs(lines) do
    -- Track JSON container depth at end of line so a top-level key is only
    -- matched when we are directly inside the root object (depth == 1).
    local _, opens = line:gsub("{", "")
    local _, closes = line:gsub("}", "")
    depth = depth + opens - closes
    if depth == 1 then
      local _, _, indent, trailing_comma = line:find(
        "^(%s*)" .. vim.pesc(quoted_key) .. "%s*:%s*\"[^\"]*\"(,?)%s*$"
      )
      if indent then
        lines[i] = indent .. quoted_key .. ": " .. new_value
          .. (trailing_comma ~= "" and trailing_comma or "")
        return table.concat(lines, "\n"), true
      end
    end
  end
  return text, false
end

-- Insert a new top-level string-typed key just before the closing brace,
-- borrowing the indent from an existing entry. If the previously-last
-- sibling lacks a trailing comma (which only happens when the file had
-- exactly zero or one top-level keys), add one so the result stays valid
-- JSON. Handles a single-line `{}` as a special case.
function M.insert_string_setting(text, key, value)
  local quoted_key = '"' .. key .. '"'
  local lines = vim.split(text, "\n", { plain = true })
  local indent = "  "
  for _, l in ipairs(lines) do
    local found = l:match("^(%s*)\"[^\"]+\"%s*:%s*")
    if found then
      indent = found
      break
    end
  end
  for i = #lines, 1, -1 do
    local stripped = lines[i]:match("^%s*(.-)%s*$")
    if stripped == "}" or stripped == "{}" then
      if stripped == "{}" then
        lines[i] = "{\n" .. indent .. quoted_key .. ": " .. vim.json.encode(value) .. "\n}"
        return table.concat(lines, "\n"), true
      end
      if i > 1 then
        local prev = lines[i - 1]
        if not prev:match(",%s*$") then
          lines[i - 1] = (prev:gsub("%s+$", "")) .. ","
        end
      end
      table.insert(lines, i, indent .. quoted_key .. ": " .. vim.json.encode(value) .. ",")
      return table.concat(lines, "\n"), true
    end
  end
  return text, false
end

return M
