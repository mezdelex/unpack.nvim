if not string.is_empty_or_whitespace then
	---@param self string
	---@return boolean
	string.is_empty_or_whitespace = function(self)
		return not not self:match("^%s*$")
	end
end
