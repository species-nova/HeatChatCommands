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

local NEXT = 3
local ARG = 2
local FUNCTION = 1
local NONE = 0
local trace_level = NONE
local function trace(funcname) if trace_level >= FUNCTION then log("TRACE: " .. funcname) end end

local orig_type_func = type
local var_data_meta = {
	__mode = "v", --Have variables store weak external references so that GC isn't impacted much.
}

local cond_tree_meta = {}

type = function(obj)
	local orig_type = orig_type_func(obj)
	if orig_type == "table" then
		local metatable = getmetatable(obj)
		if metatable  == var_data_meta then
			return "refvar"
		elseif metatable == cond_tree_meta then
			return "condtree"
		end
	end
	return orig_type
end

--Provides the external interface.
ChatCommands = ChatCommands or class()

--[[
An expression that resolves into a single lua variable.
Args of the form '[ .. ]' corresponds to a tree traversal from Lua's _G table.
An arg of the form '$..' corresponds to a Chat Commands variable, which will be dereferenced to its value.
Args of the form '".."' correponds to a string that may include spaces.
An arg of the form '{ .. }' corresponds to a new lua table.
Args of the form '$.. ( .. )' corresponds to a function call that will return some value.
Any other args will be interpreted into a number.
Returns the lua variable
]]
function ChatCommands:_parse_value(get_references)
	trace("parse value")
	local value = nil
	local arg = self:arg()
	if not arg then
		self:trigger_error("SYNTAX ERROR: Not enough arguments supplied.")
		return
	end

	local arg_num = tonumber(arg)

	if arg_num then
		value = arg_num
		self:next()
	elseif arg == "true" then
		value = true
		self:next()
	elseif arg == "false" then
		value = false
		self:next()
	elseif arg == "[" then
		value = self:_parse_traverse()
		if not get_references then
			if value then
				value = value.value
			else 
				return
			end
		end
	elseif arg:sub(1, 1) == "$" then
		if not get_references then
			value = self:_deref_variable(arg)
			self:next()
			arg = self:arg()

			--Resolve function calls if needed.
			if arg and arg:sub(1,1) == "(" then
				value, parent = self:_call_function(value, parent, key)
			end
		else
			value = self._variables[arg]
			if not value then
				self:trigger_error("LOOKUP ERROR: No variable named " .. arg)
			end
			self:next()
		end
	elseif arg:sub(1, 1) == "\"" then
		if arg == "\"" then
			self:next()
			if self:complete() then
				self:trigger_error("SYNTAX ERROR: String was not terminated.")
				return
			end
			arg = self:arg()
		else
			arg = arg:sub(2, -1)
		end
		local str_table = {}
		local string_terminated = false
		while not self:complete() and not string_terminated do
			if arg == "\"" then 
				string_terminated = true
			elseif arg:sub(-1, -1) == "\"" then
				table.insert(str_table, arg:sub(1, -2))
				string_terminated = true
			else
				table.insert(str_table, arg)
				self:next()
				arg = self:arg()
			end
		end

		value = table.concat(str_table, " ")
		if not string_terminated then
			self:trigger_error("SYNTAX ERROR: String \"" .. value .. "\" was not terminated.")
			return
		end
		self:next()
	elseif arg == "{" then
		local table_terminated = false
		local table_args = {"{"}
		value = {}
		self:next()
		while not self:complete() do
			arg = self:arg()
			table.insert(table_args, arg)

			if arg == "}" then
				self:next()
				table_terminated = true
				break
			end
			
			local key = nil
			if arg:find("=") then
				local split = arg:split("=")
				key = split[1]
				if #split == 2 then
					self._args[self._pos] = split[2] --Not very clean, but it works
				elseif #split == 1 then
					self:next()
				else
					self:trigger_error("SYNTAX ERROR: Unexpected = sign in \"" .. arg .. "\".")
					return
				end
			end

			t_value = self:_parse_value()
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
		self:trigger_error("SYNTAX ERROR: Unrecognized token " .. arg)
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
	self:next() --Skip the '['
	local start_pos = self._pos
	local traverse_terminated = false
	local traverse_args = ""

	local curr = _G
	local prev = _G
	local key = arg

	while not self:complete() do
		local arg = self:arg()
		local traverse_args = traverse_args .. " " .. arg
		if self._pos ~= start_pos and arg:sub(1, 1) == "$" then
			arg = self:_deref_variable(arg, true)
		end

		if arg == "]" then
			self:next() --Skip the "]"
			traverse_terminated = true
			break
		elseif self._pos == start_pos and arg:sub(1, 1) == "$" then
			curr, prev, key = self:_deref_variable(arg)
			self:next()
		elseif type(curr) == "table" then
			prev = curr
			curr = curr[arg]
			key = arg
			self:next()
		elseif type(curr) == "userdata" then
			local curr_metatable = getmetatable(curr) or {}
			prev = curr
			curr = curr_metatable[arg]
			key = arg
			self:next()
		elseif type(curr) == "function" and arg:sub(1,1) == "(" then
			curr, prev = self:_call_function(curr, prev, key)

			if not curr and not error_condition then
				self:trigger_error("LOOKUP ERROR: Call to " .. key .. " returned nil.")
				return
			end
		else
			arg = self:arg(-1)
			self:trigger_error("TYPE ERROR: " .. arg .. " is a " .. type(arg) .. " and cannot be looked up.")
			return
		end

		if error_condition then
			return
		elseif not curr then
			self:trigger_error("LOOKUP ERROR: " .. arg .. " is a nil value.")
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


