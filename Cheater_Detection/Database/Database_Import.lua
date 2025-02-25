local Database_Import = {}

local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Log = Common.Log

-- Utility function to trim whitespace from both ends of a string
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

local function GetFilePath()
    --creating file gives succes if it created and fail if it didnt create cuz it already exists but it always succeeds
    local succes, fullPath = pcall(filesystem.CreateDirectory, folder_name)
    return tostring(fullPath .. "/database.json")
end

-- Safe update that validates data before adding to database
function Database_Import.updateDatabase(steamID64, playerData, Database)
    -- Validate inputs
    if not steamID64 or not playerData or type(steamID64) ~= "string" or type(playerData) ~= "table" then
        Log.Warning("Invalid data for database update")
        return Database
    end

    -- Clone database to prevent direct modifications until we're sure everything is valid
    local tempDatabase = Database or { content = {} }

    -- Basic validation of steamID64 format (simplified check)
    if not steamID64:match("^%d+$") or #steamID64 ~= 17 then
        Log.Warning("Invalid steamID64 format: " .. steamID64)
        return tempDatabase
    end

    -- Create transaction log
    local transactionLog = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        steamID64 = steamID64,
        action = "update",
        success = false
    }

    -- Attempt to update the database
    local success, result = pcall(function()
        local existingData = tempDatabase.content[steamID64]

        if existingData then
            -- Only update fields if they are valid
            if playerData.Name and type(playerData.Name) == "string" and playerData.Name ~= "Unknown" then
                existingData.Name = playerData.Name
            end
            if playerData.proof and type(playerData.proof) == "string" then
                existingData.proof = playerData.proof
            end
            if playerData.date and type(playerData.date) == "string" then
                existingData.date = playerData.date
            end
        else
            -- Add new entry
            tempDatabase.content[steamID64] = {
                Name = playerData.Name or "Unknown",
                proof = playerData.proof or "Known Cheater",
                date = playerData.date or os.date("%Y-%m-%d %H:%M:%S")
            }

            -- Only mark as cheater if we're confident
            if playerData.proof and playerData.proof ~= "" then
                playerlist.SetPriority(steamID64, 10)
            end
        end

        return tempDatabase
    end)

    -- Log result
    transactionLog.success = success
    if not success then
        Log.Warning("Database update failed: " .. tostring(result))
        Log.Debug("Failed transaction: " .. Json.encode(transactionLog))
        return Database -- Return original database on failure
    end

    Log.Debug("Database update completed: " .. Json.encode(transactionLog))
    return result -- Return updated database
end

-- Function to safely process raw ID data with error handling
function Database_Import.processRawIDs(content, Database)
    if not content or content == "" then
        Log.Warning("Empty content for processing")
        return Database
    end

    local tempDatabase = Database or { content = {} }
    local date = os.date("%Y-%m-%d %H:%M:%S")
    local processedCount = 0
    local errorCount = 0

    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and not line:match("^%-%-") then -- Skip comments and empty lines
            local steamID64
            local success, result = pcall(function()
                if line:match("^%d+$") and #line == 17 then
                    return line -- Already SteamID64
                elseif line:match("STEAM_0:%d:%d+") then
                    return steam.ToSteamID64(line)
                elseif line:match("^%[U:1:%d+%]$") then
                    return steam.ToSteamID64(line)
                end
                return nil
            end)

            steamID64 = success and result or nil

            if steamID64 then
                tempDatabase = Database_Import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    proof = "Known Cheater (imported)",
                    date = date
                }, tempDatabase)
                processedCount = processedCount + 1
            else
                errorCount = errorCount + 1
                Log.Debug("Failed to process ID: " .. line)
            end
        end
    end

    Log.Info(string.format("Processed %d IDs with %d errors", processedCount, errorCount))
    return tempDatabase
end

