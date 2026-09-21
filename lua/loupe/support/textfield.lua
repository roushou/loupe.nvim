--- Character-indexed text-field editing helpers.
---
--- Pure: built-in APIs only. A "field" is a string plus a caret index counted in
--- characters (not bytes), so multibyte input edits correctly.

local M = {}

--- Number of characters in `s`.
function M.len(s)
	return vim.fn.strchars(s)
end

--- Clamp `caret` into `[0, M.len(text)]`.
function M.clamp(text, caret)
	return math.max(0, math.min(caret, M.len(text)))
end

--- Insert `ch` at `caret`. Returns `text, caret`.
function M.insert(text, caret, ch)
	caret = M.clamp(text, caret)
	return vim.fn.strcharpart(text, 0, caret) .. ch .. vim.fn.strcharpart(text, caret), caret + M.len(ch)
end

--- Delete the character before `caret`. Returns `text, caret`.
function M.backspace(text, caret)
	caret = M.clamp(text, caret)
	if caret == 0 then
		return text, 0
	end
	return vim.fn.strcharpart(text, 0, caret - 1) .. vim.fn.strcharpart(text, caret), caret - 1
end

--- Delete the character at `caret`. Returns `text, caret`.
function M.delete(text, caret)
	caret = M.clamp(text, caret)
	if caret >= M.len(text) then
		return text, caret
	end
	return vim.fn.strcharpart(text, 0, caret) .. vim.fn.strcharpart(text, caret + 1), caret
end

--- Delete the word before `caret`. Returns `text, caret`.
function M.delete_word(text, caret)
	caret = M.clamp(text, caret)
	local before = vim.fn.strcharpart(text, 0, caret)
	local after = vim.fn.strcharpart(text, caret)
	before = before:gsub("%s*%S+%s*$", "")
	return before .. after, M.len(before)
end

return M
