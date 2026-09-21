--- Minimal pure test harness (no third-party deps).
---
--- Spec files call `h.test(name, fn)`; `h.run()` executes them and returns
--- true when everything passed.

local M = { tests = {}, failures = {}, passed = 0 }

--- Register a test case.
function M.test(name, fn)
	M.tests[#M.tests + 1] = { name = name, fn = fn }
end

local function fmt(v)
	return type(v) == "string" and ("%q"):format(v) or vim.inspect(v)
end

--- Assert `cond` is truthy.
function M.ok(cond, msg)
	if not cond then
		error(msg or "expected a truthy value", 2)
	end
end

--- Assert deep equality of `actual` and `expected`.
function M.eq(actual, expected, msg)
	if not vim.deep_equal(actual, expected) then
		local prefix = msg and (msg .. ": ") or ""
		error(("%sexpected %s, got %s"):format(prefix, fmt(expected), fmt(actual)), 2)
	end
end

--- Run all registered tests. Returns true when none failed.
function M.run()
	for _, t in ipairs(M.tests) do
		local ok, err = pcall(t.fn)
		if ok then
			M.passed = M.passed + 1
			io.write("ok   " .. t.name .. "\n")
		else
			M.failures[#M.failures + 1] = { name = t.name, err = err }
			io.write("FAIL " .. t.name .. "\n     " .. tostring(err) .. "\n")
		end
	end
	io.write(("\n%d passed, %d failed\n"):format(M.passed, #M.failures))
	return #M.failures == 0
end

return M
