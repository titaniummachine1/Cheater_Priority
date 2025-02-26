local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Configuration for request timing
Parsers.Config = {
    RetryDelay = 4,        -- Initial delay between retries (seconds)
    RetryBackoff = 2,      -- Multiply delay by this factor on each retry
    RateLimitDelay = 2000, -- Milliseconds to wait between requests (2 seconds)
    RequestTimeout = 10,   -- Maximum time to wait for a response (seconds)
    BatchSize = 50,        -- REDUCED FURTHER: Even smaller batch size (was 100)
    SourceDelay = 5000,    -- Milliseconds to wait between sources (5 seconds)
    YieldFrequency = 5,    -- REDUCED FURTHER: Much more frequent yields (was 10)
    UseWeakTables = true,  -- NEW: Use weak tables for temporary data
    JsonBatchSize = 10,    -- REDUCED FURTHER: Ultra-small batch size for JSON processing (was 25)
    JsonYieldFrequency = 3 -- REDUCED FURTHER: Even more frequent yields for JSON (was 5)
}

-- Memory management helpers
Parsers.Memory = {
    lastGC = 0,                -- Last garbage collection time
    gcInterval = 7,            -- REDUCED: Seconds between forced garbage collections (was 3)
    memoryThreshold = 2000,   -- REDUCED: KB threshold to trigger extra GC (was 50MB)
    emergencyThreshold = 3000 -- NEW: Emergency cleanup threshold
}

-- More balanced garbage collection with incremental approach
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

        -- Set temporary tables to nil to help GC
        Parsers._tempData = nil

        -- Use incremental GC instead of stop/restart approach
        for i = 1, 10 do  -- Run several steps for thorough collection
            collectgarbage("step", 100)  -- Collect in smaller steps
            if i % 3 == 0 then  -- Yield occasionally during collection
                coroutine.yield()
            end
        end
        
        -- Finish with one full collection for completeness
        collectgarbage("collect")

        -- Update last GC time
        Parsers.Memory.lastGC = currentTime

        -- Log memory details when debugging
        local afterMem = collectgarbage("count")
        if Parsers.Config.DebugMode then
            print(string.format("[Memory] Freed: %.2f MB (%.2f MB → %.2f MB)",
                (beforeMem - afterMem) / 1024, beforeMem / 1024, afterMem / 1024))
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

-- Improved SteamID converter that uses direct API call for all formats
function Parsers.ConvertToSteamID64(steamid)
    if not steamid then return nil end
    
    -- If already a SteamID64, just return it
    if steamid:match("^%d+$") and #steamid == 17 then
        return steamid
    end
    
    -- Try direct conversion for all formats
    local success, result = pcall(steam.ToSteamID64, steamid)
    if success and result and #result == 17 then
        return result
    end
    
    -- Fallback for SteamID3 format if the API call fails
    if steamid:match("^%[U:1:%d+%]$") then
        local accountID = steamid:match("%[U:1:(%d+)%]")
        if accountID then
            return tostring(76561197960265728 + tonumber(accountID))
        end
    end
    
    return nil
end

