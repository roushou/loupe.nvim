--- Row content: what a candidate contributes to a drawn line.
---
--- The drawer owns geometry (padding, truncation, alignment); this module owns
--- what a row *says*. A row is an icon, a dimmed parent directory, the name
--- itself, and a right-hand column of dim metadata chunks (git status,
--- filetype, buffer flags).
---
--- Keeping the left text byte-identical to the string the matcher ranked
--- (`cand.label or cand.rel`) matters: match positions are byte offsets into
--- it, so splitting the path for highlighting must not rewrite it.

local icons = require("loupe.icons")

local M = {}

-- rel path -> filetype name. vim.filetype.match is the expensive part of a
-- redraw and a path's type never changes.
local ft_memo = {}

--- Filetype name for `rel`, or "" when unknown.
function M.filetype(rel)
	local hit = ft_memo[rel]
	if hit == nil then
		hit = vim.filetype.match({ filename = rel }) or ""
		ft_memo[rel] = hit
	end
	return hit
end

--- Split a relative path into a dimmed leading directory and the name.
local function split_path(text)
	local dir, name = text:match("^(.*/)([^/]*)$")
	if not dir then
		return "", text
	end
	return dir, name
end

--- Right-hand chunks for a candidate: `{ text, hl_group }` pairs, left to
--- right. Nothing here is load-bearing, so every chunk is optional.
local function meta(cand, ctx)
	local out = {}
	if ctx.git and not cand.dir then
		local st = ctx.git[cand.rel]
		if st then
			out[#out + 1] = { st.text, st.hl }
		end
	end
	if cand.bufnr and vim.api.nvim_buf_is_valid(cand.bufnr) and vim.bo[cand.bufnr].modified then
		out[#out + 1] = { "+", "LoupeMetaFlag" }
	end
	if not cand.dir then
		local ft = M.filetype(cand.rel)
		if ft ~= "" then
			out[#out + 1] = { ft, "LoupeMeta" }
		end
	end
	return out
end

--- Parts of the row for `cand`. `ctx` is `{ git, icons }`.
--- @return table { icon, icon_hl, dir, name, meta }
function M.row(cand, ctx)
	ctx = ctx or {}
	local dir, name
	if cand.label then
		dir, name = "", cand.label
	else
		dir, name = split_path(cand.rel)
	end
	if cand.dir and not name:match("/$") then
		name = name .. "/"
	end
	local icon, icon_hl = "", nil
	if ctx.icons ~= false then
		icon, icon_hl = icons.for_candidate(cand)
	end
	return {
		icon = icon,
		icon_hl = icon_hl,
		dir = dir,
		name = name,
		meta = meta(cand, ctx),
	}
end

return M
