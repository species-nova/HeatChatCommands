HCC_statements = HCC_statements or {}
HCC_statements.set = function (CC)
	CC:i_pos() --Skip "set"
	local reference = CC:parse_expression(AS_REFVAR)
	CC:c_pos('=') --Skip "="
	local new_value = CC:parse_expression()
	if CC:is_refvar(reference) then
		local t = reference.parent
		local k = reference.key
		local v = new_value
		if type(t) == "userdata" then
			t = getmetatable(curr)
			if not t then
				CC:trigger_error("LOOKUP ERROR: Unable to access userdata.")
				return
			end
		end

		if not t[k] or type(v) == type(t[k]) then
			t[k] = v
		else
			CC:trigger_error("TYPE ERROR: Attempted to change " .. type(t[k]) .. " to " .. type(v))
		end
	else
		CC:trigger_error("TYPE ERROR: Set is not yet supported for non-referenced variables.")
	end
end