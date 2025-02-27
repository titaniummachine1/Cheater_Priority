-- Minimal task system that just works
local Tasks = {
	isRunning = false,
	progress = 0,
	targetProgress = 0,
	message = "",
	status = "idle",
	currentSource = nil,
	completedSources = 0,
	totalSources = 0,
	completedTime = 0,
	Config = {
		SmoothFactor = 0.1, -- Higher = faster progress bar
		SimplifiedUI = true,
	},
}

-- Initialize fonts
local titleFont = draw.CreateFont("Verdana", 16, 800)
local textFont = draw.CreateFont("Verdana", 12, 400)

-- Initialize task tracking
function Tasks.Init(sourceCount)
	Tasks.totalSources = sourceCount or 0
	Tasks.completedSources = 0
	Tasks.progress = 0
	Tasks.targetProgress = 0
	Tasks.isRunning = true
	Tasks.status = "running"
	Tasks.message = "Loading Database"
	Tasks.currentSource = nil
	Tasks.completedTime = 0
end

-- Reset task system
function Tasks.Reset()
	-- Clean up any callbacks
	pcall(function()
		callbacks.Unregister("Draw", "TasksUpdateProgress")
	end)

	-- Reset state
	Tasks.isRunning = false
	Tasks.progress = 0
	Tasks.targetProgress = 0
	Tasks.status = "idle"
	Tasks.message = ""
	Tasks.currentSource = nil
	Tasks.completedSources = 0
	Tasks.totalSources = 0
	Tasks.completedTime = 0

	collectgarbage("collect")
end

-- Start processing a source
function Tasks.StartSource(sourceName)
	Tasks.currentSource = sourceName or "Unknown"
	Tasks.message = "Processing " .. Tasks.currentSource
end

-- Mark current source as complete
function Tasks.SourceDone()
	Tasks.completedSources = Tasks.completedSources + 1

	if Tasks.totalSources > 0 then
		Tasks.targetProgress = math.floor((Tasks.completedSources / Tasks.totalSources) * 100)
	end
end

-- Update progress with smoothing
function Tasks.UpdateProgress()
	-- Smooth progress bar
	if Tasks.progress ~= Tasks.targetProgress then
		Tasks.progress = Tasks.progress + (Tasks.targetProgress - Tasks.progress) * Tasks.Config.SmoothFactor
		if math.abs(Tasks.progress - Tasks.targetProgress) < 0.5 then
			Tasks.progress = Tasks.targetProgress
		end
	end

	-- Handle completion fade-out
	if Tasks.status == "complete" and Tasks.completedTime > 0 then
		if globals.RealTime() - Tasks.completedTime > 3 then
			Tasks.Reset()
		end
	end
end

-- Draw simple UI
function Tasks.DrawProgressUI()
	if not Tasks.isRunning then
		return
	end

	-- Update progress smoothly
	Tasks.UpdateProgress()

	-- Get screen dimensions
	local screenWidth, screenHeight = draw.GetScreenSize()

	-- Set up window dimensions
	local width = 260
	local height = 60
	local x = (screenWidth - width) / 2
	local y = screenHeight - height - 100

	-- Draw background and border
	draw.Color(20, 20, 20, 200)
	draw.FilledRect(x, y, x + width, y + height)
	draw.Color(60, 120, 255, 150)
	draw.OutlinedRect(x, y, x + width, y + height)

	-- Draw title
	draw.SetFont(titleFont)
	draw.Color(255, 255, 255, 255)
	local titleText = "Database Update"
	local titleWidth = draw.GetTextSize(titleText)
	draw.Text(x + (width - titleWidth) / 2, y + 5, titleText)

	-- Draw progress bar background
	local barY = y + 30
	local barHeight = 20
	draw.Color(40, 40, 40, 180)
	draw.FilledRect(x + 10, barY, x + width - 10, barY + barHeight)

	-- Draw progress bar
	local fillWidth = ((width - 20) * Tasks.progress) / 100
	draw.Color(30, 120, 255, 255)
	draw.FilledRect(x + 10, barY, x + 10 + fillWidth, barY + barHeight)

	-- Draw progress percentage
	draw.SetFont(textFont)
	draw.Color(255, 255, 255, 255)
	local percent = string.format("%d%%", math.floor(Tasks.progress))
	local percentWidth = draw.GetTextSize(percent)
	draw.Text(x + (width - percentWidth) / 2, barY + (barHeight - 12) / 2, percent)

	-- Draw message
	local message = Tasks.message
	if #message > 30 then
		message = message:sub(1, 27) .. "..."
	end
	local messageWidth = draw.GetTextSize(message)
	draw.Text(x + (width - messageWidth) / 2, y + height - 20, message)
end

-- Register automatic progress update
callbacks.Register("Draw", "TasksUpdateProgress", Tasks.UpdateProgress)

return Tasks
