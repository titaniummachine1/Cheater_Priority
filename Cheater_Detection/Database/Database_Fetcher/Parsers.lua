local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Configuration for request timing
Parsers.Config = {
    RetryDelay = 4,        -- Initial delay between retries (seconds)
    RetryBackoff = 2,      -- Multiply delay by this factor on each retry
    RateLimitDelay = 700, -- Milliseconds to wait between requests (4 seconds)
    RequestTimeout = 400    -- Maximum time to wait for a response (seconds)
}

-- Memory management helpers
Parsers.Memory = {
    lastGC = 0,           -- Last garbage collection time
    gcInterval = 3,      -- Seconds between forced garbage collections
    batchSize = 100,      -- Number of entries to process before yielding/GC
    memoryThreshold = 50000 -- KB threshold to trigger extra GC (50MB)
}

-- Force garbage collection with yield to prevent freezes
function Parsers.ForceGarbageCollection(immediate)
    local currentTime = globals.RealTime()
    
    -- Only GC if enough time has passed since last GC, unless immediate is specified
    if immediate or currentTime - Parsers.Memory.lastGC > Parsers.Memory.gcInterval then
        Tasks.message = "Memory cleanup in progress..."
        
        -- First yield to let the game breathe
        coroutine.yield()
        
        -- Force a complete garbage collection cycle
        collectgarbage("collect")
        
        -- Wait a bit to let system clean up
        Tasks.Sleep(200)
        
        -- Do another collection for good measure
        collectgarbage("collect")
        
        Parsers.Memory.lastGC = currentTime
        
        -- Return the current memory usage for monitoring
        return collectgarbage("count")
    end
    
    return collectgarbage("count")
end

-- Coroutine-compatible GET request with improved rate limiting
function Parsers.CoGet(url, retryCount)
    retryCount = retryCount or 3
    local retry = 0

    -- First wait for rate limit to respect GitHub's limits
    Tasks.message = "Rate limit delay before fetching..."
    Tasks.Sleep(Parsers.Config.RateLimitDelay)

    while retry < retryCount do
        Tasks.message = "Downloading from " .. url .. " (attempt " .. (retry + 1) .. "/" .. retryCount .. ")"

        -- Yield to allow game to render between attempts
        coroutine.yield()

        local success, response, responseCode

        -- Set a timer to detect timeouts
        local startTime = globals.RealTime()
        local timedOut = false

        -- Start a separate coroutine for the HTTP request
        success, response = pcall(http.Get, url)

        if success and response and #response > 0 then
            -- Add delay after successful request to be nice to the server
            Tasks.message = "Request completed, waiting to respect rate limits..."
            Tasks.Sleep(Parsers.Config.RateLimitDelay)
            return response
        end

        retry = retry + 1

        -- If we need to retry, wait with exponential backoff
        if retry < retryCount then
            local waitTime = Parsers.Config.RetryDelay * (Parsers.Config.RetryBackoff ^ (retry - 1))
            Tasks.message = string.format("Request failed. Retrying in %d seconds...", waitTime)

            local startWait = globals.RealTime()
            while globals.RealTime() < startWait + waitTime do
                local remaining = math.ceil((startWait + waitTime) - globals.RealTime())
                Tasks.message = string.format("Retry cooldown: %d seconds remaining...", remaining)
                coroutine.yield()
            end
        else
            Tasks.message = "All retry attempts failed."
            Tasks.Sleep(1000) -- Short delay to show the failure message
        end
    end

    return nil
end

-- Download a single list with coroutine support
function Parsers.CoDownloadList(url, filename)
    -- Base path and import path
    local basePath = string.format("Lua %s", GetScriptName():match("([^/\\]+)%.lua$"):gsub("%.lua$", ""))
    local importPath = basePath .. "/import/"

    -- Ensure directory exists
    local success, dirPath = pcall(filesystem.CreateDirectory, importPath)
    if not success then
        print("[Database Fetcher] Failed to create import directory")
        return false
    end

    -- Download the content
    Tasks.message = "Downloading from " .. url .. "..."
    local content = Parsers.CoGet(url)

    if not content or #content == 0 then
        print("[Database Fetcher] Download failed")
        return false
    end

    -- Save to file
    Tasks.message = "Saving to " .. filename .. "..."
    coroutine.yield()

    local filepath = importPath .. filename
    local success, file = pcall(io.open, filepath, "w")

    if not success or not file then
        print("[Database Fetcher] Failed to create file: " .. filepath)
        return false
    end

    file:write(content)
    file:close()

    print(string.format("[Database Fetcher] Successfully downloaded to %s", filepath))
    return true
end

