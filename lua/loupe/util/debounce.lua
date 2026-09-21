--- Debounce helper.
---
--- Pure: built-in APIs only. `M.new(ms, fn)` returns `{ call = fn(...), cancel = fn() }`;
--- rapid `call`s coalesce into a single deferred `fn` with the latest arguments.

local M = {}

local unpack = table.unpack or unpack

--- Create a debounced caller.
function M.new(ms, fn)
	local timer = vim.uv.new_timer()
	local api = {}

	function api:call(...)
		local args = { ... }
		timer:stop()
		timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				fn(unpack(args))
			end)
		)
	end

	function api:cancel()
		timer:stop()
	end

	--- Release the underlying timer. Do not use the caller afterwards.
	function api:close()
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
	end

	return api
end

return M
