--[[ 
    Database Manager module - Centralized control of database operations
    Allows for easy initialization, updating, and management of databases
]]

-- Import required components
local Database = require("Cheater_Detection.Database.Database")
local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands

local Manager = {}

-- Configuration options
Manager.Config = {
    AutoFetchOnLoad = true,  -- Automatically fetch database updates on script load
    CheckInterval = 24,      -- How often to automatically check for updates (in hours)
    LastCheck = 0,           -- Timestamp of last update check
    MaxEntries = 20000,      -- Maximum number of database entries (performance optimization)
}

-- Initialize database system completely
function Manager.Initialize(options)
    options = options or {}
    
    -- Override default config with provided options
    for k, v in pairs(options) do
        Manager.Config[k] = v
    end
    
    -- Load local database first
    local startTime = globals.RealTime()
    Database.LoadDatabase(false) -- Not silent, show loading message
    
    -- If auto-fetch is enabled, set up fetcher
    if Manager.Config.AutoFetchOnLoad then
        -- Configure fetcher
        Fetcher.Config.AutoFetchOnLoad = true
        Fetcher.Config.NotifyOnFetchComplete = true
        
        -- Schedule fetch for next frame to ensure everything is loaded
        local firstUpdateDone = false
        callbacks.Register("Draw", "CDDatabaseManager_InitialFetch", function()
            if not firstUpdateDone then
                firstUpdateDone = true
                Fetcher.AutoFetch(Database)
                callbacks.Unregister("Draw", "CDDatabaseManager_InitialFetch")
            end
        end)
    end
    
    -- Return the fully initialized database
    return Database
end

-- Add a new data source
function Manager.AddSource(name, url, cause, type)
    return Fetcher.AddSource(name, url, cause, type or "raw")
end

-- Force an immediate database update
function Manager.ForceUpdate()
    Database.FetchUpdates(false)
end

-- Get database stats 
function Manager.GetStats()
    local entries = 0
    local byType = {}
    
    for steamId, data in pairs(Database.content or {}) do
        entries = entries + 1
        local cause = data.cause or "Unknown"
        byType[cause] = (byType[cause] or 0) + 1
    end
    
    return {
        totalEntries = entries,
        byType = byType,
        lastFetch = Fetcher.Config.LastAutoFetch,
        lastUpdate = Manager.Config.LastCheck
    }
end

-- Register database management commands
Commands.Register("cd_db_stats", function()
    local stats = Manager.GetStats()
    print(string.format("[Database Manager] Total entries: %d", stats.totalEntries))
    print("[Database Manager] Entries by type:")
    for cause, count in pairs(stats.byType) do
        print(string.format("  - %s: %d", cause, count))
    end
    print(string.format("[Database Manager] Last fetch: %s", os.date("%Y-%m-%d %H:%M:%S", stats.lastFetch)))
end, "Show database statistics")

-- Update database command
Commands.Register("cd_update", function()
    Manager.ForceUpdate()
end, "Update the cheater database from online sources")

-- Purge old database entries to improve performance
Commands.Register("cd_cleanup", function()
    if not Database.content then
        print("[Database Manager] No database loaded")
        return
    end
    
    local beforeCount = 0
    for _ in pairs(Database.content) do
        beforeCount = beforeCount + 1
    end
    
    -- Keep track of entries to remove
    local toRemove = {}
    local twoWeeksAgo = os.time() - (14 * 24 * 60 * 60) -- 14 days ago
    
    -- Find old entries
    for steamId, data in pairs(Database.content) do
        -- If entry has a date, check if it's older than 2 weeks
        -- and doesn't have special causes we want to keep
        if data.date then
            -- Try to parse the date
            local year, month, day = data.date:match("(%d+)%-(%d+)%-(%d+)")
            if year and month and day then
                local entryTime = os.time({
                    year = tonumber(year),
                    month = tonumber(month),
                    day = tonumber(day),
                    hour = 0, min = 0, sec = 0
                })
                
                -- Exclude certain categories from cleanup
                local keepCause = data.cause and (
                    data.cause:match("Bot") or
                    data.cause:match("RGL") or
                    data.cause:match("Community")
                )
                
                -- Mark for removal if old and not a special case
                if entryTime < twoWeeksAgo and not keepCause then
                    table.insert(toRemove, steamId)
                end
            end
        end
    end
    
    -- Remove old entries
    for _, steamId in ipairs(toRemove) do
        Database.content[steamId] = nil
    end
    
    -- Save the cleaned database
    Database.SaveDatabase()
    
    -- Count entries after cleanup
    local afterCount = 0
    for _ in pairs(Database.content) do
        afterCount = afterCount + 1
    end
    
    print(string.format("[Database Manager] Removed %d old entries, keeping %d entries", 
        beforeCount - afterCount, afterCount))
end, "Remove old database entries to improve performance")

return Manager
