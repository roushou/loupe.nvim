local h = require("tests.harness")
local keymap = require("loupe.keymap")
local config = require("loupe.config")

h.test("canonical equates <C-s> and <C-S>", function()
	h.eq(keymap.canonical("<C-s>"), keymap.canonical("<C-S>"))
	h.eq(keymap.canonical("<C-s>"), "<C-S>")
end)

h.test("canonical leaves printable keys alone", function()
	h.eq(keymap.canonical("r"), "r")
	h.eq(keymap.canonical("<Space>"), "<Space>")
	h.eq(keymap.canonical("<lt>"), "<lt>")
end)

h.test("build canonicalizes lhs and drops unbinds", function()
	local map = keymap.build({ ["<C-s>"] = "split", ["<C-X>"] = false, ["q"] = 12 })
	h.eq(map["<C-S>"], "split")
	h.eq(map["<C-X>"], nil)
	h.eq(map["q"], nil)
end)

h.test("resolve maps every context", function()
	local maps = keymap.resolve(config.defaults.mappings)
	h.eq(maps.browse["<CR>"], "open")
	h.eq(maps.browse["<C-O>"], "sources")
	h.eq(maps.browse["<C-R>"], "root")
	h.eq(maps.sources["b"], "buffers")
	h.eq(maps.sources["g"], "grep")
	h.eq(maps.sources["s"], "symbols")
	h.eq(maps.sources["t"], "doc_symbols")
	h.eq(maps.sources["u"], "references")
	h.eq(maps.sources["i"], "implementations")
	h.eq(maps.sources["e"], "diagnostics")
end)

h.test("resolve tolerates a missing mappings table", function()
	local maps = keymap.resolve(nil)
	h.eq(maps.browse, {})
	h.eq(maps.sources, {})
end)

h.test("setup canonicalizes binding keys so a lower-case unbind overrides the default", function()
	-- The defaults spell control keys upper-case (`<C-O>`), but people write
	-- `<C-o>`. The merge matches raw strings, so setup() must canonicalize
	-- before merging or the unbind silently sits beside the default.
	config.setup({ mappings = { browse = { ["<C-o>"] = false, ["<C-g>"] = "sources" } } })
	local maps = keymap.resolve(config.get().mappings)
	config.setup({}) -- restore the defaults for the tests that follow
	h.eq(maps.browse["<C-O>"], nil, "the lower-case unbind must remove the default <C-O>")
	h.eq(maps.browse["<C-G>"], "sources", "the new binding survives")
	h.eq(maps.browse["<C-R>"], "root", "untouched defaults survive")
	h.eq(maps.browse["<CR>"], "open")
end)
