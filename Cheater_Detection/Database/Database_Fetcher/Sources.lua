-- Source definitions for database fetching

local Sources = {}

-- List of available sources
Sources.List = {
    {
        name = "bots.tf",
        url = "http://api.bots.tf/rawtext",
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
