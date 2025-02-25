--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Database_import = require("Cheater_Detection.Database.Database_Import")
local Database_Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

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

-- Modify the loadDatabase function to accept a 'silent' parameter
function Database.LoadDatabase(silent)
    local filepath = Database.GetFilePath()
    local file, err = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()

        local loadedDatabase, pos, decodeErr = Json.decode(content, 1)

        if decodeErr then
            if not silent then
                print("Error loading database:", decodeErr)
            end
            Database.content = {}
            return false
        else
            if not silent then
                printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database from " .. tostring(filepath))
            end
            Database.content = loadedDatabase or {}
            return true
        end
    else
        if not silent then
            print("Failed to load database. Error: " .. tostring(err))
        end
        Database.content = {}
        return false
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
    if not steamId or not data then return end
    
    Database.content[steamId] = data
    
    -- Also set priority in playerlist
    if data.priority then
        playerlist.SetPriority(steamId, data.priority)
    else
        -- Default to priority 10 for cheaters
        playerlist.SetPriority(steamId, 10)
    end
end

function Database.ClearSuspect(steamId)
    if Database.content[steamId] then
        Database.content[steamId] = nil
        -- Also reset priority in playerlist if desired
        playerlist.SetPriority(steamId, 0)
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

-- Initialize the database
local function InitializeDatabase()
    -- Load the existing database first
    local loadSuccess = Database.LoadDatabase()
    
    -- Track entry count before import
    local beforeCount = 0
    for _ in pairs(Database.content) do
        beforeCount = beforeCount + 1
    end
    
    -- Import additional data
    Database_import.importDatabase(Database)
    
    -- Count entries after import
    local afterCount = 0
    for _ in pairs(Database.content) do
        afterCount = afterCount + 1
    end
    
    -- Show a summary of the import
    local newEntries = afterCount - beforeCount
    if newEntries > 0 then
        printc(255, 255, 0, 255, string.format("[Database] Imported %d new entries from external sources", newEntries))
    end
    
    -- Save combined database only if we have entries or imports
    if afterCount > 0 then
        if Database.SaveDatabase() then
            printc(100, 255, 100, 255, string.format("[Database] Saved database with %d total entries", afterCount))
        end
    end
end

-- Register unload callback
callbacks.Unregister("Unload", "CDDatabase_Unload")
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)

-- Initialize the database when this module is loaded
InitializeDatabase()

-- Add database update command
client.Command("cd_update_db", function()
    local added = Database_Fetcher.FetchAll(Database)
    if added > 0 then
        Database.SaveDatabase()
        print("[Database] Database updated with " .. added .. " new entries")
    else
        print("[Database] No new entries added")
    end
end, "Update the cheater database from online sources")

return Database
