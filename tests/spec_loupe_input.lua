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
		return vim.keycode("<Esc>")
	end
	session.open()
	vim.fn.LoupeGetChar = real
	h.ok(opened, "the picker refused to open after an aborted session")
	h.eq(session.is_active(), false)
end)

h.test("the source keys step along the tab strip", function()
	local real = vim.fn.LoupeGetChar
	local seen = {}
	local keys = { vim.keycode("<C-Right>"), vim.keycode("<C-Right>"), vim.keycode("<C-Left>"), vim.keycode("<Esc>") }
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
		return keys[at] or vim.keycode("<Esc>")
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
		return keys[at] or vim.keycode("<Esc>")
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
end)

-- Marks key on the candidate, not on its file: a location source puts many
-- candidates in one file, and keying on the path alone collapses them.

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

--- Drive the picker over `_hits` with `keys`, then report the quickfix list.
local function qflist_after(keys)
	local real = vim.fn.LoupeGetChar
	local at = 0
	vim.fn.LoupeGetChar = function()
		at = at + 1
		return keys[at] or vim.keycode("<Esc>")
	end
	vim.fn.setqflist({}, "r")
	local ok, err = pcall(session.open, { source = "_hits" })
	vim.fn.LoupeGetChar = real
	h.ok(ok, tostring(err))
	return vim.fn.getqflist()
end

h.test("marking one hit does not mark its neighbours in the same file", function()
	-- aim, mark the first hit, then send the marked set to the quickfix list
	local qf = qflist_after({ vim.keycode("<C-N>"), vim.keycode("<Tab>"), vim.keycode("<C-X>"), "q" })
	h.eq(#qf, 1, "one mark sent " .. #qf .. " locations: the mark keyed on the file, not the hit")
	h.eq(qf[1].lnum, 1, "the wrong hit was sent")
end)

h.test("marking two hits in one file sends both", function()
	-- <Tab> marks and steps down, so two in a row mark the first two hits
	local qf =
		qflist_after({ vim.keycode("<C-N>"), vim.keycode("<Tab>"), vim.keycode("<Tab>"), vim.keycode("<C-X>"), "q" })
	h.eq(#qf, 2)
	h.eq({ qf[1].lnum, qf[2].lnum }, { 1, 2 })
end)

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

	local seen = vim.tbl_map(function(c)
		return c.abs
	end, frecency.recent(root))
	h.ok(
		vim.tbl_contains(seen, root .. "/README.md"),
		"grep and symbol jumps never reach the frecency store, so Recent never sees them"
	)
end)
