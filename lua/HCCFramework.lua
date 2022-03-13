--[[
This file contains the language implementation for Chat Commands.
The language implementation covers syntax, and the main builtin keywords.
Functions that non-advanced users will find helpful will be in the 'scripts' folder.
The parser roughly follows a recursive descent scheme, but combines the parsing, lexing, and evaluation steps to help minimize data churn.
]]

--Constants for readability.
	--PARAMETERS
		local REFERENCES_ONLY = true
		local AS_REFVAR = true

	--Logging options.
		local FUNCTION = 1
		local INSTRUCTION = 2
		local POSITION = 3
		local TYPE_IS = 4
		local TYPE_GET = 5
		local STATEMENT = 6

--Provides the external interface.
ChatCommands = ChatCommands or class()
	--Used for conditional logic.
	local condition_stack = {}

	--Used to track variables.
	--Variables come in two forms.
	--They can either be refvars, which include meta-info on how to reference them (IE: Like a pointer or reference in another language).
	--Or values, which are just raw values.
	--To assign a refvar, use $.. = [ .. ] to perform a traversal and get the relevant info.
	--To assign a value, use $.. = .. with anything else.
	local variables = {}
	local var_clear_callbacks = {}
	local var_data_meta = {
		__mode = "v", --Have variables store weak external references so that GC isn't impacted much.
	}

	--Call stack for files, which provide the ability to use functions.
	local call_stack = {}

	--Extension tracking tables. These get set once during init().
	local value_types, statements = nil

function ChatCommands:init()
	--Informations used for error handling.
	self.error_condition = false
	self.script_path = "mods/Heat Chat Commands/scripts/"

	self.log_options = {
		[FUNCTION] = true,
		[INSTRUCTION] = false,
		[POSITION] = false,
		[TYPE_IS] = false,
		[TYPE_GET] = true,
		[STATEMENT] = true
	}

	value_types = value_types or HCC_value_types
	statements = statments or HCC_statements
end

function ChatCommands:parse(command)
	self:eval(command)
	self.error_condition = false
end

