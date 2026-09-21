--- Async `git status` for the result list.
---
--- Runs once per session (and per re-root), returns a map of root-relative path
--- to a short marker + highlight group. Parsing uses the NUL-delimited
--- porcelain format so paths with spaces are preserved.

local M = {}

local proc = require("loupe.util.proc")

local function tokens(s)
	local out, i = {}, 1
	while true do
		local j = s:find("\0", i, true)
		if not j then
			break
		end
		out[#out + 1] = s:sub(i, j - 1)
		i = j + 1
	end
	return out
end

local function classify(xy)
	local x, y = xy:sub(1, 1), xy:sub(2, 2)
	if x == "?" and y == "?" then
		return { text = "??", hl = "LoupeGitNew" }
	end
	if x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
		return { text = "!!", hl = "LoupeGitDel" }
	end
	if x == "R" or x == "C" then
		return { text = "R", hl = "LoupeGitRename" }
	end
	if x == "A" then
		return { text = "A", hl = "LoupeGitAdd" }
	end
	if x == "D" or y == "D" then
		return { text = "D", hl = "LoupeGitDel" }
	end
	if x == "M" or y == "M" then
		return { text = "M", hl = "LoupeGitMod" }
	end
	return nil
end

--- Call `on_done(map)` with `map[rel] = { text, hl }` (empty when not a repo).
function M.status(root, on_done)
	local ok = proc.async(
		{ "git", "status", "--porcelain", "-z", "--untracked-files=all" },
		{ cwd = root },
		function(res)
			if res.code ~= 0 then
				vim.schedule(function()
					on_done({})
				end)
				return
			end
			local map = {}
			local toks = tokens(res.stdout or "")
			local i = 1
			while i <= #toks do
				local entry = toks[i]
				local xy = entry:sub(1, 2)
				local path = entry:sub(4)
				local info = classify(xy)
				if info and path ~= "" then
					map[path] = info
				end
				-- rename/copy records carry the original path as the next token
				i = i + (xy:find("[RC]") and 2 or 1)
			end
			vim.schedule(function()
				on_done(map)
			end)
		end
	)
	if not ok then
		on_done({})
	end
end

return M
