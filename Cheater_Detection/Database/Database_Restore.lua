-- New module to handle database restoration between reloads

local Restore = {}

-- Check for preserved database in global memory
function Restore.CheckForDatabase()
	if
		_G._CheaterDetectionDatabaseBackup
		and _G._CheaterDetectionDatabaseBackup.data
		and type(_G._CheaterDetectionDatabaseBackup.data) == "table"
		and _G._CheaterDetectionDatabaseBackup.entriesCount
		and _G._CheaterDetectionDatabaseBackup.entriesCount > 0
	then
		return true
	end
	return false
end

-- Restore database into provided database object
function Restore.RestoreDatabase(database)
	if not database then
		return false
	end

	-- Check for backup
	if not Restore.CheckForDatabase() then
		return false
	end

	-- Copy database content directly
	database.data = _G._CheaterDetectionDatabaseBackup.data
	database.State = database.State or {}
	database.State.entriesCount = _G._CheaterDetectionDatabaseBackup.entriesCount
	database.State.lastSave = _G._CheaterDetectionDatabaseBackup.lastSave
	database.State.isDirty = false

	-- Clear backup to avoid memory waste
	_G._CheaterDetectionDatabaseBackup = nil

	printc(
		0,
		255,
		140,
		255,
		"[Database Restore] Successfully restored database with " .. database.State.entriesCount .. " entries"
	)

	return true
end

return Restore
