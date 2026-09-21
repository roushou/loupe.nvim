--- Jump to a candidate's file and position, reusing an already-loaded buffer.
---
--- The session uses this for any candidate carrying `lnum` (grep, symbols,
--- diagnostics). Unlike the default open, it does not `:edit` (which would
--- reload the file and lose unsaved changes) — it switches to the existing
--- buffer and centers the target line.
---
--- Ordering matters to avoid a visible "load at line 1, then jump" flash: for
--- the common `edit` case the origin window is switched and positioned *before*
--- the picker (and its preview overlay) is torn down, so the change is hidden
--- and the file is already on the target line when it becomes visible.

local M = {}

--- Place the cursor at `cand`'s location in `win` and center it. When
--- `topline` is given (the preview's current view), match it instead so the
--- reveal is seamless — the preview and the real window have different heights,
--- so centering them independently would visibly shift the text.
local function place(win, cand, topline)
	local buf = vim.api.nvim_win_get_buf(win)
	local lnum = math.max(1, cand.lnum or 1)
	local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
	local col = math.max(0, math.min(cand.col or 0, #line))
	vim.api.nvim_win_call(win, function()
		if topline then
			vim.fn.winrestview({ topline = topline, lnum = lnum, col = col, curswant = col })
		else
			vim.api.nvim_win_set_cursor(0, { lnum, col })
			vim.cmd("normal! zvzz")
		end
	end)
end

--- Switch `win` to the candidate's file and position it.
local function show(win, cand, topline)
	local buf = vim.fn.bufadd(cand.abs)
	vim.bo[buf].buflisted = true
	vim.api.nvim_win_set_buf(win, buf)
	place(win, cand, topline)
end

--- @param cand loupe.Candidate
--- @param kind "edit"|"split"|"vsplit"|"tab"
--- @param ctx table  session context with `session` and `close`
--- @return boolean false  (the picker closes)
function M.choose(cand, kind, ctx)
	local origin = ctx.session.origin_win

	if kind == "edit" and origin and vim.api.nvim_win_is_valid(origin) then
		-- Adopt the preview's exact view while it still covers the window, then
		-- re-apply it after teardown: closing the drawer grows the window and
		-- Neovim re-centers the cursor line, which would otherwise appear as a
		-- scroll on reveal. Both happen in one synchronous turn, so only the
		-- final (seamless) state is ever drawn.
		local top = require("loupe.preview").topline()
		show(origin, cand, top)
		ctx.close({ restore_cursor = false })
		place(origin, cand, top)
		return false
	end

	ctx.close()
	if kind == "split" then
		vim.cmd("split")
	elseif kind == "vsplit" then
		vim.cmd("vsplit")
	elseif kind == "tab" then
		vim.cmd("tabnew")
	end
	show(vim.api.nvim_get_current_win(), cand)
	return false
end

return M
