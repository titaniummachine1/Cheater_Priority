--[[
    Cheater Detection for Lmaobox
    Author: titaniummachine1 (https://github.com/titaniummachine1)
    Credit for examples:
    LNX (github.com/lnx00) for base script
    Muqa for visuals and design help
]]

---@alias PlayerData { Angle: EulerAngles[], Position: Vector3[], SimTime: number[] }


---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.981, "lnxLib version is too old, please update it!")

local TF2 = lnxLib.TF2
local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WPR = TF2.WPlayer, TF2.WPlayerResource
local Helpers = lnxLib.TF2.Helpers
local Fonts = lnxLib.UI.Fonts

---@type boolean, ImMenu
local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local players = entities.FindByClass("CTFPlayer")

local pLocal = entities.GetLocalPlayer()
local WLocal = pLocal
local latin, latout = 0, 0

local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)

local options = {
    StrikeLimit = 5,
    MaxTickDelta = 8,
    Aimbotfov = 5,
    AutoMark = true,
    BhopTimes = 5,
    debug = false,
    tags = true
}

local prevData = {
    SimTime = {},
    pBhop = {}
} ---@type PlayerData
local playerData = {}

local function StrikePlayer(reason, player)
    local idx = player:GetIndex()

    -- Initialize strikes if needed
    if not playerData[idx] then
        playerData[idx] = {
            entity = player,
            strikes = 0,
            detected = false
        }
    end

    -- Increment strikes
    playerData[idx].strikes = playerData[idx].strikes + 1

    -- Handle strike limit
    if playerData[idx].strikes < options.StrikeLimit then
        -- Print message
        if player and playerlist.GetPriority(player) > -1 and playerData[idx].strikes == math.floor(options.StrikeLimit / 2) then -- only call the player sus if hes has been flagged half of the total amount
            client.ChatPrintf(tostring("\x04[CD] \x03" .. player:GetName() .. "\x01 is \x07ffd500Suspicious"))
            if options.AutoMark and player ~= pLocal then
                playerlist.SetPriority(player, 5)
                LastStrike = globals.TickInterval()
            end
        end

        if reason == "Invalid pitch" then
            -- Print cheating message if player is not detected
            if player and playerlist.GetPriority(player) > -1 and not playerData[idx].detected then
                print(tostring("[CD] ".. player:GetName() .. " is cheating"))
                client.ChatPrintf(tostring("\x04[CD] \x03" .. player:GetName() .. " \x01is\x07ff0019 Cheating\x01! \x01(\x04" .. reason.. "\x01)"))

                -- Increment strikes
                playerData[idx].strikes = options.StrikeLimit
                -- Set player as detected
                playerData[idx].detected = true

                -- Auto mark
                if options.AutoMark and player ~= pLocal then
                    playerlist.SetPriority(player, 10)
                end
            end
        end
    else
        -- Print cheating message if player is not detected
        if player and playerlist.GetPriority(player) > -1 and not playerData[idx].detected then
            print(tostring("[CD] ".. player:GetName() .. " is cheating"))
            client.ChatPrintf(tostring("\x04[CD] \x03" .. player:GetName() .. " \x01is\x07ff0019 Cheating\x01! \x01(\x04" .. reason.. "\x01)"))

            -- Set player as detected
            playerData[idx].detected = true

            -- Auto mark
            if options.AutoMark and player ~= pLocal then
                playerlist.SetPriority(player, 10)
            end
        end
    end
end

-- Detects rage pitch (looking up/down too much)
local function CheckAngles(player, entity)
    local angles = player:GetEyeAngles()
    if angles.pitch == 89.000 or angles.pitch == -89.000
    or angles.pitch >= 90 or angles.pitch <= -90 then
        StrikePlayer("Invalid pitch", entity)
        return true
    end
    return false
end

local tick_count = 0
-- Detects rage pitch (looking up/down too much)
local function CheckDuckSpeed(player, entity)
    local angles = player:GetEyeAngles()
    local flags = player:GetPropInt("m_fFlags")
    local OnGround = flags & FL_ONGROUND == 1
    local DUCKING = flags & FL_DUCKING == 2
    if OnGround
    and DUCKING then -- detects fake up/down/up/fakedown pitch settigns {lbox]
        local MaxDuckSpeed = {
            [1] = 400,
            [2] = 300,
            [3] = 240,
            [4] = 262,
            [5] = 320,
            [6] = 77,
            [7] = 300,
            [8] = 320,
            [9] = 300
        }
        if entity:EstimateAbsVelocity():Length() >= MaxDuckSpeed[entity:GetPropInt("m_iClass")] then
            tick_count = tick_count + 1
            if tick_count >= 66 then
                StrikePlayer("Duck Speed", entity)
                tick_count = 0
                return true
            end
            return true
        end
        return false
    end
    return false