-- Parse a raw list of SteamID64s with coroutine support and memory management
function Parsers.CoParseBatch(content, database, sourceName, sourceCause)
    local date = os.date("%Y-%m-%d %H:%M:%S")
    local count = 0
    local linesProcessed = 0
    local duplicateSkipped = 0
    local LINES_PER_BATCH = Parsers.Memory.batchSize -- Process this many before GC
    
    -- First break content into smaller chunks to avoid memory issues
    local lines = {}
    local lineCount = 0
    
    Tasks.message = "Preprocessing " .. sourceName .. "..."
    
    -- Split content into lines and process in batches
    for line in content:gmatch("[^\r\n]+") do
        lineCount = lineCount + 1
        lines[lineCount] = line:match("^%s*(.-)%s*$") -- trim whitespace
        
        -- If we've accumulated enough lines, process this batch
        if lineCount % LINES_PER_BATCH == 0 then
            Tasks.message = "Preprocessing " .. sourceName .. "... " .. lineCount .. " lines"
            coroutine.yield()
        end
    end
    
    -- Clear content to free memory - we don't need the raw content anymore
    content = nil
    
    -- Force GC after preprocessing
    Tasks.message = "Cleanup after preprocessing..."
    Parsers.ForceGarbageCollection(true)
    
    -- Now process the lines in smaller batches
    for i = 1, lineCount do
        local line = lines[i]
        lines[i] = nil -- Immediately clear reference to save memory
        
        -- Skip comments and empty lines
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            -- Check if it's a valid SteamID64 (should be a 17-digit number)
            if line:match("^%d+$") and #line == 17 then
                local steamID64 = line
                local existingData = database.content[steamID64]

                -- Only add if not already in database with same cause
                if not existingData then
                    -- Entry doesn't exist at all, add it
                    database.content[steamID64] = {
                        Name = "Unknown",
                        cause = sourceCause,
                        date = date,
                        source = sourceName
                    }
                    playerlist.SetPriority(steamID64, 10)
                    count = count + 1
                elseif existingData.cause ~= sourceCause then
                    -- Entry exists but has different cause, keep record but update fields
                    existingData.source = sourceName .. ", " .. (existingData.source or "")
                    existingData.date = date -- Update to most recent date
                    database.content[steamID64] = existingData
                    duplicateSkipped = duplicateSkipped + 1
                else
                    -- Skip duplicates with same cause
                    duplicateSkipped = duplicateSkipped + 1
                end
            end
        end
        
        -- Periodically yield and GC to avoid memory buildup
        linesProcessed = linesProcessed + 1
        if linesProcessed % LINES_PER_BATCH == 0 then
            Tasks.message = "Processing " .. sourceName .. "... " 
                .. linesProcessed .. "/" .. lineCount 
                .. " lines (" .. count .. " added)"
            
            -- Force garbage collection periodically
            local memUsage = Parsers.ForceGarbageCollection()
            
            -- If memory usage is high, do extra GC cycles
            if memUsage > Parsers.Memory.memoryThreshold then
                Tasks.message = "High memory usage detected, performing cleanup..."
                Tasks.Sleep(500) -- Give more time to clean up
                collectgarbage("collect")
                Tasks.Sleep(500)
            end
        end
    end
    
    -- Clear lines array to free memory
    lines = nil
    
    -- Final cleanup
    Parsers.ForceGarbageCollection(true)
    
    if duplicateSkipped > 0 then
        print(string.format("[Database Fetcher] Skipped %d duplicate entries from %s", 
            duplicateSkipped, sourceName))
    end

    return count
end

-- Parse normal version (non-coroutine) of the raw list parser
function Parsers.ParseRawIDList(content, database, sourceName, sourceCause)
    if not content or not database then return 0 end

    local date = os.date("%Y-%m-%d %H:%M:%S")
    local count = 0

    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace

        -- Skip comments and empty lines
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            -- Check if it's a valid SteamID64 (should be a 17-digit number)
            if line:match("^%d+$") and #line == 17 then
                local steamID64 = line
                local existingData = database.content[steamID64]

                if not existingData then
                    -- Only add if not already in database
                    database.content[steamID64] = {
                        Name = "Unknown",
                        cause = sourceCause,
                        date = date,
                        source = sourceName
                    }

                    -- Flag player in playerlist
                    playerlist.SetPriority(steamID64, 10)
                    count = count + 1
                end
            end
        end
    end

    return count
end

-- Parse TF2DB format (normal version)
function Parsers.ParseTF2DB(content, database, sourceName, sourceCause)
    if not content or not database then return 0 end

    local count = 0
    local success, data = pcall(Json.decode, content)

    if not success or not data or not data.players then
        print("[Database Fetcher] Failed to parse TF2DB format JSON")
        return 0
    end

    local date = os.date("%Y-%m-%d %H:%M:%S")

    for _, player in ipairs(data.players) do
        if player.steamid then
            local steamID64

            -- Convert to SteamID64 if needed
            if player.steamid:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("STEAM_0:%d:%d+") then
                steamID64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") and #player.steamid == 17 then
                steamID64 = player.steamid -- Already SteamID64
            end

            if steamID64 and not database.content[steamID64] then
                database.content[steamID64] = {
                    Name = "Unknown",
                    cause = sourceCause,
                    date = date,
                    source = sourceName
                }

                playerlist.SetPriority(steamID64, 10)
                count = count + 1
            end
        end
    end

    return count
