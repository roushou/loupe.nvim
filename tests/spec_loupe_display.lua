local h = require("tests.harness")
local display = require("loupe.display")

local function meta_text(row)
	return vim.tbl_map(function(chunk)
		return chunk[1]
	end, row.meta)
end

--- The left column as `{ text, highlight }` pairs flattened for comparison.
local function left(row)
	return vim.tbl_map(function(chunk)
		return { chunk[1], chunk[2] }
	end, row.left)
end

h.test("row dims the parent directory and keeps the name", function()
	local row = display.row({ rel = "lua/loupe/init.lua", abs = "/p/lua/loupe/init.lua" }, {})
	h.eq(left(row), { { "lua/loupe/", "LoupeDir" }, { "init.lua" } })
	h.eq(row.match_len, #"lua/loupe/init.lua", "the whole path must stay matchable")
end)

h.test("row leaves a bare filename undivided", function()
	h.eq(left(display.row({ rel = "README.md" }, {})), { { "", "LoupeDir" }, { "README.md" } })
end)

h.test("row marks directories with a trailing slash", function()
	h.eq(left(display.row({ rel = "lua/loupe", dir = true }, {}))[2], { "loupe/" })
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

h.test("a location row puts its text left and where it is right", function()
	local row = display.row({
		rel = "a/b.lua",
		text = "local M = {}",
		meta = "a/b.lua:12",
		label = "local M = {}  a/b.lua:12",
		lnum = 12,
	}, {})
	h.eq(left(row), { { "local M = {}" } })
	h.eq(meta_text(row), { "a/b.lua:12" })
	h.eq(row.match_len, #"local M = {}", "only the left column is highlightable")
	h.eq(row.marks, nil, "no match range was given")
end)

h.test("a location row carries the match range its source found", function()
	local row = display.row({
		rel = "a/b.lua",
		text = "local M = {}",
		meta = "a/b.lua:12",
		text_col = 6,
		text_col_end = 7,
	}, {})
	h.eq(row.marks, { { 6, 7, "LoupeMatch" } })
end)

h.test("a location row shows no filetype or git column", function()
	local git = { ["a/b.lua"] = { text = "M", hl = "LoupeGitMod" } }
	local row = display.row({ rel = "a/b.lua", text = "x", meta = "a/b.lua:1" }, { git = git })
	h.eq(meta_text(row), { "a/b.lua:1" }, "the location is the whole right column")
end)
