PlayerData = {}

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

return playerData
