_G.ChatCommand = _G.ChatCommand or {}

Hooks:PostHook(ChatManager, "init" , "ChatCommand" , function(self)
	self:AddCommand({"jail", "custody"}, false, false, function(peer)
		if not managers.trade:is_peer_in_custody(peer:id()) then
			if peer:id() == 1 then
				local player = managers.player:local_player()
				managers.player:force_drop_carry()
				managers.statistics:downed( { death = true } )
				IngameFatalState.on_local_player_dead()
				game_state_machine:change_state_by_name( "ingame_waiting_for_respawn" )
				player:character_damage():set_invulnerable( true )
				player:character_damage():set_health( 0 )
				player:base():_unregister()
				player:base():set_slot( player, 0 )
			else
				local _unit = peer:unit()
				_unit:network():send("sync_player_movement_state", "incapacitated", 0, _unit:id() )
				_unit:network():send_to_unit( { "spawn_dropin_penalty", true, nil, 0, nil, nil } )
				managers.groupai:state():on_player_criminal_death( _unit:network():peer():id() )
			end
		end
	end,
	"] - Sends the user to custody.")

	self:AddCommand({"loud", "alarm"}, true, false, function()
		if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
			managers.groupai:state():on_police_called("alarm_pager_hang_up")
			managers.hud:show_hint( { text = "LOUD!" } )
		end	
	end,
	"] HOST ONLY - Sounds the alarm. May softlock on certain heists if used too early.")


	self:AddCommand("ammo_clip", false, true, function(peer, type1, type2)
		local count = type2 or 1
		local unit = managers.player:local_player()
		local pos = unit:movement():m_pos()
		local rot = unit:movement():m_head_rot():y()
		for i = 1, count do
			managers.game_play_central:spawn_pickup({
				name = self._pickup,
				position = pos,
				rotation = rot
			})
		end
	end,
	"] - Spawns an ammo box at the host's feet.")
	
	self:AddCommand("spawngroup", true, false, function(peer, args)
		if not args[2] then
			self:say("No spawn group given.")
			return
		end

		for i = 2, #args do
			args[i] = string.lower(args[i])
		end

		local groups = tweak_data.group_ai.enemy_spawn_groups
		for group, _ in pairs(groups) do
			if string.lower(group) == args[2] then
				managers.groupai:state():force_spawn_group_hard(group)
				return
			end
		end
			
		self:say("Invalid spawn group \"" .. args[2] .. "\"")
	end,
	" groupName(string)] Host Only - Forces the desired spawn group to be spawned in next during the next valid opportunity in an assault.")


	function set_team( unit, team )
		local M_groupAI = managers.groupai
		local AIState = M_groupAI:state()	
		local team_id = tweak_data.levels:get_default_team_ID( team )
		unit:movement():set_team( AIState:team_data( team_id ) )
	end

	self:AddCommand("spawn", true, false, function(peer, args)
		if peer and peer:unit() then
			if not args[2] then
				self:say("No unit name given.")
				return
			end

			for i = 2, #args do
				args[i] = string.lower(args[i])
			end

			local unit = peer:unit()
			local unit_name = nil
			local count = tonumber(args[3] or "1")
			local unit_categories = tweak_data.group_ai.unit_categories
			local group_type = tweak_data.levels:get_ai_group_type()
			
			for category, data in pairs(unit_categories) do
				if string.lower(category) == args[2] then
					local unit_table = data.unit_types[group_type]
					unit_name = unit_table[math.random(#unit_table)]
				end
			end
			
			if not unit_name then
				if args[2] == "sniper" then
					unit_name = Idstring("units/payday2/characters/ene_sniper_1/ene_sniper_1")
				else
					self:say("Invalid unit \"" .. args[2] .. "\"")
					return
				end		
			end

			for i = 1, count do
				local unit_done = World:spawn_unit( unit_name, unit:position(), unit:rotation() )
				set_team( unit_done, unit_done:base():char_tweak().access == "gangster" and "gangster" or "combatant" )
			end
		end
	end,
	" unitCategory(string) count(#)] HOST ONLY - Spawns in one or more units of the desired GroupAI unitCategory at the host's location.")

	self:AddCommand({"restart"}, false, true, function()
		--Copy from Quick/Instant restart 1.0 by: FishTaco
		local all_synced = true
		for k,v in pairs(managers.network:session():peers()) do
			if not v:synched() then
				all_synced = false
			end
		end
		if all_synced then
			managers.game_play_central:restart_the_game()
		end	
	end,
	"] - Restarts the current heist.")

	self:AddCommand({"revive"}, false, true, function()
		local player = managers.player:local_player()
		player:character_damage():revive()
	end,
	"] - Revives the user from being downed.")

	self:AddCommand({"reload"}, false, true, function()
		managers.player:refill_weapons()
	end,
	"] - Reloads all equipped guns.")

	self:AddCommand({"god"}, false, true, function()
		local player = managers.player:local_player()
		local is_god = player:character_damage():god_mode()
		player:character_damage():set_god_mode(not is_god)
	end,
	"] - Enables/Disables god mode.")

	self:AddCommand("end", true, false, function()
		if game_state_machine:current_state_name() ~= "disconnected" then
			MenuCallbackHandler:load_start_menu_lobby()
		end	
	end,
	"] - Ends the current heist.")

	self:AddCommand("win", true, false, function()
		local num_winners = managers.network:session():amount_of_alive_players() 
		managers.network:session():send_to_peers("mission_ended", true, num_winners) 
		game_state_machine:change_state_by_name("victoryscreen", {num_winners = num_winners, personal_win = true}) 
	end,
	"] - Wins the current heist.")

	self:AddCommand({"doctor_bag", "db"}, false, true, function()
		local player = managers.player:local_player()
		local pos = player:movement():m_pos()
		local rot = player:movement():m_head_rot():y()
		DoctorBagBase.spawn(pos, rot, 0)
	end,
	"] - Spawns a doctor bag at the user's feet.")

	self:AddCommand({"ammo_bag", "ab"}, false, true, function()
		local player = managers.player:local_player()
		local pos = player:movement():m_pos()
		local rot = player:movement():m_head_rot():y()
		AmmoBagBase.spawn(pos, rot, 0)
	end,
	"] - Spawns an ammo bag at the user's feet.")

	self:AddCommand({"grenade_case", "gc", "throwable_case", "throwables_case", "tc"}, false, true, function()
		local player = managers.player:local_player()
		local pos = player:movement():m_pos()
		local rot = player:movement():m_head_rot():y()
		GrenadeCrateBase.spawn(pos, rot, 0)
	end,
	"] - Spawns a grenade case at the user's feet.")

	self:AddCommand({"first_aid_kit, fak"}, false, true, function()
		local player = managers.player:local_player()
		local pos = player:movement():m_pos()
		local rot = player:movement():m_head_rot():y()
		FirstAidKitBase.spawn( pos, rot, 0 , 0 )
	end,
	"] - Spawns a first aid kit at the user's feet.")

	self:AddCommand("mark", false, false, function()
		local player = managers.player:local_player()
		local targets = World:find_units_quick("sphere", player:movement():m_pos(), math.huge, managers.slot:get_mask("trip_mine_targets"))

		for _, unit in ipairs(targets) do
			if alive(unit) and not unit:base():char_tweak().is_escort then
				managers.game_play_central:auto_highlight_enemy(unit, true)
			end
		end
	end,
	"] - Marks all markeable units on the map. This includes enemies and civilians.")

	self:AddCommand("nuke", false, false, function()
		local player = managers.player:local_player()
		local targets = World:find_units_quick("sphere", player:movement():m_pos(), math.huge, managers.slot:get_mask("enemies"))
		for _, unit in ipairs(targets) do
			if alive(unit) and unit.character_damage then
				unit:character_damage():damage_mission({damage = 9999999})
			end
		end
	end,
	"] - Kills all enemies on the map.")

	self:AddCommand({"set_level", "level"}, false, true, function(peer, args)
		managers.experience:_set_current_level(math.min(math.max(args[2], 0), 100) or 100)
	end,
	" level(#, 1-100)] LOCAL - Sets the user's level.")

	self:AddCommand({"perk_points", "pp"}, false, true, function(peer, args)
		managers.skilltree:give_specialization_points(args[2] or 1000000000)
	end,
	" points(#)] LOCAL - Gives the user perk points.")

	self:AddCommand({""}, false, true, function(peer, args)
		managers.money:_add_to_total(args[2] or 1000000000)
	end,
	" cash(#)] LOCAL - Gives the user money.")

	self:AddCommand("free", false, false, function(peer)
		if peer and peer:unit() and managers.trade then
			local unit = peer:unit()
			local nowtime = math.floor(TimerManager:game():time())
			local pos = unit:position()
			local rot = unit:rotation()
			for k, v in pairs( managers.network:session():peers() ) do
				if managers.trade and managers.trade.is_peer_in_custody and managers.trade:is_peer_in_custody(v:id()) then
					IngameWaitingForRespawnState.request_player_spawn(v:id())
				end
			end
			for dt = 1, 4 do
				local first_crim = managers.trade:get_criminal_to_trade(false)
				if not first_crim then
					break
				end
				managers.enemy:add_delayed_clbk("Respawn_criminal_on_trade_"..dt, callback(managers.trade, managers.trade, "clbk_respawn_criminal", pos, rot), nowtime + dt * 2)
			end
		end
	end,
	"] - Frees the user from custody.")

	local reading_minds = false
	self:AddCommand("read_minds", true, false, function()
		managers.groupai:state():set_debug_draw_state(not reading_minds)
		reading_minds = not reading_minds
	end,
	"] HOST ONLY - Toggles the generic GroupAI debug draw mode.")

	self:AddCommand("speed", true, false, function(peer, type1, type2)
		TimerManager:timer(Idstring("player")):set_multiplier(type2 or 1)
		TimerManager:timer(Idstring("game")):set_multiplier(type2 or 1)
		TimerManager:timer(Idstring("game_animation")):set_multiplier(type2 or 1)
	end,
	" speedMultiplier(#)] HOST ONLY - Multiplies the speed of the game by speedMultiplier. If no multiplier is supplied, the speed is set to '1' (100%). Liable to explode if used in multiplayer.")

	local frozen = false
	self:AddCommand("freeze", true, false, function()
		if not frozen then
			TimerManager:timer(Idstring("game")):set_multiplier(0.000001)
			TimerManager:timer(Idstring("game_animation")):set_multiplier(0.000001)
		else
			TimerManager:timer(Idstring("game")):set_multiplier(1)
			TimerManager:timer(Idstring("game_animation")):set_multiplier(1)
		end
	end,
	"] HOST ONLY - Toggles slowing down everything except the player to a near standstill. Useful for screenshots, liable to explode if used in multiplayer.")
	
	local visible = true
	self:AddCommand("invisible", true, false, function()
		if visible then
			local unit = managers.player:local_player()
			managers.groupai:state():unregister_AI_attention_object(unit:key())
			visible = false
		else
			local unit = managers.player:local_player()
			local attention_handler = unit:movement():attention_handler()
			local nav_tracker = unit:movement():nav_tracker()
			local team = unit:movement():team()
			local SO_access = unit:movement():SO_access()
			managers.groupai:state():register_AI_attention_object(unit, attention_handler, nav_tracker, SO_access, team)
		end
	end,
	"] HOST ONLY - Makes the host invisible to any NPCs that have not yet gotten their attention object. If the host is already invisible, then it makes them visible again.")

	self:AddCommand("enduring", false, true, function()
		managers.player:check_enduring()
	end,
	"] LOCAL - Triggers the bot enduring skill.")

	self:AddCommand({"assault", "start_assault", "eat_ass"}, true, false, function()
		managers.groupai:state():set_assault_mode(true)
	end,
	"] HOST ONLY - Starts the police assault mode in GroupAI.")

	self:AddCommand({"end_assault", "end_ass"}, true, false, function()
		managers.groupai:state():force_end_assault_phase(true)
	end,
	"] HOST ONLY - Ends the current police assault in GroupAI.")

	self:AddCommand({"die", "down"}, false, true, function()
		local damage_ext = managers.player:local_player():character_damage()
		damage_ext:damage_simple({damage = 100000})
		damage_ext:damage_simple({damage = 100000})
	end,
	"] LOCAL - Downs the user.")

	self:AddCommand("damage", false, true, function(peer, args)
		local damage_ext = managers.player:local_player():character_damage()
		local amount = args[2] or 50
		damage_ext:damage_simple({damage = amount * 0.1, armor_piercing = (not (args[3] and args[3] == "true"))})
	end,
	" amount(#) piercing(true|false)] LOCAL - Deals damage to the user. Defaults to 50 armor piercing damage.")
	
	self:AddCommand("diff", false, false, function()
		self:say("Spicy level is: " .. tostring(managers.groupai:state()._difficulty_value))
	end,
	"] - Returns the current difficulty value from GroupAI.")


	local variables = {}
	local profilers = {}

	--Have variables store weak external references so that GC isn't impacted.
	local var_data_meta = {__mode = "v"}

	function value_of(v, k, indent, seen)
		indent = indent and indent .. "    " or ""
		seen = seen or {}
		k = k or "[Unknown]"

		local type = type(v)
		if type == "table" then
			log(indent .. tostring(k) .. " = {")
			value_of_table(v, k, indent, seen)
			log(indent .. "}")
		elseif type == "userdata" then
			local v_table = getmetatable(v) or {}

			log(indent .. tostring(k) .. " = " .. tostring(v) .. " | type = " .. type .. " {")
			value_of_table(v_table, k, indent, seen)
			log(indent .. "}")
		else
			log(indent .. tostring(k) .. " = " .. tostring(v) .. " | type = " .. type)
		end
	end

	function value_of_table(t, name, indent, seen)
		indent = indent and indent .. "    " or ""
		seen = seen or {}
		name = name or "[Unknown]"

		if seen[t] then
			log(indent .. "REFERENCE TO " .. seen[t])
			return
		end

		seen[t] = tostring(name)
		for k, v in pairs(t) do
			value_of(v, k, indent, seen)
		end
	end

	function unpack_variable(name)
			local var = variables[name]
			if not var then
				self:say(name .. " has not been declared, or has been freed.")
				return
			end

			value = var.value
			parent = var.parent
			key = var.key
			if not value or not parent then
				self:say(name .. " has been deallocated. Freeing metadata from memory.")
				var = nil
				profilers[name] = nil
				return
			end
			return value, parent, key
	end

	self:AddCommand("let", false, true, function(peer, args)
		--Ensure basic validity of syntax.
		local name = args[2]
		if #args < 3 or name:sub(1, 1) ~= "$" and args[3] ~= "=" then
			self:say("Invalid arguments supplied.")
			return
		end

		--Was called in the form of "/let %var =" without anything else.
		--Set the variable to nothing.
		if not args[4] then
			self:say("Freeing " .. name)
			variables[name] = nil
			profilers[name] = nil
			return
		end

		local curr, prev, key, start
		if args[4]:sub(1, 1) == "$" then
			curr, prev, key = unpack_variable(args[4])
			if not curr then
				return
			end

			start = 5
		else
			curr = _G
			prev = _G
			start = 4
		end

		local function call(curr, prev, name)
			local temp = curr

			if type(prev) == "userdata" then
				curr = curr(prev)
				prev = method
			else
				local result = false
				result, curr = pcall(curr, prev)

				if not result then
					self:say("Function call to " .. name .. "failed")
					return
				end
			end
			  
			prev = temp
			return curr, prev
		end

		for i = start, #args do
			local arg = args[i]

			if arg == "()" and type(curr) == "function" then
				curr, prev = call(curr, prev, name)

				if not curr then
					self:say("Trail ended at call to value " .. args[i - 1])
					return
				end
			elseif type(curr) == "table" then
				prev = curr
				curr = curr[arg]
				key = arg
			elseif type(curr) == "userdata" then
				local curr_metatable = getmetatable(curr) or {}
				prev = curr
				curr = curr_metatable[arg]
				key = arg
			else
				self:say("Could not index value " .. args[i-1])
				return
			end

			if not curr then
				self:say("Trail ended at value " .. arg)
				return
			end
		end

		local var_data = {}
		setmetatable(var_data, var_data_meta)
		var_data.key = key
		var_data.value = curr
		var_data.parent = prev
		variables[name] = var_data
	end,
	" $variableName(string) = $variableName(string)|luaVariable(string) luaVariable(string)] LOCAL - Stores a reference to the desired item in LUA for debugging. Leave reference blank to remove a variable.")

	self:AddCommand("print", false, true, function(peer, args)
		--Ensure basic validity of syntax.
		for i = 2, #args do
			name = args[i]
			if name:sub(1, 1) ~= "$" then
				self:say("Invalid variable name, \"" .. name .. "\" must begin with a $.")
			else
				value, parent, key = unpack_variable(name)
				if value then
					value_of(value, key)
				end
			end
		end
	end,
	" $variableName(string, any number)] LOCAL - Prints out the desired variables and all of their subfields.")

	function ChatManager:exec_variables(action, args)
		for i = 2, #args do
			local name = args[i]
			if name:sub(1, 1) ~= "$" then
				self:say("Invalid variable name, \"" .. name .. "\" must begin with a $.")
			else
				action(name)
			end
		end
	end

	self:AddCommand({"profile", "add_profiler", "remove_profiler"}, false, true, function(peer, args)
		self:exec_variables(function(name)
			value, parent, key = unpack_variable(name)
			if value then
				if not profilers[name] then
					if type(value) == "function" and type(parent) == "table" then
						local profiler = {
							start_time = os.clock(),
							exec_time = 0,
							worst_time = 0,
							calls = 0,
							original_value = value
						}
						profilers[name] = profiler

						parent[key] = function(...)
							profiler.calls = profiler.calls + 1
							local time = os.clock()
							r = {value(...)}
							local time_taken = os.clock() - time
							profiler.exec_time = profiler.exec_time + time_taken
							profiler.worst_time = math.max(profiler.worst_time, time_taken)
							return unpack(r)
						end
						self:say("Established profiling on " .. name)
					else
						self:say("Variable " .. name .. " is not a function attached to a lua table, and therefore cannot be profiled.")
					end
				else
					parent[key] = profilers[name].original_value
					profilers[name] = nil
					self:say("Removed profiling from " .. name)
				end
			end
		end, args)
	end,
	" $variableName(string, any number)] LOCAL - Attaches/detaches profilers to the given functions to allow for their performance to be measured.")

	self:AddCommand({"check", "check_profiler"}, false, true, function(peer, args)
		local function check_profilers(name)
			if profilers[name] then
				local profiler = profilers[name]
				local total_time = os.clock() - profiler.start_time
				log(name .. " profiler data:")
				log("    Calls = " .. profiler.calls)
				log("    Average runtime = " .. tostring(profiler.exec_time / profiler.calls))
				log("    % of runtime = " .. tostring(profiler.exec_time / total_time))
				log("    Worst time = " .. tostring(profiler.worst_time))
				log("    Total execution time = " .. tostring(profiler.exec_time))
				log("    Profiler lifetime = " .. tostring(total_time))
			else
				self:say(name .. " does not have a profiler attached.")
			end
		end

		if #args > 1 then
			self:exec_variables(check_profilers, args)
		else
			for k, _ in pairs(profilers) do
				check_profilers(k)
			end
		end
	end,
	" $variableName(string, any number, optional)] LOCAL - Prints out the current results from the desired profilers.")

	self:AddCommand("help", false, false, function(peer, args)
		if not args[2] then
			args[2] = "help"
		end

		for i = 2, #args do
			if self._commands[args[i]] then
				self:say("[/" .. args[i] .. tostring(self._commands[args[i]].desc or "] - No help text given."))
			else
				self:say("Command " .. args[i] .. " does not exist.")
			end
		end
	end,
	" commands(string, repeatable)] - Prints out descriptions of all listed commands. Valid commands can be searched for using \"/list\".")

	self:AddCommand("list", false, false, function(peer, args)
		if not args[2] then
			self:say("You must supply a query. Not all commands will fit in the chat window.")
			return
		end

		local list = "Matching commands: "
		for k, _ in pairs(self._commands) do
			for i = 2, #args do
				if string.match(k, args[i]) then
					list = list .. '[' .. k .. '] '
					break
				end
			end
		end
		self:say(list)
	end,
	" queries(string, any number)] - Lists all commands that match any of the desired queries.")
end)

function ChatManager:say(...)
	local args = {...}
	for i, v in ipairs(args) do
		managers.chat:send_message(ChatManager.GAME, "", tostring(v))
	end
end

function ChatManager:execute_command(message, peer)
	if not message then
		return
	end

	--Parse message for commands.
	local message_str = tostring(message)
	local prefix = message_str:sub(1, 1)
	local args = message_str:sub(2, message_str:len()):split(" ")
	local command = string.lower(args[1])

	--Try to execute command.
	--Only the host actually executes commands, but clients can ask the host to execute them.
	if Utils:IsInHeist() and command and (prefix == "!" or prefix == "/") then 
		if self._commands and self._commands[command] and (
				(self._commands[command].ishost and peer:id() == 1 and Network and not Network:is_client())
			or not self._commands[command].isHost and (
				(self._commands[command].isLocal and managers.network:session():local_peer():id() == peer:id())
				or (Network and not Network:is_client()))) then
			self._commands[command].func(peer, args)
		else
			self:say("The command: " .. command .. " doesn't exist")
		end
	end
end

local _receive_message_by_peer_orig = ChatManager.receive_message_by_peer
function ChatManager:receive_message_by_peer(channel_id, peer, message)
	--Get message normally
	_receive_message_by_peer_orig(self, channel_id, peer, message)
	self:execute_command(message, peer)
end

function ChatManager:AddCommand(cmd, ishost, isLocal, func, desc)
	if not self._commands then
		self._commands = {}
	end

	local function add(name)
		self._commands[name] = {}
		self._commands[name].ishost = ishost
		self._commands[name].func = func
		self._commands[name].desc = desc
	end

	if type(cmd) == "string" then --add single command
		add(string.lower(cmd))
	elseif type(cmd) == "table" then
		for _, _cmd in pairs(cmd) do --Add multiple commands from table
			add(string.lower(_cmd))
		end
	end
end