local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Cheater Detection for Lmaobox Recode
    Author: titaniummachine1 (https://github.com/titaniummachine1)
    Credits:
    LNX (github.com/lnx00) for base script
    Muqa for visuals and design assistance
    Alchemist for testing and party callout
]]

--[[ Import core utilities ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Config = require("Cheater_Detection.Utils.Config")

--[[ Import database system ]]
local DBManager = require("Cheater_Detection.Database.Manager")

--[[ UI components ]]
require("Cheater_Detection.Misc.Visuals.Menu")

--[[ Detection modules (uncomment when needed) ]]
--local Detections = require("Cheater_Detection.Detections")
--require("Cheater_Detection.Visuals")
--require("Cheater_Detection.Modules.EventHandler")

--[[ Variables ]]
local WPlayer, PR = Common.WPlayer, Common.PlayerResource
local Commands = Common.Lib.Utils.Commands

--[[ Initialize systems ]]
local function InitializeSystems()
    -- Load config
    Config.LoadCFG()

    -- Initialize database system through manager (this handles loading, importing and auto-fetching)
    G.Database = DBManager.Initialize({
        AutoFetchOnLoad = true, -- Automatically fetch updates on startup
        CheckInterval = 24      -- Check for updates every 24 hours
    })

    -- Clear local player from cheater list (for debugging)
    local localPlayer = entities.GetLocalPlayer()
    if localPlayer then
        local mySteamID = Common.GetSteamID64(localPlayer)
        playerlist.SetPriority(mySteamID, 0)
    end

    -- Print initialization message
    local dbStats = DBManager.GetStats()
    printc(100, 255, 100, 255,
        string.format("[Cheater Detection] Initialized with %d database entries", dbStats.totalEntries))

    -- Register console commands for database management
    Commands.Register("cd_check", function(args)
        if #args < 1 then
            print("Usage: cd_check <steamid or name fragment>")
            return
        end

        local query = args[1]
        local found = false

        -- Check if it's a valid SteamID
        if query:match("^%d+$") and #query >= 17 then
            local record = G.Database.GetRecord(query)
            if record then
                found = true
                print(string.format("[Database] Found record for SteamID: %s", query))
                print(string.format("  Name: %s", record.Name or "Unknown"))
                print(string.format("  Cause: %s", record.cause or "Unknown"))
                print(string.format("  Date: %s", record.date or "Unknown"))
            end
        end

        -- If not found by SteamID, search by name
        if not found then
            local matches = 0
            for steamId, data in pairs(G.Database.content or {}) do
                if data.Name and data.Name:lower():find(query:lower()) then
                    matches = matches + 1
                    print(string.format("[Database] Match %d: %s (SteamID: %s)", matches, data.Name, steamId))
                    print(string.format("  Cause: %s", data.cause or "Unknown"))
                    print(string.format("  Date: %s", data.date or "Unknown"))

                    -- Limit to 5 matches to avoid spam
                    if matches >= 5 then
                        print(string.format("[Database] Found more matches, showing first 5 only"))
                        break
                    end
                end
            end

            if matches == 0 then
                print(string.format("[Database] No records found for: %s", query))
            end
        end
    end, "Check if a player is in the cheat database")
end

--[[ Update the player data every tick ]] --
local function OnCreateMove(cmd)
    local DebugMode = G.Menu.Main.debug
    G.pLocal = entities.GetLocalPlayer()
    G.players = entities.FindByClass("CTFPlayer")
    if not G.pLocal or not G.players then return end

    G.WLocal = WPlayer.FromEntity(G.pLocal)
    G.connectionState = PR.GetConnectionState()[G.pLocal:GetIndex()]

    for _, entity in ipairs(G.players) do
        -- Get the steamid for the player
        local steamid = Common.GetSteamID64(entity)
        if not steamid then
            warn("Failed to get SteamID for player %s", entity:GetName() or "nil")
            return
        end

        -- Check if player is a known cheater in database
        if G.Database and G.Database.GetRecord(steamid) then
            -- Player is in database, mark them
            local priority = playerlist.GetPriority(steamid)
            if priority < 10 then
                playerlist.SetPriority(steamid, 10)
            end
            -- Skip detection checks for known cheaters
            goto continue
        end

        if Common.IsValidPlayer(entity, true) and not Common.IsCheater(steamid) then
            -- Initialize player data if it doesn't exist
            if not G.PlayerData[steamid] then
                G.PlayerData[steamid] = G.DefaultPlayerData
            end

            local wrappedPlayer = WPlayer.FromEntity(entity)
            local viewAngles = wrappedPlayer:GetEyeAngles()
            local entityFlags = entity:GetPropInt("m_fFlags")
            local isOnGround = entityFlags & FL_ONGROUND == FL_ONGROUND
            local headHitboxPosition = wrappedPlayer:GetHitboxPos(1)
            local bodyHitboxPosition = wrappedPlayer:GetHitboxPos(4)
            local viewPos = wrappedPlayer:GetEyePos()
            local simulationTime = wrappedPlayer:GetSimulationTime()

            -- Gather player data
            G.PlayerData[steamid].Current = Common.createRecord(viewAngles, viewPos, headHitboxPosition,
                bodyHitboxPosition, simulationTime, isOnGround)

            -- Perform detection checks (when Detections module is enabled)
            if Detections then
                Detections.CheckAngles(wrappedPlayer, entity)
                Detections.CheckDuckSpeed(wrappedPlayer, entity)
                Detections.CheckBunnyHop(wrappedPlayer, entity)
                Detections.CheckPacketChoke(wrappedPlayer, entity)
                Detections.CheckSequenceBurst(wrappedPlayer, entity)
            end

            -- Update history
            G.PlayerData[steamid].History = G.PlayerData[steamid].History or {}
            table.insert(G.PlayerData[steamid].History, G.PlayerData[steamid].Current)

            -- Keep the history table size to a maximum of 66
            if #G.PlayerData[steamid].History > 66 then
                table.remove(G.PlayerData[steamid].History, 1)
            end
        end

        ::continue::
    end
end

--[[ Callbacks ]]
callbacks.Register("CreateMove", "Cheater_detection", OnCreateMove)

-- Initialize everything on script load
InitializeSystems()

-- Provide global access to main module functions
return {
    ReloadDatabase = function()
        G.Database = DBManager.Initialize({ AutoFetchOnLoad = true })
    end,

    UpdateDatabase = function()
        DBManager.ForceUpdate()
    end,

    GetDatabaseStats = DBManager.GetStats
}

end)
__bundle_register("Cheater_Detection.Misc.Visuals.Menu", function(require, _LOADED, __bundle_register, __bundle_modules)
local Menu = {}

local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")

local Lib = Common.Lib
local Fonts = Lib.UI.Fonts
local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)

local ImMenu = Common.ImMenu

local function DrawMenu()
    ImMenu.BeginFrame(1)

    if G.Menu.Advanced.debug then
        draw.Color(255, 0, 0, 255)
        draw.SetFont(Fonts.Verdana)
        draw.Text(20, 120, "Debug Mode!!! Some Features Might malfunction")
    end

    if gui.IsMenuOpen() and ImMenu.Begin("Cheater Detection", true) then
        -- Tabs for different sections
        ImMenu.BeginFrame(1)
            local tabs = {"Main", "Advanced", "Misc"}
            G.Menu.currentTab = ImMenu.TabControl(tabs, G.Menu.currentTab)
        ImMenu.EndFrame()

        draw.SetFont(Fonts.Verdana)
        draw.Color(255, 255, 255, 255)

        -- Main Configuration Tab
        if G.Menu.currentTab == "Main" then
            local Main = G.Menu.Main

            ImMenu.BeginFrame()
                Main.AutoMark = ImMenu.Checkbox("Auto Mark", Main.AutoMark)
                Main.partyCallaut = ImMenu.Checkbox("Party Callout", Main.partyCallaut)
                Main.Chat_Prefix = ImMenu.Checkbox("Chat Prefix", Main.Chat_Prefix)
                Main.Cheater_Tags = ImMenu.Checkbox("Cheater Tags", Main.Cheater_Tags)
                Main.JoinWarning = ImMenu.Checkbox("Join Warning", Main.JoinWarning)
            ImMenu.EndFrame()
        end

        -- Advanced Configuration Tab
        if G.Menu.currentTab == "Advanced" then
            local Advanced = G.Menu.Advanced

            ImMenu.BeginFrame()
                Advanced.Evicence_Tolerance = ImMenu.Slider("Evidence Tolerance", Advanced.Evicence_Tolerance, 1, 10)
            ImMenu.EndFrame()

            ImMenu.BeginFrame()
                Advanced.Choke = ImMenu.Checkbox("Choke Detection", Advanced.Choke)
                Advanced.Warp = ImMenu.Checkbox("Warp Detection", Advanced.Warp)
                Advanced.Bhop = ImMenu.Checkbox("Bhop Detection", Advanced.Bhop)
            ImMenu.EndFrame()

            ImMenu.BeginFrame()
                Advanced.Aimbot.enable = ImMenu.Checkbox("Aimbot Detection", Advanced.Aimbot.enable)
                if Advanced.Aimbot.enable then
                    Advanced.Aimbot.silent = ImMenu.Checkbox("Silent Aim", Advanced.Aimbot.silent)
                    Advanced.Aimbot.plain = ImMenu.Checkbox("Plain Aim", Advanced.Aimbot.plain)
                    Advanced.Aimbot.smooth = ImMenu.Checkbox("Smooth Aim", Advanced.Aimbot.smooth)
                end
            ImMenu.EndFrame()

            ImMenu.BeginFrame()
                Advanced.triggerbot = ImMenu.Checkbox("Triggerbot Detection", Advanced.triggerbot)
                Advanced.AntyAim = ImMenu.Checkbox("Anty-Aim Detection", Advanced.AntyAim)
                Advanced.DuckSpeed = ImMenu.Checkbox("Duck Speed Detection", Advanced.DuckSpeed)
                Advanced.Strafe_bot = ImMenu.Checkbox("Strafe Bot Detection", Advanced.Strafe_bot)
            ImMenu.EndFrame()

            ImMenu.BeginFrame()
                Advanced.debug = ImMenu.Checkbox("Debug Mode", Advanced.debug)
            ImMenu.EndFrame()
        end

        -- Misc Configuration Tab
        if G.Menu.currentTab == "Misc" then
            local Misc = G.Menu.Misc

            ImMenu.BeginFrame(1)
                Misc.Autovote = ImMenu.Checkbox("Enable Auto Vote", Misc.Autovote)
            ImMenu.EndFrame()

            if Misc.Autovote then
                ImMenu.BeginFrame(1)
                    Misc.intent.legit = ImMenu.Checkbox("Vote Legit Players", Misc.intent.legit)
                    Misc.intent.cheater = ImMenu.Checkbox("Vote Cheaters", Misc.intent.cheater)
                    Misc.intent.bot = ImMenu.Checkbox("Vote Bots", Misc.intent.bot)
                    Misc.intent.friend = ImMenu.Checkbox("Exclude Friends", Misc.intent.friend)
                ImMenu.EndFrame()
            end

            ImMenu.BeginFrame(1)
                Misc.Vote_Reveal.Enable = ImMenu.Checkbox("Vote Reveal", Misc.Vote_Reveal.Enable)
            ImMenu.EndFrame()

            if Misc.Vote_Reveal.Enable then
                ImMenu.BeginFrame(1)
                    Misc.Vote_Reveal.TargetTeam.MyTeam = ImMenu.Checkbox("My Team", Misc.Vote_Reveal.TargetTeam.MyTeam)
                    Misc.Vote_Reveal.TargetTeam.enemyTeam = ImMenu.Checkbox("Enemy Team", Misc.Vote_Reveal.TargetTeam.enemyTeam)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Misc.Vote_Reveal.PartyChat = ImMenu.Checkbox("Party Chat", Misc.Vote_Reveal.PartyChat)
                    Misc.Vote_Reveal.Console = ImMenu.Checkbox("Console Log", Misc.Vote_Reveal.Console)
                ImMenu.EndFrame()
            end

            -- Class Change Reveal moved to Misc as defined in Default_Config
            ImMenu.BeginFrame(1)
                Misc.Class_Change_Reveal.Enable = ImMenu.Checkbox("Class Change Reveal", Misc.Class_Change_Reveal.Enable)
            ImMenu.EndFrame()
            if Misc.Class_Change_Reveal.Enable then
                ImMenu.BeginFrame(1)
                    Misc.Class_Change_Reveal.EnemyOnly = ImMenu.Checkbox("Enemy Only", Misc.Class_Change_Reveal.EnemyOnly)
                    Misc.Class_Change_Reveal.PartyChat = ImMenu.Checkbox("Party Chat", Misc.Class_Change_Reveal.PartyChat)
                    Misc.Class_Change_Reveal.Console = ImMenu.Checkbox("Console Log", Misc.Class_Change_Reveal.Console)
                ImMenu.EndFrame()
            end

            ImMenu.BeginFrame(1)
                Misc.Chat_notify = ImMenu.Checkbox("Chat Notifications", Misc.Chat_notify)
            ImMenu.EndFrame()
        end

        ImMenu.End()
    end
end

--[[ Callbacks ]]
callbacks.Unregister("Draw", "CD_MENU")
callbacks.Register("Draw", "CD_MENU", DrawMenu)

return Menu
end)
__bundle_register("Cheater_Detection.Utils.Globals", function(require, _LOADED, __bundle_register, __bundle_modules)
local Globals = {}

Globals.AutoVote = {
    Options = { 'Yes', 'No' },
    VoteCommand = 'vote',
    VoteIdx = nil,
    VoteValue = nil, -- Set this to 1 for yes, 2 for no, or nil for off
}

--[[Shared Varaibles]]

Globals.players = {}
Globals.pLocal = nil
Globals.WLocal = nil
Globals.latin = nil
Globals.latout = nil

Globals.Menu = require("Cheater_Detection.Utils.DefaultConfig")

-- Global utility functions and UI helpers

local G = {
    Config = {
        DebugMode = false,
        ShowNotifications = true,
        NotificationDuration = 3,
        MaxMemoryUsageMB = 100 -- Target max memory usage
    },
    
    State = {
        LastNotification = 0,
        NotificationMessage = "",
        ProgressValue = 0,
        ProgressMessage = "",
        LastMemoryCheck = 0,
        MemoryCheckInterval = 5.0 -- Check memory every 5 seconds
    }
}

-- UI helper functions
G.UI = {
    -- Show a message in the UI and console
    ShowMessage = function(message, duration)
        if not message then return end
        
        -- Store for drawing
        G.State.NotificationMessage = message
        G.State.LastNotification = globals.RealTime()
        G.Config.NotificationDuration = duration or G.Config.NotificationDuration
        
        -- Also print to console
        print("[Cheater Detection] " .. message)
    end,
    
    -- Update progress indicator
    UpdateProgress = function(value, message)
        G.State.ProgressValue = value or G.State.ProgressValue
        G.State.ProgressMessage = message or G.State.ProgressMessage
    end,
    
    -- Draw notification if active
    DrawNotification = function()
        if not G.Config.ShowNotifications then return end
        
        local currentTime = globals.RealTime()
        local timeSinceNotification = currentTime - G.State.LastNotification
        
        -- If notification is expired, don't draw
        if timeSinceNotification > G.Config.NotificationDuration then return end
        
        -- Calculate fade-out
        local alpha = 255
        if timeSinceNotification > G.Config.NotificationDuration - 0.5 then
            alpha = math.floor(255 * (G.Config.NotificationDuration - timeSinceNotification) / 0.5)
        end
        
        -- Draw notification
        local x, y = 20, 100
        local padding = 10
        local message = G.State.NotificationMessage
        local width = draw.GetTextSize(message) + padding * 2
        
        -- Background
        draw.Color(20, 20, 20, math.min(200, alpha))
        draw.FilledRect(x, y, x + width, y + 30)
        
        -- Border
        draw.Color(80, 150, 255, alpha)
        draw.OutlinedRect(x, y, x + width, y + 30)
        
        -- Text
        draw.Color(255, 255, 255, alpha)
        draw.Text(x + padding, y + padding, message)
    end,
    
    -- Draw progress bar if active
    DrawProgressBar = function()
        if G.State.ProgressValue <= 0 then return end
        
        -- Draw progress bar at bottom of screen
        local width = 300
        local height = 20
        local x = (draw.GetScreenSize() - width) / 2
        local y = draw.GetScreenSize() - height - 20
        
        -- Background
        draw.Color(20, 20, 20, 200)
        draw.FilledRect(x, y, x + width, y + height)
        
        -- Progress fill
        local progressWidth = math.floor(width * (G.State.ProgressValue / 100))
        draw.Color(80, 150, 255, 255)
        draw.FilledRect(x, y, x + progressWidth, y + height)
        
        -- Border
        draw.Color(100, 170, 255, 255)
        draw.OutlinedRect(x, y, x + width, y + height)
        
        -- Progress text
        local percent = tostring(math.floor(G.State.ProgressValue)) .. "%"
        local textWidth = draw.GetTextSize(percent)
        draw.Color(255, 255, 255, 255)
        draw.Text(x + (width - textWidth) / 2, y + 3, percent)
        
        -- Message text
        if G.State.ProgressMessage and #G.State.ProgressMessage > 0 then
            draw.Text(x, y - 15, G.State.ProgressMessage)
        end
    end
}

-- Memory management helpers
G.Memory = {
    -- Check memory usage and perform cleanup if needed
    CheckMemory = function()
        local currentTime = globals.RealTime()
        if currentTime - G.State.LastMemoryCheck < G.State.MemoryCheckInterval then
            return
        end
        
        G.State.LastMemoryCheck = currentTime
        
        -- Check current memory usage
        local memoryUsage = collectgarbage("count") / 1024 -- MB
        
        -- If over threshold, perform cleanup
        if memoryUsage > G.Config.MaxMemoryUsageMB then
            -- Run incremental garbage collection
            collectgarbage("step", 1000) -- Run 1000 steps
            
            if G.Config.DebugMode then
                print(string.format("[Memory] Usage: %.2f MB - performing cleanup", memoryUsage))
            end
        end
    end,
    
    -- Force full cleanup
    ForceCleanup = function()
        collectgarbage("collect")
        collectgarbage("collect")
        
        if G.Config.DebugMode then
            print(string.format("[Memory] Forced cleanup - new usage: %.2f MB", 
                collectgarbage("count") / 1024))
        end
    end
}

-- Register draw callback for UI elements
callbacks.Register("Draw", "GlobalsUI", function()
    G.UI.DrawNotification()
    G.UI.DrawProgressBar()
    G.Memory.CheckMemory()
end)

return G
end)
__bundle_register("Cheater_Detection.Utils.DefaultConfig", function(require, _LOADED, __bundle_register, __bundle_modules)
local Default_Config = {
    currentTab = "Main",

    Main = {
        AutoMark = true,
        partyCallaut = true,
        Chat_Prefix = true,
        Cheater_Tags = true,
        JoinWarning = true,
    },

    Advanced = {
        Evicence_Tolerance = 5, --how many evidence more then average legit to mark as cheater 
        Choke = true, --fakelag
        Warp = true,
        Bhop = true,
        Aimbot = {
            enable = true,
            silent = true,
            plain = true,
            smooth = true,
        },
        triggerbot = true,
        AntyAim = true,
        DuckSpeed = true,
        Strafe_bot = true,

        debug = false,
    },

    Misc = {
        Autovote = true,
        intent = {
            legit = true,
            cheater = true,
            bot = true,
            friend = false,
        },
        Vote_Reveal = {
            Enable = true,
            TargetTeam = {
                MyTeam = true,
                enemyTeam = true,
            },
            PartyChat = true,
            Console = true,
        },
        Class_Change_Reveal = {
            Enable = true,
            EnemyOnly = true,
            PartyChat = true,
            Console = true,
        },
        Chat_notify = true,
    }
}

return Default_Config

end)
__bundle_register("Cheater_Detection.Utils.Common", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-set-field, undefined-field

-- Create and initialize the Common table first
local Common = {
    Lib = nil,
    ImMenu = nil,
    Json = nil,
    Log = nil,
    Notify = nil,
    TF2 = nil,
    Math = nil,
    Conversion = nil,
    WPlayer = nil,
    PR = nil,
    Helpers = nil
}

if UnloadLib ~= nil then UnloadLib() end

-- Unload the module if it's already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

--------------------------------------------------------------------------------------
--Library loading--
--------------------------------------------------------------------------------------

-- Function to download content from a URL
local function downloadFile(url)
    local success, body = pcall(http.Get, url)
    if not success or not body or body == "" then
        error("Failed to download file from " .. url .. ": " .. tostring(body))
    end
    return body
end

-- Load and validate library
local function loadlib(libName, libURL)
    if libName == "LNXlib" then
        -- First try to load local LNXlib if it exists
        local success, localLib = pcall(require, "lnxLib")
        
        if success and localLib then
            -- Local version exists and loaded successfully
            lnxLib = localLib
            print("Loaded local lnxLib")
        else
            -- Local version doesn't exist, download from GitHub
            print("Local lnxLib not found, downloading from GitHub...")
            local libContent
            
            -- Try to download with error handling
            local downloadSuccess, errorMsg = pcall(function()
                libContent = downloadFile(libURL)
                return true
            end)
            
            if not downloadSuccess or not libContent then
                error("Failed to download lnxLib: " .. tostring(errorMsg))
            end
            
            -- Execute downloaded code with error handling
            local executeSuccess, result = pcall(load, libContent)
            if not executeSuccess or not result then
                error("Failed to load lnxLib content: " .. tostring(result))
            end
            
            -- Execute the loaded code
            local runSuccess, lib = pcall(result)
            if not runSuccess or not lib then
                error("Failed to execute lnxLib: " .. tostring(lib))
            end
            
            -- Assign globally
            lnxLib = lib
            print("Downloaded and loaded lnxLib from GitHub")
        end
        
        -- Allow require("lnxLib") to return global
        package.preload["lnxLib"] = function()
            return lnxLib
        end
        
        return lnxLib
    else
        -- For ImMenu, load normally but modify its code first
        local libContent = downloadFile(libURL)
        if libName == "ImMenu" then
            -- Replace the header but keep rest of the code
            libContent = libContent:gsub(
                ".-\n\nlocal Fonts",  -- Match everything up to "local Fonts"
                '--[[ ImMenu ]]--\n\nlocal lnxLib = _G.lnxLib\nlocal Fonts'  -- Replace with our simple header
            )
        end

        -- Execute modified code and capture return value
        local libFunction = assert(load(libContent))
        return libFunction() -- Return the module table
    end
end

--why
local latestLNXlib = "https://" .. "github.com/lnx00/Lmaobox-Library/releases/latest/download/lnxLib.lua"

-- Initialize libraries in order
Common.Lib = loadlib("LNXlib", latestLNXlib)
Common.ImMenu = require("Cheater_Detection.Libs.ImMenu")
Common.Json = require("Cheater_Detection.Libs.Json")

local G = require("Cheater_Detection.Utils.Globals")

-- Now initialize remaining Common fields using the loaded libraries
Common.Log = Common.Lib.Utils.Logger.new("Cheater Detection")
Common.Notify = Common.Lib.UI.Notify
Common.TF2 = Common.Lib.TF2
Common.Math = Common.Lib.Utils.Math
Common.Conversion = Common.Lib.Utils.Conversion
Common.WPlayer = Common.Lib.TF2.WPlayer
Common.PR = Common.Lib.TF2.PlayerResource
Common.Helpers = Common.Lib.TF2.Helpers

local cachedSteamIDs = {}
local lastTick = -1

function Common.GetSteamID64(Player)
    assert(Player, "Player is nil")

    local currentTick = globals.TickCount()
    local playerIndex = Player:GetIndex()

    -- Branchless cache reset
    cachedSteamIDs, lastTick = (lastTick ~= currentTick and {} or cachedSteamIDs), currentTick

    -- Retrieve cached result or calculate it
    local result = cachedSteamIDs[playerIndex] or (function()
        local playerInfo = assert(client.GetPlayerInfo(playerIndex), "Failed to get player info")
        local steamID = assert(playerInfo.SteamID, "Failed to get SteamID")
        return (playerInfo.IsBot or playerInfo.IsHLTV or steamID == "[U:1:0]") and playerInfo.UserID or
            assert(steam.ToSteamID64(steamID), "Failed to convert SteamID to SteamID64")
    end)()

    cachedSteamIDs[playerIndex] = result
    return result
end

function Common.IsCheater(playerInfo)
    local steamId = nil

    if type(playerInfo) == "number" and playerInfo < 101 then
        -- Assuming playerInfo is the index
        local targetIndex = playerInfo
        local targetPlayer = nil

        -- Find the player with the same index
        for _, player in ipairs(G.players) do
            if player:GetIndex() == targetIndex then
                targetPlayer = player
                break
            end
        end

        -- Check if the target player was found
        if targetPlayer then
            steamId = assert(Common.GetSteamID64(targetPlayer), "Failed to get SteamID64 for player")
        else
            return false
        end
    elseif type(playerInfo) == "number" then
        -- If playerInfo is a number, convert it to a string and check its length
        local steamIdStr = tostring(playerInfo)
        if #steamIdStr == 17 then
            steamId = playerInfo
        else
            return false
        end
    elseif playerInfo.GetIndex then
        -- If playerInfo is a player entity, get its SteamID64
        steamId = assert(Common.GetSteamID64(playerInfo), "Failed to get SteamID64 for player entity")
    else
        -- If playerInfo is neither a valid index, a valid SteamID64, nor a player entity, return false
        return false
    end

    if not steamId then
        return false
    end

    -- Check if the player is marked as a cheater based on various criteria
    local strikes = G.PlayerData[steamId] and G.PlayerData[steamId].info.Strikes or 0
    local isMarkedCheater = G.PlayerData[steamId] and G.PlayerData[steamId].info.isCheater
    local inDatabase = G.DataBase[steamId] ~= nil
    local priorityCheater = playerlist.GetPriority(steamId) == 10

    return isMarkedCheater or inDatabase or priorityCheater
end

function Common.IsFriend(entity)
    return (not G.Menu.Main.debug and Common.TF2.IsFriend(entity:GetIndex(), true)) -- Entity is a freind and party member
end

function Common.IsValidPlayer(entity, checkFriend)
    -- Check if the entity is a valid player
    if not entity or entity:IsDormant() or not entity:IsAlive() then
        return false -- Entity is not a valid player
    end

    if checkFriend and Common.IsFriend(entity) then
        return false -- Entity is a friend, skip
    end

    return true -- Entity is a valid player
end

-- Create a common record structure
function Common.createRecord(angle, position, headHitbox, bodyHitbox, simTime, onGround)
    return {
        Angle = angle,
        ViewPos = position,
        Hitboxes = {
            Head = headHitbox,
            Body = bodyHitbox,
        },
        SimTime = simTime,
        onGround = onGround,
    }
end

function Common.FromSteamid32To64(steamid32)
    return "[U:1:" .. steamid32 .. "]"
end

-- More robust SteamID conversion functions
function Common.SteamID3ToSteamID64(steamID3)
    if not steamID3 then return nil end
    
    -- Try to extract the numeric part from [U:1:12345]
    local accountID = steamID3:match("%[U:1:(%d+)%]")
    if not accountID then return nil end
    
    -- Safe steam API conversion with error handling
    local success, steamID64 = pcall(steam.ToSteamID64, steamID3)
    if success and steamID64 and #steamID64 == 17 then
        return steamID64
    end
    
    -- Fallback manual conversion if steam API fails
    -- SteamID64 = 76561197960265728 + accountID
    return tostring(76561197960265728 + tonumber(accountID))
end

-- Helper function to determine if the content is JSON
function Common.isJson(content)
    local firstChar = content:sub(1, 1)
    return firstChar == "{" or firstChar == "["
end

--[[ Callbacks ]]
local function OnUnload()                        -- Called when the script is unloaded
    UnloadLib()                                  --unloading lualib
    engine.PlaySound("hl1/fvox/deactivated.wav") --deactivated
end

--[[ Unregister previous callbacks ]]               --
callbacks.Unregister("Unload", "CD_Unload")         -- unregister the "Unload" callback
--[[ Register callbacks ]]                          --
callbacks.Register("Unload", "CD_Unload", OnUnload) -- Register the "Unload" callback

--[[ Play sound when loaded ]]                      --
engine.PlaySound("hl1/fvox/activated.wav")

return Common

end)
__bundle_register("Cheater_Detection.Libs.Json", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
David Kolf's JSON module for Lua 5.1 - 5.4

Version 2.6


For the documentation see the corresponding readme.txt or visit
<http://dkolf.de/src/dkjson-lua.fsl/>.

You can contact the author by sending an e-mail to 'david' at the
domain 'dkolf.de'.


Copyright (C) 2010-2021 David Heiko Kolf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

---@alias JsonState { indent : boolean?, keyorder : integer[]?, level : integer?, buffer : string[]?, bufferlen : integer?, tables : table[]?, exception : function? }

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset =
    pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat =
    string.rep, string.gsub, string.sub, string.byte, string.char,
    string.find, string.len, string.format
local strmatch = string.match
local concat = table.concat

---@class Json
local json = { version = "dkjson 2.6.1 L" }

local _ENV = nil -- blocking globals in Lua 5.2 and later

json.null = setmetatable({}, {
    __tojson = function() return "null" end
})

local function isarray(tbl)
    local max, n, arraylen = 0, 0, 0
    for k, v in pairs(tbl) do
        if k == 'n' and type(v) == 'number' then
            arraylen = v
            if v > max then
                max = v
            end
        else
            if type(k) ~= 'number' or k < 1 or floor(k) ~= k then
                return false
            end
            if k > max then
                max = k
            end
            n = n + 1
        end
    end
    if max > 10 and max > arraylen and max > n * 2 then
        return false -- don't create an array with too many holes
    end
    return true, max
end

local escapecodes = {
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
}

local function escapeutf8(uchar)
    local value = escapecodes[uchar]
    if value then
        return value
    end
    local a, b, c, d = strbyte(uchar, 1, 4)
    a, b, c, d = a or 0, b or 0, c or 0, d or 0
    if a <= 0x7f then
        value = a
    elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
        value = (a - 0xc0) * 0x40 + b - 0x80
    elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
        value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
    elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
        value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
    else
        return ""
    end
    if value <= 0xffff then
        return strformat("\\u%.4x", value)
    elseif value <= 0x10ffff then
        -- encode as UTF-16 surrogate pair
        value = value - 0x10000
        local highsur, lowsur = 0xD800 + floor(value / 0x400), 0xDC00 + (value % 0x400)
        return strformat("\\u%.4x\\u%.4x", highsur, lowsur)
    else
        return ""
    end
end

local function fsub(str, pattern, repl)
    -- gsub always builds a new string in a buffer, even when no match
    -- exists. First using find should be more efficient when most strings
    -- don't contain the pattern.
    if strfind(str, pattern) then
        return gsub(str, pattern, repl)
    else
        return str
    end
end

local function quotestring(value)
    -- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
    value = fsub(value, "[%z\1-\31\"\\\127]", escapeutf8)
    if strfind(value, "[\194\216\220\225\226\239]") then
        value = fsub(value, "\194[\128-\159\173]", escapeutf8)
        value = fsub(value, "\216[\128-\132]", escapeutf8)
        value = fsub(value, "\220\143", escapeutf8)
        value = fsub(value, "\225\158[\180\181]", escapeutf8)
        value = fsub(value, "\226\128[\140-\143\168-\175]", escapeutf8)
        value = fsub(value, "\226\129[\160-\175]", escapeutf8)
        value = fsub(value, "\239\187\191", escapeutf8)
        value = fsub(value, "\239\191[\176-\191]", escapeutf8)
    end
    return "\"" .. value .. "\""
end
json.quotestring = quotestring

local function replace(str, o, n)
    local i, j = strfind(str, o, 1, true)
    if i then
        return strsub(str, 1, i - 1) .. n .. strsub(str, j + 1, -1)
    else
        return str
    end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint()
    decpoint = strmatch(tostring(0.5), "([^05+])")
    -- build a filter that can be used to remove group separators
    numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function num2str(num)
    return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

local function str2num(str)
    local num = tonumber(replace(str, ".", decpoint))
    if not num then
        updatedecpoint()
        num = tonumber(replace(str, ".", decpoint))
    end
    return num
end

local function addnewline2(level, buffer, buflen)
    buffer[buflen + 1] = "\n"
    buffer[buflen + 2] = strrep("  ", level)
    buflen = buflen + 2
    return buflen
end

function json.addnewline(state)
    if state.indent then
        state.bufferlen = addnewline2(state.level or 0,
            state.buffer, state.bufferlen or #(state.buffer))
    end
end

local encode2 -- forward declaration

local function addpair(key, value, prev, indent, level, buffer, buflen, tables, globalorder, state)
    local kt = type(key)
    if kt ~= 'string' and kt ~= 'number' then
        return nil, "type '" .. kt .. "' is not supported as a key by JSON."
    end
    if prev then
        buflen = buflen + 1
        buffer[buflen] = ","
    end
    if indent then
        buflen = addnewline2(level, buffer, buflen)
    end
    buffer[buflen + 1] = quotestring(key)
    buffer[buflen + 2] = ":"
    return encode2(value, indent, level, buffer, buflen + 2, tables, globalorder, state)
end

local function appendcustom(res, buffer, state)
    local buflen = state.bufferlen
    if type(res) == 'string' then
        buflen = buflen + 1
        buffer[buflen] = res
    end
    return buflen
end

local function exception(reason, value, state, buffer, buflen, defaultmessage)
    defaultmessage = defaultmessage or reason
    local handler = state.exception
    if not handler then
        return nil, defaultmessage
    else
        state.bufferlen = buflen
        local ret, msg = handler(reason, value, state, defaultmessage)
        if not ret then return nil, msg or defaultmessage end
        return appendcustom(ret, buffer, state)
    end
end

function json.encodeexception(reason, value, state, defaultmessage)
    return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function(value, indent, level, buffer, buflen, tables, globalorder, state)
    local valtype = type(value)
    local valmeta = getmetatable(value)
    valmeta = type(valmeta) == 'table' and valmeta -- only tables
    local valtojson = valmeta and valmeta.__tojson
    if valtojson then
        if tables[value] then
            return exception('reference cycle', value, state, buffer, buflen)
        end
        tables[value] = true
        state.bufferlen = buflen
        local ret, msg = valtojson(value, state)
        if not ret then return exception('custom encoder failed', value, state, buffer, buflen, msg) end
        tables[value] = nil
        buflen = appendcustom(ret, buffer, state)
    elseif value == nil then
        buflen = buflen + 1
        buffer[buflen] = "null"
    elseif valtype == 'number' then
        local s
        if value ~= value or value >= huge or -value >= huge then
            -- This is the behaviour of the original JSON implementation.
            s = "null"
        else
            s = num2str(value)
        end
        buflen = buflen + 1
        buffer[buflen] = s
    elseif valtype == 'boolean' then
        buflen = buflen + 1
        buffer[buflen] = value and "true" or "false"
    elseif valtype == 'string' then
        buflen = buflen + 1
        buffer[buflen] = quotestring(value)
    elseif valtype == 'table' then
        if tables[value] then
            return exception('reference cycle', value, state, buffer, buflen)
        end
        tables[value] = true
        level = level + 1
        local isa, n = isarray(value)
        if n == 0 and valmeta and valmeta.__jsontype == 'object' then
            isa = false
        end
        local msg
        if isa then -- JSON array
            buflen = buflen + 1
            buffer[buflen] = "["
            for i = 1, n do
                buflen, msg = encode2(value[i], indent, level, buffer, buflen, tables, globalorder, state)
                if not buflen then return nil, msg end
                if i < n then
                    buflen = buflen + 1
                    buffer[buflen] = ","
                end
            end
            buflen = buflen + 1
            buffer[buflen] = "]"
        else -- JSON object
            local prev = false
            buflen = buflen + 1
            buffer[buflen] = "{"
            local order = valmeta and valmeta.__jsonorder or globalorder
            if order then
                local used = {}
                n = #order
                for i = 1, n do
                    local k = order[i]
                    local v = value[k]
                    if v ~= nil then
                        used[k] = true
                        buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                        prev = true -- add a seperator before the next element
                    end
                end
                for k, v in pairs(value) do
                    if not used[k] then
                        buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                        if not buflen then return nil, msg end
                        prev = true -- add a seperator before the next element
                    end
                end
            else -- unordered
                for k, v in pairs(value) do
                    buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
                    if not buflen then return nil, msg end
                    prev = true -- add a seperator before the next element
                end
            end
            if indent then
                buflen = addnewline2(level - 1, buffer, buflen)
            end
            buflen = buflen + 1
            buffer[buflen] = "}"
        end
        tables[value] = nil
    else
        return exception('unsupported type', value, state, buffer, buflen,
            "type '" .. valtype .. "' is not supported by JSON.")
    end
    return buflen
end

---Encodes a lua table to a JSON string.
---@param value any
---@param state? JsonState
---@return string|boolean
function json.encode(value, state)
    state = state or {}
    local oldbuffer = state.buffer
    local buffer = oldbuffer or {}
    state.buffer = buffer
    updatedecpoint()
    local ret, msg = encode2(value, state.indent, state.level or 0,
        buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state)
    if not ret then
        error(msg, 2)
    elseif oldbuffer == buffer then
        state.bufferlen = ret
        return true
    else
        state.bufferlen = nil
        state.buffer = nil
        return concat(buffer)
    end
end

local function loc(str, where)
    local line, pos, linepos = 1, 1, 0
    while true do
        pos = strfind(str, "\n", pos, true)
        if pos and pos < where then
            line = line + 1
            linepos = pos
            pos = pos + 1
        else
            break
        end
    end
    return "line " .. line .. ", column " .. (where - linepos)
end

local function unterminated(str, what, where)
    return nil, strlen(str) + 1, "unterminated " .. what .. " at " .. loc(str, where)
end

local function scanwhite(str, pos)
    while true do
        pos = strfind(str, "%S", pos)
        if not pos then return nil end
        local sub2 = strsub(str, pos, pos + 1)
        if sub2 == "\239\187" and strsub(str, pos + 2, pos + 2) == "\191" then
            -- UTF-8 Byte Order Mark
            pos = pos + 3
        elseif sub2 == "//" then
            pos = strfind(str, "[\n\r]", pos + 2)
            if not pos then return nil end
        elseif sub2 == "/*" then
            pos = strfind(str, "*/", pos + 2)
            if not pos then return nil end
            pos = pos + 2
        else
            return pos
        end
    end
end

local escapechars = {
    ["\""] = "\"",
    ["\\"] = "\\",
    ["/"] = "/",
    ["b"] = "\b",
    ["f"] = "\f",
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t"
}

local function unichar(value)
    if value < 0 then
        return nil
    elseif value <= 0x007f then
        return strchar(value)
    elseif value <= 0x07ff then
        return strchar(0xc0 + floor(value / 0x40),
            0x80 + (floor(value) % 0x40))
    elseif value <= 0xffff then
        return strchar(0xe0 + floor(value / 0x1000),
            0x80 + (floor(value / 0x40) % 0x40),
            0x80 + (floor(value) % 0x40))
    elseif value <= 0x10ffff then
        return strchar(0xf0 + floor(value / 0x40000),
            0x80 + (floor(value / 0x1000) % 0x40),
            0x80 + (floor(value / 0x40) % 0x40),
            0x80 + (floor(value) % 0x40))
    else
        return nil
    end
end

local function scanstring(str, pos)
    local lastpos = pos + 1
    local buffer, n = {}, 0
    while true do
        local nextpos = strfind(str, "[\"\\]", lastpos)
        if not nextpos then
            return unterminated(str, "string", pos)
        end
        if nextpos > lastpos then
            n = n + 1
            buffer[n] = strsub(str, lastpos, nextpos - 1)
        end
        if strsub(str, nextpos, nextpos) == "\"" then
            lastpos = nextpos + 1
            break
        else
            local escchar = strsub(str, nextpos + 1, nextpos + 1)
            local value
            if escchar == "u" then
                value = tonumber(strsub(str, nextpos + 2, nextpos + 5), 16)
                if value then
                    local value2
                    if 0xD800 <= value and value <= 0xDBff then
                        -- we have the high surrogate of UTF-16. Check if there is a
                        -- low surrogate escaped nearby to combine them.
                        if strsub(str, nextpos + 6, nextpos + 7) == "\\u" then
                            value2 = tonumber(strsub(str, nextpos + 8, nextpos + 11), 16)
                            if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
                                value = (value - 0xD800) * 0x400 + (value2 - 0xDC00) + 0x10000
                            else
                                value2 = nil -- in case it was out of range for a low surrogate
                            end
                        end
                    end
                    value = value and unichar(value)
                    if value then
                        if value2 then
                            lastpos = nextpos + 12
                        else
                            lastpos = nextpos + 6
                        end
                    end
                end
            end
            if not value then
                value = escapechars[escchar] or escchar
                lastpos = nextpos + 2
            end
            n = n + 1
            buffer[n] = value
        end
    end
    if n == 1 then
        return buffer[1], lastpos
    elseif n > 1 then
        return concat(buffer), lastpos
    else
        return "", lastpos
    end
end

local scanvalue -- forward declaration

local function scantable(what, closechar, str, startpos, nullval, objectmeta, arraymeta)
    local tbl, n = {}, 0
    local pos = startpos + 1
    if what == 'object' then
        setmetatable(tbl, objectmeta)
    else
        setmetatable(tbl, arraymeta)
    end
    while true do
        pos = scanwhite(str, pos)
        if not pos then return unterminated(str, what, startpos) end
        local char = strsub(str, pos, pos)
        if char == closechar then
            return tbl, pos + 1
        end
        local val1, err
        val1, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
        if err then return nil, pos, err end
        pos = scanwhite(str, pos)
        if not pos then return unterminated(str, what, startpos) end
        char = strsub(str, pos, pos)
        if char == ":" then
            if val1 == nil then
                return nil, pos, "cannot use nil as table index (at " .. loc(str, pos) .. ")"
            end
            pos = scanwhite(str, pos + 1)
            if not pos then return unterminated(str, what, startpos) end
            local val2
            val2, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
            if err then return nil, pos, err end
            tbl[val1] = val2
            pos = scanwhite(str, pos)
            if not pos then return unterminated(str, what, startpos) end
            char = strsub(str, pos, pos)
        else
            n = n + 1
            tbl[n] = val1
        end
        if char == "," then
            pos = pos + 1
        end
    end
end

scanvalue = function(str, pos, nullval, objectmeta, arraymeta)
    pos = pos or 1
    pos = scanwhite(str, pos)
    if not pos then
        return nil, strlen(str) + 1, "no valid JSON value (reached the end)"
    end
    local char = strsub(str, pos, pos)
    if char == "{" then
        return scantable('object', "}", str, pos, nullval, objectmeta, arraymeta)
    elseif char == "[" then
        return scantable('array', "]", str, pos, nullval, objectmeta, arraymeta)
    elseif char == "\"" then
        return scanstring(str, pos)
    else
        local pstart, pend = strfind(str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
        if pstart then
            local number = str2num(strsub(str, pstart, pend))
            if number then
                return number, pend + 1
            end
        end
        pstart, pend = strfind(str, "^%a%w*", pos)
        if pstart then
            local name = strsub(str, pstart, pend)
            if name == "true" then
                return true, pend + 1
            elseif name == "false" then
                return false, pend + 1
            elseif name == "null" then
                return nullval, pend + 1
            end
        end
        return nil, pos, "no valid JSON value at " .. loc(str, pos)
    end
end

local function optionalmetatables(...)
    if select("#", ...) > 0 then
        return ...
    else
        return { __jsontype = 'object' }, { __jsontype = 'array' }
    end
end

---@param str string
---@param pos integer?
---@param nullval any?
---@param ... table?
function json.decode(str, pos, nullval, ...)
    local objectmeta, arraymeta = optionalmetatables(...)
    return scanvalue(str, pos, nullval, objectmeta, arraymeta)
end

return json

end)
__bundle_register("Cheater_Detection.Libs.ImMenu", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Immediate mode menu library for Lmaobox
    Author: github.com/lnx00
]]

-- Get the global lnxLib instance instead of requiring Common
if not lnxLib then
    error("lnxLib not found. Make sure it's loaded before ImMenu")
end

local Fonts, Notify = lnxLib.UI.Fonts, lnxLib.UI.Notify
local KeyHelper, Input, Timer = lnxLib.Utils.KeyHelper, lnxLib.Utils.Input, lnxLib.Utils.Timer

-- Annotation aliases
---@alias ImItemID string
---@alias ImPos { X : integer, Y : integer }
---@alias ImWindow { X : integer, Y : integer, W : integer, H : integer }
---@alias ImFrame { X : integer, Y : integer, W : integer, H : integer, A : integer }
---@alias ImColor table<integer, integer, integer, integer?>
---@alias ImStyle any

--[[ Globals ]]
---@enum ImAlign
ImAlign = { Vertical = 0, Horizontal = 1 }

---@class ImMenu
---@field public Cursor ImPos
---@field public ActiveItem ImItemID|nil
ImMenu = {
    Cursor = { X = 0, Y = 0 },
    ActiveItem = nil,
    ActivePopup = nil
}

--[[ Variables ]]
local screenWidth, screenHeight = draw.GetScreenSize()
local dragPos = { X = 0, Y = 0 }
local lastKey = { Key = 0, Time = 0 }
local inPopup = false

-- Input Helpers
MouseHelper = KeyHelper.new(MOUSE_LEFT)
EnterHelper = KeyHelper.new(KEY_ENTER)
LeftArrow = KeyHelper.new(KEY_LEFT)
RightArrow = KeyHelper.new(KEY_RIGHT)

---@type table<string, ImWindow>
Windows = {}

---@type function[]
LateDrawList = {}

---@type ImColor[]
Colors = {
    Title = { 55, 100, 215, 255 },
    Text = { 255, 255, 255, 255 },
    Window = { 30, 30, 30, 255 },
    Item = { 50, 50, 50, 255 },
    ItemHover = { 60, 60, 60, 255 },
    ItemActive = { 70, 70, 70, 255 },
    Highlight = { 180, 180, 180, 100 },
    HighlightActive = { 240, 240, 240, 140 },
    WindowBorder = { 55, 100, 215, 255 },
    FrameBorder = { 0, 0, 0, 200 },
    Border = { 0, 0, 0, 200 }
}

---@type ImStyle[]
Style = {
    Font = Fonts.Verdana,
    ItemPadding = 5,
    ItemMargin = 5,
    FramePadding = 5,
    ItemSize = nil,
    WindowBorder = true,
    FrameBorder = false,
    ButtonBorder = false,
    CheckboxBorder = false,
    SliderBorder = false,
    Border = false,
    Popup = false
}

-- Stacks
WindowStack = Stack.new()
FrameStack = Stack.new()
ColorStack = Stack.new()
StyleStack = Stack.new()

--[[ Private Functions ]]
---@param color ImColor
local function UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 255
end

-- Returns a pressed key suitable for operations (function keys, arrows, etc.)
---@return integer?
function GetOperationKey()
    for i = KEY_F1, KEY_F12 do
        if input.IsButtonDown(i) then
            return i
        end
    end
    for _, key in ipairs({
        KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, 
        KEY_PAGEUP, KEY_PAGEDOWN, KEY_INSERT, KEY_DELETE, KEY_ESCAPE
    }) do
        if input.IsButtonDown(key) then
            return key
        end
    end
    return nil
end

---@return integer?
local function GetInput()
    local key = Input.GetPressedKey() or GetOperationKey()
    if not key then
        lastKey.Key = 0
        return nil
    end

    if key == lastKey.Key then
        if lastKey.Time + 0.5 < globals.RealTime() then
            return key
        else
            return nil
        end
    end

    lastKey.Key = key
    lastKey.Time = globals.RealTime()
    return key
end

--[[ Public Getters ]]

---@return number
function ImMenu.GetVersion() return 0.66 end

---@return ImStyle[]
function ImMenu.GetStyle() return table.readOnly(Style) end

---@return ImColor[]
function ImMenu.GetColors() return table.readOnly(Colors) end

---@return ImWindow
function ImMenu.GetCurrentWindow() return WindowStack:peek() end

---@return ImFrame
function ImMenu.GetCurrentFrame() return FrameStack:peek() end

--[[ Public Setters ]]
-- Push a color to the stack
---@param key string
---@param color ImColor
function ImMenu.PushColor(key, color)
    ColorStack:push({ Key = key, Value = Colors[key] })
    Colors[key] = color
end

-- Pop the last color from the stack
---@param amount? integer
function ImMenu.PopColor(amount)
    amount = amount or 1
    for _ = 1, amount do
        local color = ColorStack:pop()
        Colors[color.Key] = color.Value
    end
end

-- Push a style to the stack
---@param key string
---@param style ImStyle
function ImMenu.PushStyle(key, style)
    StyleStack:push({ Key = key, Value = Style[key] })
    Style[key] = style
end

-- Pop the last style from the stack
---@param amount? integer
function ImMenu.PopStyle(amount)
    amount = amount or 1
    for _ = 1, amount do
        local style = StyleStack:pop()
        Style[style.Key] = style.Value
    end
end

--[[ Public Functions ]]
-- Creates a new color attribute
---@param key string
---@param value any
function ImMenu.AddColor(key, value)
    Colors[key] = value
end

-- Creates a new style attribute
---@param key string
---@param value any
function ImMenu.AddStyle(key, value)
    Style[key] = value
end

-- Runs all late draw functions
function ImMenu.LateDraw()
    draw.Color(255, 255, 255, 255)

    -- Run all late draw functions
    for _, func in ipairs(LateDrawList) do
        func()
    end

    LateDrawList = {}
end

-- Updates the cursor and current frame size
---@param w integer
---@param h integer
function ImMenu.UpdateCursor(w, h)
    local frame = ImMenu.GetCurrentFrame()
    if frame then
        if frame.A == 0 then
            -- Horizontal
            ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.ItemMargin
            frame.W = math.max(frame.W, w)
            frame.H = math.max(frame.H, ImMenu.Cursor.Y - frame.Y)
        elseif frame.A == 1 then
            -- Vertical
            ImMenu.Cursor.X = ImMenu.Cursor.X + w + Style.ItemMargin
            frame.W = math.max(frame.W, ImMenu.Cursor.X - frame.X)
            frame.H = math.max(frame.H, h)
        end
    else
        -- TODO: It shouldn't be allowed to draw outside of a frame
        ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.ItemMargin
    end
end

-- Updates the next color depending on the interaction state
---@param hovered boolean
---@param active boolean
function ImMenu.InteractionColor(hovered, active)
    if active then
        draw.Color(UnpackColor(Colors.ItemActive))
    elseif hovered then
        draw.Color(UnpackColor(Colors.ItemHover))
    else
        draw.Color(UnpackColor(Colors.Item))
    end
end

---@param width integer
---@param height integer
---@return integer width, integer height
function ImMenu.GetSize(width, height)
    if Style.ItemSize ~= nil then
        width, height = Style.ItemSize[1], Style.ItemSize[2]
    end

    return width, height
end

-- Returns whether the element is clicked or active
---@param x number
---@param y number
---@param width number
---@param height number
---@param id string
---@return boolean hovered, boolean clicked, boolean active
function ImMenu.GetInteraction(x, y, width, height, id)
    -- Is a different element active?
    if ImMenu.ActiveItem ~= nil and ImMenu.ActiveItem ~= id then
        return false, false, false
    end

    -- Is a popup active?
    if ImMenu.ActivePopup ~= nil and not inPopup then
        return false, false, false
    end

    local hovered = Input.MouseInBounds(x, y, x + width, y + height) or id == ImMenu.ActiveItem
    local clicked = hovered and (MouseHelper:Pressed() or EnterHelper:Pressed())
    local active = hovered and (MouseHelper:Down() or EnterHelper:Down())

    -- Should this element be active?
    if active and ImMenu.ActiveItem == nil then
        ImMenu.ActiveItem = id
    end

    -- Is this element no longer active?
    if ImMenu.ActiveItem == id and not active then
        ImMenu.ActiveItem = nil
    end

    return hovered, clicked, active
end

---@param text string
function ImMenu.GetLabel(text)
    for label in text:gmatch("(.+)###(.+)") do
        return label
    end

    return text
end

---@param size? number
function ImMenu.Space(size)
    size = size or Style.ItemMargin
    ImMenu.UpdateCursor(size, size)
end

function ImMenu.Separator()
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local currentWindow = ImMenu.GetCurrentWindow()
    local width = currentWindow.W - Style.FramePadding * 2
    local height = Style.ItemMargin * 2

    draw.Color(UnpackColor(Colors.WindowBorder))
    draw.Line(x, y + height // 2, x + width, y + height // 2)

    ImMenu.UpdateCursor(width, height)
end


-- Begins a new frame
---@param titleOrAlign string|integer
---@param align? integer
function ImMenu.BeginFrame(titleOrAlign, align)
    local title = nil
    if type(titleOrAlign) == "string" then
        title = titleOrAlign
    elseif type(titleOrAlign) == "number" then
        align = titleOrAlign
    end
    align = align or 0

    local frame = {
        X = ImMenu.Cursor.X,
        Y = ImMenu.Cursor.Y,
        W = 0,
        H = 0,
        A = align,
        Title = title,
        Children = {}
    }

    FrameStack:push(frame)
    
    -- Apply padding
    ImMenu.Cursor.X = ImMenu.Cursor.X + Style.FramePadding
    ImMenu.Cursor.Y = ImMenu.Cursor.Y + Style.FramePadding

    -- Draw title if provided
    if title then
        local txtWidth, txtHeight = draw.GetTextSize(title)
        frame.TitleHeight = txtHeight + Style.FramePadding * 2

        -- Calculate frame width to the right side of the menu
        local currentWindow = ImMenu.GetCurrentWindow()
        local frameWidth = currentWindow.W - Style.FramePadding * 4

        -- Draw title background
        draw.Color(UnpackColor(Colors.Title))
        draw.FilledRect(frame.X, frame.Y, frame.X + frameWidth, frame.Y + frame.TitleHeight)

        -- Draw title text centered
        draw.Color(UnpackColor(Colors.Text))
        local textX = frame.X + (frameWidth - txtWidth) // 2
        draw.Text(textX, frame.Y + Style.FramePadding, title)

        -- Draw frame background
        draw.Color(UnpackColor(Colors.Title))
        draw.FilledRect(frame.X, frame.Y + frame.TitleHeight, frame.X + frameWidth, frame.Y + frame.H + frame.TitleHeight)

        ImMenu.Space(5)
        ImMenu.Cursor.Y = ImMenu.Cursor.Y + frame.TitleHeight + Style.ItemMargin
    end
end


-- Ends the current frame
---@return ImFrame frame
function ImMenu.EndFrame()
    ---@type ImFrame
    local frame = FrameStack:pop()

    -- Process children
    for _, child in ipairs(frame.Children) do
        child.W = math.max(child.W, ImMenu.Cursor.X - child.X)
        child.H = ImMenu.Cursor.Y - child.Y
        frame.W = math.max(frame.W, child.W)
        frame.H = frame.H + child.H + Style.ItemMargin

        -- Draw child frame background and border
        draw.Color(UnpackColor(Colors.Item))
        draw.FilledRect(child.X, child.Y, child.X + child.W, child.Y + child.H)
        if Style.FrameBorder then
            draw.Color(UnpackColor(Colors.FrameBorder))
            draw.OutlinedRect(child.X, child.Y, child.X + child.W, child.Y + child.H)
        end
    end

    ImMenu.Cursor.X = frame.X
    ImMenu.Cursor.Y = frame.Y

    -- Apply padding
    if frame.A == 0 then
        -- Horizontal
        frame.W = frame.W + Style.FramePadding * 2
        frame.H = frame.H + Style.FramePadding - Style.ItemMargin
    elseif frame.A == 1 then
        -- Vertical
        frame.H = frame.H + Style.FramePadding * 2
        frame.W = frame.W + Style.FramePadding - Style.ItemMargin
    end

    -- Update the cursor
    ImMenu.UpdateCursor(frame.W, frame.H)

    return frame
end

-- Load a bold font
local BoldFont = draw.CreateFont("Verdana Bold", 18, 800)

-- Begins a new window
---@param title string
---@param visible? boolean
---@return boolean visible
function ImMenu.Begin(title, visible)
    local isVisible = (visible == nil) or visible
    if not isVisible then return false end

    -- Create the window if it doesn't exist
    if not Windows[title] then
        Windows[title] = {
            X = 50,
            Y = 150,
            W = 100,
            H = 100
        }
    end

    -- Initialize the window
    local window = Windows[title]
    draw.SetFont(BoldFont)  -- Set the bold font before getting text size
    local titleText = ImMenu.GetLabel(title)
    local txtWidth, txtHeight = draw.GetTextSize(titleText)
    local titleHeight = txtHeight + Style.ItemPadding
    local hovered, clicked, active = ImMenu.GetInteraction(window.X, window.Y, window.W, titleHeight, title)

    -- Title bar
    draw.Color(table.unpack(Colors.Title))
    draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H)
    draw.FilledRect(window.X, window.Y, window.X + window.W, window.Y + titleHeight)

    -- Title text with shadow and bold font
    local titleX = window.X + (window.W // 2) - (txtWidth // 2)
    local titleY = window.Y + (titleHeight // 2) - (txtHeight // 2)

    draw.TextShadow(titleX + 1, titleY + 1, titleText)  -- Draw shadow

    draw.Color(255, 255, 255, 255)  -- Dark text color
    draw.Text(titleX, titleY, titleText)

    -- Background
    draw.Color(table.unpack(Colors.Window))
    draw.FilledRect(window.X, window.Y + titleHeight, window.X + window.W, window.Y + window.H + titleHeight)

    -- Border
    if Style.WindowBorder then
        draw.Color(UnpackColor(Colors.WindowBorder))
        draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H + titleHeight)
        draw.Line(window.X, window.Y + titleHeight, window.X + window.W, window.Y + titleHeight)
    end

    -- Mouse drag
    local mX, mY = table.unpack(input.GetMousePos())
    if clicked then
        window.DragPos = { X = mX - window.X, Y = mY - window.Y }
        window.IsDragging = true
    elseif not input.IsButtonDown(MOUSE_LEFT) and not clicked then
        window.IsDragging = false
    end

    if window.IsDragging then
        window.X = math.clamp(mX - window.DragPos.X, 0, screenWidth - window.W)
        window.Y = math.clamp(mY - window.DragPos.Y, 0, screenHeight - window.H - titleHeight)
    end

    -- Update the cursor
    ImMenu.Cursor.X = window.X
    ImMenu.Cursor.Y = window.Y + titleHeight

    ImMenu.BeginFrame()

    -- Store and push the window
    Windows[title] = window
    WindowStack:push(window)

    return true
end


-- Ends the current window
---@return ImWindow
function ImMenu.End()
    ---@type ImFrame
    local frame = ImMenu.EndFrame()
    local window = WindowStack:pop()

    -- Update the window size
    window.W = frame.W
    window.H = frame.H

    -- Draw late draw list
    ImMenu.LateDraw()

    return window
end

-- Runs the given function after the current window has been drawn
function ImMenu.DrawLate(func)
    table.insert(LateDrawList, func)
end

---@param x integer
---@param y integer
---@param func function
function ImMenu.Popup(x, y, func)
    ImMenu.DrawLate(function()
        inPopup = true

        -- Prepare cursor
        ImMenu.Cursor.X = x
        ImMenu.Cursor.Y = y

        -- Draw the popup | TODO: Add a popup frame background
        ImMenu.PushStyle("FramePadding", 0)
        ImMenu.PushStyle("ItemMargin", 0)
        ImMenu.BeginFrame()
        func()
        local frame = ImMenu.EndFrame()
        ImMenu.PopStyle(2)

        -- Close the popup if clicked outside of it
        if not Input.MouseInBounds(frame.X, frame.Y, frame.X + frame.W, frame.Y + frame.H) and MouseHelper:Pressed() then
            ImMenu.ActivePopup = nil
        end

        inPopup = false
    end)
end

-- Draw a label
---@param text string
function ImMenu.Text(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(txtWidth, txtHeight)

    if type(Colors.Text) == "table" then
        draw.Color(math.floor(Colors.Text[1] or 0), math.floor(Colors.Text[2] or 0), math.floor(Colors.Text[3] or 0), math.floor(Colors.Text[4] or 255))
    end
    draw.Text(math.floor(x + (width - txtWidth) / 2), math.floor(y + (height - txtHeight) / 2), label)

    ImMenu.UpdateCursor(width, height)
end

---@param text string
---@param state boolean
---@return boolean state, boolean clicked
function ImMenu.Checkbox(text, state)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local boxSize = txtHeight + Style.ItemPadding * 2
    local width, height = ImMenu.GetSize(boxSize + Style.ItemMargin + txtWidth, boxSize)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Box
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(math.floor(x), math.floor(y), math.floor(x + boxSize), math.floor(y + boxSize))

    -- Border
    if Style.CheckboxBorder and type(Colors.Border) == "table" then
        draw.Color(math.floor(Colors.Border[1] or 0), math.floor(Colors.Border[2] or 0), math.floor(Colors.Border[3] or 0), math.floor(Colors.Border[4] or 255))
        draw.OutlinedRect(math.floor(x), math.floor(y), math.floor(x + boxSize), math.floor(y + boxSize))
    end

    -- Check
    if state then
        if type(Colors.Highlight) == "table" then
            draw.Color(math.floor(Colors.Highlight[1] or 0), math.floor(Colors.Highlight[2] or 0), math.floor(Colors.Highlight[3] or 0), math.floor(Colors.Highlight[4] or 255))
        end
        draw.FilledRect(math.floor(x + Style.ItemPadding), math.floor(y + Style.ItemPadding), math.floor(x + boxSize - Style.ItemPadding), math.floor(y + boxSize - Style.ItemPadding))
    end

    -- Text
    if type(Colors.Text) == "table" then
        draw.Color(math.floor(Colors.Text[1] or 0), math.floor(Colors.Text[2] or 0), math.floor(Colors.Text[3] or 0), math.floor(Colors.Text[4] or 255))
    end
    draw.Text(math.floor(x + boxSize + Style.ItemMargin), math.floor(y + (height - txtHeight) / 2), label)

    -- Update State
    if clicked then
        state = not state
    end

    ImMenu.UpdateCursor(width, height)
    return state, clicked
end

-- Draws a button
---@param text string
---@return boolean clicked, boolean active
function ImMenu.Button(text)
    -- Ensure text is a string
    if type(text) ~= "string" then
        error("Expected 'text' to be a string, got " .. type(text))
    end

    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(txtWidth + Style.ItemPadding * 2, txtHeight + Style.ItemPadding * 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(math.floor(x), math.floor(y), math.floor(x + width), math.floor(y + height))

    if Style.ButtonBorder and type(Colors.Border) == "table" then
        draw.Color(math.floor(Colors.Border[1] or 0), math.floor(Colors.Border[2] or 0), math.floor(Colors.Border[3] or 0), math.floor(Colors.Border[4] or 255))
        draw.OutlinedRect(math.floor(x), math.floor(y), math.floor(x + width), math.floor(y + height))
    end

    -- Text
    if type(Colors.Text) == "table" then
        draw.Color(math.floor(Colors.Text[1] or 0), math.floor(Colors.Text[2] or 0), math.floor(Colors.Text[3] or 0), math.floor(Colors.Text[4] or 255))
    end
    draw.Text(math.floor(x + (width - txtWidth) / 2), math.floor(y + (height - txtHeight) / 2), label)

    if clicked then
        ImMenu.ActiveItem = nil
    end

    ImMenu.UpdateCursor(width, height)
    return clicked, active
end


---@param id Texture
function ImMenu.Texture(id)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = ImMenu.GetSize(draw.GetTextureSize(id))

    draw.Color(255, 255, 255, 255)
    draw.TexturedRect(id, x, y, x + width, y + height)

    if Style.Border then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    ImMenu.UpdateCursor(width, height)
end

-- Draws a slider that changes a value with fancy visual effects and text shadow
---@param text string
---@param value number
---@param min number
---@param max number
---@param step? number
---@return number value, boolean clicked
function ImMenu.Slider(text, value, min, max, step)
    step = step or 1
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = string.format("%s: %s", ImMenu.GetLabel(text), value)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)
    local sliderWidth = math.floor(width * (value - min) / (max - min))
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Ensure sliderWidth is within bounds
    sliderWidth = math.max(0, math.min(sliderWidth, width))

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Slider
    draw.Color(UnpackColor(Colors.Highlight))
    draw.FilledRect(x, y, x + sliderWidth, y + height)

    -- Border
    if Style.SliderBorder then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Add a glow effect at the end of the slider
    if sliderWidth > 1 then
        draw.Color(255, 255, 255, 150)
        draw.FilledRect(x + sliderWidth - 2, y - 2, x + sliderWidth + 2, y + height + 2)
    end


    -- Text with shadow
    draw.Color(0, 0, 0, 150)  -- Shadow color
    draw.TextShadow(x + (width // 2) - (txtWidth // 2) + 1, y + (height // 2) - (txtHeight // 2) + 1, label)  -- Draw shadow

    -- Higher contrast text color
    draw.Color(255, 255, 255, 255)  -- White color for the text
    draw.Text(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), label)


    -- Update Value
    if active then
        -- Mouse drag
        local mX, mY = table.unpack(input.GetMousePos())
        local percent = math.clamp((mX - x) / width, 0, 1)
        value = math.round((min + (max - min) * percent) / step) * step
    elseif hovered then
        -- Arrow keys
        if LeftArrow:Pressed() then
            value = math.max(value - step, min)
        elseif RightArrow:Pressed() then
            value = math.min(value + step, max)
        end
    end

    ImMenu.UpdateCursor(width, height)
    return value, clicked
end

-- Quadratic easing function for interpolation
local function easeInOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return -1 + (4 - 2 * t) * t
    end
end

-- Unpack a color from table
local function UnpackColor(color)
    return math.floor(color[1]), math.floor(color[2]), math.floor(color[3]), math.floor(color[4] or 255)
end

-- Draws a progress bar with fancy visual effects
---@param value number
---@param min number
---@param max number
---@param interpolate boolean optional
function ImMenu.Progress(value, min, max, interpolate)
    interpolate = interpolate or false

    local x, y = math.floor(ImMenu.Cursor.X or 0), math.floor(ImMenu.Cursor.Y or 0)
    local width, height = ImMenu.GetSize(250, 15)

    -- Ensure width and height are integers and not nil
    width = math.floor(width or 250)
    height = math.floor(height or 15)

    -- Ensure progress value is within bounds
    value = math.max(min, math.min(max, value))
    local targetProgressWidth = math.floor(width * (value - min) / (max - min))

    -- Initialize progress tracking if needed
    if not ImMenu.ProgressState then
        ImMenu.ProgressState = {
            currentWidth = targetProgressWidth,
            lastTargetWidth = targetProgressWidth,
            lastTick = globals.TickCount()
        }
    end

    -- Interpolation logic
    if interpolate then
        local currentTick = globals.TickCount()
        local elapsedTicks = currentTick - ImMenu.ProgressState.lastTick

        -- Adjust speed based on the distance from the target
        local distance = math.abs(targetProgressWidth - ImMenu.ProgressState.currentWidth)
        local speed = math.max(0.5, distance / 10) -- Adjust the divisor for speed control

        -- Smooth interpolation to the target value
        ImMenu.ProgressState.currentWidth = ImMenu.ProgressState.currentWidth + (targetProgressWidth - ImMenu.ProgressState.currentWidth) * easeInOutQuad(math.min(elapsedTicks / 10, 1))

        -- Update last target width and last tick for continuous interpolation
        ImMenu.ProgressState.lastTargetWidth = targetProgressWidth
        ImMenu.ProgressState.lastTick = currentTick
    else
        ImMenu.ProgressState.currentWidth = targetProgressWidth
    end

    local progressWidth = math.floor(ImMenu.ProgressState.currentWidth)

    -- Ensure progressWidth is within bounds
    progressWidth = math.max(0, math.min(progressWidth, width))

    -- Background
    draw.Color(UnpackColor(Colors.Item))
    draw.FilledRect(x, y, x + width, y + height)

    -- Progress
    draw.Color(0, 255, 0, 255)  -- Solid green color
    draw.FilledRect(x, y, x + progressWidth, y + height)

    -- Border
    if Style.Border then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Add a thinner glow effect at the end of the progress bar
    if progressWidth > 0 then
        draw.Color(255, 255, 255, 150)
        draw.FilledRect(x + progressWidth - 1, y - 1, x + progressWidth + 1, y + height + 1)
    end

    ImMenu.UpdateCursor(width, height)
end



---@param label string
---@param text string
---@param charLimit? integer
---@return string text
function ImMenu.TextInput(label, text, charLimit)
    charLimit = charLimit or 50  -- Set default character limit to 50

    -- Initialize static variables for cursor and writing mode
    if not ImMenu.TextInputState then
        ImMenu.TextInputState = {
            cursorPos = #text,
            blinkTimer = globals.RealTime(),
            isWriting = false
        }
    end

    local state = ImMenu.TextInputState
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local defaultWidth, defaultHeight = 250, txtHeight + Style.ItemPadding * 2
    local width = math.max(defaultWidth, txtWidth + Style.ItemPadding * 2)
    local height = defaultHeight
    local txtY = y + (height // 2) - (txtHeight // 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, label)

    -- Toggle writing mode
    if clicked then
        state.isWriting = not state.isWriting
    elseif MouseHelper:Pressed() and not hovered and state.isWriting then
        state.isWriting = false
    end

    -- Adjust the width dynamically based on text size
    txtWidth, txtHeight = draw.GetTextSize(text)
    width = math.max(defaultWidth, txtWidth + Style.ItemPadding * 2)

    -- Background
    ImMenu.InteractionColor(hovered, state.isWriting)
    draw.FilledRect(x, y, x + width, y + height)

    -- Border
    draw.Color(UnpackColor(Colors.Border))
    draw.OutlinedRect(x, y, x + width, y + height)

    -- Text rendering
    draw.Color(UnpackColor(Colors.Text))
    local displayText = text
    local cursorX = x + Style.ItemPadding + draw.GetTextSize(text:sub(1, state.cursorPos))
    draw.Text(x + Style.ItemPadding, txtY, displayText)

    -- Simple blinking cursor
    if state.isWriting then
        local blinkPeriod = 1.0
        local shouldShowCursor = (globals.RealTime() - state.blinkTimer) % blinkPeriod < blinkPeriod / 2
        if shouldShowCursor then
            draw.Color(UnpackColor(Colors.Highlight))
            draw.FilledRect(cursorX, txtY, cursorX + 2, txtY + txtHeight)
        end
    end

    -- Text Input
    if state.isWriting then
        local key = GetInput()
        if key then
            if key == KEY_BACKSPACE then
                if state.cursorPos > 0 then
                    text = text:sub(1, state.cursorPos - 1) .. text:sub(state.cursorPos + 1)
                    state.cursorPos = math.max(0, state.cursorPos - 1)
                end
            elseif key == KEY_LEFT then
                state.cursorPos = math.max(0, state.cursorPos - 1)
            elseif key == KEY_RIGHT then
                state.cursorPos = math.min(#text, state.cursorPos + 1)
            elseif key == KEY_DELETE then
                if state.cursorPos < #text then
                    text = text:sub(1, state.cursorPos) .. text:sub(state.cursorPos + 2)
                end
            elseif key == KEY_HOME then
                state.cursorPos = 0
            elseif key == KEY_END then
                state.cursorPos = #text
            elseif key == KEY_SPACE then
                if #text < charLimit then
                    text = text:sub(1, state.cursorPos) .. " " .. text:sub(state.cursorPos + 1)
                    state.cursorPos = state.cursorPos + 1
                end
            elseif key == KEY_TAB then
                if #text < charLimit then
                    text = text:sub(1, state.cursorPos) .. "\t" .. text:sub(state.cursorPos + 1)
                    state.cursorPos = state.cursorPos + 1
                end
            else
                local char = Input.KeyToChar(key)
                if char and #text < charLimit then
                    if input.IsButtonDown(KEY_LSHIFT) then
                        char = char:upper()
                    else
                        char = char:lower()
                    end
                    text = text:sub(1, state.cursorPos) .. char .. text:sub(state.cursorPos + 1)
                    state.cursorPos = state.cursorPos + 1
                end
            end
            state.blinkTimer = globals.RealTime()  -- Reset blink timer on input
        end
    end

    -- Adjust cursor for the next item
    ImMenu.UpdateCursor(width, height)
    return text
end


---@param selected integer
---@param options any[]
---@return integer selected
function ImMenu.Option(selected, options)
    -- Check if the inputs are of the correct type
    if type(selected) ~= "number" then
        error("Expected a number for 'selected', got " .. type(selected))
    end
    if type(options) ~= "table" then
        error("Expected a table for 'options', got " .. type(options))
    end

    -- Handle empty options
    if #options == 0 then
        error("Options table is empty")
    end

    local txtWidth, txtHeight = draw.GetTextSize("#")
    local btnSize = txtHeight + 2 * Style.ItemPadding
    local width, height = ImMenu.GetSize(250, txtHeight)

    -- Begin frame for the option control
    ImMenu.PushStyle("ItemSize", { btnSize, btnSize })
    ImMenu.PushStyle("FramePadding", 0)
    ImMenu.BeginFrame(ImAlign.Horizontal)

    -- Last Item button
    if ImMenu.Button("<###prev") then
        selected = ((selected - 2) % #options) + 1
        print("Selected previous option:", selected)
    end

    -- Current Item display
    ImMenu.PushStyle("ItemSize", { width - (2 * btnSize) - (2 * Style.ItemMargin), btnSize })
    if options[selected] then
        ImMenu.Text(tostring(options[selected]))
    else
        ImMenu.Text("Invalid selection")
    end
    ImMenu.PopStyle()

    -- Next Item button
    if ImMenu.Button(">###next") then
        selected = (selected % #options) + 1
        print("Selected next option:", selected)
    end

    -- End frame and pop styles
    ImMenu.EndFrame()
    ImMenu.PopStyle(2)

    return selected
end


---@param text string
---@param items string[]
function ImMenu.List(text, items)
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)

    ImMenu.PushStyle("FramePadding", 0)
    ImMenu.PushStyle("ItemSize", { width, height })
    ImMenu.BeginFrame()

    -- Title
    ImMenu.Text(text)

    -- Items
    for _, item in ipairs(items) do
        ImMenu.Button(tostring(item))
    end

    ImMenu.EndFrame()
    ImMenu.PopStyle(2)
end


---@param text string
---@param selected table
---@param options string[]
---@return table selected
function ImMenu.Combo(text, selected, options)
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)

    -- Dropdown button
    ImMenu.PushStyle("ItemSize", { width, height })
    if ImMenu.Button(text) then
        ImMenu.ActivePopup = text
    end

    -- Dropdown popup
    if ImMenu.ActivePopup == text then
        ImMenu.Popup(ImMenu.Cursor.X, ImMenu.Cursor.Y, function()
            ImMenu.PushStyle("ItemSize", { width, height })

            for i, option in ipairs(options) do
                local isSelected = selected[i] or false
                if isSelected then
                    ImMenu.PushColor("Item", Colors.ItemActive) -- Highlight selected option
                end

                if ImMenu.Button(tostring(option)) then
                    selected[i] = not selected[i]
                end

                if isSelected then
                    ImMenu.PopColor()
                end
            end

            ImMenu.PopStyle(1)
        end)
    end

    ImMenu.PopStyle()

    return selected
end

---@param tabs table<string, boolean>|table<number, string>
---@param currentTab string
---@return string currentTab
function ImMenu.TabControl(tabs, currentTab)
    if type(tabs) ~= "table" then
        error("Expected 'tabs' to be a table, got " .. type(tabs))
    end
    if type(currentTab) ~= "string" then
        error("Expected 'currentTab' to be a string, got " .. type(currentTab))
    end

    ImMenu.PushStyle("FramePadding", 5)
    ImMenu.PushStyle("ItemSize", {100, 25})
    ImMenu.PushStyle("Spacing", {5, 5})
    ImMenu.BeginFrame(1)

    -- Use ipairs if 'tabs' is an array, otherwise use pairs.
    if #tabs > 0 then
        for _, tabName in ipairs(tabs) do
            if ImMenu.Button(tabName) then
                currentTab = tabName
            end
        end
    else
        for tabName, _ in pairs(tabs) do
            if ImMenu.Button(tabName) then
                currentTab = tabName
            end
        end
    end

    ImMenu.EndFrame()
    ImMenu.PopStyle(3)

    return currentTab
end

local function GetPressedkeyAndMouse()
    local pressedKey = Input.GetPressedKey()
        if not pressedKey then
            -- Check for standard mouse buttons
            if input.IsButtonDown(MOUSE_LEFT) then return MOUSE_LEFT end
            if input.IsButtonDown(MOUSE_RIGHT) then return MOUSE_RIGHT end
            if input.IsButtonDown(MOUSE_MIDDLE) then return MOUSE_MIDDLE end

            -- Check for additional mouse buttons
            for i = 1, 10 do
                if input.IsButtonDown(MOUSE_FIRST + i - 1) then return MOUSE_FIRST + i - 1 end
            end
        end
    return pressedKey
end

local bindTimers = {}
local bindDelays = {}
local keybindStates = {}
local keybindModes = {}
local keybindActiveStates = {}
local keybindModeSelection = {}

---@param text string
function ImMenu.GetKeybind(text)
    local mode = keybindModes[text]
    local keybind = keybindStates[text] and GetPressedkeyAndMouse() or 0

    if mode == "Always On" then
        return true
    elseif mode == "Always Off" then
        return false
    elseif mode == "Press to Toggle" then
        if input.IsButtonDown(keybind) and not bindTimers[text .. "_Toggle"] then
            keybindActiveStates[text] = not keybindActiveStates[text]
            bindTimers[text .. "_Toggle"] = os.clock() + 0.25
        end
        if bindTimers[text .. "_Toggle"] and os.clock() > bindTimers[text .. "_Toggle"] then
            bindTimers[text .. "_Toggle"] = nil
        end
        return keybindActiveStates[text]
    elseif mode == "Hold to Use" then
        return input.IsButtonDown(keybind)
    end

    return false
end

---@param text string
function ImMenu.Keybind(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local defaultWidth, height = ImMenu.GetSize(250, 25)

    -- Initialize state for this keybind
    if not bindTimers[text] then
        bindTimers[text] = 0
        bindDelays[text] = 0.25  -- Delay of 0.25 seconds
        keybindStates[text] = "Always On"
        keybindModes[text] = "Always On"
        keybindActiveStates[text] = true
        keybindModeSelection[text] = false
    end

    -- Determine the label based on the current state
    local displayLabel = keybindStates[text]
    if keybindStates[text] == "Press The Key" then
        displayLabel = "Press the key"
    end

    local label = text .. ": " .. displayLabel .. " (" .. keybindModes[text] .. ")"
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width = math.max(defaultWidth, txtWidth + Style.ItemPadding * 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Border
    if Style.ButtonBorder then
        draw.Color(UnpackColor(Colors.Highlight))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Handle key binding process
    if keybindStates[text] ~= "Press The Key" and clicked then
        bindTimers[text] = os.clock() + bindDelays[text]
        keybindStates[text] = "Press The Key"
    end

    if keybindStates[text] == "Press The Key" then
        if os.clock() >= bindTimers[text] then
            local pressedKey = GetPressedkeyAndMouse()
            if pressedKey then
                if pressedKey == KEY_ESCAPE then
                    -- Reset keybind if the Escape key is pressed
                    keybindStates[text] = "Always On"
                    keybindModes[text] = "Always On"
                    Notify.Simple("Keybind Success", "Bound Key: " .. keybindStates[text], 2)
                else
                    -- Update keybind with the pressed key
                    keybindStates[text] = Input.GetKeyName(pressedKey)
                    Notify.Simple("Keybind Success", "Bound Key: " .. keybindStates[text], 2)
                end
            end
        end
    end

    -- Right-click to select mode
    if input.IsButtonPressed(MOUSE_RIGHT) and Input.MouseInBounds(x, y, x + width, y + height) then
        ImMenu.ActivePopup = text .. "_Mode"
    end

    if ImMenu.ActivePopup == text .. "_Mode" then
        ImMenu.Popup(ImMenu.Cursor.X + width + 1, ImMenu.Cursor.Y, function()
            if ImMenu.Button("Always On") then
                keybindModes[text] = "Always On"
                ImMenu.ActivePopup = nil
            elseif ImMenu.Button("Always Off") then
                keybindModes[text] = "Always Off"
                ImMenu.ActivePopup = nil
            elseif ImMenu.Button("Press to Toggle") then
                keybindModes[text] = "Press to Toggle"
                ImMenu.ActivePopup = nil
            elseif ImMenu.Button("Hold to Use") then
                keybindModes[text] = "Hold to Use"
                ImMenu.ActivePopup = nil
            end
        end)
    end

    -- Display the current keybind name and mode
    label = text .. ": " .. displayLabel .. " (" .. keybindModes[text] .. ")"
    txtWidth, txtHeight = draw.GetTextSize(label)
    draw.Color(UnpackColor(Colors.Text))
    draw.Text(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), label)

    ImMenu.UpdateCursor(width, height)
end


lnxLib.UI.Notify.Simple("ImMenu loaded", string.format("Version: %.2f", ImMenu.GetVersion()))

return ImMenu
end)
__bundle_register("Cheater_Detection.Database.Manager", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ 
    Database Manager module - Centralized control of database operations
    Allows for easy initialization, updating, and management of databases
]]

-- Import required components
local Database = require("Cheater_Detection.Database.Database")
local Fetcher = require("Cheater_Detection.Database.Database_Fetcher")
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands

local Manager = {}

-- Configuration options
Manager.Config = {
    AutoFetchOnLoad = true,  -- Automatically fetch database updates on script load
    CheckInterval = 24,      -- How often to automatically check for updates (in hours)
    LastCheck = 0,           -- Timestamp of last update check
    MaxEntries = 20000,      -- Maximum number of database entries (performance optimization)
}

-- Initialize database system completely
function Manager.Initialize(options)
    options = options or {}
    
    -- Override default config with provided options
    for k, v in pairs(options) do
        Manager.Config[k] = v
    end
    
    -- Load local database first
    local startTime = globals.RealTime()
    Database.LoadDatabase(false) -- Not silent, show loading message
    
    -- If auto-fetch is enabled, set up fetcher
    if Manager.Config.AutoFetchOnLoad then
        -- Configure fetcher
        Fetcher.Config.AutoFetchOnLoad = true
        Fetcher.Config.NotifyOnFetchComplete = true
        
        -- Schedule fetch for next frame to ensure everything is loaded
        local firstUpdateDone = false
        callbacks.Register("Draw", "CDDatabaseManager_InitialFetch", function()
            if not firstUpdateDone then
                firstUpdateDone = true
                Fetcher.AutoFetch(Database)
                callbacks.Unregister("Draw", "CDDatabaseManager_InitialFetch")
            end
        end)
    end
    
    -- Return the fully initialized database
    return Database
end

-- Add a new data source
function Manager.AddSource(name, url, cause, type)
    return Fetcher.AddSource(name, url, cause, type or "raw")
end

-- Force an immediate database update
function Manager.ForceUpdate()
    Database.FetchUpdates(false)
end

-- Get database stats 
function Manager.GetStats()
    local entries = 0
    local byType = {}
    
    for steamId, data in pairs(Database.content or {}) do
        entries = entries + 1
        local cause = data.cause or "Unknown"
        byType[cause] = (byType[cause] or 0) + 1
    end
    
    return {
        totalEntries = entries,
        byType = byType,
        lastFetch = Fetcher.Config.LastAutoFetch,
        lastUpdate = Manager.Config.LastCheck
    }
end

-- Register database management commands
Commands.Register("cd_db_stats", function()
    local stats = Manager.GetStats()
    print(string.format("[Database Manager] Total entries: %d", stats.totalEntries))
    print("[Database Manager] Entries by type:")
    for cause, count in pairs(stats.byType) do
        print(string.format("  - %s: %d", cause, count))
    end
    print(string.format("[Database Manager] Last fetch: %s", os.date("%Y-%m-%d %H:%M:%S", stats.lastFetch)))
end, "Show database statistics")

-- Update database command
Commands.Register("cd_update", function()
    Manager.ForceUpdate()
end, "Update the cheater database from online sources")

-- Purge old database entries to improve performance
Commands.Register("cd_cleanup", function()
    if not Database.content then
        print("[Database Manager] No database loaded")
        return
    end
    
    local beforeCount = 0
    for _ in pairs(Database.content) do
        beforeCount = beforeCount + 1
    end
    
    -- Keep track of entries to remove
    local toRemove = {}
    local twoWeeksAgo = os.time() - (14 * 24 * 60 * 60) -- 14 days ago
    
    -- Find old entries
    for steamId, data in pairs(Database.content) do
        -- If entry has a date, check if it's older than 2 weeks
        -- and doesn't have special causes we want to keep
        if data.date then
            -- Try to parse the date
            local year, month, day = data.date:match("(%d+)%-(%d+)%-(%d+)")
            if year and month and day then
                local entryTime = os.time({
                    year = tonumber(year),
                    month = tonumber(month),
                    day = tonumber(day),
                    hour = 0, min = 0, sec = 0
                })
                
                -- Exclude certain categories from cleanup
                local keepCause = data.cause and (
                    data.cause:match("Bot") or
                    data.cause:match("RGL") or
                    data.cause:match("Community")
                )
                
                -- Mark for removal if old and not a special case
                if entryTime < twoWeeksAgo and not keepCause then
                    table.insert(toRemove, steamId)
                end
            end
        end
    end
    
    -- Remove old entries
    for _, steamId in ipairs(toRemove) do
        Database.content[steamId] = nil
    end
    
    -- Save the cleaned database
    Database.SaveDatabase()
    
    -- Count entries after cleanup
    local afterCount = 0
    for _ in pairs(Database.content) do
        afterCount = afterCount + 1
    end
    
    print(string.format("[Database Manager] Removed %d old entries, keeping %d entries", 
        beforeCount - afterCount, afterCount))
end, "Remove old database entries to improve performance")

return Manager

end)
__bundle_register("Cheater_Detection.Database.Database_Fetcher", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Database_Fetcher.lua - Improved version
    Fetches cheater databases from online sources with delays to prevent IP bans
    Uses smooth interpolation for progress display
]]

-- Import required modules
local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands
local Json = Common.Json

-- Load components
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")
local Sources = require("Cheater_Detection.Database.Database_Fetcher.Sources")
local Parsers = require("Cheater_Detection.Database.Database_Fetcher.Parsers")

-- Create fetcher object with improved configuration
local Fetcher = {
    Config = {
        -- Basic settings
        AutoFetchOnLoad = false,       -- Auto fetch when script loads
        AutoSaveAfterFetch = true,     -- Save database after fetching
        NotifyOnFetchComplete = true,  -- Show completion notifications
        ShowProgressBar = true,        -- Show progress UI
        
        -- Anti-ban protection settings
        MinSourceDelay = 4,            -- Minimum seconds between sources
        MaxSourceDelay = 8,            -- Maximum seconds between sources
        RequestTimeout = 15,           -- Seconds to wait before timeout
        EnableRandomDelay = true,      -- Add random delay variation
        
        -- UI settings
        SmoothingFactor = 0.05,        -- Lower = smoother but slower progress bar
        
        -- Auto-fetch settings
        AutoFetchInterval = 0,         -- Minutes between auto-fetches (0 = disabled)
        LastAutoFetch = 0,             -- Timestamp of last auto-fetch
        
        -- Debug settings
        DebugMode = false              -- Enable debug output
    }
}

-- Export components
Fetcher.Tasks = Tasks
Fetcher.Sources = Sources.List

-- Add smooth progress variables
Fetcher.UI = {
    targetProgress = 0,
    currentProgress = 0,
    completedSources = 0,
    totalSources = 0
}

-- Get a randomized delay between sources
function Fetcher.GetSourceDelay()
    local minDelay = Fetcher.Config.MinSourceDelay
    local maxDelay = Fetcher.Config.MaxSourceDelay
    
    if Fetcher.Config.EnableRandomDelay then
        -- Random delay in the configured range
        return minDelay + math.random() * (maxDelay - minDelay)
    else
        -- Use the mid-point
        return (minDelay + maxDelay) / 2
    end
end

-- Improved batch processing system that correctly tracks progress
function Fetcher.ProcessSourceInBatches(source, database)
    if not source or not source.url or not database then
        return 0, "Invalid source configuration"
    end
    
    -- Set up tracking variables
    local addedCount = 0
    local sourceUrl = source.url
    local sourceName = source.name
    local sourceRawData = nil
    local errorMessage = nil
    
    -- Step 1: Download the content
    Tasks.message = "Downloading from " .. sourceName .. "..."
    sourceRawData = Parsers.Download(sourceUrl)
    
    -- If download failed, try a backup URL if available
    if not sourceRawData or #sourceRawData == 0 then
        -- Try GitHub fallback for bots.tf
        if sourceName == "bots.tf" then
            Tasks.message = "Primary source failed, trying backup..."
            sourceRawData = Parsers.Download("https://raw.githubusercontent.com/PazerOP/tf2_bot_detector/master/staging/cfg/playerlist.official.json")
        end
        
        -- Still failed
        if not sourceRawData or #sourceRawData == 0 then
            return 0, "Download failed"
        end
    end
    
    -- Step 2: Determine the parser to use
    local parser = nil
    if source.parser == "raw" then
        parser = Parsers.ProcessRawList
    elseif source.parser == "tf2db" then
        parser = Parsers.ProcessTF2DB
    else
        return 0, "Unknown parser type"
    end
    
    -- Step 3: Process the content in batches with accurate progress
    Tasks.message = "Processing " .. sourceName .. "..."
    
    -- First count how many entries we'll be processing
    local totalEntries = 0
    local processedEntries = 0
    
    if source.parser == "raw" then
        -- Count lines for raw data
        for _ in sourceRawData:gmatch("[^\r\n]+") do
            totalEntries = totalEntries + 1
        end
    elseif source.parser == "tf2db" then
        -- Try to parse JSON to get count
        local jsonSuccess, jsonData = pcall(Json.decode, sourceRawData)
        if jsonSuccess and jsonData and jsonData.players then
            totalEntries = #jsonData.players
        else
            -- Estimate based on content length
            totalEntries = math.floor(#sourceRawData / 100) -- Rough estimate
        end
    end
    
    -- Process with the selected parser
    local batchSize = 500
    local result = 0
    
    if parser == Parsers.ProcessRawList then
        -- Process raw list manually in batches
        local lines = {}
        for line in sourceRawData:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
        
        local batches = math.ceil(#lines / batchSize)
        
        for i = 1, batches do
            local startIdx = (i-1) * batchSize + 1
            local endIdx = math.min(i * batchSize, #lines)
            local batchLines = {}
            
            -- Extract this batch of lines
            for j = startIdx, endIdx do
                table.insert(batchLines, lines[j])
            end
            
            -- Process this batch
            local batchContent = table.concat(batchLines, "\n")
            local batchResult = parser(batchContent, database, sourceName, source.cause) 
            result = result + batchResult
            
            -- Update progress
            processedEntries = endIdx
            local progressPct = math.floor((processedEntries / totalEntries) * 100)
            Tasks.message = string.format("Processing %s: %d%% (%d entries added)",
                sourceName, progressPct, result)
                
            -- Let UI update
            coroutine.yield()
        end
    else
        -- Use the parser directly
        result = parser(sourceRawData, database, source)
    end
    
    -- Clear data to save memory
    sourceRawData = nil
    collectgarbage("collect")
    
    return result
end

-- Main fetch function with improved anti-ban protection and progress tracking
function Fetcher.FetchAll(database, callback, silent)
    -- If already running, don't start again
    if Tasks.isRunning then
        if not silent then
            print("[Database Fetcher] A fetch operation is already in progress")
        end
        return false
    end
    
    -- Initialize UI tracking with batch precision
    Fetcher.UI.totalSources = #Fetcher.Sources
    Fetcher.UI.completedSources = 0
    Fetcher.UI.currentProgress = 0
    Fetcher.UI.targetProgress = 0
    
    -- Initialize the task system
    Tasks.Reset()
    Tasks.Init(Fetcher.UI.totalSources)
    Tasks.callback = callback
    Tasks.silent = silent or false
    
    -- Create a main task that processes all sources with proper delays
    local mainTask = coroutine.create(function()
        local totalAdded = 0
        
        -- Process each source with delays between them
        for i, source in ipairs(Fetcher.Sources) do
            -- Start source with progress tracking
            Tasks.StartSource(source.name)
            Tasks.message = "Processing: " .. source.name
            
            -- Update UI tracking
            Fetcher.UI.targetProgress = (i - 1) / Fetcher.UI.totalSources * 100
            
            -- Yield to update UI
            coroutine.yield()
            
            -- Apply anti-ban delay if not the first source
            if i > 1 then
                local delay = Fetcher.GetSourceDelay()
                Tasks.message = string.format("Waiting %.1fs before next request...", delay)
                
                -- Wait with countdown
                local startTime = globals.RealTime()
                while globals.RealTime() < startTime + delay do
                    -- Update remaining time
                    local remaining = math.ceil(startTime + delay - globals.RealTime())
                    Tasks.message = string.format("Rate limit: %ds before next request...", remaining)
                    coroutine.yield()
                end
            end
            
            -- Now fetch the actual source with proper batch processing
            Tasks.message = "Fetching from " .. source.name
            local count = 0
            
            -- Use the batch processor for better progress tracking
            local success, result = pcall(function()
                return Fetcher.ProcessSourceInBatches(source, database)
            end)
            
            if success and type(result) == "number" then
                count = result
                totalAdded = totalAdded + count
                Tasks.message = string.format("Added %d entries from %s", count, source.name)
            else
                local errorMsg = type(result) == "string" and result or "unknown error"
                print("[Database Fetcher] Error processing " .. source.name .. ": " .. errorMsg)
                Tasks.message = "Error processing " .. source.name
            end
            
            -- Mark source as done and update progress
            Tasks.SourceDone()
            Fetcher.UI.completedSources = i
            Fetcher.UI.targetProgress = i / Fetcher.UI.totalSources * 100
            
            -- Yield to update UI
            coroutine.yield()
            
            -- Apply a shorter delay after processing to let UI update
            Tasks.Sleep(0.5)
        end
        
        -- Finalize
        Fetcher.UI.targetProgress = 100
        Tasks.progress = 100
        Tasks.message = "All sources processed! Added " .. totalAdded .. " entries total."
        
        -- Update last fetch time
        Fetcher.Config.LastAutoFetch = os.time()
        
        return totalAdded
    end)
    
    -- Register the main task processor
    callbacks.Register("Draw", "FetcherMainTask", function()
        -- Process the main task if it's not finished
        if coroutine.status(mainTask) ~= "dead" then
            -- Resume the main task
            local success, result = pcall(coroutine.resume, mainTask)
            
            if not success then
                -- Handle error in main task
                print("[Database Fetcher] Error: " .. tostring(result))
                Tasks.Reset()
                callbacks.Unregister("Draw", "FetcherMainTask")
            end
            
            -- Perform smooth progress interpolation
            if Fetcher.UI.currentProgress ~= Fetcher.UI.targetProgress then
                Fetcher.UI.currentProgress = Fetcher.UI.currentProgress + 
                    (Fetcher.UI.targetProgress - Fetcher.UI.currentProgress) * 
                    Fetcher.Config.SmoothingFactor
                
                -- Update the task progress
                Tasks.progress = math.floor(Fetcher.UI.currentProgress)
            end
        else
            -- Task is complete, clean up
            callbacks.Unregister("Draw", "FetcherMainTask")
            
            -- Run completion callback
            local _, result = coroutine.resume(mainTask)
            local totalAdded = tonumber(result) or 0
            
            if type(callback) == "function" then
                pcall(callback, totalAdded)
            end
            
            -- Show notification if enabled
            if Fetcher.Config.NotifyOnFetchComplete and not silent then
                printc(0, 255, 0, 255, string.format(
                    "[Database Fetcher] Update complete: Added %d entries", totalAdded))
            end
            
            -- Keep the progress bar visible for a moment
            local startTime = globals.RealTime()
            callbacks.Register("Draw", "FetcherCleanup", function()
                if globals.RealTime() > startTime + 2 then
                    Tasks.Reset()
                    callbacks.Unregister("Draw", "FetcherCleanup")
                end
            end)
        end
    end)
    
    return true
end

-- Auto fetch handler
function Fetcher.AutoFetch(database)
    -- Get database if not provided
    if not database then
        local success, db = pcall(function()
            return require("Cheater_Detection.Database.Database")
        end)
        
        if not success or not db then return false end
        database = db
    end
    
    -- Start fetch with silent mode
    return Fetcher.FetchAll(database, function(totalAdded)
        if totalAdded > 0 and Fetcher.Config.AutoSaveAfterFetch then
            database.SaveDatabase()
            
            if Fetcher.Config.NotifyOnFetchComplete then
                printc(80, 200, 120, 255, "[Database] Auto-updated with " .. totalAdded .. " new entries")
            end
        end
    end, not Fetcher.Config.ShowProgressBar)
end

-- Draw callback to show progress UI
callbacks.Register("Draw", "FetcherUI", function()
    if Tasks.isRunning and Fetcher.Config.ShowProgressBar and not Tasks.silent then
        -- Update source progress information
        if Tasks.currentSource then
            local sourcePct = Fetcher.UI.completedSources / Fetcher.UI.totalSources * 100
            Tasks.message = string.format("%s [Source %d/%d - %.0f%%]", 
                Tasks.message:gsub("%s*%[Source.*%]%s*$", ""),
                Fetcher.UI.completedSources, 
                Fetcher.UI.totalSources,
                sourcePct)
        end
        
        -- Draw the UI
        pcall(Tasks.DrawProgressUI)
    end
end)

-- Register improved commands
local function RegisterCommands()
    local function getDatabase()
        return require("Cheater_Detection.Database.Database")
    end
    
    -- Fetch all command
    Commands.Register("cd_fetch_all", function()
        if not Tasks.isRunning then
            local Database = getDatabase()
            Fetcher.FetchAll(Database, function(totalAdded)
                if totalAdded > 0 then
                    Database.SaveDatabase()
                end
            end)
        else
            print("[Database Fetcher] A fetch operation is already in progress")
        end
    end, "Fetch all cheater lists and update the database")
    
    -- Fetch specific source command
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
            
            -- Initialize for a single source
            Tasks.Reset()
            Tasks.Init(1)
            
            -- Setup UI tracking
            Fetcher.UI.totalSources = 1
            Fetcher.UI.completedSources = 0
            Fetcher.UI.currentProgress = 0
            Fetcher.UI.targetProgress = 0
            
            -- Create task coroutine
            local task = coroutine.create(function()
                Tasks.StartSource(source.name)
                local count = Parsers.ProcessSource(source, Database)
                Tasks.SourceDone()
                
                -- Update progress tracking
                Fetcher.UI.completedSources = 1
                Fetcher.UI.targetProgress = 100
                
                if count > 0 then
                    Database.SaveDatabase()
                end
                
                return count
            end)
            
            -- Process the task
            callbacks.Register("Draw", "FetcherSingleSource", function()
                if coroutine.status(task) ~= "dead" then
                    -- Resume the task
                    local success, result = pcall(coroutine.resume, task)
                    
                    -- Update smooth progress
                    Fetcher.UI.currentProgress = Fetcher.UI.currentProgress + 
                        (Fetcher.UI.targetProgress - Fetcher.UI.currentProgress) * 
                        Fetcher.Config.SmoothingFactor
                    
                    -- Update the task progress
                    Tasks.progress = math.floor(Fetcher.UI.currentProgress)
                    
                    if not success then
                        print("[Database Fetcher] Error: " .. tostring(result))
                        Tasks.Reset()
                        callbacks.Unregister("Draw", "FetcherSingleSource")
                    end
                else
                    -- Get result and clean up
                    local _, count = coroutine.resume(task)
                    count = tonumber(count) or 0
                    
                    print(string.format("[Database Fetcher] Added %d entries from %s", count, source.name))
                    callbacks.Unregister("Draw", "FetcherSingleSource")
                    
                    -- Show completion
                    Tasks.status = "complete"
                    Tasks.progress = 100
                    Tasks.message = "Added " .. count .. " entries from " .. source.name
                    
                    -- Clean up after showing completion
                    local startTime = globals.RealTime()
                    local function cleanup()
                        if globals.RealTime() >= startTime + 2 then
                            Tasks.Reset()
                            callbacks.Unregister("Draw", "FetcherSingleSourceCleanup")
                        end
                    end
                    callbacks.Register("Draw", "FetcherSingleSourceCleanup", cleanup)
                end
            end)
        else
            print("[Database Fetcher] A task is already in progress")
        end
    end, "Fetch from a specific source")
    
    -- List sources command
    Commands.Register("cd_list_sources", function()
        print("[Database Fetcher] Available sources:")
        for i, source in ipairs(Fetcher.Sources) do
            print(string.format("%d. %s (%s)", i, source.name, source.cause))
        end
    end, "List all available sources")
    
    -- Configure delay command
    Commands.Register("cd_fetch_delay", function(args)
        if #args < 2 then
            print("Usage: cd_fetch_delay <min_seconds> <max_seconds>")
            print(string.format("Current delay: %.1f-%.1f seconds", 
                Fetcher.Config.MinSourceDelay, Fetcher.Config.MaxSourceDelay))
            return
        end
        
        local minDelay = tonumber(args[1])
        local maxDelay = tonumber(args[2])
        
        if not minDelay or not maxDelay then
            print("Invalid delay values")
            return
        end
        
        Fetcher.Config.MinSourceDelay = math.max(1, minDelay)
        Fetcher.Config.MaxSourceDelay = math.max(Fetcher.Config.MinSourceDelay, maxDelay)
        
        print(string.format("[Database Fetcher] Set source delay to %.1f-%.1f seconds", 
            Fetcher.Config.MinSourceDelay, Fetcher.Config.MaxSourceDelay))
    end, "Set delay between source fetches (anti-ban protection)")
    
    -- Cancel command
    Commands.Register("cd_cancel", function()
        if Tasks.isRunning then
            Tasks.Reset()
            print("[Database Fetcher] Cancelled all tasks")
        else
            print("[Database Fetcher] No tasks running")
        end
    end, "Cancel any running fetch operations")
end

-- Register commands
RegisterCommands()

-- Auto-fetch on load if enabled
if Fetcher.Config.AutoFetchOnLoad then
    callbacks.Register("Draw", "FetcherAutoLoad", function()
        callbacks.Unregister("Draw", "FetcherAutoLoad")
        Fetcher.AutoFetch()
    end)
end

return Fetcher

end)
__bundle_register("Cheater_Detection.Database.Database", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Simplified Database.lua
    Direct implementation of database functionality using native Lua tables
    Stores only essential data: name and proof for each SteamID64
]]

local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Json = Common.Json
local Database_import = require("Cheater_Detection.Database.Database_Import")
local Database_Fetcher = require("Cheater_Detection.Database.Database_Fetcher")

local Database = {
    -- Internal data storage (direct table)
    data = {},

    -- Configuration
    Config = {
        AutoSave = true,
        SaveInterval = 300, -- 5 minutes
        DebugMode = false,
        MaxEntries = 15000  -- Maximum entries to prevent memory issues
    },

    -- State tracking
    State = {
        entriesCount = 0,
        isDirty = false,
        lastSave = 0
    }
}

-- Create the content accessor with metatable for cleaner API
Database.content = setmetatable({}, {
    __index = function(_, key)
        return Database.data[key]
    end,

    __newindex = function(_, key, value)
        Database.HandleSetEntry(key, value)
    end,

    __pairs = function()
        return pairs(Database.data)
    end
})

-- Handle setting an entry with proper counting
function Database.HandleSetEntry(key, value)
    -- Count entries if adding/removing
    if (Database.data[key] == nil) and value ~= nil then
        Database.State.entriesCount = Database.State.entriesCount + 1
    elseif (Database.data[key] ~= nil) and value == nil then
        Database.State.entriesCount = Database.State.entriesCount - 1
    end

    -- Simplified data structure - keep only what's needed
    if value ~= nil then
        -- Ensure we only store essential data
        local minimalValue = {
            Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
            proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown"
        }
        Database.data[key] = minimalValue
    else
        Database.data[key] = nil
    end

    Database.State.isDirty = true

    -- Auto-save if enabled and enough time has passed
    if Database.Config.AutoSave then
        local currentTime = os.time()
        if currentTime - Database.State.lastSave >= Database.Config.SaveInterval then
            Database.SaveDatabase()
        end
    end
end

-- Find best path for database storage
function Database.GetFilePath()
    local possibleFolders = {
        "Lua Cheater_Detection",
        "Lua Scripts/Cheater_Detection",
        "lbox/Cheater_Detection",
        "lmaobox/Cheater_Detection",
        "."
    }

    -- Try to find existing folder first
    for _, folder in ipairs(possibleFolders) do
        if pcall(function() return filesystem.GetFileSize(folder) end) then
            return folder .. "/database.json"
        end
    end

    -- Try to create folders
    for _, folder in ipairs(possibleFolders) do
        if pcall(filesystem.CreateDirectory, folder) then
            return folder .. "/database.json"
        end
    end

    -- Last resort
    return "./database.json"
end

-- Save database to disk with batch writing and progress tracking
function Database.SaveDatabase()
    -- Create a save task to run in coroutine
    local saveTask = coroutine.create(function()
        local filePath = Database.GetFilePath()
        local tempPath = filePath .. ".tmp"
        local backupPath = filePath .. ".bak"
        
        -- Let UI know we're starting
        if G and G.UI and G.UI.ShowMessage then
            G.UI.ShowMessage("Saving database...")
        end
        
        -- Stage 1: Create a temporary file
        local tempFile = io.open(tempPath, "w")
        if not tempFile then
            print("[Database] Failed to create temporary file: " .. tempPath)
            return false
        end
        
        -- Write opening JSON bracket
        tempFile:write("{\n")
        
        -- Stage 2: Process entries in batches
        local entries = {}
        for steamID, entry in pairs(Database.data) do
            table.insert(entries, {id = steamID, data = entry})
        end
        
        local totalEntries = #entries
        local batchSize = 500 -- Process 500 entries at a time
        local batches = math.ceil(totalEntries / batchSize)
        
        for batchIndex = 1, batches do
            local startIdx = (batchIndex - 1) * batchSize + 1
            local endIdx = math.min(batchIndex * batchSize, totalEntries)
            
            -- Update progress
            local progress = math.floor((batchIndex - 1) / batches * 100)
            if G and G.UI and G.UI.UpdateProgress then
                G.UI.UpdateProgress(progress, "Saving database... " .. progress .. "%")
            end
            
            -- Allow UI to update
            coroutine.yield()
            
            -- Process this batch
            for i = startIdx, endIdx do
                local entry = entries[i]
                if entry and entry.id then
                    local steamID = entry.id
                    local data = entry.data
                    
                    -- Serialize this entry
                    local jsonEntry = string.format('"%s":{"Name":"%s","proof":"%s"}', 
                        steamID,
                        (data.Name or "Unknown"):gsub('"', '\\"'),
                        (data.proof or "Unknown"):gsub('"', '\\"')
                    )
                    
                    -- Add comma for all except the last entry
                    if i < totalEntries then
                        jsonEntry = jsonEntry .. ",\n"
                    else
                        jsonEntry = jsonEntry .. "\n"
                    end
                    
                    -- Write to file
                    tempFile:write(jsonEntry)
                end
            end
            
            -- Force flush the batch
            tempFile:flush()
            
            -- Clean up memory after each batch
            collectgarbage("step", 100)
        end
        
        -- Write closing JSON bracket
        tempFile:write("}")
        tempFile:close()
        
        -- Stage 3: Backup current file if it exists
        local currentFile = io.open(filePath, "r")
        if currentFile then
            local content = currentFile:read("*a")
            currentFile:close()
            
            local backupFile = io.open(backupPath, "w")
            if backupFile then
                backupFile:write(content)
                backupFile:close()
            end
        end
        
        -- Stage 4: Rename temporary file to actual file
        local success = os.rename(tempPath, filePath)
        
        -- Update state
        Database.State.isDirty = false
        Database.State.lastSave = os.time()
        
        if G and G.UI and G.UI.ShowMessage then
            G.UI.ShowMessage("Database saved with " .. Database.State.entriesCount .. " entries!")
        end
        
        if Database.Config.DebugMode then
            print(string.format("[Database] Saved %d entries to %s", 
                Database.State.entriesCount, filePath))
        end
        
        return success
    end)
    
    -- Run the save coroutine
    local saveCallback = function()
        -- Only proceed if the coroutine is alive
        if coroutine.status(saveTask) ~= "dead" then
            local success, result = pcall(coroutine.resume, saveTask)
            
            if not success then
                -- Error occurred
                print("[Database] Save error: " .. tostring(result))
                callbacks.Unregister("Draw", "DatabaseSave")
                
                -- Try fallback save method
                Database.FallbackSave()
            end
        else
            -- Save completed
            callbacks.Unregister("Draw", "DatabaseSave")
        end
    end
    
    -- Register the callback to run on Draw
    callbacks.Register("Draw", "DatabaseSave", saveCallback)
    return true
end

-- Fallback save method that uses simpler approach for reliability
function Database.FallbackSave()
    print("[Database] Using fallback save method")
    
    local filePath = Database.GetFilePath()
    local success = pcall(function()
        -- Open file
        local file = io.open(filePath, "w")
        if not file then
            error("Failed to open file for writing")
        end
        
        -- Build a simpler JSON structure
        file:write("{\n")
        
        local count = 0
        local total = 0
        for steamID in pairs(Database.data) do total = total + 1 end
        
        for steamID, entry in pairs(Database.data) do
            count = count + 1
            local data = string.format('"%s":{"Name":"%s","proof":"%s"}%s\n',
                steamID,
                (entry.Name or "Unknown"):gsub('"', '\\"'),
                (entry.proof or "Unknown"):gsub('"', '\\"'),
                count < total and "," or ""
            )
            file:write(data)
        end
        
        file:write("}")
        file:close()
    end)
    
    if success then
        print("[Database] Fallback save successful")
        Database.State.isDirty = false
        Database.State.lastSave = os.time()
        return true
    else
        print("[Database] Fallback save failed")
        return false
    end
end

-- Load database from disk
function Database.LoadDatabase(silent)
    local filePath = Database.GetFilePath()

    -- Try to open file
    local file = io.open(filePath, "r")
    if not file then
        if not silent then
            print("[Database] Database file not found: " .. filePath)
        end
        return false
    end

    -- Read and parse content
    local content = file:read("*a")
    file:close()

    local success, data = pcall(Json.decode, content)
    if not success or type(data) ~= "table" then
        if not silent then
            print("[Database] Failed to decode database file")
        end
        return false
    end

    -- Reset and load data
    Database.data = {}
    Database.State.entriesCount = 0

    -- Copy data with minimal structure - enforce entry limit
    local entriesAdded = 0
    for steamID, value in pairs(data) do
        if entriesAdded < Database.Config.MaxEntries then
            Database.data[steamID] = {
                Name = type(value) == "table" and (value.Name or "Unknown") or "Unknown",
                proof = type(value) == "table" and (value.proof or value.cause or "Unknown") or "Unknown"
            }
            Database.State.entriesCount = Database.State.entriesCount + 1
            entriesAdded = entriesAdded + 1
        else
            break
        end
    end

    -- Clean up memory
    collectgarbage("collect")

    -- Update state
    Database.State.isDirty = false
    Database.State.lastSave = os.time()

    if not silent then
        printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Database with " ..
            Database.State.entriesCount .. " entries")
    end

    return true
end

-- Get a player record
function Database.GetRecord(steamId)
    return Database.content[steamId]
end

-- Get proof for a player
function Database.GetProof(steamId)
    local record = Database.content[steamId]
    return record and record.proof or "Unknown"
end

-- Get name for a player
function Database.GetName(steamId)
    local record = Database.content[steamId]
    return record and record.Name or "Unknown"
end

-- Check if player is in database
function Database.Contains(steamId)
    return Database.data[steamId] ~= nil
end

-- Set a player as suspect
function Database.SetSuspect(steamId, data)
    if not steamId then return end

    -- Create minimal data structure
    local minimalData = {
        Name = (data and data.Name) or "Unknown",
        proof = (data and (data.proof or data.cause)) or "Unknown"
    }

    -- Store data
    Database.content[steamId] = minimalData

    -- Also set priority in playerlist
    playerlist.SetPriority(steamId, 10)
end

-- Clear a player from suspect list
function Database.ClearSuspect(steamId)
    if Database.content[steamId] then
        Database.content[steamId] = nil
        playerlist.SetPriority(steamId, 0)
    end
end

-- Get database stats
function Database.GetStats()
    -- Count entries by proof type
    local proofStats = {}
    for steamID, entry in pairs(Database.data) do
        local proof = entry.proof or "Unknown"
        proofStats[proof] = (proofStats[proof] or 0) + 1
    end

    return {
        entryCount = Database.State.entriesCount,
        isDirty = Database.State.isDirty,
        lastSave = Database.State.lastSave,
        memoryMB = collectgarbage("count") / 1024,
        proofTypes = proofStats
    }
end

-- Import function for database updating
function Database.ImportDatabase()
    -- Simple import from Database_import module
    local beforeCount = Database.State.entriesCount

    -- Import additional data
    Database_import.importDatabase(Database)

    -- Count entries after import
    local afterCount = Database.State.entriesCount

    -- Show a summary of the import
    local newEntries = afterCount - beforeCount
    if newEntries > 0 then
        printc(255, 255, 0, 255, string.format("[Database] Imported %d new entries from external sources", newEntries))

        -- Save the updated database
        if Database.SaveDatabase() then
            printc(100, 255, 100, 255, string.format("[Database] Saved database with %d total entries", afterCount))
        end
    end

    return newEntries
end

-- Add utility functions to trigger fetching
function Database.FetchUpdates(silent)
    if Database_Fetcher then
        return Database_Fetcher.FetchAll(Database, function(totalAdded)
            if totalAdded and totalAdded > 0 then
                Database.SaveDatabase()
                if not silent then
                    printc(0, 255, 0, 255, "[Database] Updated with " .. totalAdded .. " new entries")
                end
            elseif not silent then
                print("[Database] No new entries were added")
            end
        end, silent)
    else
        if not silent then
            print("[Database] Error: Database_Fetcher module not found")
        end
        return false
    end
end

-- Auto update function that can be called from anywhere
function Database.AutoUpdate()
    return Database.FetchUpdates(true)
end

-- Clean database by removing least important entries
function Database.Cleanup(maxEntries)
    maxEntries = maxEntries or Database.Config.MaxEntries
    
    -- If we're under the limit, no need to clean
    if Database.State.entriesCount <= maxEntries then
        return 0
    end
    
    -- Create a priority list for entries to keep
    local priorities = {
        -- Highest priority to keep (exact string matching)
        "RGL", "Bot", "Pazer List", "Community",
        -- Lower priority categories
        "Cheater", "Tacobot", "MCDB", "Suspicious", "Watched"
    }
    
    -- Count entries to remove
    local toRemove = Database.State.entriesCount - maxEntries
    local removed = 0
    
    -- Remove entries not in priority list first
    if toRemove > 0 then
        local nonPriorityEntries = {}
        
        for steamId, data in pairs(Database.data) do
            -- Check if this entry is a priority
            local isPriority = false
            local proof = (data.proof or ""):lower()
            
            for _, priority in ipairs(priorities) do
                if proof:find(priority:lower()) then
                    isPriority = true
                    break
                end
            end
            
            if not isPriority then
                table.insert(nonPriorityEntries, steamId)
                if #nonPriorityEntries >= toRemove then
                    break
                end
            end
        end
        
        -- Remove the non-priority entries
        for _, steamId in ipairs(nonPriorityEntries) do
            Database.content[steamId] = nil
            removed = removed + 1
        end
    end
    
    -- If we still need to remove more, start removing lowest priority entries
    if removed < toRemove then
        -- Process in reverse priority order
        for i = #priorities, 1, -1 do
            local priority = priorities[i]:lower()
            
            for steamId, data in pairs(Database.data) do
                local proof = (data.proof or ""):lower()
                
                if proof:find(priority) then
                    Database.content[steamId] = nil
                    removed = removed + 1
                    
                    if removed >= toRemove then
                        break
                    end
                end
            end
            
            if removed >= toRemove then
                break
            end
        end
    end
    
    -- Save the cleaned database
    if removed > 0 and Database.State.isDirty then
        Database.SaveDatabase()
    end
    
    return removed
end

-- Register database commands
local function RegisterCommands()
    local Commands = Common.Lib.Utils.Commands
    
    -- Database stats command
    Commands.Register("cd_db_stats", function()
        local stats = Database.GetStats()
        print(string.format("[Database] Total entries: %d", stats.entryCount))
        print(string.format("[Database] Memory usage: %.2f MB", stats.memoryMB))
        
        -- Show proof type breakdown
        print("[Database] Proof type breakdown:")
        for proofType, count in pairs(stats.proofTypes) do
            if count > 10 then -- Only show categories with more than 10 entries
                print(string.format("  - %s: %d", proofType, count))
            end
        end
    end, "Show database statistics")
    
    -- Database cleanup command
    Commands.Register("cd_db_cleanup", function(args)
        local limit = tonumber(args[1]) or Database.Config.MaxEntries
        local beforeCount = Database.State.entriesCount
        local removed = Database.Cleanup(limit)
        
        print(string.format("[Database] Cleaned %d entries (from %d to %d)", 
            removed, beforeCount, Database.State.entriesCount))
    end, "Clean the database to stay under entry limit")
end

-- Auto-save on unload
local function OnUnload()
    if Database.State.isDirty then
        Database.SaveDatabase()
    end
end

-- Initialize the database
local function InitializeDatabase()
    -- Load existing database first
    Database.LoadDatabase()
    
    -- Import additional data
    Database.ImportDatabase()
    
    -- Clean up if over limit
    if Database.State.entriesCount > Database.Config.MaxEntries then
        local removed = Database.Cleanup()
        if removed > 0 and Database.Config.DebugMode then
            print(string.format("[Database] Cleaned %d entries to stay under limit", removed))
        end
    end

    -- Check if Database_Fetcher is available and has auto-fetch enabled
    pcall(function()
        if Database_Fetcher and Database_Fetcher.Config and Database_Fetcher.Config.AutoFetchOnLoad then
            Database_Fetcher.AutoFetch(Database)
        end
    end)
end

-- Register unload callback
callbacks.Unregister("Unload", "CDDatabase_Unload")
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)

-- Register commands
RegisterCommands()

-- Initialize the database when this module is loaded
InitializeDatabase()

return Database

end)
__bundle_register("Cheater_Detection.Database.Database_Import", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")

local Database_Import = {}

local Json = Common.Json

-- Utility function to trim whitespace
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
local folder_name = string.format([[Lua %s]], Lua__fileName)

local function GetFilePath()
    local _, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

-- Update database with player data
function Database_Import.updateDatabase(steamID64, playerData, Database)
    -- Basic validation
    if not steamID64 or not playerData or not Database then return end

    Database.content = Database.content or {}

    local existingData = Database.content[steamID64]
    if existingData then
        -- Only update fields if they are not nil
        if playerData.Name and playerData.Name ~= "Unknown" then
            existingData.Name = playerData.Name
        end
        if playerData.cause then
            existingData.cause = playerData.cause
        end
        if playerData.date then
            existingData.date = playerData.date
        end
    else
        -- Mark as cheater in playerlist
        playerlist.SetPriority(steamID64, 10)

        -- Add new entry
        Database.content[steamID64] = {
            Name = playerData.Name or "Unknown",
            cause = playerData.cause or "Known Cheater",
            date = playerData.date or os.date("%Y-%m-%d %H:%M:%S")
        }
    end
end

-- Process raw ID data
function Database_Import.processRawIDs(content, Database)
    if not content or not Database then return end

    local date = os.date("%Y-%m-%d %H:%M:%S")
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if not line:match("^%-%-") then -- Skip comment lines
            local steamID64
            local success, result = pcall(function()
                if line:match("^%d+$") then
                    return line
                elseif line:match("STEAM_0:%d:%d+") then
                    return steam.ToSteamID64(line)
                elseif line:match("^%[U:1:%d+%]$") then
                    return steam.ToSteamID64(line)
                end
                return nil
            end)

            steamID64 = success and result or nil

            if steamID64 then
                Database_Import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    cause = "Known Cheater",
                    date = date,
                }, Database)
            end
        end
    end
