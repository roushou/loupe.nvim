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
--- `set_source`, `cycle_source`, `mouse_select`, `go_parent`, `go_root`.

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
	elseif action == "sources" then
		S.menu = "sources"
	elseif action == "source_next" then
		ctx.cycle_source(1)
	elseif action == "source_prev" then
		ctx.cycle_source(-1)
	elseif action == "root" then
		ctx.go_root()
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

-- Reading keys through Vimscript's `:try` is not a detour: outside one,
-- CTRL-C during `getcharstr()` raises an interrupt that aborts the running
-- Lua chunk outright — `pcall` does not catch it. The loop would stop mid-way
-- with the drawer still open, the preview still covering the window and the
-- real cursor still hidden, and nothing left running to clean any of it up.
-- Inside a `:try`, the same keypress is delivered as the character it is, so
-- it reaches the mappings like any other key.
vim.api.nvim_exec2(
	[[
function! LoupeGetChar() abort
  try
    return getcharstr()
  catch /^Vim:Interrupt$/
    return "\<C-c>"
  endtry
endfunction
]],
	{}
)

--- Read one key, or "" when the input stream ended.
function M.read()
	local ok, ch = pcall(vim.fn.LoupeGetChar)
	-- a failed read is the stream giving up; treat it as a close
	return ok and ch or ""
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
		local ch = M.read()
		if ch == "" then
			ctx.close()
			return
		end
		local key = vim.fn.keytrans(ch)

		local quit
		if ctx.state.menu == "sources" then
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
