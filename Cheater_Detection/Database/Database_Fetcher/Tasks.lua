-- Simplified task system with improved error handling and text wrapping

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
    DebugMode = false,     -- Enable debug logging
    YieldInterval = 500,   -- Process this many items before yielding
    MaxMessageLength = 40, -- Max message length before truncating in UI
    MaxErrorLength = 120   -- Max error message length to display
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

-- Safe error handling
function Tasks.LogError(message, details)
    print("[Tasks] ERROR: " .. message)
    if details then
        if type(details) == "string" and #details > 200 then
            print("[Tasks] Details: " .. details:sub(1, 200) .. "... (truncated)")
        else
            print("[Tasks] Details: " .. tostring(details))
        end
    end
    
    -- Set error message in UI
    Tasks.message = "ERROR: " .. message:sub(1, Tasks.Config.MaxErrorLength)
    if #message > Tasks.Config.MaxErrorLength then
        Tasks.message = Tasks.message .. "..."
    end
end

-- Initialize task tracking with error handling
function Tasks.Init(sourceCount)
    Tasks.tracking = {
        sourcesTotal = sourceCount or 0,
        sourcesDone = 0,
        sourceNames = {}
    }
    Tasks.progress = 0
    Tasks.queue = {}
    Tasks.isRunning = true
    Tasks.status = "initializing"
    Tasks.message = "Preparing to fetch sources..."
    
    if Tasks.Config.DebugMode then
        print("[Tasks] Initialized with " .. Tasks.tracking.sourcesTotal .. " sources")
    end
    
    -- Run initial GC
    collectgarbage("collect")
end

-- Add a task with minimal tracking and error handling
function Tasks.Add(fn, name)
    if type(fn) ~= "function" then
        Tasks.LogError("Task must be a function", type(fn))
        return false
    end
    
    table.insert(Tasks.queue, {
        fn = fn,
        name = name or "Unknown task"
    })
    
    table.insert(Tasks.tracking.sourceNames, name)
    return true
end

-- Start a source processing with text limit
function Tasks.StartSource(sourceName)
    -- Safety check for nil
    if not sourceName then sourceName = "Unknown source" end
    
    -- Truncate long source names
    if #sourceName > Tasks.Config.MaxMessageLength then
        sourceName = sourceName:sub(1, Tasks.Config.MaxMessageLength) .. "..."
    end
    
    Tasks.message = "Processing: " .. sourceName
    Tasks.currentSource = sourceName
    
    if Tasks.Config.DebugMode then
        print("[Tasks] Starting source: " .. sourceName)
    end
end

-- Mark a source as completed with error handling
function Tasks.SourceDone()
    Tasks.tracking.sourcesDone = Tasks.tracking.sourcesDone + 1
    
    if Tasks.tracking.sourcesTotal > 0 then
        -- Calculate progress based on completed sources
        Tasks.progress = math.floor((Tasks.tracking.sourcesDone / Tasks.tracking.sourcesTotal) * 100)
        -- Ensure progress never exceeds 100%
        Tasks.progress = math.min(Tasks.progress, 100)
    else
        Tasks.progress = 0
    end
    
    if Tasks.Config.DebugMode then
        print(string.format("[Tasks] Source complete: %d/%d (%.0f%%)", 
            Tasks.tracking.sourcesDone, 
            Tasks.tracking.sourcesTotal,
            Tasks.progress))
    end
end

