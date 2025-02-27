-- Improved task system with fixed fonts, smoother animations, and proper fade-out

local Tasks = {
	queue = {}, -- Task queue
	status = "idle", -- Current status (idle, running, complete)
	progress = 0, -- Current displayed progress (0-100)
	targetProgress = 0, -- Target progress for smooth interpolation
	message = "", -- Status message
	callback = nil, -- Callback to run when all tasks complete
	isRunning = false, -- Is the task system currently running
	silent = false, -- Whether to show UI
	completedTime = 0, -- Time when tasks completed (for fade-out)
	fadeDelay = 2, -- Seconds to wait before fading out
	opacity = 255, -- Current opacity for fade effect
}

-- Basic configuration
Tasks.Config = {
	DebugMode = false, -- Enable debug logging
	YieldInterval = 500, -- Process this many items before yielding
	SmoothFactor = 0.08, -- Lower = smoother but slower progress animation
	FontName = "Verdana", -- Font name to use
	FontSize = 16, -- Font size for title
	SmallFontSize = 12, -- Font size for messages
	SimplifiedUI = true, -- Use simplified "Loading Database" text
}

-- Font caching to avoid recreation
Tasks.Fonts = {
	title = nil,
	text = nil,
}

-- Simple progress tracking
Tasks.tracking = {
	sourcesTotal = 0,
	sourcesDone = 0,
	sourceNames = {},
}

-- Initialize fonts to ensure they're set correctly
function Tasks.InitFonts()
	if not Tasks.Fonts.title then
		Tasks.Fonts.title = draw.CreateFont(Tasks.Config.FontName, Tasks.Config.FontSize, 800)
	end

	if not Tasks.Fonts.text then
		Tasks.Fonts.text = draw.CreateFont(Tasks.Config.FontName, Tasks.Config.SmallFontSize, 400)
	end
end

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
	Tasks.message = "ERROR: " .. message:sub(1, 40)
	if #message > 40 then
		Tasks.message = Tasks.message .. "..."
	end
end

-- Initialize task tracking with error handling
function Tasks.Init(sourceCount)
	Tasks.InitFonts() -- Make sure fonts are initialized

	Tasks.tracking = {
		sourcesTotal = sourceCount or 0,
		sourcesDone = 0,
		sourceNames = {},
	}
	Tasks.progress = 0
	Tasks.targetProgress = 0
	Tasks.queue = {}
	Tasks.isRunning = true
	Tasks.status = "initializing"
	Tasks.message = "Loading Database"
	Tasks.opacity = 255
	Tasks.completedTime = 0

	if Tasks.Config.DebugMode then
		print("[Tasks] Initialized with " .. Tasks.tracking.sourcesTotal .. " sources")
	end

	-- Run initial GC
	collectgarbage("collect")
end

-- Add a task
function Tasks.Add(fn, name)
	if type(fn) ~= "function" then
		Tasks.LogError("Task must be a function", type(fn))
		return false
	end

	table.insert(Tasks.queue, {
		fn = fn,
		name = name or "Unknown task",
	})

	table.insert(Tasks.tracking.sourceNames, name)
	return true
end

-- Start a source processing with text limit
function Tasks.StartSource(sourceName)
	-- Safety check for nil
	if not sourceName then
		sourceName = "Unknown source"
	end

	-- Truncate long source names
	if #sourceName > 40 then
		sourceName = sourceName:sub(1, 40) .. "..."
	end

	-- In simplified UI mode, just keep the basic message
	if Tasks.Config.SimplifiedUI then
		Tasks.message = "Loading Database"
	else
		Tasks.message = "Processing: " .. sourceName
	end
	Tasks.currentSource = sourceName

	if Tasks.Config.DebugMode then
		print("[Tasks] Starting source: " .. sourceName)
	end
end

