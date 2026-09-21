--- Fuzzy ranking for loupe.
---
--- Static sources enumerate once and rank client-side with
--- |vim.fn.matchfuzzypos()| (C-implemented, returns per-character positions
--- for highlighting). The optional `fff` Rust engine performs its own search
--- and is selected with `config.backend == "fff"`.

local config = require("loupe.config")

local M = {}

--- Text fuzzy matching runs against; `label` wins when a source sets one.
local function key(cand)
	return cand.label or cand.rel
end

--- Rank `cands` against `query`, returning at most `max` `{ cand, positions }`.
function M.fuzzy(query, cands, max)
	local out = {}
	if query == "" then
		for i = 1, math.min(max, #cands) do
			out[i] = { cand = cands[i], positions = {} }
		end
		return out
	end

	local by_key, keys = {}, {}
	for _, c in ipairs(cands) do
		local k = key(c)
		by_key[k] = c
		keys[#keys + 1] = k
	end

	-- matchfuzzypos returns a single 3-element list: { matches, positions, scores }.
	local res = vim.fn.matchfuzzypos(keys, query)
	local matches, positions = res[1], res[2]
	for i = 1, math.min(max, #matches) do
		local cand = by_key[matches[i]]
		if cand then
			out[#out + 1] = { cand = cand, positions = positions[i] or {} }
		end
	end
	return out
end

--- The `fff` module when selected and installed, else nil.
function M.fff_module()
	if config.get().backend ~= "fff" then
		return nil
	end
	local ok, mod = pcall(require, "fff")
	if ok and type(mod.file_search) == "function" then
		return mod
	end
	return nil
end

--- Run the fff engine, mapping its items to the loupe candidate shape.
function M.fff_search(mod, query, max, ctx)
	local mode = ctx and ctx.mode == "dirs" and "directories" or "files"
	local ok, res = pcall(mod.file_search, query, {
		cwd = ctx and ctx.root or nil,
		mode = mode,
		max_results = max,
	})
	if not ok or type(res) ~= "table" then
		return nil
	end
	local out = {}
	for _, item in ipairs(res.items or {}) do
		local rel = item.relative_path
		if rel then
			out[#out + 1] = {
				cand = {
					rel = rel,
					abs = ctx and ctx.root and (ctx.root .. "/" .. rel) or rel,
					dir = item.type == "directory",
				},
				positions = {},
			}
		end
	end
	return out
end

--- Rank `cands` against `query`; fff when selected, fuzzy otherwise.
function M.match(query, cands, max, ctx)
	local mod = M.fff_module()
	if mod then
		local res = M.fff_search(mod, query, max, ctx)
		if res then
			return res
		end
	end
	return M.fuzzy(query, cands, max)
end

return M
