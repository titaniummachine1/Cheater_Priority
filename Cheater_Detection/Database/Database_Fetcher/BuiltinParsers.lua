--[[
    BuiltinParsers - Simplified parsers that don't depend on external modules
    Used as a fallback when the main Parsers module fails to load
]]

local BuiltinParsers = {}

-- Simple download function
function BuiltinParsers.Download(url)
	print("[BuiltinParsers] Downloading: " .. url)

	local success, content = pcall(function()
		return http.Get(url)
	end)

	if not success then
		print("[BuiltinParsers] Download failed: " .. tostring(content))
		return nil
	end

	if not content or #content == 0 then
		print("[BuiltinParsers] Empty response from: " .. url)
		return nil
	end

	return content
end

-- Basic raw list processor
function BuiltinParsers.ProcessRawList(content, database, sourceName, sourceCause)
	print("[BuiltinParsers] Processing raw list: " .. sourceName)

	if not content or not database or not sourceName or not sourceCause then
		print("[BuiltinParsers] Missing required parameters")
		return 0
	end

	local count = 0

	-- Process line by line to be memory efficient
	for line in content:gmatch("[^\r\n]+") do
		-- Clean and validate line
		line = line:match("^%s*(.-)%s*$") -- Trim whitespace

		-- Skip comments and empty lines
		if line ~= "" and not line:match("^#") and not line:match("^//") then
			-- Check if line is a valid SteamID64
			if line:match("^%d+$") and #line >= 15 and #line <= 20 then
				-- Add to database if not already present
				if not database.content[line] then
					database.content[line] = {
						Name = "Unknown",
						proof = sourceCause,
					}
					count = count + 1

					-- Try to add to player list
					pcall(function()
						playerlist.SetPriority(line, 10)
					end)
				end
			end
		end

		-- Yield occasionally to keep the game responsive
		if count % 500 == 0 then
			coroutine.yield()
		end
	end

	print("[BuiltinParsers] Added " .. count .. " entries from " .. sourceName)
	return count
end

-- Basic TF2DB processor
function BuiltinParsers.ProcessTF2DB(content, database, source)
	print("[BuiltinParsers] Processing TF2DB: " .. source.name)

	if not content or not database or not source then
		print("[BuiltinParsers] Missing required parameters")
		return 0
	end

	local count = 0

	-- Simple pattern matching for steamIDs
	local pattern = '"steamid"%s*:%s*"([^"]+)"'

	for steamId in content:gmatch(pattern) do
		-- Try to handle different formats
		local steamID64 = steamId

		-- Convert if needed
		if not steamId:match("^%d+$") or #steamId < 15 then
			pcall(function()
				steamID64 = steam.ToSteamID64(steamId)
			end)
		end

		-- Add valid IDs to database
		if steamID64 and steamID64:match("^%d+$") and #steamID64 >= 15 then
			if not database.content[steamID64] then
				database.content[steamID64] = {
					Name = "Unknown",
					proof = source.cause,
				}
				count = count + 1

				-- Try to add to player list
				pcall(function()
					playerlist.SetPriority(steamID64, 10)
				end)
			end
		end

		-- Yield occasionally to keep the game responsive
		if count % 500 == 0 then
			coroutine.yield()
		end
	end

	print("[BuiltinParsers] Added " .. count .. " entries from " .. source.name)
	return count
end

-- Generic source processor
function BuiltinParsers.ProcessSource(source, database)
	if not source or not database then
		return 0
	end

	-- Download content
	local content = BuiltinParsers.Download(source.url)
	if not content then
		return 0
	end

	-- Process based on parser type
	if source.parser == "raw" then
		return BuiltinParsers.ProcessRawList(content, database, source.name, source.cause)
	elseif source.parser == "tf2db" then
		return BuiltinParsers.ProcessTF2DB(content, database, source)
	else
		print("[BuiltinParsers] Unknown parser type: " .. tostring(source.parser))
		return 0
	end
end

return BuiltinParsers
