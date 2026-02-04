---@diagnostic disable: duplicate-set-field
local assert = require("luassert")

describe("unpack.setup", function()
	local unpack

	before_each(function()
		package.loaded["unpack"] = nil
		package.loaded["commands"] = nil
		package.loaded["config"] = nil
		package.loaded["extensions"] = nil

		local calls = {}
		package.loaded["commands"] = {
			build = function(...)
				table.insert(calls, { "build", ... })
			end,
			clean = function(...)
				table.insert(calls, { "clean", ... })
			end,
			load = function(...)
				table.insert(calls, { "load", ... })
			end,
			update = function(...)
				table.insert(calls, { "update", ... })
			end,
			__calls = calls,
		}

		local config_setup_called
		package.loaded["config"] = {
			setup = function(opts)
				config_setup_called = opts or true
			end,
			__called = function()
				return config_setup_called
			end,
		}

		package.loaded["extensions"] = true

		_G.vim = require("test.fixtures").vim_unpack_fixtures

		unpack = require("lua.unpack")
	end)

	it("calls config.setup with opts", function()
		unpack.setup({ foo = "bar" })
		local config = package.loaded["config"]
		assert.same({ foo = "bar" }, config.__called())
	end)

	it("creates augroup and autocmd for PackChanged", function()
		unpack.setup()
		local ac = _G.__last_autocmd
		assert.same("PackChanged", ac.event)
		assert.is_function(ac.opts.callback)
	end)

	it("autocmd triggers commands.build for install/update", function()
		local commands = package.loaded["commands"]
		unpack.setup()
		local cb = _G.__last_autocmd.opts.callback

		cb({ data = { kind = "install", spec = { src = "a" } } })
		cb({ data = { kind = "update", spec = { src = "b" } } })
		cb({ data = { kind = "remove", spec = { src = "c" } } })

		local names = {}
		for _, c in ipairs(commands.__calls) do
			table.insert(names, c[1])
		end

		assert.True(vim.tbl_contains(names, "build"))
		assert.True(vim.tbl_contains(names, "build"))
		assert.False(vim.tbl_contains(names, "remove"))
	end)

	it("registers user commands", function()
		unpack.setup()
		local uc = _G.__last_user_command
		assert.is_function(uc.PackBuild.fn)
		assert.is_function(uc.PackClean.fn)
		assert.is_function(uc.PackLoad.fn)
		assert.is_function(uc.PackUpdate.fn)
	end)

	it("invokes commands.load immediately", function()
		local commands = package.loaded["commands"]
		unpack.setup()
		local names = {}
		for _, c in ipairs(commands.__calls) do
			table.insert(names, c[1])
		end
		assert.True(vim.tbl_contains(names, "load"))
	end)
end)
