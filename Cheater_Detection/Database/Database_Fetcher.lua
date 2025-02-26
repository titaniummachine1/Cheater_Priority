--[[
    Database_Fetcher.lua
    Fetches cheater databases from online sources using coroutines to avoid game freezing
    Processes sources one at a time with configurable batch sizes and delays
]]

-- Import required modules
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands
local Json = Common.Json

-- Load modular components
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")
local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")
local Parsers = require("Cheater_Detection.Database.Database_Fetcher.Parsers")

-- Create fetcher object
local Fetcher = {
    -- Configuration options
    Config = {
        AutoFetchOnLoad = false,       -- Auto fetch when script loads
        AutoSaveAfterFetch = true,     -- Automatically save database after fetching
        NotifyOnFetchComplete = true,  -- Show notifications when fetch completes
        ShowProgressBar = true,        -- Show the progress bar during fetch
        AutoFetchInterval = 0,         -- Time in minutes between auto-fetches (0 = disabled)
        LastAutoFetch = 0,             -- Timestamp of last auto-fetch
        ProcessOneSourceAtTime = true, -- Process one source at a time (recommended)
        SourceDelay = 5,               -- Seconds to wait between sources
        BatchSize = 500                -- Lines to process in each batch
    },
    
    -- State
    State = {
        currentSourceIndex = 0,
        totalSources = 0,
        totalAdded = 0,
        processingComplete = false
    }
}

-- Export needed components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List
Fetcher.Parsers = Parsers

-- Apply configuration to parser
function Fetcher.ApplyConfig()
    -- Apply fetcher config to parser config
    Parsers.Config.BatchSize = Fetcher.Config.BatchSize
    Parsers.Config.SourceDelay = Fetcher.Config.SourceDelay * 1000 -- Convert to milliseconds
end

-- Non-coroutine fetch wrapper function for compatibility with existing code
function Fetcher.FetchSource(source, database)
    -- If tasks are already running, don't start a new synchronous fetch
    if Tasks.isRunning then
        print("[Database Fetcher] A fetch operation is already in progress")
        return 0
    end

    -- Use the Parsers module's synchronous functions
    return Parsers.FetchSource(source, database)
end

