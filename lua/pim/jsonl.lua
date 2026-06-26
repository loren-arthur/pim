-- Newline-delimited JSON framing for pi's stdout. `consume_chunk` accepts a
-- stream of bytes split into chunks (the way Neovim delivers them from
-- `on_stdout`) and emits parsed events via the supplied callback.
--
-- Pending bytes (between newlines) are read and written through callbacks so
-- the caller controls how/where storage lives; this keeps the parser pure
-- and trivially testable.
local M = {}

-- Args:
--   read_pending  -> () returns the current string of bytes accumulated but
--                    not yet terminated by a newline.
--   write_pending -> (string) replaces the pending buffer.
--   chunk         -> (string) new bytes from the stream.
--   on_event      -> (table) called for each fully framed event, including a
--                    synthetic `pim_parse_error` event when a line cannot be
--                    decoded as JSON.
function M.consume_chunk(read_pending, write_pending, chunk, on_event)
  local pending = read_pending() .. chunk
  while true do
    local newline = pending:find("\n", 1, true)
    if not newline then
      break
    end
    local line = pending:sub(1, newline - 1)
    pending = pending:sub(newline + 1)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    if line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if not ok then
        on_event({ type = "pim_parse_error", line = line, error = decoded })
      else
        on_event(decoded)
      end
    end
  end
  write_pending(pending)
end

return M
