-- Task management system for coroutines

local Tasks = {
    queue = {},        -- Task queue
    current = nil,     -- Current running coroutine
    status = "idle",   -- Current status (idle, running, etc.)
    progress = 0,      -- Progress value (0-100)
    message = "",      -- Status message
    callback = nil,    -- Callback to run when all tasks complete
    isRunning = false, -- Is the task system currently running
    silent = false,    -- Whether to show UI
    smoothProgress = 0, -- Smooth progress value for UI animation
    completionTime = 0  -- Time when tasks completed (for timeout handling)
}

-- Add memory monitoring
Tasks.MemoryStats = {
    lastCheck = 0,
    checkInterval = 1.0, -- Check memory every second
    lastUsage = 0
}

-- Rate limiting help - sleep between requests to avoid hitting limits
function Tasks.Sleep(ms)
    local start = globals.RealTime()
    while globals.RealTime() < start + ms / 1000 do
        coroutine.yield()
    end
end

-- Add proper task tracking for accurate percentages
Tasks.TaskTracking = {
    totalTasks = 0,         -- Total tasks in this run
    completedTasks = 0,     -- Number of completed tasks
    sourceCount = 0,        -- Total number of sources
    currentSource = 0       -- Current source being processed
}

-- Add a task to the queue with enhanced error checking
function Tasks.Add(taskFn, description, weight, sourceInfo)
    if type(taskFn) ~= "function" then
        print("[Tasks] Error: Attempted to add non-function task")
        return -1
    end
    
    -- Track this task in our total count
    Tasks.TaskTracking.totalTasks = Tasks.TaskTracking.totalTasks + 1
    
    -- Track source info if provided
    if sourceInfo and sourceInfo.isSource then
        Tasks.TaskTracking.sourceCount = Tasks.TaskTracking.sourceCount + 1
    end
    
    local co = coroutine.create(taskFn)
    if not co then
        print("[Tasks] Error: Failed to create coroutine")
        return -1
    end
    
    table.insert(Tasks.queue, {
        co = co,
        description = description or "Unknown task",
        weight = weight or 1,
        created = globals.RealTime(),
        sourceInfo = sourceInfo
    })

    -- Start processing if not already running
    Tasks.isRunning = true
    Tasks.completionTime = 0 -- Reset completion timestamp

    return #Tasks.queue
end

-- More thorough reset function to prevent memory leaks
function Tasks.Reset()
    -- Clear all tables instead of recreating them
    for k in pairs(Tasks.queue) do Tasks.queue[k] = nil end
    Tasks.current = nil
    Tasks.status = "idle"
    Tasks.progress = 0
    Tasks.message = ""
    Tasks.isRunning = false
    Tasks.callback = nil
    Tasks.smoothProgress = 0
    Tasks.completionTime = 0
    Tasks.silent = false
    
    -- Reset task tracking
    Tasks.TaskTracking.totalTasks = 0
    Tasks.TaskTracking.completedTasks = 0
    Tasks.TaskTracking.sourceCount = 0
    Tasks.TaskTracking.currentSource = 0
    
    -- Force multiple garbage collections
    collectgarbage("stop")  -- Disable automatic collection
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("restart")
    
    -- Unregister any lingering callbacks
    callbacks.Unregister("Draw", "CDTasks_Complete")
    
    -- Special case: reset any pending weak tables
    if Tasks.weakTables then
        for k in pairs(Tasks.weakTables) do
            Tasks.weakTables[k] = nil
        end
    end
    
    -- Create weak tables repository if it doesn't exist
    Tasks.weakTables = Tasks.weakTables or setmetatable({}, {__mode = "v"})
end

-- Create weak table for temporary data that should be GC'ed quickly
function Tasks.CreateWeakTable()
    local tbl = setmetatable({}, {__mode = "v"})
    table.insert(Tasks.weakTables, tbl)
    return tbl
end

