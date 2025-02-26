--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")

local Database_Import = {}

local Json = Common.Json

-- Utility function to trim whitespace
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

local function GetFilePath()
    local _, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

-- Update database with player data - MODIFIED FOR MINIMAL DATABASE STRUCTURE
function Database_Import.updateDatabase(steamID64, playerData, Database)
    -- Basic validation
    if not steamID64 or not playerData or not Database then return end

    Database.content = Database.content or {}

    -- Simplified data structure
    Database.content[steamID64] = {
        Name = (playerData.Name and playerData.Name ~= "Unknown") and playerData.Name or "Unknown",
        proof = playerData.cause or playerData.proof or "Known Cheater"
    }

    -- Mark as cheater in playerlist
    playerlist.SetPriority(steamID64, 10)
end

-- Process raw ID data
function Database_Import.processRawIDs(content, Database)
    if not content or not Database then return end

    local date = os.date("%Y-%m-%d %H:%M:%S")
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if not line:match("^%-%-") then -- Skip comment lines
            local steamID64
            local success, result = pcall(function()
                if line:match("^%d+$") then
                    return line
                elseif line:match("STEAM_0:%d:%d+") then
                    return steam.ToSteamID64(line)
                elseif line:match("^%[U:1:%d+%]$") then
                    return steam.ToSteamID64(line)
                end
                return nil
            end)

            steamID64 = success and result or nil

            if steamID64 then
                Database_Import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    cause = "Known Cheater",
                    date = date,
                }, Database)
            end
        end
    end
end

-- Process imported data
function Database_Import.processImportedData(data, Database)
    if not data or not data.players or not Database then return end

    for _, player in ipairs(data.players) do
        if not player or not player.steamid then goto continue end

        local steamID64
        local playerName = player.last_seen and player.last_seen.player_name or "Unknown"

        -- Validate name
        if not playerName or playerName == "" or #playerName < 3 then
            playerName = "Unknown"
        end

        -- Create player details
        local playerDetails = {
            Name = playerName,
            cause = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
            date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or
                os.date("%Y-%m-%d %H:%M:%S")
        }

        -- Convert steamID to steamID64
        local success, id = pcall(function()
            if player.steamid:match("^%[U:1:%d+%]$") then
                return steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                return steam.ToSteamID64(steam3)
            else
                return player.steamid -- Already SteamID64
            end
        end)

        steamID64 = success and id or nil

        if steamID64 then
            Database_Import.updateDatabase(steamID64, playerDetails, Database)
        end

        ::continue::
    end
end

-- Safe file reading
function Database_Import.readFromFile(filePath)
    local file = io.open(filePath, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()
    return content
end

-- Add this new function to process playerlist priority files
function Database_Import.processPriorityList(content, Database)
    if not content or not Database then return end

    local priorityMap = {
        [4] = "Bot",
        [5] = "Suspicious",
        [6] = "Watched",
        [7] = "Pazer List",
        [8] = "Tacobot",
        [9] = "MCDB",
        [10] = "Cheater"
    }

    -- Match both formats: playerlist.SetPriority("STEAMID", priority) and playerlist.SetPriority(steamid, priority)
    local pattern = 'playerlist%.SetPriority%(["\']?([^"\',)]+)["\']?%s*,%s*(%d+)%)'
    local date = os.date("%Y-%m-%d %H:%M:%S")
    local count = 0

    for steamid, priority in content:gmatch(pattern) do
        local priority = tonumber(priority)
        if steamid and priority then
            -- Convert steamid to steamid64 if needed
            local steamID64
            local success, result = pcall(function()
                if steamid:match("^%d+$") and #steamid >= 15 then
                    return steamid -- Already SteamID64
                elseif steamid:match("^STEAM_0:%d:%d+$") then
                    return steam.ToSteamID64(steamid)
                elseif steamid:match("^%[U:1:%d+%]$") then
                    return steam.ToSteamID64(steamid)
                end
                return nil
            end)

            steamID64 = success and result or nil

            if steamID64 then
                local cause = priorityMap[priority] or ("Priority " .. priority)

                Database_Import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    cause = cause,
                    date = date,
                    priority = priority
                }, Database)

                count = count + 1
            end
        end
    end

    return count
end

-- Import database function
function Database_Import.importDatabase(Database)
    if not Database then return end

    Database.content = Database.content or {}

    local baseFilePath = GetFilePath():gsub("database.json", "")
    local importPath = baseFilePath .. "/import/"

    -- Create import directory if it doesn't exist
    filesystem.CreateDirectory(importPath)

    -- Track import statistics
    local processedFiles = 0
    local importedEntries = 0

    -- Process all files
    filesystem.EnumerateDirectory(importPath .. "*", function(filename, attributes)
        if filename == "." or filename == ".." then return end

        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)

        if content then
            -- Count entries before import
            local beforeCount = 0
            for _ in pairs(Database.content) do
                beforeCount = beforeCount + 1
            end

            -- Process the file
            local success = pcall(function()
                if content:match("playerlist%.SetPriority") then
                    -- Process as a priority list file
                    Database_Import.processPriorityList(content, Database)
                elseif Common.isJson(content) then
                    local data = Json.decode(content)
                    if data then
                        Database_Import.processImportedData(data, Database)
                    end
                else
                    Database_Import.processRawIDs(content, Database)
                end
            end)

            if success then
                processedFiles = processedFiles + 1

                -- Count entries after import
                local afterCount = 0
                for _ in pairs(Database.content) do
                    afterCount = afterCount + 1
                end

                importedEntries = importedEntries + (afterCount - beforeCount)
            end
        end
    end)

    if processedFiles > 0 then
        -- Only print a message if we actually processed files - the main Database.lua will print a summary
        -- print(string.format("Processed %d import files with %d total entries", processedFiles, importedEntries))
    end

    return Database
end

return Database_Import
