-- Task management system for coroutines

local Parsers = require("Cheater_Detection.Database.Database_Fetcher.Parsers")

local Tasks = {
    queue = {},         -- Task queue
    current = nil,      -- Current running coroutine
    status = "idle",    -- Current status (idle, running, etc.)
    progress = 0,       -- Progress value (0-100)
    message = "",       -- Status message
    callback = nil,     -- Callback to run when all tasks complete
    isRunning = false,  -- Is the task system currently running
    silent = false,     -- Whether to show UI
    smoothProgress = 0, -- Smooth progress value for UI animation
    completionTime = 0  -- Time when tasks completed (for timeout handling)
}

-- Rate limiting help - sleep between requests to avoid hitting limits
function Tasks.Sleep(ms)
    local start = globals.RealTime()
    while globals.RealTime() < start + ms / 700 do
        coroutine.yield()
    end
end

-- Add a generic task to the queue
function Tasks.Add(taskFn, description, weight)
    table.insert(Tasks.queue, {
        co = coroutine.create(taskFn),
        description = description or "Unknown task",
        weight = weight or 1
    })
    
    -- Start processing if not already running
    Tasks.isRunning = true
    Tasks.completionTime = 0 -- Reset completion timestamp
    
    return #Tasks.queue
end

-- Add a fetch source task
function Tasks.AddFetchSourceTask(source, database, totalAdded)
    -- Fetch source task function
    local function fetchSourceTask()
        local count = Parsers.CoFetchSource(source, database)
        totalAdded = totalAdded + count
        return count
    end
    
    -- Add the task to the queue
    return Tasks.Add(fetchSourceTask, "Fetching " .. source.name, 1)
end

-- Add a final task
function Tasks.AddFinalTask(message)
    -- Final task function 
    local function finalTask()
        Tasks.message = message
        return true
    end
    
    -- Add the task to the queue
    return Tasks.Add(finalTask, "Finalizing", 0.5)
end

-- Add a download task
function Tasks.AddDownloadTask(url, filename)
    -- Download task function
    local function downloadTask()
        return Parsers.CoDownloadList(url, filename)
    end
    
    -- Add the task to the queue
    return Tasks.Add(downloadTask, "Downloading " .. filename, 1)
end

-- Add a source task
function Tasks.AddSourceTask(source, database)
    -- Source task function
    local function sourceTask()
        local count = Parsers.CoFetchSource(source, database)
        
        if count > 0 then
            database.SaveDatabase()
            return count
        end
        return 0
    end
    
    -- Add the task to the queue
    return Tasks.Add(sourceTask, "Fetching " .. source.name, 1)
end

-- Reset task system state completely
function Tasks.Reset()
    Tasks.queue = {}
    Tasks.current = nil
    Tasks.status = "idle"
    Tasks.progress = 0
    Tasks.message = ""
    Tasks.isRunning = false
    Tasks.callback = nil
    Tasks.smoothProgress = 0
    Tasks.completionTime = 0
    Tasks.silent = false
    
    -- Unregister any lingering callbacks
    callbacks.Unregister("Draw", "CDTasks_Complete")
end

-- Process the next available task
function Tasks.Process()
    if not Tasks.isRunning then return end
    
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
    end
    
    -- If we have a current task, resume it
    if Tasks.current then
        local co = Tasks.current.co
        local success, result = pcall(coroutine.resume, co)
        
        if not success then
            -- Error occurred
            print("[Database Fetcher] Error in task: " .. tostring(result))
            Tasks.current = nil
            Tasks.status = "error"
            Tasks.message = "Error: " .. tostring(result)
            -- Set completion time for timeout
            Tasks.completionTime = globals.RealTime()
        elseif coroutine.status(co) == "dead" then
            -- Task completed
            local completedTask = Tasks.current
            Tasks.current = nil
            
            -- Update progress
            local totalTasks = #Tasks.queue
            local completedTasks = totalTasks > 0 and (1 - totalTasks / (totalTasks + 1)) or 1
            Tasks.progress = math.min(100, math.floor(completedTasks * 100))
            
            -- Check if we're done with all tasks
            if #Tasks.queue == 0 then
                Tasks.status = "complete"
                Tasks.message = "All tasks completed"
                Tasks.progress = 100
                
                -- Set completion time for timeout
                Tasks.completionTime = globals.RealTime()
                
                -- Execute callback if one exists
                local callbackToRun = Tasks.callback
                if callbackToRun then
                    -- Clear callback before running it to prevent issues
                    Tasks.callback = nil
                    callbackToRun(result)
                end
            end
        end
    end
end

-- Cancel all tasks
function Tasks.CancelAll()
    Tasks.Reset()
    print("[Database Fetcher] All tasks cancelled")
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
    local percent = string.format("%d%%", Tasks.progress)
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

-- Register debug command
function Tasks.RegisterDebugCommand()
    local success, Commands = pcall(function() 
        return require("Cheater_Detection.Utils.Common").Lib.Utils.Commands 
    end)
    
    if success and Commands then
        Commands.Register("cd_tasks_debug", Tasks.PrintDebug, "Print task system debug info")
    end
end

-- Call this once at load time
Tasks.RegisterDebugCommand()

return Tasks
