--[[
    Database_Fetcher.lua
    Fetches cheater databases from online sources using coroutines to avoid game freezing
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
local Fetcher = {}

-- Configuration options
Fetcher.Config = {
    AutoFetchOnLoad = false,      -- Auto fetch when script loads
    AutoSaveAfterFetch = true,    -- Automatically save database after fetching
    NotifyOnFetchComplete = true, -- Show notifications when fetch completes
    ShowProgressBar = true,       -- Show the progress bar during fetch
    LastAutoFetch = 0             -- Timestamp of last auto-fetch
}

-- Export needed components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List

-- Fetch source wrapper function (synchronous)
function Fetcher.FetchSource(source, database)
    -- If tasks are already running, don't start a new synchronous fetch
    if Tasks.isRunning then
        print("[Database Fetcher] A fetch operation is already in progress")
        return 0
    end
    
    -- Use the synchronous fetch method
    return Parsers.FetchSource(source, database)
end

-- Fetch completion callback
function Fetcher.OnFetchComplete(database, totalAdded, silent)
    if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch then
        database.SaveDatabase()
        
        if Fetcher.Config.NotifyOnFetchComplete and not silent then
            printc(80, 200, 120, 255, "[Database] Updated with " .. totalAdded .. " new entries")
        end
    elseif not silent then
        print("[Database] No new entries were added")
    end
    
    -- Update last fetch time
    Fetcher.Config.LastAutoFetch = os.time()
end

-- Main fetch all function that uses coroutines
function Fetcher.FetchAll(database, callback, silent)
    -- If tasks are already running, don't start new ones
    if Tasks.isRunning then
        if not silent then
            print("[Database Fetcher] A fetch operation is already in progress")
        end
        return false
    end
    
    -- Initialize
    database = database or {}
    database.content = database.content or {}
    
    -- Set callback to run when all tasks complete
    Tasks.callback = callback
    
    -- Clear any existing tasks
    Tasks.queue = {}
    Tasks.current = nil
    Tasks.isRunning = true
    Tasks.status = "initializing"
    Tasks.progress = 0
    Tasks.message = "Preparing to fetch sources..."
    Tasks.silent = silent or false
    Tasks.smoothProgress = 0 -- Initialize smoothProgress for UI
    
    local totalAdded = 0
    
    -- Add a task for each source
    for i, source in ipairs(Fetcher.Sources) do
        Tasks.AddFetchSourceTask(source, database, totalAdded)
    end
    
    -- Final task to save the database
    Tasks.AddFinalTask("Processing complete!")
    
    if not silent then
        print(string.format("[Database Fetcher] Queued %d sources for fetching", #Fetcher.Sources))
    end
    
    -- Return immediately, the tasks will run across frames
    return true
end

-- Auto-fetch handler - can be triggered on load
function Fetcher.AutoFetch(database)
    -- Set silent mode based on config
    local silent = not Fetcher.Config.ShowProgressBar
    
    -- Get database reference if not provided
    if not database then
        -- Use pcall to safely get database reference
        local success, db = pcall(function() return require("Cheater_Detection.Database.Database") end)
        if not success or not db then return false end
        database = db
    end
    
    -- Reset task system completely before starting new fetch
    Tasks.Reset()
    
    -- Create fetch completion callback
    local function onAutoFetchComplete(totalAdded)
        Fetcher.OnFetchComplete(database, totalAdded, silent)
    end
    
    -- Start fetch with appropriate silent mode
    return Fetcher.FetchAll(database, onAutoFetchComplete, silent)
end

-- Download list wrapper function
function Fetcher.DownloadList(url, filename)
    -- If tasks are already running, don't start new ones
    if Tasks.isRunning then
        print("[Database Fetcher] A fetch operation is already in progress")
        return false
    end
    
    -- Create download completion callback
    local function onDownloadComplete(result)
        if result then
            printc(0, 255, 0, 255, "[Database Fetcher] Download complete: " .. filename)
        else
            printc(255, 0, 0, 255, "[Database Fetcher] Download failed: " .. filename)
        end
    end
    
    -- Add a download task using coroutines
    Tasks.AddDownloadTask(url, filename)
    Tasks.callback = onDownloadComplete
    Tasks.isRunning = true
    
    print("[Database Fetcher] Starting download from " .. url)
    return true
end

-- Add a new source function
function Fetcher.AddSource(name, url, cause, parser)
    return Sources.AddSource(name, url, cause, parser)
end

-- Get the database module helper function
function Fetcher.GetDatabaseModule()
    return require("Cheater_Detection.Database.Database")
end

-- Command handler for fetching all sources
function Fetcher.OnCmdFetchAll()
    -- Only start if not already running
    if not Tasks.isRunning then
        local Database = Fetcher.GetDatabaseModule()
        
        -- Create completion callback
        local function onFetchComplete(totalAdded)
            if totalAdded > 0 then
                Database.SaveDatabase()
                print("[Database Fetcher] Database saved with " .. totalAdded .. " new entries")
                printc(0, 255, 0, 255, "[Database Fetcher] Update complete: Added " .. totalAdded .. " entries")
            else
                print("[Database Fetcher] No new entries were added")
            end
        end
        
        Fetcher.FetchAll(Database, onFetchComplete)
    else
        print("[Database Fetcher] A fetch operation is already in progress")
    end
end

-- Command handler for auto-fetch toggle
function Fetcher.OnCmdAutoFetch(args)
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
        print("[Database Fetcher] Auto-fetch on load: " ..
            (Fetcher.Config.AutoFetchOnLoad and "ENABLED" or "DISABLED"))
    end
end

-- Command handler for listing sources
function Fetcher.OnCmdListSources()
    print("[Database Fetcher] Available sources:")
    for i, source in ipairs(Fetcher.Sources) do
        print(string.format("%d. %s (%s)", i, source.name, source.cause))
    end
end

-- Command handler for fetching a specific source
function Fetcher.OnCmdFetchSource(args)
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
        local Database = Fetcher.GetDatabaseModule()
        local source = Fetcher.Sources[sourceIndex]
        
        -- Create completion callback
        local function onSourceFetchComplete(count)
            print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
        end
        
        -- Add task for fetching the specific source
        Tasks.AddSourceTask(source, Database)
        Tasks.callback = onSourceFetchComplete
        Tasks.isRunning = true
    else
        print("[Database Fetcher] A task is already in progress")
    end
end

-- Command handler for canceling operations
function Fetcher.OnCmdCancel()
    if Tasks.isRunning then
        Tasks.CancelAll()
        print("[Database Fetcher] All tasks cancelled")
    else
        print("[Database Fetcher] No active tasks to cancel")
    end
end

-- Register commands
function Fetcher.RegisterCommands()
    Commands.Register("cd_fetch_all", Fetcher.OnCmdFetchAll, 
        "Fetch all cheater lists and update the database")
    
    Commands.Register("cd_autofetch", Fetcher.OnCmdAutoFetch,
        "Toggle auto-fetch on script load")
    
    Commands.Register("cd_list_sources", Fetcher.OnCmdListSources,
        "List all available database sources")
    
    Commands.Register("cd_fetch_source", Fetcher.OnCmdFetchSource,
        "Fetch from a specific database source")
    
    Commands.Register("cd_cancel", Fetcher.OnCmdCancel,
        "Cancel any ongoing database fetch operations")
end

-- Draw callback to process tasks and render progress indicator
function Fetcher.OnDraw()
    -- Always process tasks if we're running
    if Tasks.isRunning then
        Tasks.Process()
        
        -- Draw progress indicator if enabled and not in silent mode
        if Fetcher.Config.ShowProgressBar and not Tasks.silent and Tasks.status ~= "idle" then
            Tasks.DrawProgressUI()
        end
    end
end

-- Make sure we're the only one handling the Draw callback
callbacks.Unregister("Draw", "CDFetcher")
callbacks.Register("Draw", "CDFetcher", Fetcher.OnDraw)

-- Register commands when the script is loaded
Fetcher.RegisterCommands()

-- Safety measure: Reset the task system on script load
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
