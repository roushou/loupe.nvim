local h = require("tests.harness")
local nvim_backend = require("loupe.backend.nvim")

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

h.test("buffers lists listed, named buffers with bufnr", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "x" }, path)
	local buf = vim.fn.bufadd(path)
	vim.bo[buf].buflisted = true

	local got
	nvim_backend.list.buffers({ root = dir }, function(c)
		got = c
	end)
	local found
	for _, c in ipairs(got) do
		if c.bufnr == buf then
			found = c
		end
	end
	h.ok(found, "buffer not listed")
	h.eq(found.rel, "a.lua")
end)

h.test("diagnostics lists diagnostics with 1-based lnum", function()
	local dir = tmpdir()
	local path = dir .. "/a.lua"
	vim.fn.writefile({ "x" }, path)
	local buf = vim.fn.bufadd(path)
	vim.bo[buf].buflisted = true
	local ns = vim.api.nvim_create_namespace("loupe_test_diag")
	vim.diagnostic.set(ns, buf, { { lnum = 4, col = 2, message = "boom", severity = 1 } })

	local got
	nvim_backend.list.diagnostics({ root = dir }, function(c)
		got = c
	end)
	local found
	for _, c in ipairs(got) do
		if c.abs == path then
			found = c
		end
	end
	h.ok(found, "diagnostic not listed")
	h.eq(found.lnum, 5)
	h.eq(found.col, 2)
	h.eq(found.severity, 1)
	h.ok(found.icon, "severity icon missing")
	h.eq(found.icon_hl, "DiagnosticError")
	vim.diagnostic.reset(ns, buf)
end)
