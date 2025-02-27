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
	print("[Database Fetcher] Warning: JSON library not available in Common, some features may not work")
end

-- Improve module loading with better error handling
local Tasks, Sources, Parsers
local loadSuccess = true

-- Try to load each module with detailed error reporting
local function tryRequire(name, path)
	print("[Database Fetcher] Loading module: " .. path)
	local success, module = pcall(function()
		return require(path)
	end)

	if not success then
		print("[Database Fetcher] ERROR: Failed to load " .. name .. " module: " .. tostring(module))
		loadSuccess = false
		return {}
	end

	print("[Database Fetcher] Successfully loaded: " .. name)
	return module
end

-- Load modules with more robust error handling
Tasks = tryRequire("Tasks", "Cheater_Detection.Database.Database_Fetcher.Tasks")
Sources = tryRequire("Sources", "Cheater_Detection.Database.Database_Fetcher.Sources")

-- Try to load Parsers with fallback to our FallbackParsers
local parsersPath = "Cheater_Detection.Database.Database_Fetcher.Parsers"
Parsers = tryRequire("Parsers", parsersPath)

-- Create minimal Parsers interface if loading failed
if not Parsers or not Parsers.Download then
	print("[Database Fetcher] WARNING: Creating minimal Parsers interface")

	Parsers = {
		-- Simple Download function that doesn't depend on any modules
		Download = function(url)
			print("[Minimal Parsers] Downloading: " .. url)
			return http.Get(url)
		end,

		-- Simple processing functions that track what they're called with
		ProcessRawList = function(content, database, sourceName, sourceCause)
			print("[Minimal Parsers] Processing raw list: " .. sourceName)
			return 0
		end,

		ProcessTF2DB = function(content, database, source)
			print("[Minimal Parsers] Processing TF2DB: " .. source.name)
			return 0
		end,

		ProcessSource = function(source, database)
			print("[Minimal Parsers] Processing source: " .. source.name)
			return 0
		end,
	}
end

-- Make sure we create a global reference that won't be garbage collected
_G.CD_Parsers = Parsers

-- Create fetcher object with improved configuration
local Fetcher = {
	Config = {
		-- Basic settings
		AutoFetchOnLoad = false, -- Auto fetch when script loads
		AutoSaveAfterFetch = true, -- Save database after fetching
		NotifyOnFetchComplete = true, -- Show completion notifications
		ShowProgressBar = true, -- Show progress UI
		ForceInitialDelay = true, -- Always apply delay even before first source

		-- Anti-ban protection settings
		MinSourceDelay = 2, -- Fixed 2 second minimum delay between sources
		MaxSourceDelay = 2, -- Fixed 2 second maximum delay between sources
		RequestTimeout = 15, -- Seconds to wait before timeout
		EnableRandomDelay = false, -- Always use exactly 2 seconds

		-- UI settings
		SmoothingFactor = 0.05, -- Lower = smoother but slower progress bar

		-- Auto-fetch settings
		AutoFetchInterval = 0, -- Minutes between auto-fetches (0 = disabled)
		LastAutoFetch = 0, -- Timestamp of last auto-fetch

		-- Debug settings
		DebugMode = false, -- Enable debug output

		-- Memory management settings
		MaxMemoryMB = 100, -- Target maximum memory usage (MB)
		ForceGCThreshold = 50, -- Force GC when memory exceeds this % of max
		UseWeakTables = true, -- Use weak references for temp data
		StringBuffering = true, -- Use string processing instead of tables
	},
}

-- Export components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List
Fetcher.Json = Json -- Export JSON reference for components that need it

-- Use weak tables for UI tracking with minimal memory usage
Fetcher.UI = setmetatable({
	targetProgress = 0,
	currentProgress = 0,
	completedSources = 0,
	totalSources = 0,
}, { __mode = "v" }) -- Values are weak references

-- Any temporary storage should use weak tables
Fetcher.TempStorage = setmetatable({}, { __mode = "kv" }) -- Both keys and values are weak

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

	-- Add emergency cleanup function
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

	-- Create a dedicated coroutine for downloading with robust error handling
	local downloadCoroutine = coroutine.create(function()
		-- Create local copies of all needed functions to avoid upvalue issues
		local localDownload = _G.CD_Parsers.Download
		local localProcessRawList = _G.CD_Parsers.ProcessRawList
		local localProcessTF2DB = _G.CD_Parsers.ProcessTF2DB

		-- Safety check for our functions
		if not localDownload or type(localDownload) ~= "function" then
			print("[Fetcher] CRITICAL ERROR: Download function not available!")
			return 0, "Download function not available"
		end

		-- Safe download with detailed error handling
		local sourceRawData
		local success, result = pcall(function()
			print("[Fetcher] Downloading from " .. sourceUrl)
			return localDownload(sourceUrl)
		end)

		if not success then
			print("[Fetcher] Download error: " .. tostring(result))
			return 0, "Download error: " .. tostring(result)
		end

		sourceRawData = result

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
			print("[Fetcher] Processing as raw list: " .. sourceName)
			if localProcessRawList and type(localProcessRawList) == "function" then
				result = localProcessRawList(sourceRawData, database, sourceName, source.cause)
			else
				print("[Fetcher] ERROR: ProcessRawList function not available!")
			end
		elseif source.parser == "tf2db" then
			print("[Fetcher] Processing as TF2DB: " .. sourceName)
			if localProcessTF2DB and type(localProcessTF2DB) == "function" then
				result = localProcessTF2DB(sourceRawData, database, source)
			else
				print("[Fetcher] ERROR: ProcessTF2DB function not available!")
			end
		else
			return 0, "Unknown parser type: " .. tostring(source.parser)
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

			-- ALWAYS apply the 2-second delay between sources, even for the first one
			-- This allows the game to breathe between network operations
			if i > 1 or Fetcher.Config.ForceInitialDelay then
				local delay = Fetcher.GetSourceDelay() -- Will always be 2 seconds
				Tasks.message = string.format("Waiting %.1fs between requests...", delay)

				-- Wait with countdown using coroutines for smoother UI
				local startTime = globals.RealTime()
				while globals.RealTime() < startTime + delay do
					-- Update remaining time
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
		if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch then
			-- The database should be saved by the callback, not here
			-- Just mark as dirty and let the database handle it
			if database.State then
				database.State.isDirty = true
			end
		end

		return totalAdded
	end)

	-- Register the main task processor with enhanced memory management
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

			-- Handle callback with separate coroutine to prevent overflow
			if type(callback) == "function" then
				-- Run callback in next frame to prevent stack overflow
				callbacks.Register("Draw", "FetcherCallback", function()
					callbacks.Unregister("Draw", "FetcherCallback")

					local callbackSuccess, err = pcall(callback, totalAdded)
					if not callbackSuccess then
						print("[Database Fetcher] Warning: Callback failed: " .. tostring(err))
						Fetcher.Memory.EmergencyCleanup()
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
			local sourcePct = Fetcher.UI.completedSources / Fetcher.UI.totalSources * 100
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

	-- Fetch all command
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

	-- Fetch specific source command
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

	-- List sources command
	Commands.Register("cd_list_sources", function()
		print("[Database Fetcher] Available sources:")
		for i, source in ipairs(Fetcher.Sources) do
			print(string.format("%d. %s (%s)", i, source.name, source.cause))
		end
	end, "List all available sources")

	-- Configure delay command
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

	-- Cancel command
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
	callbacks.Register("Draw", "FetcherAutoLoad", function()
		callbacks.Unregister("Draw", "FetcherAutoLoad")
		Fetcher.AutoFetch()
	end)
end

return Fetcher
