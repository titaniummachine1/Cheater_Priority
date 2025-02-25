local Globals = {}

Globals.AutoVote = {
    Options = { 'Yes', 'No' },
    VoteCommand = 'vote',
    VoteIdx = nil,
    VoteValue = nil, -- Set this to 1 for yes, 2 for no, or nil for off
}

--[[Shared Varaibles]]

Globals.players = {}
Globals.pLocal = nil
Globals.WLocal = nil
Globals.latin = nil
Globals.latout = nil

Globals.Menu = require("Cheater_Detection.Utils.DefaultConfig")

return Globals