-- Optimized task processing function to prevent ruRBtree overflow
function Tasks.Process()
    if not Tasks.isRunning then return end
    
    -- Check memory usage periodically
    local currentTime = globals.RealTime()
    if currentTime - Tasks.MemoryStats.lastCheck >= Tasks.MemoryStats.checkInterval then
        Tasks.MemoryStats.lastCheck = currentTime
        Tasks.MemoryStats.lastUsage = collectgarbage("count")
        
        -- If memory usage is too high, force a collection
        if Tasks.MemoryStats.lastUsage > 40000 then -- 40MB
            collectgarbage("collect")
        end
    end
    
    -- Check if we need to hide the window after completion
    if Tasks.completionTime > 0 then
        local currentTime = globals.RealTime()
        if currentTime - Tasks.completionTime >= 2.0 then
            Tasks.Reset() -- Reset the entire task system
            return
        end
    end

    -- If we have no current coroutine but have tasks in queue
    if not Tasks.current and #Tasks.queue > 0 then
        Tasks.current = table.remove(Tasks.queue, 1)
        Tasks.status = "running"
        Tasks.message = "Processing: " .. Tasks.current.description
        
        -- Track source changes for percentage calculation
        if Tasks.current.sourceInfo and Tasks.current.sourceInfo.isSource then
            Tasks.TaskTracking.currentSource = Tasks.TaskTracking.currentSource + 1
        end
    end

    -- If we have a current task, resume it
    if Tasks.current then
        local co = Tasks.current.co
        
        -- Check if coroutine is valid and alive
        if coroutine.status(co) ~= "dead" then
            -- Resume with error handling
            local success, result = pcall(coroutine.resume, co)
            
            if not success then
                -- Error occurred
                print("[Database Fetcher] Error in task: " .. tostring(result))
                Tasks.current = nil
                Tasks.status = "error"
                Tasks.message = "Error: " .. tostring(result)
                
                -- Force GC after an error to clean up
                collectgarbage("collect")
                collectgarbage("collect")
                
                -- Set completion time for timeout
                Tasks.completionTime = globals.RealTime()
            elseif coroutine.status(co) == "dead" then
                -- Task completed
                Tasks.TaskTracking.completedTasks = Tasks.TaskTracking.completedTasks + 1
                local completedTask = Tasks.current
                Tasks.current = nil
                
                -- Calculate percentage based on completed tasks
                if Tasks.TaskTracking.totalTasks > 0 then
                    -- Base percentage on both task completion and source completion
                    local taskPercentage = Tasks.TaskTracking.completedTasks / Tasks.TaskTracking.totalTasks
                    local sourcePercentage = 0
                    
                    -- If we have sources, weight the percentage by source completion
                    if Tasks.TaskTracking.sourceCount > 0 then
                        sourcePercentage = Tasks.TaskTracking.currentSource / Tasks.TaskTracking.sourceCount
                        -- Combined percentage, weighted 70% for sources, 30% for tasks
                        Tasks.progress = math.floor((sourcePercentage * 0.7 + taskPercentage * 0.3) * 100)
                    else
                        -- Just use task percentage
                        Tasks.progress = math.floor(taskPercentage * 100)
                    end
                else
                    Tasks.progress = 0
                end
                
                -- Check if we're done with all tasks
                if #Tasks.queue == 0 then
                    Tasks.status = "complete"
                    Tasks.message = "All tasks completed"
                    Tasks.progress = 100
                    
                    -- Set completion time for timeout
                    Tasks.completionTime = globals.RealTime()
                    
                    -- Execute callback if one exists
                    if type(Tasks.callback) == "function" then
                        local callbackToRun = Tasks.callback
                        Tasks.callback = nil -- Clear callback before running
                        pcall(callbackToRun, result) -- Run with error handling
                    end
                    
                    -- Force aggressive GC after completion
                    collectgarbage("stop")
                    collectgarbage("collect")
                    collectgarbage("collect")
                    collectgarbage("restart")
                    
                    -- Clear weak tables
                    if Tasks.weakTables then
                        for k in pairs(Tasks.weakTables) do
                            Tasks.weakTables[k] = nil
                        end
                    end
                end
            end
        else
            -- Coroutine is already dead, move on
            Tasks.current = nil
        end
    end
