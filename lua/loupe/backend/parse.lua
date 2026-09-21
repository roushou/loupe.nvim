--- Output parsing shared by the enumeration backends.
---
--- All backends talk in newline-delimited, root-relative paths, so a single
--- parser covers fd, rg and git. Candidate shape is the one the session,
--- drawer and icons expect: `{ rel, abs, dir }`.

local run = require("loupe.backend.run")

local M = {}

--- Build a candidate from a root-relative path.
function M.candidate(root, rel, dir)
	return { rel = rel, abs = vim.fs.joinpath(root, rel), dir = dir == true }
end

--- Parse newline-delimited root-relative paths into deduped candidates.
--- Strips a leading `./` and, for directories, the trailing `/` fd emits.
function M.paths(stdout, root, dir)
	local seen, out = {}, {}
	for _, raw in ipairs(run.lines(stdout)) do
		local rel = raw:gsub("^%./", "")
		if dir then
			rel = rel:gsub("/$", "")
		end
		if rel ~= "" and not seen[rel] then
			seen[rel] = true
			out[#out + 1] = M.candidate(root, rel, dir)
		end
	end
	return out
end

--- Derive the set of parent directories from a file list (fd-less fallback).
function M.derive_dirs(files, root)
	local seen, out = {}, {}
	for _, c in ipairs(files) do
		local dir = c.rel:match("^(.*)/[^/]+$")
		if dir and not seen[dir] then
			seen[dir] = true
			out[#out + 1] = M.candidate(root, dir, true)
		end
	end
	return out
end

--- Path of `abs` relative to `root` (basename when outside the root).
function M.relpath(root, abs)
	if abs:sub(1, #root + 1) == root .. "/" then
		return abs:sub(#root + 2)
	end
	return vim.fn.fnamemodify(abs, ":t")
end

--- Parse `git status --porcelain -z` into changed-file candidates. NUL framing
--- preserves paths with spaces; rename/copy records carry the original path
--- as a second token, which is skipped.
function M.status(stdout, root)
	local toks, out = {}, {}
	local s, i = stdout or "", 1
	while true do
		local j = s:find("\0", i, true)
		if not j then
			break
		end
		toks[#toks + 1] = s:sub(i, j - 1)
		i = j + 1
	end
	local n = 1
	while n <= #toks do
		local entry = toks[n]
		local xy = entry:sub(1, 2)
		local rel = entry:sub(4)
		if rel ~= "" then
			out[#out + 1] = { rel = rel, abs = vim.fs.joinpath(root, rel), label = rel, dir = false }
		end
		n = n + (xy:find("[RC]") and 2 or 1)
	end
	return out
end

--- Parse `rg --json` (NDJSON) match events into candidates. Each submatch
--- becomes a candidate carrying the exact byte range (`col`..`col_end`) so the
--- preview can highlight the occurrence. Handles text and base64 byte paths.
function M.rgjson(stdout, root)
	local out = {}
	for _, line in ipairs(run.lines(stdout)) do
		local ok, ev = pcall(vim.json.decode, line)
		if ok and type(ev) == "table" and ev.type == "match" then
			local d = ev.data or {}
			local path = d.path and (d.path.text or (d.path.bytes and vim.base64.decode(d.path.bytes)))
			local text = d.lines and (d.lines.text or (d.lines.bytes and vim.base64.decode(d.lines.bytes)))
			if path and text then
				text = text:gsub("\r?\n$", "")
				local lnum = d.line_number or 1
				for _, sm in ipairs(d.submatches or {}) do
					local from = sm.start or 0
					local to = sm["end"] or from
					out[#out + 1] = {
						rel = path,
						abs = vim.fs.joinpath(root, path),
						label = path .. ":" .. lnum .. ": " .. text,
						lnum = lnum,
						col = from,
						col_end = to,
						dir = false,
					}
				end
			end
		end
	end
	return out
end

--- Parse `git grep -n` output (`path:line:text`) into candidates (no column).
function M.gitgrep(stdout, root)
	local out = {}
	for _, line in ipairs(run.lines(stdout)) do
		local rel, lnum, text = line:match("^(.-):(%d+):(.*)$")
		if rel then
			out[#out + 1] = {
				rel = rel,
				abs = vim.fs.joinpath(root, rel),
				label = rel .. ":" .. lnum .. ": " .. text,
				lnum = tonumber(lnum),
				col = 0,
				dir = false,
			}
		end
	end
	return out
end

return M
