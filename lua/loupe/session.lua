--- Loupe session: the picker state machine.
---
--- Owns the single active session (`S`), the source/query/match state, the
--- input-loop callbacks and the open/close lifecycle. `require("loupe")` is
--- the public entry point; this module is internal.
---
--- Browsing is side-effect-free: candidate files are read from disk into a
--- reused scratch buffer, never opened as buffers. Only the choose actions
--- (edit/split/vsplit/tab) create a real file buffer.

local config = require("loupe.config")
local backend = require("loupe.backend")
local source = require("loupe.source")
local drawer = require("loupe.drawer")
local preview = require("loupe.preview")
local frecency = require("loupe.frecency")
local cache = require("loupe.cache")
local git = require("loupe.git")
local action = require("loupe.action")
local parse = require("loupe.backend.parse")
local tf = require("loupe.util.textfield")
local debounce = require("loupe.util.debounce")
local input = require("loupe.input")

local M = {}

local S = nil
local run_search
local reload

local function active()
	return S ~= nil and S.active
end

local function current()
	if not S or S.index < 1 or S.index > #S.matches then
		return nil
	end
	return S.matches[S.index]
end

local function page()
	if S.drawer_win and vim.api.nvim_win_is_valid(S.drawer_win) then
		return drawer.capacity(S.drawer_win)
	end
	return 10
end

--- Keep the selection valid, and select the first match once results exist
--- -- but only once the user has aimed at something. A freshly opened picker
--- rests on `index = 0`: selecting on its own would open the preview over the
--- buffer the user was reading, replacing what is on screen with something
--- they never asked to see.
local function normalize_index()
	local n = #S.matches
	if n == 0 then
		S.index = 0
	elseif S.index < 1 then
		S.index = S.aimed and 1 or 0
	elseif S.index > n then
		S.index = n
	end
end

