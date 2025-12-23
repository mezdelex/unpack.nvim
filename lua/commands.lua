---@private
---@return UnPack.Spec[], string[]
local function get_specs_and_names()
	local config = require("config")
	local plugin_fpaths = vim.fn.glob(config.opts.config_path .. config.opts.plugins_rpath .. "*.lua", true, true) ---@type string[]
	local specs, names = {}, {} ---@type UnPack.Spec[], string[]

	for _, plugin_fpath in ipairs(plugin_fpaths) do
		local plugin_name = vim.fn.fnamemodify(plugin_fpath, ":t:r")
		local success, spec = pcall(require, "plugins." .. plugin_name) ---@type boolean, UnPack.Spec

		if not success then
			vim.schedule(function()
				vim.notify(("Failed to load plugin spec for %s"):format(plugin_name), vim.log.levels.ERROR)
			end)
		elseif type(spec) ~= "table" then
			vim.schedule(function()
				vim.notify(("Invalid spec for %s, not a table"):format(plugin_name), vim.log.levels.ERROR)
			end)
		else
			if spec.dependencies and type(spec.dependencies) == "table" then
				for _, dep in ipairs(spec.dependencies) do
					if dep.src and type(dep.src) == "string" then
						specs[#specs + 1] = dep
						names[#names + 1] = vim.fn.fnamemodify(dep.src, ":t")
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
			if spec.src and type(spec.src) == "string" then
				specs[#specs + 1] = spec
				names[#names + 1] = vim.fn.fnamemodify(spec.src, ":t")
			else
				vim.schedule(function()
					vim.notify(("Invalid spec for %s, missing src"):format(plugin_name), vim.log.levels.ERROR)
				end)
			end
		end
	end

	return specs, names
end

---@private
---@return string[]
local function get_package_names()
	local config = require("config")
	local package_fpaths = vim.fn.glob(config.opts.data_path .. config.opts.packages_rpath .. "*/", false, true) ---@type string[]
	local package_names = {} ---@type string[]

	for _, package_fpath in ipairs(package_fpaths) do
		local package_name = vim.fn.fnamemodify(package_fpath:sub(1, -2), ":t")

		package_names[#package_names + 1] = package_name
	end

	return package_names
end

---@private
---@param package_fpath string
---@param conflict string
local function safe_delete_conflict(package_fpath, conflict)
	local matches = vim.fn.glob(package_fpath .. "/**/" .. conflict, false, true) ---@type string[]

	for _, match in ipairs(matches) do
		local renamed = match .. ".conflict." .. vim.loop.now()
		local ok, err = vim.uv.fs_rename(match, renamed)
		if not ok then
			vim.schedule(function()
				vim.notify(("Rename failed: %s"):format(err), vim.log.levels.ERROR)
			end)
			return
		end

		ok, err = vim.uv.fs_unlink(renamed)
		if not ok then
			vim.schedule(function()
				vim.notify(("Unlink failed: %s"):format(err), vim.log.levels.ERROR)
			end)
		end
	end
end

---@private
---@param spec UnPack.Spec
local function handle_build(spec)
	if
		type(spec.src) ~= "string"
		or type(spec.data) ~= "table"
		or type(spec.data.build) ~= "string"
		or spec.data.build:is_empty_or_whitespace()
	then
		return
	end

	local config = require("config")
	local package_name = vim.fn.fnamemodify(spec.src, ":t")
	local package_fpath = config.opts.data_path .. config.opts.packages_rpath .. package_name ---@type string
	local stat = vim.uv.fs_stat(package_fpath)

	if not stat or stat.type ~= "directory" then
		return
	end

	if vim.fn.has("win32") == 1 and type(spec.data.conflicts) == "table" then
		for _, conflict in ipairs(spec.data.conflicts) do
			if type(conflict) == "string" then
				safe_delete_conflict(package_fpath, conflict)
			end
		end
	end

	vim.schedule(function()
		vim.notify(("Building %s..."):format(package_name), vim.log.levels.WARN)
		local response = vim.system(vim.split(spec.data.build, " "), { cwd = package_fpath }):wait()
		vim.notify(
			("Build %s for %s"):format(response.code ~= 0 and "failed" or "successful", package_name),
			response.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.INFO
		)
	end)
end

local M = {} ---@class UnPack.Commands

---@param specs? UnPack.Spec[]
M.build = function(specs)
	if not specs or #specs == 0 then
		specs, _ = get_specs_and_names()
	end

	for _, spec in ipairs(specs) do
		handle_build(spec)
	end
end
M.clean = function()
	local _, names = get_specs_and_names()
	local package_names = get_package_names()
	local names_set, packages_to_delete = {}, {} ---@type table<string, boolean>, string[]

	for _, name in ipairs(names) do
		names_set[name] = true
	end

	for _, package_name in ipairs(package_names) do
		if not names_set[package_name] then
			packages_to_delete[#packages_to_delete + 1] = package_name
		end
	end

	vim.pack.del(packages_to_delete)
end
M.load = function()
	local config = require("config")
	local specs, _ = get_specs_and_names()

	vim.pack.add(specs, config.opts.add_options)

	for _, spec in ipairs(specs) do
		if spec.config and type(spec.config) == "function" then
			if spec.defer then
				vim.schedule(spec.config)
			else
				spec.config()
			end
		end
	end
end
M.pull = function()
	local config = require("config")
	local unpack_fpath = config.opts.data_path .. config.opts.unpack_rpath
	local stat = vim.uv.fs_stat(unpack_fpath)

	if stat and stat.type == "directory" then
		vim.system({ "git", "fetch", "--all" }, { cwd = unpack_fpath }, function()
			vim.system({ "git", "reset", "--hard", "origin/main" }, { cwd = unpack_fpath }, function()
				vim.system({ "git", "clean", "-fdx" }, { cwd = unpack_fpath }, function()
					vim.schedule(function()
						vim.cmd(("helptags %s/doc"):format(unpack_fpath))
					end)
				end)
			end)
		end)
	end
end
M.update = function()
	local config = require("config")

	vim.pack.update(nil, config.opts.update_options)
end

return M
