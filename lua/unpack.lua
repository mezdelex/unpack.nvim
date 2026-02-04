---@class UnPack.Spec : vim.pack.Spec
---@field config? fun()
---@field defer? boolean
---@field dependencies? UnPack.Spec[]

local M = {} ---@class UnPack

---@param opts? UnPack.Config.UserOpts
function M.setup(opts)
	local commands = require("commands")
	local config = require("config")
	local group = "UnPack"
	require("extensions")

	config.setup(opts)

	vim.api.nvim_create_augroup(group, { clear = true })

	vim.api.nvim_create_autocmd("PackChanged", {
		callback = function(args)
			local kind = args.data.kind ---@type string

			if kind == "install" or kind == "update" then
				local spec = args.data.spec ---@type UnPack.Spec

				commands.build({ spec })
			end
		end,
		group = group,
	})

	vim.api.nvim_create_user_command("PackBuild", commands.build, {})
	vim.api.nvim_create_user_command("PackClean", commands.clean, {})
	vim.api.nvim_create_user_command("PackLoad", commands.load, {})
	vim.api.nvim_create_user_command("PackUpdate", commands.update, {})

	commands.load()

	M.commands = commands

	vim.g.unpack_loaded = true
end

return M
