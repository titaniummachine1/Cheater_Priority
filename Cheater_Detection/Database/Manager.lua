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

-- Modified initialize function to use validation instead of full reload
function Manager.Initialize(options)
	-- Import other modules *inside* the function to prevent circular dependencies
	local Database = require("Cheater_Detection.Database.Database")
	local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

	options = options or {}

	-- Override default config with provided options
	for k, v in pairs(options) do
		Manager.Config[k] = v
	end

	-- Load local database first without resetting if already loaded
	local startTime = globals.RealTime()

	-- Use the safe load that doesn't reset existing database
	Database.LoadDatabaseSafe(false)

	-- Configure validation mode based on options
	Database.Config.ValidationMode = options.ValidationMode or true
	Database.Config.ValidateOnly = options.ValidateOnly or false

	-- If auto-fetch is enabled, set up validation instead of full fetch
	if Manager.Config.AutoFetchOnLoad then
		-- Configure fetcher
		Fetcher.Config.AutoFetchOnLoad = true
		Fetcher.Config.NotifyOnFetchComplete = true

		-- Schedule validation for next frame to ensure everything is loaded
		local firstUpdateDone = false
		callbacks.Register("Draw", "CDDatabaseManager_InitialValidation", function()
			if not firstUpdateDone then
				firstUpdateDone = true

				if Database.State.entriesCount > 0 then
					-- Database already loaded, validate only
					printc(
						100,
						200,
						255,
						255,
						"[Database Manager] Validating existing database with "
							.. Database.State.entriesCount
							.. " entries"
					)
					Database.ValidateWithSources(false)
				else
					-- No database or empty, do a full fetch
					printc(100, 200, 255, 255, "[Database Manager] No database found, fetching from sources")
					Fetcher.AutoFetch(Database)
				end

				callbacks.Unregister("Draw", "CDDatabaseManager_InitialValidation")
			end
		end)
	end

	-- Return the database
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

-- Fix validation method to ensure proper progress tracking
function Manager.ValidateDatabase()
	local Database = require("Cheater_Detection.Database.Database")
	local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

	if Database.State.entriesCount == 0 then
		print("[Database Manager] No database loaded, fetching instead of validating")
		return Manager.ForceUpdate()
	end

	print("[Database Manager] Starting database validation")

	-- Reset Tasks system to ensure clean state
	Tasks.Reset()
	Tasks.Init(1) -- Initial setup for progress tracking

	-- Make sure the task knows it's validating
	Tasks.status = "running"
	Tasks.message = "Validating Database"
	Tasks.progress = 0
	Tasks.targetProgress = 0

	-- Register the UpdateProgress function to ensure smooth animation
	callbacks.Register("Draw", "TasksUpdateProgress", Tasks.UpdateProgress)

	-- Start the validation with proper progress tracking
	return Database.ValidateWithSources(false)
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

-- Fix command registration to avoid duplicate commands
local function RegisterValidationCommand()
	-- Check if command already exists before registering
	if not Commands.Exists("cd_validate") then
		Commands.Register("cd_validate", function()
			Manager.ValidateDatabase()
		end, "Validate database against sources without full reload")
	else
		print("[Database Manager] Command cd_validate already exists, skipping registration")
	end
end

-- Register commands without loading modules immediately
callbacks.Register("Draw", "CDDatabaseManager_RegisterCommands", function()
	RegisterCommands()
	callbacks.Unregister("Draw", "CDDatabaseManager_RegisterCommands")
end)

-- Register validation command only once using Draw callback
local validationCommandRegistered = false
callbacks.Register("Draw", "CDDatabaseManager_RegisterValidation", function()
	if not validationCommandRegistered then
		validationCommandRegistered = true
		RegisterValidationCommand()
		callbacks.Unregister("Draw", "CDDatabaseManager_RegisterValidation")
	end
end)

return Manager
