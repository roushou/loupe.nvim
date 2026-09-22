local h = require("tests.harness")
local run = require("loupe.backend.run")

local function collect(argv, limit)
	local calls = {}
	local cancel = run.stream(argv, vim.uv.cwd(), function(lines)
		local out = {}
		for _, l in ipairs(lines) do
			out[#out + 1] = { rel = l }
		end
		return out
	end, function(cands, ok, done, truncated)
		calls[#calls + 1] = { n = #cands, ok = ok, done = done, truncated = truncated }
	end, limit)
	vim.wait(5000, function()
		return #calls > 0 and calls[#calls].done
	end, 5)
	return calls, cancel
end

h.test("stream delivers every line once the process exits", function()
	local calls = collect({ "sh", "-c", "printf 'a\\nb\\nc\\n'" })
	local last = calls[#calls]
	h.eq(last.n, 3)
	h.eq(last.ok, true)
	h.eq(last.done, true)
	h.eq(last.truncated, false)
end)

h.test("stream reassembles lines split across chunks", function()
	-- two writes with a pause: the first chunk ends mid-line
	local calls = collect({ "sh", "-c", "printf 'ab'; sleep 0.05; printf 'cd\\nef\\n'" })
	h.eq(calls[#calls].n, 2)
end)

h.test("stream stops at the limit and reports truncation", function()
	local calls = collect({ "seq", "1", "1000000" }, 50)
	local last = calls[#calls]
	h.ok(last.n >= 50, "expected at least 50 candidates, got " .. last.n)
	h.eq(last.done, true)
	h.eq(last.truncated, true)
	-- nothing after the final delivery
	local n = #calls
	vim.wait(100)
	h.eq(#calls, n)
end)

h.test("stream cancel silences the callback", function()
	local calls = {}
	local cancel = run.stream({ "sh", "-c", "sleep 0.05; echo x" }, vim.uv.cwd(), function(lines)
		return lines
	end, function()
		calls[#calls + 1] = true
	end)
	cancel()
	vim.wait(200)
	h.eq(#calls, 0)
end)

h.test("stream reports failure when the command cannot spawn", function()
	local got
	run.stream({ "loupe-no-such-binary" }, vim.uv.cwd(), function(l)
		return l
	end, function(cands, ok, done)
		got = { cands, ok, done }
	end)
	h.eq(got, { {}, false, true })
end)
