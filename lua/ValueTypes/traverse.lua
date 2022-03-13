--An expression representing a traversal of lua tables starting from global state.
--These expressions take the form of '[ ... ]' with the dots getting replaced by table indices to follow.
--IE: [ managers player player_unit() ] will traverse from _G up intil player_unit
--Once it reaches player_unit, it will then call that function (further arguments can be passed in as per normal).
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "traverse",
	is = function(CC, ins) return ins == "[" end,
	get = function(CC, ins, as_refvar)
		local curr_value = nil
		CC:i_pos() --Skip the '['
		local start_pos = CC:pos()
		local traverse_terminated = false
		local traverse_args = ""

		if CC:get() == "]" then
			CC:trigger_error("SYNTAX ERROR: Attempted to traverse nothing.")
			return
		end

		local curr = _G
		local prev = _G
		local key = nil

		while not CC:complete() do
			local ins = CC:get()
			local traverse_args = traverse_args .. " " .. ins
			if CC:pos() ~= start_pos and ins:sub(1, 1) == "$" then
				ins = CC:deref_variable(ins, true)
			end

			if ins == "]" then
				CC:i_pos() --Skip the "]"
				traverse_terminated = true
				break
			elseif CC:pos() == start_pos and ins:sub(1, 1) == "$" then
				curr, prev, key = CC:deref_variable(ins)
				CC:i_pos()
			elseif type(curr) == "table" then
				prev = curr
				curr = curr[ins]
				key = ins
				CC:i_pos()
				if curr == CC then
					log("WARNING: Modifying values held by ChatCommands may result in undesirable behavior.")
					CC:print_position_info()
				end
			elseif type(curr) == "userdata" then
				local curr_metatable = getmetatable(curr) or {}
				prev = curr
				curr = curr_metatable[ins]
				key = ins
				CC:i_pos()
			elseif type(curr) == "function" and ins:sub(1,1) == "(" then
				curr, prev = CC:call_function(curr, prev, key)

				if not curr and not error_condition then
					CC:trigger_error("LOOKUP ERROR: Call to " .. key .. " returned nil.")
					return
				end
			else
				ins = CC:get(-1)
				CC:trigger_error("TYPE ERROR: " .. ins .. " is a " .. type(ins) .. " and cannot be looked up.")
				return
			end

			if error_condition then
				return
			elseif not curr then
				CC:trigger_error("LOOKUP ERROR: " .. ins .. " is a nil value.")
				return
			end
		end

		if not traverse_terminated then
			CC:trigger_error("SYNTAX ERROR: Traversal \"" .. traverse_args .. "\" was not terminated.")
			return
		end

		if as_refvar and curr then
			local var_data = {}
			setmetatable(var_data, CC:get_var_data_meta())
			var_data.key = key
			var_data.value = curr
			var_data.parent = prev
			return var_data
		else
			return curr
		end
	end
})