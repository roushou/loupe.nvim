local h = require("tests.harness")
local input = require("loupe.input")
local session = require("loupe.session")

-- The CTRL-C path cannot be asserted in-process, and not in `--headless`
-- either: `nvim_input("\3")` injects a plain byte rather than the interrupt a
-- terminal raises, so a test built on it passes whether or not the bug is
-- fixed. It was verified by driving a real Neovim in a pty: with the reader
-- below, CTRL-C closes the picker and the editor answers `:` again; with a
-- bare `getcharstr()`, the editor answers nothing. What is left to protect
-- here is that the reader keeps going through the wrapper.

h.test("keys are read through the interrupt-safe wrapper", function()
	h.eq(vim.fn.exists("*LoupeGetChar"), 1, "the wrapper is not defined")
	local real = vim.fn.LoupeGetChar
	local used = false
	vim.fn.LoupeGetChar = function()
		used = true
		return "x"
	end
	local ch = input.read()
	vim.fn.LoupeGetChar = real
	h.ok(used, "read() bypassed the wrapper: a CTRL-C would abort the loop")
	h.eq(ch, "x")
end)

h.test("the wrapper hands back CTRL-C as a character", function()
	-- what the catch arm returns, spelled the way the mappings spell it
	h.eq(vim.fn.keytrans(vim.keycode("<C-c>")), "<C-C>")
end)

h.test("the close mapping covers the key CTRL-C arrives as", function()
	local maps = require("loupe.keymap").resolve(require("loupe.config").get().mappings)
	h.eq(maps.browse[vim.fn.keytrans("\3")], "close")
end)

h.test("the word-delete key is <M-BS> and <C-w> is the window prefix", function()
	local maps = require("loupe.keymap").resolve(require("loupe.config").get().mappings)
	h.eq(maps.browse[vim.fn.keytrans(vim.keycode("<M-BS>"))], "delete_word")
	h.eq(maps.browse[vim.fn.keytrans(vim.keycode("<C-W>"))], "window")
end)

h.test("read reports the end of the input stream as an empty key", function()
	local real = vim.fn.LoupeGetChar
	vim.fn.LoupeGetChar = function()
		error("stream gone")
	end
	h.eq(input.read(), "")
	vim.fn.LoupeGetChar = real
end)