function ChatCommands:_parse_func_arg_list(func_args)
	trace("parse func arg list")
	local arg = self:arg()
	local func_args = func_args or {}
	local func_args_str = {}
	local args_terminated = false
	self:next() --Skip the "("
	while not self:complete() and not args_terminated do
		arg = self:arg()
		if arg == ")" then
			args_terminated = true
		else
			local value = self:_parse_value()
			table.insert(func_args, value)
			table.insert(func_args_str, arg)
		end

		if error_condition then
			return {} --Needs to return at least an empty table, or the game will crash on unpack()
		end

		self:next()
	end

	if not args_terminated then
		self:trigger_error("SYNTAX ERROR: Function call to " .. key .. " using (" .. table.concat(func_args_str, " ") .. ") was not terminated.")
		return {}
	end

	return func_args
end

function ChatCommands:_call_function(curr, prev, key)
	trace("parse call function")
	--Ensure that value passed in is of the correct type.
	if type(curr) ~= "function" and type(curr) ~= "userdata" then
		self:trigger_error("TYPE ERROR: Attempted to call a " .. type(value) .. " as a function.")
		return
	end

	--Get function arguments.
	local func_args = {}

	--pcall needs a reference to the function to be passed in as an argument.
	if type(curr) == "function" then
		table.insert(func_args, curr)
	end

	--Handle references to "self"
	if prev then
		table.insert(func_args, prev)
	end

	func_args = self:_parse_func_arg_list(func_args)

	if type(prev) == "userdata" then --Userdata functions cannot be wrapped in a pcall().
		local temp = curr
		curr = curr(prev)
		prev = temp
	else
		local result = false
		result, curr = pcall(unpack(func_args))

		if not result then
			self:trigger_error("Function call to " .. key .. " failed")
			return
		end
	end

	return curr, prev
end

function ChatCommands:_deref_variable(name, ref_only)
	trace("parse reref variable")
	local var = self._variables[name]

	if not var then
		self:trigger_error("LOOKUP ERROR: " .. name .. " has not been declared, or has been freed.")
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
		self:trigger_error("LOOKUP_ERROR: " .. name .. " has been deallocated. Freeing metadata from memory.")
		var = nil
		profilers[name] = nil
		return
	end
	return value, parent, key
end

function ChatCommands:init()
	--Parser state data, these two variables are frequently used by the parsing functions.
	self._args = {} --List of arguments being parsed. Should be left entirely untouched while a command is being executed.
	self._pos = 0 --Current position in the argument list. Is incremented by parsing functions.

	--Used for conditional logic and looping.
	self._stack = {}

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
	self._line = nil
	self._file = nil

	self._keywords = {
		--Control Flow
		["if"] = self._parse_if_statement,
		--Output
		print = self._parse_print_statement,
		echo = self._parse_echo_statement,
		--Debugging
		profile = self._parse_profile_statement, --Not yet implemented
		check = self._parse_check_statement, --Not yet implemented
		listen = self._parse_listen_statement, --Not yet implemented
		--Spawning
		spawn = self._parse_spawn, --Not yet implemented
		spawngroup = self._parse_spawngroup, --Not yet implemented
		--Mutation
		set = self._parse_set_statement
	}
end

function ChatCommands:print_position_info()
	log("    At argument " .. tostring(self._pos))
	if self._line then
		log("    At line " .. tostring(self._line))
	end
	if self._file then
		log("    In file " .. tostring(self._file))
	end
end

function ChatCommands:trigger_error(error_msg)
	log(error_msg)
	self:print_position_info()
	self._error_condition = true
end

--Breaks the command up into distinct arguments to be consumed.
--By parsing functions.
function ChatCommands:_lex(command) --TODO: Holy shit this is inefficient.
	command = command:gsub("{", " { ")
	command = command:gsub("}", " } ")
	command = command:gsub("%(", " %( ")
	command = command:gsub("%)", " %) ")
	command = command:gsub("%[", " %[ ")
	command = command:gsub("%]", " %] ")
	return command:split("%s")
