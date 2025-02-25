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

-- Export needed components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List

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

-- Main fetch all function that uses coroutines
function Fetcher.FetchAll(database, callback)
    -- If tasks are already running, don't start new ones
    if Tasks.isRunning then
        print("[Database Fetcher] A fetch operation is already in progress")
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

    local totalAdded = 0

    -- Add a task for each source
    for i, source in ipairs(Fetcher.Sources) do
        Tasks.Add(function()
            local count = Parsers.CoFetchSource(source, database)
            totalAdded = totalAdded + count
            return count
        end, "Fetching " .. source.name, 1)
    end

    -- Final task to save the database
    Tasks.Add(function()
        Tasks.message = "Processing complete! Added " .. totalAdded .. " entries."
        return totalAdded
    end, "Finalizing", 0.5)

    print(string.format("[Database Fetcher] Queued %d sources for fetching", #Fetcher.Sources))

    -- Return immediately, the tasks will run across frames
    return true
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

    -- Download list command
    Commands.Register("cd_download_list", function(args)
        -- Only start if not already running
        if not Tasks.isRunning then
            if #args < 2 then
                print("Usage: cd_download_list <url> <filename>")
                return
            end

            Fetcher.DownloadList(args[1], args[2])
        else
            print("[Database Fetcher] A task is already in progress")
        end
    end, "Download a list from URL and save to import folder")

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

-- Draw callback to process tasks and render a stylish progress indicator
local function OnDraw()
    -- Process a task each frame if we're running
    if Tasks.isRunning then
        Tasks.Process()

        -- Draw progress indicator in the corner if not idle
        if Tasks.status ~= "idle" then
            -- Set up basic dimensions and styles
            local x, y = 15, 15
            local width = 260
            local height = 70
            local padding = 10
            local barHeight = 12
            local cornerRadius = 6
            -- Calculate pulsing effect and ensure it's an integer for draw calls
            local pulseValue = math.sin(globals.RealTime() * 4) * 0.2 + 0.8 -- Value between 0.6 and 1.0
            local pulseFactor = math.floor(pulseValue * 100) / 100          -- Keep precision but without float errors

            -- Calculate smooth progress (to avoid jumpy bar)
            local targetProgress = Tasks.progress / 100
            Tasks.smoothProgress = Tasks.smoothProgress or 0
            Tasks.smoothProgress = Tasks.smoothProgress + (targetProgress - Tasks.smoothProgress) * 0.1

            -- Ensure all drawing coordinates are integers
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
            draw.FilledRect(x + padding - 2, y + padding - 2, x + padding + titleWidth + 2, y + padding + titleHeight + 2)

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
            local progressEnd = x + padding + progressWidth

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
                local glowPos = x + padding + progressWidth
                local pulseAlpha = math.floor(120 * pulseFactor)
                draw.Color(220, 240, 255, pulseAlpha)
                draw.FilledRect(glowPos - 2, barY, glowPos + 2, barY + barHeight)
            end
        end
    end
end

-- Register callbacks
callbacks.Unregister("Draw", "CDFetcher")
callbacks.Register("Draw", "CDFetcher", OnDraw)

-- Register commands when the script is loaded
RegisterCommands()

return Fetcher
