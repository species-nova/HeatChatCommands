--The primitive number type.
--Looks about how one would expect it to.
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "number",
	is = function(CC, ins) return tonumber(ins) end,
	get = function(CC, ins, is_refvar)
		CC:i_pos()
		return tonumber(ins)
	end
})