end

local function CheckBhop(pEntity, mData, entity)
    if not mData[pEntity] then
        mData[pEntity] = { pBhop = { 0, 0 }, iPlayerSuspicion = 0 }
    end

    local flags = pEntity:GetPropInt("m_fFlags")
    local bOnGround = flags & FL_ONGROUND == 1

    if bOnGround then
        mData[pEntity].pBhop[1] = 0 -- Reset the bhop count if the player is on the ground
    else
        mData[pEntity].pBhop[1] = mData[pEntity].pBhop[1] + 1 -- Increment the bhop count if the player is in the air
    end

    if mData[pEntity].pBhop[1] >= options.BhopTimes then
        mData[pEntity].iPlayerSuspicion = mData[pEntity].iPlayerSuspicion + 1 -- Increment the suspicion if the player consistently bhops
        mData[pEntity].pBhop[1] = 0 -- Reset the bhop count
        StrikePlayer("Bunny Hop", entity) --return true, mData[pEntity].pBhop[1] -- Return true if the suspicion threshold is reached
        return true
    end
    return false
end

-- Check if a player is choking packets (Fakelag, Doubletap)
local function CheckChoke(player, entity)
    local simTime = player:GetSimulationTime()
    local oldSimTime = prevData.SimTime[player:GetIndex()]
    if not oldSimTime then return end -- no simTime
    local delta = simTime - oldSimTime --get difference between current and previous simtime
    if delta == 0 then return end --its local player revinding time
    local deltaTicks = Conversion.Time_to_Ticks(delta)
    if deltaTicks > options.MaxTickDelta then
        return true
    end
    return false
end

--[[local function isValidName(player, name, entity)

    for i, pattern in ipairs(BOTPATTERNS) do
      if string.find(name, pattern) then
        StrikePlayer("Bot Name", entity, player)
      end
    end
end]]

local HurtVictim = nil
local shooter = nil

-- Event hook function
local function event_hook(ev)
    -- Return if the event is not a player hurt event
    if ev:GetName() ~= "player_hurt" then
        return
    end

    -- Get the entities involved in the event
    local attacker = entities.GetByUserID(ev:GetInt("attacker"))
    if playerData[attacker:GetIndex()] ~= nil
    and playerData[attacker:GetIndex()].detected == true then return end --skip detected players
    local Victim = entities.GetByUserID(ev:GetInt("userid"))
        if attacker == nil or Victim == nil then return end
        if options.debug == false and attacker == pLocal then return end
        if options.debug == false and TF2.IsFriend(attacker:GetIndex(), true) then return end
        if playerlist.GetPriority(attacker) == 10 then return end
        if attacker:IsDormant() then return end
        if Victim:IsDormant() then return end
        if not attacker:IsAlive() then return end
        local pWeapon = attacker:GetPropEntity("m_hActiveWeapon")
        if pWeapon:GetWeaponProjectileType() ~= 1 then return end --skip projectile weapons
    --print("pass")
    --update lastattacker and lastHurtVictim
    shooter = attacker
    HurtVictim = Victim
end

