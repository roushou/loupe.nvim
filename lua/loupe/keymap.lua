--- Key-binding resolution for loupe.
---
--- `config.mappings` stores `{ [lhs] = action }` maps grouped by context.
--- Dispatch compares against `vim.fn.keytrans()` output, so every configured
--- lhs is normalized through `vim.keycode()` + `keytrans()` first. That lets
--- users write `<C-s>` or `<C-S>` interchangeably and keeps the lookup key
--- identical to the one produced by the input loop.
---
--- Pure: built-in APIs only (no windows, buffers or external tools).

local M = {}

--- Canonicalize a key notation to the form `vim.fn.keytrans()` emits.
--- Falls back to the input verbatim when it isn't a recognized notation.
function M.canonical(lhs)
	local ok, code = pcall(vim.keycode, lhs)
	if ok and type(code) == "string" and code ~= "" then
		local kt = vim.fn.keytrans(code)
		if kt ~= "" then
			return kt
		end
	end
	return lhs
end

--- Build a canonical `{ [key] = action }` map from a raw config map.
--- Non-string values (notably `false`, used to unbind) are dropped.
function M.build(raw)
	local out = {}
	for lhs, action in pairs(raw or {}) do
		if type(action) == "string" then
			out[M.canonical(lhs)] = action
		end
	end
	return out
end

--- Resolve every context from `config.get().mappings`.
--- Returns `{ browse, menu, sources, prompt }` of canonical lookup maps.
function M.resolve(mappings)
	mappings = mappings or {}
	return {
		browse = M.build(mappings.browse),
		menu = M.build(mappings.menu),
		sources = M.build(mappings.sources),
		prompt = M.build(mappings.prompt),
	}
end

return M