end

-- Fetch from a specific source with coroutine support and memory management
function Parsers.CoFetchSource(source, database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end
    
    -- Initial cleanup before starting new source
    Parsers.ForceGarbageCollection(true)
    
    Tasks.message = "Preparing to fetch from " .. source.name .. "..."
    coroutine.yield() -- Give UI a chance to update
    
    -- First apply a delay to respect rate limits between sources
    Tasks.message = "Waiting for rate limit cooldown..."
    Tasks.Sleep(Parsers.Config.RateLimitDelay)
    
    Tasks.message = "Fetching from " .. source.name .. "..."
    local content = Parsers.CoGet(source.url)
    
    if not content or #content == 0 then
        print("[Database Fetcher] Failed to fetch from " .. source.name)
        return 0
    end
    
    -- GC before parsing to ensure we have memory available
    Parsers.ForceGarbageCollection(true)
    
    -- Parse the content based on the specified parser
    local count = 0
    
    if source.parser == "raw" then
        -- For raw lists, process with memory-optimized batch processor
        count = Parsers.CoParseBatch(content, database, source.name, source.cause)
        
        -- Clear content reference to free memory
        content = nil
        
    elseif source.parser == "tf2db" then
        -- For JSON content, parse in chunks with memory management
        Tasks.message = "Parsing JSON data from " .. source.name
        coroutine.yield()
        
        local success, data
        
        -- Wrap JSON parsing in a protected call with cleanup
        Tasks.message = "Decoding JSON data..."
        success, data = pcall(function()
            local result = Json.decode(content)
            -- Clear content to free memory immediately after parsing
            content = nil
            Parsers.ForceGarbageCollection(true)
            return result
        end)
        
        if success and data and data.players then
            local players = data.players
            local playerCount = #players
            local date = os.date("%Y-%m-%d %H:%M:%S")
            local processed = 0
            
            -- Process in smaller batches with cleanup between batches
            local batchSize = 50
            for i = 1, playerCount, batchSize do
                local batchEnd = math.min(i + batchSize - 1, playerCount)
                
                for j = i, batchEnd do
                    local player = players[j]
                    processed = processed + 1
                    
                    if player.steamid then
                        local steamID64
                        
                        -- Convert to SteamID64 if needed
                        if player.steamid:match("^%[U:1:%d+%]$") then
                            steamID64 = steam.ToSteamID64(player.steamid)
                        elseif player.steamid:match("STEAM_0:%d:%d+") then
                            steamID64 = steam.ToSteamID64(player.steamid)
                        elseif player.steamid:match("^%d+$") and #player.steamid == 17 then
                            steamID64 = player.steamid -- Already SteamID64
                        end
                        
                        if steamID64 and not database.content[steamID64] then
                            database.content[steamID64] = {
                                Name = "Unknown",
                                cause = source.cause,
                                date = date,
                                source = source.name
                            }
                            
                            playerlist.SetPriority(steamID64, 10)
                            count = count + 1
                        end
                    end
                end
                
                -- Update progress and force GC between batches
                Tasks.message = string.format("Processing %s... %d/%d players (%d added)",
                    source.name, processed, playerCount, count)
                
                -- Run GC and yield
                Parsers.ForceGarbageCollection()
            end
            
            -- Clear players table reference
            players = nil
            data = nil
            
        else
            print("[Database Fetcher] Failed to parse TF2DB format JSON from " .. source.name)
        end
        
        -- Force final cleanup
        Parsers.ForceGarbageCollection(true)
    end
    
    -- Wait a bit after processing to stabilize game before next source
    Tasks.message = "Finished processing " .. source.name .. " (added " .. count .. " entries)"
    Tasks.Sleep(500)
    
    -- Run GC before returning
    Parsers.ForceGarbageCollection(true)
    
    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
    return count
end

-- Add a simple function to update database paths in Lua system
function Parsers.FixDatabasePaths()
    local possiblePaths = {
        "Lua Cheater_Detection",
        "Lua Scripts/Cheater_Detection",
        "lbox/Cheater_Detection",
        "lmaobox/Cheater_Detection",
        "."
    }
    
    -- Check each path and try to create it
    for _, path in ipairs(possiblePaths) do
        if pcall(filesystem.CreateDirectory, path) then
            print("[Database Fetcher] Successfully created directory: " .. path)
            return path
        end
    end
    
    return nil
end

return Parsers
