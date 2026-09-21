-- Minimal init for the headless test runner: repo on the runtimepath, no
-- plugins, and `tests/` importable. Invoked as:
--   nvim --headless -u tests/minimal_init.lua -l tests/run.lua

local src = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(src, ":h:h")
if root == "" then
	root = vim.fn.getcwd()
end

vim.opt.loadplugins = false
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
