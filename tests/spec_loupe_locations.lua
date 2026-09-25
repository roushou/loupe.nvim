local h = require("tests.harness")

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

h.test("doc_symbols wraps params in textDocument", function()
	local lsp = require("loupe.backend").registry.lsp
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
	h.eq(got[1][1].text, "foo")
	h.eq(got[1][1].meta, "Function", "the kind belongs in the right-hand column")
	h.eq(got[1][1].label, "foo  Function", "both columns stay searchable")
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

--- Run an LSP list op against a fake client and capture what it produced.
local function lsp_list(op, ctx, client, method)
	local lsp = require("loupe.backend").registry.lsp
	local real = vim.lsp.get_clients
	local got
	local ok, err = pcall(function()
		vim.lsp.get_clients = function()
			return { client }
		end
		lsp.list[op](ctx, function(cands, done)
			got = { cands, done }
		end)
		if method then
			vim.wait(500, function()
				return got ~= nil
			end)
		end
	end)
	vim.lsp.get_clients = real
	if not ok then
		error(err)
	end
	return got
end

h.test("references asks at the captured cursor, dedupes and sorts locations", function()
	local dir = tmpdir()
	local a = dir .. "/a.lua"
	local b = dir .. "/sub/b.lua"
	vim.fn.mkdir(dir .. "/sub", "p")
	vim.fn.writefile({ "one", "two", "three" }, a)
	vim.fn.writefile({ "alpha" }, b)

	local seen
	local client = {
		supports_method = function(_, method)
			return method == "textDocument/references"
		end,
		request = function(_, method, params, handler)
			seen = { method = method, params = params }
			handler(nil, {
				{ uri = vim.uri_from_fname(a), range = { start = { line = 2, character = 4 } } },
				{ uri = vim.uri_from_fname(b), range = { start = { line = 0, character = 1 } } },
				-- the same location again: it must be collapsed
				{ uri = vim.uri_from_fname(a), range = { start = { line = 2, character = 4 } } },
			})
			return true
		end,
	}
	local got = lsp_list("references", { buf = 0, root = dir, cursor = { 5, 7 } }, client, true)

	h.eq(seen.method, "textDocument/references")
	h.eq(seen.params.position, { line = 4, character = 7 }, "cursor is 1-based and becomes 0-based")
	h.ok(seen.params.context and seen.params.context.includeDeclaration, "declaration must be included")
	h.eq(#got[1], 2, "the duplicate location must be collapsed")
	h.eq(got[1][1].rel, "a.lua")
	h.eq(got[1][1].text, "three")
	h.eq(got[1][1].meta, "a.lua:3")
	h.eq(got[1][1].label, "three  a.lua:3")
	h.eq(got[1][1].lnum, 3)
	h.eq(got[1][1].col, 4)
	h.eq(got[1][2].rel, "sub/b.lua")
	h.eq(got[1][2].text, "alpha")
	h.eq(got[2], true)
end)

h.test("implementations accepts a bare Location and a LocationLink", function()
	local dir = tmpdir()
	local a = dir .. "/impl.lua"
	vim.fn.writefile({ "x", "y" }, a)

	local client = {
		supports_method = function(_, method)
			return method == "textDocument/implementation"
		end,
		request = function(_, _, _, handler)
			handler(nil, {
				-- a bare Location rather than a list of them
				{ uri = vim.uri_from_fname(a), range = { start = { line = 1, character = 0 } } },
				-- a LocationLink points at its target instead, and its selection
				-- range wins over the (wider) target range
				{
					targetUri = vim.uri_from_fname(a),
					targetRange = { start = { line = 0, character = 0 } },
					targetSelectionRange = { start = { line = 0, character = 4 } },
				},
			})
			return true
		end,
	}
	local got = lsp_list("implementations", { buf = 0, root = dir, cursor = { 1, 0 } }, client, true)

	h.eq(#got[1], 2)
	h.eq(got[1][1].meta, "impl.lua:1")
	h.eq(got[1][1].text, "x")
	h.eq(got[1][1].col, 4, "the selection range is preferred over the whole target range")
	h.eq(got[1][2].meta, "impl.lua:2")
	h.eq(got[1][2].text, "y")
end)

h.test("references is empty when no client supports the method", function()
	local client = {
		supports_method = function()
			return false
		end,
		request = function()
			error("a request must not be sent to an unqualified client")
		end,
	}
	local got = lsp_list("references", { buf = 0, root = "/r", cursor = { 1, 0 } }, client, false)
	h.eq(got, { {}, true })
end)

h.test("the references source resolves to the lsp backend with the corner cursor", function()
	local source = require("loupe.source")
	local dir = tmpdir()
	local a = dir .. "/a.lua"
	vim.fn.writefile({ "hello" }, a)

	local real = vim.lsp.get_clients
	local seen
	local client = {
		supports_method = function(_, method)
			return method == "textDocument/references"
		end,
		request = function(_, _, params, handler)
			seen = params
			handler(nil, { { uri = vim.uri_from_fname(a), range = { start = { line = 0, character = 0 } } } })
			return true
		end,
	}
	local got
	local ok, err = pcall(function()
		vim.lsp.get_clients = function()
			return { client }
		end
		source.load(source.get("references"), {
			root = dir,
			buf = 0,
			cursor = { 3, 1 },
			name = "references",
		}, function(cands, done)
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
	h.eq(seen.position, { line = 2, character = 1 })
	h.eq(got[1][1].text, "hello")
	h.eq(got[2], true)
end)
