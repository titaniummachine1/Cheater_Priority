--[[
    ChunkedDB.lua
    A chunked database implementation to solve CUTIRBTree overflow issues
    by splitting large databases into multiple chunks
]]

local Common = require("Cheater_Detection.Utils.Common")
local Json = Common.Json

local ChunkedDB = {}

-- Configuration
ChunkedDB.Config = {
    ChunkSize = 2000,          -- Number of entries per chunk
    AutoSave = true,           -- Automatically save when modified
    SaveInterval = 30,         -- Seconds between auto-saves
    UseWeakReferences = true,  -- Use weak tables for chunk references
    DebugMode = false          -- Print debug information
}

-- Internal state
ChunkedDB.State = {
    chunks = {},               -- Array of database chunks
    chunkLookup = {},          -- Maps key hash to chunk index
    lastSave = 0,              -- Timestamp of last save
    totalEntries = 0,          -- Total number of entries across all chunks
    isDirty = false,           -- Whether database has unsaved changes
    loadedChunks = 0           -- Number of loaded chunks
}

-- Simple hashing function for keys
local function hashKey(key)
    if type(key) ~= "string" then
        key = tostring(key)
    end
    
    local hash = 0
    for i = 1, #key do
        hash = (hash * 31 + string.byte(key, i)) % 1000000007
    end
    return hash
end

