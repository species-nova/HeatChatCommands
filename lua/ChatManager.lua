_G.ChatCommand = _G.ChatCommand or {}

local orig_init = ChatManager.init
function ChatManager:init(...)
	orig_init(self, ...)
	self._ChatCommands = ChatCommands:new()
end

function ChatManager:execute_command(message, peer)
	if not message then
		return
	end

	--Parse message for commands.
	local command = tostring(message)
	local prefix = command:sub(1, 1)

	if prefix == "/" then
		command = command:sub(2, -1)
	elseif prefix ~= "!" then
		return
	end

	--Try to execute command.
	--Only the host actually executes commands, but clients can ask the host to execute them.
	if Utils:IsInHeist() and command then 
		self._ChatCommands:parse(command, nil, nil)
	end
end

local _receive_message_by_peer_orig = ChatManager.receive_message_by_peer
function ChatManager:receive_message_by_peer(channel_id, peer, message)
	--Get message normally
	_receive_message_by_peer_orig(self, channel_id, peer, message)
	self:execute_command(message, peer)
end

function ChatManager:say(...)
	local args = {...}
	for i, v in ipairs(args) do
		managers.chat:send_message(ChatManager.GAME, "", tostring(v))
	end
end