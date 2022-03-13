--Value parsing stuff for variables. They're named items prefixed by a $.
--The majority of the code handling these can currently be found in HCCFramework.lua
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "variable",
	is = function(CC, ins) return ins:sub(1, 1) == "$" end,
	get = function(CC, ins, as_refvar) 
		if not as_refvar then
			local value = CC:deref_variable(ins)
			CC:i_pos()
			ins = CC:get()

			--Resolve function calls if needed.
			if ins == "(" then
				value, parent = CC:call_function(value, parent, key)
			end

			return value
		else
			local value = CC:get_variable(ins)
			CC:i_pos()
			return value
		end
	end
})