-- Enhanced parsers with improved memory management and string-based processing

local Common = require("Cheater_Detection.Utils.Common")
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

-- Get JSON directly from Common, don't try to use any other module
local Json = Common.Json

local Parsers = {}

-- Configuration (enhanced)
Parsers.Config = {
	RetryDelay = 4, -- Initial delay between retries (seconds)
	RetryBackoff = 2, -- Multiply delay by this factor on each retry
	RequestTimeout = 10, -- Maximum time to wait for a response (seconds)
	YieldInterval = 500, -- Yield after processing this many items
	MaxRetries = 3, -- Maximum number of retry attempts
	RetryOnEmpty = true, -- Retry if response is empty
	DebugMode = true, -- Enable detailed error logging
	UserAgents = { -- Add different user agents to rotate through
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
	},
	CurrentUserAgent = 1, -- Index of current user agent to use
	AllowHtml = false, -- Whether to allow HTML responses (usually indicates an error)
	MaxErrorDisplayLength = 80, -- Maximum length of error messages to display
	StringBufferSize = 8192, -- Process strings in chunks of this size
	UseWeakTables = true, -- Use weak references for temporary data
	ForceGCInterval = 10000, -- Force garbage collection every N entries
	UseStringOnly = true, -- Use string operations instead of tables where possible
	MaxTableEntries = 1000, -- Maximum entries to store in a table before switching to incremental processing
}

-- Configuration enhancements for TF2DB parser
Parsers.Config.TF2DB = {
	ChunkSize = 32768, -- 32KB chunks for string processing
	MaxContentSize = 5 * 1024 * 1024, -- 5MB max size for any source
	EmergencyTimeoutSec = 10, -- Maximum processing time before emergency bailout
	ForceStringOnly = true, -- Always use string-based parser (never use JSON)
	EstimateEntriesPerKB = 2, -- Estimate 2 entries per KB of content for progress
	MaxEntriesPerSource = 50000, -- Maximum entries to process from a single source
	FastSkipMode = true, -- Skip detailed parsing for very large files
	LogMemoryUsage = true, -- Log memory usage during parsing
}

-- Create weak reference tables for temporary storage (both keys and values are weak)
Parsers.TempStorage = setmetatable({}, { __mode = "kv" })

-- Error logging function with debug mode control
function Parsers.LogError(message, details)
	-- Always log critical errors
	print("[Database Fetcher] Error: " .. message)

	-- Log additional details only in debug mode
	if Parsers.Config.DebugMode and details then
		if type(details) == "string" and #details > 100 then
			-- Truncate very long details to prevent console overflow
			print("[Database Fetcher] Details: " .. details:sub(1, 100) .. "... (truncated)")
		else
			print("[Database Fetcher] Details: " .. tostring(details))
		end
	end

	-- Set the task message with a safe truncated version
	local displayMessage = message
	if #displayMessage > Parsers.Config.MaxErrorDisplayLength then
		displayMessage = displayMessage:sub(1, Parsers.Config.MaxErrorDisplayLength) .. "..."
	end

	if Tasks and Tasks.message then
		Tasks.message = "Error: " .. displayMessage
	end
end

