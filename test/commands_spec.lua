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
		packages_rpath = "packages/",
		plugins_rpath = "plugins/",
		unpack_rpath = "unpack",
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
		it("runs build command", function()
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

		it("handles conflicts on Windows", function()
			local msgs = {}
			local safe_delete_called = false
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
				if path == "/tmp/data/packages/test/**/*" .. ".conflict" then
					return { "/tmp/data/packages/test/existing.conflict" }
				end
				if path == "/tmp/data/packages/test/**/conflict.dll" then
					return { "/tmp/data/packages/test/conflict.dll" }
				end
				return {}
			end
			vim.uv.fs_rename = function(_, _)
				return true, nil
			end
			vim.uv.fs_unlink = function(_)
				safe_delete_called = true
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
			assert.True(safe_delete_called)
		end)

		it("skips conflict handling on non-Windows", function()
			local safe_delete_called = false
			vim.fn.has = function(feature)
				return feature == "win32" and 0 or 1
			end
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.fn.glob = function()
				safe_delete_called = true
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
			assert.False(safe_delete_called)
		end)

		it("handles fs_rename failure gracefully", function()
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

		it("handles fs_unlink failure gracefully", function()
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
				if path == "/tmp/data/packages/test/**/*" .. ".conflict" then
					return { "/tmp/data/packages/test/existing.conflict" }
				end
				if path == "/tmp/data/packages/test/**/conflict.dll" then
					return { "/tmp/data/packages/test/conflict.dll" }
				end
				return {}
			end
			vim.uv.fs_rename = function(_, _)
				return true, nil
			end
			vim.uv.fs_unlink = function(_)
				return false, "file in use"
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
			assert.same("Unlink failed: file in use", msgs[1][1])
			assert.same(vim.log.levels.ERROR, msgs[1][2])
			assert.same("Building test...", msgs[2][1])
			assert.same(vim.log.levels.WARN, msgs[2][2])
			assert.same("Build successful for test", msgs[3][1])
			assert.same(vim.log.levels.INFO, msgs[3][2])
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
			local deleted
			vim.pack.del = function(pkgs)
				deleted = pkgs
			end
			commands.clean()
			assert.same({ "b" }, deleted)
		end)
	end)

	describe("load", function()
		it("adds and configures immediately", function()
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
			local added
			vim.pack.add = function(specs)
				added = specs
			end
			commands.load()
			assert.is_not_nil(added)
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
			local scheduled
			vim.schedule = function(f)
				scheduled = f
			end
			commands.load()
			assert.is_function(scheduled)
			scheduled()
			assert.True(ran)
		end)
	end)

	describe("pull", function()
		it("pulls if unpack dir exists", function()
			local calls = {}
			local cmd_called_with
			vim.uv.fs_stat = function()
				return { type = "directory" }
			end
			vim.system = function(cmd, opts, cb)
				table.insert(calls, { cmd = cmd, opts = opts })
				if cb then
					cb()
				end
			end
			vim.cmd = function(cmd_str)
				cmd_called_with = cmd_str
			end

			commands.pull()

			assert.same({ "git", "fetch", "--all" }, calls[1].cmd)
			assert.same({ cwd = "/tmp/data/unpack" }, calls[1].opts)

			assert.same({ "git", "reset", "--hard", "origin/main" }, calls[2].cmd)
			assert.same({ cwd = "/tmp/data/unpack" }, calls[2].opts)

			assert.same({ "git", "clean", "-fdx" }, calls[3].cmd)
			assert.same({ cwd = "/tmp/data/unpack" }, calls[3].opts)

			assert.same("helptags /tmp/data/unpack/doc", cmd_called_with)
		end)

		it("does nothing if unpack dir missing", function()
			local called = false
			vim.uv.fs_stat = function()
				return {}
			end
			vim.system = function()
				called = true
			end

			commands.pull()
			assert.False(called)
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
