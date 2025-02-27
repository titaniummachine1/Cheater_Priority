--[[
    Simplified Database.lua
    Direct implementation of database functionality using native Lua tables
    Stores only essential data: name and proof for each SteamID64
]]

local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Json = Common.Json
local Database_import = require("Cheater_Detection.Database.Database_Import")
local Database_Fetcher = require("Cheater_Detection.Database.Database_Fetcher")
local Restore = require("Cheater_Detection.Database.Database_Restore")

local Database = {
	-- Internal data storage (direct table)
	data = {},

	-- Configuration
	Config = {
		AutoSave = true,
		SaveInterval = 300, -- 5 minutes
		DebugMode = false,
		MaxEntries = 15000, -- Maximum entries to prevent memory issues
		ValidationMode = true, -- Enable validation mode by default
		BatchSize = 500, -- Process in smaller batches to prevent overflow
		ValidateOnly = false, -- If true, only validates but doesn't add new entries
	},

	-- State tracking
	State = {
		entriesCount = 0,
		isDirty = false,
		lastSave = 0,
	},

	-- Validation statistics
	ValidationStats = {
		entriesExisting = 0,
		entriesAdded = 0,
		entriesSkipped = 0,
		lastValidation = 0,
	},
}

-- Create the content accessor with metatable for cleaner API
Database.content = setmetatable({}, {
	__index = function(_, key)
		return Database.data[key]
	end,

	__newindex = function(_, key, value)
		Database.HandleSetEntry(key, value)
	end,

	__pairs = function()
		return pairs(Database.data)
	end,
})

-- Handle setting an entry with optimized record updating
function Database.HandleSetEntry(key, value)
	-- Skip nil values or invalid keys
	if not key then
		return
	end

	-- Get existing entry
	local existing = Database.data[key]

	-- If removing an entry
	if value == nil then
		if existing then
			Database.data[key] = nil
			Database.State.entriesCount = Database.State.entriesCount - 1
			Database.State.isDirty = true
		end
		return
	end

	-- If adding a new entry
	if not existing then
		-- Simplified data structure - keep only what's needed
		Database.data[key] = {
			Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
			proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown",
		}

		Database.State.entriesCount = Database.State.entriesCount + 1
		Database.State.isDirty = true
	else
		-- Update existing entry but only if the new data has better information
		if type(value) == "table" then
			-- Only update name if the new name is better
			if value.Name and value.Name ~= "Unknown" and (not existing.Name or existing.Name == "Unknown") then
				existing.Name = value.Name
				Database.State.isDirty = true
			end

			-- Only update proof if the new proof is better
			local newProof = value.proof or value.cause
			if newProof and newProof ~= "Unknown" and (not existing.proof or existing.proof == "Unknown") then
				existing.proof = newProof
				Database.State.isDirty = true
			end
		end
	end

	-- Auto-save if enabled and enough time has passed
	if Database.Config.AutoSave and Database.State.isDirty then
		local currentTime = os.time()
		if currentTime - Database.State.lastSave >= Database.Config.SaveInterval then
			Database.SaveDatabase()
		end
	end
end

-- Find best path for database storage
function Database.GetFilePath()
	local possibleFolders = {
		"Lua Cheater_Detection",
		"Lua Scripts/Cheater_Detection",
		"lbox/Cheater_Detection",
		"lmaobox/Cheater_Detection",
		".",
	}

	-- Try to find existing folder first
	for _, folder in ipairs(possibleFolders) do
		if pcall(function()
			return filesystem.GetFileSize(folder)
		end) then
			return folder .. "/database.json"
		end
	end

	-- Try to create folders
	for _, folder in ipairs(possibleFolders) do
		if pcall(filesystem.CreateDirectory, folder) then
			return folder .. "/database.json"
		end
	end

	-- Last resort
	return "./database.json"
end

