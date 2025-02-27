--[[
    ModuleDebugger - Tools to debug module loading issues
    Provides commands to test and diagnose module loading problems
]]

local ModuleDebugger = {}

-- Table to track loaded modules
ModuleDebugger.LoadedModules = {}

-- Test if a module can be loaded
function ModuleDebugger.TestModule(modulePath)
	print("Testing module: " .. modulePath)

	local startTime = globals.RealTime()
	local success, result = pcall(require, modulePath)
	local loadTime = globals.RealTime() - startTime

	if success then
		print(string.format("✓ %s loaded successfully (%.2fms)", modulePath, loadTime * 1000))

		-- Check what type of object was returned
		local resultType = type(result)
		print("  - Return type: " .. resultType)

		if resultType == "table" then
			-- Count methods and check for common functions
			local methodCount = 0
			local functions = {}

			for k, v in pairs(result) do
				if type(v) == "function" then
					methodCount = methodCount + 1
					table.insert(functions, k)

					if #functions <= 5 then -- Only show first 5 functions
						print("  - Function: " .. k)
					end
				end
			end

			if #functions > 5 then
				print("  - Plus " .. (#functions - 5) .. " more functions")
			end

			print(string.format("  - Total: %d methods", methodCount))
		end

		-- Store in loaded modules
		ModuleDebugger.LoadedModules[modulePath] = result
		return true, result
	else
		print(string.format("✗ %s failed to load: %s", modulePath, tostring(result)))
		return false, result
	end
end

-- Test a specific function in a module
function ModuleDebugger.TestFunction(modulePath, functionName)
	print(string.format("Testing function %s in %s", functionName, modulePath))

	local success, module = ModuleDebugger.TestModule(modulePath)
	if not success then
		return false, "Module failed to load"
	end

	if type(module) ~= "table" then
		return false, "Module is not a table but a " .. type(module)
	end

	local func = module[functionName]
	if type(func) ~= "function" then
		return false, "Function " .. functionName .. " not found or not a function (type: " .. type(func) .. ")"
	end

	print("✓ Function " .. functionName .. " exists in module")
	return true, func
end

-- Register debug commands
local function RegisterDebugCommands()
	local Common = require("Cheater_Detection.Utils.Common")
	local Commands = Common.Lib.Utils.Commands

	Commands.Register("cd_test_module", function(args)
		if #args < 1 then
			print("Usage: cd_test_module <module_path>")
			print("Example: cd_test_module Cheater_Detection.Database.Database_Fetcher.Parsers")
			return
		end

		local modulePath = args[1]
		ModuleDebugger.TestModule(modulePath)
	end, "Test if a module can be loaded and examine its contents")

	Commands.Register("cd_test_function", function(args)
		if #args < 2 then
			print("Usage: cd_test_function <module_path> <function_name>")
			print("Example: cd_test_function Cheater_Detection.Database.Database_Fetcher.Parsers Download")
			return
		end

		local modulePath = args[1]
		local functionName = args[2]
		ModuleDebugger.TestFunction(modulePath, functionName)
	end, "Test if a specific function exists in a module")
end

-- Register the debug commands
RegisterDebugCommands()

return ModuleDebugger
