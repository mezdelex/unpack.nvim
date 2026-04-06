---@class Unpack.Config.UserOpts
---@field add_options vim.pack.keyset.add?
---@field update_options vim.pack.keyset.update?

local M = {} ---@class Unpack.Config

M.opts = { ---@class Unpack.Config.Opts
	add_options = { confirm = false }, ---@type vim.pack.keyset.add
	config_path = vim.fn.stdpath("config"),
	conflict_suffix = ".conflict",
	group = "Unpack",
	is_win32 = vim.fn.has("win32"),
	plugins_rpath = "/lua/plugins/",
	unpack_package = "unpack.nvim",
	update_options = { force = true }, ---@type vim.pack.keyset.update
}
---@param opts Unpack.Config.UserOpts?
M.setup = function(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
