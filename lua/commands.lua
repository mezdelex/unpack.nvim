---@private
---@param data table
local function handle_conflicts(data)
	local config = require("config")
	if config.opts.is_win32 ~= 1 or type(data.spec.data.conflicts) ~= "table" then
		return
	end

	for _, conflict in ipairs(data.spec.data.conflicts) do
		if type(conflict) == "string" then
			local matches = vim.fn.glob(data.path .. "/**/" .. conflict, false, true) ---@type string[]
			for _, match in ipairs(matches) do
				local ok, err = vim.uv.fs_rename(match, match .. config.opts.conflict_suffix)
				if not ok then
					vim.schedule(function()
						vim.notify(("Rename failed: %s"):format(err), vim.log.levels.ERROR)
					end)
				end
			end
		end
	end
end

---@private
---@param plug_data vim.pack.PlugData
---@param config Unpack.Config
local function clean_conflicts(plug_data, config)
	if
		config.opts.is_win32 ~= 1
		or type(plug_data.spec.data) ~= "table"
		or type(plug_data.spec.data.conflicts) ~= "table"
	then
		return
	end

	local matches = vim.fn.glob(plug_data.path .. "/**/*" .. config.opts.conflict_suffix, false, true) ---@type string[]
	for _, match in ipairs(matches) do
		local ok, err = vim.uv.fs_unlink(match)
		if not ok then
			vim.schedule(function()
				vim.notify(("Unlink failed: %s"):format(err), vim.log.levels.ERROR)
			end)
		end
	end
end

---@private
---@param config Unpack.Config
---@return Unpack.Spec[], Unpack.Spec[]
local function get_specs(config)
	local plugin_fpaths = vim.fn.glob(config.opts.config_path .. config.opts.plugins_rpath .. "*.lua", true, true) ---@type string[]
	local deferred_specs, eager_specs = {}, {} ---@type Unpack.Spec[], Unpack.Spec[]

	---@private
	---@param _spec Unpack.Spec
	---@param _plugin_name string
	---@return boolean
	local function validate_spec(_spec, _plugin_name)
		if type(_spec.src) ~= "string" then
			vim.schedule(function()
				vim.notify(("Invalid spec for %s, missing src"):format(_plugin_name), vim.log.levels.ERROR)
			end)
			return false
		end
		return true
	end

	---@private
	---@param _spec Unpack.Spec
	local function add_spec(_spec)
		if _spec.defer then
			deferred_specs[#deferred_specs + 1] = _spec
		else
			eager_specs[#eager_specs + 1] = _spec
		end
	end

	for _, plugin_fpath in ipairs(plugin_fpaths) do
		local plugin_name = vim.fn.fnamemodify(plugin_fpath, ":t:r")
		local success, spec = pcall(require, "plugins." .. plugin_name) ---@type boolean, Unpack.Spec

		if not success then
			vim.schedule(function()
				vim.notify(("Failed to load plugin spec for %s"):format(plugin_name), vim.log.levels.ERROR)
			end)
		elseif type(spec) ~= "table" then
			vim.schedule(function()
				vim.notify(("Invalid spec for %s, not a table"):format(plugin_name), vim.log.levels.ERROR)
			end)
		else
			if type(spec.dependencies) == "table" then
				for _, dep in ipairs(spec.dependencies) do
					if validate_spec(dep, plugin_name) then
						add_spec(dep)
					end
				end
			end

			if validate_spec(spec, plugin_name) then
				add_spec(spec)
			end
		end
	end

	return deferred_specs, eager_specs
end

---@private
---@param specs Unpack.Spec[]
---@param config Unpack.Config
local function load_specs(specs, config)
	vim.pack.add(specs, config.opts.add_options)

	for _, spec in ipairs(specs) do
		if type(spec.config) == "function" then
			spec.config()
		end
	end
end

local M = {} ---@class Unpack.Commands

---@param data table
M.build = function(data)
	if
		type(data.spec.data) ~= "table"
		or type(data.spec.data.build) ~= "string"
		or data.spec.data.build:is_empty_or_whitespace()
	then
		return
	end

	handle_conflicts(data)

	vim.schedule(function()
		vim.notify(("Building %s..."):format(data.spec.name), vim.log.levels.WARN)
		local response = vim.system(vim.split(data.spec.data.build, " "), { cwd = data.path }):wait()
		vim.notify(
			("Build %s for %s"):format(response.code ~= 0 and "failed" or "successful", data.spec.name),
			response.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.INFO
		)
	end)
end
M.clean = function()
	local config = require("config")
	local packages_to_delete = {} ---@type string[]

	for _, plug_data in ipairs(vim.pack.get(nil, { info = false })) do
		if plug_data.spec.name ~= config.opts.unpack_package and not plug_data.active then
			packages_to_delete[#packages_to_delete + 1] = plug_data.spec.name
		else
			clean_conflicts(plug_data, config)
		end
	end

	vim.pack.del(packages_to_delete)
end
---@param config Unpack.Config
M.load = function(config)
	local deferred_specs, eager_specs = get_specs(config)

	load_specs(eager_specs, config)
	vim.schedule(function()
		load_specs(deferred_specs, config)
	end)
end
M.update = function()
	vim.pack.update(nil, require("config").opts.update_options)
end

return M