-- Process more complex import data with validation
function Database_Import.processImportedData(data, Database)
    if not data or type(data) ~= "table" or not data.players or type(data.players) ~= "table" then
        Log.Warning("Invalid imported data structure")
        return Database
    end

    local tempDatabase = Database or { content = {} }
    local processedCount = 0
    local errorCount = 0

    for _, player in ipairs(data.players) do
        local success, result = pcall(function()
            if not player or type(player) ~= "table" or not player.steamid then
                return nil
            end

            local steamID64
            local playerName = player.last_seen and player.last_seen.player_name or "Unknown"

            -- Validate name
            if not playerName or playerName == "" or #playerName < 3 then
                playerName = "Unknown"
            end

            -- Create player details
            local playerDetails = {
                Name = playerName,
                proof = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
                date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or
                os.date("%Y-%m-%d %H:%M:%S")
            }

            -- Convert steamID to steamID64
            if player.steamid:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") and #player.steamid <= 10 then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                steamID64 = steam.ToSteamID64(steam3)
            elseif player.steamid:match("^%d+$") and #player.steamid == 17 then
                steamID64 = player.steamid -- Already SteamID64
            end

            return { steamID64 = steamID64, details = playerDetails }
        end)

        if success and result and result.steamID64 then
            tempDatabase = Database_Import.updateDatabase(result.steamID64, result.details, tempDatabase)
            processedCount = processedCount + 1
        else
            errorCount = errorCount + 1
            Log.Debug("Failed to process imported player data")
        end
    end

    Log.Info(string.format("Imported %d players with %d errors", processedCount, errorCount))
    return tempDatabase
end

-- Safely read file content
function Database_Import.readFromFile(filePath)
    local success, fileOrError = pcall(io.open, filePath, "r")
    if not success or not fileOrError then
        Log.Warning("Failed to open file: " .. filePath)
        return nil
    end

    local success, contentOrError = pcall(function()
        local content = fileOrError:read("*a")
        fileOrError:close()
        return content
    end)

    if not success then
        Log.Warning("Failed to read file: " .. filePath)
        pcall(function() fileOrError:close() end) -- Try to close if still open
        return nil
    end

    return contentOrError
end

-- Import and process database files with transaction-like safety
function Database_Import.importDatabase(Database)
    local baseFilePath = GetFilePath():gsub("database.json", "")
    local importPath = baseFilePath .. "/import/"

    -- Create a backup before making changes
    local backupDatabase = {}
    if Database and Database.content then
        for k, v in pairs(Database.content) do
            backupDatabase[k] = v
        end
    end

    -- Ensure the import directory exists
    local success = pcall(filesystem.CreateDirectory, importPath)
    if not success then
        Log.Warning("Failed to create import directory")
        return Database
    end

    -- Process all files in the directory
    local totalFiles = 0
    local processedFiles = 0
    local failedFiles = 0

    local tempDatabase = Database or { content = {} }

    -- Count files first for progress tracking
    filesystem.EnumerateDirectory(importPath .. "/*", function(filename)
        if filename ~= "." and filename ~= ".." then
            totalFiles = totalFiles + 1
        end
    end)

    Log.Info("Starting import of " .. totalFiles .. " files")

    -- Process each file
    filesystem.EnumerateDirectory(importPath .. "/*", function(filename, attributes)
        if filename == "." or filename == ".." then
            return -- Skip directory entries
        end

        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)

        if content then
            local beforeCount = 0
            for _ in pairs(tempDatabase.content) do beforeCount = beforeCount + 1 end

            local fileSuccess, result = pcall(function()
                if Common.isJson(content) then
                    local data, err = Json.decode(content)
                    if data then
                        return Database_Import.processImportedData(data, tempDatabase)
                    else
                        Log.Warning("Error decoding JSON from file: " .. filename)
                        return tempDatabase
                    end
                else
                    return Database_Import.processRawIDs(content, tempDatabase)
                end
            end)

            if fileSuccess then
                tempDatabase = result
                processedFiles = processedFiles + 1

                local afterCount = 0
                for _ in pairs(tempDatabase.content) do afterCount = afterCount + 1 end

                Log.Info(string.format("Processed file %s: added %d entries",
                    filename, afterCount - beforeCount))
            else
                failedFiles = failedFiles + 1
                Log.Warning("Failed to process file: " .. filename)
            end
        else
            failedFiles = failedFiles + 1
        end
    end)

    -- Report import results
    if processedFiles > 0 then
        Log.Info(string.format("Import completed: %d files processed, %d files failed",
            processedFiles, failedFiles))
        return tempDatabase
    else
        Log.Warning("Import failed: No files could be processed")
        return Database -- Return original database on complete failure
    end
end

return Database_Import
