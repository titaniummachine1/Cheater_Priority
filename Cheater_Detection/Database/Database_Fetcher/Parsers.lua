local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Configuration for request timing
Parsers.Config = {
    RetryDelay = 4,         -- Initial delay between retries (seconds)
    RetryBackoff = 2,       -- Multiply delay by this factor on each retry
    RateLimitDelay = 2000,  -- Milliseconds to wait between requests (2 seconds)
    RequestTimeout = 10,    -- Maximum time to wait for a response (seconds)
    BatchSize = 200,        -- REDUCED: Number of entries to process in one batch (was 500)
    SourceDelay = 5000,     -- Milliseconds to wait between sources (5 seconds)
    YieldFrequency = 20     -- NEW: Yield every N items to prevent ruRBtree overflow
}

-- Memory management helpers
Parsers.Memory = {
    lastGC = 0,             -- Last garbage collection time
    gcInterval = 2,         -- REDUCED: Seconds between forced garbage collections (was 3)
    memoryThreshold = 25000, -- REDUCED: KB threshold to trigger extra GC (was 50MB)
    emergencyThreshold = 40000 -- NEW: Emergency cleanup threshold
}

-- More aggressive garbage collection with better handling
function Parsers.ForceGarbageCollection(immediate)
    local currentTime = globals.RealTime()
    local memUsage = collectgarbage("count")
    
    -- Emergency GC if memory usage exceeds threshold
    if memUsage > Parsers.Memory.emergencyThreshold then
        immediate = true
        Tasks.message = "Emergency memory cleanup in progress..."
    end
    
    -- Only GC if enough time has passed since last GC, unless immediate is specified
    if immediate or currentTime - Parsers.Memory.lastGC > Parsers.Memory.gcInterval then
        Tasks.message = "Memory cleanup in progress..."
        
        -- First yield to let the game breathe
        coroutine.yield()
        
        -- Store some metrics for logging
        local beforeMem = collectgarbage("count")
        
        -- Force a complete garbage collection cycle
        collectgarbage("stop")  -- Disable automatic collection
        collectgarbage("collect")
        Tasks.Sleep(50) -- Short yield to let the system process
        
        -- Do another collection for good measure
        collectgarbage("collect")
        Tasks.Sleep(50)
        
        -- Re-enable automatic collection
        collectgarbage("restart")
        
        -- Update last GC time
        Parsers.Memory.lastGC = currentTime
        
        -- Log memory details when debugging
        local afterMem = collectgarbage("count")
        if Parsers.Config.DebugMode then
            print(string.format("[Memory] Freed: %.2f MB (%.2f MB → %.2f MB)", 
                (beforeMem - afterMem)/1024, beforeMem/1024, afterMem/1024))
        end
        
        -- Return the current memory usage for monitoring
        return afterMem
    end
    
    return memUsage
end

-- Coroutine-compatible GET request with improved rate limiting
function Parsers.CoGet(url, retryCount)
    retryCount = retryCount or 3
    local retry = 0
    
    -- First wait for rate limit to respect API limits
    Tasks.message = "Rate limit delay before fetching..."
    Tasks.Sleep(Parsers.Config.RateLimitDelay)
    
    while retry < retryCount do
        Tasks.message = "Downloading from " .. url .. " (attempt " .. (retry + 1) .. "/" .. retryCount .. ")"
        
        -- Yield to allow game to render between attempts
        coroutine.yield()
        
        local success, response
        local timedOut = false
        
        -- Start a timer to detect timeouts
        local startTime = globals.RealTime()
        
        -- Make the HTTP request
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

