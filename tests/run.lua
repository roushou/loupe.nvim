--- Headless test runner.
---   nvim --headless -u tests/minimal_init.lua -l tests/run.lua

vim.notify = function() end -- keep test output clean

local harness = require("tests.harness")
for _, spec in ipairs({
	"tests.spec_loupe_backend",
	"tests.spec_loupe_parse",
	"tests.spec_loupe_nvim",
	"tests.spec_loupe_locations",
	"tests.spec_loupe_preview",
	"tests.spec_loupe_source",
	"tests.spec_loupe_icons",
	"tests.spec_loupe_keymap",
	"tests.spec_loupe_action",
	"tests.spec_loupe_stream",
}) do
	require(spec)
end

if not harness.run() then
	vim.cmd("cquit")
end
vim.cmd("qall!")
