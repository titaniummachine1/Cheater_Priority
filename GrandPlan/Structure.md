# Project Structure

## Root Directory
```
/Cheater_Detection/
│── Main.lua
```

## Core Modules
```
/Cheater_Detection/core/
│── Detection_engine.lua
│── Evidence_system.lua
│── Player_monitor.lua
```

## Database Modules
```
/Cheater_Detection/database/
│── Database_manager.lua
│── Runtime_database.lua
│── Local_database.lua
│── Database_fetcher.lua
```

## Detection Methods
```
/Cheater_Detection/detection_methods/
│── silent_aimbot.lua      # Detects silent aimbot behavior
│── plain_aimbot.lua       # Detects obvious aimbot snapping
│── smooth_aimbot.lua      # Detects assisted aiming with smoothing
│── triggerbot.lua         # Detects automatic firing on enemies
│── bhop.lua               # Detects frame-perfect bunny hopping
│── strafe_bot.lua         # Detects automated strafe movements
│── anti_aim.lua           # Detects anti-aim desynchronization
│── warp_dt.lua            # Detects warping or double-tap abuse
│── warp_recharge.lua      # Detects artificial recharge mechanics
│── fake_lag.lua           # Detects lag switching or induced latency
```

## Miscellaneous Features
```
/Cheater_Detection/misc/
│── Vote_reveal.lua         # Reveals in-game vote results
│── Auto_vote.lua           # Automates voting actions
│── /Visuals/               # Subfolder for visual elements
│   │── Menu.lua            # UI menu using ImMenu
│   │── Cheater_tag.lua     # Displays "cheater" tags on flagged players
│   │── Loading_ring.lua    # Displays a loading indicator for processes
```

## Utility Modules
```
/Cheater_Detection/utils/
│── Config.lua
│── Common.lua
```

## External Libraries (Optional)
```
/Cheater_Detection/libs/
│── ImMenu.lua              # UI Library
│── LNX.lua                 # General Utility Library
│── json.lua              # JSON Parsing Library
```

## Unit Tests
```
/Cheater_Detection/unit_tests/
│── test_runner.lua          # Runs automated unit tests
│── core_tests.lua           # Tests core detection functionality
│── database_tests.lua       # Tests database operations
│── detection_tests.lua      # Tests individual detection modules
```