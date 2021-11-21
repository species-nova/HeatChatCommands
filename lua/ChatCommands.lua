--[[
This file contains the language implementation for Chat Commands.
The language implementation covers syntax, and the main builtin keywords.
Functions that non-advanced users will find helpful will be in the 'scripts' folder.
The parser roughly follows a recursive descent scheme, but combines the parsing, lexing, and evaluation steps to help minimize data churn.
]]

--Constants that are recommended for readability in external files.
local REFERENCES_ONLY = true
local IMPLY_BRACKETS = true
local GET_REFERENCES = true

local POSITION = 3
local INSTRUCTION = 2
local FUNCTION = 1
local NONE = 0
local trace_level = NONE
local function trace(funcname) if trace_level >= FUNCTION then log("TRACE: " .. funcname) end end

local orig_type_func = type
local var_data_meta = {
	__mode = "v", --Have variables store weak external references so that GC isn't impacted much.
}

local cond_tree_meta = {}
local while_tree_meta = {}


local custom_types = {
	[var_data_meta] = "refvar",
	[cond_tree_meta] = "condtree",
	[while_tree_meta] = "whiletree"
}
type = function(obj)
	local orig_type = orig_type_func(obj)
	if orig_type == "table" then
		local metatable = getmetatable(obj)
		if custom_types[metatable] then
			return custom_types[metatable]
		end
	end
	return orig_type
end

--Provides the external interface.
ChatCommands = ChatCommands or class()

function ChatCommands:init()
	--Call stack for files, which provide the ability to use functions.
	self._call_stack = {}

	--Used for conditional logic and looping.
	self._condition_stack = {}

	--Used to track variables.
	--Variables come in two forms.
	--They can either be refvars, which include meta-info on how to reference them (IE: Like a pointer or reference in another language).
	--Or values, which are just raw values.
	--To assign a refvar, use $.. = [ .. ] to perform a traversal and get the relevant info.
	--To assign a value, use $.. = .. with anything else.
	self._variables = {}

	--Tracks performance information for a given refvar.
	--self._profilers = {}
	
	--Tracks variables with the listener metatable.
	--The listener metatable tracks whenever the value of a given refvar is changed, and logs it to the console.
	--self._listeners = {}

	--Informations used for error handling.
	self._error_condition = false
	self._script_path = "mods/Heat Chat Commands/scripts/"

	self._keywords = {
		--Control Flow
		["if"] = self._parse_if_statement, --Not yet fully implemented.
		["for"] = self._parse_for_statement, --Not yet implemented.
		is_null = self._parse_is_null, --Not yet implemented
		--Output
		print = self._parse_print_statement,
		echo = self._parse_echo_statement,
		--Debugging
		profile = self._parse_profile_statement, --Not yet implemented
		check = self._parse_check_statement, --Not yet implemented
		listen = self._parse_listen_statement, --Not yet implemented
		--Mutation
		set = self._parse_set_statement
	}
end

function ChatCommands:parse(command)
	self:eval(command)
	self._error_condition = false
end

