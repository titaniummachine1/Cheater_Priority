local Globals = {}

--[[ Annotations ]]
--- @alias TickData { Angle: EulerAngles, Position: Vector3, SimTime: number }
--- @alias PlayerHistory { Ticks: TickData[] }
--- @alias PlayerCurrent { Angle: EulerAngles, Position: Vector3, SimTime: number }
--- @alias PlayerState { Strikes: number, IsCheater: boolean }
--- @alias Globals.PlayerData table<number, { Entity: any, History: PlayerHistory, Current: PlayerCurrent, Info: PlayerState }>
Globals.DefaultPlayerData = {
    Entity = nil,
        info = {
            Name = "NN",
            Cause = "None",
            Date = os.date("%Y-%m-%d %H:%M:%S"),
            Strikes = 0,
            IsCheater = false,
            LastStrike = globals.TickCount(),
            bhop = 0,
            LastOnGround = true,
            LastVelocity = Vector3(0,0,0),
            Class = 2,
        },

        Current = {
            Angle = EulerAngles(0,0,0),
            Hitboxes = {
                Head = Vector3(0,0,0),
                Body = Vector3(0,0,0),
            },
            SimTime = 0,
            onGround = true,
            FiredGun = 0,
        },

        History = {
            {
                Angle = EulerAngles(0,0,0),
                Hitboxes = {
                    Head = Vector3(0,0,0),
                    Body = Vector3(0,0,0),
                },
                SimTime = 0,
                onGround = true,
                StdDev = 1,
                FiredGun = 0,
            },
        },
}

Globals.PlayerData = {}
Globals.AutoVote = {
    Options = { 'Yes', 'No' },
    VoteCommand = 'vote',
    VoteIdx = nil,
    VoteValue = nil, -- Set this to 1 for yes, 2 for no, or nil for off
}

--[[Shared Varaibles]]
Globals.DataBase = {}

Globals.players = {}
Globals.pLocal = nil
Globals.WLocal = nil
Globals.latin = nil
Globals.latout = nil

Globals.defaultRecord = {
    Name = "NN",
    Cause = "Known Cheater",
    Date = os.date("%Y-%m-%d %H:%M:%S"),
}

Globals.Menu = require("Cheater_Detection.Utils.DefaultConfig")

return Globals