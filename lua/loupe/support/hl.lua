--- Extmark helpers for the common "highlight a region of a line" shapes
--- used across floats, pickers and virtual text.

local M = {}

--- Highlight a byte range [from_col, to_col) on a row.
function M.range(buf, ns, row, from_col, to_col, group, opts)
	opts = vim.tbl_extend("force", { hl_group = group, end_col = to_col }, opts or {})
	vim.api.nvim_buf_set_extmark(buf, ns, row, from_col, opts)
end

--- Highlight an entire line (its text, EOL and sign-column background).
function M.line(buf, ns, row, group, opts)
	opts = vim.tbl_extend("force", { line_hl_group = group }, opts or {})
	vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
end

--- Draw `text` in the sign column of `row`.
function M.sign(buf, ns, row, text, group, opts)
	opts = vim.tbl_extend("force", { sign_text = text, sign_hl_group = group }, opts or {})
	vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
end

--- Highlight from a column to the end of a row.
function M.eol(buf, ns, row, col, group, opts)
	opts = vim.tbl_extend("force", { hl_group = group, hl_eol = true }, opts or {})
	vim.api.nvim_buf_set_extmark(buf, ns, row, col, opts)
end

--- End-of-line virtual text.
function M.virt_text(buf, ns, row, text, group, opts)
	opts = vim.tbl_extend("force", {
		virt_text = { { text, group } },
		virt_text_pos = "eol",
		hl_mode = "combine",
	}, opts or {})
	vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
end

return M
