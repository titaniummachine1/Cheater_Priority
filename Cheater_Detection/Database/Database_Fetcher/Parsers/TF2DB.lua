--[[
    TF2DB Parser - Specialized parser for TF2 Database format
    Uses string operations to parse JSON data with minimal memory impact
]]

local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local TF2DB = {}

-- Configuration for TF2DB parser
TF2DB.Config = {
	ChunkSize = 32768, -- 32KB chunks for string processing
	MaxContentSize = 5 * 1024 * 1024, -- 5MB max size for any source
	EmergencyTimeoutSec = 10, -- Maximum processing time before emergency bailout
	ForceStringOnly = true, -- Always use string-based parser (never use JSON)
	EstimateEntriesPerKB = 2, -- Estimate 2 entries per KB of content for progress
	MaxEntriesPerSource = 50000, -- Maximum entries to process from a single source
	FastSkipMode = true, -- Skip detailed parsing for very large files
	LogMemoryUsage = true, -- Log memory usage during parsing
}

-- Process TF2DB data efficiently
function TF2DB.Process(content, database, source)
	-- Input validation
	if not content or not database or not source then
		print("[Parsers] Error: Missing required parameters for TF2DB parser")
		return 0
	end

	-- Get source metadata
	local sourceName = source.name or "Unknown TF2DB Source"
	local sourceCause = source.cause or "Unknown"

	-- Check for extremely large content and apply limits
	if #content > TF2DB.Config.MaxContentSize then
		print(
			string.format(
				"[Parsers] Error: Content too large from %s (%dMB), truncating to %dMB",
				sourceName,
				math.floor(#content / 1024 / 1024),
				math.floor(TF2DB.Config.MaxContentSize / 1024 / 1024)
			)
		)

		-- Truncate content to avoid memory issues
		content = content:sub(1, TF2DB.Config.MaxContentSize)
	end

	Tasks.message = "Processing " .. sourceName .. " with string parser..."
	coroutine.yield()

	-- Log initial memory usage
	if TF2DB.Config.LogMemoryUsage then
		local memBefore = collectgarbage("count") / 1024
		print(string.format("[Parsers] Starting TF2DB processing, memory: %.2f MB", memBefore))
	end

	-- Initialize counters
	local count = 0
	local skipped = 0
	local invalid = 0
	local processed = 0
	local contentLen = #content

	-- Estimate total entries for progress reporting
	local estimatedTotal = math.floor(contentLen / 1024 * TF2DB.Config.EstimateEntriesPerKB)

	-- Create emergency bailout function
	local startTime = globals.RealTime()
	local bailoutTime = startTime + TF2DB.Config.EmergencyTimeoutSec

	-- Fast detection of SteamID format to optimize parsing strategy
	local hasSteamID64Format = content:match('"steamid":%s*"[0-9]+"')
	local hasSteamID3Format = content:match('"steamid":%s*"\\[U:1:[0-9]+\\]"')
	local hasSteamID2Format = content:match('"steamid":%s*"STEAM_0:[01]:[0-9]+"')

	-- Select the most appropriate pattern based on content
	local steamIDPattern
	if hasSteamID64Format then
		steamIDPattern = '"steamid":%s*"([0-9]+)"'
	elseif hasSteamID3Format then
		steamIDPattern = '"steamid":%s*"(%[U:1:[0-9]+%])"'
	elseif hasSteamID2Format then
		steamIDPattern = '"steamid":%s*"(STEAM_0:[01]:[0-9]+)"'
	else
		-- Fallback pattern that matches any format
		steamIDPattern = '"steamid":%s*"([^"]+)"'
	end

	-- Determine name pattern
	local namePattern
	if content:match('"name":%s*"[^"]+"') then
		namePattern = '"name":%s*"([^"]*)"'
	elseif content:match('"player_name":%s*"[^"]+"') then
		namePattern = '"player_name":%s*"([^"]*)"'
	else
		namePattern = '"name":%s*"([^"]*)"'
	end

	Tasks.message = "Parsing " .. sourceName .. " (" .. math.floor(contentLen / 1024) .. "KB)"
	coroutine.yield()

	-- Process in chunks to prevent memory issues
	local currentPos = 1
	local chunkSize = TF2DB.Config.ChunkSize
	local lastProgressUpdate = globals.RealTime()

	-- Convert SteamID to SteamID64
	local function convertToSteamID64(steamID)
		if not steamID then
			return nil
		end
	end

	return count
end

return TF2DB
