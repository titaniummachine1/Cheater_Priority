-- Task management system for coroutines

local Tasks = {
    queue = {},       -- Task queue
    current = nil,    -- Current running coroutine
    status = "idle",  -- Current status (idle, running, etc.)
    progress = 0,     -- Progress value (0-100)
    message = "",     -- Status message
    callback = nil,   -- Callback to run when all tasks complete
    isRunning = false -- Is the task system currently running
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
            Tasks.current = nil

            -- Update progress
            local totalTasks = #Tasks.queue
            Tasks.progress = math.min(100, math.floor((1 - totalTasks / (totalTasks + 1)) * 100))

            -- Check if we're done with all tasks
            if #Tasks.queue == 0 then
                Tasks.status = "complete"
                Tasks.message = "All tasks completed"
                Tasks.isRunning = false
                Tasks.progress = 100

                -- Execute callback if one exists
                if Tasks.callback then
                    Tasks.callback(result)
                    Tasks.callback = nil
                end
            end
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

return Tasks
