-- helpers/interp.lua — resolve a standalone Lua interpreter for spawning the
-- fake_pi helper as a subprocess. CI/dev machines vary: some ship `lua`, some
-- only `luajit`, some neither. We probe common names and, as a last resort,
-- fall back to running the helper through the current Neovim binary (`nvim -l`),
-- which executes a Lua script with argv exposed via the global `arg` table.

local M = {}

-- Returns the interpreter prefix as a list (e.g. { "luajit" } or
-- { "/path/to/nvim", "-l" }). Cached after the first probe.
local cached
function M.prefix()
  if cached then
    return vim.deepcopy(cached)
  end
  for _, name in ipairs({ "lua", "luajit", "lua5.4", "lua5.3", "lua5.2", "lua5.1" }) do
    if vim.fn.executable(name) == 1 then
      cached = { name }
      return vim.deepcopy(cached)
    end
  end
  -- Fall back to the running Neovim as a Lua interpreter.
  cached = { vim.v.progpath, "-l" }
  return vim.deepcopy(cached)
end

-- Build a full pi_cmd that runs `script` with the given args under the
-- resolved interpreter.
function M.cmd(script, ...)
  local out = M.prefix()
  table.insert(out, script)
  for _, arg in ipairs({ ... }) do
    table.insert(out, arg)
  end
  return out
end

return M
