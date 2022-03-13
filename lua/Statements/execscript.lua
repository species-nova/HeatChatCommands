local AS_REFVAR = true
local script_parameters = {
	"$1","$2","$3","$4","$5"
}
function get_script_parameter_name(paramnum)
	while not script_parameters[paramnum] do
		table.insert(script_parameters, "$" .. tostring(#script_parameters))
	end
	return script_parameters[paramnum]
end

HCC_statements = HCC_statements or {}
HCC_statements["!"] = function (CC)
	CC:i_pos() --Skip the '!'
	local fileref = CC:get() 
	if not fileref then
		CC:trigger_error("SYNTAX ERROR: Attempted to open script without a name.")
		return
	end

	local filepath = CC.script_path .. fileref
	local file = io.open(filepath, "r")
	if not file then
		CC:trigger_error("LOOKUP ERROR: Unable to open script: \"" .. fileref .. "\"")
		return
	end
	local script = file:read("*all")

	--Handle any arguments that were passed in.
	CC:i_pos()
	local args = {}
	if CC:get() == "(" then
		local arg_vals = CC:parse_func_arg_list({}, AS_REFVAR)
		for i = 1, #arg_vals do
			print_value(arg_vals[i], "$" .. tostring(i))
			args[get_script_parameter_name(i)] = arg_vals[i]
			if not script:find(get_script_parameter_name(i)) then
				log("Warning: Parameter number " .. tostring(i) .. " is unused by \"" .. fileref .. "\".")
			end
		end
	end

	CC:eval(script, fileref, args)
	file:close()
end