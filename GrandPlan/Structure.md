# Project Structure

## Root Directory
```
/cheat_detection/
│── main.lua
│── config.json
```

## Core Modules
```
/cheat_detection/core/
│── detection_engine.lua
│── evidence_system.lua
│── player_monitor.lua
```

## Database Modules
```
/cheat_detection/database/
│── database_manager.lua
│── runtime_database.lua
│── local_database.lua
│── database_fetcher.lua
```

## Detection Methods
```
/cheat_detection/detection_methods/
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
/cheat_detection/misc/
│── vote_reveal.lua         # Reveals in-game vote results
│── auto_vote.lua           # Automates voting actions
│── /visuals/               # Subfolder for visual elements
│   │── menu.lua            # UI menu using ImMenu
│   │── cheater_tag.lua     # Displays "cheater" tags on flagged players
│   │── loading_ring.lua    # Displays a loading indicator for processes
```

## Utility Modules
```
/cheat_detection/utils/
│── logger.lua
│── config.lua
│── helpers.lua
│── performance.lua
```

## External Libraries (Optional)
```
/cheat_detection/libs/
│── ImMenu.lua              # UI Library
│── LNX.lua                 # General Utility Library
│── json.lua              # JSON Parsing Library
```

## Unit Tests
```
/cheat_detection/unit_tests/
│── test_runner.lua          # Runs automated unit tests
│── core_tests.lua           # Tests core detection functionality
│── database_tests.lua       # Tests database operations
│── detection_tests.lua      # Tests individual detection modules
```