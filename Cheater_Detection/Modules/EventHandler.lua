
local EventHandler = {}

--[[ Imports ]]
local Common = require("Cheater_Detection.Common")
local Detections = require("Cheater_Detection.Detections")
local G = require("Cheater_Detection.Globals")

--local Log = Common.Log

local classNames = {
    [1] = "Scout",
    [2] = "Sniper",
    [3] = "Soldier",
    [4] = "Demoman",
    [5] = "Medic",
    [6] = "Heavy",
    [7] = "Pyro",
    [8] = "Spy",
    [9] = "Engineer"
}

-- Global variables
local options = { 'Yes', 'No'}

--[[debug]]
client.Command("sv_vote_issue_kick_allowed 1", true) -- enable cheats"sv_cheats 1"
client.Command("cl_vote_ui_active_after_voting 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_failure_timer 1", true) -- enable cheats"sv_cheats 1"


-- Event hook function
local function event_hook(ev)
    local eventName = ev:GetName()

    if G.Menu.Visuals.Class_Change_Reveal.Enable and (eventName == "player_changeclass") then
        local player = entities.GetByUserID(ev:GetInt("userid"))
        if (player == nil) then return end

        local playerName = player:GetName()
        if Common.IsFriend(player) then return end --ignore friends

        if G.Menu.Visuals.Class_Change_Reveal.EnemyOnly then --ignore team
            if player:GetTeamNumber() == G.pLocal:GetTeamNumber() then return end
        end

        local classNumber = ev:GetInt("class")
        local className = classNames[classNumber] or "Unknown Class"
        local text = string.format("\x04[CD] \x03%s\x01 changed class to \x04%s", playerName, className)
        client.ChatPrintf(text)

        if G.Menu.Visuals.Class_Change_Reveal.PartyChat then
            client.Command( "say_party \"" .. text .. "\"", true );
        end

        if G.Menu.Visuals.Class_Change_Reveal.Console then
            printc(255,255,255,255, text)
        end
        return
    end

    if (eventName == "player_connect") or (eventName == "player_spawn") then
            local UserID = (ev:GetInt("userid"))
        if (UserID == nil) then return end
            local player = entities.GetByUserID(UserID)
        if (player == nil) then return end

        local player = entities.GetByUserID(UserID)
        local playerName = player:GetName()

        if Common.IsFriend(player) then return end --ignore friends

        --run cehck for backgreound in database
        Detections.KnownCheater(player)
        return
    end

    --[[Vote Revealer]]--
    if (eventName == "vote_cast") then
        local player = entities.GetByIndex(event:GetInt("entityid"))
        if (player == nil) then return end

        local me = G.pLocal
        if (me == nil or me == player) then return end

        local processVote = false

        if (G.Menu.Visuals.Vote_Reveal.TargetTeam.MyTeam and me:GetTeamNumber() == player:GetTeamNumber()) then
            processVote = true
        elseif (G.Menu.Visuals.Vote_Reveal.TargetTeam.enemyTeam and me:GetTeamNumber() ~= player:GetTeamNumber()) then
            processVote = true
        end

        if not processVote then return end

        local vote_option = event:GetInt("vote_option")
        local optionColorCode = vote_option == 0 and "\x07" .. "00ff00" or "\x07" .. "ff0000" -- Green for Yes, Red for No
        local option = vote_option == 0 and "Yes" or "No"

        local playerinfo = client.GetPlayerInfo(player:GetIndex())
        if (playerinfo == nil) then return end

        local playername = playerinfo.Name
        local teamIdentifier = me:GetTeamNumber() == player:GetTeamNumber() and "[Same team vote]" or "[Other team vote]"

        local formattedText = string.format("\x01%s \x03%s \x01voted %s%s\x01!", teamIdentifier, playername, optionColorCode, option)

        -- Print to console with colors
        if G.Menu.Visuals.Vote_Reveal.Console then
            print(formattedText) -- This might need adjusting if console does not support colors
        end

        -- Print to party chat with colors
        if G.Menu.Visuals.Vote_Reveal.PartyChat then
            client.ChatPrintf(formattedText)
        end
    end

    if (eventName == "teamplay_round_win") or (eventName == "world_status_changed") then
        --reset playerdata to not crash game after long sesion
        G.PlayerData = {}
        return
    end

    -- Handle game events
    if eventName == "player_death" or eventName == "player_hurt" then
        -- Initialize variables
        local isHeadshot, attacker, victim

        -- Get the entities involved in the event
        attacker = entities.GetByUserID(ev:GetInt("attacker"))
        victim = entities.GetByUserID(ev:GetInt("userid"))

        -- Skip if attacker or victim is nil, or if attacker is valid
        if not attacker or not victim or Common.IsValidPlayer(attacker, true) then return end
        local attackerID = Common.GetSteamID64(attacker)

        --ignore detected players
        if Common.IsCheater(attackerID) then return end
        --ignore non hitscan weapons
        if attacker:GetPropEntity("m_hActiveWeapon"):GetWeaponProjectileType() ~= 1 then return end

        -- Handle specific event types
        isHeadshot = (ev:GetInt("customkill") == TF_CUSTOM_AIM_HEADSHOT)
        if eventName == "player_death" and isHeadshot then --when killed with headshot
            --Get the most recent entry in the history table
            G.PlayerData[attackerID].History[#G.PlayerData[attackerID].History].FiredGun = 1
            --CheckAimbotFlick(hurtVictim , shooter)
            --print(true)
        else
            G.PlayerData[attackerID].History[#G.PlayerData[attackerID].History].FiredGun = 2
            --CheckAimbotFlick(hurtVictim , shooter)
        end

        return
    end
end

-- Function to handle user message vote starts
local function handleUserMessageVoteStart(msg)
    if not (msg:GetID() == VoteStart) then return end --fix the code working every time someone sends any mesage

    local team = msg:ReadByte()
    local voteIdx = msg:ReadInt(32)
    local entIdx = msg:ReadByte()
    local dispStr = msg:ReadString(64)
    local detailsStr = msg:ReadString(64)
    local target = msg:ReadByte() >> 1 --index

    local playerInfo = client.GetPlayerInfo(target)  -- Retrieve player information

    --ent0 is caster ent1 is victim
    local ent0, ent1 = entities.GetByIndex(entIdx), entities.GetByIndex(target)
    local me = entities.GetLocalPlayer()

    -- Format the player name more clearly
    local playerName = playerInfo and playerInfo.Name or "[unknown]"

    if G.Menu.AutoVote.Vote_Anouncer and ent0 == me and Common.IsCheater(Common.GetSteamID64(ent1)) then -- Check if the local player initiated the vote
        --client.ChatPrintf(string.format('\x01Initiated vote against %s (%s) "vote option%d" (%s)', playerName, playerInfo.SteamID, voteInt, dispStr))
        client.Command('say "Attention: ' .. playerName .. ' is suspected of Cheating. Vote F1."', true)
    elseif G.Menu.AutoVote.Enabled and ent0 ~= me and ent1 ~= me then --respond to vote field
        local voteInt = 2 -- Default vote is no
        local steamID = Common.GetSteamID64(ent1)

        -- Check if the target is a friend
        if G.Menu.AutoVote.intent.friend and Common.IsFriend(target) then
            voteInt = 2  -- Always vote no if the target is a friend
        else
            -- Check if the target is a cheater
            if G.Menu.AutoVote.intent.cheater and Common.IsCheater(steamID) then
                voteInt = 1  -- Vote yes if the target is a cheater
            end

            -- Check if the target is a bot
            if G.Menu.AutoVote.intent.bot and G.DataBase[steamID].Cause == "Bot" then
                voteInt = 1  -- Vote yes if the target is a bot
            end

            -- Manual intent override for legit players
            if G.Menu.AutoVote.intent.legit and not Common.IsCheater(steamID) and G.DataBase[steamID].Cause ~= "Bot" then
                voteInt = 1 -- Vote yes if intent is set to legit and the player is neither a cheater nor a bot
            end
        end

        client.Command(string.format('vote %d option%d', voteIdx, voteInt), true)
    end
end

-- Register and unregister callbacks for clean setup
callbacks.Unregister('DispatchUserMessage', 'AutoVoteCD_DispatchUserMessage') --unregister callbacks for clean setup
callbacks.Register('DispatchUserMessage', 'AutoVoteCD_DispatchUserMessage', handleUserMessageVoteStart) -- Register user messages hook will catch anynform of message besides vc

callbacks.Unregister("FireGameEvent", "CD_event_hook")                 -- unregister the "FireGameEvent" callback
callbacks.Register("FireGameEvent", "CD_event_hook", event_hook)         -- register the "FireGameEvent" callback

return EventHandler