local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json

local LocalDB = {}

function LocalDB.GetFilePath()
    local script_name = GetScriptName():match("([^/\\]+)%.lua$")
    local folder_name = string.format([[Lua %s]], script_name)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    return tostring(fullPath .. "/database.json")
end

function LocalDB.Save(database)
    local filepath = LocalDB.GetFilePath()
    -- Create backup
    local backupPath = filepath .. ".bak"
    pcall(os.rename, filepath, backupPath)

    local status, file = pcall(io.open, filepath, "w")
    if status and file then
        local serializedDB = Json.encode(database)
        if serializedDB then
            file:write(serializedDB)
            file:close()
            return true
        end
        file:close()
    end
    return false
end

function LocalDB.Load()
    local filepath = LocalDB.GetFilePath()
    local status, file = pcall(io.open, filepath, "r")
    if status and file then
        local content = file:read("*a")
        file:close()
        local database = Json.decode(content)
        if database then
            return database
        end
    end
    return {}
end

return LocalDB