end

-- Process imported data
function Database_Import.processImportedData(data, Database)
    if not data or not data.players or not Database then return end

    for _, player in ipairs(data.players) do
        if not player or not player.steamid then goto continue end

        local steamID64
        local playerName = player.last_seen and player.last_seen.player_name or "Unknown"

        -- Validate name
        if not playerName or playerName == "" or #playerName < 3 then
            playerName = "Unknown"
        end

        -- Create player details
        local playerDetails = {
            Name = playerName,
            cause = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
            date = player.last_seen and os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time) or
                os.date("%Y-%m-%d %H:%M:%S")
        }

        -- Convert steamID to steamID64
        local success, id = pcall(function()
            if player.steamid:match("^%[U:1:%d+%]$") then
                return steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                return steam.ToSteamID64(steam3)
            else
                return player.steamid -- Already SteamID64
            end
        end)

        steamID64 = success and id or nil

        if steamID64 then
            Database_Import.updateDatabase(steamID64, playerDetails, Database)
        end

        ::continue::
    end
end

-- Safe file reading
function Database_Import.readFromFile(filePath)
    local file = io.open(filePath, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()
    return content
end

-- Add this new function to process playerlist priority files
function Database_Import.processPriorityList(content, Database)
    if not content or not Database then return end

    local priorityMap = {
        [4] = "Bot",
        [5] = "Suspicious",
        [6] = "Watched",
        [7] = "Pazer List",
        [8] = "Tacobot",
        [9] = "MCDB",
        [10] = "Cheater"
    }

    -- Match both formats: playerlist.SetPriority("STEAMID", priority) and playerlist.SetPriority(steamid, priority)
    local pattern = 'playerlist%.SetPriority%(["\']?([^"\',)]+)["\']?%s*,%s*(%d+)%)'
    local date = os.date("%Y-%m-%d %H:%M:%S")
    local count = 0

    for steamid, priority in content:gmatch(pattern) do
        local priority = tonumber(priority)
        if steamid and priority then
            -- Convert steamid to steamid64 if needed
            local steamID64
            local success, result = pcall(function()
                if steamid:match("^%d+$") and #steamid >= 15 then
                    return steamid -- Already SteamID64
                elseif steamid:match("^STEAM_0:%d:%d+$") then
                    return steam.ToSteamID64(steamid)
                elseif steamid:match("^%[U:1:%d+%]$") then
                    return steam.ToSteamID64(steamid)
                end
                return nil
            end)

            steamID64 = success and result or nil

            if steamID64 then
                local cause = priorityMap[priority] or ("Priority " .. priority)

                Database_Import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    cause = cause,
                    date = date,
                    priority = priority
                }, Database)

                count = count + 1
            end
        end
    end

    return count
