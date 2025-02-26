--[[
    Database_Fetcher.lua - Improved version
    Fetches cheater databases from online sources with delays to prevent IP bans
    Uses smooth interpolation for progress display
]]

-- Import required modules
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands

-- Load components
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")
local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")
local Parsers = require("Cheater_Detection.Database.Database_Fetcher.Parsers")

-- Create fetcher object with improved configuration
local Fetcher = {
    Config = {
        -- Basic settings
        AutoFetchOnLoad = false,       -- Auto fetch when script loads
        AutoSaveAfterFetch = true,     -- Save database after fetching
        NotifyOnFetchComplete = true,  -- Show completion notifications
        ShowProgressBar = true,        -- Show progress UI
        
        -- Anti-ban protection settings
        MinSourceDelay = 4,            -- Minimum seconds between sources
        MaxSourceDelay = 8,            -- Maximum seconds between sources
        RequestTimeout = 15,           -- Seconds to wait before timeout
        EnableRandomDelay = true,      -- Add random delay variation
        
        -- UI settings
        SmoothingFactor = 0.05,        -- Lower = smoother but slower progress bar
        
        -- Auto-fetch settings
        AutoFetchInterval = 0,         -- Minutes between auto-fetches (0 = disabled)
        LastAutoFetch = 0,             -- Timestamp of last auto-fetch
        
        -- Debug settings
        DebugMode = false              -- Enable debug output
    }
}

-- Export components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List

-- Add smooth progress variables
Fetcher.UI = {
    targetProgress = 0,
    currentProgress = 0,
    completedSources = 0,
    totalSources = 0
}

-- Get a randomized delay between sources
function Fetcher.GetSourceDelay()
    local minDelay = Fetcher.Config.MinSourceDelay
    local maxDelay = Fetcher.Config.MaxSourceDelay
    
    if Fetcher.Config.EnableRandomDelay then
        -- Random delay in the configured range
        return minDelay + math.random() * (maxDelay - minDelay)
    else
        -- Use the mid-point
        return (minDelay + maxDelay) / 2
    end
end

