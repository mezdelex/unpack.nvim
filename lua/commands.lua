---@private
---@return Unpack.Spec[], Unpack.Spec[], string[]
local function get_specs_and_names()
	local config = require("config")
	local plugin_fpaths = vim.fn.glob(config.opts.config_path .. config.opts.plugins_rpath .. "*.lua", true, true) ---@type string[]
	local deferred_specs, eager_specs, names = {}, {}, {} ---@type Unpack.Spec[], Unpack.Spec[], string[]

	---@private
	---@param _spec Unpack.Spec
	local function fill_specs_and_names(_spec)
		if _spec.defer then
			deferred_specs[#deferred_specs + 1] = _spec
		else
			eager_specs[#eager_specs + 1] = _spec
		end
		names[#names + 1] = vim.fn.fnamemodify(_spec.src, ":t")
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
					if type(dep.src) == "string" then
						fill_specs_and_names(dep)
					else
						vim.schedule(function()
							vim.notify(
								("Invalid dependency for %s, missing src"):format(plugin_name),
								vim.log.levels.ERROR
							)
						end)
					end
				end
			end

			if type(spec.src) == "string" then
				fill_specs_and_names(spec)
			else
				vim.schedule(function()
					vim.notify(("Invalid spec for %s, missing src"):format(plugin_name), vim.log.levels.ERROR)
				end)
			end
		end
	end

	return deferred_specs, eager_specs, names
end

---@private
---@return string[]
local function get_package_names()
	local config = require("config")
	local package_fpaths = vim.fn.glob(config.opts.data_path .. config.opts.packages_rpath .. "*/", false, true) ---@type string[]
	local package_names = {} ---@type string[]

	for _, package_fpath in ipairs(package_fpaths) do
		local package_name = vim.fn.fnamemodify(package_fpath:sub(1, -2), ":t")

		if package_name ~= config.opts.unpack_package then
			package_names[#package_names + 1] = package_name
		end
	end

	return package_names
end

---@private
---@param package_fpath string
---@param spec Unpack.Spec
---@param config Unpack.Config
local function handle_conflicts(package_fpath, spec, config)
	if config.opts.is_win32 ~= 1 or type(spec.data.conflicts) ~= "table" then
		return
	end

	for _, conflict in ipairs(spec.data.conflicts) do
		if type(conflict) == "string" then
			local matches = vim.fn.glob(package_fpath .. "/**/" .. conflict, false, true) ---@type string[]

			for _, match in ipairs(matches) do
				local renamed = match .. config.opts.conflict_suffix
				local ok, err = vim.uv.fs_rename(match, renamed)

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
---@param specs Unpack.Spec[]
local function handle_builds(specs)
	for _, spec in ipairs(specs) do
		if
			type(spec.src) ~= "string"
			or type(spec.data) ~= "table"
			or type(spec.data.build) ~= "string"
			or spec.data.build:is_empty_or_whitespace()
		then
			goto continue
		end

		local config = require("config")
		local package_name = vim.fn.fnamemodify(spec.src, ":t")
		local package_fpath = config.opts.data_path .. config.opts.packages_rpath .. package_name ---@type string
		local stat = vim.uv.fs_stat(package_fpath)

		if not stat or stat.type ~= "directory" then
			goto continue
		end

		handle_conflicts(package_fpath, spec, config)

		vim.schedule(function()
			vim.notify(("Building %s..."):format(package_name), vim.log.levels.WARN)
			local response = vim.system(vim.split(spec.data.build, " "), { cwd = package_fpath }):wait()
			vim.notify(
				("Build %s for %s"):format(response.code ~= 0 and "failed" or "successful", package_name),
				response.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.INFO
			)
		end)

		::continue::
	end
end

---@private
---@param spec Unpack.Spec
---@param package_name string
---@param config Unpack.Config
local function clean_conflicts(spec, package_name, config)
	if config.opts.is_win32 ~= 1 or type(spec.data) ~= "table" or type(spec.data.conflicts) ~= "table" then
		return
	end

	local matches = vim.fn.glob(
		config.opts.data_path .. config.opts.packages_rpath .. package_name .. "/**/*" .. config.opts.conflict_suffix,
		false,
		true
	) ---@type string[]

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

---@param specs? Unpack.Spec[]
M.build = function(specs)
	local deferred_specs = {} ---@type Unpack.Spec[]

	if not specs or #specs == 0 then
		deferred_specs, specs, _ = get_specs_and_names()
	end

	handle_builds(deferred_specs)
	handle_builds(specs)
end
M.clean = function()
	local config = require("config")
	local deferred_specs, eager_specs, names = get_specs_and_names()
	local idx, names_set, packages_to_delete = 1, {}, {} ---@type number, table<string, Unpack.Spec>, string[]
	local package_names = get_package_names()

	---@private
	---@param _specs Unpack.Spec[]
	local function fill_names_set(_specs)
		for _, spec in ipairs(_specs) do
			names_set[names[idx]] = spec
			idx = idx + 1
		end
	end

	fill_names_set(deferred_specs)
	fill_names_set(eager_specs)

	for _, package_name in ipairs(package_names) do
		if names_set[package_name] == nil then
			packages_to_delete[#packages_to_delete + 1] = package_name
		else
			clean_conflicts(names_set[package_name], package_name, config)
		end
	end

	vim.pack.del(packages_to_delete)
end
M.load = function()
	local config = require("config")
	local deferred_specs, eager_specs, _ = get_specs_and_names()

	load_specs(eager_specs, config)
	vim.schedule(function()
		load_specs(deferred_specs, config)
	end)
end
M.update = function()
	local config = require("config")

	vim.pack.update(nil, config.opts.update_options)
end

return M