end

-- Import database function
function Database_Import.importDatabase(Database)
    if not Database then return end

    Database.content = Database.content or {}

    local baseFilePath = GetFilePath():gsub("database.json", "")
    local importPath = baseFilePath .. "/import/"

    -- Create import directory if it doesn't exist
    filesystem.CreateDirectory(importPath)

    -- Track import statistics
    local processedFiles = 0
    local importedEntries = 0

    -- Process all files
    filesystem.EnumerateDirectory(importPath .. "*", function(filename, attributes)
        if filename == "." or filename == ".." then return end

        local fullPath = importPath .. filename
        local content = Database_Import.readFromFile(fullPath)

        if content then
            -- Count entries before import
            local beforeCount = 0
            for _ in pairs(Database.content) do
                beforeCount = beforeCount + 1
            end

            -- Process the file
            local success = pcall(function()
                if content:match("playerlist%.SetPriority") then
                    -- Process as a priority list file
                    Database_Import.processPriorityList(content, Database)
                elseif Common.isJson(content) then
                    local data = Json.decode(content)
                    if data then
                        Database_Import.processImportedData(data, Database)
                    end
                else
                    Database_Import.processRawIDs(content, Database)
                end
            end)

            if success then
                processedFiles = processedFiles + 1

                -- Count entries after import
                local afterCount = 0
                for _ in pairs(Database.content) do
                    afterCount = afterCount + 1
                end

                importedEntries = importedEntries + (afterCount - beforeCount)
            end
        end
    end)

    if processedFiles > 0 then
        -- Only print a message if we actually processed files - the main Database.lua will print a summary
        -- print(string.format("Processed %d import files with %d total entries", processedFiles, importedEntries))
    end

    return Database
