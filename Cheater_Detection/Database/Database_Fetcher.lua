local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json

local Fetcher = {}

function Fetcher.FetchFromURL(url)
    local response = http.Get(url)
    if response then
        local data = Json.decode(response)
        if data then
            return data
        end
    end
    return nil
end

function Fetcher.ProcessImportFolder(basePath)
    local imports = {}
    filesystem.EnumerateDirectory(basePath .. "/import/*", function(filename)
        local path = basePath .. "/import/" .. filename
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            
            if Common.isJson(content) then
                local data = Json.decode(content)
                if data then
                    table.insert(imports, data)
                end
            end
        end
    end)
    return imports
end

return Fetcher