-- Mark a source as completed with error handling
function Tasks.SourceDone()
	Tasks.tracking.sourcesDone = Tasks.tracking.sourcesDone + 1

	if Tasks.tracking.sourcesTotal > 0 then
		-- Update target progress - actual progress will interpolate smoothly
		Tasks.targetProgress = math.floor((Tasks.tracking.sourcesDone / Tasks.tracking.sourcesTotal) * 100)
		-- Ensure progress never exceeds 100%
		Tasks.targetProgress = math.min(Tasks.targetProgress, 100)
	else
		Tasks.targetProgress = 0
	end

	if Tasks.Config.DebugMode then
		print(
			string.format(
				"[Tasks] Source complete: %d/%d (%.0f%%)",
				Tasks.tracking.sourcesDone,
				Tasks.tracking.sourcesTotal,
				Tasks.targetProgress
			)
		)
	end
end

-- Reset the task system with cleanup
function Tasks.Reset()
	-- Clear all task data
	Tasks.queue = {}
	Tasks.status = "idle"
	Tasks.progress = 0
	Tasks.targetProgress = 0
	Tasks.message = ""
	Tasks.isRunning = false
	Tasks.callback = nil
	Tasks.currentSource = nil
	Tasks.completedTime = 0
	Tasks.opacity = 255

	-- Clear tracking data
	Tasks.tracking = {
		sourcesTotal = 0,
		sourcesDone = 0,
		sourceNames = {},
	}

	-- Force GC and cleanup
	collectgarbage("collect")

	-- Unregister any callbacks that might be lingering
	pcall(function()
		callbacks.Unregister("Draw", "TasksProcessCleanup")
		callbacks.Unregister("Draw", "TasksUpdateProgress")
	end)
end