-- Reset the task system with cleanup
function Tasks.Reset()
    -- Clear all task data
    Tasks.queue = {}
    Tasks.status = "idle"
    Tasks.progress = 0
    Tasks.message = ""
    Tasks.isRunning = false
    Tasks.callback = nil
    Tasks.currentSource = nil
    
    -- Clear tracking data
    Tasks.tracking = {
        sourcesTotal = 0,
        sourcesDone = 0,
        sourceNames = {}
    }
    
    -- Force GC and cleanup
    collectgarbage("collect")
    
    -- Unregister any callback that might be lingering
    pcall(function()
        callbacks.Unregister("Draw", "TasksProcessCleanup")
    end)
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
    
    -- Process each task directly with error handling
    for i, task in ipairs(Tasks.queue) do
        -- Safety check for task validity
        if not task or type(task) ~= "table" or not task.fn then
            Tasks.LogError("Invalid task at index " .. i)
            goto continue
        end
        
        Tasks.StartSource(task.name)
        
        -- Calculate progress based on task index
        Tasks.progress = math.floor((i - 1) / #Tasks.queue * 100)
        
        -- Yield to update UI
        coroutine.yield()
        
        -- Execute the task function directly with proper error handling
        local success, result = pcall(task.fn)
        
        if success then
            if type(result) == "number" then
                totalResult = totalResult + result
            end
            
            -- Format message with limits
            local resultMsg = "Added " .. tostring(result) .. " entries from " .. task.name
            if #resultMsg > Tasks.Config.MaxMessageLength then
                resultMsg = resultMsg:sub(1, Tasks.Config.MaxMessageLength) .. "..."
            end
            Tasks.message = resultMsg
        else
            -- Handle error and display message
            local errorMsg = tostring(result)
            Tasks.LogError("Error in " .. task.name, errorMsg)
            
            -- Format error message with limits
            local displayError = "Error in " .. task.name .. ": " .. errorMsg
            if #displayError > Tasks.Config.MaxErrorLength then
                displayError = displayError:sub(1, Tasks.Config.MaxErrorLength) .. "..."
            end
            Tasks.message = displayError
        end
        
        -- Mark this source as done
        Tasks.SourceDone()
        
        -- Yield to update UI
        coroutine.yield()
        
        ::continue::
    end
    
    -- Mark all processing as complete
    Tasks.status = "complete"
    Tasks.progress = 100
    Tasks.message = "All sources processed! Added " .. totalResult .. " entries total."
    
    -- Run callback if provided with error handling
    if type(Tasks.callback) == "function" then
        local success, err = pcall(Tasks.callback, totalResult)
        if not success then
            Tasks.LogError("Callback failed", err)
        end
    end
    
    -- Give time to show completion
    local startTime = globals.RealTime()
    local function cleanup()
        if globals.RealTime() < startTime + 2 then return end
        Tasks.Reset()
        callbacks.Unregister("Draw", "TasksProcessCleanup")
    end
    callbacks.Register("Draw", "TasksProcessCleanup", cleanup)
    
    return totalResult
end

-- Draw progress UI function with text wrapping
function Tasks.DrawProgressUI()
    -- Set up basic dimensions
    local x, y = 15, 15
    local width = 280  -- Slightly wider to fit more text
    local height = 80  -- Slightly taller to fit wrapped text
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
    
    -- Status message with wrapping
    draw.SetFont(draw.CreateFont("Verdana", 12, 400))
    draw.Color(255, 255, 255, 255)
    
    -- Split message into multiple lines if needed
    local message = Tasks.message or ""
    local maxWidth = width - 2 * padding
    local messageX = x + padding
    local messageY = y + padding + 22
    
    -- Wrap text to fit window width
    local lines = {}
    local currentLine = ""
    local wordWidth, lineWidth = 0, 0
    
    for word in message:gmatch("%S+") do
        wordWidth = draw.GetTextSize(word)
        
        if lineWidth + wordWidth + (currentLine ~= "" and draw.GetTextSize(" ") or 0) > maxWidth then
            -- Line would be too long with this word, start a new line
            table.insert(lines, currentLine)
            currentLine = word
            lineWidth = wordWidth
        else
            -- Add word to current line
            if currentLine ~= "" then
                currentLine = currentLine .. " " .. word
                lineWidth = lineWidth + draw.GetTextSize(" ") + wordWidth
            else
                currentLine = word
                lineWidth = wordWidth
            end
        end
    end
    
    -- Add the last line
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    -- If no lines were created, add an empty one
    if #lines == 0 then
        table.insert(lines, "")
    end
    
    -- Display lines (limit to 3 lines maximum to fit in the UI)
    local maxLines = 3
    for i = 1, math.min(#lines, maxLines) do
        -- Draw shadow
        draw.Color(0, 0, 0, 180)
        draw.Text(messageX + 1, messageY + (i-1) * 14 + 1, lines[i])
        
        -- Draw text
        draw.Color(255, 255, 255, 255)
        draw.Text(messageX, messageY + (i-1) * 14, lines[i])
    end
    
    -- Show "..." if we had to truncate lines
    if #lines > maxLines then
        draw.Color(255, 255, 255, 200)
        draw.Text(messageX, messageY + maxLines * 14, "...")
    end
    
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
