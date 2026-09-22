--- Bottom drawer: a real horizontal split holding the result list.
---
--- The list buffer is a `nofile` scratch buffer (never listed, never written to
--- disk). Rendering is a full redraw on each key: prompt line + one line per
--- ranked match, with matched characters, icons and git markers highlighted.

local hl = require("loupe.util.hl")
local buf = require("loupe.util.buf")
local win = require("loupe.util.win")
local icons = require("loupe.icons")
local parse = require("loupe.backend.parse")

local M = {}

local ns = vim.api.nvim_create_namespace("loupe_matches")

local function define_highlights()
	vim.api.nvim_set_hl(0, "LoupeMatch", { link = "Search", default = true })
	vim.api.nvim_set_hl(0, "LoupeMark", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "LoupePrompt", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "LoupePromptCaret", { link = "LoupePrompt", default = true })
	vim.api.nvim_set_hl(0, "LoupeCursor", { blend = 100, nocombine = true })
	vim.api.nvim_set_hl(0, "LoupeBorder", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitMod", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitAdd", { link = "DiagnosticOk", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitDel", { link = "DiagnosticError", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitNew", { link = "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitRename", { link = "DiagnosticInfo", default = true })
end

--- Open the split at `height` lines and return { win, buf }.
function M.open(height)
	define_highlights()

	local bufnr = buf.scratch({ bufhidden = "wipe" })

	vim.cmd(("botright %dsplit"):format(height))
	local winid = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(winid, bufnr)

	win.set(winid, {
		winfixheight = true,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		wrap = false,
		cursorline = true,
		foldenable = false,
		spell = false,
		list = false,
		scrolloff = 0,
		winhighlight = "Normal:Normal,WinBar:LoupeBorder,WinBarNC:LoupeBorder",
		winbar = "─ Loupe ",
	})

	return { win = winid, buf = bufnr }
end

--- Sorted `[key]action` hints for a mapping context.
local function menu_hints(cfg, context)
	local map = (cfg.mappings and cfg.mappings[context]) or {}
	local keys = vim.tbl_keys(map)
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = "[" .. k .. "]" .. tostring(map[k])
	end
	return "   " .. table.concat(parts, "  ")
end

--- Build the header line (prompt, query, caret, submenu hint) plus the prefix
--- highlight width and the caret's start column.
local function header(session, cfg)
	local caret = cfg.prompt_caret or "▏"
	if session.prompt then
		local value = session.prompt.value or ""
		local c = session.prompt.caret or vim.fn.strchars(value)
		local text = session.prompt.label .. vim.fn.strcharpart(value, 0, c)
		return text .. caret .. vim.fn.strcharpart(value, c), #session.prompt.label, #text
	end

	local query = session.query or ""
	local c = session.caret or vim.fn.strchars(query)
	local text = cfg.prompt .. vim.fn.strcharpart(query, 0, c)
	local caret_start = #text
	text = text .. caret .. vim.fn.strcharpart(query, c)
	if session.menu == "actions" then
		text = text .. menu_hints(cfg, "menu")
	elseif session.menu == "sources" then
		text = text .. menu_hints(cfg, "sources")
	end
	return text, #cfg.prompt, caret_start
end

--- Build the buffer lines plus per-line highlight metadata.
local function build(session, cfg)
	local head, head_hl, caret_start = header(session, cfg)
	local lines = { head }
	local meta = {}

	if not session.loaded then
		lines[#lines + 1] = "  (loading…)"
	elseif #session.matches == 0 then
		lines[#lines + 1] = "  (no matches)"
	else
		local has_marks = session.marked and next(session.marked) ~= nil
		for _, m in ipairs(session.matches) do
			local cand = m.cand
			local mark = ""
			if has_marks then
				mark = session.marked[cand.abs] and "● " or "  "
			end
			local icon, icon_hl = "", nil
			if cfg.icons then
				icon, icon_hl = icons.for_candidate(cand)
			end
			local prefix = mark .. (icon ~= "" and (icon .. " ") or "")

			local label = cand.label or cand.rel
			if cand.dir and not label:match("/$") then
				label = label .. "/"
			end
			local line = prefix .. label
			local git_start, git_len, git_hl

			if cfg.git and session.git and not cand.dir then
				local st = session.git[cand.rel]
				if st then
					git_start = #line + 2
					line = line .. "  " .. st.text
					git_len, git_hl = #st.text, st.hl
				end
			end

			lines[#lines + 1] = line
			meta[#meta + 1] = {
				prefix = #prefix,
				mark = has_marks and (session.marked[cand.abs] and 2 or 0) or 0,
				icon = #icon,
				icon_start = #mark,
				icon_hl = icon_hl,
				git_start = git_start,
				git_len = git_len,
				git_hl = git_hl,
			}
		end
	end
	return lines, meta, head_hl, caret_start
end

--- Title segments: source, `shown/total` (static) or `found[+]` (dynamic,
--- with `…` while still streaming) and the root when browsing away from the
--- project root.
function M.title(session)
	local parts = { "Loupe", (session.source and session.source.label) or "" }
	local shown, total = #session.matches, #(session.candidates or {})
	local count
	if session.source and session.source.search then
		count = tostring(total) .. (session.truncated and "+" or "") .. (session.searching and " …" or "")
	elseif not session.loaded then
		count = "…"
	elseif total > shown then
		count = shown .. "/" .. total
	else
		count = tostring(shown)
	end
	parts[#parts + 1] = count
	if session.root and session.project_root and session.root ~= session.project_root then
		local rel = parse.relpath(session.project_root, session.root)
		local inside = session.root:sub(1, #session.project_root + 1) == session.project_root .. "/"
		parts[#parts + 1] = inside and (rel .. "/") or vim.fn.fnamemodify(session.root, ":~")
	end
	return parts
end

--- Redraw prompt, matches and selection.
function M.render(session, cfg)
	local buf = session.list_buf
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end

	local lines, meta, head_hl, caret_start = build(session, cfg)

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	hl.range(buf, ns, 0, 0, head_hl, "LoupePrompt")
	if caret_start then
		hl.range(buf, ns, 0, caret_start, caret_start + #(cfg.prompt_caret or "▏"), "LoupePromptCaret")
	end
	for i, m in ipairs(session.matches) do
		local mt = meta[i]
		if mt then
			-- matchfuzzypos columns are 0-based byte offsets; extmark end is exclusive.
			for _, col in ipairs(m.positions) do
				hl.range(buf, ns, i, mt.prefix + col, mt.prefix + col + 1, "LoupeMatch")
			end
			if mt.icon > 0 then
				hl.range(buf, ns, i, mt.icon_start, mt.icon_start + mt.icon, mt.icon_hl)
			end
			if mt.mark and mt.mark > 0 then
				hl.range(buf, ns, i, 0, mt.mark, "LoupeMark")
			end
			if mt.git_start then
				hl.range(buf, ns, i, mt.git_start, mt.git_start + mt.git_len, mt.git_hl)
			end
		end
	end

	local win = session.drawer_win
	if win and vim.api.nvim_win_is_valid(win) then
		local title = " " .. table.concat(M.title(session), " · ") .. " "
		local pad = math.max(0, vim.api.nvim_win_get_width(win) - vim.fn.strchars(title) - 1)
		vim.wo[win].winbar = "─" .. title .. string.rep("─", pad)
	end
	if win and vim.api.nvim_win_is_valid(win) and session.prompt then
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
	elseif win and vim.api.nvim_win_is_valid(win) and session.index >= 1 then
		local row = session.index + 1
		vim.api.nvim_win_set_cursor(win, { row, 0 })
		local topline = vim.fn.line("w0", win)
		local botline = vim.fn.line("w$", win)
		if row < topline or row > botline then
			vim.api.nvim_win_call(win, function()
				vim.cmd("normal! zz")
			end)
		end
	elseif win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
	end

	vim.cmd("redraw")
end

--- Close the split and wipe the list buffer.
function M.close(session)
	if session.drawer_win and vim.api.nvim_win_is_valid(session.drawer_win) then
		vim.api.nvim_win_close(session.drawer_win, true)
	end
	if session.list_buf and vim.api.nvim_buf_is_valid(session.list_buf) then
		pcall(vim.api.nvim_buf_delete, session.list_buf, { force = true })
	end
end

return M