local lastAngles = {}
-- Function to check for aimbot
local function CheckAimbot()
	if HurtVictim == nil then return end -- when noone gets killed or damaged amingot check is not needed
        local idx = shooter:GetIndex()
    if lastAngles[idx] == nil then
        lastAngles[idx] = shooter:GetEyeAngles()
    end -- when noone gets killed or damaged amingot check is not needed

    local Wshooter = WPlayer.FromEntity(shooter)
    local shootAngles = Wshooter:GetEyeAngles() --get angles of player called

    -- Initialize variables
    local shooterTeam = shooter:GetTeamNumber()

    -- Get the shooter's position and view angles
    local shooterOrigin = Wshooter:GetEyePos()

        -- Get the attacker's class and aim position
        local attackerclass = shooter:GetPropInt("m_iClass")
        local AimPos = 4
        if attackerclass == 2 or attackerclass == 8 then
            AimPos = 1
        end

        -- Get the most propable hibox aimbot will target
        local WHurtVictim = WPlayer.FromEntity(HurtVictim)
        local playerOrigin = WHurtVictim:GetHitboxPos(AimPos) -- most propable aimbot target
        local AimbotAngle = Math.PositionAngles(shooterOrigin, playerOrigin)-- most propable aimbot angle
        -- Calculate the FOV between the shooter's view angles and the player's position
        local fov = Math.AngleFov(AimbotAngle, shootAngles)
        local PrewFov = Math.AngleFov(AimbotAngle, lastAngles[idx])
        local FovDelta = math.abs(PrewFov - fov) % 360

        if options.debug == true then print(shooter:GetName(), fov, PrewFov, FovDelta) end

        if FovDelta > options.Aimbotfov
        and fov <= 0.77 then
            StrikePlayer("Aimbot", shooter)
        end
end

local function OnCreateMove(userCmd)
    pLocal = entities.GetLocalPlayer()
    if pLocal == nil then return end -- Skip if local player is nil

    WLocal = WPlayer.FromEntity(pLocal)
    players = entities.FindByClass("CTFPlayer")

    latin, latout = clientstate.GetLatencyIn() * 1000, clientstate.GetLatencyOut() * 1000 -- Convert to ms

    local connectionState = entities.GetPlayerResources():GetPropDataTableInt("m_iConnectionState")[WLocal:GetIndex()]

    -- Get current data
    local currentData = {
        SimTime = {},
        pBhop = {}
    }

    local packetloss = true
    if (latin + latout) < 200 and prevData then
        local localSimTime = WLocal:GetSimulationTime()
        local localOldSimTime = prevData.SimTime[WLocal:GetIndex()]
        if localOldSimTime then
            local localDelta = localSimTime - localOldSimTime
            local localDeltaTicks = Conversion.Time_to_Ticks(localDelta)
            if localDeltaTicks <= options.MaxTickDelta then
                packetloss = false
            end
        end
    end

    for i = 1, #players do
        local entity = players[i]
        local idx = entity:GetIndex()

        if playerData[idx] and playerData[idx].detected == true --dont check detected players
        or entity:IsDormant()
        or not entity:IsAlive() then goto continue end -- Skip if player is nil, dormant or dead

        if options.debug == false and playerlist.GetPriority(entity) == 10 then
            -- Set player as detected
            playerData[idx].detected = true
            goto continue
        end -- Skip local player

        local player = WPlayer.FromEntity(entity)
        currentData.SimTime[idx] = player:GetSimulationTime() --store simulation time of target players

        if options.debug == false and TF2.IsFriend(idx, true) then goto continue end -- Skip local player 

        if HurtVictim ~= nil then goto continue end --skip aimbot check if someone gets killed or damaged

        lastAngles[idx] = player:GetEyeAngles() --store viewangles of target players

        --if isValidName(player, entity:GetName(), entity) == true then break end --detect bot names

        if CheckAngles(player, entity) == true then break end --detects rage cheaters and bots

        if CheckDuckSpeed(player, entity) == true then break end --detects DuckSpeed

        if CheckBhop(player, currentData, entity) == true then break end --detects rage Bhop

        --local XconnectionState = entities.GetPlayerResources():GetPropDataTableInt("m_iConnectionState")[idx]
        if prevData then
            if not packetloss and connectionState == 1 then
                if CheckChoke(player, entity) == true then break end --detects rage Fakelag
            end
        end
        ::continue::
    end

    CheckAimbot() --detect silent aimbot users

    --update globals
    HurtVictim = nil
    shooter = nil
    prevData = currentData
end

local strikes_default = options.StrikeLimit

