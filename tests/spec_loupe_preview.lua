local h = require("tests.harness")
local preview = require("loupe.preview")

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

--- Open a preview over a real drawer split and return the float buffer.
local function open_preview(path, opts)
	vim.cmd("botright 8split")
	local drawer = vim.api.nvim_get_current_win()
	preview.open(drawer)
	preview.show(path, opts)
	local pwin
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(w).relative ~= "" then
			pwin = w
		end
	end
	return drawer, vim.api.nvim_win_get_buf(pwin)
end

h.test("preview re-emits diagnostics from the real buffer", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "a", "b", "c", "d", "e" }, path)
	local buf = vim.fn.bufadd(path)
	vim.bo[buf].buflisted = true
	local ns = vim.api.nvim_create_namespace("loupe_test_preview_diag")
	vim.diagnostic.set(ns, buf, { { lnum = 2, col = 0, end_lnum = 2, end_col = 1, message = "boom", severity = 1 } })

	local drawer, pbuf = open_preview(path, { diagnostics = true })
	local dns = vim.api.nvim_create_namespace("loupe_preview_diag")
	local has_virt, has_underline, has_sign = false, false, false
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(pbuf, dns, 0, -1, { details = true })) do
		local d = m[4]
		if d.virt_text then
			has_virt = true
		end
		if d.hl_group and d.hl_group:match("DiagnosticUnderline") then
			has_underline = true
		end
		if d.sign_text then
			has_sign = true
		end
	end
	h.ok(has_virt, "no diagnostic virtual text")
	h.ok(has_underline, "no diagnostic underline")
	h.ok(has_sign, "no diagnostic sign")

	preview.close()
	vim.api.nvim_win_close(drawer, true)
	vim.diagnostic.reset(ns, buf)
end)

h.test("preview diagnostics can be disabled", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "a", "b", "c" }, path)
	local buf = vim.fn.bufadd(path)
	vim.bo[buf].buflisted = true
	local ns = vim.api.nvim_create_namespace("loupe_test_preview_diag2")
	vim.diagnostic.set(ns, buf, { { lnum = 1, col = 0, message = "boom", severity = 1 } })

	local drawer, pbuf = open_preview(path, { diagnostics = false })
	local dns = vim.api.nvim_create_namespace("loupe_preview_diag")
	h.eq(#vim.api.nvim_buf_get_extmarks(pbuf, dns, 0, -1, {}), 0)

	preview.close()
	vim.api.nvim_win_close(drawer, true)
	vim.diagnostic.reset(ns, buf)
end)

-- The preview buffer is reused across files, so every show has to leave it in
-- a state that matches what it is displaying: the right language attached, or
-- nothing attached at all.
--
-- Which languages have a parser installed varies, so these assert on "typed
-- somehow" (treesitter or native syntax) rather than on treesitter winning.

--- Open a preview on `path` from a clean slate and return its buffer.
local function fresh_preview(path)
	preview.close()
	local _, buf = open_preview(path)
	return buf
end

--- Whether the preview buffer has been typed as `ft` by either mechanism.
local function typed_as(buf, ft)
	return vim.bo[buf].filetype == ft or vim.bo[buf].syntax == ft
end

h.test("a shebang script is detected even with no extension", function()
	local dir = tmpdir()
	local path = dir .. "/deploy"
	vim.fn.writefile({ "#!/usr/bin/env bash", "echo hi" }, path)
	-- the premise: filename alone cannot type this file, the content tier can
	h.eq(vim.filetype.match({ filename = path }), nil, "this now types by name; the test needs a new example")

	local buf = fresh_preview(path)
	h.ok(typed_as(buf, "sh"), "an extensionless script previewed as plain text")
	preview.close()
end)

h.test("a file too big to highlight drops the previous file's highlighting", function()
	local dir = tmpdir()
	local small, big = dir .. "/small.lua", dir .. "/big.lua"
	vim.fn.writefile({ "local x = 1", "return x" }, small)
	-- past the per-line bound, so `should_highlight` refuses it
	local long = {}
	for i = 1, 10 do
		long[i] = "-- " .. string.rep("x", 5000)
	end
	vim.fn.writefile(long, big)

	local buf = fresh_preview(small)
	h.ok(typed_as(buf, "lua"), "the small file was not typed at all")

	preview.show(big, {})
	h.eq(
		vim.treesitter.highlighter.active[buf],
		nil,
		"the previous file's parser stayed attached, still parsing text it cannot match"
	)
	h.eq(vim.bo[buf].filetype, "", "the previous file's filetype stayed set")
	h.eq(vim.bo[buf].syntax, "", "the previous file's syntax stayed set")
	preview.close()
end)

h.test("typing the preview buffer fires no FileType autocmd", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "local x = 1" }, path)
	local fired = {}
	local group = vim.api.nvim_create_augroup("loupe_spec_ft", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(ev)
			fired[#fired + 1] = ev.buf
		end,
	})

	local buf = fresh_preview(path)
	vim.api.nvim_del_augroup_by_id(group)
	h.ok(typed_as(buf, "lua"), "the preview was not typed at all")
	h.ok(not vim.tbl_contains(fired, buf), "FileType fired on the preview buffer: LSP and friends will attach")
	preview.close()
end)
