--- Source registry.
---
--- A source is a named mode of the picker (`files`, `dirs`, `buffers`,
--- `recent`, `changed`, `grep`, `symbols`, ...). It knows how to produce
--- candidates, either through a backend `list` operation (string `list`) or a
--- self-contained loader (`list` function). Matching, drawing, previewing and
--- opening stay generic; only the candidate list is source-specific.
---
--- `cache = true` keeps the last enumeration across sessions (see
--- `loupe.cache`) so reopening renders before the fresh list arrives.

local backend = require("loupe.backend")

local M = { registry = {}, order = {} }

--- Register a source definition. Registration order is the order the tab
--- strip shows them in.
function M.register(src)
	M.registry[src.name] = src
	M.order[#M.order + 1] = src
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

--- Search `source` for `query` under `ctx` (dynamic sources). `ctx.limit`
--- asks for at most that many candidates.
---
--- Calls `cb(cands, ok, meta)` with `meta = { backend, done, truncated }`. A
--- streaming backend calls it several times with the growing list and
--- `done = false`, then once more with `done = true`; `truncated` means the
--- backend stopped at `ctx.limit`. Returns the backend's cancel function when
--- it has one.
function M.search(source, query, ctx, cb)
	local id, fn
	if type(source.search) == "function" then
		id, fn = source.name, source.search
	else
		local op = source.search or source.name
		id, fn = backend.resolve(op, source.backend, "search")
	end
	if not fn then
		cb({}, false, { backend = id, done = true, truncated = false })
		return
	end
	return fn(query, ctx, function(cands, ok, done, truncated)
		cb(cands, ok, { backend = id, done = done ~= false, truncated = truncated == true })
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