-- Main fetch function with improved anti-ban protection and progress tracking
function Fetcher.FetchAll(database, callback, silent)
    -- If already running, don't start again
    if Tasks.isRunning then
        if not silent then
            print("[Database Fetcher] A fetch operation is already in progress")
        end
        return false
    end
    
    -- Initialize UI tracking
    Fetcher.UI.totalSources = #Fetcher.Sources
    Fetcher.UI.completedSources = 0
    Fetcher.UI.currentProgress = 0
    Fetcher.UI.targetProgress = 0
    
    -- Initialize the task system
    Tasks.Reset()
    Tasks.Init(Fetcher.UI.totalSources)
    Tasks.callback = callback
    Tasks.silent = silent or false
    
    -- Create a main task that processes all sources with proper delays
    local mainTask = coroutine.create(function()
        local totalAdded = 0
        
        -- Process each source with delays between them
        for i, source in ipairs(Fetcher.Sources) do
            -- Start source with progress tracking
            Tasks.StartSource(source.name)
            Tasks.message = "Processing: " .. source.name
            
            -- Update UI tracking
            Fetcher.UI.targetProgress = (i - 1) / Fetcher.UI.totalSources * 100
            
            -- Yield to update UI
            coroutine.yield()
            
            -- Apply anti-ban delay if not the first source
            if i > 1 then
                local delay = Fetcher.GetSourceDelay()
                Tasks.message = string.format("Waiting %.1fs before next request...", delay)
                
                -- Wait with countdown
                local startTime = globals.RealTime()
                while globals.RealTime() < startTime + delay do
                    -- Update remaining time
                    local remaining = math.ceil(startTime + delay - globals.RealTime())
                    Tasks.message = string.format("Rate limit: %ds before next request...", remaining)
                    coroutine.yield()
                end
            end
            
            -- Now fetch the actual source
            Tasks.message = "Fetching from " .. source.name
            local count = 0
            
            -- Try to fetch with error handling
            local success, result = pcall(function()
                return Parsers.ProcessSource(source, database)
            end)
            
            if success then
                count = result
                totalAdded = totalAdded + count
                Tasks.message = string.format("Added %d entries from %s", count, source.name)
            else
                print("[Database Fetcher] Error processing " .. source.name .. ": " .. tostring(result))
                Tasks.message = "Error processing " .. source.name
            end
            
            -- Mark source as done and update progress
            Tasks.SourceDone()
            Fetcher.UI.completedSources = i
            Fetcher.UI.targetProgress = i / Fetcher.UI.totalSources * 100
            
            -- Yield to update UI
            coroutine.yield()
            
            -- Apply a shorter delay after processing to let UI update
            Tasks.Sleep(0.5)
        end
        
        -- Finalize
        Fetcher.UI.targetProgress = 100
        Tasks.progress = 100
        Tasks.message = "All sources processed! Added " .. totalAdded .. " entries total."
        
        -- Update last fetch time
        Fetcher.Config.LastAutoFetch = os.time()
        
        return totalAdded
    end)
    
    -- Register the main task processor
    callbacks.Register("Draw", "FetcherMainTask", function()
        -- Process the main task if it's not finished
        if coroutine.status(mainTask) ~= "dead" then
            -- Resume the main task
            local success, result = pcall(coroutine.resume, mainTask)
            
            if not success then
                -- Handle error in main task
                print("[Database Fetcher] Error: " .. tostring(result))
                Tasks.Reset()
                callbacks.Unregister("Draw", "FetcherMainTask")
            end
            
            -- Perform smooth progress interpolation
            if Fetcher.UI.currentProgress ~= Fetcher.UI.targetProgress then
                Fetcher.UI.currentProgress = Fetcher.UI.currentProgress + 
                    (Fetcher.UI.targetProgress - Fetcher.UI.currentProgress) * 
                    Fetcher.Config.SmoothingFactor
                
                -- Update the task progress
                Tasks.progress = math.floor(Fetcher.UI.currentProgress)
            end
        else
            -- Task is complete, clean up
            callbacks.Unregister("Draw", "FetcherMainTask")
            
            -- Run completion callback
            local _, result = coroutine.resume(mainTask)
            local totalAdded = tonumber(result) or 0
            
            if type(callback) == "function" then
                pcall(callback, totalAdded)
            end
            
            -- Show notification if enabled
            if Fetcher.Config.NotifyOnFetchComplete and not silent then
                printc(0, 255, 0, 255, string.format(
                    "[Database Fetcher] Update complete: Added %d entries", totalAdded))
            end
            
            -- Keep the progress bar visible for a moment
            local startTime = globals.RealTime()
            callbacks.Register("Draw", "FetcherCleanup", function()
                if globals.RealTime() > startTime + 2 then
                    Tasks.Reset()
                    callbacks.Unregister("Draw", "FetcherCleanup")
                end
            end)
        end
    end)
    
    return true
end

-- Auto fetch handler
function Fetcher.AutoFetch(database)
    -- Get database if not provided
    if not database then
        local success, db = pcall(function()
            return require("Cheater_Detection.Database.Database")
        end)
        
        if not success or not db then return false end
        database = db
    end
    
    -- Start fetch with silent mode
    return Fetcher.FetchAll(database, function(totalAdded)
        if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch then
            database.SaveDatabase()
            
            if Fetcher.Config.NotifyOnFetchComplete then
                printc(80, 200, 120, 255, "[Database] Auto-updated with " .. totalAdded .. " new entries")
            end
        end
    end, not Fetcher.Config.ShowProgressBar)
end

-- Draw callback to show progress UI
callbacks.Register("Draw", "FetcherUI", function()
    if Tasks.isRunning and Fetcher.Config.ShowProgressBar and not Tasks.silent then
        -- Update source progress information
        if Tasks.currentSource then
            local sourcePct = Fetcher.UI.completedSources / Fetcher.UI.totalSources * 100
            Tasks.message = string.format("%s [Source %d/%d - %.0f%%]", 
                Tasks.message:gsub("%s*%[Source.*%]%s*$", ""),
                Fetcher.UI.completedSources, 
                Fetcher.UI.totalSources,
                sourcePct)
        end
        
        -- Draw the UI
        pcall(Tasks.DrawProgressUI)
    end
end)

