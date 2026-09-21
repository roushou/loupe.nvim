--- Frecency store: rank files by how often and how recently they were opened.
---
--- Persisted as JSON under `stdpath("state")`. Keys are absolute paths so the
--- same file is shared across sessions; the ranking is only used to order the
--- empty-query list, never to reorder fuzzy matches.

local M = {}

local state_path = vim.fn.stdpath("state") .. "/loupe_frecency.json"

--- @type table<string, { count: number, last: number }>|nil
local data = nil

local function load()
	if data then
		return data
	end
	data = {}
	local ok, lines = pcall(vim.fn.readfile, state_path)
	if ok and lines and lines[1] then
		local okd, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
		if okd and type(decoded) == "table" then
			data = decoded
		end
	end
	return data
end

local function save()
	local f = io.open(state_path, "w")
	if not f then
		return
	end
	f:write(vim.json.encode(load()))
	f:close()
end

--- Record that `abs` was chosen.
function M.record(abs)
	local d = load()
	local entry = d[abs] or { count = 0, last = 0 }
	entry.count = entry.count + 1
	entry.last = os.time()
	d[abs] = entry
	save()
end

--- Frecency score: recency buckets + access count.
function M.score(abs)
	local entry = load()[abs]
	if not entry then
		return 0
	end
	local age = os.time() - (entry.last or 0)
	local recency
	if age < 3600 then
		recency = 100
	elseif age < 86400 then
		recency = 50
	elseif age < 604800 then
		recency = 20
	else
		recency = 5
	end
	return (entry.count or 0) * 10 + recency
end

--- Sort candidates by frecency (then alphabetically). Returns the same table.
function M.sort(cands)
	table.sort(cands, function(a, b)
		local sa, sb = M.score(a.abs), M.score(b.abs)
		if sa ~= sb then
			return sa > sb
		end
		return a.rel < b.rel
	end)
	return cands
end

--- Candidates for files under `root`, most recent/frequent first.
--- `limit` caps the result (all when nil).
function M.recent(root, limit)
	local prefix = root .. "/"
	local out = {}
	for abs in pairs(load()) do
		if abs:sub(1, #prefix) == prefix then
			local rel = abs:sub(#prefix + 1)
			out[#out + 1] = { rel = rel, abs = abs, label = rel, dir = false }
		end
	end
	table.sort(out, function(a, b)
		local sa, sb = M.score(a.abs), M.score(b.abs)
		if sa ~= sb then
			return sa > sb
		end
		return a.rel < b.rel
	end)
	if limit and #out > limit then
		out = vim.list_slice(out, 1, limit)
	end
	return out
end

return M
