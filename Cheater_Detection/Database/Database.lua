--[[
    Simplified Database.lua
    Direct implementation of database functionality using native Lua tables
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
        DebugMode = false,
        MaxEntries = 15000  -- Maximum entries to prevent memory issues
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
        Database.HandleSetEntry(key, value)
    end,

    __pairs = function()
        return pairs(Database.data)
    end
})

-- Handle setting an entry with proper counting
function Database.HandleSetEntry(key, value)
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
end

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

-- Save database to disk with batch writing and progress tracking
function Database.SaveDatabase()
    -- Create a save task to run in coroutine
    local saveTask = coroutine.create(function()
        local filePath = Database.GetFilePath()
        local tempPath = filePath .. ".tmp"
        local backupPath = filePath .. ".bak"
        
        -- Let UI know we're starting
        if G and G.UI and G.UI.ShowMessage then
            G.UI.ShowMessage("Saving database...")
        end
        
        -- Stage 1: Create a temporary file
        local tempFile = io.open(tempPath, "w")
        if not tempFile then
            print("[Database] Failed to create temporary file: " .. tempPath)
            return false
        end
        
        -- Write opening JSON bracket
        tempFile:write("{\n")
        
        -- Stage 2: Process entries in batches
        local entries = {}
        for steamID, entry in pairs(Database.data) do
            table.insert(entries, {id = steamID, data = entry})
        end
        
        local totalEntries = #entries
        local batchSize = 500 -- Process 500 entries at a time
        local batches = math.ceil(totalEntries / batchSize)
        
        for batchIndex = 1, batches do
            local startIdx = (batchIndex - 1) * batchSize + 1
            local endIdx = math.min(batchIndex * batchSize, totalEntries)
            
            -- Update progress
            local progress = math.floor((batchIndex - 1) / batches * 100)
            if G and G.UI and G.UI.UpdateProgress then
                G.UI.UpdateProgress(progress, "Saving database... " .. progress .. "%")
            end
            
            -- Allow UI to update
            coroutine.yield()
            
            -- Process this batch
            for i = startIdx, endIdx do
                local entry = entries[i]
                if entry and entry.id then
                    local steamID = entry.id
                    local data = entry.data
                    
                    -- Serialize this entry
                    local jsonEntry = string.format('"%s":{"Name":"%s","proof":"%s"}', 
                        steamID,
                        (data.Name or "Unknown"):gsub('"', '\\"'),
                        (data.proof or "Unknown"):gsub('"', '\\"')
                    )
                    
                    -- Add comma for all except the last entry
                    if i < totalEntries then
                        jsonEntry = jsonEntry .. ",\n"
                    else
                        jsonEntry = jsonEntry .. "\n"
                    end
                    
                    -- Write to file
                    tempFile:write(jsonEntry)
                end
            end
            
            -- Force flush the batch
            tempFile:flush()
            
            -- Clean up memory after each batch
            collectgarbage("step", 100)
        end
        
        -- Write closing JSON bracket
        tempFile:write("}")
        tempFile:close()
        
        -- Stage 3: Backup current file if it exists
        local currentFile = io.open(filePath, "r")
        if currentFile then
            local content = currentFile:read("*a")
            currentFile:close()
            
            local backupFile = io.open(backupPath, "w")
            if backupFile then
                backupFile:write(content)
                backupFile:close()
            end
        end
        
        -- Stage 4: Rename temporary file to actual file
        local success = os.rename(tempPath, filePath)
        
        -- Update state
        Database.State.isDirty = false
        Database.State.lastSave = os.time()
        
        if G and G.UI and G.UI.ShowMessage then
            G.UI.ShowMessage("Database saved with " .. Database.State.entriesCount .. " entries!")
        end
        
        if Database.Config.DebugMode then
            print(string.format("[Database] Saved %d entries to %s", 
                Database.State.entriesCount, filePath))
        end
        
        return success
    end)
    
    -- Run the save coroutine
    local saveCallback = function()
        -- Only proceed if the coroutine is alive
        if coroutine.status(saveTask) ~= "dead" then
            local success, result = pcall(coroutine.resume, saveTask)
            
            if not success then
                -- Error occurred
                print("[Database] Save error: " .. tostring(result))
                callbacks.Unregister("Draw", "DatabaseSave")
                
                -- Try fallback save method
                Database.FallbackSave()
            end
        else
            -- Save completed
            callbacks.Unregister("Draw", "DatabaseSave")
        end
    end
    
    -- Register the callback to run on Draw
    callbacks.Register("Draw", "DatabaseSave", saveCallback)
    return true
end

