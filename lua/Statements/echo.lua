HCC_statements = HCC_statements or {}
HCC_statements.echo = function (CC)
	CC:i_pos() --Skip echo

	local echo_table = {}
	local args = CC:parse_func_arg_list({}, AS_REFVAR)
	if CC.error_condition then
		return
	end

	for i = 1, #args do
		table.insert(echo_table, tostring(args[i]))
	end
	managers.chat:say(table.concat(echo_table, ""))
end