function ChatCommands:pos(offset)
	return math.min(math.max(self:stack_frame().pos + (offset or 1), 1), #self:stack_frame().instructions)
end

function ChatCommands:i_pos(spaces)
	if trace_level >= POSITION then
		log("Advancing to " .. tostring(self:pos() + (spaces or 1)))
	end 
	self:stack_frame().pos = self:stack_frame().pos + (spaces or 1)
end

function ChatCommands:complete()
	return self:stack_frame().pos > #self:stack_frame().instructions or self._error_condition
end

function ChatCommands:stack_frame()
	return self._call_stack[#self._call_stack]
end

function ChatCommands:get(index)
	local frame = self:stack_frame()
	if trace_level >= INSTRUCTION then
		if frame.instructions[index and index + self:pos() or self:pos()] then
			log("Consuming " .. frame.instructions[index and index + frame.pos or frame.pos])
		elseif not index then
			log("FATAL ERROR: Attempted to consume nonexistent instruction.")
		end
	end
	return frame.instructions[index and index + frame.pos or frame.pos]
end

function ChatCommands:trigger_error(error_msg)
	if not self._error_condition then
		log(error_msg)
		self:_print_position_info()
		self._error_condition = true
	end
end

function ChatCommands:_print_position_info()
	local pos = self:pos()
	local curr_ins = self:get()
	local min_pos = math.max(self:stack_frame().statement_pos - 1, 1) --TODO: Not sure why this if off by 1. Need to fix.
	local instructions = self:stack_frame().instructions
	local max_pos = math.min(pos + 5, #instructions)
	local nearby_instructions = table.concat(instructions, " ", min_pos, max_pos)
	log("    Around:" .. nearby_instructions)
	log("    Instruction number " .. tostring(self:pos()))
	if self:stack_frame().file then
		log("    From file \"" .. self:stack_frame().file .. "\"")
	else
		log("    From in-game chat.")
	end
end

--Breaks the command up into distinct arguments to be consumed.
--By parsing functions.
--Doesn't do 'real' lexxing, but is still important for tokenizing input
function ChatCommands:_lex(command) --TODO: Holy shit this is inefficient. Maybe use pattern captures?
	command = command:gsub("//.*\n", "")
	command = command:gsub("|", " | ")
	command = command:gsub("!", " ! ")
	command = command:gsub("=", " = ")
	command = command:gsub("{", " { ")
	command = command:gsub("}", " } ")
	command = command:gsub("%(", " %( ")
	command = command:gsub("%)", " %) ")
	command = command:gsub("%[", " %[ ")
	command = command:gsub("%]", " %] ")
	return command:split("%s")
end

--[[
An expression that resolves into a single lua variable.
Args of the form '[ .. ]' corresponds to a tree traversal from Lua's _G table.
An arg of the form '$..' corresponds to a Chat Commands variable, which will be dereferenced to its value.
Args of the form '".."' correponds to a string that may include spaces.
An arg of the form '{ .. }' corresponds to a new lua table.
Args of the form '$.. ( .. )' corresponds to a function call that will return some value.
Any other args will be interpreted into a number.
Returns the lua variable.
get_references results in the function returning refvars when parsing variables or traverses.
Use this in cases where knowing the parent of the value is important, such as when assigning variables or making function calls.
]]
function ChatCommands:_parse_value(get_references)
	trace("parse value")
	local value = nil
	local ins = self:get()
	if not ins then
		self:trigger_error("SYNTAX ERROR: Not enough arguments supplied.")
		return
	end

	local ins_num = tonumber(ins)

	if ins_num then
		value = ins_num
		self:i_pos()
	elseif ins == "true" then
		value = true
		self:i_pos()
	elseif ins == "false" then
		value = false
		self:i_pos()
	elseif ins == "[" then
		value = self:_parse_traverse()
		if not get_references then
			if value then
				value = value.value
			else 
				return
			end
		end
	elseif ins:sub(1, 1) == "$" then
		if not get_references then
			value = self:_deref_variable(ins)
			self:i_pos()
			ins = self:get()

			--Resolve function calls if needed.
			if ins and ins:sub(1,1) == "(" then
				value, parent = self:_call_function(value, parent, key)
			end
		else
			value = self._variables[ins] or self:stack_frame().args[ins]
			if not value then
				log("WARNING: No variable named " .. ins)
				return
			end
			self:i_pos()
		end
	elseif ins:sub(1, 1) == "\"" then
		if ins == "\"" then
			self:i_pos()
			if self:complete() then
				self:trigger_error("SYNTAX ERROR: String was not terminated.")
				return
			end
			ins = self:get()
		else
			ins = ins:sub(2, -1)
		end
		local str_table = {}
		local string_terminated = false
		while not self:complete() and not string_terminated do
			if ins == "\"" then 
				string_terminated = true
			elseif ins:sub(-1, -1) == "\"" then
				table.insert(str_table, ins:sub(1, -2))
				string_terminated = true
			else
				table.insert(str_table, ins)
				self:i_pos()
				ins = self:get()
			end
		end

		value = table.concat(str_table, " ")
		if not string_terminated then
			self:trigger_error("SYNTAX ERROR: String \"" .. value .. "\" was not terminated.")
			return
		end
		self:i_pos()
	elseif ins == "{" then
		local table_terminated = false
		local table_args = {"{"}
		value = {}
		self:i_pos()
		while not self:complete() do
			ins = self:get()
			table.insert(table_args, ins)

			if ins == "}" then
				self:i_pos()
				table_terminated = true
				break
			end
			
			local key = nil
			local t_value = nil
			local next_instruction = self:get(1)
			if next_instruction == "=" then
				key = ins
				self:i_pos(2) --Skip = sign.
				if self:get() then
					t_value = self:_parse_value()
				else
					self:trigger_error("SYNTAX ERROR: No value following \"=\" next to \"" .. ins .. "\".")
					return
				end
			else
				t_value = self:_parse_value()
			end

			
			if not key then
				table.insert(value, t_value)
			else
				value[key] = t_value 
			end
		end

		if not table_terminated then
			self:trigger_error("SYNTAX ERROR: Table \"" .. table.concat(table_args, " ") .. "\" was not terminated.")
			return
		end
	else
		self:trigger_error("SYNTAX ERROR: Unrecognized token " .. ins)
		return
	end

	return value
end

--[[
Perform a lua tree traversal.
Follows syntax [ .. ] with the area between the brackets being the strings and calls needed to traverse through.
The first item in the bracketed area can be a variable to start the traversal from.
]]
function ChatCommands:_parse_traverse()
	trace("parse traverse")
	local curr_value = nil
	self:i_pos() --Skip the '['
	local start_pos = self:pos()
	local traverse_terminated = false
	local traverse_args = ""

	if self:get() == "]" then
		self:trigger_error("SYNTAX ERROR: Attempted to traverse nothing.")
		return
	end

	local curr = _G
	local prev = _G
	local key = nil

	while not self:complete() do
		local ins = self:get()
		local traverse_args = traverse_args .. " " .. ins
		if self:pos() ~= start_pos and ins:sub(1, 1) == "$" then
			ins = self:_deref_variable(ins, true)
		end

		if ins == "]" then
			self:i_pos() --Skip the "]"
			traverse_terminated = true
			break
		elseif self:pos() == start_pos and ins:sub(1, 1) == "$" then
			curr, prev, key = self:_deref_variable(ins)
			self:i_pos()
		elseif type(curr) == "table" then
			prev = curr
			curr = curr[ins]
			key = ins
			self:i_pos()
			if curr == self then
				log("WARNING: Modifying values held by ChatCommands may result in undesirable behavior.")
				self:_print_position_info()
			end
		elseif type(curr) == "userdata" then
			local curr_metatable = getmetatable(curr) or {}
			prev = curr
			curr = curr_metatable[ins]
			key = ins
			self:i_pos()
		elseif type(curr) == "function" and ins:sub(1,1) == "(" then
			curr, prev = self:_call_function(curr, prev, key)

			if not curr and not error_condition then
				self:trigger_error("LOOKUP ERROR: Call to " .. key .. " returned nil.")
				return
			end
		else
			ins = self:get(-1)
			self:trigger_error("TYPE ERROR: " .. ins .. " is a " .. type(ins) .. " and cannot be looked up.")
			return
		end

		if error_condition then
			return
		elseif not curr then
			self:trigger_error("LOOKUP ERROR: " .. ins .. " is a nil value.")
			return
		end
	end

	if not traverse_terminated then
		self:trigger_error("SYNTAX ERROR: Traversal \"" .. traverse_args .. "\" was not terminated.")
		return
	end

	local var_data = {}
	setmetatable(var_data, var_data_meta)
	var_data.key = key
	var_data.value = curr
	var_data.parent = prev
	return var_data
end


function ChatCommands:_parse_func_arg_list(args, GET_REFERENCES)
	trace("parse func arg list")
	local ins = self:get()
	local args = args or {}
	local args_str = {}
	local args_terminated = false
	self:i_pos() --Skip the "("
	while not self:complete() and not args_terminated do
		ins = self:get()
		if ins == ")" then
			args_terminated = true
			self:i_pos()
		else
			local value = self:_parse_value(GET_REFERENCES)
			table.insert(args, value)
			table.insert(args_str, ins)
		end

		if error_condition then
			return
		end
	end

	if not args_terminated then
		self:trigger_error("SYNTAX ERROR: Function call to " .. tostring(key) .. " using (" .. table.concat(args_str, " ") .. ") was not terminated.")
		return
	end

	return args
end

function ChatCommands:_call_function(curr, prev, key)
	trace("parse call function")
	--Ensure that value passed in is of the correct type.
	if type(curr) ~= "function" and type(curr) ~= "userdata" then
		self:trigger_error("TYPE ERROR: Attempted to call a " .. type(value) .. " as a function.")
		return
	end

	--Get function arguments.
	local args = {}

	--pcall needs a reference to the function to be passed in as an argument.
	if type(curr) == "function" then
		table.insert(args, curr)
	end

	--Handle references to "self"
	if prev then
		table.insert(args, prev)
	end

	args = self:_parse_func_arg_list(args)
	if not args then return end

	if type(prev) == "userdata" then --Userdata functions cannot be wrapped in a pcall().
		local temp = curr
		curr = curr(prev)
		prev = temp
	else
		local result = false
		result, curr = pcall(unpack(args))

		if not result then
			self:trigger_error("FUNCTION ERROR: Function call to " .. key .. " failed")
			return
		end
	end

	return curr, prev
end

function ChatCommands:_unset_variable(name)
	self._variables[name] = nil
	--self._profilers[name] = nil
	--self._listeners[name] = nil
end

function ChatCommands:_deref_variable(name, ref_only)
	trace("parse reref variable")
	local var = self._variables[name] or self:stack_frame().args[name]

	if not var then
		log("WARNING: No variable named " .. name)
		return
	end

	if type(var) ~= "refvar" then
		if ref_only == true then
			self:trigger_error("TYPE ERROR: " .. name .. " is a value, not a reference.")
			return
		end
		return var, null, name:sub(2, name:len())
	end

	value = var.value
	parent = var.parent
	key = var.key
	if not value or not parent then
		self:trigger_error("LOOKUP ERROR: " .. name .. " has been deallocated. Freeing metadata from memory.")
		self:_unset_variable(name)
		return
	end
	return value, parent, key
end

function ChatCommands:eval(instructions, file, args)
	trace("eval")

	if #self._call_stack == 100 then
		self:trigger_error("STACK ERROR: Over 100 files were loaded at once, it's likely that there is unbounded recursion.")
		return
	end

	--Create a new stack frame to evaluate.
	table.insert(self._call_stack, {
		instructions = self:_lex(instructions),
		pos = 1,
		statement_pos = 1,
		file = file,
		args = args or {}
	})

	--Consume the current stack frame.
	while not self:complete() do
		self:stack_frame().statement_pos = self:pos()
		local ins = self:get()
		if ins == "return" then
			break
		elseif ins == "end" then
			self:_parse_end()
		elseif self:_check_condition_stack() then
			self:_parse_statement()
		else
			self:i_pos()
		end
	end

	--Once evaluation of the current frame is finished, pop it.
	table.remove(self._call_stack)
end

function ChatCommands:_parse_statement()
	trace("parse statement")
	local ins = self:get()
	local first_char = ins:sub(1,1)

	if self._keywords[ins] then
		self._keywords[ins](self)
	elseif ins == "!" then
		self:_execute_script()
	elseif first_char == "$" then
		local next_ins = self:get(1)
		if next_ins == "=" then
			self:_parse_assignment()
		elseif next_ins and next_ins:sub(1,1) == "(" then
			self:_parse_call_function()
		else
			self:trigger_error("SYNTAX ERROR: Unexpected token " .. next_ins)
		end
	elseif first_char == "[" then
		self:_parse_call_function()
	else
		self:trigger_error("SYNTAX ERROR: Unexpected token " .. ins)
	end
end

local script_parameters = {
	"$1","$2","$3","$4","$5"
}
function get_script_parameter_name(paramnum)
	while not script_parameters[paramnum] do
		table.insert(script_parameters, "$" .. tostring(#script_parameters))
	end
	return script_parameters[paramnum]
end

function ChatCommands:_execute_script()
	trace("execute script")
	self:i_pos() --Skip the '!'
	local fileref = self:get() 
	if not fileref then
		self:trigger_error("SYNTAX ERROR: Attempted to open script without a name.")
		return
	end

	local filepath = self._script_path .. fileref
	local file = io.open(filepath, "r")
	if not file then
		self:trigger_error("LOOKUP ERROR: Unable to open script: \"" .. fileref .. "\"")
		return
	end
	local script = file:read("*all")

	--Handle any arguments that were passed in.
	self:i_pos()
	local args = {}
	if self:get() == "(" then
		local arg_vals = self:_parse_func_arg_list({}, true)
		for i = 1, #arg_vals do
			args[get_script_parameter_name(i)] = arg_vals[i]
			if not script:find(get_script_parameter_name(i)) then
				log("Warning: Parameter number " .. tostring(i) .. " is unused by \"" .. fileref .. "\".")
			end
		end
	end

	self:eval(script, fileref, args)
	file:close()
end

function ChatCommands:_parse_assignment()
	trace("parse assignment")
	local variable = self:get()
	if variable:len() == 1 then
		self:trigger_error("SYNTAX ERROR: Attempted to assign to a variable without a name.")
		return
	elseif tonumber(variable:sub(2,-1)) then
		self:trigger_error("SYNTAX ERROR: Numerical variable name \"" .. variable .. "\" is reserved for script parameters.")
		return
	end

	self:i_pos(2) --Skip the = sign.
	if self:get() == "nil" then
		self:_unset_variable(variable)
		self:i_pos()
	elseif self:get() then
		local new_value = self:_parse_value(GET_REFERENCES)
		if not self._error_condition then
			self:_unset_variable(variable)
			self._variables[variable] = new_value 
		end
	else
		self:trigger_error("SYNTAX ERROR: No value given to set variable \"" .. variable .. "\" to.")
	end
end

function ChatCommands:_parse_call_function()
	trace("parse call function")
	local reference = self:_parse_value(GET_REFERENCES)
	if type(reference) == "refvar" then
		self:_call_function(reference.value, reference.parent, reference.key)
	else
		self:trigger_error("LOOKUP ERROR: Unable to call functions from non-referenced variables.")
	end
end

function ChatCommands:_parse_set()
	trace("parse set")
	local reference = self:_parse_value(GET_REFERENCES)
	self:i_pos()
	local key = nil
	if self:get() == "=" then
		key = self:get()
		self:i_pos()
	end
	local new_value = self:_parse_value()

	local function setTable(t, k, v)
		if type(t) == "userdata" then
			t = getmetatable(curr)
			if not t then
				self:trigger_error("LOOKUP ERROR: Unable to access userdata.")
				return
			end
		end

		if not t[k] or type(v) == type(t[k]) then
			t[k] = v
		else
			self:trigger_error("TYPE ERROR: Attempted to change " .. type(t[k]) .. " to " .. type(v))
		end
	end

	if type(reference) == "refvar" then
		if key then
			setTable(reference, key, new_value)
		else
			setTable(reference.parent, reference.key, new_value)
		end
	elseif type(reference) == "table" or type(reference) == "userdata" then
		if key then
			setTable(reference, key, new_value)
		else
			if type(reference) == "userdata" then
				reference = getmetatable(curr)
				if not reference then
					self:trigger_error("LOOKUP ERROR: Unable to access userdata.")
					return
				end
			end
			table.insert(reference, new_value)
		end
	else
		self:trigger_error("TYPE ERROR: Cannot set non-referenced variables.")
	end
end

function ChatCommands:_parse_condition(condition_tree, cond_str)
	trace("parse conditional")
	local req_close_paren = cond_str and condition_tree
	cond_str = cond_str or ""
	local condition_tree = condition_tree or {}
	setmetatable(condition_tree, cond_tree_meta)
	local current_and_leaf = {}
	table.insert(condition_tree, current_and_leaf)
	local need_connector = false

	while not self:complete() do
		local ins = self:get()
		cond_str = cond_str .. " " .. ins
		if ins == "or" then
			need_connector = false
			self:i_pos()
			current_and_leaf = {}
			table.insert(condition_tree, current_and_leaf)
		elseif ins == "and" then
			need_connector = false
			self:i_pos()
		elseif not need_connector then
			need_connector = true
			local value = nil
			if ins == ")" then
				self:i_pos()
				return condition_tree
			elseif ins == "(" then
				self:i_pos()
				local new_sub_tree = {}
				table.insert(current_and_leaf, new_sub_tree)
				value = self:_parse_condition(new_sub_tree, cond_str)
			else
				value = self:_parse_value(GET_REFERENCES)
			end
			table.insert(current_and_leaf, value)
		else
			self:trigger_error("SYNTAX ERROR: Invalid conditional \"" .. cond_str .. "\", values must be separated by operators.")
			return
		end
	end

	if req_close_paren then
		self:trigger_error("SYNTAX ERROR: Conditional \"" .. cond_str .. "\" was not terminated." )
		return
	end

	return condition_tree
end

function ChatCommands:_evaluate_condition(conditions, i)
	trace("evaluate condition")
	local i = i or 1
	while i < #conditions do --Handles OR.
		local condition = conditions[i]
		for j = 1, #condition do --Handles AND.
			if type(condition[j]) == "condtree" then --Evaluate parenthesized expressions.
				result, i = self:_evaluate_condition(condition[j], i)
			else --Determine value. Use listeners if you want conditionals based on values that might change in-game.
				result = type(condition[j]) == "refvar" and condition[j].value or condition[j]
			end

			if not result then --Short circuit evaluation.
				break
			end
		end

		if result then --Short circuit evaluation.
			return true, i
		end

		i = i + 1
	end

	return false, i
end

function ChatCommands:_check_condition_stack()
	for i = 1, #self._condition_stack do
		if not self:_evaluate_condition(self._condition_stack[#self._condition_stack]) then
			return false
		end
	end

	return true
end

function ChatCommands:_parse_if_statement()
	trace("parse if")
	self:i_pos() --Skip the 'if' keyword.
	local condition_tree = self:_parse_condition()
	table.insert(self._condition_stack, condition_tree)
end

function ChatCommands:_parse_end()
	trace("parse end")
	if #self._condition_stack == 0 then
		log("Warning: End without a matching 'if'.")
		self:_print_position_info()
	end

	self:i_pos() --Skip echo.
	table.remove(self._condition_stack) --Remove active conditional.
end

function ChatCommands:_parse_echo_statement()
	trace("parse echo")
	self:i_pos() --Skip echo
	local echo_str = ""
	while not self:complete() and self:get() ~= "end" do
		local value = self:_parse_value()
		echo_str = echo_str .. tostring(value)
	end
	log(echo_str)
	self:i_pos() --Skip 'end'
end

--Memoized indentation handling.
--Large prints can take a while, so any way to cut down on concatenation is a win.
local indent_strs = {
	"",
	"    ",
	"        ",
	"            "
}
function get_indent(indent)
	while not indent_strs[indent] do
		table.insert(indent_strs, indent_strs[#indent_strs] .. "    ")
	end
	return indent_strs[indent]
end

function print_value(v, k, indent, seen)
	indent = indent and indent + 1 or 1
	local i = get_indent(indent)
	seen = seen or {}
	k = k or "[Unknown]"

	local type = type(v)
	if type == "table" then
		log(i .. tostring(k) .. " = {")
		print_table(v, k, indent, seen)
		log(i .. "}")
	elseif type == "userdata" then
		local v_table = getmetatable(v) or {}

		log(i .. tostring(k) .. " = " .. tostring(v) .. " | type = " .. type .. " {")
		print_table(v_table, k, indent, seen)
		log(i .. "}")
	else
		log(i .. tostring(k) .. " = " .. tostring(v) .. " | type = " .. type)
	end
end

function print_table(t, name, indent, seen)
	indent = indent and indent + 1 or 1
	local i = get_indent(indent)
	seen = seen or {}
	name = name or "[Unknown]"

	if not i then log("fuck") return end

	if seen[t] then
		log(i .. "REFERENCE TO " .. seen[t])
		return
	end

	seen[t] = tostring(name)
	for k, v in pairs(t) do
		print_value(v, k, indent, seen)
	end
end

function ChatCommands:_parse_print_statement()
	trace("parse print")

	self:i_pos() --Skip 'print'
	local ins = self:get() 
	local variable_name = nil
	if ins:sub(1, 1) == "$" then
		variable_name = ins
	end
	
	value = self:_parse_value(GET_REFERENCES)
	if self._error_condition then
		return
	end

	if type(value) == "refvar" then
		print_value(value.value, value.key)
	else
		print_value(value, variable_name)
	end
end