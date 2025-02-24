--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")

local Database = {}

local Json = Common.Json

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

function Database.GetFilePath()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

function Database.SaveDatabase(DataBaseTable)
    DataBaseTable = DataBaseTable or G.DataBase or {}
    local filepath = Database.GetFilePath()


    local status, file = pcall(io.open, filepath, "w")
    if status and file then
        local uniqueDataBase = {}
        -- Iterate over the database table
        for steamId, data in pairs(DataBaseTable) do
            -- If the record doesn't exist in the unique database, add it
            if not uniqueDataBase[steamId] then
                uniqueDataBase[steamId] = data
            end
        end

        -- Serialize the unique database to JSON
        local serializedDatabase = Json.encode(uniqueDataBase)
        if not serializedDatabase then
            print("Failed encoding database.")
            file:close()
            return
        end

        -- Write the serialized database to the file
        file:write(serializedDatabase)
        file:close()

        printc(255, 183, 0, 255, "[" .. os.date("%H:%M:%S") .. "] Saved Database to " .. tostring(filepath))
    else
        print("Failed to open file for saving. Error: " .. tostring(file))
    end
end

function Database.LoadDatabase()
    local filepath = Database.GetFilePath()
    local status, file = pcall(io.open, filepath, "r")
    if status and file then
        local content = file:read("*a")
        file:close()

        local loadedDatabase, pos, decodeErr = Json.decode(content, 1, nil)

        if decodeErr then
            print("Error loading database:", decodeErr)
            G.DataBase = {}
            Database.SaveDatabase()
        else
            printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database from " .. tostring(filepath))
            G.DataBase = loadedDatabase or {}
        end
    else
        print("Failed to load database. Error: " .. tostring(file))
        G.DataBase = {}
        Database.SaveDatabase()
    end
end

-- Enhance data update checking and handling
function Database.updateDatabase(steamID64, playerData)
    local existingData = G.DataBase[steamID64]
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
        playerlist.SetPriority(steamID64, 10)
        G.DataBase[steamID64] = playerData
    end
end

-- Utility function to trim whitespace from both ends of a string
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

-- Function to process raw ID data, handling SteamID64 and SteamID formats
function Database.processRawIDs(content)
    local date = os.date("%Y-%m-%d %H:%M:%S")
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if not line:match("^%-%-") then  -- Skip comment lines
            local steamID64
            if line:match("^%d+$") then
                steamID64 = line
            elseif line:match("STEAM_0:%d:%d+") then
                steamID64 = steam.ToSteamID64(line)
            elseif line:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(line)
            end
            if steamID64 then
                Database.updateDatabase(steamID64, {
                    Name = "Unknown",
                    cause = "Known Cheater",
                    date = date,
                })
            end
        end
    end
end

-- Process each item in the imported data
function Database.processImportedData(data)
    if data and data.players then
        for _, player in ipairs(data.players) do
            local steamID64
            local playerName = player.last_seen.player_name or "Unknown"

            -- Set the name to "NN" if it is empty or too short
            if not playerName or playerName == "" or #playerName < 3 then
                playerName = "Unknown"
            end

            local playerDetails = {
                Name = playerName,
                cause = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
                date = os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time)
            }

            if player.steamid:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                steamID64 = steam.ToSteamID64(steam3)
            else
                steamID64 = player.steamid  -- Already SteamID64
            end

            Database.updateDatabase(steamID64, playerDetails)
        end
    end
end

-- Simplify file handling using a utility function
function Database.readFromFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Import and process database files
function Database.importDatabase()
    local baseFilePath = Database.GetFilePath():gsub("database.json", "")  -- Ensure the correct base path
    local importPath = baseFilePath .. "/import/"

    -- Ensure the import directory exists
    filesystem.CreateDirectory(importPath)

    -- Enumerate all files in the import directory
    filesystem.EnumerateDirectory(importPath .. "/*", function(filename, attributes)
        local fullPath = importPath .. filename
        local content = Database.readFromFile(fullPath)
        if content then
            if Common.isJson(content) then
                local data, err = Json.decode(content)
                if data then
                    Database.processImportedData(data)
                else
                    print("Error decoding JSON from file:", err)
                end
            else
                Database.processRawIDs(content)
            end
        end
    end)
end

function Database.GetRecord(steamId)
    return G.DataBase[steamId]
end

function Database.GetStrikes(steamId)
    return G.DataBase[steamId].strikes
end

function Database.GetCause(steamId)
    return G.DataBase[steamId].cause
end

function Database.GetDate(steamId)
    return G.DataBase[steamId].date
end

function Database.PushSuspect(steamId, data)
    G.DataBase[steamId] = data
end

function Database.ClearSuspect(steamId)
    local status, err = pcall(function()
        if G.DataBase[steamId] then 
            G.DataBase[steamId] = nil
        end
    end)

    if not status then
        print("Failed to clear suspect: " .. err)
    end
end

local function OnUnload() -- Called when the script is unloaded
    if G.DataBase then
        if G.Menu.Main.debug then
            Database.ClearSuspect(Common.GetSteamID64(entities.GetLocalPlayer())) -- Clear the local if debug is enabled
        end

        Database.SaveDatabase(G.DataBase) -- Save the database
    else
        Database.SaveDatabase()
    end
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("Unload", "CDDatabase_Unload")                                -- unregister the "Unload" callback
--[[ Register callbacks ]]--
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)                         -- Register the "Unload" callback


return Database
