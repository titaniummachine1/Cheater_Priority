--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Database_import = require("Cheater_Detection.Database.Database_Import")
local Database_Fetcher = require("Cheater_Detection.Database.Database_Fetcher")
local ChunkedDB = require("Cheater_Detection.Database.ChunkedDB")

local Database = {}

-- Configure ChunkedDB for our needs
ChunkedDB.Config.ChunkSize = 2000       -- 2000 entries per chunk
ChunkedDB.Config.AutoSave = true        -- Auto-save when database changes
ChunkedDB.Config.UseWeakReferences = false -- Disable weak references to improve reliability
ChunkedDB.Config.DebugMode = false      -- Disable debug output

-- Use ChunkedDB for storage to avoid CUTIRBTree overflow
Database.content = setmetatable({}, {
    __index = function(_, key)
        return ChunkedDB.Get(key)
    end,
    
    __newindex = function(_, key, value)
        if value == nil then
            ChunkedDB.Remove(key)
        else
            ChunkedDB.Set(key, value)
        end
    end,
    
    __pairs = function()
        -- Create an iterator for use with pairs()
        return ChunkedDB.Iterate()
    end
})

local Json = Common.Json

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("([^/\\]+)%.lua$"):gsub("%.lua$", "")

-- Try multiple possible folder names to improve compatibility
local function GetFolderName()
    local possibleFolders = {
        string.format([[Lua %s]], Lua__fileName),
        "Lua Cheater_Detection",
        "Lua Scripts/Cheater_Detection",
        "lbox/Cheater_Detection",
        "lmaobox/Cheater_Detection"
    }
    
    -- Try to find existing folder first
    for _, folder in ipairs(possibleFolders) do
        if pcall(function() return filesystem.GetFileSize(folder) end) then
            return folder
        end
    end
    
    -- Fall back to the first option if none exist
    return possibleFolders[1]
end

-- Updated folder name with more robust handling
local folder_name = GetFolderName()

function Database.GetFilePath()
    -- Try to create directory, but don't fail if it doesn't work
    pcall(filesystem.CreateDirectory, folder_name)
    return tostring(folder_name)
end

function Database.SaveDatabase(DataBaseTable)
    -- Instead of saving a single file, use ChunkedDB's save function
    local filepath = Database.GetFilePath()
    return ChunkedDB.SaveDatabase(filepath)
end

-- Modify the loadDatabase function to use ChunkedDB
function Database.LoadDatabase(silent)
    local filepath = Database.GetFilePath()
    local success = ChunkedDB.LoadDatabase(filepath)
    
    if success then
        if not silent then
            local stats = ChunkedDB.GetStats()
            printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database with " .. 
                stats.totalEntries .. " entries across " .. stats.chunks .. " chunks")
        end
        return true
    else
        if not silent then
            print("Failed to load database.")
        end
        return false
    end
end

function Database.GetRecord(steamId)
    return ChunkedDB.Get(steamId)
end

function Database.GetStrikes(steamId)
    if not steamId then return 0 end
    
    local record = ChunkedDB.Get(steamId)
    return record and (tonumber(record.strikes) or 0) or 0
end

function Database.GetProof(steamId)
    if not steamId then return "Unknown" end
    
    local record = ChunkedDB.Get(steamId)
    return record and (record.proof or "Unknown") or "Unknown"
end

function Database.GetDate(steamId)
    if not steamId then return os.date("%Y-%m-%d %H:%M:%S") end
    
    local record = ChunkedDB.Get(steamId)
    return record and record.date or os.date("%Y-%m-%d %H:%M:%S")
end

function Database.SetSuspect(steamId, data)
    if not steamId or not data then return end
    
    ChunkedDB.Set(steamId, data)
    
    -- Also set priority in playerlist
    if data.priority then
        playerlist.SetPriority(steamId, data.priority)
    else
        -- Default to priority 10 for cheaters
        playerlist.SetPriority(steamId, 10)
    end
end

function Database.ClearSuspect(steamId)
    if ChunkedDB.Contains(steamId) then
        ChunkedDB.Remove(steamId)
        -- Also reset priority in playerlist if desired
        playerlist.SetPriority(steamId, 0)
    end
end

-- Save when unloaded
local function OnUnload()
    if G.Menu and G.Menu.Main and G.Menu.Main.debug then
        local localPlayer = entities.GetLocalPlayer()
        if localPlayer then
            Database.ClearSuspect(Common.GetSteamID64(localPlayer))
        end
    end
    
    Database.SaveDatabase()
end

-- Initialize the database
local function InitializeDatabase()
    -- Load the existing database first
    local loadSuccess = Database.LoadDatabase()
    
    -- Track entry count before import
    local beforeCount = ChunkedDB.Count()
    
    -- Import additional data
    Database_import.importDatabase(Database)
    
    -- Count entries after import
    local afterCount = ChunkedDB.Count()
    
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
    
    -- Inform about chunking if database is large
    if afterCount > 5000 then
        local stats = ChunkedDB.GetStats()
        printc(255, 200, 0, 255, string.format(
            "[Database] Large database detected! Using %d chunks to prevent RBTree overflow", 
            stats.chunks
        ))
    end
    
    -- Check if Database_Fetcher is available and has auto-fetch enabled
    pcall(function()
        local Fetcher = Database_Fetcher
        if Fetcher and Fetcher.Config and Fetcher.Config.AutoFetchOnLoad then
            Fetcher.AutoFetch(Database)
        end
    end)
end

-- Add utility functions to trigger fetching
function Database.FetchUpdates(silent)
    if Database_Fetcher then
        return Database_Fetcher.FetchAll(Database, function(totalAdded)
            if totalAdded > 0 then
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

-- Get stats about the database
function Database.GetStats()
    local stats = ChunkedDB.GetStats()
    local causeStats = {}
    
    -- Count entries by cause
    for k, v in ChunkedDB.Iterate() do
        local cause = v.cause or "Unknown"
        causeStats[cause] = (causeStats[cause] or 0) + 1
    end
    
    return {
        totalEntries = stats.totalEntries,
        chunks = stats.chunks,
        causeBreakdown = causeStats,
        lastSave = stats.lastSave
    }
end

-- Add utility functions to manage duplicate entries
function Database.MergeDuplicates()
    local steamIDs = {}
    local duplicates = 0
    
    -- First, collect all steamIDs
    for steamID, _ in pairs(Database.content) do
        table.insert(steamIDs, steamID)
    end
    
    print(string.format("[Database] Processing %d entries for duplicates...", #steamIDs))
    
    -- Nothing more to do here since ChunkedDB already prevents duplicates by key
    -- This is just a placeholder for possible future functionality
    
    print(string.format("[Database] Database is already optimized (0 duplicates removed)"))
    return 0
end

-- Register unload callback
callbacks.Unregister("Unload", "CDDatabase_Unload")
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)

-- Initialize the database when this module is loaded
InitializeDatabase()

return Database
