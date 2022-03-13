--A string literal.
--Encase any text within quotation marks to make one.
--TODO: Make parsing character-by-character and actually robust.
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "string",
	is = function(CC, ins) return ins:sub(1, 1) == "\"" end,
	get = function(CC, ins, is_refvar)
		if ins == "\"" then
			CC:i_pos()
			if CC:complete() then
				CC:trigger_error("SYNTAX ERROR: String was not terminated.")
				return
			end
			ins = CC:get()
		else
			ins = ins:sub(2, -1)
		end

		local str_table = {}
		local string_terminated = false
		while not CC:complete() and not string_terminated do
			if ins == "\"" then 
				string_terminated = true
			elseif ins:sub(-1, -1) == "\"" then
				table.insert(str_table, ins:sub(1, -2))
				string_terminated = true
			else
				table.insert(str_table, ins)
				CC:i_pos()
				ins = CC:get()
			end
		end

		local str = table.concat(str_table, " ")
		if not string_terminated then
			CC:trigger_error("SYNTAX ERROR: String \"" .. str .. "\" was not terminated.")
			return
		end
		CC:i_pos()
		return str
	end
})