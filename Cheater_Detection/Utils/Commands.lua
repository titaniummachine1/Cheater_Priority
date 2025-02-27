--[[
    Simple Commands Utility
    Provides command registration with automatic overwrite
]]

local Commands = {}

-- Store registered commands
Commands.registered = {}

-- Register a command (always overwrite existing)
function Commands.Register(name, callback, helpText)
	-- Register the command, overriding any existing one
	Commands.registered[name] = {
		callback = callback,
		helpText = helpText or "No description available",
	}

	-- Register with the engine
	client.Command_Register(name, function(args)
		local cmd = Commands.registered[name]
		if cmd and type(cmd.callback) == "function" then
			cmd.callback(args)
		end
	end)
end

-- Unregister a command
function Commands.Unregister(name)
	if Commands.registered[name] then
		client.Command_Unregister(name)
		Commands.registered[name] = nil
		return true
	end
	return false
end

-- Get help text for a command
function Commands.GetHelp(name)
	local cmd = Commands.registered[name]
	return cmd and cmd.helpText or "Command not found"
end

-- List all registered commands
function Commands.List()
	local result = {}
	for name, _ in pairs(Commands.registered) do
		table.insert(result, name)
	end
	return result
end

return Commands
