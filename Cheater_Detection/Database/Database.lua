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
    
    -- Open file for writing
    local file = io.open(filepath, "w")
    if not file then
        print("[Database] Failed to open file for saving")
        return false
    end

    -- Prepare data
    local uniqueDataBase = {}
    for steamId, data in pairs(DataBaseTable) do
        -- Skip any entries that aren't valid
        if type(steamId) == "string" and type(data) == "table" then
            uniqueDataBase[steamId] = data
        end
    end

    -- Encode and save
    local serializedDatabase = Json.encode(uniqueDataBase)
    if serializedDatabase then
        file:write(serializedDatabase)
        file:close()
        return true
    else
        file:close()
        print("[Database] Failed to encode database")
        return false
    end
end

function Database.LoadDatabase()
    local filepath = Database.GetFilePath()
    local file, err = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()

        local loadedDatabase, pos, decodeErr = Json.decode(content, 1)

        if decodeErr then
            print("Error loading database:", decodeErr)
            Database.content = {}
            Database.SaveDatabase()
        else
            printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database from " .. tostring(filepath))
            Database.content = loadedDatabase or {}
        end
    else
        print("Failed to load database. Error: " .. tostring(err))
        Database.content = {}
        Database.SaveDatabase()
    end
end

function Database.GetRecord(steamId)
    return Database.content[steamId]
end

function Database.GetStrikes(steamId)
    if not steamId or not Database.content[steamId] then
        return 0
    end
    return tonumber(Database.content[steamId].strikes) or 0
end

function Database.GetProof(steamId)
    if not steamId or not Database.content[steamId] then
        return "Unknown"
    end
    return Database.content[steamId].proof or "Unknown"
end

function Database.GetDate(steamId)
    if not steamId or not Database.content[steamId] then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
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

-- Save when unloaded
local function OnUnload()
    if Database.content then
        if G.Menu and G.Menu.Main and G.Menu.Main.debug then
            local localPlayer = entities.GetLocalPlayer()
            if localPlayer then
                Database.ClearSuspect(Common.GetSteamID64(localPlayer))
            end
        end
        
        Database.SaveDatabase(Database.content)
    end
end

-- Initialize
Database.LoadDatabase() -- Load existing database first
Database_import.importDatabase(Database) -- Import additional data
Database.SaveDatabase() -- Save combined database

-- Register unload callback
callbacks.Unregister("Unload", "CDDatabase_Unload")
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)

return Database