--- Wrap raw dynamic results as matches (no client-side ranking).
local function wrap(cands)
	local out = {}
	local max = config.get().max_results
	for i = 1, math.min(max, #cands) do
		out[i] = { cand = cands[i], positions = {} }
	end
	return out
end

--- Stop the in-flight dynamic search, if any.
local function cancel_search()
	if S.search_cancel then
		S.search_cancel()
		S.search_cancel = nil
	end
	S.searching = false
end

--- Recompute matches for the current query. Static sources are ranked locally;
--- dynamic sources (grep/symbols) re-query the backend, debounced unless
--- `immediate` is set. A search still streaming for the previous query is
--- stopped at once so its results never paint over the new query.
local function refresh(immediate)
	S.gen = S.gen + 1
	if S.source.search then
		cancel_search()
		S.searching = true
		if immediate then
			S.search_timer:cancel()
			run_search()
		else
			S.search_timer:call()
		end
		return
	end
	local matches =
		backend.match(S.query, S.candidates, config.get().max_results, { root = S.root, mode = S.source.name })
	S.matches = matches
	normalize_index()
end

--- Move the selection onto the match with relative path `rel`, if present.
local function focus(rel)
	S.aimed = true
	S.index = 1
	for i, m in ipairs(S.matches) do
		if m.cand.rel == rel then
			S.index = i
			return
		end
	end
end

local function update_preview()
	local cfg = config.get()
	if not cfg.preview.enabled then
		return
	end
	local item = current()
	if item then
		preview.ensure_open(S.drawer_win, S.preview_opts)
		preview.show(item.cand.abs, {
			max_lines = cfg.preview.max_lines,
			max_bytes = cfg.preview.max_bytes,
			diagnostics = cfg.preview.diagnostics,
			lnum = item.cand.lnum,
			col = item.cand.col,
			col_end = item.cand.col_end,
		})
	elseif preview.is_open() then
		preview.clear()
	end
end

local function render()
	-- More keys are already waiting (held or repeated key): the last of them
	-- redraws, so painting now would only be overwritten unseen.
	if input.pending() then
		return
	end
	-- Update the preview *before* the list redraws, otherwise the redraw paints
	-- the stale preview and it only catches up on the next keypress.
	update_preview()
	drawer.render(S, config.get())
end

--- Fire the active dynamic source's search and apply the results.
run_search = function()
	if not active() then
		return
	end
	local session = S
	if not session.source.search then
		return
	end
	local gen = session.gen
	local root, src, query = session.root, session.source, session.query
	local limit = config.get().max_results
	session.searching = true
	session.truncated = false
	local ctx = { root = root, buf = session.origin_buf, name = src.name, limit = limit }
	-- Results may arrive in several batches (streaming backends): each one
	-- replaces the list, keeping the selection where it is.
	session.search_cancel = source.search(src, query, ctx, function(cands, _, meta)
		if S ~= session or session.gen ~= gen or session.root ~= root or session.source ~= src then
			return
		end
		if meta.truncated and #cands > limit then
			cands = vim.list_slice(cands, 1, limit)
		end
		session.candidates = cands
		session.loaded = true
		session.searching = not meta.done
		session.truncated = meta.truncated
		if meta.done then
			session.search_cancel = nil
		end
		session.matches = wrap(cands)
		normalize_index()
		render()
	end)
end

local function move(delta)
	local n = #S.matches
	if n == 0 then
		return
	end
	S.aimed = true
	if S.index == 0 then
		S.index = delta > 0 and 1 or n
		return
	end
	S.index = ((S.index - 1 + delta) % n + n) % n + 1
end

--- Replace the query, reset the selection and refilter (caller redraws).
local function set_query(text, caret)
	S.query = text
	S.caret = caret or tf.len(text)
	-- typing is the ask: from here the picker may point at its own best guess
	S.aimed = true
	S.index = 1
	refresh()
end

local function start_prompt(label, value, name)
	value = value or ""
	S.prompt = { label = label, value = value, action = name, caret = tf.len(value) }
end

--- Switch the active source and reload its candidates.
local function set_source(name)
	local src = source.get(name)
	if not src or src == S.source then
		return
	end
	S.source = src
	S.query = ""
	S.caret = 0
	S.git = nil
	reload()
end

--- Switch to the source `delta` places along the tab strip, wrapping at both
--- ends so the strip can be walked in either direction.
local function cycle_source(delta)
	local order = source.order
	local at
	for i, src in ipairs(order) do
		if src == S.source then
			at = i
			break
		end
	end
	if not at then
		return
	end
	set_source(order[(at - 1 + delta) % #order + 1].name)
end

--- Run a committed action by name and refresh the view.
local function run_action(name, value)
	local item = current()
	if not item then
		return
	end
	local ctx = { session = S, item = item, root = S.root }
	if name == "rename" then
		local rel = action.rename(ctx, value)
		if rel then
			refresh()
			focus(rel)
		end
	elseif name == "delete" then
		if value:lower() == "y" and action.delete(ctx) then
			refresh()
		end
	elseif name == "close_buffer" then
		if value:lower() == "y" and action.close_buffer(ctx, true) then
			refresh()
		end
	elseif name == "create" then
		local rel = action.create(ctx, value)
		if rel then
			S.query = ""
			S.caret = 0
			refresh()
			focus(rel)
		end
	elseif name == "duplicate" then
		local rel = action.duplicate(ctx, value)
		if rel then
			S.query = ""
			S.caret = 0
			refresh()
			focus(rel)
		end
	end
	render()
end

--- (Re)enumerate the current root/source asynchronously and refresh the view.
function reload()
	if not active() then
		return
	end
	local cfg = config.get()
	if S.search_timer then
		S.search_timer:cancel()
	end
	cancel_search()
	S.truncated = false

	local session = S
	local root, src = S.root, S.source
	if src.search then
		S.loaded = false
		S.matches = {}
		S.index = 0
		drawer.render(S, cfg)
		vim.cmd("redraw")
		refresh(true)
		return
	end

	-- A cached enumeration renders at once; the fresh one replaces it below.
	local cached = src.cache and cache.get(root, src.name)
	if cached then
		S.candidates = (cfg.frecency and src.name == "files") and frecency.promote(cached) or cached
		S.loaded = true
		-- back to the top for the new source, or back to rest if the picker
		-- has not been aimed yet
		S.index = S.aimed and 1 or 0
		refresh()
	else
		S.loaded = false
		S.matches = {}
		S.index = 0
	end
	drawer.render(S, cfg)
	vim.cmd("redraw")

	source.load(src, { root = root, buf = session.origin_buf, name = src.name }, function(cands)
		if cfg.frecency and src.name == "files" then
			cands = frecency.sort(cands)
		end
		-- worth keeping even when the picker was closed before it arrived
		if src.cache then
			cache.put(root, src.name, cands)
		end
		if S ~= session or S.root ~= root or S.source ~= src then
			return
		end
		local keep = cached and current()
		S.candidates = cands
		S.loaded = true
		refresh()
		if keep then
			focus(keep.cand.rel)
		end
		render()
	end)

	if cfg.git and src.name == "files" then
		git.status(root, function(map)
			if S == session and S.root == root then
				S.git = map
				render()
			end
		end)
	end
end

--- Begin the delete action for the current entry.
---
--- What `delete` means is the source's to say: a source with
--- `delete = "buffer"` (see `loupe.source.buffers`) closes the buffer, which
--- loses nothing and so needs no confirmation unless the buffer is modified.
--- Everything else removes the file and always asks first.
local function start_delete()
	local item = current()
	if not item then
		return
	end
	local rel = item.cand.rel
	if S.source.delete ~= "buffer" then
		start_prompt("Delete " .. rel .. "? [y/N] ", "", "delete")
		return
	end
	local buf = item.cand.bufnr
	if buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
		start_prompt("Close " .. rel .. " with unsaved changes? [y/N] ", "", "close_buffer")
		return
	end
	if action.close_buffer({ session = S, item = item, root = S.root }) then
		refresh()
	end
end

--- Toggle the mark on the current match.
local function toggle_mark()
	local item = current()
	if not item then
		return
	end
	local key = parse.identity(item.cand)
	if S.marked[key] then
		S.marked[key] = nil
	else
		S.marked[key] = true
	end
end

--- Move the root up one directory.
local function go_parent()
	local parent = vim.fs.dirname(S.root)
	if not parent or parent == "" or parent == S.root then
		return
	end
	S.root = parent
	S.query = ""
	S.caret = 0
	S.git = nil
	S.marked = {}
	reload()
end

--- Reset to the project root resolved when the picker opened.
local function go_root()
	S.root = S.project_root
	S.query = ""
	S.caret = 0
	S.git = nil
	S.marked = {}
	reload()
end

--- Send marked candidates (or the current one) to the quickfix list.
local function quickfix()
	local items = {}
	for _, c in ipairs(S.candidates) do
		if S.marked[parse.identity(c)] then
			items[#items + 1] = c
		end
	end
	if #items == 0 then
		local item = current()
		if not item then
			return
		end
		items = { item.cand }
	end
	action.quickfix(items)
end

--- Close the picker and return to the window it was opened from.
--- `opts.restore_cursor = false` keeps the origin window's current cursor,
--- used when choosing has already positioned it (see `loupe.source.jump`).
function M.close(opts)
	if not active() then
		return
	end
	opts = opts or {}
	local origin = S.origin_win
	local guicursor = S.guicursor
	local cursor = S.origin_cursor
	S.active = false
	cancel_search()
	if S.search_timer then
		S.search_timer:close()
	end
	if S.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, S.augroup)
	end
	preview.close()
	drawer.close(S)
	S = nil
	if guicursor ~= nil then
		pcall(function()
			vim.o.guicursor = guicursor
		end)
	end
	if origin and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
		if cursor and opts.restore_cursor ~= false then
			pcall(vim.api.nvim_win_set_cursor, origin, cursor)
		end
	end
end

--- Open an already-loaded buffer in the target window, reusing it as-is.
local function open_buf(bufnr, kind)
	if kind == "split" then
		vim.cmd("split")
	elseif kind == "vsplit" then
		vim.cmd("vsplit")
	elseif kind == "tab" then
		vim.cmd("tabnew")
	end
	vim.api.nvim_win_set_buf(0, bufnr)
	vim.bo[bufnr].buflisted = true
end

--- Commit the current selection and open it for real (or descend into a dir).
--- Returns true when the picker should stay open (directory navigation).
local function choose(kind)
	local item = current()
	if not item then
		return true
	end

	if item.cand.dir then
		S.root = item.cand.abs
		S.source = source.get("files")
		S.query = ""
		S.caret = 0
		S.git = nil
		reload()
		return true
	end

	-- Sources that jump to a location (symbols, diagnostics) handle choosing
	-- themselves; nil means "fall through".
	local src = S.source
	if src.choose then
		local keep = src.choose(item.cand, kind, { session = S, root = S.root, close = M.close })
		if keep ~= nil then
			return keep
		end
	end

	-- Any candidate carrying a line number (grep, symbols, diagnostics) jumps
	-- to that location, reusing an already-loaded buffer.
	if item.cand.lnum then
		return require("loupe.source.jump").choose(item.cand, kind, { session = S, root = S.root, close = M.close })
	end

	local origin = S.origin_win
	if config.get().frecency and item.cand.abs then
		frecency.record(item.cand.abs)
	end

	-- `bufadd` rather than `:edit`: it reuses a buffer already holding this
	-- file, unsaved changes and all, where `:edit` would reload over them.
	local bufnr = item.cand.bufnr
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		bufnr = vim.fn.bufadd(item.cand.abs)
	end

	-- Same ordering, and the same forced paint, as `loupe.source.jump` — see
	-- the note there. The window is switched and drawn while the picker still
	-- covers it, so the teardown uncovers the file rather than a frame of
	-- whatever was on screen before. The buffer loads on the set, which puts
	-- the read, the filetype and whatever attaches to it behind the chrome
	-- too.
	if kind == "edit" and origin and vim.api.nvim_win_is_valid(origin) then
		vim.bo[bufnr].buflisted = true
		vim.api.nvim_win_set_buf(origin, bufnr)
		vim.cmd("redraw")
		M.close({ restore_cursor = false })
		return false
	end

	M.close()
	open_buf(bufnr, kind)
	return false
end

--- Select the match under the mouse (if the click was in the drawer). Row 1
--- is the prompt; the rows below it show the viewport starting at `S.top`.
local function mouse_select()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= S.drawer_win or mp.line < 2 then
		return false
	end
	local idx = (S.top or 1) + mp.line - 2
	if idx < 1 or idx > #S.matches then
		return false
	end
	S.aimed = true
	S.index = idx
	return true
end

--- Open the picker. `opts.source` picks the initial source by name.
function M.open(opts)
	if active() then
		-- A session whose drawer is gone was torn down from under us; drop it
		-- rather than refusing to open for the rest of the editor's life.
		if S.drawer_win and vim.api.nvim_win_is_valid(S.drawer_win) then
			return
		end
		M.close()
	end
	local cfg = config.get()
	local origin = vim.api.nvim_get_current_win()
	local root = cfg.root()
	local wanted = opts and opts.source

	S = {
		active = true,
		loaded = false,
		origin_win = origin,
		origin_buf = vim.api.nvim_win_get_buf(origin),
		origin_cursor = vim.api.nvim_win_get_cursor(origin),
		gen = 0,
		root = root,
		project_root = root,
		source = (wanted and source.get(wanted)) or source.get(cfg.default_source or "files") or source.get("files"),
		candidates = {},
		query = "",
		caret = 0,
		matches = {},
		index = 0,
		-- whether the user has pointed the selection anywhere yet (moved,
		-- typed, clicked); until then nothing is selected and the preview
		-- stays shut, so opening the picker leaves the view alone
		aimed = false,
		-- first match drawn (the drawer keeps this in step with `index`)
		top = 1,
		sources = source.order,
		marked = {},
		git = nil,
		prompt = nil,
		menu = nil,
		-- dynamic sources: in-flight search handle, its progress and whether
		-- it was stopped at `max_results`
		search_cancel = nil,
		searching = false,
		truncated = false,
		-- captured before the drawer exists, so window-local options are the
		-- user's normal values (drawer turns number/signcolumn off)
		preview_opts = {
			number = vim.wo[origin].number,
			relativenumber = vim.wo[origin].relativenumber,
			signcolumn = vim.wo[origin].signcolumn,
			wrap = vim.wo[origin].wrap,
			linebreak = vim.wo[origin].linebreak,
			list = vim.wo[origin].list,
		},
	}

	-- Debounced driver for dynamic sources (grep/symbols).
	S.search_timer = debounce.new(80, function()
		run_search()
	end)

	local height = type(cfg.height) == "function" and cfg.height() or cfg.height
	local d = drawer.open(height)
	S.drawer_win, S.list_buf = d.win, d.buf
	-- hide the real cursor and draw a caret in the prompt instead
	S.guicursor = vim.o.guicursor
	vim.o.guicursor = "a:LoupeCursor"

	S.augroup = vim.api.nvim_create_augroup("LoupeSession", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", {
		group = S.augroup,
		callback = function()
			if active() then
				preview.resize(S.drawer_win)
				drawer.render(S, config.get())
			end
		end,
	})

	reload()
	-- Whatever happens in the loop, the picker must not be left half-open: the
	-- drawer and the preview cover the screen and the real cursor is hidden,
	-- so an error escaping here would look like a frozen editor.
	local ok, err = pcall(input.run, {
		state = S,
		is_active = active,
		render = render,
		close = M.close,
		choose = choose,
		reload = reload,
		refresh = refresh,
		move = move,
		page = page,
		current = current,
		set_query = set_query,
		start_prompt = start_prompt,
		set_source = set_source,
		cycle_source = cycle_source,
		run_action = run_action,
		start_delete = start_delete,
		mouse_select = mouse_select,
		go_parent = go_parent,
		go_root = go_root,
		toggle_mark = toggle_mark,
		quickfix = quickfix,
		yank = function(item, variant)
			action.yank({ session = S, item = item, root = S.root }, variant)
		end,
		open_external = function(item)
			action.open_external({ session = S, item = item, root = S.root })
		end,
	})
	if not ok then
		M.close()
		require("loupe.util.notify").scoped("loupe")(tostring(err), vim.log.levels.ERROR)
	end
end

--- Toggle the picker.
function M.toggle(opts)
	if active() then
		M.close()
	else
		M.open(opts)
	end
end

--- Configure the picker.
function M.setup(opts)
	config.setup(opts)
end

--- Whether the picker is open.
function M.is_active()
	return active()
end

return M
