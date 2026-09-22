--- Frecency store: rank files by how often and how recently they were opened.
---
--- Persisted as JSON under `stdpath("state")`. Keys are absolute paths so the
--- same file is shared across sessions; the ranking is only used to order the
--- empty-query list, never to reorder fuzzy matches.

local M = {}

--- Store location; tests point it elsewhere.
M.path = vim.fn.stdpath("state") .. "/loupe_frecency.json"

--- @type table<string, { count: number, last: number }>|nil
local data = nil
local loaded_from = nil

local function load()
	if data and loaded_from == M.path then
		return data
	end
	data = {}
	loaded_from = M.path
	local ok, lines = pcall(vim.fn.readfile, M.path)
	if ok and lines and lines[1] then
		local okd, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
		if okd and type(decoded) == "table" then
			data = decoded
		end
	end
	return data
end

local function save()
	local f = io.open(M.path, "w")
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

--- Frecency scores of the candidates that have one, computed once.
local function scores(cands)
	local d = load()
	local out = {}
	for _, c in ipairs(cands) do
		if d[c.abs] then
			out[c.abs] = M.score(c.abs)
		end
	end
	return out
end

--- Sort candidates by frecency (then alphabetically). Returns the same table.
function M.sort(cands)
	local s = scores(cands)
	table.sort(cands, function(a, b)
		local sa, sb = s[a.abs] or 0, s[b.abs] or 0
		if sa ~= sb then
			return sa > sb
		end
		return a.rel < b.rel
	end)
	return cands
end

--- Move the scored candidates to the front of an otherwise sorted list,
--- keeping the rest in place. Linear, for lists `sort` already ordered.
--- Returns a new table.
function M.promote(cands)
	local s = scores(cands)
	if next(s) == nil then
		return cands
	end
	local top, rest = {}, {}
	for _, c in ipairs(cands) do
		if s[c.abs] then
			top[#top + 1] = c
		else
			rest[#rest + 1] = c
		end
	end
	table.sort(top, function(a, b)
		if s[a.abs] ~= s[b.abs] then
			return s[a.abs] > s[b.abs]
		end
		return a.rel < b.rel
	end)
	return vim.list_extend(top, rest)
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
