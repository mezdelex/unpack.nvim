---@diagnostic disable: duplicate-set-field
local assert = require("luassert")

describe("string.is_empty_or_whitespace", function()
	before_each(function()
		string.is_empty_or_whitespace = nil
		package.loaded["string"] = nil
		dofile("lua/extensions.lua")
	end)

	it("returns true for empty string", function()
		assert.True((""):is_empty_or_whitespace())
	end)

	it("returns true for whitespace-only strings", function()
		assert.True(("   "):is_empty_or_whitespace())
		assert.True(("\t\n"):is_empty_or_whitespace())
	end)

	it("returns false for non-whitespace strings", function()
		assert.False(("a"):is_empty_or_whitespace())
		assert.False(("  b  "):is_empty_or_whitespace())
		assert.False(("0"):is_empty_or_whitespace())
	end)

	it("does not override if already defined", function()
		local old = function()
			return "sentinel"
		end
		string.is_empty_or_whitespace = old
		dofile("lua/extensions.lua")

		assert.equal("sentinel", string.is_empty_or_whitespace())
	end)
end)
