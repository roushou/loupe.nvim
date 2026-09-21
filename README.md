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
| `<C-o>` | Source menu (`f d b r c g s t e`) |
| `<C-x>` | Action menu (`r` rename, `d` delete, `a` add, `c` duplicate, `y` yank, `o` open externally, `q` quickfix) |
| `<Tab>` | Mark (marks feed quickfix) |
| `<C-r>` | Jump back to the project root |
| `<BS>` | On an empty query, go up a directory |
| `<C-p>`/`<C-n>` | Move up/down · `<C-d>`/`<C-u>` page |
| `<Esc>` / `<C-c>` | Close |

`:Loupe [source]` opens a specific source (`:Loupe grep`, `:Loupe symbols`, …).

## Configuration

```lua
require("loupe").setup({
  default_source = "files",
  trash = true,          -- delete via the OS trash when available
  frecency = true,       -- order the empty-query list by use
  git = true,            -- show git status markers
  preview = { diagnostics = true },
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

## License

[MIT](./LICENSE)
