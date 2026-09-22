local h = require("tests.harness")
local display = require("loupe.display")

local function meta_text(row)
	return vim.tbl_map(function(chunk)
		return chunk[1]
	end, row.meta)
end

h.test("row dims the parent directory and keeps the name", function()
	local row = display.row({ rel = "lua/loupe/init.lua", abs = "/p/lua/loupe/init.lua" }, {})
	h.eq(row.dir, "lua/loupe/")
	h.eq(row.name, "init.lua")
	h.eq(row.dir .. row.name, "lua/loupe/init.lua", "the matched text must survive the split")
end)

h.test("row leaves a bare filename undivided", function()
	local row = display.row({ rel = "README.md" }, {})
	h.eq(row.dir, "")
	h.eq(row.name, "README.md")
end)

h.test("row marks directories with a trailing slash", function()
	h.eq(display.row({ rel = "lua/loupe", dir = true }, {}).name, "loupe/")
end)

h.test("row carries the filetype in the metadata column", function()
	h.eq(meta_text(display.row({ rel = "a/b.lua" }, {})), { "lua" })
	h.eq(meta_text(display.row({ rel = "a/b", dir = true }, {})), {})
end)

h.test("row shows git status before the filetype", function()
	local git = { ["a/b.lua"] = { text = "M", hl = "LoupeGitMod" } }
	local row = display.row({ rel = "a/b.lua" }, { git = git })
	h.eq(meta_text(row), { "M", "lua" })
	h.eq(row.meta[1][2], "LoupeGitMod")
end)

h.test("row flags a modified buffer", function()
	local path = vim.fn.tempname() .. ".lua"
	vim.fn.writefile({ "x" }, path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited" })
	local row = display.row({ rel = "b.lua", abs = path, bufnr = buf }, {})
	h.eq(meta_text(row), { "+", "lua" })
	vim.api.nvim_buf_delete(buf, { force = true })
end)

h.test("row can be drawn without icons", function()
	h.eq(display.row({ rel = "a.lua" }, { icons = false }).icon, "")
	h.ok(display.row({ rel = "a.lua" }, {}).icon ~= "")
end)

h.test("row leaves a source's own label whole", function()
	local row = display.row({ rel = "a/b.lua", label = "handler  a/b.lua", lnum = 3 }, {})
	h.eq(row.dir, "", "a label is not a path to dim")
	h.eq(row.name, "handler  a/b.lua")
end)
