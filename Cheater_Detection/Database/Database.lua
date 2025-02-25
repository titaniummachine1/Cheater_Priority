--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Database_import = require("Cheater_Detection.Database.Database_Import")

local Database = {}

Database.content = {}

local Json = Common.Json

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

function Database.GetFilePath()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

function Database.SaveDatabase(DataBaseTable)
    DataBaseTable = DataBaseTable or Database.content
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
            Database.content = {}
            Database.SaveDatabase()
        else
            printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database from " .. tostring(filepath))
            Database.content = loadedDatabase or {}
        end
    else
        print("Failed to load database. Error: " .. tostring(file))
        Database.content = {}
        Database.SaveDatabase()
    end
end

function Database.GetRecord(steamId)
    return Database.content[steamId]
end

function Database.GetStrikes(steamId)
    return Database.content[steamId].strikes
end

function Database.GetProof(steamId)
    return Database.content[steamId].Proof
end

function Database.GetDate(steamId)
    return Database.content[steamId].date
end

function Database.SetSuspect(steamId, data)
    Database.content[steamId] = data
end

function Database.ClearSuspect(steamId)
    if Database.content[steamId] then
        Database.content[steamId] = nil
    end
end

Database_import.importDatabase()

local function OnUnload() -- Called when the script is unloaded
    if Database.content then
        if G.Menu.Main.debug then
            Database.ClearSuspect(Common.GetSteamID64(entities.GetLocalPlayer())) -- Clear the local if debug is enabled
        end

        Database.SaveDatabase(Database.content) -- Save the database
    else
        Database.SaveDatabase()
    end
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("Unload", "CDDatabase_Unload")                                -- unregister the "Unload" callback
--[[ Register callbacks ]]--
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)                         -- Register the "Unload" callback


return Database
