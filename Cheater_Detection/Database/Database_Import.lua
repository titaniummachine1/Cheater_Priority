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

-- Update database with player data
function Database_Import.updateDatabase(steamID64, playerData, Database)
    -- Basic validation
    if not steamID64 or not playerData or not Database then return end
    
    Database.content = Database.content or {}
    
    local existingData = Database.content[steamID64]
    if existingData then
        -- Only update fields if they are not nil
        if playerData.Name and playerData.Name ~= "Unknown" then
            existingData.Name = playerData.Name
        end
        if playerData.cause then
            existingData.cause = playerData.cause
        end
        if playerData.date then
            existingData.date = playerData.date
        end
    else
        -- Mark as cheater in playerlist
        playerlist.SetPriority(steamID64, 10)
        
        -- Add new entry
        Database.content[steamID64] = {
            Name = playerData.Name or "Unknown",
            cause = playerData.cause or "Known Cheater",
            date = playerData.date or os.date("%Y-%m-%d %H:%M:%S")
        }
    end
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
            date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or os.date("%Y-%m-%d %H:%M:%S")
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

-- Import database function
function Database_Import.importDatabase(Database)
    if not Database then return end
    
    Database.content = Database.content or {}
    
    local baseFilePath = GetFilePath():gsub("database.json", "")
    local importPath = baseFilePath .. "/import/"
    
    -- Create import directory if it doesn't exist
    filesystem.CreateDirectory(importPath)
    
    -- Process all files
    filesystem.EnumerateDirectory(importPath .. "*", function(filename, attributes)
        if filename == "." or filename == ".." then return end
        
        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)
        
        if content then
            pcall(function()
                if Common.isJson(content) then
                    local data = Json.decode(content)
                    if data then
                        Database_Import.processImportedData(data, Database)
                    end
                else
                    Database_Import.processRawIDs(content, Database)
                end
            end)
        end
    end)
    
    return Database
end

return Database_Import
