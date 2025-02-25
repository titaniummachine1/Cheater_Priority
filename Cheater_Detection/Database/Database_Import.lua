--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")

local Database_Import = {}

local Json = Common.Json
local Log = Common.Log or { Warning = print, Info = print, Debug = function() end }

-- Utility function to trim whitespace from both ends of a string
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

    -- Initialize content if it doesn't exist
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

        -- Add new entry to database
        Database.content[steamID64] = {
            Name = playerData.Name or "Unknown",
            cause = playerData.cause or "Known Cheater",
            date = playerData.date or os.date("%Y-%m-%d %H:%M:%S")
        }
    end
end

-- Process raw ID data (now accepts Database parameter)
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
                }, Database) -- Pass Database parameter
            end
        end
    end
end

-- Process imported data (now accepts Database parameter)
function Database_Import.processImportedData(data, Database)
    if not data or not data.players or type(data.players) ~= "table" or not Database then
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
            date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or
                os.date("%Y-%m-%d %H:%M:%S")
        }

        -- Safely convert steamID to steamID64
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
            Database_Import.updateDatabase(steamID64, playerDetails, Database) -- Pass Database parameter
        end

        ::continue::
    end
end

-- Safe file reading
function Database_Import.readFromFile(filePath)
    local success, fileOrErr = pcall(io.open, filePath, "r")
    if not success or not fileOrErr then
        return nil
    end

    local content
    success, content = pcall(function()
        local data = fileOrErr:read("*a")
        fileOrErr:close()
        return data
    end)

    if not success then
        pcall(function() fileOrErr:close() end) -- Try to close if error occurred
        return nil
    end

    return content
end

-- Import database function - enhanced to properly use passed Database object
function Database_Import.importDatabase(Database)
    -- Validate input
    if not Database then
        print("Error: No database object provided to importDatabase")
        return
    end

    -- Ensure content exists
    Database.content = Database.content or {}

    local baseFilePath = GetFilePath():gsub("database.json", "") -- Get base path
    local importPath = baseFilePath .. "/import/"

    -- Ensure import directory exists
    local _, dirPath = pcall(filesystem.CreateDirectory, importPath)

    -- Statistics
    local totalFiles = 0
    local successFiles = 0
    local failedFiles = 0

    print("[Database Import] Starting import from: " .. importPath)

    -- Process all files in the import directory
    filesystem.EnumerateDirectory(importPath .. "*", function(filename, attributes)
        if filename == "." or filename == ".." then
            return -- Skip directory entries
        end

        totalFiles = totalFiles + 1
        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)

        if content then
            local before = 0
            for _ in pairs(Database.content) do
                before = before + 1
            end

            local success = pcall(function()
                if Common.isJson(content) then
                    local data = Json.decode(content)
                    if data then
                        Database_Import.processImportedData(data, Database)
                    end
                else
                    Database_Import.processRawIDs(content, Database)
                end
            end)

            local after = 0
            for _ in pairs(Database.content) do
                after = after + 1
            end

            if success then
                successFiles = successFiles + 1
                print(string.format("[Database Import] Processed %s: Added %d entries",
                    filename, after - before))
            else
                failedFiles = failedFiles + 1
                print("[Database Import] Failed to process: " .. filename)
            end
        else
            failedFiles = failedFiles + 1
            print("[Database Import] Failed to read: " .. filename)
        end
    end)

    print(string.format("[Database Import] Complete. Processed %d files (%d successful, %d failed)",
        totalFiles, successFiles, failedFiles))

    return Database -- Return the updated database
end

return Database_Import
