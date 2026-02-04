---@diagnostic disable: duplicate-set-field
local assert = require("luassert")

_G.vim = require("test.fixtures").vim_config_fixtures

describe("config", function()
	local config

	before_each(function()
		package.loaded["config"] = nil
		config = require("lua.config")

		config.opts = {
			add_options = { confirm = false },
			config_path = "/tmp/config",
			data_path = "/tmp/data",
			packages_rpath = "/site/pack/core/opt/",
			plugins_rpath = "/lua/plugins/",
			unpack_package = "unpack.nvim",
			update_options = { force = true },
		}
	end)

	it("has default opts", function()
		assert.same({
			add_options = { confirm = false },
			config_path = "/tmp/config",
			data_path = "/tmp/data",
			packages_rpath = "/site/pack/core/opt/",
			plugins_rpath = "/lua/plugins/",
			unpack_package = "unpack.nvim",
			update_options = { force = true },
		}, config.opts)
	end)

	describe("setup", function()
		it("merges new opts into defaults", function()
			config.setup({
				add_options = { confirm = true },
				update_options = { force = false },
			})

			assert.same(true, config.opts.add_options.confirm)
			assert.same(false, config.opts.update_options.force)
			assert.same("/tmp/config", config.opts.config_path)
		end)

		it("deep-merges nested tables instead of replacing them", function()
			config.setup({
				add_options = { extra = 1 },
			})
			assert.same({ confirm = false, extra = 1 }, config.opts.add_options)
		end)

		it("does nothing when called with nil", function()
			local before = vim.deepcopy(config.opts)
			config.setup()
			assert.same(before, config.opts)
		end)

		it("overrides paths if provided", function()
			config.setup({
				config_path = "/custom/config",
				data_path = "/custom/data",
			})
			assert.same("/custom/config", config.opts.config_path)
			assert.same("/custom/data", config.opts.data_path)
		end)
	end)
end)