end

-- Cancel all tasks
function Tasks.CancelAll()
    Tasks.Reset()
    print("[Database Fetcher] All tasks cancelled")
end

-- Debug function to print task status
function Tasks.PrintDebug()
    print("Tasks Status: " .. Tasks.status)
    print("Is Running: " .. tostring(Tasks.isRunning))
    print("Progress: " .. Tasks.progress .. "%")
    print("Message: " .. Tasks.message)
    print("Queue Length: " .. #Tasks.queue)
    print("Current Task: " .. (Tasks.current and Tasks.current.description or "None"))
    print("Silent Mode: " .. tostring(Tasks.silent))
end

-- Draw progress UI function
function Tasks.DrawProgressUI()
    -- Set up basic dimensions and styles
    local x, y = 15, 15
    local width = 260
    local height = 70
    local padding = 10
    local barHeight = 12
    local cornerRadius = 6
    
    -- Calculate pulsing effect
    local pulseValue = math.sin(globals.RealTime() * 4) * 0.2 + 0.8 -- Value between 0.6 and 1.0
    local pulseFactor = math.floor(pulseValue * 100) / 100 -- Keep precision but without float errors
    
    -- Calculate smooth progress (to avoid jumpy bar)
    local targetProgress = Tasks.progress / 100
    if not Tasks.smoothProgress then Tasks.smoothProgress = 0 end
    Tasks.smoothProgress = Tasks.smoothProgress + (targetProgress - Tasks.smoothProgress) * 0.1
    
    -- Ensure all drawing coordinates are integers to prevent cursor bit overflow
    x, y = math.floor(x), math.floor(y)
    width, height = math.floor(width), math.floor(height)
    padding, barHeight = math.floor(padding), math.floor(barHeight)
    cornerRadius = math.floor(cornerRadius)
    
    -- Draw panel background with rounded corners
    -- Main background
    draw.Color(20, 20, 20, 220)
    draw.FilledRect(x + cornerRadius, y, x + width - cornerRadius, y + height) -- Main rectangle
    draw.FilledRect(x, y + cornerRadius, x + width, y + height - cornerRadius) -- Vertical fill
    
    -- Draw the corners
    draw.OutlinedCircle(x + cornerRadius, y + cornerRadius, cornerRadius, 12)
    draw.OutlinedCircle(x + width - cornerRadius, y + cornerRadius, cornerRadius, 12)
    draw.OutlinedCircle(x + cornerRadius, y + height - cornerRadius, cornerRadius, 12)
    draw.OutlinedCircle(x + width - cornerRadius, y + height - cornerRadius, cornerRadius, 12)
    
    -- Fill the corners
    draw.Color(20, 20, 20, 220)
    for i = 0, cornerRadius do
        draw.FilledRect(x, y + cornerRadius - i, x + cornerRadius - i, y + cornerRadius + 1)
        draw.FilledRect(x + width - cornerRadius + i, y + cornerRadius - i, x + width, y + cornerRadius + 1)
        draw.FilledRect(x, y + height - cornerRadius - 1, x + cornerRadius - i, y + height - cornerRadius + i)
        draw.FilledRect(x + width - cornerRadius + i, y + height - cornerRadius - 1, x + width,
            y + height - cornerRadius + i)
    end
    
    -- Outer glow effect
    local glowSize = 8
    local glowAlpha = math.floor(40 * pulseFactor)
    for i = 1, glowSize do
        local alpha = math.floor(glowAlpha * (1 - i / glowSize))
        draw.Color(100, 150, 255, alpha)
        draw.OutlinedRect(x - i, y - i, x + width + i, y + height + i)
    end
    
    -- Top border highlight
    draw.Color(60, 120, 255, 180)
    draw.FilledRect(x + cornerRadius, y, x + width - cornerRadius, y + 2)
    
    -- Title text with shadow
    draw.SetFont(draw.CreateFont("Verdana", 16, 800, FONTFLAG_ANTIALIAS))
    
    local title = "Database Fetcher"
    local titleWidth, titleHeight = draw.GetTextSize(title)
    titleWidth, titleHeight = math.floor(titleWidth), math.floor(titleHeight)
    
    -- Draw fancy title background
    draw.Color(40, 100, 220, 60)
    draw.FilledRect(x + padding - 2, y + padding - 2, 
                   x + padding + titleWidth + 2, y + padding + titleHeight + 2)
    
    -- Draw text shadow
    draw.Color(0, 0, 0, 180)
    draw.Text(x + padding + 1, y + padding + 1, title)
    
    -- Draw text
    draw.Color(120, 200, 255, 255)
    draw.Text(x + padding, y + padding, title)
    
    -- Task status message
    draw.SetFont(draw.CreateFont("Verdana", 12, 400, FONTFLAG_ANTIALIAS))
    local message = Tasks.message
    
    -- Truncate message if too long
    local msgWidth = draw.GetTextSize(message)
    msgWidth = math.floor(msgWidth)
    
    if msgWidth > width - 2 * padding - 40 then
        local truncated = message
        while draw.GetTextSize(truncated .. "...") > width - 2 * padding - 40 do
            truncated = truncated:sub(1, -2)
        end
        message = truncated .. "..."
    end
    
    -- Draw message text with shadow
    draw.Color(0, 0, 0, 150)
    draw.Text(x + padding + 1, y + padding + titleHeight + 5, message)
    
    draw.Color(255, 255, 255, 255)
    draw.Text(x + padding, y + padding + titleHeight + 4, message)
    
    -- Progress bar background with rounded corners
    local barY = y + height - padding - barHeight
    draw.Color(40, 40, 40, 200)
    draw.FilledRect(x + padding, barY, x + width - padding, barY + barHeight)
    
    -- Progress bar fill with gradient
    local progressWidth = math.floor((width - 2 * padding) * Tasks.smoothProgress)
    local progressEnd = math.floor(x + padding + progressWidth) -- Ensure integer
    
    -- Progress gradient - blue to cyan
    draw.Color(30, 120, 255, 255)
    draw.FilledRectFade(
        x + padding, barY,
        progressEnd, barY + barHeight,
        255, 180, true
    )
    
    -- Highlight on top of progress bar
    draw.Color(150, 230, 255, 100)
    draw.FilledRect(x + padding, barY, progressEnd, barY + 2)
    
    -- Progress percentage text
    local percent = string.format("%d%%", math.min(Tasks.progress, 100))
    local percentWidth = draw.GetTextSize(percent)
    percentWidth = math.floor(percentWidth)
    
    draw.Color(0, 0, 0, 150)
    draw.Text(x + width - padding - percentWidth + 1, barY + 1, percent)
    
    draw.Color(255, 255, 255, 255)
    draw.Text(x + width - padding - percentWidth, barY, percent)
    
    -- Add animated glow at the progress edge
    if progressWidth > 0 then
        local glowPos = math.floor(x + padding + progressWidth) -- Ensure integer
        local pulseAlpha = math.floor(120 * pulseFactor)
        draw.Color(220, 240, 255, pulseAlpha)
        draw.FilledRect(glowPos - 2, barY, glowPos + 2, barY + barHeight)
    end
    
    -- If task is completed, show completion message
    if Tasks.completionTime > 0 then
        local timeLeft = math.ceil(2.0 - (globals.RealTime() - Tasks.completionTime))
        local closeMsg = string.format("Closing in %d...", timeLeft)
        
        draw.Color(255, 255, 255, 200)
        draw.Text(x + width - padding - draw.GetTextSize(closeMsg), y + padding, closeMsg)
    end
end

-- Register debug command
pcall(function()
    local Commands = require("Cheater_Detection.Utils.Common").Lib.Utils.Commands
    Commands.Register("cd_tasks_debug", Tasks.PrintDebug, "Print task system debug info")
end)

return Tasks
