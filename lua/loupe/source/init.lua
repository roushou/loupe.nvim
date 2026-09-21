--- Source registry.
---
--- A source is a named mode of the picker (`files`, `dirs`, `buffers`,
--- `recent`, `changed`, later `grep` / `symbols`). It knows how to produce
--- candidates, either through a backend `list` operation (string `list`) or a
--- self-contained loader (`list` function). Matching, drawing, previewing and
--- opening stay generic; only the candidate list is source-specific.

local backend = require("loupe.backend")

local M = { registry = {} }

--- Register a source definition.
function M.register(src)
	M.registry[src.name] = src
	return src
end

--- Look up a source by name.
function M.get(name)
	return M.registry[name]
end

--- Load candidates for `source`. `ctx` is `{ root, buf, name }`.
--- Calls `cb(cands, ok, backend_id)`.
function M.load(source, ctx, cb)
	if type(source.list) == "function" then
		source.list(ctx, cb)
		return
	end
	local op = source.list or source.name
	local id, fn = backend.resolve(op, source.backend)
	if not fn then
		cb({}, false, id)
		return
	end
	fn(ctx, function(cands, ok)
		cb(cands, ok, id)
	end)
end

--- Search `source` for `query` under `ctx` (dynamic sources).
--- Calls `cb(cands, ok, backend_id)`.
function M.search(source, query, ctx, cb)
	if type(source.search) == "function" then
		source.search(query, ctx, cb)
		return
	end
	local op = source.search or source.name
	local id, fn = backend.resolve(op, source.backend, "search")
	if not fn then
		cb({}, false, id)
		return
	end
	fn(query, ctx, function(cands, ok)
		cb(cands, ok, id)
	end)
end

M.register(require("loupe.source.files"))
M.register(require("loupe.source.dirs"))
M.register(require("loupe.source.buffers"))
M.register(require("loupe.source.recent"))
M.register(require("loupe.source.changed"))
M.register(require("loupe.source.grep"))
M.register(require("loupe.source.symbols"))
M.register(require("loupe.source.doc_symbols"))
M.register(require("loupe.source.diagnostics"))

return M
