local Globals = {}

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