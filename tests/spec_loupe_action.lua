local h = require("tests.harness")
local action = require("loupe.action")

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

h.test("create makes a file and inserts it first", function()
	local root = tmpdir()
	local session = { candidates = {} }
	local item = { cand = { rel = "a.lua", abs = root .. "/a.lua", dir = false } }

	local rel = action.create({ session = session, item = item, root = root }, "new.lua")
	h.eq(rel, "new.lua")
	h.eq(vim.fn.filereadable(root .. "/new.lua"), 1)
	h.eq(session.candidates[1].rel, "new.lua")
end)

h.test("create refuses an existing path", function()
	local root = tmpdir()
	vim.fn.writefile({ "x" }, root .. "/a.lua")
	local rel = action.create({ session = { candidates = {} }, item = { cand = { rel = "b" } }, root = root }, "a.lua")
	h.eq(rel, nil)
end)

h.test("delete removes the file and its candidate", function()
	local root = tmpdir()
	vim.fn.writefile({ "x" }, root .. "/a.lua")
	local cand = { rel = "a.lua", abs = root .. "/a.lua", dir = false }
	local session = { candidates = { cand } }

	h.ok(action.delete({ session = session, item = { cand = cand }, root = root }))
	h.eq(vim.fn.filereadable(root .. "/a.lua"), 0)
	h.eq(#session.candidates, 0)
end)

h.test("delete refuses directories when trash is disabled", function()
	-- Trash availability is environment-dependent (gio/trash-cli), so pin the
	-- non-trash path to make the assertion deterministic.
	local config = require("loupe.config")
	config.setup({ trash = false })
	local root = tmpdir()
	vim.fn.mkdir(root .. "/sub", "p")
	local cand = { rel = "sub", abs = root .. "/sub", dir = true }
	local result = action.delete({ session = { candidates = { cand } }, item = { cand = cand }, root = root })
	config.setup({})
	h.eq(result, false)
	h.eq(vim.fn.isdirectory(root .. "/sub"), 1)
end)

h.test("rename moves the file and updates the candidate", function()
	local root = tmpdir()
	vim.fn.writefile({ "x" }, root .. "/a.lua")
	local cand = { rel = "a.lua", abs = root .. "/a.lua", dir = false }

	local rel = action.rename({ session = { candidates = { cand } }, item = { cand = cand }, root = root }, "sub/b.lua")
	h.eq(rel, "sub/b.lua")
	h.eq(vim.fn.filereadable(root .. "/sub/b.lua"), 1)
	h.eq(cand.rel, "sub/b.lua")
end)

h.test("rename refuses an existing target", function()
	local root = tmpdir()
	vim.fn.writefile({ "a" }, root .. "/a.lua")
	vim.fn.writefile({ "b" }, root .. "/b.lua")
	local cand = { rel = "a.lua", abs = root .. "/a.lua", dir = false }
	h.eq(action.rename({ session = { candidates = { cand } }, item = { cand = cand }, root = root }, "b.lua"), nil)
end)

h.test("duplicate copies the file and inserts the copy first", function()
	local root = tmpdir()
	vim.fn.writefile({ "x" }, root .. "/a.lua")
	local cand = { rel = "a.lua", abs = root .. "/a.lua", dir = false }
	local session = { candidates = { cand } }
	local rel = action.duplicate({ session = session, item = { cand = cand }, root = root }, "b.lua")
	h.eq(rel, "b.lua")
	h.eq(vim.fn.filereadable(root .. "/b.lua"), 1)
	h.eq(session.candidates[1].rel, "b.lua")
end)

h.test("create with a trailing slash makes a directory", function()
	local root = tmpdir()
	local session = { candidates = {} }
	local item = { cand = { rel = "x.lua", abs = root .. "/x.lua", dir = false } }
	local rel = action.create({ session = session, item = item, root = root }, "sub/")
	h.eq(rel, "sub")
	h.eq(vim.fn.isdirectory(root .. "/sub"), 1)
	h.eq(session.candidates[1].dir, true)
end)

h.test("quickfix fills the list with 1-based columns", function()
	vim.fn.setqflist({}, "f")
	action.quickfix({ { abs = "/r/a.lua", rel = "a.lua", lnum = 3, col = 2, label = "a.lua:3: x" } })
	local qf = vim.fn.getqflist()
	h.eq(#qf, 1)
	h.eq(qf[1].lnum, 3)
	h.eq(qf[1].col, 3)
end)

h.test("close_buffer closes the buffer and leaves the file on disk", function()
	local root = tmpdir()
	local path = root .. "/a.lua"
	vim.fn.writefile({ "x" }, path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	local cand = { rel = "a.lua", abs = path, bufnr = buf, dir = false }
	local session = { candidates = { cand } }

	h.ok(action.close_buffer({ session = session, item = { cand = cand }, root = root }))
	h.eq(vim.api.nvim_buf_is_valid(buf), false)
	h.eq(vim.fn.filereadable(path), 1, "the file was deleted")
	h.eq(#session.candidates, 0)
end)

h.test("close_buffer refuses a modified buffer unless forced", function()
	local root = tmpdir()
	local path = root .. "/b.lua"
	vim.fn.writefile({ "x" }, path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited" })
	local cand = { rel = "b.lua", abs = path, bufnr = buf, dir = false }
	local ctx = { session = { candidates = { cand } }, item = { cand = cand }, root = root }

	h.eq(action.close_buffer(ctx), false)
	h.eq(vim.api.nvim_buf_is_valid(buf), true)
	h.ok(action.close_buffer(ctx, true))
	h.eq(vim.api.nvim_buf_is_valid(buf), false)
	h.eq(vim.fn.filereadable(path), 1)
end)

h.test("close_buffer drops a candidate whose buffer is already gone", function()
	local cand = { rel = "gone.lua", abs = "/x/gone.lua", bufnr = 9999, dir = false }
	local session = { candidates = { cand } }
	h.ok(action.close_buffer({ session = session, item = { cand = cand }, root = "/x" }))
	h.eq(#session.candidates, 0)
end)

h.test("close_buffer keeps the windows that showed the buffer", function()
	local root = tmpdir()
	local path = root .. "/c.lua"
	vim.fn.writefile({ "x" }, path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	vim.cmd("split")
	local before = #vim.api.nvim_list_wins()
	local wins = vim.fn.win_findbuf(buf)
	h.eq(#wins, 2)

	local cand = { rel = "c.lua", abs = path, bufnr = buf, dir = false }
	h.ok(action.close_buffer({ session = { candidates = { cand } }, item = { cand = cand }, root = root }))
	h.eq(#vim.api.nvim_list_wins(), before, "a window was closed with the buffer")
	for _, win in ipairs(wins) do
		h.ok(vim.api.nvim_win_is_valid(win), "window closed")
		h.ok(vim.api.nvim_win_get_buf(win) ~= buf, "window still shows the closed buffer")
	end
	vim.cmd("only")
end)