-- Create a new chunk
local function createChunk()
    local chunk
    if ChunkedDB.Config.UseWeakReferences then
        -- Use weak table for chunk (keys aren't automatically held in memory)
        chunk = setmetatable({}, {__mode = "k"})
    else
        chunk = {}
    end
    return chunk
end

-- Initialize the database with chunks
function ChunkedDB.Initialize()
    ChunkedDB.State.chunks = {}
    ChunkedDB.State.chunkLookup = {}
    ChunkedDB.State.totalEntries = 0
    ChunkedDB.State.isDirty = false
    ChunkedDB.State.loadedChunks = 0
    
    -- Create first chunk
    table.insert(ChunkedDB.State.chunks, createChunk())
    
    if ChunkedDB.Config.DebugMode then
        print("[ChunkedDB] Initialized with chunk size: " .. ChunkedDB.Config.ChunkSize)
    end
    
    return ChunkedDB
end

-- Get the chunk index for a key
function ChunkedDB.GetChunkIndex(key)
    local hash = hashKey(key)
    local index = ChunkedDB.State.chunkLookup[hash]
    
    -- If we don't have an index yet, assign to the least populated chunk
    if not index then
        local leastCount = math.huge
        local leastIndex = 1
        
        for i, chunk in ipairs(ChunkedDB.State.chunks) do
            local count = 0
            for _ in pairs(chunk) do
                count = count + 1
            end
            
            if count < leastCount then
                leastCount = count
                leastIndex = i
            end
        end
        
        index = leastIndex
        
        -- If the chunk is full, create a new one
        if leastCount >= ChunkedDB.Config.ChunkSize then
            table.insert(ChunkedDB.State.chunks, createChunk())
            index = #ChunkedDB.State.chunks
            
            if ChunkedDB.Config.DebugMode then
                print("[ChunkedDB] Created new chunk #" .. index)
            end
        end
        
        ChunkedDB.State.chunkLookup[hash] = index
    end
    
    return index
end

-- Set a value in the database
function ChunkedDB.Set(key, value)
    -- Remove existing entry if it exists (might be in a different chunk)
    ChunkedDB.Remove(key)
    
    -- Get appropriate chunk
    local chunkIndex = ChunkedDB.GetChunkIndex(key)
    local chunk = ChunkedDB.State.chunks[chunkIndex]
    
    -- Add to chunk
    chunk[key] = value
    ChunkedDB.State.totalEntries = ChunkedDB.State.totalEntries + 1
    ChunkedDB.State.isDirty = true
    
    -- Auto-save if enabled
    if ChunkedDB.Config.AutoSave then
        local currentTime = os.time()
        if currentTime - ChunkedDB.State.lastSave >= ChunkedDB.Config.SaveInterval then
            ChunkedDB.SaveDatabase()
        end
    end
end

-- Get a value from the database
function ChunkedDB.Get(key)
    local hash = hashKey(key)
    local chunkIndex = ChunkedDB.State.chunkLookup[hash]
    
    if not chunkIndex then
        -- Search all chunks (slower fallback)
        for i, chunk in ipairs(ChunkedDB.State.chunks) do
            if chunk[key] then
                -- Update lookup table for faster future access
                ChunkedDB.State.chunkLookup[hash] = i
                return chunk[key]
            end
        end
        return nil
    end
    
    local chunk = ChunkedDB.State.chunks[chunkIndex]
    return chunk[key]
end

-- Remove a key from the database
function ChunkedDB.Remove(key)
    local hash = hashKey(key)
    local chunkIndex = ChunkedDB.State.chunkLookup[hash]
    
    if not chunkIndex then
        -- Search all chunks
        for i, chunk in ipairs(ChunkedDB.State.chunks) do
            if chunk[key] then
                chunk[key] = nil
                ChunkedDB.State.totalEntries = ChunkedDB.State.totalEntries - 1
                ChunkedDB.State.isDirty = true
                return true
            end
        end
        return false
    end
    
    local chunk = ChunkedDB.State.chunks[chunkIndex]
    if chunk[key] then
        chunk[key] = nil
        ChunkedDB.State.totalEntries = ChunkedDB.State.totalEntries - 1
        ChunkedDB.State.isDirty = true
        return true
    end
    
    return false
end

-- Check if a key exists
function ChunkedDB.Contains(key)
    return ChunkedDB.Get(key) ~= nil
end

-- Iterate through all key-value pairs
function ChunkedDB.Iterate()
    local chunkIndex = 1
    local chunk = ChunkedDB.State.chunks[chunkIndex]
    local currentIterator = pairs(chunk)
    local currentKey, currentValue = currentIterator(chunk, nil)
    
    return function()
        -- If we have a current key-value pair, return it
        if currentKey then
            local key, value = currentKey, currentValue
            currentKey, currentValue = currentIterator(chunk, currentKey)
            return key, value
        end
        
        -- Try to move to the next chunk
        chunkIndex = chunkIndex + 1
        if chunkIndex <= #ChunkedDB.State.chunks then
            chunk = ChunkedDB.State.chunks[chunkIndex]
            currentIterator = pairs(chunk)
            currentKey, currentValue = currentIterator(chunk, nil)
            
            if currentKey then
                local key, value = currentKey, currentValue
                currentKey, currentValue = currentIterator(chunk, currentKey)
                return key, value
            end
        end
        
        -- No more entries
        return nil
    end
end

-- Count all entries
function ChunkedDB.Count()
    return ChunkedDB.State.totalEntries
end

-- Get database stats
function ChunkedDB.GetStats()
    local chunkSizes = {}
    
    for i, chunk in ipairs(ChunkedDB.State.chunks) do
        local count = 0
        for _ in pairs(chunk) do
            count = count + 1
        end
        table.insert(chunkSizes, count)
    end
    
    return {
        totalEntries = ChunkedDB.State.totalEntries,
        chunks = #ChunkedDB.State.chunks,
        chunkSizes = chunkSizes,
        isDirty = ChunkedDB.State.isDirty,
        lastSave = ChunkedDB.State.lastSave,
        loadedChunks = ChunkedDB.State.loadedChunks
    }
end

-- Clear the database
function ChunkedDB.Clear()
    ChunkedDB.State.chunks = {createChunk()}
    ChunkedDB.State.chunkLookup = {}
    ChunkedDB.State.totalEntries = 0
    ChunkedDB.State.isDirty = true
end

-- Get file path for a chunk
local function getChunkPath(baseDir, index)
    return baseDir .. "/db_chunk_" .. index .. ".json"
end

-- Save the database to disk
function ChunkedDB.SaveDatabase(path)
    local baseDir = path or "Lua " .. GetScriptName():match("([^/\\]+)%.lua$"):gsub("%.lua$", "")
    
    -- Create directory if it doesn't exist
    local success, dirPath = filesystem.CreateDirectory(baseDir)
    if not success then
        print("[ChunkedDB] Failed to create directory: " .. tostring(dirPath))
        return false
    end
    
    -- Save metadata
    local metadata = {
        version = 1,
        chunkCount = #ChunkedDB.State.chunks,
        totalEntries = ChunkedDB.State.totalEntries,
        chunkSize = ChunkedDB.Config.ChunkSize,
        timestamp = os.time()
    }
    
    local metaFile = io.open(baseDir .. "/db_meta.json", "w")
    if not metaFile then
        print("[ChunkedDB] Failed to open metadata file for writing")
        return false
    end
    
    metaFile:write(Json.encode(metadata))
    metaFile:close()
    
    -- Save each chunk
    for i, chunk in ipairs(ChunkedDB.State.chunks) do
        local chunkData = {}
        for k, v in pairs(chunk) do
            chunkData[k] = v
        end
        
        local chunkFile = io.open(getChunkPath(baseDir, i), "w")
        if not chunkFile then
            print("[ChunkedDB] Failed to open chunk file for writing: " .. i)
            return false
        end
        
        chunkFile:write(Json.encode(chunkData))
        chunkFile:close()
    end
    
    ChunkedDB.State.isDirty = false
    ChunkedDB.State.lastSave = os.time()
    
    if ChunkedDB.Config.DebugMode then
        print("[ChunkedDB] Saved database with " .. ChunkedDB.State.totalEntries .. " entries across " .. 
              #ChunkedDB.State.chunks .. " chunks")
    end
    
    return true
end

-- Load the database from disk
function ChunkedDB.LoadDatabase(path)
    local baseDir = path or "Lua " .. GetScriptName():match("([^/\\]+)%.lua$"):gsub("%.lua$", "")
    
    -- Load metadata
    local metaFile = io.open(baseDir .. "/db_meta.json", "r")
    if not metaFile then
        print("[ChunkedDB] No metadata file found, initializing new database")
        ChunkedDB.Initialize()
        return false
    end
    
    local metaContent = metaFile:read("*a")
    metaFile:close()
    
    local metadata = Json.decode(metaContent)
    if not metadata or not metadata.chunkCount then
        print("[ChunkedDB] Invalid metadata")
        ChunkedDB.Initialize()
        return false
    end
    
    -- Reset the database
    ChunkedDB.Initialize()
    
    -- Load each chunk
    ChunkedDB.State.totalEntries = 0
    ChunkedDB.State.loadedChunks = 0
    
    for i = 1, metadata.chunkCount do
        local chunkPath = getChunkPath(baseDir, i)
        local chunkFile = io.open(chunkPath, "r")
        
        if chunkFile then
            local chunkContent = chunkFile:read("*a")
            chunkFile:close()
            
            local chunkData = Json.decode(chunkContent)
            if chunkData then
                local chunk = createChunk()
                
                -- Copy data to chunk
                for k, v in pairs(chunkData) do
                    chunk[k] = v
                    ChunkedDB.State.totalEntries = ChunkedDB.State.totalEntries + 1
                    
                    -- Update lookup table
                    ChunkedDB.State.chunkLookup[hashKey(k)] = i
                end
                
                ChunkedDB.State.chunks[i] = chunk
                ChunkedDB.State.loadedChunks = ChunkedDB.State.loadedChunks + 1
            end
        end
    end
    
    ChunkedDB.State.isDirty = false
    ChunkedDB.State.lastSave = os.time()
    
    if ChunkedDB.Config.DebugMode then
        print("[ChunkedDB] Loaded database with " .. ChunkedDB.State.totalEntries .. " entries across " .. 
              ChunkedDB.State.loadedChunks .. " chunks")
    end
    
    return true
end

-- Initialize the database
ChunkedDB.Initialize()

-- Auto-save on unload
callbacks.Register("Unload", function()
    if ChunkedDB.State.isDirty then
        ChunkedDB.SaveDatabase()
    end
end)

return ChunkedDB
