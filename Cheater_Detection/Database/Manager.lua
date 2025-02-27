--[[ 
    Database Manager module - Centralized control of database operations
]]

-- Import required components
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands

-- Create the Manager object
local Manager = {
	-- Configuration options
	Config = {
		AutoFetchOnLoad = true, -- Auto fetch database updates on script load
		CheckInterval = 24, -- Hours between auto updates
		LastCheck = 0, -- Timestamp of last update check
		MaxEntries = 20000, -- Maximum number of database entries
	},
}

-- Modified initialize function to use correct fetcher function
function Manager.Initialize(options)
	-- Import other modules only when needed
	local Database = require("Cheater_Detection.Database.Database")
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

	-- Apply any provided options
	if options then
		for k, v in pairs(options) do
			Manager.Config[k] = v
		end
	end

	-- Load local database first
	Database.LoadDatabaseSafe(false)

	-- Auto fetch if enabled
	if Manager.Config.AutoFetchOnLoad then
		-- Schedule update for next frame to avoid initialization issues
		callbacks.Register("Draw", "CDDatabaseManager_InitialUpdate", function()
			callbacks.Unregister("Draw", "CDDatabaseManager_InitialUpdate")

			printc(100, 200, 255, 255, "[Database Manager] Updating database from sources...")
			Fetcher.FetchAll(Database) -- Use FetchAll instead of FetchAllNoValidation
		end)
	end

	-- Return the database
	return Database
end

-- Force an immediate database update
function Manager.UpdateDatabase()
	local Database = require("Cheater_Detection.Database.Database")
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

	print("[Database Manager] Starting database update")
	return Fetcher.FetchAll(Database) -- Use FetchAll instead of FetchAllNoValidation
end

-- Get database stats
function Manager.GetStats()
	local Database = require("Cheater_Detection.Database.Database")
	return Database.GetStats()
end

-- Only register commands once
Commands.Register("cd_update", function()
	Manager.UpdateDatabase()
end, "Update the cheater database from online sources")

Commands.Register("cd_cleanup", function()
	local Database = require("Cheater_Detection.Database.Database")
	Database.Cleanup()
	print("[Database Manager] Cleanup completed")
end, "Remove unnecessary database entries to improve performance")

Commands.Register("cd_stats", function()
	local stats = Manager.GetStats()
	print(string.format("[Database] Total entries: %d", stats.entryCount))
	print(string.format("[Database] Memory usage: %.2f MB", stats.memoryMB))
end, "Show database statistics")

return Manager
