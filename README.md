# loupe.nvim

A bottom-docked fuzzy finder for Neovim with a full-viewport live preview.

Loupe is **source-based**: the source menu changes *what* is searched, while
matching, previewing and actions stay the same. Browsing never opens a file
buffer — files are read into a scratch buffer, and only the choose actions
create real buffers.

```
f files · d dirs · b buffers · r recent · c changed · g grep · s symbols · t doc_symbols · e diagnostics
```

## Requirements

- Neovim **≥ 0.11**
- `fd`, `rg`, `git` on `$PATH` (each optional; Loupe degrades gracefully)
- A [Nerd Font](https://www.nerdfonts.com/) for the icons

## Install

**lazy.nvim**

```lua
{
  "roushou/loupe.nvim",
  version = "*",
  cmd = "Loupe",
  opts = {},
}
```

**vim.pack** (Neovim 0.12)

```lua
vim.pack.add({ { src = "https://github.com/roushou/loupe.nvim", version = vim.version.range("*") } })
require("loupe").setup({})
```

**rocks.nvim**

```vim
:Rocks install loupe.nvim
```

Loupe creates **no keymaps**. Suggested:

```lua
vim.keymap.set("n", "<C-p>", function() require("loupe").open() end, { desc = "Find files" })
vim.keymap.set("n", "<leader>fw", function() require("loupe").open({ source = "grep" }) end)
vim.keymap.set("n", "<leader>ss", function() require("loupe").open({ source = "doc_symbols" }) end)
```

## Usage

| Key | Action |
| --- | --- |
| `<CR>` | Open |
| `<C-s>` / `<C-v>` / `<C-t>` | Open in split / vsplit / tab |
| `<C-o>` | Source menu — marks each tab with its key |
| `<C-Right>` / `<C-Left>` | Next / previous source |
| `<C-x>` | Action menu (`r` rename, `d` delete — closes the buffer in the `buffers` source, `a` add, `c` duplicate, `y`/`Y`/`n`/`D` yank path/relative/name/dir, `o` open externally, `q` quickfix) |
| `<Tab>` | Mark (marks feed quickfix) |
| `<C-r>` | Jump back to the project root |
| `<BS>` | On an empty query, go up a directory |
| `<C-p>`/`<C-n>` | Move up/down · `<C-d>`/`<C-u>` page |
| `<Esc>` / `<C-c>` | Close |

`:Loupe [source]` opens a specific source (`:Loupe grep`, `:Loupe symbols`, …).

The window bar carries the source tabs and the keys that open each menu; the
prompt row carries the source glyph and the count (`shown/total` for list
sources, `found` for live ones — `+` means the search stopped at
`max_results`, `…` that it is still running). `<C-o>` and `<C-x>` mark each
entry with its key and tint that strip rather than opening anything.
Reopening renders the last file list at once and refreshes it in the
background.

## API

- `require("loupe").setup(opts)` — configure (see below)
- `.open({ source = "grep" })` — open, optionally on a source
- `.close()`, `.toggle()`, `.is_active()`

Full reference: `:help loupe`.

## Configuration

```lua
require("loupe").setup({
  default_source = "files",
  trash = true,          -- delete via the OS trash when available
  frecency = true,       -- order the empty-query list by use
  git = true,            -- show git status markers
  preview = { diagnostics = true, max_lines = 2000, max_bytes = 1048576 },
  backends = { files = { "fd", "rg", "git" }, grep = { "rg", "git" } },
  mappings = {
    browse = { ["<CR>"] = "split" },
    menu = { ["m"] = "rename" },
    sources = { ["t"] = "changed" },
  },
})
```

See `:help loupe-configuration` for the full option set. Every keybinding is
data — set a value to `false` to unbind.

## Appearance

Every colour is a highlight group linked to a standard one, so themes apply
without configuration. Override any of them to taste:

```lua
vim.api.nvim_set_hl(0, "LoupeSelection", { link = "CursorLine" })
```

| Group | Default | Used for |
| --- | --- | --- |
| `LoupeSelection` | `Visual` | the selected row |
| `LoupeMatch` | `Search` | matched characters |
| `LoupeDir` | `Comment` | the parent directory of a path |
| `LoupeMeta` | `LineNr` | the right-hand metadata column |
| `LoupeMetaFlag` | `DiagnosticWarn` | the modified-buffer marker |
| `LoupeTab` / `LoupeTabActive` | computed / `Title` | source tabs |
| `LoupeTabSelect` / `LoupeTabSelectActive` / `LoupeTabSelectKey` | computed from `Normal` | the strip while a menu is open, and the key to press |
| `LoupeBorder` | `StatusLine` | the window bar, and the text every unstyled part of it inherits |
| `LoupePrompt` / `LoupePromptCaret` | `Title` | prompt prefix and caret |
| `LoupeGhost` | `Comment` | the source name on an empty query |
| `LoupeCount` | `LineNr` | the result count |
| `LoupeGit*` | diagnostic colours | git status markers |

## Dependencies

Loupe integrates with `mini.icons` (file/symbol icons) and `fff` (an optional
fuzzy-search engine) when available, and uses LSP for the `symbols` and
`doc_symbols` sources. All are optional. Run `:checkhealth loupe` to see what
was detected.

## Development

Pure headless tests (no plugins required):

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run.lua
```

End-to-end benchmark (generates a 20k-file fixture on first run, drives the
real picker through a scripted key queue and prints a timing table):

```sh
nvim --headless -u tests/minimal_init.lua -l tests/bench.lua
```

Every scenario states what its probes must see, and the run ends in
`BENCH PASS` or `BENCH FAIL`. Add `--smoke` for the same scenarios over a
small fixture — that is what CI runs, to catch the harness rotting rather
than to measure anything.

## License

[MIT](./LICENSE)