-- Safe and memory-efficient download function
function Parsers.Download(url, retryCount)
	-- Clear any previous temp storage before download
	Parsers.TempStorage = setmetatable({}, { __mode = "v" })
	collectgarbage("step", 100)

	retryCount = retryCount or Parsers.Config.MaxRetries

	-- Use different user agents for GitHub to avoid rate limiting
	if url:find("github") or url:find("githubusercontent") then
		table.insert(
			Parsers.Config.UserAgents,
			1,
			"Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
		)
	end

	local retry = 0
	local lastError = nil

	while retry < retryCount do
		-- Rotate user agents on retries
		Parsers.Config.CurrentUserAgent = 1 + (retry % #Parsers.Config.UserAgents)
		local userAgent = Parsers.Config.UserAgents[Parsers.Config.CurrentUserAgent]

		Tasks.message = "Downloading from " .. url:sub(1, 40) .. "... (try " .. (retry + 1) .. "/" .. retryCount .. ")"
		coroutine.yield()

		local requestTimedOut = false
		local startTime = globals.RealTime()
		local response = nil

		-- Create a timeout checker
		local timeoutCheckerId = "request_timeout_" .. tostring(math.random(1000000))
		callbacks.Register("Draw", timeoutCheckerId, function()
			if globals.RealTime() - startTime > Parsers.Config.RequestTimeout then
				requestTimedOut = true
				callbacks.Unregister("Draw", timeoutCheckerId)
			end
		end)

		-- Attempt the HTTP request with custom headers
		local success, result = pcall(function()
			local headers = {
				["User-Agent"] = userAgent,
				["Accept"] = "text/plain, application/json",
				["Cache-Control"] = "no-cache",
			}

			-- Use http.Get with headers
			return http.Get(url, headers)
		end)

		-- Unregister the timeout checker
		callbacks.Unregister("Draw", timeoutCheckerId)

		-- Process the result with direct string handling
		if requestTimedOut then
			lastError = "Request timed out"
		elseif not success then
			lastError = "HTTP error: " .. tostring(result)
		elseif not result then
			lastError = "Empty response"
		elseif type(result) ~= "string" then
			lastError = "Invalid response type: " .. type(result)
		elseif #result == 0 then
			if Parsers.Config.RetryOnEmpty then
				lastError = "Empty response"
			else
				return "" -- Return empty string if empty responses are acceptable
			end
		else
			-- Check for HTML directly via string patterns, not table operations
			if result:match("<!DOCTYPE html>") or result:match("<html") then
				-- Check if it's GitHub returning HTML
				if url:find("github") or url:find("githubusercontent") and result:find("rate limit") then
					lastError = "GitHub rate limit exceeded. Try again later."
				else
					lastError = "Received HTML instead of data (website error or CAPTCHA)"
				end

				-- Always print the HTML response start for debugging
				print("[Parsers] HTML response from " .. url .. " (length: " .. #result .. ")")
				print("[Parsers] First 100 chars: " .. result:sub(1, 100))

				-- If HTML allowed, return it anyway
				if Parsers.Config.AllowHtml then
					return result
				end
			else
				-- Success! Return the response without creating tables
				return result
			end
		end

		-- Failed, try again
		retry = retry + 1
		if retry < retryCount then
			-- Wait with exponential backoff
			local waitTime = Parsers.Config.RetryDelay * (Parsers.Config.RetryBackoff ^ (retry - 1))
			Tasks.message = "Retry in " .. waitTime .. "s: " .. lastError:sub(1, 50)

			-- Wait with a countdown
			local startWait = globals.RealTime()
			while globals.RealTime() < startWait + waitTime do
				local remaining = math.ceil((startWait + waitTime) - globals.RealTime())
				Tasks.message = "Retry in " .. remaining .. "s: " .. lastError:sub(1, 50)
				coroutine.yield()
			end
		end
	end

	-- All retries failed
	Parsers.LogError("Download failed after " .. retryCount .. " attempts", lastError)
	return nil
end

-- More robust SteamID conversion
function Parsers.ConvertToSteamID64(input)
	if not input then
		return nil
	end

	-- Safety check for unexpected input types
	if type(input) ~= "string" and type(input) ~= "number" then
		return nil
	end

	local steamid = tostring(input):match("^%s*(.-)%s*$") -- Trim whitespace

	-- If already a SteamID64, just return it
	if steamid:match("^%d+$") and #steamid >= 15 and #steamid <= 20 then
		return steamid
	end

	-- Try direct conversion with error handling
	local success, result = pcall(function()
		if steamid:match("^STEAM_0:%d:%d+$") or steamid:match("^%[U:1:%d+%]$") then
			return steam.ToSteamID64(steamid)
		end
		return nil
	end)

	if success and result and type(result) == "string" and #result >= 15 then
		return result
	end

	-- Manual conversion for SteamID3
	if steamid:match("^%[U:1:%d+%]$") then
		local accountID = steamid:match("%[U:1:(%d+)%]$")
		if accountID and tonumber(accountID) then
			local steamID64 = tostring(76561197960265728 + tonumber(accountID))
			-- Validate the result
			if #steamID64 >= 15 and #steamID64 <= 20 and steamID64:match("^%d+$") then
				return steamID64
			end
		end
	end

	-- Handle plain numeric IDs that might be account IDs
	if steamid:match("^%d+$") and tonumber(steamid) < 1000000000 then
		local steamID64 = tostring(76561197960265728 + tonumber(steamid))
		if #steamID64 >= 15 and #steamID64 <= 20 then
			return steamID64
		end
	end

	return nil
end

-- Safe function to process a line from a raw list
function Parsers.ProcessRawLine(line, database, sourceCause)
	-- Check for nil inputs
	if not line or not database or not sourceCause then
		return false, 0, "Missing required parameters"
	end

	-- Initialize counters
	local added = 0
	local skipped = 0
	local invalid = 0

	local success, errorMsg = pcall(function()
		-- Trim and validate line
		local trimmedLine = line:match("^%s*(.-)%s*$") or ""

		-- Skip comments, empty lines, and other non-ID lines
		if
			trimmedLine ~= ""
			and not trimmedLine:match("^%-%-")
			and not trimmedLine:match("^#")
			and not trimmedLine:match("^//")
			and not trimmedLine:match("^<!")
		then
			-- Attempt to extract a SteamID from various formats
			local steamID64 = Parsers.ConvertToSteamID64(trimmedLine)

			-- Add to database if valid and not duplicate
			if steamID64 then
				if not database.content[steamID64] then
					-- Add new entry
					database.content[steamID64] = {
						Name = "Unknown",
						proof = sourceCause,
					}

					-- Set player priority with error handling
					pcall(function()
						playerlist.SetPriority(steamID64, 10)
					end)
					added = 1
				else
					-- Entry already exists, don't update (the database handler will decide what to keep)
					skipped = 1
				end
			else
				invalid = 1
			end
		else
			skipped = 1 -- Count skipped comments/empty lines
		end
	end)

	if not success then
		return false, 0, errorMsg
	else
		return true, added, { skipped = skipped, invalid = invalid }
	end
end

-- Super robust raw list processor
function Parsers.ProcessRawList(content, database, sourceName, sourceCause)
	-- Special handling for bots.tf data
	if sourceName == "bots.tf" then
		return Parsers.ProcessBotsTF(content, database, sourceName, sourceCause)
	end

	-- Regular processing for other raw sources
	-- Input validation with detailed errors
	if not content then
		Parsers.LogError("Empty content from " .. (sourceName or "unknown source"))
		return 0
	end

	if not database then
		Parsers.LogError("Invalid database object")
		return 0
	end

	if not sourceName or not sourceCause then
		Parsers.LogError("Missing source metadata")
		return 0
	end

	-- Safety check for database structure
	if type(database) ~= "table" or type(database.content) ~= "table" then
		Parsers.LogError("Invalid database structure", type(database))
		return 0
	end

	Tasks.message = "Processing " .. sourceName .. "..."
	coroutine.yield()

	-- Initialize counters
	local count = 0
	local skipped = 0
	local invalid = 0
	local linesProcessed = 0
	local totalLines = 0

	-- Count lines with minimal memory usage (no table storage)
	local lineCount = 0
	for _ in content:gmatch("[^\r\n]+") do
		lineCount = lineCount + 1

		-- Yield occasionally during counting to prevent freezing
		if lineCount % 10000 == 0 then
			Tasks.message = "Counting lines in " .. sourceName .. " (" .. lineCount .. ")"
			coroutine.yield()
		end
	end
	totalLines = lineCount

	-- Process directly from string without storing all lines in memory
	local position = 1
	local contentLength = #content
	local batchSize = Parsers.Config.StringBufferSize

	while position <= contentLength do
		-- Extract a chunk of content to process
		local endPos = content:find("\n", position + batchSize) or contentLength
		local chunk = content:sub(position, endPos)
		position = endPos + 1

		-- Process all lines in this chunk
		for line in chunk:gmatch("[^\r\n]+") do
			local success, added, extraInfo = Parsers.ProcessRawLine(line, database, sourceCause)

			if success then
				count = count + added
				if type(extraInfo) == "table" then
					skipped = skipped + extraInfo.skipped
					invalid = invalid + extraInfo.invalid
				end
			else
				invalid = invalid + 1
			end

			linesProcessed = linesProcessed + 1

			-- Update progress periodically
			if linesProcessed % Parsers.Config.YieldInterval == 0 or linesProcessed >= totalLines then
				local progressPct = totalLines > 0 and math.floor((linesProcessed / totalLines) * 100) or 0
				Tasks.message =
					string.format("Processing %s: %d%% (%d added, %d skipped)", sourceName, progressPct, count, skipped)
				coroutine.yield()

				-- Force GC periodically
				if linesProcessed % Parsers.Config.ForceGCInterval == 0 then
					collectgarbage("step", 1000)
				end
			end
		end

		-- Clear the chunk from memory
		chunk = nil

		-- Yield to update UI
		coroutine.yield()
		collectgarbage("step", 100)
	end

	Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid", sourceName, count, skipped, invalid)
	coroutine.yield()

	-- Clear memory
	content = nil
	collectgarbage("collect")

	return count
end

-- Process a source with improved error handling and fallbacks
function Parsers.ProcessSource(source, database)
	-- Validate inputs
	if not source then
		Parsers.LogError("Source is nil")
		return 0
	end

	if not database then
		Parsers.LogError("Database is nil")
		return 0
	end

	if not source.url or not source.parser or not source.cause then
		local missingFields = {}
		if not source.url then
			table.insert(missingFields, "url")
		end
		if not source.parser then
			table.insert(missingFields, "parser")
		end
		if not source.cause then
			table.insert(missingFields, "cause")
		end

		Parsers.LogError("Invalid source configuration: missing " .. table.concat(missingFields, ", "))
		return 0
	end

	local sourceName = source.name or "Unknown Source"
	Tasks.message = "Fetching from " .. sourceName .. "..."

	-- Clear temp storage before each source
	Parsers.TempStorage = setmetatable({}, { __mode = "v" })
	collectgarbage("step", 100)

	-- Load fallbacks if needed
	local Fallbacks
	pcall(function()
		Fallbacks = require("Cheater_Detection.Database.Database_Fetcher.Fallbacks")
	end)

	-- Special handling for bots.tf which often fails due to CAPTCHA
	local usesFallback = false
	if sourceName:lower():find("bots%.tf") and Fallbacks then
		-- First try downloading normally
		content = Parsers.Download(source.url)

		-- If it fails (likely HTML/CAPTCHA response), use fallbacks
		if not content or #content == 0 or content:match("<!DOCTYPE html>") then
			-- Use GitHub fallbacks first - try common repositories
			local fallbackUrls = {
				"https://raw.githubusercontent.com/PazerOP/tf2_bot_detector/master/staging/cfg/playerlist.official.json",
				"https://raw.githubusercontent.com/wgetJane/tf2-catkill/master/bots.txt",
			}

			for _, url in ipairs(fallbackUrls) do
				Tasks.message = "Using fallback source for " .. sourceName .. "..."
				content = Parsers.Download(url)

				if content and #content > 0 and not content:match("<!DOCTYPE html>") then
					Tasks.message = "Fallback source successful!"
					usesFallback = true
					break
				end
			end

			-- If all online sources fail, use stored fallback data
			if (not content or #content == 0 or content:match("<!DOCTYPE html>")) and Fallbacks.LoadFallbackBots then
				Tasks.message = "Using emergency fallback bot data..."
				local emergencyCount = Fallbacks.LoadFallbackBots(database, source.cause)
				Tasks.message = "Added " .. emergencyCount .. " bots from emergency fallback"
				coroutine.yield()
				return emergencyCount
			end
		end
	else
		-- Non-bots.tf source - normal download procedure
		content = Parsers.Download(source.url)
	end

	-- If we still have no content, try backup URL if one exists
	if (not content or #content == 0) and sourceUrls and sourceUrls.backup then
		Tasks.message = "Primary URL failed, trying backup..."
		content = Parsers.Download(sourceUrls.backup)
	end

	-- If all downloads failed
	if not content or #content == 0 then
		Parsers.LogError("Failed to fetch from " .. sourceName)
		return 0
	end

	-- Process content based on parser type with full error handling
	local count = 0

	-- If we're using a fallback URL for bots.tf, adjust the parser as needed
	local parser = source.parser
	if usesFallback and sourceName:lower():find("bots%.tf") then
		if content:match("^%s*{") or content:match("^%s*%[") then
			parser = "tf2db" -- Use JSON parser for JSON content
		else
			parser = "raw" -- Use raw parser for plain text content
		end
	end

	if parser == "raw" then
		local success, result = pcall(function()
			return Parsers.ProcessRawList(content, database, sourceName, source.cause)
		end)

		-- Immediately clear content to free memory
		content = nil

		if success then
			count = result
		else
			Parsers.LogError("Failed to parse raw list from " .. sourceName, result)
		end
	elseif parser == "tf2db" then
		local success, result = pcall(function()
			return Parsers.ProcessTF2DB(content, database, source)
		end)

		-- Immediately clear content to free memory
		content = nil

		if success then
			count = result
		else
			Parsers.LogError("Failed to parse TF2DB data from " .. sourceName, result)

			-- If JSON parsing failed, try as raw list as a fallback
			Tasks.message = "Trying alternate parser for " .. sourceName
			success, result = pcall(function()
				return Parsers.ProcessRawList(content, database, sourceName, source.cause)
			end)

			if success then
				count = result
			end
		end
	else
		Parsers.LogError("Unknown parser type: " .. source.parser)
	end

	-- Force complete memory cleanup
	collectgarbage("collect")

	return count
end

-- Extremely memory-efficient TF2DB parser that avoids tables completely
function Parsers.ProcessTF2DB(content, database, source)
	-- Input validation
	if not content or not database or not source then
		Parsers.LogError("Missing required parameters for ProcessTF2DB")
		return 0
	end

	-- Get source metadata
	local sourceName = source.name or "Unknown TF2DB Source"

	-- Check for extremely large content and apply limits
	if #content > Parsers.Config.TF2DB.MaxContentSize then
		Parsers.LogError(
			"Content too large from " .. sourceName .. " (" .. math.floor(#content / 1024 / 1024) .. "MB), truncating",
			"Exceeds " .. math.floor(Parsers.Config.TF2DB.MaxContentSize / 1024 / 1024) .. "MB limit"
		)

		-- Truncate content to avoid memory issues
		content = content:sub(1, Parsers.Config.TF2DB.MaxContentSize)
	end

	-- Always use string-based processing now - no JSON parsing at all
	Tasks.message = "Processing " .. sourceName .. " with string parser..."

	-- Set up emergency bailout timer
	local startTime = globals.RealTime()
	local bailoutTime = startTime + Parsers.Config.TF2DB.EmergencyTimeoutSec
	local bailoutTask = coroutine.create(function()
		while true do
			if globals.RealTime() > bailoutTime then
				Parsers.LogError(
					"Emergency bailout: processing time exceeded "
						.. Parsers.Config.TF2DB.EmergencyTimeoutSec
						.. " seconds"
				)
				return true
			end
			coroutine.yield(false)
		end
	end)

	-- Log initial memory usage
	if Parsers.Config.TF2DB.LogMemoryUsage then
		local memBefore = collectgarbage("count") / 1024
		print(string.format("[Parsers] Starting TF2DB processing, memory: %.2f MB", memBefore))
	end

	-- Process in chunks with memory tracking
	local count = Parsers.ProcessTF2DBChunks(content, database, source, bailoutTask)

	-- Log final memory usage
	if Parsers.Config.TF2DB.LogMemoryUsage then
		local memAfter = collectgarbage("count") / 1024
		print(string.format("[Parsers] Finished TF2DB processing, memory: %.2f MB", memAfter))
	end

	-- Content no longer needed, clear it immediately
	content = nil
	collectgarbage("collect")

	return count
end

-- Chunk-based parser that avoids creating any table of entries
function Parsers.ProcessTF2DBChunks(content, database, source, bailoutTask)
	local sourceName = source.name or "Unknown Source"
	local sourceCause = source.cause or "Unknown"

	-- Validate content
	if not content or #content == 0 then
		return 0
	end

	-- Initialize counters with direct variables (no tables)
	local count = 0
	local skipped = 0
	local invalid = 0
	local processed = 0
	local contentLen = #content

	-- Estimate total entries for progress reporting
	local estimatedTotal = math.floor(contentLen / 1024 * Parsers.Config.TF2DB.EstimateEntriesPerKB)

	-- Fast detection of SteamID format to optimize parsing strategy
	local hasSteamID64Format = content:match('"steamid":%s*"[0-9]+"')
	local hasSteamID3Format = content:match('"steamid":%s*"\\[U:1:[0-9]+\\]"')
	local hasSteamID2Format = content:match('"steamid":%s*"STEAM_0:[01]:[0-9]+"')

	-- Select the most appropriate pattern based on content
	local steamIDPattern = nil
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
	local namePattern = nil
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
	local chunkSize = Parsers.Config.TF2DB.ChunkSize

	-- Set up initial progress
	local lastProgressUpdate = globals.RealTime()

	while currentPos <= contentLen do
		-- Check for emergency bailout
		local shouldBail = false
		pcall(function()
			local _, bailResult = coroutine.resume(bailoutTask)
			shouldBail = bailResult == true
		end)

		if shouldBail then
			Tasks.message = "Emergency bailout: processed " .. count .. " entries"
			return count
		end

		-- Define the chunk
		local endPos = math.min(currentPos + chunkSize, contentLen)
		local chunk = content:sub(currentPos, endPos)
		local chunkLen = #chunk

		-- Fast mode for large files just scans for IDs without context
		if Parsers.Config.TF2DB.FastSkipMode and contentLen > 1000000 then
			-- Just directly match all SteamIDs in the chunk
			for steamID in chunk:gmatch(steamIDPattern) do
				-- Convert to SteamID64 if needed
				local steamID64 = steamID:match("^%d+$") and #steamID >= 15 and steamID
					or Parsers.ConvertToSteamID64(steamID)

				-- Add to database if valid and limit not reached
				if
					steamID64
					and not database.content[steamID64]
					and count < Parsers.Config.TF2DB.MaxEntriesPerSource
				then
					database.content[steamID64] = {
						Name = "Unknown", -- In fast mode we don't parse names
						proof = sourceCause,
					}
					count = count + 1
				elseif steamID64 then
					skipped = skipped + 1
				else
					invalid = invalid + 1
				end

				processed = processed + 1
			end
		else
			-- Regular chunk processing with name extraction
			local chunkPos = 1

			while chunkPos <= chunkLen do
				-- Find a steamID entry
				local steamIDStart, steamIDEnd, steamID = chunk:find(steamIDPattern, chunkPos)
				if not steamIDStart then
					break
				end

				-- Extract the steamID
				chunkPos = steamIDEnd + 1

				-- Find name near this steamID
				local name = "Unknown"

				-- Look within a reasonable range for name
				local nameSearchStart = math.max(1, steamIDStart - 100)
				local nameSearchEnd = math.min(chunkLen, steamIDEnd + 100)
				local nameStart, nameEnd, extractedName = chunk:find(namePattern, nameSearchStart, nameSearchEnd)

				if nameStart and extractedName then
					name = extractedName
				end

				-- Convert to SteamID64 if needed
				local steamID64 = steamID:match("^%d+$") and #steamID >= 15 and steamID
					or Parsers.ConvertToSteamID64(steamID)

				-- Add to database if valid and limit not reached
				if
					steamID64
					and not database.content[steamID64]
					and count < Parsers.Config.TF2DB.MaxEntriesPerSource
				then
					database.content[steamID64] = {
						Name = name,
						proof = sourceCause,
					}
					count = count + 1
				elseif steamID64 then
					skipped = skipped + 1
				else
					invalid = invalid + 1
				end

				processed = processed + 1
			end
		end

		-- Move to next chunk
		currentPos = endPos + 1

		-- Update progress periodically (don't flood UI updates)
		if globals.RealTime() - lastProgressUpdate > 0.25 then
			lastProgressUpdate = globals.RealTime()
			local progressPct = math.min(99, math.floor((processed / estimatedTotal) * 100))
			local entriesPerSec = processed / (globals.RealTime() - startTime)

			Tasks.message =
				string.format("%s: %d%% (%d entries @ %.0f/sec)", sourceName, progressPct, count, entriesPerSec)

			-- Update memory usage
			if Parsers.Config.TF2DB.LogMemoryUsage then
				local memNow = collectgarbage("count") / 1024
				print(string.format("[Parsers] Progress: %d%%, Memory: %.2f MB", progressPct, memNow))
			end

			coroutine.yield()
			collectgarbage("step", 200)
		end

		-- If we're approaching entry limit, bail out early
		if count >= Parsers.Config.TF2DB.MaxEntriesPerSource * 0.9 then
			Tasks.message = string.format(
				"Approaching limit of %d entries, completing early",
				Parsers.Config.TF2DB.MaxEntriesPerSource
			)
			break
		end
	end

	-- Final progress update
	Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid", sourceName, count, skipped, invalid)
	coroutine.yield()

	return count
end

-- New function to process JSON TF2DB data
function Parsers.ProcessTF2DBJson(jsonData, database, source)
	local sourceName = source.name or "Unknown Source"
	Tasks.message = "Processing " .. sourceName .. " JSON..."
	coroutine.yield()

	-- Track stats
	local count = 0
	local skipped = 0
	local invalid = 0
	local processed = 0

	-- Check for players array structure
	if type(jsonData.players) == "table" then
		local totalPlayers = #jsonData.players
		Tasks.message = "Processing " .. totalPlayers .. " players from " .. sourceName

		for _, player in ipairs(jsonData.players) do
			if type(player) == "table" then
				-- Extract SteamID from different formats
				local steamID64 = nil

				if player.steamid then
					steamID64 = Parsers.ConvertToSteamID64(player.steamid)
				elseif player.steamID64 then
					steamID64 = player.steamID64
				elseif player.attributes and player.attributes[1] == "cheater" then
					-- Special handling for certain JSON formats
					steamID64 = Parsers.ConvertToSteamID64(player.id)
				end

				-- Add to database if valid
				if steamID64 and not database.content[steamID64] then
					database.content[steamID64] = {
						Name = player.name or player.player_name or "Unknown",
						proof = source.cause,
					}

					pcall(function()
						playerlist.SetPriority(steamID64, 10)
					end)
					count = count + 1
				elseif steamID64 then
					skipped = skipped + 1
				else
					invalid = invalid + 1
				end
			end

			processed = processed + 1

			-- Yield occasionally to update progress
			if processed % Parsers.Config.YieldInterval == 0 or processed == totalPlayers then
				local progressPct = totalPlayers > 0 and math.floor((processed / totalPlayers) * 100) or 100
				Tasks.message =
					string.format("%s: %d%% (%d added, %d skipped)", sourceName, progressPct, count, skipped)
				coroutine.yield()
			end
		end
	else
		-- Handle other JSON structures
		Parsers.LogError("Unknown JSON structure for " .. sourceName)
	end

	Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid", sourceName, count, skipped, invalid)
	coroutine.yield()

	collectgarbage("collect")
	return count
end

-- New function specifically for handling bots.tf response
function Parsers.ProcessBotsTF(content, database, sourceName, sourceCause)
	-- Input validation with detailed errors
	if not content then
		Parsers.LogError("Empty content from " .. sourceName)
		return 0
	end

	if not database then
		Parsers.LogError("Invalid database object")
		return 0
	end

	Tasks.message = "Processing " .. sourceName .. "..."
	coroutine.yield()

	-- Initialize counters
	local count = 0
	local skipped = 0
	local invalid = 0
	local linesProcessed = 0

	-- First do a quick check of content type
	if type(content) ~= "string" then
		Parsers.LogError("Invalid content type: " .. type(content))
		return 0
	end

	-- bots.tf returns raw text with one SteamID64 per line
	-- It might have some empty lines or other data we need to filter

	-- Count lines for progress reporting
	local lines = {}
	local totalLines = 0

	-- Extract lines with error handling
	local success, errorMsg = pcall(function()
		for line in content:gmatch("[^\r\n]+") do
			-- Skip empty lines or lines that are obviously not SteamID64s
			line = line:match("^%s*(.-)%s*$") -- Trim whitespace
			if line ~= "" and #line >= 15 and #line <= 20 and line:match("^%d+$") then
				table.insert(lines, line)
				totalLines = totalLines + 1
			end
		end
	end)

	if not success then
		Parsers.LogError("Failed to parse lines from " .. sourceName, errorMsg)
		return 0
	end

	if totalLines == 0 then
		Parsers.LogError("No valid SteamID64s found in " .. sourceName, "Content length: " .. #content)
		return 0
	end

	Tasks.message = "Processing " .. totalLines .. " SteamID64s from " .. sourceName
	coroutine.yield()

	-- Process each line with robust error handling
	for i, steamID64 in ipairs(lines) do
		-- We should already have valid SteamID64s at this point

		-- Add to database if not duplicate
		if not database.content[steamID64] then
			database.content[steamID64] = {
				Name = "Unknown",
				proof = sourceCause,
			}

			-- Set player priority with error handling
			pcall(function()
				playerlist.SetPriority(steamID64, 10)
			end)
			count = count + 1
		else
			skipped = skipped + 1
		end

		linesProcessed = linesProcessed + 1

		-- Update progress periodically
		if linesProcessed % Parsers.Config.YieldInterval == 0 or linesProcessed == totalLines then
			local progressPct = math.floor((linesProcessed / totalLines) * 100)
			Tasks.message =
				string.format("Processing %s: %d%% (%d added, %d skipped)", sourceName, progressPct, count, skipped)
			coroutine.yield()
		end
	end

	Tasks.message = string.format("Finished %s: %d added, %d skipped", sourceName, count, skipped)
	coroutine.yield()

	-- Clear lines table to free memory
	lines = nil
	collectgarbage("collect")

	return count
end

-- New function for direct string operations only (no tables at all)
function Parsers.StringOnlyMode(enable)
	Parsers.Config.UseStringOnly = (enable ~= false)
	return Parsers.Config.UseStringOnly
end

-- New diagnostic function to detect memory issues
function Parsers.DiagnoseMemoryUse()
	local results = {
		totalMemory = collectgarbage("count") / 1024,
		gcPause = collectgarbage("setpause", 100), -- Get current and set to 100%
		gcStepmul = collectgarbage("setstepmul", 5000), -- Get current and set to 5000%
	}

	-- Force more aggressive GC
	collectgarbage("collect")
	collectgarbage("collect")

	-- Memory after collection
	results.memoryAfterGC = collectgarbage("count") / 1024
	results.memoryDifference = results.totalMemory - results.memoryAfterGC

	-- Restore original GC settings
	collectgarbage("setpause", results.gcPause)
	collectgarbage("setstepmul", results.gcStepmul)

	-- Output diagnostic info
	print("--- Memory Diagnostic ---")
	print(string.format("Total memory: %.2f MB", results.totalMemory))
	print(string.format("After GC: %.2f MB (saved %.2f MB)", results.memoryAfterGC, results.memoryDifference))
	print("------------------------")

	return results
end

-- Add emergency reset function
function Parsers.EmergencyReset()
	-- Unregister any parser callbacks to stop processing
	pcall(function()
		for _, name in ipairs({
			"FetcherMainTask",
			"FetcherCallback",
			"FetcherSingleSource",
			"TasksProcessCleanup",
			"DatabaseSave",
		}) do
			callbacks.Unregister("Draw", name)
		end
	end)

	-- Clear any temporary storage
	Parsers.TempStorage = setmetatable({}, { __mode = "kv" })

	-- Force aggressive GC
	collectgarbage("stop") -- Stop GC temporarily to avoid it running while we clean
	collectgarbage("collect")
	collectgarbage("collect")
	collectgarbage("restart") -- Restart GC

	print("[Parsers] Emergency reset performed")
end

return Parsers
