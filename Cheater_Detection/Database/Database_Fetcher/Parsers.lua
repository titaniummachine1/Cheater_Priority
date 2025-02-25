local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Coroutine-compatible GET request
function Parsers.CoGet(url, retryCount)
    retryCount = retryCount or 3
    local retry = 0

    while retry < retryCount do
        Tasks.message = "Downloading from " .. url .. " (attempt " .. (retry + 1) .. "/" .. retryCount .. ")"

        -- Yield to allow game to render between attempts
        coroutine.yield()

        local success, response = pcall(http.Get, url)

        if success and response and #response > 0 then
            return response
        end

        retry = retry + 1

        -- If we need to retry, wait a moment
        if retry < retryCount then
            local startTime = globals.RealTime()
            local waitTime = retry * 1 -- Increase wait time with each retry

            while globals.RealTime() < startTime + waitTime do
                Tasks.message = "Retrying in " .. math.floor((startTime + waitTime) - globals.RealTime()) .. "s..."
                coroutine.yield()
            end
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

-- Parse a raw list of SteamID64s with coroutine support
function Parsers.CoParseBatch(content, database, sourceName, sourceCause)
    local date = os.date("%Y-%m-%d %H:%M:%S")
    local count = 0
    local linesProcessed = 0
    local LINES_PER_YIELD = 100 -- Process this many lines before yielding

    -- Parse raw ID list
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace

        linesProcessed = linesProcessed + 1
        if linesProcessed % LINES_PER_YIELD == 0 then
            Tasks.message = "Processing " .. sourceName .. "... " .. linesProcessed .. " lines"
            coroutine.yield()
        end

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

-- Fetch from a specific source with coroutine support
function Parsers.CoFetchSource(source, database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end

    Tasks.message = "Fetching from " .. source.name .. "..."
    local content = Parsers.CoGet(source.url)

    if not content or #content == 0 then
        print("[Database Fetcher] Failed to fetch from " .. source.name)
        return 0
    end

    -- Parse the content based on the specified parser
    local count = 0

    if source.parser == "raw" then
        -- For raw lists, process batch by batch
        count = Parsers.CoParseBatch(content, database, source.name, source.cause)
    elseif source.parser == "tf2db" then
        -- For JSON content, parse in chunks
        Tasks.message = "Parsing JSON data from " .. source.name
        coroutine.yield()

        local success, data = pcall(Json.decode, content)

        if success and data and data.players then
            local players = data.players
            local date = os.date("%Y-%m-%d %H:%M:%S")
            local processed = 0

            for _, player in ipairs(players) do
                processed = processed + 1
                if processed % 50 == 0 then
                    Tasks.message = "Processing " .. source.name .. "... " .. processed .. "/" .. #players
                    coroutine.yield()
                end

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
        else
            print("[Database Fetcher] Failed to parse TF2DB format JSON from " .. source.name)
        end
    end

    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
    return count
end

return Parsers
