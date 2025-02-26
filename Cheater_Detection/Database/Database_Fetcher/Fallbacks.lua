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