-- Main fetch all function that processes one source at a time
function Fetcher.FetchAll(database, callback, silent)
    -- If tasks are already running, don't start new ones
    if Tasks.isRunning then
        if not silent then
            print("[Database Fetcher] A fetch operation is already in progress")
        end
        return false
    end
    
    -- Apply configuration
    Fetcher.ApplyConfig()
    
    -- Initialize
    database = database or {}
    database.content = database.content or {}
    
    -- Reset state
    Fetcher.State.currentSourceIndex = 0
    Fetcher.State.totalSources = #Fetcher.Sources
    Fetcher.State.totalAdded = 0
    Fetcher.State.processingComplete = false
    
    -- Clear any existing tasks
    Tasks.Reset()
    Tasks.callback = callback
    Tasks.isRunning = true
    Tasks.status = "initializing"
    Tasks.progress = 0
    Tasks.message = "Preparing to fetch sources..."
    Tasks.silent = silent or false
    Tasks.smoothProgress = 0
    
    -- If processing one source at a time
    if Fetcher.Config.ProcessOneSourceAtTime then
        -- Add task to process the next source
        Tasks.Add(function()
            return Fetcher.ProcessNextSource(database)
        end, "Starting fetch process", 1)
    else
        -- Legacy mode: queue all sources at once
        for i, source in ipairs(Fetcher.Sources) do
            Tasks.Add(function()
                local count = Parsers.CoFetchSource(source, database)
                Fetcher.State.totalAdded = Fetcher.State.totalAdded + count
                return count
            end, "Fetching " .. source.name, 1)
        end

        -- Final task to save the database
        Tasks.Add(function()
            Tasks.message = "Processing complete! Added " .. Fetcher.State.totalAdded .. " entries."
            return Fetcher.State.totalAdded
        end, "Finalizing", 0.5)
    end

    if not silent then
        print(string.format("[Database Fetcher] Queued %d sources for fetching", #Fetcher.Sources))
    end

    -- Return immediately, the tasks will run across frames
    return true
end

-- Process the next source in the list
function Fetcher.ProcessNextSource(database)
    Fetcher.State.currentSourceIndex = Fetcher.State.currentSourceIndex + 1

    if Fetcher.State.currentSourceIndex > Fetcher.State.totalSources then
        Fetcher.State.processingComplete = true
        Tasks.message = "Processing complete! Added " .. Fetcher.State.totalAdded .. " entries."
        return Fetcher.State.totalAdded
    end

    local source = Fetcher.Sources[Fetcher.State.currentSourceIndex]
    Tasks.message = "Fetching " .. source.name

    local count = Parsers.CoFetchSource(source, database)
    Fetcher.State.totalAdded = Fetcher.State.totalAdded + count

    if Fetcher.State.currentSourceIndex < Fetcher.State.totalSources then
        Tasks.Add(function()
            return Fetcher.ProcessNextSource(database)
        end, "Waiting for next source", Fetcher.Config.SourceDelay)
    end

    return count
end

-- Auto-fetch handler - can be triggered on load or periodically
function Fetcher.AutoFetch(database)
    -- Set silent mode based on config
    local silent = not Fetcher.Config.ShowProgressBar
    
    -- Get database reference if not provided
    if not database then
        local success, db = pcall(function()
            return require("Cheater_Detection.Database.Database")
        end)
        
        if not success or not db then
            return false
        end
        
        database = db
    end
    
    -- Reset task system completely before starting new fetch
    Tasks.Reset()
    
    -- Start fetch with appropriate silent mode
    return Fetcher.FetchAll(database, function(totalAdded)
        if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch then
            database.SaveDatabase()
            
            if Fetcher.Config.NotifyOnFetchComplete then
                printc(80, 200, 120, 255, "[Database] Auto-updated with " .. totalAdded .. " new entries")
            end
        end
        
        -- Update last fetch time
        Fetcher.Config.LastAutoFetch = os.time()
    end, silent)
end

-- Download list wrapper function
function Fetcher.DownloadList(url, filename)
    -- If tasks are already running, don't start new ones
    if Tasks.isRunning then
        print("[Database Fetcher] A fetch operation is already in progress")
        return false
    end

    -- Add a download task using coroutines
    Tasks.Add(function()
        return Parsers.CoDownloadList(url, filename)
    end, "Downloading " .. filename, 1)

    Tasks.callback = function(result)
        if result then
            printc(0, 255, 0, 255, "[Database Fetcher] Download complete: " .. filename)
        else
            printc(255, 0, 0, 255, "[Database Fetcher] Download failed: " .. filename)
        end
    end

    Tasks.isRunning = true

    print("[Database Fetcher] Starting download from " .. url)
    return true
end

-- Add a new source function
function Fetcher.AddSource(name, url, cause, parser)
    return Sources.AddSource(name, url, cause, parser)
end

-- Register commands
local function RegisterCommands()
    -- Get the database module
    local function getDatabase()
        return require("Cheater_Detection.Database.Database")
    end

    -- Fetch all sources command
    Commands.Register("cd_fetch_all", function()
        -- Only start if not already running
        if not Tasks.isRunning then
            local Database = getDatabase()

            Fetcher.FetchAll(Database, function(totalAdded)
                if totalAdded > 0 then
                    Database.SaveDatabase()
                    print("[Database Fetcher] Database saved with " .. totalAdded .. " new entries")
                    printc(0, 255, 0, 255, "[Database Fetcher] Update complete: Added " .. totalAdded .. " entries")
                else
                    print("[Database Fetcher] No new entries were added")
                end
            end)
        else
            print("[Database Fetcher] A fetch operation is already in progress")
        end
    end, "Fetch all cheater lists and update the database")
    
    -- Auto fetch toggle command
    Commands.Register("cd_autofetch", function(args)
        if #args >= 1 then
            local mode = args[1]:lower()
            if mode == "on" or mode == "1" or mode == "true" then
                Fetcher.Config.AutoFetchOnLoad = true
                print("[Database Fetcher] Auto-fetch on load: ENABLED")
            elseif mode == "off" or mode == "0" or mode == "false" then
                Fetcher.Config.AutoFetchOnLoad = false
                print("[Database Fetcher] Auto-fetch on load: DISABLED")
            end
        else
            -- Toggle mode
            Fetcher.Config.AutoFetchOnLoad = not Fetcher.Config.AutoFetchOnLoad
            print("[Database Fetcher] Auto-fetch on load: " .. (Fetcher.Config.AutoFetchOnLoad and "ENABLED" or "DISABLED"))
        end
    end, "Toggle auto-fetch on script load")
    
    -- Set update interval command
    Commands.Register("cd_fetch_interval", function(args)
        if #args >= 1 then
            local minutes = tonumber(args[1])
            if minutes and minutes >= 0 then
                Fetcher.Config.AutoFetchInterval = minutes
                if minutes == 0 then
                    print("[Database Fetcher] Periodic auto-fetch: DISABLED")
                else
                    print(string.format("[Database Fetcher] Auto-fetch interval set to %d minutes", minutes))
                end
            else
                print("[Database Fetcher] Invalid interval. Usage: cd_fetch_interval <minutes>")
            end
        else
            print(string.format("[Database Fetcher] Current auto-fetch interval: %d minutes", Fetcher.Config.AutoFetchInterval))
        end
    end, "Set auto-fetch interval in minutes (0 to disable)")

    -- List all available sources command
    Commands.Register("cd_list_sources", function()
        print("[Database Fetcher] Available sources:")
        for i, source in ipairs(Fetcher.Sources) do
            print(string.format("%d. %s (%s)", i, source.name, source.cause))
        end
    end, "List all available database sources")

    -- Fetch a specific source command
    Commands.Register("cd_fetch_source", function(args)
        if #args < 1 then
            print("Usage: cd_fetch_source <source_index>")
            return
        end

        local sourceIndex = tonumber(args[1])
        if not sourceIndex or sourceIndex < 1 or sourceIndex > #Fetcher.Sources then
            print("Invalid source index. Use cd_list_sources to see available sources.")
            return
        end

        if not Tasks.isRunning then
            local Database = getDatabase()
            local source = Fetcher.Sources[sourceIndex]

            -- Add as a coroutine task for better experience
            Tasks.Add(function()
                local count = Parsers.CoFetchSource(source, Database)

                if count > 0 then
                    Database.SaveDatabase()
                    return count
                end
                return 0
            end, "Fetching " .. source.name, 1)

            Tasks.callback = function(count)
                print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
            end

            Tasks.isRunning = true
        else
            print("[Database Fetcher] A task is already in progress")
        end
    end, "Fetch from a specific database source")

    -- Cancel current operation
    Commands.Register("cd_cancel", function()
        if Tasks.isRunning then
            Tasks.CancelAll()
            print("[Database Fetcher] All tasks cancelled")
        else
            print("[Database Fetcher] No active tasks to cancel")
        end
    end, "Cancel any ongoing database fetch operations")
end

-- Draw callback to process tasks and render progress indicator
local function OnDraw()
    -- Always process tasks if we're running
    if Tasks.isRunning then
        Tasks.Process()

        -- Draw progress indicator if enabled and not in silent mode
        if Fetcher.Config.ShowProgressBar and not Tasks.silent and Tasks.status ~= "idle" then
            -- Use the built-in draw progress UI function
            Tasks.DrawProgressUI()
        end
    end
    
    -- Check if we need to auto-fetch based on interval
    if Fetcher.Config.AutoFetchInterval > 0 and not Tasks.isRunning then
        local currentTime = os.time()
        local nextFetchTime = Fetcher.Config.LastAutoFetch + (Fetcher.Config.AutoFetchInterval * 60)
        
        if currentTime >= nextFetchTime then
            Fetcher.AutoFetch()
        end
    end
end

-- Make sure we're the only one handling the Draw callback
callbacks.Unregister("Draw", "CDFetcher")
callbacks.Register("Draw", "CDFetcher", OnDraw)

-- Register commands when the script is loaded
RegisterCommands()

-- Safety measure: Reset the task system on script load to clear any potential leftover state
Tasks.Reset()

-- Run auto-fetch if enabled - delay slightly to ensure everything is initialized
if Fetcher.Config.AutoFetchOnLoad then
    callbacks.Register("Draw", "CDFetcher_FirstRun", function()
        callbacks.Unregister("Draw", "CDFetcher_FirstRun")
        -- Schedule with a brief delay
        callbacks.Run(function()
            -- Make sure task system is reset
            Tasks.Reset()
            -- Set ShowProgressBar to true to make the loading window visible
            Fetcher.Config.ShowProgressBar = true
            Fetcher.AutoFetch()
        end)
    end)
end

return Fetcher
