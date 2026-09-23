--- diagnostics: every diagnostic Neovim is holding, across open documents.

local parse = require("loupe.backend.parse")

--- Severity glyph + highlight, keyed by |vim.diagnostic.severity|.
local SEVERITY = {
	[vim.diagnostic.severity.ERROR] = { "\u{f057}", "DiagnosticError" },
	[vim.diagnostic.severity.WARN] = { "\u{f071}", "DiagnosticWarn" },
	[vim.diagnostic.severity.INFO] = { "\u{f05a}", "DiagnosticInfo" },
	[vim.diagnostic.severity.HINT] = { "\u{f0eb}", "DiagnosticHint" },
}

return {
	list = {
		diagnostics = {
			nvim = function(ctx, cb)
				local out = {}
				for _, d in ipairs(vim.diagnostic.get()) do
					local name = d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) and vim.api.nvim_buf_get_name(d.bufnr)
						or ""
					if name ~= "" then
						local rel = parse.relpath(ctx.root, name)
						local lnum = d.lnum + 1
						local sev = SEVERITY[d.severity]
						local where = parse.location(rel, lnum)
						local message = vim.trim((d.message or ""):gsub("%s*\n.*$", ""))
						out[#out + 1] = {
							rel = rel,
							abs = name,
							text = message,
							meta = where,
							label = message .. "  " .. where,
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
		},
	},
}
