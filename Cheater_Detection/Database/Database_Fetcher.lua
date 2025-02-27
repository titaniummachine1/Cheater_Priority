--[[
    Minimal Database_Fetcher.lua that just works
    No bloat, just gets data and adds it to the database
]]

local Common = require("Cheater_Detection.Utils.Common")
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")
local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")
local Commands = Common.Lib.Utils.Commands -- Use existing Commands

-- Create fetcher object
local Fetcher = {
	Config = {
		AutoFetchOnLoad = false,
		ShowProgressBar = true,
		SourceDelay = 2, -- Fixed 2 second delay
	},
	Sources = Sources.List,
	Tasks = Tasks,
}

-- Improved direct update with better coroutine yielding
function Fetcher.DirectUpdate(source, database)
	if not source or not source.url or not database then
		return 0
	end

	-- Get source name for display
	local sourceName = source.name or "Unknown Source"
	Tasks.message = "Downloading from " .. sourceName

	-- Always yield after updating UI message
	coroutine.yield()

	-- Download content in a non-blocking way
	local downloadTask = coroutine.create(function()
		return http.Get(source.url)
	end)

	-- Process the download
	local content
	while coroutine.status(downloadTask) ~= "dead" do
		local success, result = coroutine.resume(downloadTask)

		if success and result then
			content = result
		end

		-- Always yield to keep game responsive
		coroutine.yield()
	end

	-- Check for failed download
	if not content or #content == 0 then
		print("[Fetcher] Failed to download from " .. sourceName)
		return 0
	end

	Tasks.message = "Processing " .. sourceName
	coroutine.yield()

	-- Process based on parser type
	local count = 0
	local processed = 0

	if source.parser == "raw" then
		-- Process plain text list
		for line in content:gmatch("[^\r\n]+") do
			line = line:match("^%s*(.-)%s*$") -- Trim whitespace

			-- Skip comments and empty lines
			if line ~= "" and not line:match("^%-%-") and not line:match("^#") and not line:match("^//") then
				-- Check if line is a valid SteamID64
				if line:match("^%d+$") and #line >= 15 and #line <= 20 then
					-- Add to database if not already present
					if not database.content[line] then
						database.content[line] = {
							Name = "Unknown",
							proof = source.cause,
						}
						count = count + 1
						database.State.isDirty = true

						-- Set player priority
						pcall(function()
							playerlist.SetPriority(line, 10)
						end)
					end
				end
			end

			processed = processed + 1

			-- Yield frequently to keep the game responsive
			if processed % 250 == 0 then
				Tasks.message = string.format("Processing %s: %d added", sourceName, count)
				coroutine.yield()
			end
		end
	elseif source.parser == "tf2db" then
		-- Process TF2DB JSON
		for steamId in content:gmatch('"steamid"%s*:%s*"([^"]+)"') do
			local steamID64 = steamId

			-- Only convert non-SteamID64 formats
			if not (steamId:match("^%d+$") and #steamId >= 15) then
				pcall(function()
					steamID64 = steam.ToSteamID64(steamId)
				end)
			end

			-- Add valid IDs to database
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
				end
			end

			processed = processed + 1

			-- Yield frequently
			if processed % 250 == 0 then
				Tasks.message = string.format("Processing %s: %d added", sourceName, count)
				coroutine.yield()
			end
		end
	end

	-- Log results
	print("[Fetcher] Added " .. count .. " entries from " .. sourceName)

	-- Clean up
	content = nil
	collectgarbage("collect")

	return count
end

-- Simple FetchAll function with proper coroutines
function Fetcher.FetchAll(database, callback, silent)
	-- Don't start if already running
	if Tasks.isRunning then
		return false
	end

	-- Reset task system
	Tasks.Reset()
	Tasks.Init(#Fetcher.Sources)
	Tasks.isRunning = true
	Tasks.silent = silent or false

	-- Clear any existing callbacks
	pcall(function()
		callbacks.Unregister("Draw", "FetcherMain")
		callbacks.Unregister("Draw", "FetcherUI")
	end)

	-- Register UI drawing if not silent
	if not silent then
		callbacks.Register("Draw", "FetcherUI", function()
			if Tasks.isRunning then
				pcall(Tasks.DrawProgressUI)
			else
				callbacks.Unregister("Draw", "FetcherUI")
			end
		end)
	end

	-- Create main fetch task
	local fetchTask = coroutine.create(function()
		local totalAdded = 0

		-- Loop through each source
		for i, source in ipairs(Fetcher.Sources) do
			-- Update progress display
			Tasks.StartSource(source.name)
			Tasks.targetProgress = (i - 1) / #Fetcher.Sources * 100
			coroutine.yield()

			-- Add delay between sources (except first)
			if i > 1 then
				local startTime = globals.RealTime()
				while globals.RealTime() < startTime + Fetcher.Config.SourceDelay do
					local remaining = math.ceil(startTime + Fetcher.Config.SourceDelay - globals.RealTime())
					Tasks.message = "Waiting " .. remaining .. "s between requests..."
					coroutine.yield()
				end
			end

			-- Download and process the source
			local count = Fetcher.DirectUpdate(source, database)
			totalAdded = totalAdded + count

			-- Mark source as complete
			Tasks.SourceDone()
			collectgarbage("collect")
			coroutine.yield()
		end

		-- Complete the task
		Tasks.status = "complete"
		Tasks.targetProgress = 100
		Tasks.message = "Update Complete: Added " .. totalAdded .. " entries"
		Tasks.completedTime = globals.RealTime()

		-- Mark database as dirty if entries were added
		if totalAdded > 0 then
			database.State.isDirty = true

			-- Schedule save for next frame
			pcall(function()
				callbacks.Unregister("Draw", "FetcherSaveDelay")
			end)

			callbacks.Register("Draw", "FetcherSaveDelay", function()
				callbacks.Unregister("Draw", "FetcherSaveDelay")
				database.SaveDatabase()
			end)
		end

		-- Run callback if provided
		if callback and type(callback) == "function" then
			callback(totalAdded)
		end

		return totalAdded
	end)

	-- Register task processor
	callbacks.Register("Draw", "FetcherMain", function()
		if coroutine.status(fetchTask) ~= "dead" then
			local success, result = pcall(coroutine.resume, fetchTask)

			if not success then
				print("[Fetcher] Error: " .. tostring(result))
				Tasks.Reset()
				callbacks.Unregister("Draw", "FetcherMain")
			end
		else
			callbacks.Unregister("Draw", "FetcherMain")
		end
	end)

	return true
end

-- Auto fetch handler
function Fetcher.AutoFetch(database)
	if not database then
		local success, db = pcall(function()
			return require("Cheater_Detection.Database.Database")
		end)

		if not success or not db then
			return false
		end
		database = db
	end

	return Fetcher.FetchAll(database, function(totalAdded)
		if totalAdded > 0 then
			printc(80, 200, 120, 255, "[Database] Updated with " .. totalAdded .. " new entries")
		end
	end, not Fetcher.Config.ShowProgressBar)
end

-- Register only essential commands
Commands.Register("cd_fetch", function()
	if not Tasks.isRunning then
		local Database = require("Cheater_Detection.Database.Database")
		Fetcher.FetchAll(Database)
	else
		print("[Database Fetcher] A fetch operation is already in progress")
	end
end, "Fetch all cheater lists and update the database")

Commands.Register("cd_cancel", function()
	if Tasks.isRunning then
		Tasks.Reset()
		print("[Database Fetcher] Cancelled operation")
	end
end, "Cancel any running fetch operations")

-- Auto-fetch on load if enabled
if Fetcher.Config.AutoFetchOnLoad then
	pcall(function()
		callbacks.Unregister("Draw", "FetcherAutoLoad")
	end)

	callbacks.Register("Draw", "FetcherAutoLoad", function()
		callbacks.Unregister("Draw", "FetcherAutoLoad")
		Fetcher.AutoFetch()
	end)
end

return Fetcher
