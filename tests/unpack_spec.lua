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
			opts = {
				group = "Unpack",
			},
			__called = function()
				return config_setup_called
			end,
		}

		package.loaded["extensions"] = true

		_G.vim = require("tests.fixtures").vim_unpack_fixtures

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

		local build_count = 0
		for _, n in ipairs(names) do
			if n == "build" then
				build_count = build_count + 1
			end
		end
		assert.equal(2, build_count)
		assert.False(vim.tbl_contains(names, "clean"))
		assert.False(vim.tbl_contains(names, "update"))
	end)

	it("registers Unpack user command", function()
		unpack.setup()
		local uc = _G.__last_user_command

		assert.is_function(uc.Unpack.fn)
		assert.equals("*", uc.Unpack.opts.nargs)
		assert.is_function(uc.Unpack.opts.complete)
		assert.same({ "clean", "update" }, uc.Unpack.opts.complete())
	end)

	it("Unpack command calls clean subcommand", function()
		local commands = package.loaded["commands"]
		unpack.setup()
		local uc = _G.__last_user_command

		uc.Unpack.fn({ fargs = { "clean" } })

		local found = false
		for _, c in ipairs(commands.__calls) do
			if c[1] == "clean" then
				found = true
				break
			end
		end
		assert.True(found)
	end)

	it("Unpack command calls update subcommand", function()
		local commands = package.loaded["commands"]
		unpack.setup()
		local uc = _G.__last_user_command

		uc.Unpack.fn({ fargs = { "update" } })

		local found = false
		for _, c in ipairs(commands.__calls) do
			if c[1] == "update" then
				found = true
				break
			end
		end
		assert.True(found)
	end)

	it("Unpack command shows usage for unknown subcommand", function()
		local msgs = {}
		vim.notify = function(msg, level)
			msgs[#msgs + 1] = { msg = msg, level = level }
		end
		vim.log = vim.log or { levels = { WARN = 2 } }
		unpack.setup()
		local uc = _G.__last_user_command

		uc.Unpack.fn({ fargs = { "unknown" } })

		assert.same("Usage: Unpack [clean|update]", msgs[1].msg)
		assert.same(vim.log.levels.WARN, msgs[1].level)
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
