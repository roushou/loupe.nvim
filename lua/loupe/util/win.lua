--- Window-option helpers.
---
--- Pure: built-in APIs only.

local M = {}

--- Set window options from a table (bulk form of `vim.wo[win][k] = v`).
function M.set(winid, opts)
	for k, v in pairs(opts or {}) do
		vim.wo[winid][k] = v
	end
end

return M
