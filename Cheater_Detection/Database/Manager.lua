--[[ 
    Database Manager module - Centralized control of database operations
    Allows for easy initialization, updating, and management of databases
]]

-- Import required components
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands
-- Import database components directly, don't use variable assignments yet
local Json = Common.Json

-- Create the Manager object
local Manager = {}

-- Configuration options
Manager.Config = {
	AutoFetchOnLoad = true, -- Automatically fetch database updates on script load
	CheckInterval = 24, -- How often to automatically check for updates (in hours)
	LastCheck = 0, -- Timestamp of last update check
	MaxEntries = 20000, -- Maximum number of database entries (performance optimization)
}

-- Initialize database system completely
function Manager.Initialize(options)
	-- Import other modules *inside* the function to prevent circular dependencies
	local Database = require("Cheater_Detection.Database.Database")
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

	options = options or {}

	-- Override default config with provided options
	for k, v in pairs(options) do
		Manager.Config[k] = v
	end

	-- Load local database first
	local startTime = globals.RealTime()
	Database.LoadDatabase(false) -- Not silent, show loading message

	-- If auto-fetch is enabled, set up fetcher
	if Manager.Config.AutoFetchOnLoad then
		-- Configure fetcher
		Fetcher.Config.AutoFetchOnLoad = true
		Fetcher.Config.NotifyOnFetchComplete = true

		-- Schedule fetch for next frame to ensure everything is loaded
		local firstUpdateDone = false
		callbacks.Register("Draw", "CDDatabaseManager_InitialFetch", function()
			if not firstUpdateDone then
				firstUpdateDone = true
				Fetcher.AutoFetch(Database)
				callbacks.Unregister("Draw", "CDDatabaseManager_InitialFetch")
			end
		end)
	end

	-- Return the fully initialized database
	return Database
end

-- Add a new data source
function Manager.AddSource(name, url, cause, type)
	-- Import Fetcher only when needed to avoid circular dependencies
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")
	local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")

	return Sources.AddSource(name, url, cause, type or "raw")
end

-- Force an immediate database update
function Manager.ForceUpdate()
	local Database = require("Cheater_Detection.Database.Database")
	Database.FetchUpdates(false)
end

-- Get database stats
function Manager.GetStats()
	local Database = require("Cheater_Detection.Database.Database")
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

	-- Use a weak table for temporary statistics storage
	local byType = setmetatable({}, { __mode = "v" })
	local entries = 0

	for steamId, data in pairs(Database.content or {}) do
		entries = entries + 1
		local cause = data.cause or "Unknown"
		byType[cause] = (byType[cause] or 0) + 1

		-- Yield periodically if there are many entries
		if entries % 5000 == 0 then
			coroutine.yield()
		end
	end

	return {
		totalEntries = entries,
		byType = byType,
		lastFetch = Fetcher.Config.LastAutoFetch,
		lastUpdate = Manager.Config.LastCheck,
	}
end

-- Register commands later to avoid loading modules immediately
local function RegisterCommands()
	Commands.Register("cd_db_stats", function()
		-- Import modules only when the command is called
		local stats = Manager.GetStats()
		print(string.format("[Database Manager] Total entries: %d", stats.totalEntries))
		print("[Database Manager] Entries by type:")
		for cause, count in pairs(stats.byType) do
			print(string.format("  - %s: %d", cause, count))
		end
		print(string.format("[Database Manager] Last fetch: %s", os.date("%Y-%m-%d %H:%M:%S", stats.lastFetch)))
	end, "Show database statistics")

	Commands.Register("cd_update", function()
		Manager.ForceUpdate()
	end, "Update the cheater database from online sources")

	Commands.Register("cd_cleanup", function()
		local Database = require("Cheater_Detection.Database.Database")

		if not Database.content then
			print("[Database Manager] No database loaded")
			return
		end

		Database.Cleanup()
		print("[Database Manager] Cleanup completed")
	end, "Remove unnecessary database entries to improve performance")
end

-- Register commands without loading modules immediately
callbacks.Register("Draw", "CDDatabaseManager_RegisterCommands", function()
	RegisterCommands()
	callbacks.Unregister("Draw", "CDDatabaseManager_RegisterCommands")
end)

return Manager
