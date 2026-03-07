---@diagnostic disable: duplicate-set-field, missing-parameter
local assert = require("luassert")
local commands = require("lua.commands")

_G.vim = require("test.fixtures").vim_commands_fixtures
_G.string.is_empty_or_whitespace = function(s)
	return not not s:match("^%s*$")
end

package.loaded["config"] = {
	opts = {
		add_options = {},
		config_path = "/tmp/config/",
		conflict_suffix = ".conflict",
		data_path = "/tmp/data/",
		is_win32 = vim.fn.has("win32"),
		packages_rpath = "packages/",
		plugins_rpath = "plugins/",
		unpack_package = "unpack.nvim",
		update_options = {},
	},
}

describe("commands", function()
	local original_vim_schedule = vim.schedule

	before_each(function()
		vim.schedule = function(func)
			func()
		end
	end)

	after_each(function()
		vim.schedule = original_vim_schedule
	end)

	describe("build", function()
		it("runs build command for eager specs", function()
			local msgs = {}
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			vim.system = function(cmd, opts)
				assert.same({ "make", "install" }, cmd)
				assert.same({ cwd = "/tmp/data/packages/test" }, opts)
				return {
					wait = function()
						return { code = 0, stdout = "ok", stderr = "" }
					end,
				}
			end

			commands.build({ { src = "test", data = { build = "make install" } } })

			assert.same("Building test...", msgs[1][1])
			assert.same(vim.log.levels.WARN, msgs[1][2])
			assert.same("Build successful for test", msgs[2][1])
			assert.same(vim.log.levels.INFO, msgs[2][2])
		end)

		it("skips if no build cmd", function()
			local called = false
			vim.system = function()
				called = true
			end

			commands.build({ { src = "test" } })

			assert.False(called)
		end)

		it("builds both deferred and eager specs when no specs provided", function()
			local msgs = {}
			local build_calls = {}
			package.loaded["plugins.test"] = {
				src = "test",
				data = { build = "make install" },
			}
			package.loaded["plugins.deferred"] = {
				src = "deferred",
				defer = true,
				data = { build = "make build" },
			}
			vim.fn.glob = function(path)
				if path:match("plugins/") then
					return { "/tmp/config/plugins/test.lua", "/tmp/config/plugins/deferred.lua" }
				end
				return {}
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return fpath:match("([^/]+)%.lua$")
				end
				if mod == ":t" then
					return fpath:match("([^/]+)$")
				end
				return fpath
			end
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			vim.system = function(cmd, opts)
				build_calls[#build_calls + 1] = cmd
				return {
					wait = function()
						return { code = 0, stdout = "ok", stderr = "" }
					end,
				}
			end

			commands.build()

			assert.same(2, #build_calls)
			local found_install, found_build = false, false
			for _, cmd in ipairs(build_calls) do
				if cmd[1] == "make" and cmd[2] == "install" then
					found_install = true
				end
				if cmd[1] == "make" and cmd[2] == "build" then
					found_build = true
				end
			end
			assert.True(found_install)
			assert.True(found_build)
		end)

		it("notifies error on failure", function()
			local msgs = {}
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			vim.system = function(_, _)
				return {
					wait = function()
						return { code = 1, stderr = "fail", stdout = "" }
					end,
				}
			end

			commands.build({ { src = "test", data = { build = "x" } } })

			assert.same("Building test...", msgs[1][1])
			assert.same(vim.log.levels.WARN, msgs[1][2])
			assert.same("Build failed for test", msgs[2][1])
			assert.same(vim.log.levels.ERROR, msgs[2][2])
		end)

		it("renames conflicts on Windows", function()
			local msgs = {}
			vim.fn.has = function(feature)
				return feature == "win32" and 1 or 0
			end
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			vim.fn.glob = function(path)
				if path == "/tmp/data/packages/test/**/conflict.dll" then
					return { "/tmp/data/packages/test/conflict.dll" }
				end
				return {}
			end
			vim.uv.fs_rename = function(src, dst)
				assert.same("/tmp/data/packages/test/conflict.dll", src)
				assert.same("/tmp/data/packages/test/conflict.dll.conflict", dst)
				return true, nil
			end
			vim.system = function(cmd, opts)
				assert.same({ "make", "install" }, cmd)
				assert.same({ cwd = "/tmp/data/packages/test" }, opts)
				return {
					wait = function()
						return { code = 0, stdout = "ok", stderr = "" }
					end,
				}
			end

			commands.build({ { src = "test", data = { build = "make install", conflicts = { "conflict.dll" } } } })

			assert.same("Building test...", msgs[1][1])
			assert.same(vim.log.levels.WARN, msgs[1][2])
			assert.same("Build successful for test", msgs[2][1])
			assert.same(vim.log.levels.INFO, msgs[2][2])
		end)

		it("skips conflict handling on non-Windows", function()
			local glob_called = false
			package.loaded["config"].opts.is_win32 = 0
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.fn.glob = function()
				glob_called = true
				return {}
			end
			vim.system = function(cmd, opts)
				assert.same({ "make", "install" }, cmd)
				assert.same({ cwd = "/tmp/data/packages/test" }, opts)
				return {
					wait = function()
						return { code = 0, stdout = "ok", stderr = "" }
					end,
				}
			end

			commands.build({ { src = "test", data = { build = "make install", conflicts = { "conflict.dll" } } } })

			assert.False(glob_called)
		end)

		it("handles fs_rename failure gracefully", function()
			local msgs = {}
			package.loaded["config"].opts.is_win32 = 1
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			vim.fn.glob = function(path)
				if path == "/tmp/data/packages/test/**/conflict.dll" then
					return { "/tmp/data/packages/test/conflict.dll" }
				end
				return {}
			end
			vim.uv.fs_rename = function(_, _)
				return false, "permission denied"
			end
			vim.system = function(cmd, opts)
				assert.same({ "make", "install" }, cmd)
				assert.same({ cwd = "/tmp/data/packages/test" }, opts)
				return {
					wait = function()
						return { code = 0, stdout = "ok", stderr = "" }
					end,
				}
			end

			commands.build({ { src = "test", data = { build = "make install", conflicts = { "conflict.dll" } } } })

			assert.same("Rename failed: permission denied", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
			assert.same("Building test...", msgs[2][1])
			assert.same(vim.log.levels.WARN, msgs[2][2])
			assert.same("Build successful for test", msgs[3][1])
			assert.same(vim.log.levels.INFO, msgs[3][2])
		end)

		it("handles build when package directory doesn't exist", function()
			local called = false
			vim.uv.fs_stat = function()
				return nil
			end
			vim.system = function()
				called = true
			end

			commands.build({ { src = "test", data = { build = "make" } } })

			assert.False(called)
		end)

		it("skips when spec.data.build is empty", function()
			local called = false
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.system = function()
				called = true
			end

			commands.build({ { src = "test", data = { build = "   " } } })

			assert.False(called)
		end)

		it("skips when spec.data is not a table", function()
			local called = false
			vim.system = function()
				called = true
			end

			commands.build({ { src = "test", data = "not a table" } })

			assert.False(called)
		end)

		it("skips when spec.src is not a string", function()
			local called = false
			vim.system = function()
				called = true
			end

			commands.build({ { src = 123, data = { build = "make" } } })

			assert.False(called)
		end)

		it("skips when spec.data.build is not a string", function()
			local called = false
			vim.system = function()
				called = true
			end

			commands.build({ { src = "test", data = { build = 123 } } })

			assert.False(called)
		end)
	end)

	describe("clean", function()
		it("removes packages not in specs", function()
			package.loaded["plugins.a"] = { src = "/tmp/data/packages/a" }
			vim.fn.glob = function(p)
				if p:match("plugins/") then
					return { "/tmp/config/plugins/a.lua" }
				else
					return { "/tmp/data/packages/a/", "/tmp/data/packages/b/" }
				end
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return fpath:match("([^/]+)%.lua$")
				end
				if mod == ":t" then
					return fpath:match("([^/]+)$")
				end
				return fpath
			end
			local deleted
			vim.pack.del = function(pkgs)
				deleted = pkgs
			end

			commands.clean()

			assert.same({ "b" }, deleted)
		end)

		it("cleans conflict files on Windows", function()
			local unlink_calls = {}
			package.loaded["config"].opts.is_win32 = 1
			package.loaded["plugins.test"] = {
				src = "/tmp/data/packages/test",
				data = { conflicts = { "a.dll" } },
			}
			vim.fn.glob = function(path)
				if path == "/tmp/data/packages/test/**/*.conflict" then
					return {
						"/tmp/data/packages/test/a.dll.conflict",
					}
				end
				if path:match("plugins/") then
					return { "/tmp/config/plugins/test.lua" }
				else
					return { "/tmp/data/packages/test/" }
				end
			end
			vim.fn.fnamemodify = function(path, mod)
				if mod == ":t:r" then
					return "test"
				end
				if mod == ":t" then
					return "test"
				end
				return path
			end
			vim.uv.fs_unlink = function(file)
				table.insert(unlink_calls, file)
				return true, nil
			end
			vim.pack.del = function() end

			commands.clean()

			assert.same(1, #unlink_calls)
			assert.is_true(unlink_calls[1] == "/tmp/data/packages/test/a.dll.conflict")
		end)

		it("handles unlink failure gracefully", function()
			local msgs = {}
			package.loaded["config"].opts.is_win32 = 1
			package.loaded["plugins.test"] = {
				src = "/tmp/data/packages/test",
				data = { conflicts = { "a.dll" } },
			}
			vim.fn.glob = function(path)
				if path == "/tmp/data/packages/test/**/*.conflict" then
					return { "/tmp/data/packages/test/a.dll.conflict" }
				end
				if path:match("plugins/") then
					return { "/tmp/config/plugins/test.lua" }
				else
					return { "/tmp/data/packages/test/" }
				end
			end
			vim.fn.fnamemodify = function(path, mod)
				if mod == ":t:r" then
					return "test"
				end
				if mod == ":t" then
					return "test"
				end
				return path
			end
			vim.uv.fs_unlink = function(_)
				return false, "permission denied"
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end

			commands.clean()

			assert.same("Unlink failed: permission denied", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
		end)

		it("skips conflict cleaning on non-Windows", function()
			local glob_called = false
			vim.fn.has = function(feature)
				return feature == "win32" and 0 or 1
			end
			vim.fn.glob = function(path)
				if path:match("**/*.conflict$") then
					glob_called = true
				end
				return {}
			end

			commands.clean()

			assert.False(glob_called)
		end)

		it("only cleans conflicts for packages with conflicts config", function()
			local glob_called = false
			package.loaded["plugins.a"] = { src = "/tmp/data/packages/a" }
			vim.fn.has = function(feature)
				return feature == "win32" and 1 or 0
			end
			vim.fn.glob = function(path)
				if path == "/tmp/data/packages/a/**/*.conflict" then
					glob_called = true
					return { "/tmp/data/packages/a/test.dll.conflict" }
				end
				if path:match("plugins/") then
					return { "/tmp/config/plugins/a.lua" }
				else
					return { "/tmp/data/packages/a/" }
				end
			end
			vim.fn.fnamemodify = function(path, mod)
				if mod == ":t:r" then
					return "a"
				end
				if mod == ":t" then
					return "a"
				end
				return path
			end
			vim.uv.fs_unlink = function(_)
				return true, nil
			end

			commands.clean()

			assert.False(glob_called)
		end)

		it("notifies when plugin spec fails to load", function()
			local msgs = {}
			package.loaded["plugins.bad"] = nil
			vim.fn.glob = function()
				return { "/tmp/config/plugins/bad.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return "bad"
				end
				return fpath
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end
			local original_require = require
			require = function(mod)
				if mod == "plugins.bad" then
					error("module not found")
				end
				return original_require(mod)
			end

			commands.load()

			require = original_require
			assert.equals(1, #msgs)
			assert.same("Failed to load plugin spec for bad", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
		end)

		it("notifies when spec is not a table", function()
			local msgs = {}
			package.loaded["plugins.invalid"] = "not a table"
			vim.fn.glob = function()
				return { "/tmp/config/plugins/invalid.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return "invalid"
				end
				return fpath
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end

			commands.load()

			assert.equals(1, #msgs)
			assert.same("Invalid spec for invalid, not a table", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
		end)

		it("notifies when dependency is missing src", function()
			local msgs = {}
			package.loaded["plugins.parent"] = {
				src = "parent",
				dependencies = {
					{ name = "no-src" }, -- missing src
				},
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/parent.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return "parent"
				end
				return fpath
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end

			commands.load()

			assert.equals(1, #msgs)
			assert.same("Invalid dependency for parent, missing src", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
		end)

		it("notifies when spec is missing src", function()
			local msgs = {}
			package.loaded["plugins.no-src"] = {
				name = "no-src",
				-- missing src
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/no-src.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return "no-src"
				end
				return fpath
			end
			vim.notify = function(msg, level)
				msgs[#msgs + 1] = { msg, level }
			end

			commands.load()

			assert.equals(1, #msgs)
			assert.same("Invalid spec for no-src, missing src", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
		end)

		it("handles dependencies with defer flag", function()
			local add_calls = {}
			local configs_run = {}
			package.loaded["plugins.parent"] = {
				src = "parent",
				dependencies = {
					{
						src = "dep-eager",
						config = function()
							configs_run[#configs_run + 1] = "dep-eager"
						end,
					},
					{
						src = "dep-deferred",
						defer = true,
						config = function()
							configs_run[#configs_run + 1] = "dep-deferred"
						end,
					},
				},
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/parent.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return "parent"
				end
				if mod == ":t" then
					return fpath:match("([^/]+)$")
				end
				return fpath
			end
			local scheduled_func
			vim.schedule = function(f)
				scheduled_func = f
			end
			vim.pack.add = function(specs, options)
				add_calls[#add_calls + 1] = specs
			end

			commands.load()

			assert.is_true(vim.tbl_contains(configs_run, "dep-eager"))
			assert.is_false(vim.tbl_contains(configs_run, "dep-deferred"))
			scheduled_func()
			assert.is_true(vim.tbl_contains(configs_run, "dep-deferred"))
			assert.equals(2, #add_calls)
		end)

		it("filters out unpack_package from package list", function()
			local deleted
			package.loaded["plugins.a"] = { src = "/tmp/data/packages/a" }
			vim.fn.glob = function(p)
				if p:match("plugins/") then
					return { "/tmp/config/plugins/a.lua" }
				else
					return { "/tmp/data/packages/a/", "/tmp/data/packages/b/", "/tmp/data/packages/unpack.nvim/" }
				end
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return fpath:match("([^/]+)%.lua$")
				end
				if mod == ":t" then
					return fpath:match("([^/]+)$")
				end
				return fpath
			end
			vim.pack.del = function(pkgs)
				deleted = pkgs
			end

			commands.clean()

			assert.same({ "b" }, deleted)
		end)
	end)

	describe("load", function()
		it("adds and configures eager specs immediately", function()
			local cfg = false
			package.loaded["plugins.a"] = {
				src = "a",
				config = function()
					cfg = true
				end,
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/a.lua" }
			end
			vim.fn.fnamemodify = function(_, _)
				return "a"
			end
			local add_calls = {}
			vim.pack.add = function(specs, options)
				add_calls[#add_calls + 1] = { specs = specs, opts = options }
			end

			commands.load()

			assert.equals(2, #add_calls)
			assert.equals(1, #add_calls[1].specs)
			assert.equals("a", add_calls[1].specs[1].src)
			assert.is_function(add_calls[1].specs[1].config)
			assert.same({}, add_calls[1].opts)
			assert.True(cfg)
		end)

		it("defers config when defer=true", function()
			local ran = false
			package.loaded["plugins.b"] = {
				src = "b",
				defer = true,
				config = function()
					ran = true
				end,
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/b.lua" }
			end
			vim.fn.fnamemodify = function(_, _)
				return "b"
			end
			local scheduled_func
			local add_calls = {}
			vim.schedule = function(f)
				scheduled_func = f
			end
			vim.pack.add = function(specs, options)
				add_calls[#add_calls + 1] = { specs = specs, opts = options }
			end

			commands.load()

			assert.is_function(scheduled_func)
			assert.equals(1, #add_calls)
			assert.same({}, add_calls[1].specs)
			assert.False(ran)
			scheduled_func()
			assert.equals(2, #add_calls)
			assert.equals(1, #add_calls[2].specs)
			assert.equals("b", add_calls[2].specs[1].src)
			assert.equals(true, add_calls[2].specs[1].defer)
			assert.True(ran)
		end)

		it("handles mixed deferred and eager specs", function()
			local eager_ran, deferred_ran = false, false
			package.loaded["plugins.eager"] = {
				src = "eager",
				config = function()
					eager_ran = true
				end,
			}
			package.loaded["plugins.deferred"] = {
				src = "deferred",
				defer = true,
				config = function()
					deferred_ran = true
				end,
			}
			vim.fn.glob = function()
				return { "/tmp/config/plugins/eager.lua", "/tmp/config/plugins/deferred.lua" }
			end
			vim.fn.fnamemodify = function(fpath, mod)
				if mod == ":t:r" then
					return fpath:match("([^/]+)%.lua$")
				end
				if mod == ":t" then
					return fpath:match("([^/]+)$")
				end
				return fpath
			end
			local scheduled_func
			vim.schedule = function(f)
				scheduled_func = f
			end
			local add_calls = {}
			vim.pack.add = function(specs, options)
				add_calls[#add_calls + 1] = specs
			end

			commands.load()

			assert.True(eager_ran)
			assert.False(deferred_ran)
			assert.is_function(scheduled_func)
			scheduled_func()
			assert.True(deferred_ran)
			assert.equals(2, #add_calls)
		end)
	end)

	describe("update", function()
		it("calls pack.update with options", function()
			local called, opts
			vim.pack.update = function(_, o)
				called, opts = true, o
			end

			commands.update()

			assert.True(called)
			assert.same({}, opts)
		end)
	end)
end)
