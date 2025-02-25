local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json

local Fetcher = {}

-- Sources to fetch from
Fetcher.Sources = {
    {
        name = "bots.tf",
        url = "http://api.bots.tf/rawtext", 
        cause = "Bot",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Cheater List",
        url = "https://raw.githubusercontent.com/d3fc0n6/CheaterList/main/CheaterFriend/64ids",
        cause = "Cheater",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Tacobot List",
        url = "https://raw.githubusercontent.com/d3fc0n6/TacobotList/master/64ids",
        cause = "Tacobot",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Pazer List",
        url = "https://raw.githubusercontent.com/d3fc0n6/TacobotList/master/64ids", 
        cause = "Pazer List",
        parser = "raw"
    },
    {
        name = "Sleepy List - Bots",
        url = "https://raw.githubusercontent.com/surepy/tf2db-sleepy-list/main/playerlist.sleepy-bots.merged.json",
        cause = "Bot",
        parser = "tf2db"
    },
    {
        name = "Sleepy List - RGL",
        url = "https://raw.githubusercontent.com/surepy/tf2db-sleepy-list/main/playerlist.rgl-gg.json",
        cause = "RGL Banned",
        parser = "tf2db"
    }
}

-- Rate limiting help - sleep between requests to avoid hitting limits
local function sleepMs(ms)
    local start = globals.RealTime()
    while globals.RealTime() < start + ms/1000 do end
end

-- Make a GET request with error handling and retries
function Fetcher.Get(url)
    local retries = 3
    local retry_delay = 2000 -- ms
    
    for attempt = 1, retries do
        local success, response = pcall(http.Get, url)
        
        if success and response and #response > 0 then
            return response
        end
        
        print(string.format("[Database Fetcher] Request failed (%d/%d), retrying in %d ms", 
                           attempt, retries, retry_delay))
        
        if attempt < retries then
            sleepMs(retry_delay)
            retry_delay = retry_delay * 2  -- Exponential backoff
        end
    end
    
    return nil
end

-- Parse a raw list of SteamID64s
function Fetcher.ParseRawIDList(content)
    local ids = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        
        -- Skip comments and empty lines
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            -- Check if it's a valid SteamID64 (should be a 17-digit number)
            if line:match("^%d+$") and #line == 17 then
                table.insert(ids, line)
            end
        end
    end
    return ids
end

-- Parse TF2DB format (JSON with players array)
function Fetcher.ParseTF2DB(content)
    local ids = {}
    local success, data = pcall(Json.decode, content)
    
    if not success or not data or not data.players then
        print("[Database Fetcher] Failed to parse TF2DB format JSON")
        return {}
    end
    
    for _, player in ipairs(data.players) do
        if player.steamid then
            local steamid64
            
            -- Convert to SteamID64 if needed
            if player.steamid:match("^%[U:1:%d+%]$") then
                steamid64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("STEAM_0:%d:%d+") then
                steamid64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") and #player.steamid == 17 then
                steamid64 = player.steamid  -- Already SteamID64
            end
            
            if steamid64 then
                table.insert(ids, steamid64)
            end
        end
    end
    
    return ids
end

-- Fetch from a specific source and update the database
function Fetcher.FetchSource(source, Database)
    if not source or not source.url or not source.parser or not source.cause then
        print("[Database Fetcher] Invalid source configuration")
        return 0
    end
    
    print(string.format("[Database Fetcher] Fetching from %s...", source.name))
    local content = Fetcher.Get(source.url)
    
    if not content or #content == 0 then
        print(string.format("[Database Fetcher] Failed to fetch from %s", source.name))
        return 0
    end
    
    -- Parse the content based on the specified parser
    local ids = {}
    if source.parser == "raw" then
        ids = Fetcher.ParseRawIDList(content)
    elseif source.parser == "tf2db" then
        ids = Fetcher.ParseTF2DB(content)
    else
        print(string.format("[Database Fetcher] Unknown parser type: %s", source.parser))
        return 0
    end
    
    -- Add to database
    local count = 0
    local date = os.date("%Y-%m-%d %H:%M:%S")
    
    for _, steamID64 in ipairs(ids) do
        local existingData = Database.content[steamID64]
        if not existingData then
            -- Only add if not already in database
            Database.content[steamID64] = {
                Name = "Unknown",
                cause = source.cause,
                date = date,
                source = source.name
            }
            
            -- Flag player in playerlist
            playerlist.SetPriority(steamID64, 10)
            count = count + 1
        end
    end
    
    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
    return count
end

-- Fetch from all sources and update the database
function Fetcher.FetchAll(Database)
    if not Database then
        print("[Database Fetcher] No database provided")
        return 0
    end
    
    print("[Database Fetcher] Starting fetch from all sources")
    local totalAdded = 0
    
    for _, source in ipairs(Fetcher.Sources) do
        local count = Fetcher.FetchSource(source, Database)
        totalAdded = totalAdded + count
        
        -- Rate limiting between sources
        sleepMs(1000) 
    end
    
    print(string.format("[Database Fetcher] Completed fetch, added %d total entries", totalAdded))
    return totalAdded
end

-- Download a single remote list and save to import folder
function Fetcher.DownloadList(url, filename)
    if not url or not filename then return false end
    
    -- Create import directory
    local basePath = string.format("Lua %s", GetScriptName():match("([^/\\]+)%.lua$"):gsub("%.lua$", ""))
    local importPath = basePath .. "/import/"
    filesystem.CreateDirectory(importPath)
    
    -- Download content
    print(string.format("[Database Fetcher] Downloading from %s...", url))
    local content = Fetcher.Get(url)
    
    if not content or #content == 0 then
        print("[Database Fetcher] Download failed")
        return false
    end
    
    -- Save to file
    local filepath = importPath .. filename
    local file = io.open(filepath, "w")
    if not file then
        print("[Database Fetcher] Failed to create file: " .. filepath)
        return false
    end
    
    file:write(content)
    file:close()
    
    print(string.format("[Database Fetcher] Successfully downloaded to %s", filepath))
    return true
end

-- CLI commands for manual fetching
local function RegisterCommands()
    -- Fetch all sources
    client.Command("cd_fetch_all", function()
        local Database = require("Cheater_Detection.Database.Database")
        local added = Fetcher.FetchAll(Database)
        if added > 0 then
            Database.SaveDatabase()
        end
    end, "Fetch all cheater lists and update the database")
    
    -- Download a source to import folder
    client.Command("cd_download_list", function(url, filename)
        if not url or not filename then
            print("Usage: cd_download_list <url> <filename>")
            return
        end
        Fetcher.DownloadList(url, filename)
    end, "Download a list from URL and save to import folder")
end

-- Register commands when the script is loaded
RegisterCommands()

return Fetcher