local h = require("tests.harness")
local file = require("loupe.util.file")

local function tmpfile(content)
	local path = vim.fn.tempname()
	local f = assert(io.open(path, "wb"))
	f:write(content)
	f:close()
	return path
end

h.test("read returns lines without the trailing newline entry", function()
	local lines, err, truncated = file.read(tmpfile("a\nb\nc\n"))
	h.eq(err, nil)
	h.eq(lines, { "a", "b", "c" })
	h.eq(truncated, false)
end)

h.test("read strips CR from CRLF endings", function()
	local lines = file.read(tmpfile("a\r\nb\r\n"))
	h.eq(lines, { "a", "b" })
end)

h.test("read caps lines", function()
	local lines, _, truncated = file.read(tmpfile("1\n2\n3\n4\n"), 2)
	h.eq(lines, { "1", "2" })
	h.eq(truncated, true)
end)

h.test("read caps bytes on a whole-line boundary", function()
	local lines, _, truncated = file.read(tmpfile("aaaa\nbbbb\ncccc\n"), nil, 12)
	h.eq(lines, { "aaaa", "bbbb" })
	h.eq(truncated, true)
end)

h.test("read keeps a short head of a single giant line", function()
	local path = tmpfile(string.rep("x", 100000))
	local lines, _, truncated = file.read(path, 2000, 8192)
	h.eq(#lines, 1)
	h.eq(#lines[1], 4096)
	h.eq(truncated, true)
end)

h.test("read flags binary content", function()
	local lines, err = file.read(tmpfile("ab\0cd"))
	h.eq(lines, nil)
	h.eq(err, "binary")
end)

h.test("read reports a missing file", function()
	local lines, err = file.read(vim.fn.tempname() .. "/missing")
	h.eq(lines, nil)
	h.ok(err)
end)
