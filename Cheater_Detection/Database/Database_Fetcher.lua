--[[
    Database_Fetcher.lua - Fixed version
    Fetches cheater databases from online sources with fixed 2-second delays
    Uses coroutines for background processing to keep the game responsive
]]

-- Import required modules
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands

-- Get JSON from Common
local Json = Common.Json
if not Json then
	print("[Database Fetcher] Warning: JSON library not available in Common")
end

-- Load components directly without error handling
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")
local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")
local Parsers = require("Cheater_Detection.Database.Database_Fetcher.Parsers")

-- Create minimal Parsers interface if needed functions don't exist
if not Parsers.Download or not Parsers.ProcessRawList or not Parsers.ProcessTF2DB then
	print("[Database Fetcher] Creating minimal Parsers interface")

	-- Simple Download function
	if not Parsers.Download then
		Parsers.Download = function(url)
			print("[Minimal Parsers] Downloading: " .. url)
			local content = http.Get(url)
			if content and #content > 0 then
				print("[Minimal Parsers] Downloaded " .. #content .. " bytes")
			else
				print("[Minimal Parsers] Download failed or empty response")
			end
			return content
		end
	end

	-- Simple raw list processor
	if not Parsers.ProcessRawList then
		Parsers.ProcessRawList = function(content, database, sourceName, sourceCause)
			print("[Minimal Parsers] Processing raw list: " .. sourceName)

			if not content or not database then
				print("[Minimal Parsers] Missing content or database")
				return 0
			end

			-- Make sure database has required fields
			if not database.content then
				database.content = {}
			end
			if not database.State then
				database.State = { isDirty = false, entriesCount = 0 }
			end

			local count = 0
			-- Process line by line
			for line in content:gmatch("[^\r\n]+") do
				line = line:match("^%s*(.-)%s*$") -- Trim whitespace

				if line ~= "" and not line:match("^%-%-") and not line:match("^#") and not line:match("^//") then
					if line:match("^%d+$") and #line >= 15 and #line <= 20 then
						if not database.content[line] then
							database.content[line] = {
								Name = "Unknown",
								proof = sourceCause,
							}
							count = count + 1
							database.State.isDirty = true
							database.State.entriesCount = (database.State.entriesCount or 0) + 1

							pcall(function()
								playerlist.SetPriority(line, 10)
							end)
						end
					end
				end

				if count % 500 == 0 then
					coroutine.yield()
				end
			end

			print("[Minimal Parsers] Added " .. count .. " entries from " .. sourceName)
			return count
		end
	end

	-- Simple TF2DB processor
	if not Parsers.ProcessTF2DB then
		Parsers.ProcessTF2DB = function(content, database, source)
			print("[Minimal Parsers] Processing TF2DB: " .. source.name)

			if not content or not database then
				print("[Minimal Parsers] Missing content or database")
				return 0
			end

			-- Make sure database has required fields
			if not database.content then
				database.content = {}
			end
			if not database.State then
				database.State = { isDirty = false, entriesCount = 0 }
			end

			local count = 0
			-- Process with safer pattern matching
			for steamId in content:gmatch('"steamid"%s*:%s*"([^"]+)"') do
				local steamID64 = steamId

				-- Only convert non-SteamID64 formats
				if not (steamId:match("^%d+$") and #steamId >= 15) then
					pcall(function()
						steamID64 = steam.ToSteamID64(steamId)
					end)
				end

				-- Only process if we have a valid SteamID64
				if type(steamID64) == "string" and steamID64:match("^%d+$") and #steamID64 >= 15 then
					if not database.content[steamID64] then
						database.content[steamID64] = {
							Name = "Unknown",
							proof = source.cause,
						}

						pcall(function()
							playerlist.SetPriority(steamID64, 10)
						end)

						count = count + 1
						database.State.isDirty = true
						database.State.entriesCount = (database.State.entriesCount or 0) + 1
					end
				end

				if count % 500 == 0 then
					coroutine.yield()
				end
			end

			print("[Minimal Parsers] Added " .. count .. " entries from " .. source.name)
			return count
		end
	end
end

-- Create fetcher object with configuration
local Fetcher = {
	Config = {
		-- Basic settings
		AutoFetchOnLoad = false,
		AutoSaveAfterFetch = true,
		NotifyOnFetchComplete = true,
		ShowProgressBar = true,
		ForceInitialDelay = true,

		-- Anti-ban protection settings
		MinSourceDelay = 2, -- Fixed 2 second delay
		MaxSourceDelay = 2,
		RequestTimeout = 15,
		EnableRandomDelay = false,

		-- UI settings
		SmoothingFactor = 0.05,

		-- Auto-fetch settings
		AutoFetchInterval = 0,
		LastAutoFetch = 0,

		-- Debug settings
		DebugMode = false,

		-- Memory management settings
		MaxMemoryMB = 100,
		ForceGCThreshold = 50,
		UseWeakTables = true,
		StringBuffering = true,
	},
}

-- Export components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List
Fetcher.Json = Json

-- Use weak tables for UI tracking
Fetcher.UI = setmetatable({
	targetProgress = 0,
	currentProgress = 0,
	completedSources = 0,
	totalSources = 0,
}, { __mode = "v" })

-- Any temporary storage should use weak tables
Fetcher.TempStorage = setmetatable({}, { __mode = "kv" })

-- Memory management functions
Fetcher.Memory = {
	-- Check and manage memory usage
	Check = function()
		local memoryUsageMB = collectgarbage("count") / 1024
		local maxAllowed = Fetcher.Config.MaxMemoryMB
		local forceThreshold = maxAllowed * (Fetcher.Config.ForceGCThreshold / 100)

		-- If over threshold, force cleanup
		if memoryUsageMB > forceThreshold then
			collectgarbage("collect")

			if Fetcher.Config.DebugMode then
				print(
					string.format(
						"[Memory] Forced cleanup: %.2f MB -> %.2f MB",
						memoryUsageMB,
						collectgarbage("count") / 1024
					)
				)
			end
		end

		return memoryUsageMB
	end,

	-- Force full cleanup
	ForceCleanup = function()
		local before = collectgarbage("count") / 1024
		collectgarbage("collect")
		collectgarbage("collect")

		if Fetcher.Config.DebugMode then
			local after = collectgarbage("count") / 1024
			print(
				string.format(
					"[Memory] Full cleanup: %.2f MB -> %.2f MB (saved %.2f MB)",
					before,
					after,
					before - after
				)
			)
		end
	end,

	-- Emergency cleanup function
	EmergencyCleanup = function()
		-- Force immediate garbage collection
		collectgarbage("collect")
		collectgarbage("collect")

		-- Reset any in-progress tasks
		Tasks.Reset()

		-- Clear all temporary tables
		Fetcher.TempStorage = {}
		Fetcher.UI = setmetatable({
			targetProgress = 0,
			currentProgress = 0,
			completedSources = 0,
			totalSources = 0,
		}, { __mode = "v" })

		-- Clear any registered callbacks
		pcall(function()
			callbacks.Unregister("Draw", "FetcherMainTask")
			callbacks.Unregister("Draw", "FetcherCleanup")
			callbacks.Unregister("Draw", "FetcherSingleSource")
			callbacks.Unregister("Draw", "FetcherSingleSourceCleanup")
			callbacks.Unregister("Draw", "FetcherCallback")
			callbacks.Unregister("Draw", "DatabaseSaveDelay")
		end)

		print("[Database Fetcher] Emergency cleanup performed")
	end,
}

-- Always return exactly 2 seconds delay
function Fetcher.GetSourceDelay()
	return Fetcher.Config.MinSourceDelay
end

-- Improved batch processing with enhanced coroutine support
function Fetcher.ProcessSourceInBatches(source, database)
	if not source or not source.url or not database then
		return 0, "Invalid source configuration"
	end

	-- Set up tracking variables
	local addedCount = 0
	local sourceUrl = source.url
	local sourceName = source.name
	local errorMessage = nil

	-- Check memory before download
	Fetcher.Memory.Check()

	-- Step 1: Download the content without blocking main thread
	Tasks.message = "Downloading from " .. sourceName .. "..."

	-- Create a dedicated coroutine for downloading
	local downloadCoroutine = coroutine.create(function()
		local sourceRawData = Parsers.Download(sourceUrl)

		-- If download failed, try a backup URL if available
		if not sourceRawData or #sourceRawData == 0 then
			-- Try GitHub fallback for bots.tf
			if sourceName == "bots.tf" then
				Tasks.message = "Primary source failed, trying backup..."

				-- Wait 2 seconds before retrying
				local startTime = globals.RealTime()
				while globals.RealTime() - startTime < Fetcher.Config.MinSourceDelay do
					Tasks.message = string.format(
						"Retry in %.1fs...",
						Fetcher.Config.MinSourceDelay - (globals.RealTime() - startTime)
					)
					coroutine.yield()
				end

				sourceRawData = Parsers.Download(
					"https://raw.githubusercontent.com/PazerOP/tf2_bot_detector/master/staging/cfg/playerlist.official.json"
				)
			end

			-- Still failed
			if not sourceRawData or #sourceRawData == 0 then
				return 0, "Download failed"
			end
		end

		-- Step 2: Process with minimal memory usage in the same coroutine
		Tasks.message = "Processing " .. sourceName .. "..."
		local result = 0

		-- Use incremental processing based on parser type
		if source.parser == "raw" then
			result = Parsers.ProcessRawList(sourceRawData, database, sourceName, source.cause)
		elseif source.parser == "tf2db" then
			result = Parsers.ProcessTF2DB(sourceRawData, database, source)
		else
			return 0, "Unknown parser type"
		end

		-- Clear data and force memory cleanup
		sourceRawData = nil
		Fetcher.Memory.ForceCleanup()

		return result
	end)

	-- Run the download coroutine until completion
	local result = 0
	while coroutine.status(downloadCoroutine) ~= "dead" do
		local success, res = coroutine.resume(downloadCoroutine)

		if not success then
			print("[Fetcher] Error in download coroutine: " .. tostring(res))
			return 0, tostring(res)
		end

		if type(res) == "number" then
			result = res
		end

		coroutine.yield() -- Give control back to main thread
	end

	return result
end

-- Main fetch function with improved coroutine handling
function Fetcher.FetchAll(database, callback, silent)
	-- If already running, don't start again
	if Tasks.isRunning then
		if not silent then
			print("[Database Fetcher] A fetch operation is already in progress")
		end
		return false
	end

	-- Force initial cleanup
	Fetcher.Memory.ForceCleanup()

	-- Initialize the task system with simplified UI
	Tasks.Reset()
	Tasks.Init(#Fetcher.Sources)
	Tasks.callback = callback
	Tasks.silent = silent or false
	Tasks.Config.SimplifiedUI = true -- Use simplified "Loading Database" UI

	-- Clean up any stale callbacks first
	pcall(function()
		callbacks.Unregister("Draw", "FetcherMainTask")
		callbacks.Unregister("Draw", "FetcherCallback")
	end)

	-- Create a main task that processes all sources with proper pacing
	local mainTask = coroutine.create(function()
		local totalAdded = 0

		-- Process each source with mandatory delays between them
		for i, source in ipairs(Fetcher.Sources) do
			-- Start source with progress tracking
			Tasks.StartSource(source.name)

			-- Update target progress for smooth interpolation
			Tasks.targetProgress = (i - 1) / #Fetcher.Sources * 100

			-- Check memory before each source
			Fetcher.Memory.Check()

			-- Yield to update UI
			coroutine.yield()

			-- Always apply the 2-second delay between sources
			if i > 1 or Fetcher.Config.ForceInitialDelay then
				local delay = Fetcher.GetSourceDelay()
				Tasks.message = string.format("Waiting %.1fs between requests...", delay)

				-- Wait with countdown using coroutines for smoother UI
				local startTime = globals.RealTime()
				while globals.RealTime() < startTime + delay do
					local remaining = math.ceil((startTime + delay) - globals.RealTime())
					Tasks.message = string.format("Rate limit: %ds before next request...", remaining)
					coroutine.yield()
				end
			end

			-- Process the source with memory-efficient batching
			Tasks.message = "Fetching from " .. source.name
			local count = 0

			-- Use the batch processor for better memory management
			local success, result = pcall(function()
				return Fetcher.ProcessSourceInBatches(source, database)
			end)

			if success and type(result) == "number" then
				count = result
				totalAdded = totalAdded + count
				Tasks.message = string.format("Added %d entries from %s", count, source.name)
			else
				local errorMsg = type(result) == "string" and result or "unknown error"
				print("[Database Fetcher] Error processing " .. source.name .. ": " .. errorMsg)
				Tasks.message = "Error processing " .. source.name
			end

			-- Mark source as done for progress updates
			Tasks.SourceDone()

			-- Force cleanup after each source
			Fetcher.Memory.ForceCleanup()

			-- Always yield after each source to keep the game responsive
			coroutine.yield()
		end

		-- Finalize
		Tasks.targetProgress = 100
		Tasks.status = "complete"
		Tasks.message = "Database Loaded"
		Tasks.completedTime = globals.RealTime()

		-- Update last fetch time
		Fetcher.Config.LastAutoFetch = os.time()

		-- Final cleanup
		Fetcher.Memory.ForceCleanup()

		-- Safely handle database save outside coroutine
		if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch and database.State then
			database.State.isDirty = true
		end

		return totalAdded
	end)

	-- Register the main task processor
	callbacks.Register("Draw", "FetcherMainTask", function()
		-- Check memory every frame
		Fetcher.Memory.Check()

		-- Process the main task if it's not finished
		if coroutine.status(mainTask) ~= "dead" then
			-- Resume the main task
			local success, result = pcall(coroutine.resume, mainTask)

			if not success then
				-- Handle error in main task
				print("[Database Fetcher] Error: " .. tostring(result))
				Tasks.Reset()
				Fetcher.Memory.ForceCleanup()
				callbacks.Unregister("Draw", "FetcherMainTask")
			end
		else
			-- Task is complete, clean up
			callbacks.Unregister("Draw", "FetcherMainTask")

			-- Run completion callback with safety measures
			local _, result = coroutine.resume(mainTask)
			local totalAdded = tonumber(result) or 0

			-- Handle callback with separate function to prevent overflow
			if type(callback) == "function" then
				pcall(function()
					callbacks.Unregister("Draw", "FetcherCallback")
				end)

				-- Run callback in next frame
				callbacks.Register("Draw", "FetcherCallback", function()
					callbacks.Unregister("Draw", "FetcherCallback")
					local callbackSuccess, err = pcall(callback, totalAdded)
					if not callbackSuccess then
						print("[Database Fetcher] Warning: Callback failed: " .. tostring(err))
					end
				end)
			end

			-- Ensure complete memory cleanup
			Fetcher.Memory.ForceCleanup()
		end
	end)

	return true
end

-- Auto fetch handler
function Fetcher.AutoFetch(database)
	-- Get database if not provided
	if not database then
		local success, db = pcall(function()
			return require("Cheater_Detection.Database.Database")
		end)

		if not success or not db then
			return false
		end
		database = db
	end

	-- Start fetch with silent mode and safe save handling
	return Fetcher.FetchAll(database, function(totalAdded)
		-- Only force save if we have a meaningful number of entries
		if totalAdded and totalAdded > 0 then
			-- First clean memory to avoid overflow during save
			collectgarbage("collect")

			-- Clean up any existing callback first
			pcall(function()
				callbacks.Unregister("Draw", "DatabaseSaveDelay")
			end)

			-- Delay save to next frame to avoid stack overflow
			callbacks.Register("Draw", "DatabaseSaveDelay", function()
				callbacks.Unregister("Draw", "DatabaseSaveDelay")

				pcall(function()
					database.SaveDatabase()

					if Fetcher.Config.NotifyOnFetchComplete then
						printc(80, 200, 120, 255, "[Database] Auto-updated with " .. totalAdded .. " new entries")
					end
				end)
			end)
		end
	end, not Fetcher.Config.ShowProgressBar)
end

-- Draw callback to show progress UI
callbacks.Register("Draw", "FetcherUI", function()
	if Tasks.isRunning and Fetcher.Config.ShowProgressBar and not Tasks.silent then
		-- Update source progress information
		if Tasks.currentSource then
			local sourcePct = Fetcher.UI.totalSources > 0
					and (Fetcher.UI.completedSources / Fetcher.UI.totalSources * 100)
				or 0
			Tasks.message = string.format(
				"%s [Source %d/%d - %.0f%%]",
				Tasks.message:gsub("%s*%[Source.*%]%s*$", ""),
				Fetcher.UI.completedSources,
				Fetcher.UI.totalSources,
				sourcePct
			)
		end

		-- Draw the UI
		pcall(Tasks.DrawProgressUI)
	end
end)

-- Register improved commands
local function RegisterCommands()
	local function getDatabase()
		return require("Cheater_Detection.Database.Database")
	end

	-- Register fetch commands
	Commands.Register("cd_fetch_all", function()
		if not Tasks.isRunning then
			local Database = getDatabase()
			Fetcher.FetchAll(Database, function(totalAdded)
				if totalAdded > 0 then
					Database.SaveDatabase()
				end
			end)
		else
			print("[Database Fetcher] A fetch operation is already in progress")
		end
	end, "Fetch all cheater lists and update the database")

	Commands.Register("cd_fetch_source", function(args)
		if #args < 1 then
			print("Usage: cd_fetch_source <source_index>")
			return
		end

		local sourceIndex = tonumber(args[1])
		if not sourceIndex or sourceIndex < 1 or sourceIndex > #Fetcher.Sources then
			print("Invalid source index. Use cd_list_sources to see available sources.")
			return
		end

		if not Tasks.isRunning then
			local Database = getDatabase()
			local source = Fetcher.Sources[sourceIndex]

			-- Initialize for a single source
			Tasks.Reset()
			Tasks.Init(1)

			-- Setup UI tracking
			Fetcher.UI.totalSources = 1
			Fetcher.UI.completedSources = 0
			Fetcher.UI.currentProgress = 0
			Fetcher.UI.targetProgress = 0

			-- Clean up existing callbacks first
			pcall(function()
				callbacks.Unregister("Draw", "FetcherSingleSource")
				callbacks.Unregister("Draw", "FetcherSingleSourceCleanup")
			end)

			-- Create task coroutine
			local task = coroutine.create(function()
				Tasks.StartSource(source.name)
				local count = Parsers.ProcessSource(source, Database)
				Tasks.SourceDone()

				-- Update progress tracking
				Fetcher.UI.completedSources = 1
				Fetcher.UI.targetProgress = 100

				if count > 0 then
					Database.SaveDatabase()
				end

				return count
			end)

			-- Process the task
			callbacks.Register("Draw", "FetcherSingleSource", function()
				if coroutine.status(task) ~= "dead" then
					-- Resume the task
					local success, result = pcall(coroutine.resume, task)

					-- Update smooth progress
					Fetcher.UI.currentProgress = Fetcher.UI.currentProgress
						+ (Fetcher.UI.targetProgress - Fetcher.UI.currentProgress) * Fetcher.Config.SmoothingFactor

					-- Update the task progress
					Tasks.progress = math.floor(Fetcher.UI.currentProgress)

					if not success then
						print("[Database Fetcher] Error: " .. tostring(result))
						Tasks.Reset()
						callbacks.Unregister("Draw", "FetcherSingleSource")
					end
				else
					-- Get result and clean up
					local _, count = coroutine.resume(task)
					count = tonumber(count) or 0

					print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
					callbacks.Unregister("Draw", "FetcherSingleSource")

					-- Show completion
					Tasks.status = "complete"
					Tasks.progress = 100
					Tasks.message = "Added " .. count .. " entries from " .. source.name

					-- Clean up after showing completion
					local startTime = globals.RealTime()
					local function cleanup()
						if globals.RealTime() >= startTime + 2 then
							Tasks.Reset()
							callbacks.Unregister("Draw", "FetcherSingleSourceCleanup")
						end
					end
					callbacks.Register("Draw", "FetcherSingleSourceCleanup", cleanup)
				end
			end)
		else
			print("[Database Fetcher] A task is already in progress")
		end
	end, "Fetch from a specific source")

	Commands.Register("cd_list_sources", function()
		print("[Database Fetcher] Available sources:")
		for i, source in ipairs(Fetcher.Sources) do
			print(string.format("%d. %s (%s)", i, source.name, source.cause))
		end
	end, "List all available sources")

	Commands.Register("cd_fetch_delay", function(args)
		if #args < 2 then
			print("Usage: cd_fetch_delay <min_seconds> <max_seconds>")
			print(
				string.format(
					"Current delay: %.1f-%.1f seconds",
					Fetcher.Config.MinSourceDelay,
					Fetcher.Config.MaxSourceDelay
				)
			)
			return
		end

		local minDelay = tonumber(args[1])
		local maxDelay = tonumber(args[2])

		if not minDelay or not maxDelay then
			print("Invalid delay values")
			return
		end

		Fetcher.Config.MinSourceDelay = math.max(1, minDelay)
		Fetcher.Config.MaxSourceDelay = math.max(Fetcher.Config.MinSourceDelay, maxDelay)

		print(
			string.format(
				"[Database Fetcher] Set source delay to %.1f-%.1f seconds",
				Fetcher.Config.MinSourceDelay,
				Fetcher.Config.MaxSourceDelay
			)
		)
	end, "Set delay between source fetches (anti-ban protection)")

	Commands.Register("cd_cancel", function()
		if Tasks.isRunning then
			Tasks.Reset()
			print("[Database Fetcher] Cancelled all tasks")
		else
			print("[Database Fetcher] No tasks running")
		end
	end, "Cancel any running fetch operations")
end

-- Register commands
RegisterCommands()

-- Auto-fetch on load if enabled
if Fetcher.Config.AutoFetchOnLoad then
	local autoLoadRegistered = false
	pcall(function()
		callbacks.Unregister("Draw", "FetcherAutoLoad")
	end)

	callbacks.Register("Draw", "FetcherAutoLoad", function()
		callbacks.Unregister("Draw", "FetcherAutoLoad")
		Fetcher.AutoFetch()
	end)
end

return Fetcher