end

function ChatCommands:parse(command, line, file)
	self._args = self:_lex(command)
	self._pos = 1
	self._line = line
	self._file = file
	self._error_condition = false
	self:_parse_statement()
end

function ChatCommands:next(spaces)
	if trace_level >= NEXT then
		log("Advancing to " .. tostring(self._pos + (spaces or 1)))
	end 
	self._pos = self._pos + (spaces or 1)
end

function ChatCommands:complete()
	return self._pos > #self._args or self._error_condition
end

function ChatCommands:arg(index)
	if trace_level >= ARG then
		if self._args[index and index + self._pos or self._pos] then
			log("Consuming " .. self._args[index and index + self._pos or self._pos])
		else
			log("FATAL ERROR: Attempted to consume nonexistent arg.")
		end
	end
	return self._args[index and index + self._pos or self._pos]
end

function ChatCommands:_parse_statement()
	trace("parse statement")
	trace(tostring(error_condition))
	local arg = self:arg()
	if arg == "end" then
		self:_parse_end()
	end

	if self:_check_stack() then
		while not self:complete() do
			trace("parse statement (loop)")
			arg = self:arg()
			local first_char = arg:sub(1,1)

			if self._keywords[arg] then
				self._keywords[arg](self)
			elseif first_char == "!" then
				self:trigger_error("NYI ERROR: Running Scripts is not yet implemented " .. arg)
			elseif first_char == "$" or first_char == "[" then
				next_arg = self:arg(1)
				if next_arg == "=" then
					self:_parse_assignment()
				elseif next_arg:sub(1,1) == "(" then
					self:_parse_call_function()
				else
					self:trigger_error("SYNTAX ERROR: Unexpected token " .. next_arg)
				end
			else
				self:trigger_error("SYNTAX ERROR: Unexpected token " .. arg)
			end
		end
	end
end

function ChatCommands:_unset_variable(name)
	self._variables[name] = nil
	--self._profilers[name] = nil
	--self._listeners[name] = nil
end

function ChatCommands:_parse_assignment()
	trace("parse assignment")
	local variable = self:arg()
	self:next(2) --Skip the = sign.
	if self:arg() then
		local new_value = self:_parse_value(GET_REFERENCES)
		if not self._error_condition then
			self:_unset_variable(variable)
			self._variables[variable] = new_value 
		end
	else
		self:_unset_variable(variable)
	end
end

function ChatCommands:_parse_call_function()
	trace("parse call function")
	local reference = self:_parse_value(GET_REFERENCES)
	if type(reference) == "refvar" then
		self:next()
		self:_call_function(value, parent, key)
	else
		self:trigger_error("LOOKUP ERROR: Unable to call functions from non-referenced variables.")
	end
end

function ChatCommands:_parse_set()
	trace("parse set")
	local reference = self:_parse_value(GET_REFERENCES)
	self:next()
	local key = nil
	if self:arg() == "=" then
		key = self:arg()
		self:next()
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
		local arg = self:arg()
		cond_str = cond_str .. " " .. arg
		if arg == "or" then
			need_connector = false
			self:next()
			current_and_leaf = {}
			table.insert(condition_tree, current_and_leaf)
		elseif arg == "and" then
			need_connector = false
			self:next()
		elseif not need_connector then
			need_connector = true
			local value = nil
			if arg == ")" then
				self:next()
				return condition_tree
			elseif arg == "(" then
				self:next()
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

function ChatCommands:_check_stack()
	for i = 1, #self._stack do
		if not self:_evaluate_condition(self._stack[#self._stack]) then
			return false
		end
	end

	return true
end

function ChatCommands:_parse_if_statement()
	trace("parse if")
	self:next() --Skip the 'if' keyword.
	local condition_tree = self:_parse_condition()
	table.insert(self._stack, condition_tree)
end

function ChatCommands:_parse_end()
	trace("parse end")
	if #self._stack == 0 then
		log("Warning: End without a matching 'if'.")
		self:print_position_info()
	end

	self:next() --Skip echo.
	table.remove(self._stack) --Remove active conditional.
end

function ChatCommands:_parse_echo_statement()
	trace("parse echo")
	self:next() --Skip echo
	local echo_str = ""
	while not self:complete() do
		local value = self:_parse_value()
		echo_str = echo_str .. tostring(value)
	end	
	log(echo_str)
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

	self:next() --Skip 'print'
	local arg = self:arg() 
	local variable_name = nil
	if arg:sub(1, 1) == "$" then
		variable_name = arg
	end
	
	value = self:_parse_value(GET_REFERENCES)
	if type(value) == "refvar" then
		print_value(value.value, value.key)
	else
		print_value(value, variable_name)
	end
end