end

return Database_Import

end)
__bundle_register("Cheater_Detection.Database.Database_Fetcher.Parsers", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Enhanced parsers with improved HTML detection and better error handling

local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json
local Tasks = require("Cheater_Detection.Database.Database_Fetcher.Tasks")

local Parsers = {}

-- Configuration (enhanced)
Parsers.Config = {
    RetryDelay = 4,      -- Initial delay between retries (seconds)
    RetryBackoff = 2,    -- Multiply delay by this factor on each retry
    RequestTimeout = 10, -- Maximum time to wait for a response (seconds)
    YieldInterval = 500, -- Yield after processing this many items
    MaxRetries = 3,      -- Maximum number of retry attempts
    RetryOnEmpty = true, -- Retry if response is empty
    DebugMode = true,    -- Enable detailed error logging
    UserAgents = {  -- Add different user agents to rotate through
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15"
    },
    CurrentUserAgent = 1,  -- Index of current user agent to use
    AllowHtml = false,     -- Whether to allow HTML responses (usually indicates an error)
    MaxErrorDisplayLength = 80  -- Maximum length of error messages to display
}

-- Error logging function with debug mode control
function Parsers.LogError(message, details)
    -- Always log critical errors
    print("[Database Fetcher] Error: " .. message)

    -- Log additional details only in debug mode
    if Parsers.Config.DebugMode and details then
        if type(details) == "string" and #details > 100 then
            -- Truncate very long details to prevent console overflow
            print("[Database Fetcher] Details: " .. details:sub(1, 100) .. "... (truncated)")
        else
            print("[Database Fetcher] Details: " .. tostring(details))
        end
    end

    -- Set the task message with a safe truncated version
    local displayMessage = message
    if #displayMessage > Parsers.Config.MaxErrorDisplayLength then
        displayMessage = displayMessage:sub(1, Parsers.Config.MaxErrorDisplayLength) .. "..."
    end
    
    if Tasks and Tasks.message then
        Tasks.message = "Error: " .. displayMessage
    end
end

-- Safe download with better error handling and user agent rotation
function Parsers.Download(url, retryCount)
    retryCount = retryCount or Parsers.Config.MaxRetries
    
    -- Use different user agents for GitHub to avoid rate limiting
    if url:find("github") or url:find("githubusercontent") then
        table.insert(Parsers.Config.UserAgents, 1, "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")
    end
    
    local retry = 0
    local lastError = nil

    while retry < retryCount do
        -- Rotate user agents on retries
        Parsers.Config.CurrentUserAgent = 1 + (retry % #Parsers.Config.UserAgents)
        local userAgent = Parsers.Config.UserAgents[Parsers.Config.CurrentUserAgent]

        Tasks.message = "Downloading from " .. url:sub(1, 40) .. "... (try " .. (retry + 1) .. "/" .. retryCount .. ")"
        coroutine.yield()

        local requestTimedOut = false
        local startTime = globals.RealTime()
        local response = nil

        -- Create a timeout checker
        local timeoutCheckerId = "request_timeout_" .. tostring(math.random(1000000))
        callbacks.Register("Draw", timeoutCheckerId, function()
            if globals.RealTime() - startTime > Parsers.Config.RequestTimeout then
                requestTimedOut = true
                callbacks.Unregister("Draw", timeoutCheckerId)
            end
        end)

        -- Attempt the HTTP request with custom headers
        local success, result = pcall(function()
            local headers = {
                ["User-Agent"] = userAgent,
                ["Accept"] = "text/plain, application/json",
                ["Cache-Control"] = "no-cache"
            }
            
            -- Use http.Get with headers
            return http.Get(url, headers)
        end)

        -- Unregister the timeout checker
        callbacks.Unregister("Draw", timeoutCheckerId)

        -- Process the result with more robust error handling
        if requestTimedOut then
            lastError = "Request timed out"
        elseif not success then
            lastError = "HTTP error: " .. tostring(result)
        elseif not result then
            lastError = "Empty response"
        elseif type(result) ~= "string" then
            lastError = "Invalid response type: " .. type(result)
        elseif #result == 0 then
            if Parsers.Config.RetryOnEmpty then
                lastError = "Empty response"
            else
                return "" -- Return empty string if empty responses are acceptable
            end
        else
            -- Check for HTML response (likely an error page)
            if result:match("<!DOCTYPE html>") or result:match("<html") then
                -- Check if it's GitHub returning HTML
                if url:find("github") or url:find("githubusercontent") and result:find("rate limit") then
                    lastError = "GitHub rate limit exceeded. Try again later."
                else
                    lastError = "Received HTML instead of data (website error or CAPTCHA)"
                end
                
                -- Always print the HTML response start for debugging
                print("[Parsers] HTML response from " .. url .. " (length: " .. #result .. ")")
                print("[Parsers] First 100 chars: " .. result:sub(1, 100))
                
                -- If HTML allowed, return it anyway
                if Parsers.Config.AllowHtml then
                    return result
                end
            else
                -- Success! Return the response
                return result
            end
        end

        -- Failed, try again
        retry = retry + 1
        if retry < retryCount then
            -- Wait with exponential backoff
            local waitTime = Parsers.Config.RetryDelay * (Parsers.Config.RetryBackoff ^ (retry - 1))
            Tasks.message = "Retry in " .. waitTime .. "s: " .. lastError:sub(1, 50)

            -- Wait with a countdown
            local startWait = globals.RealTime()
            while globals.RealTime() < startWait + waitTime do
                local remaining = math.ceil((startWait + waitTime) - globals.RealTime())
                Tasks.message = "Retry in " .. remaining .. "s: " .. lastError:sub(1, 50)
                coroutine.yield()
            end
        end
    end

    -- All retries failed
    Parsers.LogError("Download failed after " .. retryCount .. " attempts", lastError)
    return nil
end

-- More robust SteamID conversion
function Parsers.ConvertToSteamID64(input)
    if not input then return nil end

    -- Safety check for unexpected input types
    if type(input) ~= "string" and type(input) ~= "number" then
        return nil
    end

    local steamid = tostring(input):match("^%s*(.-)%s*$") -- Trim whitespace

    -- If already a SteamID64, just return it
    if steamid:match("^%d+$") and #steamid >= 15 and #steamid <= 20 then
        return steamid
    end

    -- Try direct conversion with error handling
    local success, result = pcall(function()
        if steamid:match("^STEAM_0:%d:%d+$") or steamid:match("^%[U:1:%d+%]$") then
            return steam.ToSteamID64(steamid)
        end
        return nil
    end)

    if success and result and type(result) == "string" and #result >= 15 then
        return result
    end

    -- Manual conversion for SteamID3
    if steamid:match("^%[U:1:%d+%]$") then
        local accountID = steamid:match("%[U:1:(%d+)%]$")
        if accountID and tonumber(accountID) then
            local steamID64 = tostring(76561197960265728 + tonumber(accountID))
            -- Validate the result
            if #steamID64 >= 15 and #steamID64 <= 20 and steamID64:match("^%d+$") then
                return steamID64
            end
        end
    end

    -- Handle plain numeric IDs that might be account IDs
    if steamid:match("^%d+$") and tonumber(steamid) < 1000000000 then
        local steamID64 = tostring(76561197960265728 + tonumber(steamid))
        if #steamID64 >= 15 and #steamID64 <= 20 then
            return steamID64
        end
    end

    return nil
end

-- Safe function to process a line from a raw list
function Parsers.ProcessRawLine(line, database, sourceCause)
    -- Check for nil inputs
    if not line or not database or not sourceCause then
        return false, 0, "Missing required parameters"
    end

    -- Initialize counters
    local added = 0
    local skipped = 0
    local invalid = 0

    local success, errorMsg = pcall(function()
        -- Trim and validate line
        local trimmedLine = line:match("^%s*(.-)%s*$") or ""

        -- Skip comments, empty lines, and other non-ID lines
        if trimmedLine ~= "" and
            not trimmedLine:match("^%-%-") and
            not trimmedLine:match("^#") and
            not trimmedLine:match("^//") and
            not trimmedLine:match("^<!") then
            -- Attempt to extract a SteamID from various formats
            local steamID64 = Parsers.ConvertToSteamID64(trimmedLine)

            -- Add to database if valid and not duplicate
            if steamID64 then
                if not database.content[steamID64] then
                    database.content[steamID64] = {
                        Name = "Unknown",
                        proof = sourceCause
                    }

                    -- Set player priority with error handling
                    pcall(function()
                        playerlist.SetPriority(steamID64, 10)
                    end)
                    added = 1
                else
                    skipped = 1
                end
            else
                invalid = 1
            end
        else
            skipped = 1 -- Count skipped comments/empty lines
        end
    end)

    if not success then
        return false, 0, errorMsg
    else
        return true, added, { skipped = skipped, invalid = invalid }
    end
end

-- Super robust raw list processor
function Parsers.ProcessRawList(content, database, sourceName, sourceCause)
    -- Special handling for bots.tf data
    if sourceName == "bots.tf" then
        return Parsers.ProcessBotsTF(content, database, sourceName, sourceCause)
    end
    
    -- Regular processing for other raw sources
    -- Input validation with detailed errors
    if not content then
        Parsers.LogError("Empty content from " .. (sourceName or "unknown source"))
        return 0
    end

    if not database then
        Parsers.LogError("Invalid database object")
        return 0
    end

    if not sourceName or not sourceCause then
        Parsers.LogError("Missing source metadata")
        return 0
    end

    -- Safety check for database structure
    if type(database) ~= "table" or type(database.content) ~= "table" then
        Parsers.LogError("Invalid database structure", type(database))
        return 0
    end

    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()

    -- Initialize counters
    local count = 0
    local skipped = 0
    local invalid = 0
    local linesProcessed = 0

    -- First do a quick check of content type
    if type(content) ~= "string" then
        Parsers.LogError("Invalid content type: " .. type(content))
        return 0
    end

    -- Check for HTML content that might be an error page
    if content:match("<!DOCTYPE html>") or content:match("<html>") then
        Parsers.LogError("Received HTML instead of raw data", content:sub(1, 200))
        return 0
    end

    -- Count lines for progress reporting
    local lines = {}
    local totalLines = 0

    -- Extract lines with error handling
    local success, errorMsg = pcall(function()
        for line in content:gmatch("[^\r\n]+") do
            table.insert(lines, line)
            totalLines = totalLines + 1
        end
    end)

    if not success then
        Parsers.LogError("Failed to parse lines from " .. sourceName, errorMsg)
        return 0
    end

    if totalLines == 0 then
        Parsers.LogError("No lines found in " .. sourceName, "Content length: " .. #content)
        return 0
    end

    Tasks.message = "Processing " .. totalLines .. " lines from " .. sourceName
    coroutine.yield()

    -- Process each line with robust error handling
    for i, line in ipairs(lines) do
        local success, added, extraInfo = Parsers.ProcessRawLine(line, database, sourceCause)

        if success then
            count = count + added
            if type(extraInfo) == "table" then
                skipped = skipped + extraInfo.skipped
                invalid = invalid + extraInfo.invalid
            end
        else
            -- Log but continue on errors
            if Parsers.Config.DebugMode then
                Parsers.LogError("Error processing line " .. i, extraInfo)
            end
            invalid = invalid + 1
        end

        linesProcessed = linesProcessed + 1

        -- Update progress periodically
        if linesProcessed % Parsers.Config.YieldInterval == 0 or linesProcessed == totalLines then
            local progressPct = totalLines > 0 and math.floor((linesProcessed / totalLines) * 100) or 0
            Tasks.message = string.format("Processing %s: %d%% (%d added, %d skipped)",
                sourceName, progressPct, count, skipped)
            coroutine.yield()
        end
    end

    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        sourceName, count, skipped, invalid)
    coroutine.yield()

    -- Clear lines table to free memory
    lines = nil
    collectgarbage("collect")

    return count
end

-- Process a source with improved error handling and fallbacks
function Parsers.ProcessSource(source, database)
    -- Validate inputs
    if not source then
        Parsers.LogError("Source is nil")
        return 0
    end

    if not database then
        Parsers.LogError("Database is nil")
        return 0
    end

    if not source.url or not source.parser or not source.cause then
        local missingFields = {}
        if not source.url then table.insert(missingFields, "url") end
        if not source.parser then table.insert(missingFields, "parser") end
        if not source.cause then table.insert(missingFields, "cause") end

        Parsers.LogError("Invalid source configuration: missing " .. table.concat(missingFields, ", "))
        return 0
    end

    local sourceName = source.name or "Unknown Source"
    Tasks.message = "Fetching from " .. sourceName .. "..."

    -- Load fallbacks if needed
    local Fallbacks
    pcall(function() 
        Fallbacks = require("Cheater_Detection.Database.Database_Fetcher.Fallbacks")
    end)

    -- Special handling for bots.tf which often fails due to CAPTCHA
    local usesFallback = false
    if sourceName:lower():find("bots%.tf") and Fallbacks then
        -- First try downloading normally
        content = Parsers.Download(source.url)
        
        -- If it fails (likely HTML/CAPTCHA response), use fallbacks
        if not content or #content == 0 or content:match("<!DOCTYPE html>") then
            -- Use GitHub fallbacks first - try common repositories
            local fallbackUrls = {
                "https://raw.githubusercontent.com/PazerOP/tf2_bot_detector/master/staging/cfg/playerlist.official.json",
                "https://raw.githubusercontent.com/wgetJane/tf2-catkill/master/bots.txt"
            }
            
            for _, url in ipairs(fallbackUrls) do
                Tasks.message = "Using fallback source for " .. sourceName .. "..."
                content = Parsers.Download(url)
                
                if content and #content > 0 and not content:match("<!DOCTYPE html>") then
                    Tasks.message = "Fallback source successful!"
                    usesFallback = true
                    break
                end
            end
            
            -- If all online sources fail, use stored fallback data
            if (not content or #content == 0 or content:match("<!DOCTYPE html>")) and Fallbacks.LoadFallbackBots then
                Tasks.message = "Using emergency fallback bot data..."
                local emergencyCount = Fallbacks.LoadFallbackBots(database, source.cause)
                Tasks.message = "Added " .. emergencyCount .. " bots from emergency fallback"
                coroutine.yield()
                return emergencyCount
            end
        end
    else
        -- Non-bots.tf source - normal download procedure
        content = Parsers.Download(source.url)
    end

    -- If we still have no content, try backup URL if one exists
    if (not content or #content == 0) and sourceUrls and sourceUrls.backup then
        Tasks.message = "Primary URL failed, trying backup..."
        content = Parsers.Download(sourceUrls.backup)
    end

    -- If all downloads failed
    if not content or #content == 0 then
        Parsers.LogError("Failed to fetch from " .. sourceName)
        return 0
    end

    -- Process content based on parser type with full error handling
    local count = 0
    
    -- If we're using a fallback URL for bots.tf, adjust the parser as needed
    local parser = source.parser
    if usesFallback and sourceName:lower():find("bots%.tf") then
        if content:match("^%s*{") or content:match("^%s*%[") then
            parser = "tf2db"  -- Use JSON parser for JSON content
        else
            parser = "raw"    -- Use raw parser for plain text content
        end
    end

    if parser == "raw" then
        local success, result = pcall(function()
            return Parsers.ProcessRawList(content, database, sourceName, source.cause)
        end)

        if success then
            count = result
        else
            Parsers.LogError("Failed to parse raw list from " .. sourceName, result)
        end
    elseif parser == "tf2db" then
        local success, result = pcall(function()
            return Parsers.ProcessTF2DB(content, database, source)
        end)

        if success then
            count = result
        else
            Parsers.LogError("Failed to parse TF2DB data from " .. sourceName, result)
            
            -- If JSON parsing failed, try as raw list as a fallback
            Tasks.message = "Trying alternate parser for " .. sourceName
            success, result = pcall(function() 
                return Parsers.ProcessRawList(content, database, sourceName, source.cause)
            end)
            
            if success then
                count = result
            end
        end
    else
        Parsers.LogError("Unknown parser type: " .. source.parser)
    end

    -- Clear content to free memory
    content = nil
    collectgarbage("collect")

    return count
end

-- Improved TF2DB parser with much better error handling
function Parsers.ProcessTF2DB(content, database, source)
    -- Input validation
    if not content or not database or not source then
        Parsers.LogError("Missing required parameters for ProcessTF2DB")
        return 0
    end

    local sourceName = source.name or "Unknown TF2DB Source"
    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()

    -- Track stats
    local count = 0
    local skipped = 0
    local invalid = 0
    local processed = 0

    -- First try parsing as JSON (safer approach)
    local jsonSuccess, data = pcall(Json.decode, content)

    if jsonSuccess and type(data) == "table" then
        -- Process as proper JSON - look for players array or other common structures
        if type(data.players) == "table" then
            -- Handle players array format
            for _, player in ipairs(data.players) do
                if type(player) == "table" and player.steamid then
                    local steamID64 = Parsers.ConvertToSteamID64(player.steamid)

                    if steamID64 and not database.content[steamID64] then
                        database.content[steamID64] = {
                            Name = player.name or "Unknown",
                            proof = source.cause
                        }

                        pcall(function() playerlist.SetPriority(steamID64, 10) end)
                        count = count + 1
                    elseif steamID64 then
                        skipped = skipped + 1
                    else
                        invalid = invalid + 1
                    end

                    processed = processed + 1

                    -- Yield occasionally
                    if processed % Parsers.Config.YieldInterval == 0 then
                        Tasks.message = sourceName .. ": " .. processed .. " processed, " .. count .. " added"
                        coroutine.yield()
                    end
                end
            end
        else
            -- Fall back to direct string parsing approach if JSON structure is unexpected
            return Parsers.ProcessTF2DBString(content, database, source)
        end
    else
        -- JSON parsing failed, try direct string approach
        return Parsers.ProcessTF2DBString(content, database, source)
    end

    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        sourceName, count, skipped, invalid)
    coroutine.yield()

    collectgarbage("collect")
    return count
end

-- Direct string parsing approach for TF2DB with better error handling
function Parsers.ProcessTF2DBString(content, database, source)
    local sourceName = source.name or "Unknown Source"

    -- Variables for tracking
    local count = 0
    local skipped = 0
    local invalid = 0
    local processed = 0

    -- Check for empty content or obvious errors first
    if not content or #content == 0 then
        Parsers.LogError("Empty TF2DB content from " .. sourceName)
        return 0
    end
    
    -- Check if content is valid JSON format
    if content:match("^%s*{") or content:match("^%s*%[") then
        -- Try to parse as JSON first (better approach)
        local success, jsonData = pcall(Json.decode, content)
        if success and type(jsonData) == "table" then
            -- Process as JSON
            return Parsers.ProcessTF2DBJson(jsonData, database, source)
        end
    end

    -- Direct string parsing with safety checks
    local currentIndex = 1
    local contentLength = #content

    while currentIndex < contentLength and currentIndex > 0 do
        -- Find next steamid entry with error handling
        local success, steamIDStart = pcall(function()
            return content:find('"steamid":%s*"', currentIndex)
        end)

        if not success or not steamIDStart then break end

        -- Extract steamid with error handling
        local steamID = nil
        local extractSuccess = pcall(function()
            currentIndex = steamIDStart + 10
            local steamIDEnd = content:find('"', currentIndex)
            if not steamIDEnd then return end

            steamID = content:sub(currentIndex, steamIDEnd - 1)
            currentIndex = steamIDEnd + 1
        end)

        -- Process the extracted steamID safely
        if extractSuccess and steamID then
            local steamID64 = Parsers.ConvertToSteamID64(steamID)

            -- Add to database if valid
            if steamID64 and not database.content[steamID64] then
                database.content[steamID64] = {
                    Name = "Unknown",
                    proof = source.cause
                }

                pcall(function() playerlist.SetPriority(steamID64, 10) end)
                count = count + 1
            elseif steamID64 then
                skipped = skipped + 1
            else
                invalid = invalid + 1
            end

            processed = processed + 1

            -- Yield occasionally
            if processed % Parsers.Config.YieldInterval == 0 then
                Tasks.message = "Processing " .. sourceName .. "... " .. count .. " added"
                coroutine.yield()
            end
        end
    end

    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        sourceName, count, skipped, invalid)
    coroutine.yield()

    -- Clean up
    collectgarbage("collect")

    return count
end

-- New function to process JSON TF2DB data
function Parsers.ProcessTF2DBJson(jsonData, database, source)
    local sourceName = source.name or "Unknown Source"
    Tasks.message = "Processing " .. sourceName .. " JSON..."
    coroutine.yield()
    
    -- Track stats
    local count = 0
    local skipped = 0
    local invalid = 0
    local processed = 0
    
    -- Check for players array structure
    if type(jsonData.players) == "table" then
        local totalPlayers = #jsonData.players
        Tasks.message = "Processing " .. totalPlayers .. " players from " .. sourceName
        
        for _, player in ipairs(jsonData.players) do
            if type(player) == "table" then
                -- Extract SteamID from different formats
                local steamID64 = nil
                
                if player.steamid then
                    steamID64 = Parsers.ConvertToSteamID64(player.steamid)
                elseif player.steamID64 then
                    steamID64 = player.steamID64
                elseif player.attributes and player.attributes[1] == "cheater" then
                    -- Special handling for certain JSON formats
                    steamID64 = Parsers.ConvertToSteamID64(player.id)
                end
                
                -- Add to database if valid
                if steamID64 and not database.content[steamID64] then
                    database.content[steamID64] = {
                        Name = player.name or player.player_name or "Unknown",
                        proof = source.cause
                    }
                    
                    pcall(function() playerlist.SetPriority(steamID64, 10) end)
                    count = count + 1
                elseif steamID64 then
                    skipped = skipped + 1
                else
                    invalid = invalid + 1
                end
            end
            
            processed = processed + 1
            
            -- Yield occasionally to update progress
            if processed % Parsers.Config.YieldInterval == 0 or processed == totalPlayers then
                local progressPct = totalPlayers > 0 and math.floor((processed / totalPlayers) * 100) or 100
                Tasks.message = string.format("%s: %d%% (%d added, %d skipped)", 
                    sourceName, progressPct, count, skipped)
                coroutine.yield()
            end
        end
    else
        -- Handle other JSON structures
        Parsers.LogError("Unknown JSON structure for " .. sourceName)
    end
    
    Tasks.message = string.format("Finished %s: %d added, %d skipped, %d invalid",
        sourceName, count, skipped, invalid)
    coroutine.yield()
    
    collectgarbage("collect")
    return count
end

-- New function specifically for handling bots.tf response
function Parsers.ProcessBotsTF(content, database, sourceName, sourceCause)
    -- Input validation with detailed errors
    if not content then
        Parsers.LogError("Empty content from " .. sourceName)
        return 0
    end
    
    if not database then
        Parsers.LogError("Invalid database object")
        return 0
    end
    
    Tasks.message = "Processing " .. sourceName .. "..."
    coroutine.yield()
    
    -- Initialize counters
    local count = 0
    local skipped = 0
    local invalid = 0
    local linesProcessed = 0
    
    -- First do a quick check of content type
    if type(content) ~= "string" then
        Parsers.LogError("Invalid content type: " .. type(content))
        return 0
    end
    
    -- bots.tf returns raw text with one SteamID64 per line
    -- It might have some empty lines or other data we need to filter
    
    -- Count lines for progress reporting
    local lines = {}
    local totalLines = 0
    
    -- Extract lines with error handling
    local success, errorMsg = pcall(function()
        for line in content:gmatch("[^\r\n]+") do
            -- Skip empty lines or lines that are obviously not SteamID64s
            line = line:match("^%s*(.-)%s*$") -- Trim whitespace
            if line ~= "" and #line >= 15 and #line <= 20 and line:match("^%d+$") then
                table.insert(lines, line)
                totalLines = totalLines + 1
            end
        end
    end)
    
    if not success then
        Parsers.LogError("Failed to parse lines from " .. sourceName, errorMsg)
        return 0
    end
    
    if totalLines == 0 then
        Parsers.LogError("No valid SteamID64s found in " .. sourceName, "Content length: " .. #content)
        return 0
    end
    
    Tasks.message = "Processing " .. totalLines .. " SteamID64s from " .. sourceName
    coroutine.yield()
    
    -- Process each line with robust error handling
    for i, steamID64 in ipairs(lines) do
        -- We should already have valid SteamID64s at this point
        
        -- Add to database if not duplicate
        if not database.content[steamID64] then
            database.content[steamID64] = {
                Name = "Unknown",
                proof = sourceCause
            }
            
            -- Set player priority with error handling
            pcall(function()
                playerlist.SetPriority(steamID64, 10)
            end)
            count = count + 1
        else
            skipped = skipped + 1
        end
        
        linesProcessed = linesProcessed + 1
        
        -- Update progress periodically
        if linesProcessed % Parsers.Config.YieldInterval == 0 or linesProcessed == totalLines then
            local progressPct = math.floor((linesProcessed / totalLines) * 100)
            Tasks.message = string.format("Processing %s: %d%% (%d added, %d skipped)",
                sourceName, progressPct, count, skipped)
            coroutine.yield()
        end
    end
    
    Tasks.message = string.format("Finished %s: %d added, %d skipped",
        sourceName, count, skipped)
    coroutine.yield()
    
    -- Clear lines table to free memory
    lines = nil
    collectgarbage("collect")
    
    return count
end

return Parsers

end)
__bundle_register("Cheater_Detection.Database.Database_Fetcher.Fallbacks", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Fallback data for when online sources fail

local Fallbacks = {}

-- Known common bot patterns for identification
Fallbacks.BotPatterns = {
    "bot",
    "doeshotter",
    "royalhack",
    "omegatronic",
    "m?gcitybot",
    "braaap",
    "racistbot",
    "discordbot",
    "wamo",
    "nkill",
    "waffen",
    "d[o0]ktor",
    "racism",
    "myg[o0]t",
    "lagbot",
    "cathook",
    "n word",
    "nig",
    "cheat"
}

-- Emergency fallback of known bot IDs in case all online sources fail
Fallbacks.KnownBots = {
    -- Just a small sample of known bots for emergency fallback
    "76561198961947572", -- DoesHotterBot
    "76561199014767523", -- DoesHotterBot 
    "76561199045829301", -- OmegaTronic
    "76561199046828571", -- OmegaTronic
    "76561199066518026", -- MYG)T
    "76561199096930543", -- MYG)T
    "76561199044181696", -- MYG)T
    "76561198134956590", -- MYG)T
    "76561198404433491", -- MYG)T
    "76561198340178446", -- Royalhack.net Bot 
    "76561198818929774", -- Royalhack.net Bot
    "76561199055393391"  -- Royalhack.net Bot
}

