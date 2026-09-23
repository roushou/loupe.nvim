--- symbols: named declarations from attached language servers, scoped either
--- to one document or to the whole workspace.
---
--- Both scopes answer the same question and share the same plumbing, so they
--- live together. Requests target `ctx.buf` explicitly because the picker
--- itself runs in a scratch buffer with no LSP attachment. Responses from
--- every client are merged; a 5s safety net delivers whatever arrived if a
--- server never answers.

local parse = require("loupe.backend.parse")

--- Deliver `cb(out, true)` once `n` responses have arrived (or after 5s).
local function collector(n, cb)
	local out = {}
	local state = { done = 0 }
	local delivered = false
	local timer = vim.uv.new_timer()

	local function deliver()
		if delivered then
			return
		end
		delivered = true
		timer:stop()
		timer:close()
		vim.schedule(function()
			cb(out, true)
		end)
	end

	timer:start(5000, 0, vim.schedule_wrap(deliver))

	return out, function()
		state.done = state.done + 1
		if state.done >= n then
			deliver()
		end
	end
end

--- Symbol-kind name, glyph and highlight. The glyph comes from `mini.icons`
--- when it is installed (optional dependency, so pcall).
local function kind_of(kind)
	local name = kind and vim.lsp.protocol.SymbolKind[kind]
	if not name then
		return nil, nil, nil
	end
	local ok, mini = pcall(require, "mini.icons")
	if ok and type(mini.get) == "function" then
		local icon, hl = mini.get("lsp", name)
		return name, icon, hl
	end
	return name, nil, nil
end

--- Flatten SymbolInformation / hierarchical DocumentSymbol results.
local function flatten(symbols, out, path, root, depth)
	for _, sym in ipairs(symbols) do
		local range = sym.range or (sym.location and sym.location.range)
		if sym.name and range then
			local kind, icon, icon_hl = kind_of(sym.kind)
			local text = string.rep("  ", depth) .. sym.name
			out[#out + 1] = {
				rel = parse.relpath(root, path),
				abs = path,
				text = text,
				meta = kind,
				label = kind and (text .. "  " .. kind) or text,
				lnum = (range.start and range.start.line + 1) or 1,
				col = 0,
				icon = icon,
				icon_hl = icon_hl,
				dir = false,
			}
		end
		if sym.children then
			flatten(sym.children, out, path, root, depth + 1)
		end
	end
end

return {
	list = {
		--- Symbols in `ctx.buf`, flattened and fuzzy-filtered by the session.
		doc_symbols = {
			lsp = function(ctx, cb)
				local buf = ctx.buf
				if not (buf and vim.api.nvim_buf_is_valid(buf)) then
					cb({}, true)
					return
				end
				local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
				if #clients == 0 then
					cb({}, true)
					return
				end
				local path = vim.api.nvim_buf_get_name(buf)
				local out, finish = collector(#clients, cb)
				local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
				for _, c in ipairs(clients) do
					c:request("textDocument/documentSymbol", params, function(err, result)
						if not err and type(result) == "table" then
							flatten(result, out, path, ctx.root, 0)
						end
						finish()
					end, buf)
				end
			end,
		},
	},

	search = {
		--- Workspace symbols for `query` (`ctx.root` scopes which clients answer).
		symbols = {
			lsp = function(query, ctx, cb)
				local buf = ctx.buf
				if not (buf and vim.api.nvim_buf_is_valid(buf)) then
					cb({}, true)
					return
				end
				local capable = vim.tbl_filter(function(c)
					return c:supports_method("workspace/symbol", buf)
				end, vim.lsp.get_clients({ bufnr = buf }))
				if #capable == 0 then
					cb({}, true)
					return
				end

				local out, finish = collector(#capable, cb)
				vim.lsp.buf_request(buf, "workspace/symbol", { query = query }, function(err, result)
					if not err and type(result) == "table" then
						for _, sym in ipairs(result) do
							local loc = sym.location or sym
							if loc and loc.uri and loc.range then
								local path = vim.uri_to_fname(loc.uri)
								local rel = parse.relpath(ctx.root, path)
								local name = sym.name or "?"
								if sym.containerName and sym.containerName ~= "" then
									name = name .. " (" .. sym.containerName .. ")"
								end
								local _, icon, icon_hl = kind_of(sym.kind)
								local lnum = (loc.range.start and loc.range.start.line + 1) or 1
								local where = parse.location(rel, lnum)
								out[#out + 1] = {
									rel = rel,
									abs = path,
									text = name,
									meta = where,
									label = name .. "  " .. where,
									lnum = lnum,
									col = 0,
									icon = icon,
									icon_hl = icon_hl,
									dir = false,
								}
							end
						end
					end
					finish()
				end)
			end,
		},
	},
}
