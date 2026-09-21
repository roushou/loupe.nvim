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

--- Read at most `max_lines` lines from `path` (all when nil).
--- Returns `lines, err, truncated`; `err` is nil on success.
function M.read(path, max_lines)
	local ok, res
	if max_lines then
		ok, res = pcall(vim.fn.readfile, path, "", max_lines + 1)
	else
		ok, res = pcall(vim.fn.readfile, path, "")
	end
	if not ok then
		return nil, res, false
	end
	local truncated = max_lines ~= nil and #res > max_lines
	if truncated then
		res = vim.list_slice(res, 1, max_lines)
	end
	return res, nil, truncated
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
		has_parser = pcall(vim.treesitter.start, buf, lang)
	end
	if not has_parser then
		vim.bo[buf].syntax = ft
	end
end

return M