-- Ultra-optimized batch processing for raw ID lists
function Parsers.CoParseBatch(content, database, sourceName, sourceCause)
    local count = 0
    local linesProcessed = 0
    local duplicateSkipped = 0
    
    -- Use reduced batch sizes to prevent lag
    local LINES_PER_BATCH = Parsers.Config.BatchSize      
    local YIELD_FREQUENCY = Parsers.Config.YieldFrequency
    
    -- Process directly without creating tables of lines
    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()
    
    -- Count total lines first - use a weak table for line counting
    local totalLines = 0
    do
        -- Local scope to help garbage collection
        for _ in content:gmatch("[^\r\n]+") do
            totalLines = totalLines + 1
            -- Much more frequent yields while counting
            if totalLines % 500 == 0 then
                coroutine.yield()
            end
        end
    end
    
    -- Setup progress tracking for this source
    Tasks.SetupSourceBatches({name = sourceName}, totalLines, LINES_PER_BATCH)
    
    -- Process in smaller chunks with weak tables for each batch
    local currentBatch = 0
    local linesInCurrentBatch = 0
    local batchCount = math.ceil(totalLines / LINES_PER_BATCH)
    
    -- Create a weak table for temporary storage
    local weakBatch = setmetatable({}, {__mode = "v"})
    
    -- Process line by line to avoid storing all lines in memory
    for line in content:gmatch("[^\r\n]+") do
        linesProcessed = linesProcessed + 1
        
        -- Trim whitespace directly
        line = line:match("^%s*(.-)%s*$")
        
        -- Skip comments and empty lines
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            -- Check if it's a valid SteamID64 or can be converted
            local steamID64 = line
            
            -- Convert if needed using optimized function
            if not (line:match("^%d+$") and #line == 17) then
                steamID64 = Parsers.ConvertToSteamID64(line)
            end
            
            -- Add to database if valid
            if steamID64 and not database.content[steamID64] then
                -- Only add if not already in database - minimal data structure
                database.content[steamID64] = {
                    Name = "Unknown",
                    proof = sourceCause
                }
                
                -- Set player priority
                playerlist.SetPriority(steamID64, 10)
                count = count + 1
            else
                duplicateSkipped = duplicateSkipped + 1
            end
        end
        
        -- Clear the line variable to help GC
        line = nil
        
        linesInCurrentBatch = linesInCurrentBatch + 1
        
        -- FIX: Changed linesProcessedInBatch to linesInCurrentBatch
        if linesInCurrentBatch % YIELD_FREQUENCY == 0 then
            coroutine.yield()
        end
        
        -- After processing a batch, perform garbage collection
        if linesInCurrentBatch >= LINES_PER_BATCH then
            currentBatch = currentBatch + 1
            
            -- Update batch completion for progress tracking
            Tasks.BatchCompleted()
            
            -- Update progress message and yield
            Tasks.message = string.format("Processing %s... batch %d/%d (%d added, %d skipped)",
                sourceName, currentBatch, batchCount, count, duplicateSkipped)
            
            -- Force GC after each batch - very aggressive
            Parsers.ForceGarbageCollection(true)
            
            -- Reset batch counter and clear weak batch table
            linesInCurrentBatch = 0
            for k in pairs(weakBatch) do weakBatch[k] = nil end
            
            -- Important yield point to prevent ruRBtree overflow
            coroutine.yield()
            
            -- Run a second collection after yield
            collectgarbage("collect")
        end
    end
    
    -- Final progress update
    Tasks.message = string.format("Finished %s: %d added, %d skipped",
        sourceName, count, duplicateSkipped)
    
    -- Mark source as completed for progress tracking
    Tasks.SourceCompleted()
    
    -- Final cleanup - use weak tables for all temporary data
    content = nil -- Clear the content reference
    Parsers.ForceGarbageCollection(true)
    
    -- Set all locals to nil explicitly
    weakBatch = nil
    totalLines = nil
    currentBatch = nil
    linesInCurrentBatch = nil
    linesProcessed = nil
    duplicateSkipped = nil
    
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

-- Optimized TF2DB JSON parser using string manipulation
function Parsers.CoFetchTF2DB(content, database, source)
    -- Direct string parser for TF2DB format - no JSON decode to avoid memory issues
    Tasks.message = "Parsing TF2DB data from " .. source.name
    coroutine.yield()
    
    -- Initialize parsing state using weak tables
    local contentLength = #content
    local count = 0
    
    -- Use smaller scope to help garbage collection
    do
        -- First do a quick count of players for progress tracking
        Tasks.message = "Counting entries in " .. source.name
        local playerCount = 0
        for _ in content:gmatch('"steamid":%s*"') do
            playerCount = playerCount + 1
            -- Yield occasionally while counting
            if playerCount % 50 == 0 then
                coroutine.yield()
            end
        end
        
        -- Report the number of players found
        Tasks.message = "Found " .. playerCount .. " entries in " .. source.name
        coroutine.yield()
        
        -- Setup progress tracking for this source
        Tasks.SetupSourceBatches(source, playerCount, Parsers.Config.JsonBatchSize)
        
        -- Process in very small batches with proper progress tracking
        local batchSize = Parsers.Config.JsonBatchSize
        local processedCount = 0
        local currentBatch = 0
        local batchCount = math.ceil(playerCount / batchSize)
        local playersInBatch = 0
        
        -- Create weak tables for temporary storage
        local weakData = setmetatable({}, {__mode = "v"})
        
        -- State variables for parsing
        local currentIndex = 1
        
        -- Continue until we reach the end of the content
        while currentIndex < contentLength do
            -- Find next player entry
            local steamIDStart = content:find('"steamid":%s*"', currentIndex)
            
            -- If no more players found, exit loop
            if not steamIDStart then
                break
            end
            
            -- Move current index forward
            currentIndex = steamIDStart + 10
            
            -- Extract steamid
            local steamIDEnd = content:find('"', currentIndex)
            if not steamIDEnd then
                break -- Malformed JSON, exit
            end
            
            local steamID = content:sub(currentIndex, steamIDEnd - 1)
            currentIndex = steamIDEnd + 1
            
            -- Variables for this player - use local scope only, no globals
            local playerName = "Unknown"
            local playerProof = source.cause
            
            -- Look for player_name
            local nameStart = content:find('"player_name":%s*"', currentIndex)
            if nameStart and nameStart < (content:find('"steamid":%s*"', currentIndex + 1) or contentLength) then
                currentIndex = nameStart + 14
                local nameEnd = content:find('"', currentIndex)
                if nameEnd then
                    playerName = content:sub(currentIndex, nameEnd - 1)
                    currentIndex = nameEnd + 1
                end
            end
            
            -- Look for proof
            local proofStart = content:find('"proof":%s*%[', currentIndex)
            if proofStart and proofStart < (content:find('"steamid":%s*"', currentIndex + 1) or contentLength) then
                currentIndex = proofStart + 9
                local proofEnd = content:find('%]', currentIndex)
                if proofEnd then
                    local proofStr = content:sub(currentIndex, proofEnd - 1)
                    -- Extract the first proof string (usually there's only one)
                    local singleProof = proofStr:match('"([^"]+)"')
                    if singleProof then
                        playerProof = singleProof
                    end
                    currentIndex = proofEnd + 1
                end
            end
            
            -- Convert SteamID3 to SteamID64 using optimized function
            local steamID64 = Parsers.ConvertToSteamID64(steamID)
            
            -- Add to database if conversion was successful
            if steamID64 and not database.content[steamID64] then
                database.content[steamID64] = {
                    Name = playerName,
                    proof = playerProof
                }
                
                playerlist.SetPriority(steamID64, 10)
                count = count + 1
            end
            
            -- Update processed count for progress tracking
            processedCount = processedCount + 1
            playersInBatch = playersInBatch + 1
            
            -- Ultra-frequent yields during JSON processing
            if processedCount % Parsers.Config.JsonYieldFrequency == 0 then
                coroutine.yield()
            end
            
            -- Every batch, force GC and update display
            if playersInBatch >= batchSize then
                currentBatch = currentBatch + 1
                
                -- Update batch completion for progress tracking
                Tasks.BatchCompleted()
                
                Tasks.message = string.format("Processing %s... Batch %d/%d (%d entries added)",
                    source.name, currentBatch, batchCount, count)
                
                -- Clear temporary data
                for k in pairs(weakData) do weakData[k] = nil end
                steamID = nil
                playerName = nil
                playerProof = nil
                steamID64 = nil
                
                -- Force GC and yield
                Parsers.ForceGarbageCollection(true)
                playersInBatch = 0
                coroutine.yield()
                collectgarbage("collect")
            end
        end
        
        -- Clear all local variables to help GC
        weakData = nil
        currentIndex = nil
        batchSize = nil
        processedCount = nil
        currentBatch = nil
        batchCount = nil
        playersInBatch = nil
    end
    
    -- Mark source as completed for progress tracking
    Tasks.SourceCompleted()
    
    -- Cleanup with incremental approach
    content = nil
    for i = 1, 3 do
        collectgarbage("step", 200)
        coroutine.yield()
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
        -- Process raw list with ultra-optimized batch processing
        Tasks.message = "Processing raw list from " .. source.name
        count = Parsers.CoParseBatch(content, database, source.name, source.cause)

        -- Important: Clear content reference to free memory immediately
        content = nil
        collectgarbage("collect")
    elseif source.parser == "tf2db" then
        -- Use completely rewritten TF2DB parser
        count = Parsers.CoFetchTF2DB(content, database, source)
    end

    -- Wait a bit after processing to stabilize game before next source
    Tasks.message = "Finished processing " .. source.name .. " (added " .. count .. " entries)"
    Tasks.Sleep(500)

    -- Run incremental GC instead of multiple full passes
    Parsers.ForceGarbageCollection(true)
    Tasks.Sleep(100)
    collectgarbage("step", 200) -- More gentle approach

    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))

    -- Return value, all other locals should be cleared
    local result = count
    count = nil
    return result
