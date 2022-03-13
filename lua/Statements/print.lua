--Memoized indentation handling.
--Large prints can take a while, so any way to cut down on concatenation is a win.
local indent_strs = {
	"",
	"    ",
	"        ",
	"            "
}
local function get_indent(indent)
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

local AS_REFVAR = true

HCC_statements = HCC_statements or {}
HCC_statements.print = function (CC)
	CC:i_pos() --Skip 'print'

	local args = CC:parse_func_arg_list({}, AS_REFVAR)
	if CC.error_condition then
		return
	end

	for i = 1, #args do
		local value = args[i]
		if CC:is_refvar(value) then
			print_value(value.value, value.key)
		else
			print_value(value, "Literal")
		end
	end
end