-- Process all tasks directly - simpler approach
function Tasks.ProcessAll()
	-- Don't do anything if not running
	if not Tasks.isRunning then
		return
	end

	-- Process entire queue
	local totalResult = 0

	-- Show starting message
	Tasks.status = "running"
	Tasks.message = "Loading Database"

	-- Register the smooth progress update
	callbacks.Register("Draw", "TasksUpdateProgress", Tasks.UpdateProgress)

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

		-- Update target progress based on task index
		Tasks.targetProgress = math.floor((i - 1) / #Tasks.queue * 100)

		-- Yield to update UI
		coroutine.yield()

		-- Execute the task function directly with proper error handling
		local success, result = pcall(task.fn)

		if success then
			if type(result) == "number" then
				totalResult = totalResult + result
			end
		else
			-- Handle error and display message
			local errorMsg = tostring(result)
			Tasks.LogError("Error in " .. task.name, errorMsg)
		end

		-- Mark this source as done
		Tasks.SourceDone()

		-- Yield to update UI
		coroutine.yield()

		::continue::
	end

	-- Mark all processing as complete
	Tasks.status = "complete"
	Tasks.targetProgress = 100
	Tasks.completedTime = globals.RealTime()

	-- Run callback if provided with error handling
	if type(Tasks.callback) == "function" then
		local success, err = pcall(Tasks.callback, totalResult)
		if not success then
			Tasks.LogError("Callback failed", err)
		end
	end

	return totalResult
end

-- Handle smooth progress updates and fade-out with debug info
function Tasks.UpdateProgress()
	-- Smooth progress interpolation
	if Tasks.progress ~= Tasks.targetProgress then
		Tasks.progress = Tasks.progress + (Tasks.targetProgress - Tasks.progress) * Tasks.Config.SmoothFactor
		-- Clamp to avoid floating point issues
		if math.abs(Tasks.progress - Tasks.targetProgress) < 0.5 then
			Tasks.progress = Tasks.targetProgress
		end

		-- Add debug info to see progress values
		if Tasks.Config.DebugMode then
			print(string.format("[Tasks] Progress: %.1f%% -> %.1f%%", Tasks.progress, Tasks.targetProgress))
		end
	end

	-- Handle fade-out when complete
	if Tasks.status == "complete" and Tasks.completedTime > 0 then
		local currentTime = globals.RealTime()
		local timeSinceComplete = currentTime - Tasks.completedTime

		-- Debug the fade timing
		if Tasks.Config.DebugMode and timeSinceComplete > Tasks.fadeDelay then
			print(string.format("[Tasks] Fading out: %.1f seconds after completion", timeSinceComplete))
		end

		-- Start fade-out after delay
		if timeSinceComplete > Tasks.fadeDelay then
			local fadeTime = 1.0 -- fade out over 1 second
			local fadeProgress = math.min(1.0, (timeSinceComplete - Tasks.fadeDelay) / fadeTime)
			Tasks.opacity = math.floor(255 * (1.0 - fadeProgress))

			-- Debug opacity value
			if Tasks.Config.DebugMode then
				print(string.format("[Tasks] Opacity: %d", Tasks.opacity))
			end

			-- When fully faded out, reset
			if Tasks.opacity <= 0 then
				if Tasks.Config.DebugMode then
					print("[Tasks] Fully faded out, resetting")
				end
				Tasks.Reset()
				callbacks.Unregister("Draw", "TasksUpdateProgress")
			end
		end
	end
end

-- Draw progress UI function with cleaner, centered design
function Tasks.DrawProgressUI()
	-- Skip if fully transparent
	if Tasks.opacity <= 0 then
		return
	end

	-- Make sure fonts are initialized
	Tasks.InitFonts()

	-- Get screen dimensions for centered positioning
	local screenWidth, screenHeight = draw.GetScreenSize()

	-- Set up basic dimensions (centered on screen)
	local width = 280
	local height = 40 -- Reduced height for cleaner look
	local barHeight = 20
	local padding = 10

	-- Center horizontally, position near bottom of screen
	local x = math.floor((screenWidth - width) / 2)
	local y = math.floor(screenHeight - height - 40) -- 40px from bottom

	-- Draw background
	draw.Color(20, 20, 20, math.min(200, Tasks.opacity))
	draw.FilledRect(x, y, x + width, y + height)

	-- Draw border
	draw.Color(60, 120, 255, math.min(150, Tasks.opacity))
	draw.OutlinedRect(x, y, x + width, y + height)

	-- Title text - explicitly set font
	draw.SetFont(Tasks.Fonts.title)
	draw.Color(180, 225, 255, Tasks.opacity)

	-- Center align the title
	local titleText = "Database Update"
	local titleWidth = draw.GetTextSize(titleText)
	draw.Text(x + math.floor((width - titleWidth) / 2), y + 2, titleText)

	-- Progress bar background
	local barY = y + math.floor(height - barHeight - 4)
	draw.Color(40, 40, 40, math.min(180, Tasks.opacity))
	draw.FilledRect(x + padding, barY, x + width - padding, barY + barHeight)

	-- Progress bar fill
	local progressWidth = math.floor((width - 2 * padding) * (Tasks.progress / 100))
	draw.Color(30, 120, 255, Tasks.opacity)
	draw.FilledRect(x + padding, barY, x + padding + progressWidth, barY + barHeight)

	-- Progress percentage text - centered in the bar
	local percent = string.format("%d%%", math.floor(Tasks.progress))
	draw.SetFont(Tasks.Fonts.text)
	draw.Color(255, 255, 255, Tasks.opacity)

	-- Calculate position to center percentage in the progress bar
	local percentWidth = draw.GetTextSize(percent)
	local percentX = x + math.floor((width - percentWidth) / 2)
	local percentY = barY + math.floor((barHeight - 12) / 2)
	draw.Text(percentX, percentY, percent)
end

-- Add an explicit debug mode setter
function Tasks.EnableDebugMode(enable)
	Tasks.Config.DebugMode = (enable == true)
	print("[Tasks] Debug mode " .. (Tasks.Config.DebugMode and "enabled" or "disabled"))
	return Tasks.Config.DebugMode
end

-- Add force complete method to manually set completion state
function Tasks.ForceComplete(fadeDelay)
	Tasks.status = "complete"
	Tasks.targetProgress = 100
	Tasks.progress = 100
	Tasks.completedTime = globals.RealTime()

	if fadeDelay then
		Tasks.fadeDelay = fadeDelay
	end

	print("[Tasks] Forced completion state")
end

return Tasks
