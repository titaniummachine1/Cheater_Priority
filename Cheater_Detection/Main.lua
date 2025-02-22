--[[
    Cheater Detection for Lmaobox Recode
    Author: titaniummachine1 (https://github.com/titaniummachine1)
    Credits:
    LNX (github.com/lnx00) for base script
    Muqa for visuals and design assistance
    Alchemist for testing and party callout
]]

--[[ actiave the script Modules]]
local Common = require("Cheater_Detection.Utils.Common")
local G = require("Cheater_Detection.Utils.Globals")
local Config = require("Cheater_Detection.Utils.Config")
--local Database = require("Cheater_Detection.Database")
--local Detections = require("Cheater_Detection.Detections")
--require("Cheater_Detection.Visuals") --wake up the visuals
--require("Cheater_Detection.Modules.EventHandler") --wake up the visuals
require("Cheater_Detection.Misc.Visuals.Menu") --wake up the visuals

--[[ Variables ]]

local WPlayer, PR = Common.WPlayer, Common.PlayerResource

Config.LoadCFG() --load config on load of script
Database.LoadDatabase() --load database inicialy to have stable databse first before loadign imports
Database.importDatabase() --import the database after loading main one to avoid geting trolled by empty imports

playerlist.SetPriority(entities.GetLocalPlayer(), 0) --debug

--[[ Update the player data every tick ]]--
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
            G.PlayerData[steamid].Current = Common.createRecord(viewAngles, viewPos, headHitboxPosition, bodyHitboxPosition, simulationTime, isOnGround)

            -- Perform detection checks
            Detections.CheckAngles(wrappedPlayer, entity)
            Detections.CheckDuckSpeed(wrappedPlayer, entity)
            Detections.CheckBunnyHop(wrappedPlayer, entity)
            Detections.CheckPacketChoke(wrappedPlayer, entity)
            Detections.CheckSequenceBurst(wrappedPlayer, entity)
            --Detections.rtrue(entity) --debug

            -- Update history
            G.PlayerData[steamid].History = G.PlayerData[steamid].History or {}
            table.insert(G.PlayerData[steamid].History, G.PlayerData[steamid].Current)

            -- Keep the history table size to a maximum of 66
            if #G.PlayerData[steamid].History > 66 then
                table.remove(G.PlayerData[steamid].History, 1)
            end
        end
    end
end

--[[ Callbacks ]]
local function OnUnload() -- Called when the script is unloaded
    Config.CreateCFG(G.Menu) -- Save the configurations
    if G.DataBase then
        if G.Menu.Main.debug then
            Database.ClearSuspect(Common.GetSteamID64(G.pLocal)) -- Clear the local if debug is enabled
        end

        Database.SaveDatabase(G.DataBase) -- Save the database
    else
        Database.SaveDatabase()
    end
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("Unload", "CDDatabase_Unload")                                -- unregister the "Unload" callback
--[[ Register callbacks ]]--
callbacks.Register("Unload", "CDDatabase_Unload", OnUnload)                         -- Register the "Unload" callback

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("CreateMove", "Cheater_detection")                     -- unregister the "CreateMove" callback

--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "Cheater_detection", OnCreateMove)        -- register the "CreateMove" callback