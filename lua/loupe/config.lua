--- Loupe configuration: defaults + optional user overrides via setup().

local keymap = require("loupe.keymap")

local M = {}

M.defaults = {
	--- Drawer height in lines, window bar included. May be a number or a
	--- function returning one. Three of those lines are chrome (tabs, prompt,
	--- hints), so the floor leaves room for a useful number of matches.
	height = function()
		return math.max(10, math.floor(vim.o.lines * 0.33))
	end,

	--- Cap on ranked results rendered (and previewed).
	max_results = 200,

	--- Source shown when the picker opens (see `lua/loupe/source/`).
	default_source = "files",

	--- Project root resolver. Prefers a VCS root, then common project
	--- markers, then the current working directory.
	root = function()
		local root = vim.fs.root(0, { ".git", ".hg", ".svn", ".jj" })
		if root then
			return root
		end
		root = vim.fs.root(0, { "Cargo.toml", "package.json", "go.mod", "pyproject.toml", ".luarc.json" })
		return root or vim.uv.cwd() or vim.fn.getcwd()
	end,

	--- Backend id. Only "ripgrep" (built-in CLI + matchfuzzypos) exists so far.
	backend = "ripgrep",

	--- Enumeration backends per capability, in preference order. The first
	--- available tool wins; a failing run cascades to the next. `fd` is
	--- preferred for files/dirs, with `rg`/`git` as fallbacks.
	backends = {
		files = { "fd", "rg", "git" },
		dirs = { "fd" },
		changed = { "git" },
		buffers = { "nvim" },
		recent = { "internal" },
		grep = { "rg", "git" },
		symbols = { "lsp" },
		doc_symbols = { "lsp" },
		references = { "lsp" },
		implementations = { "lsp" },
		diagnostics = { "nvim" },
	},

	--- Preview options.
	preview = {
		enabled = true,
		--- Read at most this many lines into the preview buffer.
		max_lines = 2000,
		--- ... and at most this many bytes, so one enormous line stays cheap.
		max_bytes = 1048576,
		--- Re-emit the previewed file's diagnostics (undercurls, signs, and an
		--- end-of-line message) on the preview scratch buffer.
		diagnostics = true,
	},

	--- Show a per-filetype glyph before each entry.
	icons = true,

	--- Show git status markers (async `git status`) next to files.
	git = true,

	--- Order the empty-query list by frecency (recently/frequently opened).
	frecency = true,

	--- Move deleted files to the OS trash instead of unlinking. When no trash
	--- tool is available, files are unlinked and directories are refused.
	trash = true,

	--- Whether choosing a file tears the picker down or merely parks it. The
	--- default keeps the drawer (and its query, selection and source) at the
	--- bottom after a jump, quickfix-style; set to `true` for the classic
	--- "select and it is gone" behaviour.
	close_on_choose = false,

	--- Prompt prefix rendered before the query.
	prompt = "> ",

	--- Caret drawn at the end of the prompt input.
	prompt_caret = "▏",

	--- Key bindings, grouped by context. Each map is `{ [lhs] = action }`.
	---
	---   browse:  the result list (movement, opening, editing the query)
	---   sources: the submenu opened by the browse `sources` action (<C-o>)
	---
	--- lhs may be written in any notation Neovim understands (`<C-s>` and
	--- `<C-S>` are equivalent). Set a value to `false` to unbind a default
	--- key. Printable characters with no binding are inserted into the query.
	---
	--- `park` leaves filter mode but keeps the drawer and its state; `close`
	--- tears it down. By default `<Esc>` parks and `<C-c>` closes.
	mappings = {
		browse = {
			["<CR>"] = "open",
			["<C-S>"] = "split",
			["<C-V>"] = "vsplit",
			["<C-T>"] = "tab",
			["<Esc>"] = "park",
			["<C-C>"] = "close",
			["<C-O>"] = "sources",
			["<C-Right>"] = "source_next",
			["<C-Left>"] = "source_prev",
			["<C-R>"] = "root",
			["<C-P>"] = "up",
			["<Up>"] = "up",
			["<C-N>"] = "down",
			["<Down>"] = "down",
			["<C-U>"] = "page_up",
			["<C-D>"] = "page_down",
			["<ScrollWheelUp>"] = "scroll_up",
			["<ScrollWheelDown>"] = "scroll_down",
			["<BS>"] = "backspace",
			["<Del>"] = "delete",
			["<C-W>"] = "delete_word",
			["<Left>"] = "caret_left",
			["<C-B>"] = "caret_left",
			["<Right>"] = "caret_right",
			["<C-F>"] = "caret_right",
			["<Home>"] = "home",
			["<C-A>"] = "home",
			["<End>"] = "end",
			["<C-E>"] = "end",
			["<LeftMouse>"] = "select",
			["<2-LeftMouse>"] = "open_mouse",
		},
		sources = {
			["f"] = "files",
			["d"] = "dirs",
			["b"] = "buffers",
			["r"] = "recent",
			["c"] = "changed",
			["g"] = "grep",
			["s"] = "symbols",
			["t"] = "doc_symbols",
			["u"] = "references",
			["i"] = "implementations",
			["e"] = "diagnostics",
		},
	},
}

M.values = nil

--- Canonicalize every lhs in a `mappings` table to the form `keytrans()`
--- emits, so a user's `<C-o>` overrides the default `<C-O>` instead of
--- sitting beside it. `tbl_deep_extend` matches raw strings, so this has to
--- happen before the merge; dispatch canonicalizes again, harmlessly.
local function canonical_mappings(mappings)
	local out = {}
	for ctx, map in pairs(mappings) do
		if type(map) == "table" then
			local canon = {}
			for lhs, action in pairs(map) do
				canon[keymap.canonical(lhs)] = action
			end
			out[ctx] = canon
		else
			out[ctx] = map
		end
	end
	return out
end

--- Lazily build the effective config (defaults, or defaults merged by setup()).
function M.get()
	if not M.values then
		M.values = vim.tbl_deep_extend("force", {}, M.defaults)
	end
	return M.values
end

--- Merge user options over the defaults.
function M.setup(opts)
	opts = vim.tbl_extend("force", {}, opts or {})
	if type(opts.mappings) == "table" then
		opts.mappings = canonical_mappings(opts.mappings)
	end
	M.values = vim.tbl_deep_extend("force", {}, M.defaults, opts)
	return M.values
end

return M
