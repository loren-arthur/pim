-- Minimal Neovim init for running pim's plugin tests under plenary.nvim.
-- Intentionally does NOT source the user's init.lua — tests should exercise
-- pim in isolation.
--
-- Locates plenary.nvim in any of the typical install paths and prepends it,
-- then prepends the pim repo onto runtimepath so `require("pim")` resolves.

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.more = false
vim.opt.shortmess:append("I")

-- Settle the test leader key so global `<leader>p*` mappings registered by
-- pim are stored literally resolved (e.g. ` pm`); otherwise they would be
-- stored with the raw `<leader>` token and lookups against `pm` would miss.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Pin the pim repo (parent of this file's parent) onto runtimepath.
local info = debug.getinfo(1, "S")
local source = info.source:sub(2) -- strip leading "@"
local this_file = vim.fn.fnamemodify(source, ":p")
local repo_root = vim.fn.fnamemodify(this_file, ":h:h")
vim.opt.rtp:prepend(repo_root)

-- Make `require("helpers.<name>")` resolve to tests/helpers/<name>.lua so specs
-- can share small utilities (interpreter probing, fixtures, etc.).
package.path = package.path .. ";" .. repo_root .. "/tests/?.lua"

local function find_plenary()
  local function check(path)
    if vim.fn.isdirectory(path) == 1 and vim.fn.filereadable(path .. "/lua/plenary/busted.lua") == 1 then
      return path
    end
  end
  for _, base in ipairs({
    "~/.local/share/nvim/site/pack/local/start/plenary.nvim",
    "~/.local/share/nvim/lazy/plenary.nvim",
    vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
    "~/.config/nvim/pack/local/start/plenary.nvim",
  }) do
    local p = check(vim.fn.expand(base))
    if p then
      return p
    end
  end
  for _, glob in ipairs({
    vim.fn.stdpath("data") .. "/site/pack/*/start/plenary.nvim",
    vim.fn.stdpath("data") .. "/site/pack/*/opt/plenary.nvim",
  }) do
    for _, p in ipairs(vim.fn.glob(glob, true, true)) do
      if check(p) then
        return p
      end
    end
  end
  return nil
end

local plenary = find_plenary()
if not plenary then
  error("plenary.nvim not found in any known install path — see tests/README.md")
end
vim.opt.rtp:prepend(plenary)
vim.cmd("runtime plugin/plenary.vim")