-- Save database to disk with optimized line-by-line writing to prevent overflow
function Database.SaveDatabase()
	-- Ensure the database is initialized first
	Database.EnsureInitialized()

	-- Create a save task to run in coroutine
	local saveTask = coroutine.create(function()
		local filePath = Database.GetFilePath()
		local tempPath = filePath .. ".tmp"
		local backupPath = filePath .. ".bak"

		-- Let UI know we're starting
		if G and G.UI and G.UI.ShowMessage then
			G.UI.ShowMessage("Saving database...")
		end

		-- Skip saving if no entries or not dirty
		if Database.State.entriesCount == 0 then
			print("[Database] No entries to save")
			return true
		end

		if not Database.State.isDirty then
			print("[Database] Database is not dirty, skipping save")
			return true
		end

		-- Stage 1: Create a temporary file
		local tempFile = io.open(tempPath, "w")
		if not tempFile then
			print("[Database] Failed to create temporary file: " .. tempPath)
			return false
		end

		-- Write opening JSON bracket without using Json.encode
		tempFile:write("{\n")

		-- Stage 2: Convert entries to direct strings and write in batches
		-- This avoids creating tables that the JSON encoder would need to process
		local steamIDs = {}
		for steamID in pairs(Database.data) do
			table.insert(steamIDs, steamID)
		end

		local totalEntries = #steamIDs
		local batchSize = 200 -- Smaller batches to avoid memory issues
		local batches = math.ceil(totalEntries / batchSize)

		for batchIndex = 1, batches do
			local startIdx = (batchIndex - 1) * batchSize + 1
			local endIdx = math.min(batchIndex * batchSize, totalEntries)

			-- Update progress
			local progress = math.floor((batchIndex - 1) / batches * 100)
			if G and G.UI and G.UI.UpdateProgress then
				G.UI.UpdateProgress(progress, "Saving database... " .. progress .. "%")
			end

			-- Allow UI to update
			coroutine.yield()

			-- Process this batch directly as strings
			for i = startIdx, endIdx do
				local steamID = steamIDs[i]
				local entry = Database.data[steamID]

				if entry and type(entry) == "table" then
					-- Sanitize strings for JSON safety
					local name = entry.Name or "Unknown"
					local proof = entry.proof or "Unknown"

					-- Escape quotes and control characters
					name = name:gsub('"', '\\"'):gsub("[\r\n\t]", " ")
					proof = proof:gsub('"', '\\"'):gsub("[\r\n\t]", " ")

					-- Build JSON entry manually without encoder
					local jsonEntry = string.format('"%s":{"Name":"%s","proof":"%s"}', steamID, name, proof)

					-- Add comma for all except the last entry
					if i < totalEntries then
						jsonEntry = jsonEntry .. ",\n"
					else
						jsonEntry = jsonEntry .. "\n"
					end

					-- Write directly to file without table operations
					tempFile:write(jsonEntry)
				end
			end

			-- Force flush the batch to disk
			tempFile:flush()

			-- Clear memory after each batch
			steamIDs[batchIndex] = nil -- Allow previous batch to be GC'd
			collectgarbage("step", 200)
		end

		-- Write closing JSON bracket
		tempFile:write("}")
		tempFile:close()

		-- Stage 3: Safely replace the original file
		-- First create a backup if the original file exists
		local success, backupErr = pcall(function()
			local existingFile = io.open(filePath, "r")
			if existingFile then
				local content = existingFile:read("*a")
				existingFile:close()

				if content and #content > 0 then
					local backupFile = io.open(backupPath, "w")
					if backupFile then
						backupFile:write(content)
						backupFile:close()
					end
				end
			end
		end)

		if not success then
			print("[Database] Warning: Could not create backup: " .. tostring(backupErr))
		end

		-- Replace file using atomic operation when possible
		local replaceSuccess = os.rename(tempPath, filePath)

		-- If rename failed, try copy and delete approach
		if not replaceSuccess then
			-- Read temp file
			local tempContent = nil
			local tempReader = io.open(tempPath, "r")
			if tempReader then
				tempContent = tempReader:read("*a")
				tempReader:close()

				-- Write to actual file
				if tempContent then
					local actualWriter = io.open(filePath, "w")
					if actualWriter then
						actualWriter:write(tempContent)
						actualWriter:close()
						replaceSuccess = true

						-- Clean up temp file
						os.remove(tempPath)
					end
				end
			end
		end

		-- Update state
		Database.State.isDirty = false
		Database.State.lastSave = os.time()

		if G and G.UI and G.UI.ShowMessage then
			G.UI.ShowMessage("Database saved with " .. Database.State.entriesCount .. " entries!")
		end

		if Database.Config.DebugMode then
			print(string.format("[Database] Saved %d entries to %s", Database.State.entriesCount, filePath))
		end

		-- Clean up memory before returning
		steamIDs = nil
		collectgarbage("collect")

		return replaceSuccess
	end)

	-- Run the save coroutine
	local saveCallback = function()
		-- Only proceed if the coroutine is alive
		if coroutine.status(saveTask) ~= "dead" then
			local success, result = pcall(coroutine.resume, saveTask)

			if not success then
				-- Error occurred
				print("[Database] Save error: " .. tostring(result))
				callbacks.Unregister("Draw", "DatabaseSave")

				-- Try fallback save method
				Database.FallbackSave()
			end
		else
			-- Save completed
			callbacks.Unregister("Draw", "DatabaseSave")
		end
	end

	-- Register the callback to run on Draw
	callbacks.Register("Draw", "DatabaseSave", saveCallback)
	return true