-- Handle using the fallback data in case of API failure
function Fallbacks.LoadFallbackBots(database, cause)
    local count = 0
    
    -- Add the fallback bot IDs to the database
    for _, steamID64 in ipairs(Fallbacks.KnownBots) do
        if not database.content[steamID64] then
            database.content[steamID64] = {
                Name = "Bot (Fallback Data)",
                proof = cause or "Bot"
            }
            
            -- Add to playerlist for in-game use
            pcall(function()
                playerlist.SetPriority(steamID64, 10)
            end)
            
            count = count + 1
        end
    end
    
    return count
end

-- Detect if a player name matches known bot patterns
function Fallbacks.IsBotByName(playerName)
    if not playerName then return false end
    
    local lowerName = playerName:lower()
    
    -- Check against bot patterns
    for _, pattern in ipairs(Fallbacks.BotPatterns) do
        if lowerName:find(pattern) then
            return true
        end
    end
    
    -- Check for common bot naming patterns
    if lowerName:match("^%[%d+%]$") then -- [123] format
        return true
    end
    
    if lowerName:match("%d+%.%d+%.%d+%.%d+") then -- IP address in name
        return true
    end
    
    -- Check for repetitive characters (common in spam bots)
    local repeats = lowerName:match("(.)%1%1%1%1%1+") -- 6+ of same character
    if repeats then
        return true
    end
    
    return false
