--- nvim backend: sources served from Neovim's own state, no external tool.
---
--- Always available (`exe` is nil). Buffer candidates carry `bufnr` so the
--- session can reuse the loaded buffer instead of re-reading from disk.

local parse = require("loupe.backend.parse")

local M = {} -- no exe: always available

--- Severity glyph + highlight, keyed by |vim.diagnostic.severity|.
local SEVERITY = {
	[vim.diagnostic.severity.ERROR] = { "\u{f057}", "DiagnosticError" },
	[vim.diagnostic.severity.WARN] = { "\u{f071}", "DiagnosticWarn" },
	[vim.diagnostic.severity.INFO] = { "\u{f05a}", "DiagnosticInfo" },
	[vim.diagnostic.severity.HINT] = { "\u{f0eb}", "DiagnosticHint" },
}

M.list = {
	buffers = function(ctx, cb)
		local out = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if vim.bo[buf].buflisted and name ~= "" then
				local rel = parse.relpath(ctx.root, name)
				out[#out + 1] = { rel = rel, abs = name, label = rel, bufnr = buf, dir = false }
			end
		end
		cb(out, true)
	end,

	diagnostics = function(ctx, cb)
		local out = {}
		for _, d in ipairs(vim.diagnostic.get()) do
			local name = d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) and vim.api.nvim_buf_get_name(d.bufnr) or ""
			if name ~= "" then
				local rel = parse.relpath(ctx.root, name)
				local lnum = d.lnum + 1
				local sev = SEVERITY[d.severity]
				out[#out + 1] = {
					rel = rel,
					abs = name,
					label = rel .. ":" .. lnum .. ": " .. (d.message or ""),
					lnum = lnum,
					col = d.col or 0,
					col_end = (d.end_lnum == d.lnum) and d.end_col or nil,
					severity = d.severity,
					icon = sev and sev[1],
					icon_hl = sev and sev[2],
					dir = false,
				}
			end
		end
		cb(out, true)
	end,
}

return M