h.test("an error in the key loop still tears the picker down", function()
	local real = vim.fn.LoupeGetChar
	local guicursor = vim.o.guicursor
	local windows = #vim.api.nvim_list_wins()
	vim.fn.LoupeGetChar = function()
		error("boom")
	end
	local notify = vim.notify
	vim.notify = function() end

	session.open()

	vim.fn.LoupeGetChar = real
	vim.notify = notify
	h.eq(session.is_active(), false, "session left active")
	h.eq(#vim.api.nvim_list_wins(), windows, "drawer or preview left open")
	h.eq(vim.o.guicursor, guicursor, "the real cursor was left hidden")
end)

h.test("opening again recovers from a session whose drawer is gone", function()
	local real = vim.fn.LoupeGetChar
	local notify = vim.notify
	vim.notify = function() end
	vim.fn.LoupeGetChar = function()
		error("boom")
	end
	session.open()
	vim.fn.LoupeGetChar = real
	vim.notify = notify

	-- the picker must still open afterwards
	local opened = false
	vim.fn.LoupeGetChar = function()
		opened = true
		return vim.keycode("<C-C>")
	end
	session.open()
	vim.fn.LoupeGetChar = real
	h.ok(opened, "the picker refused to open after an aborted session")
	h.eq(session.is_active(), false)
end)

h.test("the source keys step along the tab strip", function()
	local real = vim.fn.LoupeGetChar
	local seen = {}
	local keys = { vim.keycode("<C-Right>"), vim.keycode("<C-Right>"), vim.keycode("<C-Left>"), vim.keycode("<C-C>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		-- the window bar says which source is active when each key is read
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local bar = vim.wo[win].winbar or ""
			if bar:find("LoupeTab", 1, true) then
				seen[#seen + 1] = bar:match("LoupeTabActive#%s*([%w]+)")
			end
		end
		at = at + 1
		return keys[at] or vim.keycode("<C-C>")
	end
	session.open()
	vim.fn.LoupeGetChar = real

	h.eq(seen[1], "Files", "the picker did not start on the default source")
	h.eq(seen[2], "Dirs", "<C-Right> did not step forward")
	h.eq(seen[3], "Buffers")
	h.eq(seen[4], "Dirs", "<C-Left> did not step back")
end)

-- The picker opens over whatever the user was reading. Selecting a match on
-- its own would throw the preview across that buffer, so the freshly opened
-- picker rests with nothing selected until the user points it somewhere.
--
-- Driven through a source that hands back its candidates on the spot: the
-- real enumerations are asynchronous, and a stubbed key reader never yields
-- long enough for one to land.

local parse = require("loupe.backend.parse")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

require("loupe.source").register({
	name = "_resting",
	label = "Resting",
	list = function(_, cb)
		cb({ parse.candidate(root, "README.md"), parse.candidate(root, "doc/loupe.txt") }, true)
	end,
})

--- Open the picker on that source, feeding `keys`, and report whether the
--- preview was on screen before each key was read.
local function preview_at(keys)
	local real = vim.fn.LoupeGetChar
	local preview = require("loupe.preview")
	local at, seen = 0, {}
	vim.fn.LoupeGetChar = function()
		seen[#seen + 1] = preview.is_open()
		at = at + 1
		return keys[at] or vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	h.ok(ok, tostring(err))
	return seen
end

h.test("opening the picker previews nothing until the selection is aimed", function()
	local seen = preview_at({ vim.keycode("<C-N>") })
	h.eq(seen[1], false, "the picker previewed a match nobody asked for")
	h.eq(seen[2], true, "<C-N> did not open the preview")
end)

h.test("typing a query aims the selection", function()
	local seen = preview_at({ "r" })
	h.eq(seen[1], false)
	h.eq(seen[2], true, "a typed query left the picker resting")
end)

h.test("<Esc> parks: the drawer and its state survive, the preview withdraws", function()
	local real = vim.fn.LoupeGetChar
	local preview = require("loupe.preview")
	local keys = { vim.keycode("<C-N>"), vim.keycode("<Esc>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	h.ok(ok, tostring(err))

	h.eq(at, 2, "the loop read past <Esc>: it did not park")
	h.eq(session.is_active(), true, "<Esc> closed the picker instead of parking it")
	h.eq(session.is_focused(), false, "the parked picker still owns focus")
	h.eq(preview.is_open(), false, "the preview stayed up after parking")

	session.close()
	h.eq(session.is_active(), false, "close() left the session alive")
end)

h.test("re-entering a parked picker restores the preview over the same selection", function()
	local real = vim.fn.LoupeGetChar
	local preview = require("loupe.preview")
	-- first pass: aim at a row, then park
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return (at == 1 and vim.keycode("<C-N>")) or vim.keycode("<Esc>")
	end
	pcall(session.open, { source = "_resting" })
	h.eq(session.is_active(), true, "parking dropped the session")
	h.eq(preview.is_open(), false, "parking left the preview up")

	-- second pass: :Loupe with no source focuses the same session
	local restored
	vim.fn.LoupeGetChar = function()
		restored = preview.is_open()
		return vim.keycode("<C-C>")
	end
	pcall(session.open)
	vim.fn.LoupeGetChar = real

	h.eq(restored, true, "re-entering did not restore the preview")
	h.eq(session.is_active(), false, "<C-c> did not close the picker")
end)

h.test("<C-c> closes the picker outright", function()
	local real = vim.fn.LoupeGetChar
	local before = vim.o.guicursor
	vim.fn.LoupeGetChar = function()
		return vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	h.ok(ok, tostring(err))
	h.eq(session.is_active(), false, "<C-c> did not close the picker")
	h.eq(vim.o.guicursor, before, "the real cursor was left hidden")
end)

h.test("focusing a parked drawer restarts filter mode", function()
	local real = vim.fn.LoupeGetChar
	-- open, aim at a row, park
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return (at == 1 and vim.keycode("<C-N>")) or vim.keycode("<Esc>")
	end
	pcall(session.open, { source = "_resting" })
	h.eq(session.is_active(), true, "parking dropped the session")

	-- the parked drawer is still on screen, but not focused
	local drawer
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if (vim.wo[w].winbar or ""):find("LoupeTab", 1, true) then
			drawer = w
			break
		end
	end
	h.ok(drawer ~= nil, "the parked drawer is gone")
	h.ok(vim.api.nvim_get_current_win() ~= drawer, "parking left the drawer focused")

	-- focusing it (as <C-w>b would) must restart the key loop
	local read = false
	vim.fn.LoupeGetChar = function()
		read = true
		return vim.keycode("<C-C>")
	end
	vim.api.nvim_set_current_win(drawer)
	local pumped = vim.wait(500, function()
		return read
	end, 5)
	vim.fn.LoupeGetChar = real
	if session.is_active() then
		session.close()
	end
	h.ok(pumped, "focusing the parked drawer did not restart the key loop")
	h.eq(session.is_active(), false, "<C-c> did not close the restarted picker")
end)

--- The prompt row of the on-screen drawer, or nil when there is none.
local function drawer_prompt()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if (vim.wo[w].winbar or ""):find("LoupeTab", 1, true) then
			local bufnr = vim.api.nvim_win_get_buf(w)
			return vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
		end
	end
	return nil
end

h.test("<M-BS> deletes the word before the caret in the query", function()
	local real = vim.fn.LoupeGetChar
	local keys = { "a", "b", "c", " ", "d", "e", vim.keycode("<M-BS>"), vim.keycode("<C-C>") }
	local at, prompt = 0, nil
	vim.fn.LoupeGetChar = function()
		at = at + 1
		if at == 8 then
			prompt = drawer_prompt()
		end
		return keys[at] or vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	if session.is_active() then
		session.close()
	end
	h.ok(ok, tostring(err))
	h.ok(prompt ~= nil, "the drawer prompt could not be read")
	h.ok(prompt:find("abc", 1, true) ~= nil, "the query lost text before the word delete: " .. tostring(prompt))
	h.ok(prompt:find("de", 1, true) == nil, "<M-BS> did not delete the word: " .. tostring(prompt))
end)

h.test("<C-w> in the drawer runs a window command and parks", function()
	local real = vim.fn.LoupeGetChar
	local origin = vim.api.nvim_get_current_win()
	local keys = { vim.keycode("<C-N>"), vim.keycode("<C-W>"), "k", vim.keycode("<C-C>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	local parked = session.is_active()
	local still_focused = session.is_focused()
	local focused_win = vim.api.nvim_get_current_win()
	if session.is_active() then
		session.close()
	end
	h.ok(ok, tostring(err))
	h.ok(parked, "the picker was torn down instead of parked")
	h.eq(still_focused, false, "<C-w>k did not park the picker")
	h.eq(focused_win, origin, "<C-w>k did not move to the window above")
end)

h.test("closing the drawer from outside tears the session down", function()
	local real = vim.fn.LoupeGetChar
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return (at == 1 and vim.keycode("<C-N>")) or vim.keycode("<Esc>")
	end
	pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	h.eq(session.is_active(), true, "parking dropped the session")

	local drawer
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if (vim.wo[w].winbar or ""):find("LoupeTab", 1, true) then
			drawer = w
			break
		end
	end
	h.ok(drawer ~= nil, "the parked drawer is gone")
	vim.api.nvim_win_close(drawer, true)
	h.eq(session.is_active(), false, "closing the drawer from outside left the session alive")
end)

h.test("close_on_choose closes the picker after opening a file", function()
	local config = require("loupe.config")
	config.values = nil
	config.setup({ close_on_choose = true })
	local real = vim.fn.LoupeGetChar
	local origin = vim.api.nvim_get_current_win()
	local restore = vim.api.nvim_win_get_buf(origin)
	local keys = { vim.keycode("<C-N>"), vim.keycode("<CR>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<C-C>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	vim.api.nvim_win_set_buf(origin, restore)
	config.values = nil
	h.ok(ok, tostring(err))
	h.eq(session.is_active(), false, "close_on_choose left the picker open")
end)

h.test("the chosen file is in the window before the chrome comes down", function()
	-- The flash this guards against is a rendering artifact, so what is
	-- asserted here is the invariant behind it: by the time the first of the
	-- picker's windows closes, the window underneath already holds the file.
	-- Close first and the teardown uncovers a frame of the old buffer.
	local origin = vim.api.nvim_get_current_win()
	local restore = vim.api.nvim_win_get_buf(origin)
	local seen
	local group = vim.api.nvim_create_augroup("loupe_spec_reveal", { clear = true })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function()
			if seen == nil and vim.api.nvim_win_is_valid(origin) then
				seen = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin))
			end
		end,
	})

	local real = vim.fn.LoupeGetChar
	local keys = { vim.keycode("<C-N>"), vim.keycode("<CR>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<Esc>")
	end
	local ok, err = pcall(session.open, { source = "_resting" })
	vim.fn.LoupeGetChar = real
	vim.api.nvim_del_augroup_by_id(group)
	vim.api.nvim_win_set_buf(origin, restore)
	h.ok(ok, tostring(err))

	h.ok(seen ~= nil, "no window closed, so the picker never came down")
	h.ok(
		seen:find("README.md", 1, true) ~= nil,
		"the window still held " .. vim.fn.fnamemodify(seen, ":t") .. " when the picker started closing"
	)
	session.close()
end)

-- A source whose candidates all live in one file, the shape grep and symbols
-- produce.

local frecency = require("loupe.frecency")

require("loupe.source").register({
	name = "_hits",
	label = "Hits",
	list = function(_, cb)
		local abs = root .. "/README.md"
		cb({
			{ rel = "README.md", abs = abs, text = "first", label = "first", lnum = 1, col = 0 },
			{ rel = "README.md", abs = abs, text = "second", label = "second", lnum = 2, col = 0 },
			{ rel = "README.md", abs = abs, text = "third", label = "third", lnum = 3, col = 0 },
		}, true)
	end,
})

h.test("a file opened by jumping to a location counts as opened", function()
	frecency.path = vim.fn.tempname()
	local origin = vim.api.nvim_get_current_win()
	local restore = vim.api.nvim_win_get_buf(origin)
	local real = vim.fn.LoupeGetChar
	local keys = { vim.keycode("<C-N>"), vim.keycode("<CR>") }
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<Esc>")
	end
	local ok, err = pcall(session.open, { source = "_hits" })
	vim.fn.LoupeGetChar = real
	vim.api.nvim_win_set_buf(origin, restore)
	h.ok(ok, tostring(err))
	session.close()

	local seen = vim.tbl_map(function(c)
		return c.abs
	end, frecency.recent(root))
	h.ok(
		vim.tbl_contains(seen, root .. "/README.md"),
		"grep and symbol jumps never reach the frecency store, so Recent never sees them"
	)
end)
