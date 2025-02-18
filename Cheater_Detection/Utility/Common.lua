---@diagnostic disable: duplicate-set-field, undefined-field
---@class Common
local Common = {}

-- Unload the module if it's already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

--------------------------------------------------------------------------------------
--Library loading--
--------------------------------------------------------------------------------------
--[[
-- Function to download content from a URL
local function downloadFile(url)
    local body = http.Get(url)
    if not body or body == "" then
        error("Failed to download file from " .. url)
    end
    return body
end
]]--

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
