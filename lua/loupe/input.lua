--- Blocking key loop and key dispatch for loupe.
---
--- Loupe is not a real Vim mode: a `getcharstr` loop reads raw keys and routes
--- them to session operations supplied via `ctx`. This module owns only that
--- layer, keeping the quirky input handling out of the session logic.
---
--- Bindings are data, not code: `config.mappings` maps key notation to action
--- names (see `loupe.keymap` and the defaults in `loupe.config`). Each context
--- below is a thin interpreter over that map.
---
--- `ctx` fields: `state` (session table), `is_active`, `render`, `close`,
--- `choose`, `reload`, `refresh`, `move`, `page`, `current`, `set_query`,
--- `start_prompt`, `set_source`, `run_action`, `mouse_select`, `yank`,
--- `go_parent`, `go_root`, `toggle_mark`, `quickfix`, `open_external`.

local tf = require("loupe.util.textfield")
local config = require("loupe.config")
local keymap = require("loupe.keymap")

local M = {}

--- A key is printable when it isn't a special `<...>` sequence or a control
--- byte. keytrans() renders space and `<` as `<Space>`/`<lt>`, so allow those.
local function is_printable(ch, key)
	if key == "<Space>" or key == "<lt>" then
		return true
	end
	if key:match("^<.+>$") then
		return false
	end
	local b = ch:byte(1)
	return b ~= nil and b >= 32 and b ~= 127
end

--- One key while an inline prompt (rename/delete/create) is active.
local function handle_prompt(ctx, map, ch, key)
	local S = ctx.state
	local p = S.prompt
	local action = map[key]
	if action == "submit" then
		local value, name = p.value, p.action
		S.prompt = nil
		ctx.run_action(name, value)
	elseif action == "cancel" then
		S.prompt = nil
	elseif action == "backspace" then
		p.value, p.caret = tf.backspace(p.value, p.caret)
	elseif action == "delete" then
		p.value, p.caret = tf.delete(p.value, p.caret)
	elseif action == "delete_word" then
		p.value, p.caret = tf.delete_word(p.value, p.caret)
	elseif action == "clear" then
		p.value, p.caret = "", 0
	elseif action == "caret_left" then
		p.caret = math.max(0, p.caret - 1)
	elseif action == "caret_right" then
		p.caret = math.min(tf.len(p.value), p.caret + 1)
	elseif action == "home" then
		p.caret = 0
	elseif action == "end" then
		p.caret = tf.len(p.value)
	elseif is_printable(ch, key) then
		p.value, p.caret = tf.insert(p.value, p.caret, ch)
	end
end

--- One key while the action menu (`<C-x>`) is showing.
local function handle_menu(ctx, map, key)
	local S = ctx.state
	S.menu = nil
	local item = ctx.current()
	if not item then
		return
	end
	local action = map[key]
	if action == "rename" then
		ctx.start_prompt("Rename: ", item.cand.rel, "rename")
	elseif action == "delete" then
		ctx.start_prompt("Delete " .. item.cand.rel .. "? [y/N] ", "", "delete")
	elseif action == "create" then
		ctx.start_prompt("Add (end with / for a dir): ", "", "create")
	elseif action == "duplicate" then
		ctx.start_prompt("Duplicate to: ", item.cand.rel, "duplicate")
	elseif action == "yank" then
		ctx.yank(item, "abs")
	elseif action == "yank_rel" then
		ctx.yank(item, "rel")
	elseif action == "yank_name" then
		ctx.yank(item, "name")
	elseif action == "yank_dir" then
		ctx.yank(item, "dir")
	elseif action == "open_external" then
		ctx.open_external(item)
	elseif action == "quickfix" then
		ctx.quickfix()
	end
end

--- One key while the source menu (`<C-o>`) is showing.
local function handle_sources(ctx, map, key)
	ctx.state.menu = nil
	local name = map[key]
	if name then
		ctx.set_source(name)
	end
end

--- One browse key. Returns true when the picker should quit.
local function handle_browse(ctx, map, ch, key)
	local S = ctx.state
	local action = map[key]
	if action == "open" then
		return not ctx.choose("edit")
	elseif action == "close" then
		ctx.close()
		return true
	elseif action == "split" then
		return not ctx.choose("split")
	elseif action == "vsplit" then
		return not ctx.choose("vsplit")
	elseif action == "tab" then
		return not ctx.choose("tab")
	elseif action == "menu" then
		S.menu = "actions"
	elseif action == "sources" then
		S.menu = "sources"
	elseif action == "root" then
		ctx.go_root()
	elseif action == "mark" then
		ctx.toggle_mark()
		ctx.move(1)
	elseif action == "select" then
		ctx.mouse_select()
	elseif action == "open_mouse" then
		if ctx.mouse_select() then
			return not ctx.choose("edit")
		end
	elseif action == "scroll_up" then
		ctx.move(-3)
	elseif action == "scroll_down" then
		ctx.move(3)
	elseif action == "down" then
		ctx.move(1)
	elseif action == "up" then
		ctx.move(-1)
	elseif action == "page_down" then
		ctx.move(ctx.page())
	elseif action == "page_up" then
		ctx.move(-ctx.page())
	elseif action == "delete_word" then
		ctx.set_query(tf.delete_word(S.query, S.caret))
	elseif action == "backspace" then
		if S.query == "" then
			ctx.go_parent()
		else
			ctx.set_query(tf.backspace(S.query, S.caret))
		end
	elseif action == "delete" then
		ctx.set_query(tf.delete(S.query, S.caret))
	elseif action == "caret_left" then
		S.caret = math.max(0, S.caret - 1)
	elseif action == "caret_right" then
		S.caret = math.min(tf.len(S.query), S.caret + 1)
	elseif action == "home" then
		S.caret = 0
	elseif action == "end" then
		S.caret = tf.len(S.query)
	elseif is_printable(ch, key) then
		ctx.set_query(tf.insert(S.query, S.caret, ch))
	end
	return false
end

--- Whether keys are waiting in the typeahead (a held or repeated key). The
--- session skips redraws while this holds: only the last queued key needs to
--- paint.
function M.pending()
	return vim.fn.getchar(1) ~= 0
end

--- Run the blocking key loop until the picker closes.
function M.run(ctx)
	local maps = keymap.resolve(config.get().mappings)
	ctx.render()
	while ctx.is_active() do
		local ch = vim.fn.getcharstr()
		if ch == "" then
			ctx.close()
			return
		end
		local key = vim.fn.keytrans(ch)

		local quit
		if ctx.state.prompt then
			handle_prompt(ctx, maps.prompt, ch, key)
		elseif ctx.state.menu == "actions" then
			handle_menu(ctx, maps.menu, key)
		elseif ctx.state.menu == "sources" then
			handle_sources(ctx, maps.sources, key)
		else
			quit = handle_browse(ctx, maps.browse, ch, key)
		end
		if quit then
			return
		end
		ctx.render()
	end
end

return M
