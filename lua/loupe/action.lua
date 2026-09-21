--- File operations on the highlighted entry.
---
--- Every operation is rooted at `ctx.root`; `ctx.item` is the current match's
--- candidate. Functions return the relative path to focus afterwards (or true
--- for a plain mutation), and nil/false when nothing changed.

local config = require("loupe.config")
local notify = require("loupe.util.notify").scoped("loupe")

local M = {}

local function parent(path)
	return vim.fn.fnamemodify(path, ":h")
end

--- Remove `cand` from the session's candidate list.
local function drop(ctx, cand)
	local cands = ctx.session.candidates
	for i, c in ipairs(cands) do
		if c == cand then
			table.remove(cands, i)
			return
		end
	end
end

--- Rename/move the current entry to `newrel` (relative to root). This is also
--- the "move" action: the target path may point into another directory.
function M.rename(ctx, newrel)
	local cand = ctx.item.cand
	if newrel == "" or newrel == cand.rel then
		return nil
	end
	local newabs = vim.fs.joinpath(ctx.root, newrel)
	if vim.uv.fs_stat(newabs) then
		notify("already exists: " .. newrel, vim.log.levels.WARN)
		return nil
	end
	vim.fn.mkdir(parent(newabs), "p")
	local ok, err = vim.uv.fs_rename(cand.abs, newabs)
	if not ok then
		notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end
	-- Keep an already-open buffer pointed at the new path.
	local buf = vim.fn.bufnr(cand.abs)
	if buf ~= -1 then
		pcall(vim.api.nvim_buf_set_name, buf, newabs)
	end
	cand.rel, cand.abs = newrel, newabs
	notify("renamed to " .. newrel)
	return newrel
end

--- Move `abs` to the trash if a supported tool is available.
local function trash(abs)
	for _, cmd in ipairs({ { "gio", "trash", "--", abs }, { "trash", "--", abs } }) do
		if vim.fn.executable(cmd[1]) == 1 then
			local res = vim.system(cmd, { text = true }):wait()
			if res.code == 0 then
				return true
			end
		end
	end
	return false
end

--- Delete the current entry. Files go to the trash when enabled and available,
--- otherwise they are unlinked. Directories are only removed via the trash.
function M.delete(ctx)
	local cand = ctx.item.cand
	if config.get().trash and trash(cand.abs) then
		drop(ctx, cand)
		notify("trashed " .. cand.rel)
		return true
	end
	if cand.dir then
		notify("refusing to delete a directory", vim.log.levels.WARN)
		return false
	end
	local ok, err = vim.uv.fs_unlink(cand.abs)
	if not ok then
		notify("delete failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	drop(ctx, cand)
	notify("deleted " .. cand.rel)
	return true
end

--- Create a file at `newrel`, or a directory when `newrel` ends with `/`.
--- Returns the relative path so the caller can focus it.
function M.create(ctx, newrel)
	if newrel == "" then
		return nil
	end
	local is_dir = newrel:sub(-1) == "/"
	local rel = is_dir and newrel:sub(1, -2) or newrel
	if rel == "" then
		return nil
	end
	local newabs = vim.fs.joinpath(ctx.root, rel)
	if vim.uv.fs_stat(newabs) then
		notify("already exists: " .. rel, vim.log.levels.WARN)
		return nil
	end
	if is_dir then
		vim.fn.mkdir(newabs, "p")
	else
		vim.fn.mkdir(parent(newabs), "p")
		vim.fn.writefile({}, newabs)
	end
	table.insert(ctx.session.candidates, 1, { rel = rel, abs = newabs, dir = is_dir })
	notify((is_dir and "created directory " or "created ") .. rel)
	return rel
end

--- Copy the current file to `newrel`, leaving the original in place.
function M.duplicate(ctx, newrel)
	if newrel == "" then
		return nil
	end
	local cand = ctx.item.cand
	if cand.dir then
		notify("cannot duplicate a directory", vim.log.levels.WARN)
		return nil
	end
	local newabs = vim.fs.joinpath(ctx.root, newrel)
	if vim.uv.fs_stat(newabs) then
		notify("already exists: " .. newrel, vim.log.levels.WARN)
		return nil
	end
	vim.fn.mkdir(parent(newabs), "p")
	local ok, err = vim.uv.fs_copyfile(cand.abs, newabs)
	if not ok then
		notify("duplicate failed: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end
	table.insert(ctx.session.candidates, 1, { rel = newrel, abs = newabs, dir = false })
	notify("duplicated to " .. newrel)
	return newrel
end

--- Hand the current entry to the OS default handler.
function M.open_external(ctx)
	local _, err = vim.ui.open(ctx.item.cand.abs)
	if err then
		notify("open failed: " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Yank a path derived from the current entry to the unnamed and clipboard
--- registers. `variant` is "abs" (default), "rel", "name" or "dir".
function M.yank(ctx, variant)
	local c = ctx.item.cand
	local path
	if variant == "rel" then
		path = c.rel
	elseif variant == "name" then
		path = vim.fn.fnamemodify(c.abs, ":t")
	elseif variant == "dir" then
		path = vim.fn.fnamemodify(c.abs, ":h")
	else
		path = c.abs
	end
	vim.fn.setreg('"', path)
	vim.fn.setreg("+", path)
	notify("yanked " .. path)
end

--- Put `cands` into the quickfix list.
function M.quickfix(cands)
	local entries = {}
	for _, c in ipairs(cands) do
		entries[#entries + 1] = {
			filename = c.abs,
			lnum = c.lnum or 1,
			col = (c.col or 0) + 1,
			text = c.label or c.rel,
		}
	end
	if #entries == 0 then
		return
	end
	vim.fn.setqflist({}, " ", { items = entries, title = "Loupe" })
	notify(("%d location(s) → quickfix"):format(#entries))
end

return M