end

return Fallbacks

end)
__bundle_register("Cheater_Detection.Database.Database_Fetcher.Tasks", function(require, _LOADED, __bundle_register, __bundle_modules)
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

end)
__bundle_register("Cheater_Detection.Database.Database_Fetcher.Sources", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Source definitions for database fetching with updated URLs and fallbacks

local Sources = {}

-- List of available sources
Sources.List = {
    {
        name = "bots.tf",
        url = "https://raw.githubusercontent.com/PazerOP/tf2_bot_detector/master/staging/cfg/playerlist.official.json",
        -- Switched from bots.tf to PazerOP's GitHub JSON which contains the same bot data
        cause = "Bot",
        parser = "tf2db" -- Changed parser to tf2db since it's JSON format
    },
    -- Fallback source for bots (in case the primary source fails)
    {
        name = "TF2BD Bots (backup)",
        url = "https://raw.githubusercontent.com/wgetJane/tf2-catkill/master/bots.txt",
        cause = "Bot",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Cheater List",
        url = "https://raw.githubusercontent.com/d3fc0n6/CheaterList/main/CheaterFriend/64ids",
        cause = "Cheater",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Tacobot List",
        url = "https://raw.githubusercontent.com/d3fc0n6/TacobotList/master/64ids",
        cause = "Tacobot",
        parser = "raw"
    },
    {
        name = "d3fc0n6 Pazer List",
        url = "https://raw.githubusercontent.com/d3fc0n6/TacobotList/master/64ids",
        cause = "Pazer List",
        parser = "raw"
    },
    {
        name = "Sleepy List - Bots",
        url = "https://raw.githubusercontent.com/surepy/tf2db-sleepy-list/main/playerlist.sleepy-bots.merged.json",
        cause = "Bot",
        parser = "tf2db"
    },
    {
        name = "Sleepy List - RGL",
        url = "https://raw.githubusercontent.com/surepy/tf2db-sleepy-list/main/playerlist.rgl-gg.json",
        cause = "RGL Banned",
        parser = "tf2db"
    }
}

-- Function to add a custom source
function Sources.AddSource(name, url, cause, parser)
    if not name or not url or not cause or not parser then
        print("[Database Fetcher] Error: Missing required fields for new source")
        return false
    end

    if parser ~= "raw" and parser ~= "tf2db" then
        print("[Database Fetcher] Error: Invalid parser type: " .. parser)
        return false
    end

    table.insert(Sources.List, {
        name = name,
        url = url,
        cause = cause,
        parser = parser
    })

    print("[Database Fetcher] Added new source: " .. name)
    return true
end

return Sources

end)
__bundle_register("Cheater_Detection.Utils.Config", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[ Imports ]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local json = require("Cheater_Detection.Libs.Json")
local Default_Config = require("Cheater_Detection.Utils.DefaultConfig")

local Config = {}

local Log = Common.Log
local Notify = Common.Notify
Log.Level = 0

local script_name = GetScriptName():match("([^/\\]+)%.lua$")
local folder_name = string.format([[Lua %s]], script_name)

--[[ Helper Functions ]]
function Config.GetFilePath()
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return fullPath .. "/config.cfg"
end

local function checkAllKeysExist(expectedMenu, loadedMenu)
    for key, value in pairs(expectedMenu) do
        if loadedMenu[key] == nil then
            return false
        end
        if type(value) == "table" then
            local result = checkAllKeysExist(value, loadedMenu[key])
            if not result then
                return false
            end
        end
    end
    return true
end

--[[ Configuration Functions ]]
function Config.CreateCFG(cfgTable)
    cfgTable = cfgTable or Default_Config
    local filepath = Config.GetFilePath()
    local file = io.open(filepath, "w")
    local shortFilePath = filepath:match(".*\\(.*\\.*)$")
    if file then
        local serializedConfig = json.encode(cfgTable)
        file:write(serializedConfig)
        file:close()
        printc(100, 183, 0, 255, "Success Saving Config: Path: " .. shortFilePath)
        Notify.Simple("Success! Saved Config to:", shortFilePath, 5)
    else
        local errorMessage = "Failed to open: " .. shortFilePath
        printc(255, 0, 0, 255, errorMessage)
        Notify.Simple("Error", errorMessage, 5)
    end
end

function Config.LoadCFG()
    local filepath = Config.GetFilePath()
    local file = io.open(filepath, "r")
    local shortFilePath = filepath:match(".*\\(.*\\.*)$")
    if file then
        local content = file:read("*a")
        file:close()
        local loadedCfg = json.decode(content)
        if loadedCfg and checkAllKeysExist(Default_Config, loadedCfg) and not input.IsButtonDown(KEY_LSHIFT) then
            printc(100, 183, 0, 255, "Success Loading Config: Path: " .. shortFilePath)
            Notify.Simple("Success! Loaded Config from", shortFilePath, 5)
            G.Menu = loadedCfg
        else
            local warningMessage = input.IsButtonDown(KEY_LSHIFT) and "Creating a new config." or "Config is outdated or invalid. Resetting to default."
            printc(255, 0, 0, 255, warningMessage)
            Notify.Simple("Warning", warningMessage, 5)
            Config.CreateCFG(Default_Config)
            G.Menu = Default_Config
        end
    else
        local warningMessage = "Config file not found. Creating a new config."
        printc(255, 0, 0, 255, warningMessage)
        Notify.Simple("Warning", warningMessage, 5)
        Config.CreateCFG(Default_Config)
        G.Menu = Default_Config
    end
end

return Config
end)
return __bundle_require("__root")