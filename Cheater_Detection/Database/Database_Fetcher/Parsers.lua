-- Enhanced parsers with retry logic and better error handling

local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Configuration (enhanced)
Parsers.Config = {
    RetryDelay = 4,      -- Initial delay between retries (seconds)
    RetryBackoff = 2,    -- Multiply delay by this factor on each retry
    RequestTimeout = 10, -- Maximum time to wait for a response (seconds)
    YieldInterval = 500, -- Yield after processing this many items
    MaxRetries = 3,      -- Maximum number of retry attempts
    RetryOnEmpty = true  -- Retry if response is empty
}

-- Improved HTTP download with retry logic and better error handling
function Parsers.Download(url, retryCount)
    retryCount = retryCount or Parsers.Config.MaxRetries
    local retry = 0
    local lastError = nil

    while retry < retryCount do
        Tasks.message = "Downloading from " .. url .. " (attempt " .. (retry + 1) .. "/" .. retryCount .. ")"
        coroutine.yield()

        -- Start a timer to detect timeouts
        local startTime = globals.RealTime()
        local requestTimedOut = false

        -- Create a timeout checker
        local timeoutCheckerId = "request_timeout_" .. tostring(math.random(1000000))
        callbacks.Register("Draw", timeoutCheckerId, function()
            if globals.RealTime() - startTime > Parsers.Config.RequestTimeout then
                requestTimedOut = true
                callbacks.Unregister("Draw", timeoutCheckerId)
            end
        end)

        -- Attempt the HTTP request
        local success, response
        success, response = pcall(http.Get, url)

        -- Unregister the timeout checker
        callbacks.Unregister("Draw", timeoutCheckerId)

        -- Process the result
        if requestTimedOut then
            lastError = "Request timed out"
        elseif not success then
            lastError = tostring(response)
        elseif not response or #response == 0 then
            if Parsers.Config.RetryOnEmpty then
                lastError = "Empty response"
            else
                return "" -- Return empty string if empty responses are acceptable
            end
        else
            -- Success! Return the response
            return response
        end

        -- Failed, try again
        retry = retry + 1
        if retry < retryCount then
            -- Wait with exponential backoff
            local waitTime = Parsers.Config.RetryDelay * (Parsers.Config.RetryBackoff ^ (retry - 1))
            Tasks.message = "Download failed (" .. lastError .. "). Retrying in " .. waitTime .. " seconds..."

            -- Wait with a countdown
            local startWait = globals.RealTime()
            while globals.RealTime() < startWait + waitTime do
                local remaining = math.ceil((startWait + waitTime) - globals.RealTime())
                Tasks.message = "Retry in " .. remaining .. "s (" .. lastError .. ")..."
                coroutine.yield()
            end
        end
    end

    -- All retries failed
    print("[Database Fetcher] Download failed after " .. retryCount .. " attempts: " .. (lastError or "Unknown error"))
    return nil
end

-- Improved ConvertToSteamID64 with better error handling
function Parsers.ConvertToSteamID64(steamid)
    if not steamid then return nil end

    -- If already a SteamID64, just return it
    if type(steamid) == "string" and steamid:match("^%d+$") and #steamid == 17 then
        return steamid
    end

    -- Try direct conversion with error handling
    local success, result = pcall(function()
        return steam.ToSteamID64(tostring(steamid))
    end)

    if success and result and #result == 17 then
        return result
    end

    -- Manual conversion for SteamID3
    if type(steamid) == "string" and steamid:match("^%[U:1:%d+%]$") then
        local accountID = steamid:match("%[U:1:(%d+)%]")
        if accountID then
            local steamID64 = tostring(76561197960265728 + tonumber(accountID))
            -- Validate the result
            if #steamID64 == 17 and steamID64:match("^%d+$") then
                return steamID64
            end
        end
    end

    return nil
end