-- Fallback save method that uses simpler approach for reliability
function Database.FallbackSave()
    print("[Database] Using fallback save method")
    
    local filePath = Database.GetFilePath()
    local success = pcall(function()
        -- Open file
        local file = io.open(filePath, "w")
        if not file then
            error("Failed to open file for writing")
        end
        
        -- Build a simpler JSON structure
        file:write("{\n")
        
        local count = 0
        local total = 0
        for steamID in pairs(Database.data) do total = total + 1 end
        
        for steamID, entry in pairs(Database.data) do
            count = count + 1
            local data = string.format('"%s":{"Name":"%s","proof":"%s"}%s\n',
                steamID,
                (entry.Name or "Unknown"):gsub('"', '\\"'),
                (entry.proof or "Unknown"):gsub('"', '\\"'),
                count < total and "," or ""
            )
            file:write(data)
        end
        
        file:write("}")
        file:close()
    end)
    
    if success then
        print("[Database] Fallback save successful")
        Database.State.isDirty = false
        Database.State.lastSave = os.time()
        return true
    else
        print("[Database] Fallback save failed")
        return false
    end
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

    -- Copy data with minimal structure - enforce entry limit
    local entriesAdded = 0
    for steamID, value in pairs(data) do
        if entriesAdded < Database.Config.MaxEntries then
            Database.data[steamID] = {
                Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
                proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown"
            }
            Database.State.entriesCount = Database.State.entriesCount + 1
            entriesAdded = entriesAdded + 1
        else
            break
        end
    end

    -- Clean up memory
    collectgarbage("collect")

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

-- Get name for a player
function Database.GetName(steamId)
    local record = Database.content[steamId]
    return record and record.Name or "Unknown"
end

-- Check if player is in database
function Database.Contains(steamId)
    return Database.data[steamId] ~= nil
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

-- Clean database by removing least important entries
function Database.Cleanup(maxEntries)
    maxEntries = maxEntries or Database.Config.MaxEntries
    
    -- If we're under the limit, no need to clean
    if Database.State.entriesCount <= maxEntries then
        return 0
    end
    
    -- Create a priority list for entries to keep
    local priorities = {
        -- Highest priority to keep (exact string matching)
        "RGL", "Bot", "Pazer List", "Community",
        -- Lower priority categories
        "Cheater", "Tacobot", "MCDB", "Suspicious", "Watched"
    }
    
    -- Count entries to remove
    local toRemove = Database.State.entriesCount - maxEntries
    local removed = 0
    
    -- Remove entries not in priority list first
    if toRemove > 0 then
        local nonPriorityEntries = {}
        
        for steamId, data in pairs(Database.data) do
            -- Check if this entry is a priority
            local isPriority = false
            local proof = (data.proof or ""):lower()
            
            for _, priority in ipairs(priorities) do
                if proof:find(priority:lower()) then
                    isPriority = true
                    break
                end
            end
            
            if not isPriority then
                table.insert(nonPriorityEntries, steamId)
                if #nonPriorityEntries >= toRemove then
                    break
                end
            end
        end
        
        -- Remove the non-priority entries
        for _, steamId in ipairs(nonPriorityEntries) do
            Database.content[steamId] = nil
            removed = removed + 1
        end
    end
    
    -- If we still need to remove more, start removing lowest priority entries
    if removed < toRemove then
        -- Process in reverse priority order
        for i = #priorities, 1, -1 do
            local priority = priorities[i]:lower()
            
            for steamId, data in pairs(Database.data) do
                local proof = (data.proof or ""):lower()
                
                if proof:find(priority) then
                    Database.content[steamId] = nil
                    removed = removed + 1
                    
                    if removed >= toRemove then
                        break
                    end
                end
            end
            
            if removed >= toRemove then
                break
            end
        end
    end
    
    -- Save the cleaned database
    if removed > 0 and Database.State.isDirty then
        Database.SaveDatabase()
    end
    
    return removed
end

-- Register database commands
local function RegisterCommands()
    local Commands = Common.Lib.Utils.Commands
    
    -- Database stats command
    Commands.Register("cd_db_stats", function()
        local stats = Database.GetStats()
        print(string.format("[Database] Total entries: %d", stats.entryCount))
        print(string.format("[Database] Memory usage: %.2f MB", stats.memoryMB))
        
        -- Show proof type breakdown
        print("[Database] Proof type breakdown:")
        for proofType, count in pairs(stats.proofTypes) do
            if count > 10 then -- Only show categories with more than 10 entries
                print(string.format("  - %s: %d", proofType, count))
            end
        end
    end, "Show database statistics")
    
    -- Database cleanup command
    Commands.Register("cd_db_cleanup", function(args)
        local limit = tonumber(args[1]) or Database.Config.MaxEntries
        local beforeCount = Database.State.entriesCount
        local removed = Database.Cleanup(limit)
        
        print(string.format("[Database] Cleaned %d entries (from %d to %d)", 
            removed, beforeCount, Database.State.entriesCount))
    end, "Clean the database to stay under entry limit")
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
    
    -- Clean up if over limit
    if Database.State.entriesCount > Database.Config.MaxEntries then
        local removed = Database.Cleanup()
        if removed > 0 and Database.Config.DebugMode then
            print(string.format("[Database] Cleaned %d entries to stay under limit", removed))
        end
    end

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

-- Register commands
RegisterCommands()

-- Initialize the database when this module is loaded
InitializeDatabase()

return Database
