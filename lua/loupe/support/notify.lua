--- Tiny scoped notifier.
---
--- Vendored so the plugin does not depend on a host config's message routing.
--- `M.scoped(scope)` returns a callable with `.info/.warn/.error` and the
--- legacy `notify(msg, level, opts)` form.

local M = {}

function M.scoped(scope)
	local prefix = scope .. ": "
	local api = {}
	function api.info(m, opts)
		vim.notify(prefix .. m, vim.log.levels.INFO, opts)
	end
	function api.warn(m, opts)
		vim.notify(prefix .. m, vim.log.levels.WARN, opts)
	end
	function api.error(m, opts)
		vim.notify(prefix .. m, vim.log.levels.ERROR, opts)
	end
	return setmetatable(api, {
		__call = function(_, m, level, opts)
			vim.notify(prefix .. m, level or vim.log.levels.INFO, opts)
		end,
	})
end

return M
