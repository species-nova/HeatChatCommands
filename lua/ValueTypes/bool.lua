--The primitive boolean type.
--Instructions of 'true' correspond to the primitive true value.
--Instructions of 'false' correspond to the primitive false value.
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "boolean",
	is = function(CC, ins) return ins == "true" or ins == "false" end,
	get = function(CC, ins, is_refvar) 
		CC:i_pos()
		return ins == "true"
	end
})