local function doDraw()

    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)

    
        if engine.IsGameUIVisible() and ImMenu.Begin("Cheater Detection", true) then

            local menuWidth, menuHeight = 250, 300
            local x, y = ImMenu.GetCurrentWindow().X, ImMenu.GetCurrentWindow().Y

            -- Strike Limit Slider
            ImMenu.BeginFrame(1)
            options.StrikeLimit = ImMenu.Slider("Strikes Limit", options.StrikeLimit, 4, 17)
            ImMenu.EndFrame()

            -- Max Tick Delta Slider
            ImMenu.BeginFrame(1)
            options.MaxTickDelta = ImMenu.Slider("Max Packet Choke", options.MaxTickDelta, 8, 22)
            ImMenu.EndFrame()
            
            -- Max Tick Delta Slider
            ImMenu.BeginFrame(1)
            options.BhopTimes = ImMenu.Slider("Max Bhops", options.BhopTimes, 4, 15)
            ImMenu.EndFrame()

            -- Aimbot FOV Slider
            ImMenu.BeginFrame(1)
            options.Aimbotfov = ImMenu.Slider("Aimbot Fov", options.Aimbotfov, 2, 180)
            ImMenu.EndFrame()

            -- Options
            ImMenu.BeginFrame(1)
            options.AutoMark = ImMenu.Checkbox("Auto Mark", options.AutoMark)
            options.tags = ImMenu.Checkbox("Draw Tags", options.tags)
            ImMenu.EndFrame()

            -- Options
            ImMenu.BeginFrame(1)
            options.debug = ImMenu.Checkbox("Debug", options.debug)
            ImMenu.EndFrame()

            ImMenu.End()
        end

        if options.tags and not engine.Con_IsVisible() and not engine.IsGameUIVisible() then
            draw.SetFont(tahoma_bold)
            if playerData then
                for idx, data in pairs(playerData) do
                    local entity = data.entity
                    local strikes = data.strikes
                    local detected = data.detected

                    if not entity or not entity:IsValid() or entity:IsDormant() or not entity:IsAlive() then goto continue end
                        if playerData[idx].strikes >= math.floor(options.StrikeLimit / 2) then
                            local tagText, tagColor
                            local padding = Vector3(0, 0, 7)
                            local headPos = (entity:GetAbsOrigin() + entity:GetPropVector("localdata", "m_vecViewOffset[0]")) + padding
                            if gui.GetValue("CLASS") == "icon" and gui.GetValue("AIM RESOLVER") == 0 then
                                    headPos = headPos + Vector3(0, 0, 17)
                            end
                            local feetPos = entity:GetAbsOrigin() - padding
                            local headScreenPos = client.WorldToScreen(headPos)
                            local feetScreenPos = client.WorldToScreen(feetPos)
                            if headScreenPos ~= nil and feetScreenPos ~= nil then
                                local height = math.abs(headScreenPos[2] - feetScreenPos[2])
                                local width = height * 0.6
                                local x = math.floor(headScreenPos[1] - width * 0.5)
                                local y = math.floor(headScreenPos[2])
                                local w = math.floor(width)
                                local h = math.floor(height)

                                tagText = "SUSPICIOUS"

                                tagColor = {255,255,0,255}
                                if detected then
                                    tagText = "CHEATER"
                                    tagColor = {255,0,0,255}
                                end
                                draw.Color(table.unpack(tagColor))
                                local tagWidth, tagHeight = draw.GetTextSize(tagText)
                                if gui.GetValue("AIM RESOLVER") == 1 then --fix bug when arrow of resolver clips with tag
                                    y = y - 20
                                end
                                draw.Text(math.floor(x + w / 2 - (tagWidth / 2)), y - 30, tagText)
                            end
                        end
                    ::continue::
                end
            end
        end
    end
    ----424 lineeror

local function OnUnload()-- Called when the script is unloaded
    UnloadLib() --unloading lualib
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("CreateMove", "Cheater_detection")                     -- unregister the "CreateMove" callback
callbacks.Unregister("FireGameEvent", "unique_event_hook")                 -- unregister the "FireGameEvent" callback
callbacks.Unregister("Unload", "MCT_Unload")                                -- unregister the "Unload" callback
callbacks.Unregister("Draw", "MCT_Draw")                                   -- unregister the "Draw" callback

--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "Cheater_detection", OnCreateMove)        -- register the "CreateMove" callback
callbacks.Register("FireGameEvent", "unique_event_hook", event_hook)         -- register the "FireGameEvent" callback
callbacks.Register("Unload", "MCT_Unload", OnUnload)                         -- Register the "Unload" callback
callbacks.Register("Draw", "MCT_Draw", doDraw)                              -- Register the "Draw" callback 

--[[ Play sound when loaded ]]--
client.Command('play "ui/buttonclick"', true) -- Play the "buttonclick" sound when the script is loaded