--- Scratch-buffer helpers.
---
--- Pure: built-in APIs only. One idiom for the `nofile` buffers used across the
--- plugin (floats, pickers, previews, scratch panes).

local M = {}

--- Create an unlisted `nofile` scratch buffer.
--- @param opts? { name?: string, bufhidden?: string, listed?: boolean, modifiable?: boolean, filetype?: string }
--- @return integer bufnr
function M.scratch(opts)
	opts = opts or {}
	local listed = opts.listed == true
	local bufnr = vim.api.nvim_create_buf(listed, true)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = opts.bufhidden or "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].buflisted = listed
	if opts.modifiable ~= nil then
		vim.bo[bufnr].modifiable = opts.modifiable
	end
	if opts.filetype then
		vim.bo[bufnr].filetype = opts.filetype
	end
	if opts.name then
		pcall(vim.api.nvim_buf_set_name, bufnr, opts.name)
	end
	return bufnr
end

--- Set buffer options from a table (bulk form of `vim.bo[buf][k] = v`).
function M.set(bufnr, opts)
	for k, v in pairs(opts or {}) do
		vim.bo[bufnr][k] = v
	end
end

return M
