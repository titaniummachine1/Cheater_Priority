local Database_import = {}

local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json

-- Utility function to trim whitespace from both ends of a string
local function trim(s)
    return s:match('^%s*(.-)%s*$') or ''
end

-- Enhance data update checking and handling
function Database_import.updateDatabase(steamID64, playerData, Database)
    local existingData = Database.content[steamID64]
    if existingData then
        -- Only update fields if they are not nil
        if playerData.Name and playerData.Name ~= "Unknown" then
            existingData.Name = playerData.Name
        end
        if playerData.proof then
            existingData.proof = playerData.proof
        end
        if playerData.date then
            existingData.date = playerData.date
        end
    else
        playerlist.SetPriority(steamID64, 10)
        Database.content[steamID64] = playerData
    end

    return Database
end

-- Function to process raw ID data, handling SteamID64 and SteamID formats
function Database_import.processRawIDs(content, Database)
    local date = os.date("%Y-%m-%d %H:%M:%S")
    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if not line:match("^%-%-") then  -- Skip comment lines
            local steamID64
            if line:match("^%d+$") then
                steamID64 = line
            elseif line:match("STEAM_0:%d:%d+") then
                steamID64 = steam.ToSteamID64(line)
            elseif line:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(line)
            end
            if steamID64 then
                Database_import.updateDatabase(steamID64, {
                    Name = "Unknown",
                    proof = "Known Cheater",
                    date = date,
                },
                Database)
            end
        end
    end
end

-- Process each item in the imported data
function Database_import.processImportedData(data, Database)
    if data and data.players then
        for _, player in ipairs(data.players) do
            local steamID64
            local playerName = player.last_seen.player_name or "Unknown"

            -- Set the name to "NN" if it is empty or too short
            if not playerName or playerName == "" or #playerName < 3 then
                playerName = "Unknown"
            end

            local playerDetails = {
                Name = playerName,
                proof = (player.attributes and table.concat(player.attributes, ", ")) or "Known Cheater",
                date = os.date("%Y-%m-%d %H:%M:%S", player.last_seen.time)
            }

            if player.steamid:match("^%[U:1:%d+%]$") then
                steamID64 = steam.ToSteamID64(player.steamid)
            elseif player.steamid:match("^%d+$") then
                local steam3 = Common.FromSteamid32To64(player.steamid)
                steamID64 = steam.ToSteamID64(steam3)
            else
                steamID64 = player.steamid  -- Already SteamID64
            end

            Database_import.updateDatabase(steamID64, playerDetails, Database)
        end
    end
end

-- Simplify file handling using a utility function
function Database_import.readFromFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Import and process database files
function Database_import.importDatabase(Database)
    local baseFilePath = Database_import.GetFilePath():gsub("database.json", "")  -- Ensure the correct base path
    local importPath = baseFilePath .. "/import/"

    -- Ensure the import directory exists
    filesystem.CreateDirectory(importPath)

    -- Enumerate all files in the import directory
    filesystem.EnumerateDirectory(importPath .. "/*", function(filename, attributes)
        local fullPath = importPath .. filename
        local content = Database_import.readFromFile(fullPath)
        if content then
            if Common.isJson(content) then
                local data, err = Json.decode(content)
                if data then
                    Database_import.processImportedData(data, Database)
                else
                    print("Error decoding JSON from file:", err)
                end
            else
                Database_import.processRawIDs(content, Database)
            end
        end
    end)
end

return Database_import