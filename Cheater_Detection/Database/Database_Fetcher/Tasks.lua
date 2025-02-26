-- Simplified task system with direct processing approach

local Tasks = {
    queue = {},         -- Task queue (simplified)
    status = "idle",    -- Current status (idle, running, complete)
    progress = 0,       -- Progress value (0-100)
    message = "",       -- Status message
    callback = nil,     -- Callback to run when all tasks complete
    isRunning = false,  -- Is the task system currently running
    silent = false      -- Whether to show UI
}

-- Basic configuration
Tasks.Config = {
    DebugMode = false,  -- Enable debug logging
    YieldInterval = 500 -- Process this many items before yielding
}

-- Simple progress tracking (no batches)
Tasks.tracking = {
    sourcesTotal = 0,
    sourcesDone = 0,
    sourceNames = {}
}

-- Simple sleep function
function Tasks.Sleep(ms)
    local start = globals.RealTime()
    while globals.RealTime() < start + ms / 1000 do
        coroutine.yield()
    end
end

-- Initialize task tracking
function Tasks.Init(sourceCount)
    Tasks.tracking = {
        sourcesTotal = sourceCount,
        sourcesDone = 0,
        sourceNames = {}
    }
    Tasks.progress = 0
    Tasks.queue = {}
    Tasks.isRunning = true
    Tasks.status = "initializing"
    Tasks.message = "Preparing to fetch sources..."
    
    if Tasks.Config.DebugMode then
        print("[Tasks] Initialized with " .. sourceCount .. " sources")
    end
end

-- Add a task with minimal tracking
function Tasks.Add(fn, name)
    if type(fn) ~= "function" then
        print("[Tasks] Error: Task must be a function")
        return false
    end
    
    table.insert(Tasks.queue, {
        fn = fn,
        name = name
    })
    
    table.insert(Tasks.tracking.sourceNames, name)
    return true
end

-- Start a source processing
function Tasks.StartSource(sourceName)
    Tasks.message = "Processing: " .. sourceName
    Tasks.currentSource = sourceName
    
    if Tasks.Config.DebugMode then
        print("[Tasks] Starting source: " .. sourceName)
    end
end

-- Mark a source as completed
function Tasks.SourceDone()
    Tasks.tracking.sourcesDone = Tasks.tracking.sourcesDone + 1
    
    if Tasks.tracking.sourcesTotal > 0 then
        -- Calculate progress based on completed sources
        Tasks.progress = math.floor((Tasks.tracking.sourcesDone / Tasks.tracking.sourcesTotal) * 100)
    end
    
    if Tasks.Config.DebugMode then
        print(string.format("[Tasks] Source complete: %d/%d (%.0f%%)", 
            Tasks.tracking.sourcesDone, 
            Tasks.tracking.sourcesTotal,
            Tasks.progress))
    end
end

-- Reset the task system
function Tasks.Reset()
    Tasks.queue = {}
    Tasks.status = "idle"
    Tasks.progress = 0
    Tasks.message = ""
    Tasks.isRunning = false
    Tasks.callback = nil
    Tasks.currentSource = nil
    
    Tasks.tracking = {
        sourcesTotal = 0,
        sourcesDone = 0,
        sourceNames = {}
    }
    
    -- Force GC
    collectgarbage("collect")
end

-- Process all tasks directly - simpler approach
function Tasks.ProcessAll()
    -- Don't do anything if not running
    if not Tasks.isRunning then return end
    
    -- Process entire queue
    local totalResult = 0
    
    -- Show starting message
    Tasks.status = "running"
    Tasks.message = "Processing all sources..."
    
    -- Make sure we render the initial state
    coroutine.yield()
    
    -- Process each task directly
    for i, task in ipairs(Tasks.queue) do
        Tasks.StartSource(task.name)
        
        -- Calculate progress based on task index
        Tasks.progress = math.floor((i - 1) / #Tasks.queue * 100)
        
        -- Yield to update UI
        coroutine.yield()
        
        -- Execute the task function directly
        local success, result = pcall(task.fn)
        
        if success then
            if type(result) == "number" then
                totalResult = totalResult + result
            end
            Tasks.message = "Added " .. result .. " entries from " .. task.name
        else
            Tasks.message = "Error in " .. task.name .. ": " .. tostring(result)
            print("[Tasks] Error in " .. task.name .. ": " .. tostring(result))
        end
        
        -- Mark this source as done
        Tasks.SourceDone()
        
        -- Yield to update UI
        coroutine.yield()
    end
    
    -- Mark all processing as complete
    Tasks.status = "complete"
    Tasks.progress = 100
    Tasks.message = "All sources processed! Added " .. totalResult .. " entries total."
    
    -- Run callback if provided
    if type(Tasks.callback) == "function" then
        pcall(Tasks.callback, totalResult)
    end
    
    -- Give time to show completion
    local startTime = globals.RealTime()
    while globals.RealTime() < startTime + 2 do
        coroutine.yield()
    end
    
    -- Reset after showing completion
    Tasks.Reset()
    
    return totalResult
end

-- Draw progress UI function - simplified version
function Tasks.DrawProgressUI()
    -- Set up basic dimensions
    local x, y = 15, 15
    local width = 260
    local height = 70
    local padding = 10
    local barHeight = 12
    
    -- Draw background
    draw.Color(20, 20, 20, 220)
    draw.FilledRect(x, y, x + width, y + height)
    
    -- Draw border
    draw.Color(60, 120, 255, 180)
    draw.OutlinedRect(x, y, x + width, y + height)
    
    -- Title text
    draw.SetFont(draw.CreateFont("Verdana", 16, 800))
    draw.Color(120, 200, 255, 255)
    draw.Text(x + padding, y + padding, "Database Fetcher")
    
    -- Status message
    draw.SetFont(draw.CreateFont("Verdana", 12, 400))
    draw.Color(255, 255, 255, 255)
    draw.Text(x + padding, y + padding + 20, Tasks.message)
    
    -- Progress bar background
    local barY = y + height - padding - barHeight
    draw.Color(40, 40, 40, 200)
    draw.FilledRect(x + padding, barY, x + width - padding, barY + barHeight)
    
    -- Progress bar fill
    local progressWidth = math.floor((width - 2 * padding) * (Tasks.progress / 100))
    draw.Color(30, 120, 255, 255)
    draw.FilledRect(x + padding, barY, x + padding + progressWidth, barY + barHeight)
    
    -- Progress percentage text
    local percent = string.format("%d%%", Tasks.progress)
    draw.Color(255, 255, 255, 255)
    draw.Text(x + width - padding - draw.GetTextSize(percent), barY, percent)
end

return Tasks
