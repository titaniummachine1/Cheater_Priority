local Common = require("Cheater_Detection.Utils.Common")
local Commands = Common.Lib.Utils.Commands
local Database = require("Cheater_Detection.Database.Database")
local ChunkedDB = require("Cheater_Detection.Database.ChunkedDB")

-- Register database commands
Commands.Register("cd_db_info", function()
    local stats = Database.GetStats()
    printc(100, 255, 255, 255, "======= Database Statistics =======")
    printc(255, 255, 255, 255, string.format("Total entries: %d", stats.totalEntries))
    printc(255, 255, 255, 255, string.format("Chunk count: %d", stats.chunks))
    printc(255, 255, 255, 255, string.format("Last saved: %s", os.date("%Y-%m-%d %H:%M:%S", stats.lastSave)))
    printc(255, 255, 255, 255, "Entries by type:")
    
    -- Sort causes by count
    local causes = {}
    for cause, count in pairs(stats.causeBreakdown) do
        table.insert(causes, {name = cause, count = count})
    end
    table.sort(causes, function(a, b) return a.count > b.count end)
    
    -- Print top 10 causes
    for i = 1, math.min(10, #causes) do
        local cause = causes[i]
        printc(200, 255, 200, 255, string.format("  - %s: %d", cause.name, cause.count))
    end
    
    -- Print memory usage
    local memInfo = collectgarbage("count")
    printc(255, 255, 200, 255, string.format("Lua memory usage: %.2f KB", memInfo))
end, "Show detailed database statistics")

Commands.Register("cd_db_optimize", function()
    local beforeStats = ChunkedDB.GetStats()
    printc(255, 255, 0, 255, "Optimizing database...")
    
    -- Create new instance with optimized storage
    local tempChunkedDB = require("Cheater_Detection.Database.ChunkedDB")
    tempChunkedDB.Config.ChunkSize = beforeStats.totalEntries / math.max(1, math.floor(beforeStats.totalEntries / 3000))
    
    -- Transfer all entries to temporary database
    for k, v in ChunkedDB.Iterate() do
        tempChunkedDB.Set(k, v)
    end
    
    -- Save and reload
    tempChunkedDB.SaveDatabase(Database.GetFilePath())
    ChunkedDB.Clear()
    ChunkedDB.LoadDatabase(Database.GetFilePath())
    
    local afterStats = ChunkedDB.GetStats()
    printc(0, 255, 0, 255, string.format("Database optimized: %d entries in %d chunks (was %d chunks)",
        afterStats.totalEntries, afterStats.chunks, beforeStats.chunks))
end, "Optimize the database structure")

-- Register command to safely remove problematic entries
Commands.Register("cd_db_cleanup", function()
    local beforeCount = ChunkedDB.Count()
    local removed = 0
    
    for k, v in ChunkedDB.Iterate() do
        -- Remove problematic entries (invalid format, missing required fields, etc.)
        if type(v) ~= "table" or not v.cause then
            ChunkedDB.Remove(k)
            removed = removed + 1
        end
    end
    
    Database.SaveDatabase()
    printc(0, 255, 0, 255, string.format("Database cleaned: Removed %d problematic entries", removed))
end, "Remove problematic database entries")

return {
    -- Export any functions you want to expose
}