function ChatCommands:pos(offset)
	return math.min(math.max(self:_stack_frame().pos + (offset or 1), 1), #self:_stack_frame().instructions)
end

function ChatCommands:i_pos(spaces)
	self:_log(POSITION, "Advancing to " .. tostring(self:pos() + (spaces or 1)))
	self:_stack_frame().pos = self:_stack_frame().pos + (spaces or 1)
end

function ChatCommands:c_pos(...)
	local arg = {...}
	for i = 1, #arg do
		if self:get() == arg[i] or arg[i] == "" then
			self:i_pos()
		else
			self:trigger_error("SYNTAX ERROR: Expected a \"" .. arg[i] .. "\" but got \"" .. self:get() .. "\"")
		end
	end
end

function ChatCommands:complete()
	return self:_stack_frame().pos > #self:_stack_frame().instructions or self.error_condition
end

function ChatCommands:get(index)
	local frame = self:_stack_frame()
	if self.log_options[INSTRUCTION] then
		if frame.instructions[index and index + self:pos() or self:pos()] then
			log("Consuming " .. frame.instructions[index and index + frame.pos or frame.pos])
		elseif not index then
			log("FATAL ERROR: Attempted to consume nonexistent instruction.")
		end
	end
	return frame.instructions[index and index + frame.pos or frame.pos]
end

function ChatCommands:trigger_error(error_msg)
	if not self.error_condition then
		log(error_msg)
		self:print_position_info()
		self.error_condition = true
	end
end

function ChatCommands:get_var_data_meta()
	return var_data_meta
end

function ChatCommands:is_refvar(obj)
	if type(obj) == "table" then
		local metatable = getmetatable(obj)
		if metatable == var_data_meta then
			return true
		end
	end
	return false
end

function ChatCommands:call_function(curr, prev, key)
	self:_log(FUNCTION, "parse call function")
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

	args = self:parse_func_arg_list(args)
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

function ChatCommands:get_variable(name)
	return variables[name] or self:_stack_frame().args[name]
end

function ChatCommands:deref_variable(name, ref_only)
	self:_log(FUNCTION, "parse deref variable")
	local var = self:get_variable(name)

	if not var then
		log("WARNING: No variable named " .. name)
		return
	end

	if not self:is_refvar(var) then
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
	self:_log(FUNCTION, "eval")

	if #call_stack == 100 then
		self:trigger_error("STACK ERROR: Over 100 files were loaded at once, it's likely that there is unbounded recursion.")
		return
	end

	--Create a new stack frame to evaluate.
	table.insert(call_stack, {
		instructions = self:_lex(instructions),
		pos = 1,
		statement_pos = 1,
		file = file,
		args = args or {}
	})

	--Consume the current stack frame.
	while not self:complete() do
		self:_stack_frame().statement_pos = self:pos()
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
	table.remove(call_stack)
end

function ChatCommands:print_position_info()
	local pos = self:pos()
	local curr_ins = self:get()
	local min_pos = math.max(self:_stack_frame().statement_pos - 1, 1) --TODO: Not sure why this if off by 1. Need to fix.
	local instructions = self:_stack_frame().instructions
	local max_pos = math.min(pos + 5, #instructions)
	local nearby_instructions = table.concat(instructions, " ", min_pos, max_pos)
	log("    Around:" .. nearby_instructions)
	log("    Instruction number " .. tostring(self:pos()))
	if self:_stack_frame().file then
		log("    From file \"" .. self:_stack_frame().file .. "\"")
	else
		log("    From in-game chat.")
	end
end

--Public parsers that are used by extensions because they perform useful functions.
	function ChatCommands:parse_func_arg_list(args, as_refvar)
		self:_log(FUNCTION, "parse func arg list")
		local ins = self:get()
		local args = args or {}
		local args_str = {}
		local args_terminated = false
		self:c_pos('(') --Skip the "("
		while not self:complete() and not args_terminated do
			ins = self:get()
			if ins == ")" then
				args_terminated = true
				self:i_pos()
			else
				local value = self:parse_expression(as_refvar)
				table.insert(args, value)
				table.insert(args_str, ins)
			end

			if self.error_condition then
				return
			end
		end

		if not args_terminated then
			self:trigger_error("SYNTAX ERROR: Function call to " .. tostring(key) .. " using (" .. table.concat(args_str, " ") .. ") was not terminated.")
			return
		end

		return args
	end

	function ChatCommands:parse_call_function()
		self:_log(FUNCTION, "parse call function")
		local reference = self:parse_expression(AS_REFVAR)
		if self:is_refvar(reference) then
			self:call_function(reference.value, reference.parent, reference.key)
		else
			self:trigger_error("LOOKUP ERROR: Unable to call functions from non-referenced variables.")
		end
	end

	function ChatCommands:parse_expression(as_refvar)
		self:_log(FUNCTION, "parse expression")
		return self:_parse_value(as_refvar)
	end

--Private utility functions. These generally change important private state and should not concern extensions.
	function ChatCommands:_unset_variable(name)
		variables[name] = nil
		local callbacks = var_clear_callbacks[name]
		if callbacks then
			for i = 1, #callbacks do
				callbacks[i]()
			end
			var_clear_callbacks[name] = nil
		end
	end

	function ChatCommands:_log(option, ...)
		if self.log_options[option] then
			log(...)
		end
	end

	--Breaks the command up into distinct arguments to be consumed.
	--By parsing functions.
	--Doesn't do 'real' lexxing, but is still important for tokenizing input
	function ChatCommands:_lex(command)
		command = command:gsub("//.*\n", "")
		command = command:gsub("([|!={}%(%)%[%]])", " %1 ")
		return command:split("%s")
	end

	function ChatCommands:_check_condition_stack()
		for i = 1, #condition_stack do
			if not condition_stack[#condition_stack] then
				return false
			end
		end

		return true
	end

	function ChatCommands:_stack_frame()
		return call_stack[#call_stack]
	end


--Special form parsers that follow their own rules that should not be invoked by extensions to the framework.
	function ChatCommands:_parse_statement()
		self:_log(FUNCTION, "parse statement")
		local ins = self:get()
		local first_char = ins:sub(1,1)

		if statements[ins] then
			self:_log(STATEMENT, "Executing " .. ins)
			statements[ins](self)
		elseif first_char == "$" then
			local next_ins = self:get(1)
			if next_ins == "=" then
				self:_parse_assignment()
			elseif next_ins and next_ins:sub(1,1) == "(" then
				self:parse_call_function()
			else
				self:trigger_error("SYNTAX ERROR: Unexpected token " .. next_ins)
			end
		else
			self:trigger_error("SYNTAX ERROR: Unexpected token " .. ins)
		end
	end

	function ChatCommands:_parse_assignment()
		self:_log(FUNCTION, "parse assignment")
		local variable = self:get()
		if variable:len() == 1 then
			self:trigger_error("SYNTAX ERROR: Attempted to assign to a variable without a name.")
			return
		elseif tonumber(variable:sub(2,-1)) then
			self:trigger_error("SYNTAX ERROR: Numerical variable name \"" .. variable .. "\" is reserved for script parameters.")
			return
		end

		self:c_pos("", "=")
		local value_ins = self:get()
		if value_ins == "nil" then
			self:_unset_variable(variable)
			self:i_pos()
		elseif value_ins then
			local new_value = self:parse_expression(AS_REFVAR)
			if not self.error_condition then
				self:_unset_variable(variable)
				variables[variable] = new_value
			end
		else
			self:trigger_error("SYNTAX ERROR: No value given to set variable \"" .. variable .. "\" to.")
		end
	end

	function ChatCommands:_parse_if_statement()
		self:_log(FUNCTION, "parse if")
		self:i_pos() --Skip the 'if' keyword.
		table.insert(condition_stack, self:parse_expression())
	end

	function ChatCommands:_parse_end()
		self:_log(FUNCTION, "parse end")
		if #condition_stack == 0 then
			log("Warning: End without a matching 'if'.")
			self:print_position_info()
		end
		self:i_pos() --Skip echo.
		table.remove(condition_stack) --Remove active conditional.
	end

	function ChatCommands:_parse_value(as_refvar)
		self:_log(FUNCTION, "parse value")
		local ins = self:get()
		if not ins then
			self:trigger_error("SYNTAX ERROR: Not enough arguments supplied.")
			return
		end

		for i = 1, #value_types do
			local t = value_types[i]
			self:_log(TYPE_IS, "Checking if \"" .. ins .. "\" is type \"" .. t.name .. "\"")
			if t.is(self, ins) then
				self:_log(TYPE_GET, "Getting value of \"" .. ins .. "\" as type \"" .. t.name .. "\"")
				return t.get(self, ins, as_refvar)
			end
		end

		self:trigger_error("SYNTAX ERROR: Unrecognized token " .. ins)
	end