-- Process raw ID list - with improved error handling and progress reporting
function Parsers.ProcessRawList(content, database, sourceName, sourceCause)
    if not content or not database then return 0 end

    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()

    local count = 0
    local skipped = 0
    local invalid = 0
    local linesProcessed = 0
    local totalLines = 0

    -- First count the lines to provide better progress reporting
    for _ in content:gmatch("[^\r\n]+") do
        totalLines = totalLines + 1
        if totalLines % 1000 == 0 then
            Tasks.message = "Counting lines in " .. sourceName .. "... (" .. totalLines .. ")"
            coroutine.yield()
        end
    end

    Tasks.message = "Processing " .. totalLines .. " lines from " .. sourceName
    coroutine.yield()

    -- Process all lines with periodic updates
    for line in content:gmatch("[^\r\n]+") do
        -- Trim and filter with error handling
        local trimmedLine = line
        pcall(function()
            trimmedLine = line:match("^%s*(.-)%s*$") or ""
        end)

        -- Skip comments and empty lines
        if trimmedLine ~= "" and not trimmedLine:match("^%-%-") and not trimmedLine:match("^#") then
            -- Convert ID format if needed
            local steamID64 = Parsers.ConvertToSteamID64(trimmedLine)

            -- Add to database if valid and not duplicate
            if steamID64 and not database.content[steamID64] then
                database.content[steamID64] = {
                    Name = "Unknown",
                    proof = sourceCause
                }

                -- Set player priority
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

        linesProcessed = linesProcessed + 1

        -- Update progress periodically
        if linesProcessed % Parsers.Config.YieldInterval == 0 or linesProcessed == totalLines then
            local progressPct = math.floor((linesProcessed / totalLines) * 100)
            Tasks.message = string.format("Processing %s... %d%% (%d added, %d skipped, %d invalid)",
                sourceName, progressPct, count, skipped, invalid)
            coroutine.yield()
        end
    end

    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        sourceName, count, skipped, invalid)
    coroutine.yield()

    -- Clean up
    collectgarbage("collect")

    return count
end

-- Process a source with improved error handling
function Parsers.ProcessSource(source, database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end

    Tasks.message = "Fetching from " .. source.name .. "..."
    local content = Parsers.Download(source.url)

    if not content or #content == 0 then
        print("[Database Fetcher] Failed to fetch from " .. source.name)
        return 0
    end

    -- Process based on parser type with error handling
    local count = 0
    local success = false

    success, count = pcall(function()
        if source.parser == "raw" then
            return Parsers.ProcessRawList(content, database, source.name, source.cause)
        elseif source.parser == "tf2db" then
            return Parsers.ProcessTF2DB(content, database, source)
        else
            print("[Database Fetcher] Unknown parser type: " .. source.parser)
            return 0
        end
    end)

    -- Clear content to free memory
    content = nil
    collectgarbage("collect")

    if not success then
        print("[Database Fetcher] Error processing " .. source.name .. ": " .. tostring(count))
        return 0
    end

    return count
end

-- Simplified TF2DB parser that can handle large files better
function Parsers.ProcessTF2DB(content, database, source)
    if not content or not database then return 0 end

    Tasks.message = "Processing " .. source.name .. "..."
    coroutine.yield()

    -- Variables for tracking
    local count = 0
    local skipped = 0
    local invalid = 0
    local processed = 0

    -- Estimate total entries by counting steamid patterns
    local totalEntries = 0
    local pos = 1
    while true do
        local nextPos = content:find('"steamid":', pos)
        if not nextPos then break end
        totalEntries = totalEntries + 1
        pos = nextPos + 10

        if totalEntries % 1000 == 0 then
            Tasks.message = "Counting entries in " .. source.name .. "... (" .. totalEntries .. ")"
            coroutine.yield()
        end
    end

    Tasks.message = "Processing " .. totalEntries .. " entries from " .. source.name
    coroutine.yield()

    -- Direct string parsing approach for better performance
    local currentIndex = 1
    local contentLength = #content

    while currentIndex < contentLength do
        -- Find next steamid entry
        local steamIDStart = content:find('"steamid":%s*"', currentIndex)
        if not steamIDStart then break end

        -- Extract steamid
        currentIndex = steamIDStart + 10
        local steamIDEnd = content:find('"', currentIndex)
        if not steamIDEnd then break end

        local steamID = content:sub(currentIndex, steamIDEnd - 1)
        currentIndex = steamIDEnd + 1

        -- Convert to SteamID64
        local steamID64 = Parsers.ConvertToSteamID64(steamID)

        -- Add to database if valid
        if steamID64 and not database.content[steamID64] then
            database.content[steamID64] = {
                Name = "Unknown",
                proof = source.cause
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

        processed = processed + 1

        -- Update progress periodically
        if processed % Parsers.Config.YieldInterval == 0 or processed >= totalEntries then
            local progressPct = math.floor((processed / totalEntries) * 100)
            Tasks.message = string.format("Processing %s... %d%% (%d added, %d skipped, %d invalid)",
                source.name, progressPct, count, skipped, invalid)
            coroutine.yield()
        end
    end

    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        source.name, count, skipped, invalid)
    coroutine.yield()

    -- Clean up
    collectgarbage("collect")

    return count
end

return Parsers
