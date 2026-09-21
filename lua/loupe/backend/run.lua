--- Shared async command runner for the enumeration backends.
---
--- Pure wrapper around |util.proc| plus the two conventions every backend
--- relies on: line splitting and a success flag so callers can fall back to
--- the next preferred backend when a tool is missing or fails.

local proc = require("loupe.util.proc")

local M = {}

--- Split stdout into non-empty lines.
function M.lines(stdout)
	local out = {}
	for _, line in ipairs(vim.split(stdout or "", "\n", { plain = true })) do
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	return out
end

--- Run `argv` in `root`; `parse(stdout)` returns the candidate list.
--- Calls `cb(cands, ok)` with `ok = false` on spawn or exit failure so the
--- caller can cascade to the next backend. Empty-but-successful stays `ok`.
function M.raw(argv, root, parse, cb)
	local spawned = proc.async(argv, { cwd = root }, function(res)
		local ok = res.code == 0
		local cands = ok and parse(res.stdout or "") or {}
		vim.schedule(function()
			cb(cands, ok)
		end)
	end)
	if not spawned then
		cb({}, false)
	end
end

return M
