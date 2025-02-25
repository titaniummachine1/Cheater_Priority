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
    smoothProgress = 0 -- Smooth progress value for UI animation
}

-- Rate limiting help - sleep between requests to avoid hitting limits
function Tasks.Sleep(ms)
    local start = globals.RealTime()
    while globals.RealTime() < start + ms / 1000 do
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

    return #Tasks.queue
end

-- Process the next available task
function Tasks.Process()
    if not Tasks.isRunning then return end

    -- If we have no current coroutine but have tasks in queue
    if not Tasks.current and #Tasks.queue > 0 then
        Tasks.current = table.remove(Tasks.queue, 1)
        Tasks.status = "running"
        Tasks.message = "Processing: " .. Tasks.current.description
    end

    -- If we have a current task, resume it
    if Tasks.current then
        local co = Tasks.current.co
        local success, result = coroutine.resume(co)

        if not success then
            -- Error occurred
            print("[Database Fetcher] Error in task: " .. tostring(result))
            Tasks.current = nil
            Tasks.status = "error"
            Tasks.message = "Error: " .. tostring(result)
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

                -- Execute callback if one exists
                local taskCallback = Tasks.callback

                -- Delay marking as not running until after callback to ensure UI shows 100%
                callbacks.Run(function()
                    if taskCallback then
                        taskCallback(result)
                    end

                    -- Wait briefly before marking as complete so UI can show 100%
                    callbacks.Register("Draw", "CDTasks_Complete", function()
                        Tasks.isRunning = false
                        Tasks.callback = nil
                        callbacks.Unregister("Draw", "CDTasks_Complete")
                    end)
                end)
            end

            -- Return the result from the completed task
            return result
        end
    end
end

-- Cancel all tasks
function Tasks.CancelAll()
    Tasks.queue = {}
    Tasks.current = nil
    Tasks.status = "idle"
    Tasks.progress = 0
    Tasks.message = "Tasks cancelled"
    Tasks.isRunning = false
    Tasks.callback = nil
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