-- Register improved commands
local function RegisterCommands()
    local function getDatabase()
        return require("Cheater_Detection.Database.Database")
    end
    
    -- Fetch all command
    Commands.Register("cd_fetch_all", function()
        if not Tasks.isRunning then
            local Database = getDatabase()
            Fetcher.FetchAll(Database, function(totalAdded)
                if totalAdded > 0 then
                    Database.SaveDatabase()
                end
            end)
        else
            print("[Database Fetcher] A fetch operation is already in progress")
        end
    end, "Fetch all cheater lists and update the database")
    
    -- Fetch specific source command
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
            
            -- Initialize for a single source
            Tasks.Reset()
            Tasks.Init(1)
            
            -- Setup UI tracking
            Fetcher.UI.totalSources = 1
            Fetcher.UI.completedSources = 0
            Fetcher.UI.currentProgress = 0
            Fetcher.UI.targetProgress = 0
            
            -- Create task coroutine
            local task = coroutine.create(function()
                Tasks.StartSource(source.name)
                local count = Parsers.ProcessSource(source, Database)
                Tasks.SourceDone()
                
                -- Update progress tracking
                Fetcher.UI.completedSources = 1
                Fetcher.UI.targetProgress = 100
                
                if count > 0 then
                    Database.SaveDatabase()
                end
                
                return count
            end)
            
            -- Process the task
            callbacks.Register("Draw", "FetcherSingleSource", function()
                if coroutine.status(task) ~= "dead" then
                    -- Resume the task
                    local success, result = pcall(coroutine.resume, task)
                    
                    -- Update smooth progress
                    Fetcher.UI.currentProgress = Fetcher.UI.currentProgress + 
                        (Fetcher.UI.targetProgress - Fetcher.UI.currentProgress) * 
                        Fetcher.Config.SmoothingFactor
                    
                    -- Update the task progress
                    Tasks.progress = math.floor(Fetcher.UI.currentProgress)
                    
                    if not success then
                        print("[Database Fetcher] Error: " .. tostring(result))
                        Tasks.Reset()
                        callbacks.Unregister("Draw", "FetcherSingleSource")
                    end
                else
                    -- Get result and clean up
                    local _, count = coroutine.resume(task)
                    count = tonumber(count) or 0
                    
                    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
                    callbacks.Unregister("Draw", "FetcherSingleSource")
                    
                    -- Show completion
                    Tasks.status = "complete"
                    Tasks.progress = 100
                    Tasks.message = "Added " .. count .. " entries from " .. source.name
                    
                    -- Clean up after showing completion
                    local startTime = globals.RealTime()
                    local function cleanup()
                        if globals.RealTime() >= startTime + 2 then
                            Tasks.Reset()
                            callbacks.Unregister("Draw", "FetcherSingleSourceCleanup")
                        end
                    end
                    callbacks.Register("Draw", "FetcherSingleSourceCleanup", cleanup)
                end
            end)
        else
            print("[Database Fetcher] A task is already in progress")
        end
    end, "Fetch from a specific source")
    
    -- List sources command
    Commands.Register("cd_list_sources", function()
        print("[Database Fetcher] Available sources:")
        for i, source in ipairs(Fetcher.Sources) do
            print(string.format("%d. %s (%s)", i, source.name, source.cause))
        end
    end, "List all available sources")
    
    -- Configure delay command
    Commands.Register("cd_fetch_delay", function(args)
        if #args < 2 then
            print("Usage: cd_fetch_delay <min_seconds> <max_seconds>")
            print(string.format("Current delay: %.1f-%.1f seconds", 
                Fetcher.Config.MinSourceDelay, Fetcher.Config.MaxSourceDelay))
            return
        end
        
        local minDelay = tonumber(args[1])
        local maxDelay = tonumber(args[2])
        
        if not minDelay or not maxDelay then
            print("Invalid delay values")
            return
        end
        
        Fetcher.Config.MinSourceDelay = math.max(1, minDelay)
        Fetcher.Config.MaxSourceDelay = math.max(Fetcher.Config.MinSourceDelay, maxDelay)
        
        print(string.format("[Database Fetcher] Set source delay to %.1f-%.1f seconds", 
            Fetcher.Config.MinSourceDelay, Fetcher.Config.MaxSourceDelay))
    end, "Set delay between source fetches (anti-ban protection)")
    
    -- Cancel command
    Commands.Register("cd_cancel", function()
        if Tasks.isRunning then
            Tasks.Reset()
            print("[Database Fetcher] Cancelled all tasks")
        else
            print("[Database Fetcher] No tasks running")
        end
    end, "Cancel any running fetch operations")
end

-- Register commands
RegisterCommands()

-- Auto-fetch on load if enabled
if Fetcher.Config.AutoFetchOnLoad then
    callbacks.Register("Draw", "FetcherAutoLoad", function()
        callbacks.Unregister("Draw", "FetcherAutoLoad")
        Fetcher.AutoFetch()
    end)
end

return Fetcher