end

-- Fallback save method with chunking to avoid memory issues
function Database.FallbackSave()
	print("[Database] Using fallback save method")

	-- Create a fallback task to run in coroutine
	local fallbackTask = coroutine.create(function()
		local filePath = Database.GetFilePath()

		-- Attempt to save in direct chunks without using Json.encode
		local file = io.open(filePath, "w")
		if not file then
			print("[Database] Fallback: Failed to open file for writing")
			return false
		end

		-- Build JSON manually in chunks
		file:write("{\n")

		-- Count entries first to know when to add comma
		local totalEntries = 0
		for _ in pairs(Database.data) do
			totalEntries = totalEntries + 1
		end

		-- Process entries in smaller batches
		local entriesProcessed = 0
		local batchSize = 100 -- Smaller batch for fallback mode

		-- Get all keys
		local keys = {}
		for steamID in pairs(Database.data) do
			table.insert(keys, steamID)
		end

		-- Process in batches
		for i = 1, #keys, batchSize do
			local endIdx = math.min(i + batchSize - 1, #keys)

			-- Process this batch
			for j = i, endIdx do
				local steamID = keys[j]
				local entry = Database.data[steamID]

				entriesProcessed = entriesProcessed + 1

				-- Basic string escaping for safety
				local name = (entry.Name or "Unknown"):gsub('"', '\\"')
				local proof = (entry.proof or "Unknown"):gsub('"', '\\"')

				-- Format as JSON directly
				local line = string.format(
					'"%s":{"Name":"%s","proof":"%s"}%s\n',
					steamID,
					name,
					proof,
					entriesProcessed < totalEntries and "," or ""
				)

				file:write(line)
			end

			-- Yield to let UI update
			coroutine.yield()
		end

		file:write("}")
		file:close()

		-- Update state
		Database.State.isDirty = false
		Database.State.lastSave = os.time()

		-- Clean up memory
		keys = nil
		collectgarbage("collect")

		print("[Database] Fallback save completed successfully")
		return true
	end)

	-- Process the fallback task with error handling
	callbacks.Register("Draw", "DatabaseFallbackSave", function()
		if coroutine.status(fallbackTask) ~= "dead" then
			local success, result = pcall(coroutine.resume, fallbackTask)

			if not success then
				print("[Database] Fallback save error: " .. tostring(result))
				callbacks.Unregister("Draw", "DatabaseFallbackSave")
			end
		else
			callbacks.Unregister("Draw", "DatabaseFallbackSave")
		end
	end)

	return true
end

-- Enhanced load function that doesn't reset the database if it already exists
function Database.LoadDatabaseSafe(silent)
	-- If database is already loaded and has entries, don't reload completely
	if Database.State.entriesCount > 0 then
		if not silent then
			printc(
				100,
				150,
				255,
				255,
				"[Database] Using existing database with " .. Database.State.entriesCount .. " entries"
			)
		end
		return true
	end

	-- Otherwise, perform normal load
	return Database.LoadDatabase(silent)
end

-- Load database from disk
function Database.LoadDatabase(silent)
	local filePath = Database.GetFilePath()

	-- Try to open file
	local file = io.open(filePath, "r")
	if not file then
		if not silent then
			print("[Database] Database file not found: " .. filePath)
		end
		return false
	end

	-- Read and parse content
	local content = file:read("*a")
	file:close()

	local success, data = pcall(Json.decode, content)
	if not success or type(data) ~= "table" then
		if not silent then
			print("[Database] Failed to decode database file")
		end
		return false
	end

	-- Reset and load data
	Database.data = {}
	Database.State.entriesCount = 0

	-- Copy data with minimal structure - enforce entry limit
	local entriesAdded = 0
	for steamID, value in pairs(data) do
		if entriesAdded < Database.Config.MaxEntries then
			Database.data[steamID] = {
				Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
				proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown",
			}
			Database.State.entriesCount = Database.State.entriesCount + 1
			entriesAdded = entriesAdded + 1
		else
			break
		end
	end

	-- Clean up memory
	collectgarbage("collect")

	-- Update state
	Database.State.isDirty = false
	Database.State.lastSave = os.time()

	if not silent then
		printc(
			0,
			255,
			140,
			255,
			"[" .. os.date("%H:%M:%S") .. "] Loaded Database with " .. Database.State.entriesCount .. " entries"
		)
	end

	return true
end

-- Get a player record
function Database.GetRecord(steamId)
	return Database.content[steamId]
end

-- Get proof for a player
function Database.GetProof(steamId)
	local record = Database.content[steamId]
	return record and record.proof or "Unknown"
end

-- Get name for a player
function Database.GetName(steamId)
	local record = Database.content[steamId]
	return record and record.Name or "Unknown"
end

-- Check if player is in database
function Database.Contains(steamId)
	return Database.data[steamId] ~= nil
end

-- Set a player as suspect
function Database.SetSuspect(steamId, data)
	if not steamId then
		return
	end

	-- Create minimal data structure
	local minimalData = {
		Name = (data and data.Name) or "Unknown",
		proof = (data and (data.proof or data.cause)) or "Unknown",
	}

	-- Store data
	Database.content[steamId] = minimalData

	-- Also set priority in playerlist
	playerlist.SetPriority(steamId, 10)
end

-- Clear a player from suspect list
function Database.ClearSuspect(steamId)
	if Database.content[steamId] then
		Database.content[steamId] = nil
		playerlist.SetPriority(steamId, 0)
	end
end

-- Get database stats
function Database.GetStats()
	-- Count entries by proof type
	local proofStats = {}
	for steamID, entry in pairs(Database.data) do
		local proof = entry.proof or "Unknown"
		proofStats[proof] = (proofStats[proof] or 0) + 1
	end

	return {
		entryCount = Database.State.entriesCount,
		isDirty = Database.State.isDirty,
		lastSave = Database.State.lastSave,
		memoryMB = collectgarbage("count") / 1024,
		proofTypes = proofStats,
	}
end

-- Validate database entries against source without complete reload
function Database.ValidateDatabase(source, sourceName, sourceCause)
	if not source then
		return 0
	end

	-- Initialize counters
	local added = 0
	local skipped = 0
	local existing = 0
	local totalProcessed = 0

	-- Track start time
	local startTime = os.time()

	-- Check if we have an existing database
	if Database.State.entriesCount > 0 then
		print("[Database] Validating against existing database with " .. Database.State.entriesCount .. " entries")
	else
		print("[Database] No existing database, will create new entries")
	end

	-- Define a processing function that works with strings only
	local function processValue(steamId, data)
		-- Skip invalid IDs
		if not steamId or #steamId < 15 or not steamId:match("^%d+$") then
			skipped = skipped + 1
			return
		end

		-- Check if entry already exists
		if Database.data[steamId] then
			existing = existing + 1

			-- Only update if the new data has better information and we're not in validate-only mode
			if type(data) == "table" and not Database.Config.ValidateOnly then
				local existingEntry = Database.data[steamId]

				-- Update name if better
				if
					data.Name
					and data.Name ~= "Unknown"
					and (not existingEntry.Name or existingEntry.Name == "Unknown")
				then
					existingEntry.Name = data.Name
					Database.State.isDirty = true
				end

				-- Update proof if better
				local newProof = data.proof or data.cause or sourceCause
				if
					newProof
					and newProof ~= "Unknown"
					and (not existingEntry.proof or existingEntry.proof == "Unknown")
				then
					existingEntry.proof = newProof
					Database.State.isDirty = true
				end
			end
		else
			-- Only add if we're not in validate-only mode
			if not Database.Config.ValidateOnly then
				-- Add new entry with minimal data
				Database.data[steamId] = {
					Name = (type(data) == "table" and data.Name) or "Unknown",
					proof = (type(data) == "table" and (data.proof or data.cause)) or sourceCause or "Unknown",
				}

				-- Set priority in player list with error handling
				pcall(function()
					playerlist.SetPriority(steamId, 10)
				end)

				Database.State.entriesCount = Database.State.entriesCount + 1
				Database.State.isDirty = true
				added = added + 1
			else
				skipped = skipped + 1
			end
		end

		-- Track progress
		totalProcessed = totalProcessed + 1

		-- Periodically yield and update UI for large data sets
		if totalProcessed % 1000 == 0 and G and G.UI and G.UI.UpdateProgress then
			G.UI.UpdateProgress(nil, "Validated " .. totalProcessed .. " entries...")
			coroutine.yield()
		end
	end

	-- If source is a table, process entries
	if type(source) == "table" then
		-- Process in batches to prevent memory issues
		local keys = {}
		local batchCount = 0

		-- Collect keys first (for tables with many entries)
		for steamId in pairs(source) do
			table.insert(keys, steamId)

			-- Process in batches
			if #keys >= Database.Config.BatchSize then
				-- Process this batch
				for _, key in ipairs(keys) do
					processValue(key, source[key])
				end

				-- Clear batch and force GC
				keys = {}
				collectgarbage("step", 100)
				coroutine.yield()
				batchCount = batchCount + 1

				-- Update progress
				if G and G.UI and G.UI.UpdateProgress then
					G.UI.UpdateProgress(nil, "Validated batch " .. batchCount .. "...")
				end
			end
		end

		-- Process remaining keys
		for _, key in ipairs(keys) do
			processValue(key, source[key])
		end
	end

	-- Update validation statistics
	Database.ValidationStats.entriesExisting = Database.ValidationStats.entriesExisting + existing
	Database.ValidationStats.entriesAdded = Database.ValidationStats.entriesAdded + added
	Database.ValidationStats.entriesSkipped = Database.ValidationStats.entriesSkipped + skipped
	Database.ValidationStats.lastValidation = startTime

	-- Log result
	print(
		string.format(
			"[Database] Validation complete for %s: %d added, %d existing, %d skipped",
			sourceName or "source",
			added,
			existing,
			skipped
		)
	)

	-- Auto-save if we've made changes
	if Database.State.isDirty and added > 0 and Database.Config.AutoSave then
		print("[Database] Changes detected, scheduling save...")
		-- Schedule save for next frame to prevent stack overflow
		callbacks.Register("Draw", "DatabaseValidationSave", function()
			callbacks.Unregister("Draw", "DatabaseValidationSave")
			Database.SaveDatabase()
		end)
	end

	-- Return added count for compatibility with existing fetch functions
	return added
end

-- Add utility functions to trigger validation with proper progress updates and coroutine pacing
function Database.ValidateWithSources(silent)
	if not Database_Fetcher then
		if not silent then
			print("[Database] Error: Database_Fetcher module not found")
		end
		return false
	end

	-- Reset validation statistics
	Database.ValidationStats.entriesExisting = 0
	Database.ValidationStats.entriesAdded = 0
	Database.ValidationStats.entriesSkipped = 0
	Database.ValidationStats.lastValidation = os.time()

	-- Get active sources with fallback
	local sources = Database_Fetcher.Sources
	if not sources then
		if not silent then
			print("[Database] Error: No sources found")
		end
		return false
	end

	-- Enable validation mode
	local prevValidateOnly = Database.Config.ValidateOnly
	Database.Config.ValidateOnly = false -- We want to add missing entries

	-- Initialize UI with Tasks system
	local Tasks = Database_Fetcher.Tasks
	local hasTasks = false

	pcall(function()
		if Tasks then
			Tasks.Reset()
			Tasks.Init(#sources)
			Tasks.message = "Validating Database"
			Tasks.Config.SimplifiedUI = true
			Tasks.isRunning = true
			hasTasks = true

			-- Make sure we have a Draw hook for Tasks.UpdateProgress
			callbacks.Register("Draw", "TasksUpdateProgress", Tasks.UpdateProgress)
		end
	end)

	-- Create a coroutine to process sources one by one with fixed 2-second delays
	local validationTask = coroutine.create(function()
		local totalAdded = 0
		local totalSources = #sources

		for i, source in ipairs(sources) do
			if source and source.url and source.cause then
				-- Update progress display if we have Tasks
				if hasTasks then
					Tasks.StartSource(source.name)
					Tasks.targetProgress = ((i - 1) / totalSources) * 100
					Tasks.message = "Validating: " .. source.name
				end

				-- Add a fixed 2-second delay between sources to prevent overloading
				if i > 1 then
					local delayTime = 2.0 -- Fixed 2-second delay

					-- Use countdown for better UI feedback
					local startTime = globals.RealTime()
					while globals.RealTime() < startTime + delayTime do
						local remaining = math.ceil((startTime + delayTime) - globals.RealTime())
						if hasTasks then
							Tasks.message = string.format("Rate limit: %ds before next request...", remaining)
						end
						coroutine.yield() -- Keep yielding to maintain smooth gameplay
					end
				end

				-- Get content from source
				if Database_Fetcher.ProcessSourceInBatches then
					-- Use the batch processor with built-in coroutine support
					local content = Database_Fetcher.ProcessSourceInBatches(source, Database)
					totalAdded = totalAdded + (tonumber(content) or 0)
				else
					-- Fall back to direct processing with improved coroutine handling
					local content = {}
					local success, rawContent = false, nil

					-- Download in a non-blocking way
					local dlTask = coroutine.create(function()
						if hasTasks then
							Tasks.message = "Downloading from " .. source.name
						end
						return pcall(function()
							return http.Get(source.url)
						end)
					end)

					-- Run the download task with yielding
					while coroutine.status(dlTask) ~= "dead" do
						local dlSuccess, dlResult, dlContent = coroutine.resume(dlTask)

						if dlSuccess then
							success = dlResult
							rawContent = dlContent
						end

						coroutine.yield() -- Keep game responsive
					end

					if success and rawContent and #rawContent > 0 then
						local added = Database.ValidateDatabase(content, source.name, source.cause)
						totalAdded = totalAdded + added
					end
				end

				-- Mark task complete if we have Tasks
				if hasTasks then
					Tasks.SourceDone()
				end

				-- Force a yield even if not needed, to maintain responsiveness
				coroutine.yield()
			end
		end

		-- Restore validation mode
		Database.Config.ValidateOnly = prevValidateOnly

		-- Show completion if we have Tasks
		if hasTasks then
			Tasks.targetProgress = 100
			Tasks.status = "complete"
			Tasks.message = "Validation Complete"
			Tasks.completedTime = globals.RealTime()
		end

		if not silent then
			printc(
				0,
				255,
				0,
				255,
				string.format(
					"[Database] Validation complete: %d added, %d existing, %d skipped",
					Database.ValidationStats.entriesAdded,
					Database.ValidationStats.entriesExisting,
					Database.ValidationStats.entriesSkipped
				)
			)
		end

		-- Save if needed
		if Database.State.isDirty and Database.ValidationStats.entriesAdded > 0 then
			Database.SaveDatabase()
		end

		return totalAdded
	end)

	-- Register the validation task
	callbacks.Register("Draw", "DatabaseValidationTask", function()
		if coroutine.status(validationTask) ~= "dead" then
			local success, result = pcall(coroutine.resume, validationTask)
			if not success then
				print("[Database] Validation error: " .. tostring(result))
				callbacks.Unregister("Draw", "DatabaseValidationTask")
				Database.Config.ValidateOnly = prevValidateOnly
			end
		else
			callbacks.Unregister("Draw", "DatabaseValidationTask")
			Database.Config.ValidateOnly = prevValidateOnly
		end
	end)

	return true
end

-- Import function for database updating
function Database.ImportDatabase()
	-- Ensure database is properly initialized
	Database.EnsureInitialized()

	-- Simple import from Database_import module
	local beforeCount = Database.State.entriesCount

	-- Import additional data
	Database_import.importDatabase(Database)

	-- Count entries after import
	local afterCount = Database.State.entriesCount

	-- Show a summary of the import
	local newEntries = afterCount - beforeCount
	if newEntries > 0 then
		printc(255, 255, 0, 255, string.format("[Database] Imported %d new entries from external sources", newEntries))

		-- Save the updated database
		if Database.SaveDatabase() then
			printc(100, 255, 100, 255, string.format("[Database] Saved database with %d total entries", afterCount))
		end
	end

	return newEntries
end

-- Add utility functions to trigger fetching
function Database.FetchUpdates(silent)
	-- Ensure database is properly initialized
	Database.EnsureInitialized()

	if Database_Fetcher then
		return Database_Fetcher.FetchAll(Database, function(totalAdded)
			if totalAdded and totalAdded > 0 then
				Database.SaveDatabase()
				if not silent then
					printc(0, 255, 0, 255, "[Database] Updated with " .. totalAdded .. " new entries")
				end
			elseif not silent then
				print("[Database] No new entries were added")
			end
		end, silent)
	else
		if not silent then
			print("[Database] Error: Database_Fetcher module not found")
		end
		return false
	end
end

-- Auto update function that can be called from anywhere
function Database.AutoUpdate()
	return Database.FetchUpdates(true)
end

-- Clean database by removing least important entries
function Database.Cleanup(maxEntries)
	maxEntries = maxEntries or Database.Config.MaxEntries

	-- If we're under the limit, no need to clean
	if Database.State.entriesCount <= maxEntries then
		return 0
	end

	-- Create a priority list for entries to keep
	local priorities = {
		-- Highest priority to keep (exact string matching)
		"RGL",
		"Bot",
		"Pazer List",
		"Community",
		-- Lower priority categories
		"Cheater",
		"Tacobot",
		"MCDB",
		"Suspicious",
		"Watched",
	}

	-- Count entries to remove
	local toRemove = Database.State.entriesCount - maxEntries
	local removed = 0

	-- Remove entries not in priority list first
	if toRemove > 0 then
		local nonPriorityEntries = {}

		for steamId, data in pairs(Database.data) do
			-- Check if this entry is a priority
			local isPriority = false
			local proof = (data.proof or ""):lower()

			for _, priority in ipairs(priorities) do
				if proof:find(priority:lower()) then
					isPriority = true
					break
				end
			end

			if not isPriority then
				table.insert(nonPriorityEntries, steamId)
				if #nonPriorityEntries >= toRemove then
					break
				end
			end
		end

		-- Remove the non-priority entries
		for _, steamId in ipairs(nonPriorityEntries) do
			Database.content[steamId] = nil
			removed = removed + 1
		end
	end

	-- If we still need to remove more, start removing lowest priority entries
	if removed < toRemove then
		-- Process in reverse priority order
		for i = #priorities, 1, -1 do
			local priority = priorities[i]:lower()

			for steamId, data in pairs(Database.data) do
				local proof = (data.proof or ""):lower()

				if proof:find(priority) then
					Database.content[steamId] = nil
					removed = removed + 1

					if removed >= toRemove then
						break
					end
				end
			end

			if removed >= toRemove then
				break
			end
		end
	end

	-- Save the cleaned database
	if removed > 0 and Database.State.isDirty then
		Database.SaveDatabase()
	end

	return removed
end

-- Register database commands
local function RegisterCommands()
	local Commands = Common.Lib.Utils.Commands

	-- Database stats command
	Commands.Register("cd_db_stats", function()
		local stats = Database.GetStats()
		print(string.format("[Database] Total entries: %d", stats.entryCount))
		print(string.format("[Database] Memory usage: %.2f MB", stats.memoryMB))

		-- Show proof type breakdown
		print("[Database] Proof type breakdown:")
		for proofType, count in pairs(stats.proofTypes) do
			if count > 10 then -- Only show categories with more than 10 entries
				print(string.format("  - %s: %d", proofType, count))
			end
		end
	end, "Show database statistics")

	-- Database cleanup command
	Commands.Register("cd_db_cleanup", function(args)
		local limit = tonumber(args[1]) or Database.Config.MaxEntries
		local beforeCount = Database.State.entriesCount
		local removed = Database.Cleanup(limit)

		print(
			string.format(
				"[Database] Cleaned %d entries (from %d to %d)",
				removed,
				beforeCount,
				Database.State.entriesCount
			)
		)
	end, "Clean the database to stay under entry limit")
end

-- Auto-save on unload
local function OnUnload()
	if Database.State.isDirty then
		Database.SaveDatabase()
	end
end

-- Initialize the database
local function InitializeDatabase()
	-- Ensure database structure is properly initialized
	Database.EnsureInitialized()

	-- Try to restore the database first
	if Restore.RestoreDatabase(Database) then
		-- Successfully restored, skip loading from file
		print("[Database] Successfully restored database from memory")

		-- Clean up if over limit
		if Database.State.entriesCount > Database.Config.MaxEntries then
			local removed = Database.Cleanup()
			if removed > 0 and Database.Config.DebugMode then
				print(string.format("[Database] Cleaned %d entries to stay under limit", removed))
			end
		end

		return true
	end

	-- Otherwise, continue with normal database loading
	Database.LoadDatabase()
	Database.State.isDirty = true
	-- Import additional data
	Database.ImportDatabase()

	-- Clean up if over limit
	if Database.State.entriesCount > Database.Config.MaxEntries then
		local removed = Database.Cleanup()
		if removed > 0 and Database.Config.DebugMode then
			print(string.format("[Database] Cleaned %d entries to stay under limit", removed))
		end
	end

	-- Check if Database_Fetcher is available and has auto-fetch enabled
	pcall(function()
		if Database_Fetcher and Database_Fetcher.Config and Database_Fetcher.Config.AutoFetchOnLoad then
			Database_Fetcher.AutoFetch(Database)
		end
	end)
end

-- Make sure structures exist
function Database.EnsureInitialized()
	-- Create data table if needed
	Database.data = Database.data or {}

	-- Create state tracking
	Database.State = Database.State or {
		entriesCount = 0,
		isDirty = false,
		lastSave = 0,
	}

	-- Create content accessor
	if not Database.content then
		Database.content = setmetatable({}, {
			__index = function(_, key)
				return Database.data[key]
			end,
			__newindex = function(_, key, value)
				Database.HandleSetEntry(key, value)
			end,
			__pairs = function()
				return pairs(Database.data)
			end,
		})
	end

	return true
end

-- Simplified update function that just adds new entries
function Database.DirectUpdate(source, sourceName, sourceCause)
	if type(source) ~= "table" then
		return 0
	end

	local added = 0
	for steamId, data in pairs(source) do
		-- Only process valid Steam IDs
		if type(steamId) == "string" and #steamId >= 15 and steamId:match("^%d+$") then
			-- Add if doesn't exist
			if not Database.data[steamId] then
				Database.data[steamId] = {
					Name = (type(data) == "table" and data.Name) or "Unknown",
					proof = (type(data) == "table" and (data.proof or data.cause)) or sourceCause or "Unknown",
				}

				-- Update state
				Database.State.entriesCount = Database.State.entriesCount + 1
				Database.State.isDirty = true

				-- Set priority
				pcall(function()
					playerlist.SetPriority(steamId, 10)
				end)

				added = added + 1
			end
		end

		-- Yield periodically to avoid freezing
		if added % 500 == 0 then
			coroutine.yield()
		end
	end

	return added
end

-- Save database with simpler approach
function Database.QuickSave()
	-- Create a save task in a coroutine
	local saveTask = coroutine.create(function()
		-- Open file
		local filePath = Database.GetFilePath()
		local file = io.open(filePath, "w")
		if not file then
			print("[Database] Failed to open file for writing: " .. filePath)
			return false
		end

		-- Write opening bracket
		file:write("{\n")

		-- Get all IDs
		local ids = {}
		for id in pairs(Database.data) do
			table.insert(ids, id)
		end

		-- Write each entry
		local totalEntries = #ids
		for i, id in ipairs(ids) do
			local entry = Database.data[id]

			-- Get and sanitize data
			local name = entry.Name or "Unknown"
			local proof = entry.proof or "Unknown"
			name = name:gsub('"', '\\"'):gsub("[\r\n\t]", " ")
			proof = proof:gsub('"', '\\"'):gsub("[\r\n\t]", " ")

			-- Write JSON entry
			local line = string.format('"%s":{"Name":"%s","proof":"%s"}', id, name, proof)
			if i < totalEntries then
				line = line .. ","
			end
			line = line .. "\n"
			file:write(line)

			-- Yield periodically
			if i % 200 == 0 then
				coroutine.yield()
			end
		end

		-- Write closing bracket
		file:write("}")
		file:close()

		-- Update state
		Database.State.isDirty = false
		Database.State.lastSave = os.time()

		print("[Database] Saved " .. totalEntries .. " entries to " .. filePath)
		return true
	end)

	-- Run the save coroutine
	callbacks.Register("Draw", "DatabaseQuickSave", function()
		if coroutine.status(saveTask) ~= "dead" then
			local success, result = pcall(coroutine.resume, saveTask)
			if not success then
				print("[Database] Save error: " .. tostring(result))
				callbacks.Unregister("Draw", "DatabaseQuickSave")
			end
		else
			callbacks.Unregister("Draw", "DatabaseQuickSave")
		end
	end)

	return true
end

-- Replace existing functions with simplified versions
Database.SaveDatabase = Database.QuickSave
Database.ValidateDatabase = Database.DirectUpdate

InitializeDatabase() -- Initialize the database when this module is loaded
RegisterCommands() -- Register commands
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload) -- Register unload callback

return Database
