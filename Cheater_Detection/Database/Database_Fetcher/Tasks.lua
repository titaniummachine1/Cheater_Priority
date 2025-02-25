-- Task management system for coroutines

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

-- Add a task to the queue
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
pcall(function()
    local Commands = require("Cheater_Detection.Utils.Common").Lib.Utils.Commands
    Commands.Register("cd_tasks_debug", Tasks.PrintDebug, "Print task system debug info")
end)

return Tasks
