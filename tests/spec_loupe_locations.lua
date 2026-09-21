local h = require("tests.harness")

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

h.test("doc_symbols wraps params in textDocument", function()
	local lsp = require("loupe.backend.lsp")
	local real = vim.lsp.get_clients
	local seen
	local fake = {
		supports_method = function()
			return true
		end,
		request = function(_, method, params, handler)
			seen = { method = method, params = params }
			handler(nil, { { name = "foo", kind = 12, range = { start = { line = 0, character = 0 } } } })
			return true
		end,
	}
	local got
	local ok, err = pcall(function()
		vim.lsp.get_clients = function()
			return { fake }
		end
		lsp.list.doc_symbols({ buf = 0, root = "/r" }, function(cands, done)
			got = { cands, done }
		end)
		vim.wait(500, function()
			return got ~= nil
		end)
	end)
	vim.lsp.get_clients = real
	if not ok then
		error(err)
	end
	h.ok(seen, "no request was made")
	h.eq(seen.method, "textDocument/documentSymbol")
	h.ok(seen.params.textDocument, "params must be wrapped in `textDocument`")
	h.ok(seen.params.textDocument.uri, "textDocument.uri missing")
	h.eq(got[1][1].label, "foo")
end)

h.test("jump positions the origin before the picker closes", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "aaaa", "bbbb", "cccc", "dddd", "eeee" }, path)
	local origin = vim.api.nvim_get_current_win()
	vim.cmd("enew") -- origin starts on an unrelated buffer

	local at_close
	require("loupe.source.jump").choose({ abs = path, lnum = 4, col = 2 }, "edit", {
		session = { origin_win = origin },
		close = function()
			local buf = vim.api.nvim_win_get_buf(origin)
			at_close = { name = vim.api.nvim_buf_get_name(buf), cursor = vim.api.nvim_win_get_cursor(origin) }
		end,
	})
	-- Already on the target when the picker tears down: no line-1 flash.
	h.eq(at_close.name, path)
	h.eq(at_close.cursor[1], 4)
	-- And correctly positioned afterwards.
	h.eq(vim.api.nvim_win_get_cursor(0)[1], 4)
	h.eq(vim.api.nvim_win_get_cursor(0)[2], 2)
end)

h.test("jump keeps the preview view after the drawer closes", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	local lines = {}
	for i = 1, 60 do
		lines[i] = ("L%02d"):format(i)
	end
	vim.fn.writefile(lines, path)
	vim.cmd("edit " .. path)
	local origin = vim.api.nvim_get_current_win()

	-- Simulate the picker layout: a bottom drawer split plus a preview float.
	vim.cmd("botright 9split")
	local drawer = vim.api.nvim_get_current_win()
	local preview = require("loupe.preview")
	preview.open(drawer, {})
	preview.show(path, { lnum = 40 })
	local preview_top = preview.topline()

	require("loupe.source.jump").choose({ abs = path, lnum = 40, col = 0 }, "edit", {
		session = { origin_win = origin },
		close = function()
			preview.close()
			vim.api.nvim_win_close(drawer, true)
		end,
	})

	-- Closing the drawer grows the window and Neovim re-centers; jump must
	-- restore the preview's topline so the reveal does not scroll.
	local v = vim.api.nvim_win_call(origin, function()
		return vim.fn.winsaveview()
	end)
	h.eq(v.topline, preview_top)
	h.eq(v.lnum, 40)
end)
