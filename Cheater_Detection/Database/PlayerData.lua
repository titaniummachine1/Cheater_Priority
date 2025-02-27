PlayerData = {}

--[[ Annotations ]]
--- @alias TickData { Angle: EulerAngles, Position: Vector3, SimTime: number }
--- @alias PlayerHistory { Ticks: TickData[] }
--- @alias PlayerCurrent { Angle: EulerAngles, Position: Vector3, SimTime: number }
--- @alias PlayerState { Strikes: number, IsCheater: boolean }
--- @alias Globals.PlayerData table<number, { Entity: any, History: PlayerHistory, Current: PlayerCurrent, Info: PlayerState }>
PlayerData.DefaultPlayerData = {
	Entity = nil,
	info = {
		Name = "NN",
		Proof = "None",
		Date = os.date("%Y-%m-%d %H:%M:%S"),
		Strikes = 0,
		IsCheater = false,
		LastStrike = globals.TickCount(),
		bhop = 0,
		LastOnGround = true,
		LastVelocity = Vector3(0, 0, 0),
		Class = 0,
	},

	Current = {
		Angle = EulerAngles(0, 0, 0),
		Hitboxes = {
			Head = Vector3(0, 0, 0),
			Body = Vector3(0, 0, 0),
		},
		SimTime = 0,
		onGround = true,
		FiredGun = false,
	},

	History = {
		{
			Angle = EulerAngles(0, 0, 0),
			Hitboxes = {
				Head = Vector3(0, 0, 0),
				Body = Vector3(0, 0, 0),
			},
			SimTime = 0,
			onGround = true,
			StdDev = 1,
			FiredGun = false,
		},
	},
}

PlayerData.defaultRecord = {
	Name = "NN",
	Cause = "Known Cheater",
	Date = os.date("%Y-%m-%d %H:%M:%S"),
}

return playerData
