---@class Unpack.Spec : vim.pack.Spec
---@field config fun()?
---@field defer boolean?
---@field dependencies Unpack.Spec[]?

local M = {} ---@class Unpack

---@param opts Unpack.Config.UserOpts?
function M.setup(opts)
	local commands = require("commands")
	local config = require("config")

	config.setup(opts)
	require("extensions")

	M.clean = commands.clean
	M.update = commands.update

	vim.api.nvim_create_user_command("PackClean", commands.clean, {})
	vim.api.nvim_create_user_command("PackUpdate", commands.update, {})

	vim.api.nvim_create_augroup(config.opts.group, { clear = true })

	vim.api.nvim_create_autocmd("PackChanged", {
		callback = function(args)
			if args.data.kind == "install" or args.data.kind == "update" then
				commands.build(args.data)
			end
		end,
		group = config.opts.group,
	})

	commands.load(config)

	vim.g.unpack_loaded = true
end

return M
