--[[
    Simplified Database.lua
    Direct implementation of database functionality without external DB modules
    Stores only essential data: name and proof for each SteamID64
]]

local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Json = Common.Json
local Database_import = require("Cheater_Detection.Database.Database_Import")
local Database_Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

local Database = {
    -- Internal data storage (direct table)
    data = {},

    -- Configuration
    Config = {
        AutoSave = true,
        SaveInterval = 300, -- 5 minutes
        DebugMode = false
    },

    -- State tracking
    State = {
        entriesCount = 0,
        isDirty = false,
        lastSave = 0
    }
}

-- Create the content accessor with metatable for cleaner API
Database.content = setmetatable({}, {
    __index = function(_, key)
        return Database.data[key]
    end,

    __newindex = function(_, key, value)
        -- Count entries if adding/removing
        if (Database.data[key] == nil) and value ~= nil then
            Database.State.entriesCount = Database.State.entriesCount + 1
        elseif (Database.data[key] ~= nil) and value == nil then
            Database.State.entriesCount = Database.State.entriesCount - 1
        end

        -- Simplified data structure - keep only what's needed
        if value ~= nil then
            -- Ensure we only store essential data
            local minimalValue = {
                Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
                proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown"
            }
            Database.data[key] = minimalValue
        else
            Database.data[key] = nil
        end

        Database.State.isDirty = true

        -- Auto-save if enabled and enough time has passed
        if Database.Config.AutoSave then
            local currentTime = os.time()
            if currentTime - Database.State.lastSave >= Database.Config.SaveInterval then
                Database.SaveDatabase()
            end
        end
    end,

    __pairs = function()
        return pairs(Database.data)
    end
})

-- Find best path for database storage
function Database.GetFilePath()
    local possibleFolders = {
        "Lua Cheater_Detection",
        "Lua Scripts/Cheater_Detection",
        "lbox/Cheater_Detection",
        "lmaobox/Cheater_Detection",
        "."
    }

    -- Try to find existing folder first
    for _, folder in ipairs(possibleFolders) do
        if pcall(function() return filesystem.GetFileSize(folder) end) then
            return folder .. "/database.json"
        end
    end

    -- Try to create folders
    for _, folder in ipairs(possibleFolders) do
        if pcall(filesystem.CreateDirectory, folder) then
            return folder .. "/database.json"
        end
    end

    -- Last resort
    return "./database.json"
end

-- Save database to disk
function Database.SaveDatabase()
    local filePath = Database.GetFilePath()

    -- Open file for writing
    local file = io.open(filePath, "w")
    if not file then
        print("[Database] Failed to open file for writing: " .. filePath)
        return false
    end

    -- Write the data
    local jsonData = Json.encode(Database.data)
    file:write(jsonData)
    file:close()

    -- Update state
    Database.State.isDirty = false
    Database.State.lastSave = os.time()

    if Database.Config.DebugMode then
        print(string.format("[Database] Saved %d entries to %s", Database.State.entriesCount, filePath))
    end

    return true
end

-- Load database from disk
function Database.LoadDatabase(silent)
    local filePath = Database.GetFilePath()

    -- Try to open file
    local file = io.open(filePath, "r")
    if not file then
        if not silent then
            print("[Database] Database file not found: " .. filePath)
        end
        return false
    end

    -- Read and parse content
    local content = file:read("*a")
    file:close()

    local success, data = pcall(Json.decode, content)
    if not success or type(data) ~= "table" then
        if not silent then
            print("[Database] Failed to decode database file")
        end
        return false
    end

    -- Reset and load data
    Database.data = {}
    Database.State.entriesCount = 0

    -- Copy data with minimal structure
    for steamID, value in pairs(data) do
        Database.data[steamID] = {
            Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
            proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown"
        }
        Database.State.entriesCount = Database.State.entriesCount + 1
    end

    -- Update state
    Database.State.isDirty = false
    Database.State.lastSave = os.time()

    if not silent then
        printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database with " ..
            Database.State.entriesCount .. " entries")
    end

    return true
end

-- Get a player record
function Database.GetRecord(steamId)
    return Database.content[steamId]
end

-- Get proof for a player
function Database.GetProof(steamId)
    local record = Database.content[steamId]
    return record and record.proof or "Unknown"
end

-- Set a player as suspect
function Database.SetSuspect(steamId, data)
    if not steamId then return end

    -- Create minimal data structure
    local minimalData = {
        Name = (data and data.Name) or "Unknown",
        proof = (data and (data.proof or data.cause)) or "Unknown"
    }

    -- Store data
    Database.content[steamId] = minimalData

    -- Also set priority in playerlist
    playerlist.SetPriority(steamId, 10)
end

-- Clear a player from suspect list
function Database.ClearSuspect(steamId)
    if Database.content[steamId] then
        Database.content[steamId] = nil
        playerlist.SetPriority(steamId, 0)
    end
end

-- Get database stats
function Database.GetStats()
    -- Count entries by proof type
    local proofStats = {}
    for steamID, entry in pairs(Database.data) do
        local proof = entry.proof or "Unknown"
        proofStats[proof] = (proofStats[proof] or 0) + 1
    end

    return {
        entryCount = Database.State.entriesCount,
        isDirty = Database.State.isDirty,
        lastSave = Database.State.lastSave,
        memoryMB = collectgarbage("count") / 1024,
        proofTypes = proofStats
    }
end

-- Import function for database updating
function Database.ImportDatabase()
    -- Simple import from Database_import module
    local beforeCount = Database.State.entriesCount

    -- Import additional data
    Database_import.importDatabase(Database)

    -- Count entries after import
    local afterCount = Database.State.entriesCount

    -- Show a summary of the import
    local newEntries = afterCount - beforeCount
    if newEntries > 0 then
        printc(255, 255, 0, 255, string.format("[Database] Imported %d new entries from external sources", newEntries))

        -- Save the updated database
        if Database.SaveDatabase() then
            printc(100, 255, 100, 255, string.format("[Database] Saved database with %d total entries", afterCount))
        end
    end

    return newEntries
end

-- Add utility functions to trigger fetching
function Database.FetchUpdates(silent)
    if Database_Fetcher then
        return Database_Fetcher.FetchAll(Database, function(totalAdded)
            if totalAdded and totalAdded > 0 then
                Database.SaveDatabase()
                if not silent then
                    printc(0, 255, 0, 255, "[Database] Updated with " .. totalAdded .. " new entries")
                end
            elseif not silent then
                print("[Database] No new entries were added")
            end
        end, silent)
    else
        if not silent then
            print("[Database] Error: Database_Fetcher module not found")
        end
        return false
    end
end

-- Auto update function that can be called from anywhere
function Database.AutoUpdate()
    return Database.FetchUpdates(true)
end

-- Auto-save on unload
local function OnUnload()
    if Database.State.isDirty then
        Database.SaveDatabase()
    end
end

-- Initialize the database
local function InitializeDatabase()
    -- Load existing database first
    Database.LoadDatabase()

    -- Import additional data
    Database.ImportDatabase()

    -- Check if Database_Fetcher is available and has auto-fetch enabled
    pcall(function()
        if Database_Fetcher and Database_Fetcher.Config and Database_Fetcher.Config.AutoFetchOnLoad then
            Database_Fetcher.AutoFetch(Database)
        end
    end)
end

-- Register unload callback
callbacks.Unregister("Unload", "CDDatabase_Unload")
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)

-- Initialize the database when this module is loaded
InitializeDatabase()

return Database
