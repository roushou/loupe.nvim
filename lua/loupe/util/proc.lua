--- Process helpers around |vim.system()|.
---
--- Pure: built-in APIs only. Normalizes `text = true`, exit-code handling and
--- empty-line splitting so callers don't repeat it.

local M = {}

local function trim(s)
	return s and (s:gsub("%s+$", "")) or nil
end

--- Run `cmd` synchronously.
--- Returns `stdout, err`; `err` is nil on success, stderr (or exit code) otherwise.
function M.sync(cmd, opts)
	opts = vim.tbl_extend("force", { text = true }, opts or {})
	local ok, res = pcall(vim.system, cmd, opts)
	if not ok then
		return nil, tostring(res)
	end
	local out = res:wait()
	if out.code ~= 0 then
		return nil, trim(out.stderr) or ("exit code " .. out.code)
	end
	return out.stdout, nil
end

--- Run `cmd` synchronously and split stdout into non-empty lines.
--- Returns `lines, err`.
function M.lines(cmd, opts)
	local out, err = M.sync(cmd, opts)
	if not out then
		return nil, err
	end
	local lines = {}
	for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
		if line ~= "" then
			lines[#lines + 1] = line
		end
	end
	return lines, nil
end

--- Run `cmd` asynchronously. `cb(res)` receives the |vim.system()| result.
--- Returns true when the process was spawned, false otherwise.
function M.async(cmd, opts, cb)
	opts = vim.tbl_extend("force", { text = true }, opts or {})
	return (pcall(vim.system, cmd, opts, cb))
end

return M
