--- Headless end-to-end benchmark.
---   nvim --headless -u tests/minimal_init.lua -l tests/bench.lua
---
--- Drives the real session (open → type → move → grep) by replacing the key
--- reader with a scripted queue, so every layer from enumeration to preview
--- rendering is exercised exactly as in interactive use. Keys queued back to
--- back are delivered with typeahead pending, like a held key; a function in
--- the queue runs between keys (waits, timers).
---
--- Fixture: a synthetic repo under $LOUPE_BENCH_DIR (default: stdpath cache),
--- generated once. Set LOUPE_BENCH_OUT to also write the results as JSON.

vim.notify = function() end

local N_FILES = tonumber(os.getenv("LOUPE_BENCH_FILES")) or 20000
local N_BIG = 20
local BIG_LINES = 5000
local HUGE_BYTES = 20 * 1024 * 1024
local ROOT = os.getenv("LOUPE_BENCH_DIR") or (vim.fn.stdpath("cache") .. "/loupe-bench")

-- ---------------------------------------------------------------------------
-- fixture

local function generate()
	if vim.uv.fs_stat(ROOT .. "/.loupe-bench-ready") then
		return
	end
	io.write(("generating fixture: %d files under %s\n"):format(N_FILES, ROOT))
	vim.fn.mkdir(ROOT, "p")
	local words = { "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta" }
	for i = 1, N_FILES do
		local d1 = words[(i % #words) + 1]
		local d2 = ("mod%02d"):format(i % 40)
		local dir = ("%s/src/%s/%s"):format(ROOT, d1, d2)
		vim.fn.mkdir(dir, "p")
		local lines = {}
		for l = 1, 30 do
			lines[l] = ("local function %s_%d_%d() return %d end"):format(d1, i, l, l)
		end
		vim.fn.writefile(lines, ("%s/file_%05d.lua"):format(dir, i))
	end
	for i = 1, N_BIG do
		local lines = {}
		for l = 1, BIG_LINES do
			lines[l] = ("function big_%d_%d(a, b) return a + b * %d end -- filler text"):format(i, l, l)
		end
		vim.fn.writefile(lines, ("%s/big_%02d.lua"):format(ROOT, i))
	end
	-- one 20MB line: worst case for line-oriented readers
	local f = assert(io.open(ROOT .. "/huge_single_line.txt", "w"))
	local chunk = string.rep("x", 1024 * 1024)
	for _ = 1, HUGE_BYTES / #chunk do
		f:write(chunk)
	end
	f:close()
	vim.fn.writefile({ "main" }, ROOT .. "/main.lua")
	vim.fn.system({ "git", "-C", ROOT, "init", "-q" })
	vim.fn.system({ "git", "-C", ROOT, "add", "-A" })
	vim.fn.system({ "git", "-C", ROOT, "-c", "user.email=b@b", "-c", "user.name=b", "commit", "-qm", "fixture" })
	vim.fn.writefile({}, ROOT .. "/.loupe-bench-ready")
end

-- ---------------------------------------------------------------------------
-- instrumentation

local procs = { active = {}, peak = {}, spawned = {} }
local real_system = vim.system
vim.system = function(cmd, opts, cb)
	local exe = vim.fn.fnamemodify(cmd[1], ":t")
	procs.active[exe] = (procs.active[exe] or 0) + 1
	procs.spawned[exe] = (procs.spawned[exe] or 0) + 1
	procs.peak[exe] = math.max(procs.peak[exe] or 0, procs.active[exe])
	return real_system(cmd, opts, function(res)
		procs.active[exe] = procs.active[exe] - 1
		if cb then
			cb(res)
		end
	end)
end

local function reset_procs()
	procs.peak, procs.spawned = {}, {}
end

local function now()
	return vim.uv.hrtime() / 1e6
end

local queue = {}
local ESC = "\27"

local function key(k)
	return vim.api.nvim_replace_termcodes(k, true, false, true)
end

-- Scripted key reader: strings are delivered as keys, functions run in between.
-- An empty queue delivers <Esc> so the session always closes.
vim.fn.getcharstr = function()
	while true do
		local item = table.remove(queue, 1)
		if item == nil then
			return ESC
		end
		if type(item) == "function" then
			item()
		else
			return item
		end
	end
end
-- getchar(1) peeks the typeahead; keys queued back to back count as pending.
vim.fn.getchar = function(expr)
	if expr == 1 then
		return type(queue[1]) == "string" and 1 or 0
	end
	return 0
end

--- The drawer's list buffer (winbar contains "Loupe").
local function drawer_lines()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if (vim.wo[w].winbar or ""):find("Loupe", 1, true) then
			return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), vim.wo[w].winbar
		end
	end
	return {}, ""
end

local function loaded()
	local lines = drawer_lines()
	return lines[2] ~= nil and lines[2] ~= "  (loading…)"
end

local function match_count()
	local lines = drawer_lines()
	if #lines < 2 or lines[2] == "  (loading…)" or lines[2] == "  (no matches)" then
		return 0
	end
	return #lines - 1
end

local function wait_until(cond, timeout)
	vim.wait(timeout or 30000, cond, 2)
end

local function idle(exe)
	return (procs.active[exe] or 0) == 0
end

-- ---------------------------------------------------------------------------
-- scenarios

local results = {}
local function record(name, ms, extra)
	results[#results + 1] = { name = name, ms = ms, extra = extra }
end

--- Flatten a step list: strings become keys, nested lists are spliced in.
local function seq(steps)
	local out = {}
	for _, item in ipairs(steps) do
		if type(item) == "table" then
			vim.list_extend(out, item)
		else
			out[#out + 1] = item
		end
	end
	return out
end

local function repeat_keys(k, n)
	local out = {}
	for i = 1, n do
		out[i] = key(k)
	end
	return out
end

--- One key per character; `gap_ms` pauses between them (pumping the loop).
local function chars(s, gap_ms)
	local out = {}
	for c in s:gmatch(".") do
		out[#out + 1] = c
		if gap_ms then
			out[#out + 1] = function()
				vim.wait(gap_ms)
			end
		end
	end
	return out
end

local function open_session(steps)
	queue = steps
	require("loupe").open()
end

local function run()
	local loupe = require("loupe")
	loupe.setup({
		root = function()
			return ROOT
		end,
	})
	vim.cmd("cd " .. vim.fn.fnameescape(ROOT))

	-- A: cold open → list rendered
	local t0 = now()
	open_session({
		function()
			wait_until(loaded)
			record("open (cold) → list rendered", now() - t0)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
		end,
	})

	-- B: reopen → list rendered (and until fresh enumeration finished)
	reset_procs()
	t0 = now()
	open_session({
		function()
			wait_until(loaded)
			record("reopen (warm) → list rendered", now() - t0)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
			record("reopen (warm) → enumeration fresh", now() - t0)
		end,
	})

	-- C: type a query with keys back to back (held / pasted)
	open_session({
		function()
			wait_until(loaded)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
			t0 = now()
		end,
		"b",
		"i",
		"g",
		"_",
		"0",
		function()
			record("type 'big_0' (5 keys queued) → settled", now() - t0, { matches = match_count() })
		end,
	})

	-- D: hold <C-n> across large files (each move previews a 5000-line file)
	open_session(seq({
		function()
			wait_until(loaded)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
		end,
		"b",
		"i",
		"g",
		"_",
		function()
			t0 = now()
		end,
		repeat_keys("<C-n>", 100),
		function()
			record("hold <C-n> ×100 over 5000-line files → settled", now() - t0)
		end,
	}))

	-- E: select the 20MB single-line file
	open_session({
		function()
			wait_until(loaded)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
			t0 = now()
		end,
		"h",
		"u",
		"g",
		"e",
		function()
			record("preview 20MB single-line file", now() - t0)
		end,
	})

	-- F: grep, query typed instantly → first results / all results
	reset_procs()
	local t_first
	open_session(seq({
		function()
			wait_until(loaded)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
		end,
		key("<C-o>"),
		"g",
		function()
			t0 = now()
		end,
		chars("function"),
		function()
			wait_until(function()
				return match_count() > 0
			end)
			t_first = now() - t0
			wait_until(function()
				return idle("rg")
			end)
			vim.wait(50)
			record("grep 'function' (queued) → first results", t_first, { matches = match_count() })
			record("grep 'function' (queued) → rg finished", now() - t0, { rg_spawned = procs.spawned.rg })
		end,
	}))

	-- G: grep, one key every 120ms (slower than the debounce): concurrent rg
	reset_procs()
	open_session(seq({
		function()
			wait_until(loaded)
			wait_until(function()
				return idle("fd") and idle("git")
			end)
		end,
		key("<C-o>"),
		"g",
		function()
			t0 = now()
		end,
		chars("function", 120),
		function()
			wait_until(function()
				return idle("rg")
			end)
			vim.wait(50)
			record("grep 'function' (120ms/key) → settled", now() - t0, {
				rg_spawned = procs.spawned.rg,
				rg_peak_concurrent = procs.peak.rg,
			})
		end,
	}))

	-- report
	io.write("\n| scenario | ms | notes |\n|---|---:|---|\n")
	for _, r in ipairs(results) do
		local notes = {}
		for k, v in pairs(r.extra or {}) do
			notes[#notes + 1] = k .. "=" .. tostring(v)
		end
		table.sort(notes)
		io.write(("| %s | %.1f | %s |\n"):format(r.name, r.ms, table.concat(notes, " ")))
	end
	local out = os.getenv("LOUPE_BENCH_OUT")
	if out then
		vim.fn.writefile({ vim.json.encode(results) }, out)
	end
end

generate()
local ok, err = pcall(run)
if not ok then
	io.write("bench error: " .. tostring(err) .. "\n")
	vim.cmd("cquit")
end
vim.cmd("qall!")