-- Optimized CoParseBatch function to prevent ruRBtree overflow
function Parsers.CoParseBatch(content, database, sourceName, sourceCause)
    local count = 0
    local linesProcessed = 0
    local duplicateSkipped = 0
    local LINES_PER_BATCH = Parsers.Config.BatchSize -- Process this many before yielding/GC
    local YIELD_FREQUENCY = Parsers.Config.YieldFrequency -- Yield every N items
    
    -- Process directly without creating a huge table of lines
    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()
    
    -- Find total line count first
    local totalLines = 0
    for _ in content:gmatch("[^\r\n]+") do
        totalLines = totalLines + 1
    end
    
    -- Process in smaller chunks
    local currentBatch = 0
    local linesInCurrentBatch = 0
    local lineCount = 0
    
    -- Process line by line to avoid storing all lines in memory
    for line in content:gmatch("[^\r\n]+") do
        lineCount = lineCount + 1
        linesProcessed = linesProcessed + 1
        
        -- Trim whitespace directly without storing
        line = line:match("^%s*(.-)%s*$")
        
        -- Skip comments and empty lines
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            -- Check if it's a valid SteamID64 (should be a 17-digit number)
            if line:match("^%d+$") and #line == 17 then
                local steamID64 = line
                
                -- Use direct index lookups instead of intermediate variables
                if not database.content[steamID64] then
                    -- Only add if not already in database
                    database.content[steamID64] = {
                        Name = "Unknown",
                        proof = sourceCause,
                        source = sourceName
                    }
                    
                    -- Set player priority
                    playerlist.SetPriority(steamID64, 10)
                    count = count + 1
                else
                    duplicateSkipped = duplicateSkipped + 1
                end
            end
        end
        
        linesInCurrentBatch = linesInCurrentBatch + 1
        
        -- Yield more frequently to prevent ruRBtree overflow
        if linesInCurrentBatch % YIELD_FREQUENCY == 0 then
            coroutine.yield()
        end
        
        -- After processing a batch, perform garbage collection
        if linesInCurrentBatch >= LINES_PER_BATCH then
            currentBatch = currentBatch + 1
            
            -- Update progress message and yield
            Tasks.message = string.format("Processing %s... %d/%d lines (%d added, %d skipped)", 
                sourceName, linesProcessed, totalLines, count, duplicateSkipped)
            
            -- Force GC after each batch
            Parsers.ForceGarbageCollection(true)
            
            -- Reset batch counter
            linesInCurrentBatch = 0
            
            -- Important yield point to prevent ruRBtree overflow
            coroutine.yield()
        end
    end
    
    -- Final progress update
    Tasks.message = string.format("Finished %s: %d added, %d skipped", 
        sourceName, count, duplicateSkipped)
    
    -- Final cleanup
    content = nil -- Clear the content reference
    Parsers.ForceGarbageCollection(true)
    
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

-- Optimized fetching to prevent memory issues
function Parsers.CoFetchSource(source, database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end
    
    -- Initial cleanup before starting new source
    Parsers.ForceGarbageCollection(true)
    
    Tasks.message = "Preparing to fetch from " .. source.name .. "..."
    coroutine.yield() -- Give UI a chance to update
    
    -- Apply a delay between sources
    Tasks.message = "Waiting for rate limit cooldown..."
    Tasks.Sleep(Parsers.Config.SourceDelay)
    
    Tasks.message = "Fetching from " .. source.name .. "..."
    local content = Parsers.CoGet(source.url)
    
    if not content or #content == 0 then
        print("[Database Fetcher] Failed to fetch from " .. source.name)
        return 0
    end
    
    -- GC before parsing
    Parsers.ForceGarbageCollection(true)
    
    -- Parse the content based on the specified parser
    local count = 0
    
    if source.parser == "raw" then
        -- Process raw list with optimized batch processing
        count = Parsers.CoParseBatch(content, database, source.name, source.cause)
        
        -- Important: Clear content reference to free memory
        content = nil
        collectgarbage("collect")
    elseif source.parser == "tf2db" then
        -- For JSON content, process differently to avoid memory issues
        Tasks.message = "Parsing JSON data from " .. source.name
        coroutine.yield()
        
        -- Parse JSON in a pcall with immediate cleanup
        local success, data = pcall(function()
            -- Parse JSON
            local result = Json.decode(content)
            
            -- Immediately clear the content to free memory
            content = nil
            collectgarbage("collect")
            
            return result
        end)
        
        -- Force GC after JSON parsing
        Parsers.ForceGarbageCollection(true)
        
        if success and data and data.players then
            local players = data.players
            local playerCount = #players
            
            -- Process in smaller batches
            local batchSize = math.min(Parsers.Config.BatchSize, 100) -- Smaller batches for JSON
            for i = 1, playerCount, batchSize do
                local batchEnd = math.min(i + batchSize - 1, playerCount)
                Tasks.message = "Processing " .. source.name .. "... batch " .. 
                    math.ceil(i/batchSize) .. "/" .. math.ceil(playerCount/batchSize)
                
                local batchCount = 0
                
                -- Process this batch
                for j = i, batchEnd do
                    local player = players[j]
                    
                    -- Yield more frequently
                    if (j - i) % Parsers.Config.YieldFrequency == 0 then
                        coroutine.yield()
                    end
                    
                    if player and player.steamid then
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
                                proof = source.cause,
                                source = source.name
                            }
                            
                            playerlist.SetPriority(steamID64, 10)
                            count = count + 1
                            batchCount = batchCount + 1
                        end
                    end
                end
                
                -- After processing a batch, force GC
                Tasks.message = "Processed " .. math.min(batchEnd, playerCount) .. "/" .. playerCount .. 
                    " players (" .. count .. " added this batch: " .. batchCount .. ")"
                
                -- Force GC and yield
                Parsers.ForceGarbageCollection(true)
                coroutine.yield()
            end
            
            -- Clear the players table to free memory
            data.players = nil
        else
            print("[Database Fetcher] Failed to parse TF2DB format JSON from " .. source.name)
        end
    end
    
    -- Wait a bit after processing to stabilize game before next source
    Tasks.message = "Finished processing " .. source.name .. " (added " .. count .. " entries)"
    Tasks.Sleep(500)
    
    -- Run GC before returning
    Parsers.ForceGarbageCollection(true)
    
    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
    return count
end

return Parsers
