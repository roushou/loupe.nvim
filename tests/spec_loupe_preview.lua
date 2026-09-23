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
