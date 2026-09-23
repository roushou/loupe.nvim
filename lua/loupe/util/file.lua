--- File reading + highlighting helpers for previews.
---
--- Pure: built-in APIs only (|vim.uv|, |vim.fn.readfile()|, treesitter, native
--- syntax). Never sets 'filetype', so no |FileType| autocmds (LSP attach,
--- indentation, ...) fire on a preview buffer.

local M = {}

--- True when `path` has no NUL byte in its first chunk (looks like text).
--- Returns nil when the file can't be opened.
function M.is_text(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil
	end
	local data = vim.uv.fs_read(fd, 1024) or ""
	vim.uv.fs_close(fd)
	return not data:find("\0")
end

--- Read at most `max_lines` lines and `max_bytes` bytes from `path` (either
--- may be nil for no bound). A single bounded `uv` read keeps a file with one
--- enormous line as cheap as a normal one.
---
--- Returns `lines, err, truncated`; `err` is "binary" when the head of the
--- file contains a NUL byte, or the open error. CR of CRLF endings is dropped.
function M.read(path, max_lines, max_bytes)
	local fd, err = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil, err or "cannot open", false
	end
	local stat = vim.uv.fs_fstat(fd)
	local size = stat and stat.size or 0
	local want = size
	if max_bytes and max_bytes + 1 < want then
		want = max_bytes + 1
	end
	local data = want > 0 and vim.uv.fs_read(fd, want, 0) or ""
	vim.uv.fs_close(fd)
	data = data or ""
	if data:sub(1, 1024):find("\0", 1, true) then
		return nil, "binary", false
	end

	local truncated = false
	if max_bytes and #data > max_bytes then
		-- keep whole lines only (drop the cut-off tail); a file that is one
		-- giant line keeps a short head
		local last = max_bytes
		while last > 0 and data:byte(last) ~= 10 do
			last = last - 1
		end
		data = last > 0 and data:sub(1, last) or data:sub(1, 4096)
		truncated = true
	end
	local lines = vim.split(data, "\n", { plain = true })
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	for i, line in ipairs(lines) do
		if line:sub(-1) == "\r" then
			lines[i] = line:sub(1, -2)
		end
	end
	if max_lines and #lines > max_lines then
		lines = vim.list_slice(lines, 1, max_lines)
		truncated = true
	end
	return lines, nil, truncated
end

--- Whether a buffer is small enough to highlight (total and per-line bounds).
function M.should_highlight(buf)
	local n = vim.api.nvim_buf_line_count(buf)
	local size = vim.api.nvim_buf_get_offset(buf, n)
	return size <= 1000000 and size <= 1000 * n
end

--- Highlight `buf` as `ft`: treesitter when a parser exists, native syntax
--- otherwise. Stops any existing treesitter highlighter first.
function M.highlight(buf, ft)
	pcall(vim.treesitter.stop, buf)
	if not ft or ft == "" then
		vim.bo[buf].syntax = ""
		return
	end
	local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
	lang = has_lang and lang or ft
	local has_parser, parser = pcall(vim.treesitter.get_parser, buf, lang, { error = false })
	has_parser = has_parser and parser ~= nil
	if has_parser then
		-- parse before attaching: past a size budget treesitter parses in the
		-- background and asks for a redraw when it lands, which never comes
		-- while the picker sits blocked on a key
		pcall(function()
			parser:parse(true)
		end)
		has_parser = pcall(vim.treesitter.start, buf, lang)
	end
	if not has_parser then
		vim.bo[buf].syntax = ft
	end
end

return M
