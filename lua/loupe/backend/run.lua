--- Shared async command runner for the enumeration backends.
---
--- Pure wrapper around |util.proc| plus the two conventions every backend
--- relies on: line splitting and a success flag so callers can fall back to
--- the next preferred backend when a tool is missing or fails. `stream` adds
--- incremental delivery for the live sources.

local proc = require("loupe.util.proc")

local M = {}

--- Split stdout into non-empty lines.
function M.lines(stdout)
	local out = {}
	for _, line in ipairs(vim.split(stdout or "", "\n", { plain = true })) do
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	return out
end

--- Run `argv` in `root`; `parse(stdout)` returns the candidate list.
--- Calls `cb(cands, ok)` with `ok = false` on spawn or exit failure so the
--- caller can cascade to the next backend. Empty-but-successful stays `ok`.
function M.raw(argv, root, parse, cb)
	local spawned = proc.async(argv, { cwd = root }, function(res)
		local ok = res.code == 0
		local cands = ok and parse(res.stdout or "") or {}
		vim.schedule(function()
			cb(cands, ok)
		end)
	end)
	if not spawned then
		cb({}, false)
	end
end

--- Run `argv` in `root`, delivering results as they arrive. `parse(lines)`
--- turns a batch of complete output lines into candidates. `cb(cands, ok,
--- done, truncated)` receives the cumulative list, throttled to one call per
--- `INTERVAL` ms and once more when the process exits (`done`). Once `limit`
--- candidates exist the process is stopped and `truncated` is set.
---
--- Returns a cancel function: it stops the process and guarantees `cb` is not
--- called again.
local INTERVAL = 30

function M.stream(argv, root, parse, cb, limit)
	local cands, pending, rest = {}, {}, ""
	local cancelled, exited, delivered_final = false, false, false
	local timer = vim.uv.new_timer()
	local proc

	local function stop()
		cancelled = true
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		if proc then
			pcall(proc.kill, proc, 15)
		end
	end

	local function deliver()
		if cancelled or delivered_final then
			return
		end
		local batch = pending
		pending = {}
		if #batch > 0 then
			for _, c in ipairs(parse(batch)) do
				cands[#cands + 1] = c
			end
		end
		local truncated = limit ~= nil and #cands >= limit
		local done = exited or truncated
		if done then
			delivered_final = true
			stop()
		end
		cb(cands, true, done, truncated)
	end

	local function schedule(ms)
		if cancelled or timer:is_active() then
			return
		end
		timer:start(ms, 0, vim.schedule_wrap(deliver))
	end

	local function on_stdout(_, data)
		if cancelled or not data then
			return
		end
		rest = rest .. data
		local last = 0
		for line, at in rest:gmatch("([^\n]*)\n()") do
			if line ~= "" then
				pending[#pending + 1] = line
			end
			last = at
		end
		rest = rest:sub(last)
		schedule(INTERVAL)
	end

	local ok, obj = pcall(vim.system, argv, { cwd = root, text = true, stdout = on_stdout }, function()
		if cancelled then
			return
		end
		exited = true
		if rest ~= "" then
			pending[#pending + 1] = rest
			rest = ""
		end
		-- exit beats a pending throttle tick: deliver now
		vim.schedule(function()
			if cancelled then
				return
			end
			timer:stop()
			deliver()
		end)
	end)
	if not ok then
		stop()
		cb({}, false, true, false)
		return function() end
	end
	proc = obj
	return stop
end

return M
