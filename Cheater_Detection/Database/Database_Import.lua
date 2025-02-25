--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")

local Database_Import = {}

local Json = Common.Json

-- Utility function to trim whitespace from both ends of a string
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

local function GetFilePath()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

-- Enhance data update checking and handling
function Database_Import.updateDatabase(steamID64, playerData)
    -- Basic validation
    if not steamID64 or not playerData then return end
    
    local existingData = G.DataBase[steamID64]
    if existingData then
        -- Only update fields if they are not nil and valid
        if playerData.Name and type(playerData.Name) == "string" and playerData.Name ~= "Unknown" then
            existingData.Name = playerData.Name
        end
        if playerData.cause and type(playerData.cause) == "string" then
            existingData.cause = playerData.cause
        end
        if playerData.date and type(playerData.date) == "string" then
            existingData.date = playerData.date
        end
        -- Ensure numeric fields are numbers
        if playerData.strikes then
            existingData.strikes = tonumber(playerData.strikes) or 0
        end
    else
        -- Create new entry with safe defaults
        G.DataBase[steamID64] = {
            Name = playerData.Name or "Unknown",
            cause = playerData.cause or "Known Cheater",
            date = playerData.date or os.date("%Y-%m-%d %H:%M:%S"),
            strikes = tonumber(playerData.strikes) or 0
        }
        playerlist.SetPriority(steamID64, 10)
    end
end

-- Function to process raw ID data, handling SteamID64 and SteamID formats
function Database_Import.processRawIDs(content)
    local date = os.date("%Y-%m-%d %H:%M:%S")
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if not line:match("^%-%-") then  -- Skip comment lines
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
                })
            end
        end
    end
end

-- Process each item in the imported data
function Database_Import.processImportedData(data)
    if not data or not data.players or type(data.players) ~= "table" then 
        return
    end
    
    for _, player in ipairs(data.players) do
        -- Skip invalid entries
        if not player or not player.steamid then goto continue end
        
        local steamID64
        local playerName = player.last_seen and player.last_seen.player_name or "Unknown"

        -- Set the name to "Unknown" if it is empty or too short
        if not playerName or playerName == "" or #playerName < 3 then
            playerName = "Unknown"
        end

        local playerDetails = {
            Name = playerName,
            cause = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
            date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or os.date("%Y-%m-%d %H:%M:%S")
        }

        -- Safely convert steamID to steamID64
        local success, id = pcall(function()
            if player.steamid:match("^%[U:1:%d+%]$") then
                return steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                return steam.ToSteamID64(steam3)
            else
                return player.steamid  -- Already SteamID64
            end
        end)
        
        steamID64 = success and id or nil

        if steamID64 then
            Database_Import.updateDatabase(steamID64, playerDetails)
        end
        
        ::continue::
    end
end

-- Simplify file handling using a utility function
function Database_Import.readFromFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Import and process database files
function Database_Import.importDatabase()
    -- Initialize database if it doesn't exist
    G.DataBase = G.DataBase or {}
    
    local baseFilePath = GetFilePath():gsub("database.json", "")  -- Ensure the correct base path
    local importPath = baseFilePath .. "/import/"

    -- Ensure the import directory exists
    local success, dirPath = pcall(filesystem.CreateDirectory, importPath)
    if not success then
        print("Failed to create import directory")
        return
    end
    
    -- Count processed files
    local fileCount = 0

    -- Enumerate all files in the import directory
    filesystem.EnumerateDirectory(importPath .. "/*", function(filename, attributes)
        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)
        if content then
            local success, errMsg = pcall(function()
                if Common.isJson(content) then
                    local data = Json.decode(content)
                    if data then
                        Database_Import.processImportedData(data)
                        fileCount = fileCount + 1
                    end
                else
                    Database_Import.processRawIDs(content)
                    fileCount = fileCount + 1
                end
            end)
            
            if not success then
                print("Error processing file: " .. filename .. " - " .. tostring(errMsg))
            end
        end
    end)
    
    print("Imported data from " .. fileCount .. " files")
end

return Database_Import
