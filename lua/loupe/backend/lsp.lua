--- lsp backend: document and workspace symbols from attached language servers.
---
--- Availability is dynamic (a client supporting the relevant method must be
--- attached). Requests target `ctx.buf` explicitly because the picker itself
--- runs in a scratch buffer with no LSP attachment. Responses from every client
--- are merged; a 5s safety net delivers whatever arrived if a server never
--- answers.

local parse = require("loupe.backend.parse")

local M = {}

M.available = function()
	return #vim.lsp.get_clients({ method = "workspace/symbol" }) > 0
		or #vim.lsp.get_clients({ method = "textDocument/documentSymbol" }) > 0
end

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

--- Symbol-kind glyph via `mini.icons` (optional dependency, so pcall).
local function kind_icon(kind)
	local name = kind and vim.lsp.protocol.SymbolKind[kind]
	if not name then
		return nil, nil
	end
	local ok, mini = pcall(require, "mini.icons")
	if ok and type(mini.get) == "function" then
		return mini.get("lsp", name)
	end
	return nil, nil
end

--- Flatten SymbolInformation / hierarchical DocumentSymbol results.
local function flatten(symbols, out, path, root, depth)
	for _, sym in ipairs(symbols) do
		local range = sym.range or (sym.location and sym.location.range)
		if sym.name and range then
			local icon, icon_hl = kind_icon(sym.kind)
			out[#out + 1] = {
				rel = parse.relpath(root, path),
				abs = path,
				label = string.rep("  ", depth) .. sym.name,
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

M.list = {
	--- Symbols in `ctx.buf`, flattened and fuzzy-filtered by the session.
	doc_symbols = function(ctx, cb)
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
}

M.search = {
	--- Workspace symbols for `query` (`ctx.root` scopes which clients answer).
	symbols = function(query, ctx, cb)
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
						local icon, icon_hl = kind_icon(sym.kind)
						out[#out + 1] = {
							rel = rel,
							abs = path,
							label = name .. "  " .. rel,
							lnum = (loc.range.start and loc.range.start.line + 1) or 1,
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
}

return M