end

-- Sync fetch function for direct calls
function Parsers.FetchSource(source, database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end

    -- Initial cleanup before starting new source
    Parsers.ForceGarbageCollection(true)

    Tasks.message = "Preparing to fetch from " .. source.name .. "..."
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
        count = Parsers.ParseRawIDList(content, database, source.name, source.cause)

        -- Important: Clear content reference to free memory immediately
        content = nil
        collectgarbage("collect")
    elseif source.parser == "tf2db" then
        -- Don't even try to parse the full JSON - just extract steamIDs directly
        local count = 0

        -- Direct string search for steamIDs
        local i = 1
        while i < #content do
            if content:sub(i, i + 10) == '"steamid":"' then
                -- Found start of steamID - extract it
                local endPos = content:find('"', i + 11)
                if endPos then
                    local steamid = content:sub(i + 11, endPos - 1)

                    -- Convert to SteamID64 if needed
                    local steamID64
                    if steamid:match("^%[U:1:%d+%]$") then
                        steamID64 = steam.ToSteamID64(steamid)
                    elseif steamid:match("STEAM_0:%d:%d+") then
                        steamID64 = steam.ToSteamID64(steamid)
                    elseif steamid:match("^%d+$") and #steamid == 17 then
                        steamID64 = steamid -- Already SteamID64
                    end

                    -- Process this steamID
                    if steamID64 and not database.content[steamID64] then
                        database.content[steamID64] = {
                            Name = "Unknown",
                            proof = source.cause
                        }

                        playerlist.SetPriority(steamID64, 10)
                        count = count + 1
                    end

                    i = endPos
                end
            end
            i = i + 1
        end

        return count
    end

    -- Wait a bit after processing to stabilize game before next source
    Tasks.message = "Finished processing " .. source.name .. " (added " .. count .. " entries)"
    Tasks.Sleep(500)

    -- Run multiple GC passes before returning
    Parsers.ForceGarbageCollection(true)
    Tasks.Sleep(100)
    collectgarbage("collect")

    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))

    -- Return value, all other locals should be cleared
    local result = count
    count = nil
    return result
end

return Parsers
