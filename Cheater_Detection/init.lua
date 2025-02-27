--[[
    Main Entry Point for Cheater Detection
    Handles proper module loading, unloading, and global cleanup
]]

-- Global unload function to clean up resources
-- Modify the unload function to preserve the database in memory
local function UnloadCheaterDetection()
	print("[Cheater Detection] Unloading modules and cleaning up resources...")

	-- Track if we have a database before unloading
	local hasDatabase = false
	local databaseContent = nil

	-- Attempt to preserve database content
	pcall(function()
		local Database = package.loaded["Cheater_Detection.Database.Database"]
		if Database and Database.data and type(Database.data) == "table" then
			if Database.State and Database.State.entriesCount > 0 then
				-- We have a valid database, preserve it in global memory
				_G._CheaterDetectionDatabaseBackup = {
					data = Database.data,
					entriesCount = Database.State.entriesCount,
					lastSave = Database.State.lastSave,
				}
				hasDatabase = true
			end
		end
	end)

	-- Step 1: Unregister all callbacks
	local callbackNames = {
		-- General
		"CD_Unload",
		"CD_MENU",
		"CD_CreateMove",
		-- Database
		"CDDatabase_Unload",
		"DatabaseSave",
		"DatabaseFallbackSave",
		"CDDatabaseManager_RegisterCommands",
		"CDDatabaseManager_InitialFetch",
		-- Fetcher
		"FetcherMainTask",
		"FetcherUI",
		"FetcherCallback",
		"FetcherCleanup",
		"FetcherSingleSource",
		"FetcherSingleSourceCleanup",
		"DatabaseSaveDelay",
		"FetcherAutoLoad",
		"TasksProcessCleanup",
	}

	-- Unregister from all callback types to be thorough
	local callbackTypes = { "Draw", "CreateMove", "Unload", "FireGameEvent", "DispatchUserMessage", "SendStringCmd" }

	for _, cbType in ipairs(callbackTypes) do
		for _, cbName in ipairs(callbackNames) do
			pcall(function()
				callbacks.Unregister(cbType, cbName)
			end)
		end
	end

	-- Step 2: Clear all module references from package.loaded
	local modulePrefix = "Cheater_Detection"
	for moduleName in pairs(package.loaded) do
		if moduleName:find("^" .. modulePrefix) then
			package.loaded[moduleName] = nil
			if _G[moduleName] and moduleName ~= "Cheater_Detection.Database.Database" then
				_G[moduleName] = nil
			end
		end
	end

	-- Step 3: Clear any known global tables and variables (except database backup)
	local globals = {
		"G",
		"Detections",
		"Parsers",
		"Tasks",
		"Sources",
		"DBManager",
		"Menu",
	}

	for _, globalName in ipairs(globals) do
		if _G[globalName] then
			if type(_G[globalName]) == "table" then
				for k in pairs(_G[globalName]) do
					_G[globalName][k] = nil
				end
			end
			_G[globalName] = nil
		end
	end

	-- Step 4: Force multiple garbage collections but less aggressively
	collectgarbage("step", 500)

	print("[Cheater Detection] Unload complete" .. (hasDatabase and " (preserved database in memory)" or ""))
end

-- Handle module unloading if it's already loaded
if package.loaded["Cheater_Detection"] then
	UnloadCheaterDetection()
	package.loaded["Cheater_Detection"] = nil
end

-- Register the unload function to run on script unload
callbacks.Register("Unload", "CD_Unload", UnloadCheaterDetection)

-- Create the module with added validation functions
local CheaterDetection = {
	Version = "2.0.0-beta",
	UnloadModule = UnloadCheaterDetection,
}

-- Load the main module
local Main = require("Cheater_Detection.Main")

-- Export public methods
CheaterDetection.ReloadDatabase = Main.ReloadDatabase
CheaterDetection.UpdateDatabase = Main.UpdateDatabase
CheaterDetection.GetDatabaseStats = Main.GetDatabaseStats
CheaterDetection.ValidateDatabase = function()
	local DBManager = require("Cheater_Detection.Database.Manager")
	return DBManager.ValidateDatabase()
end

-- Add helper functions for UI safety
CheaterDetection.Utils = {
	-- Safe integer rounding for UI coordinates
	RoundCoord = function(value)
		if not value then
			return 0
		end
		if type(value) ~= "number" then
			return 0
		end
		if value ~= value or value == math.huge or value == -math.huge then
			return 0
		end
		return math.floor(value + 0.5)
	end,
}

-- Print initialization message with safe coordinates
printc(0, 255, 140, 255, string.format("[Cheater Detection] Initialized version %s", CheaterDetection.Version))

-- Return the module
return CheaterDetection
