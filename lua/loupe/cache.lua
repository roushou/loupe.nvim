--- Candidate cache: the last enumeration per (root, source), kept across
--- picker sessions so reopening renders instantly.
---
--- Entries are never trusted as fresh: the session shows a cached list and
--- re-enumerates behind it (stale-while-revalidate), replacing the entry when
--- the fresh list arrives. Sources opt in with `cache = true`; file actions
--- mutate the cached table in place, so it tracks renames and deletes.

local M = {}

local store = {}

local function key(root, name)
	return name .. "\0" .. root
end

--- Cached candidates for `root`/`name`, or nil.
function M.get(root, name)
	return store[key(root, name)]
end

--- Remember `cands` for `root`/`name`.
function M.put(root, name, cands)
	store[key(root, name)] = cands
end

--- Forget everything.
function M.clear()
	store = {}
end

return M
