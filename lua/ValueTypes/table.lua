--Value type that allocates and returns a new lua table.
--Follows similar syntax to normal lua tables with 2 key differences.
--1: Separating commas are not required.
--2: Non-string keys (using [] or $___) are not supported due to syntax abiguity issues.
HCC_value_types = HCC_value_types or {}
table.insert(HCC_value_types, {
	name = "table",
	is = function(CC, ins) return ins == "{" end,
	get = function(CC, ins, is_refvar) 
		local table_terminated = false
		local tbl = {}
		CC:i_pos()
		while not CC:complete() do
			ins = CC:get()

			if ins == "}" then
				CC:i_pos()
				table_terminated = true
				break
			end
			
			local key = nil
			local t_value = nil

			local next_ins = CC:get(1)
			if next_ins == "=" then
				key = ins
				CC:i_pos(2) --Skip = sign.
				if CC:get() then
					t_value = CC:parse_expression()
				else
					CC:trigger_error("SYNTAX ERROR: No value following \"=\" next to \"" .. ins .. "\".")
					return
				end
			else
				t_value = CC:parse_expression()
			end

			
			if not key then
				table.insert(tbl, t_value)
			else
				tbl[key] = t_value 
			end
		end

		if not table_terminated then
			CC:trigger_error("SYNTAX ERROR: Table was not terminated.")
			return
		end

		return tbl
	end
})