local Default_Config = {
    currentTab = "Main",

    Main = {
        AutoMark = true,
        partyCallaut = true,
        Chat_Prefix = true,
        Cheater_Tags = true,
        JoinWarning = true,
        Class_Change_Reveal = {
            Enable = true,
            EnemyOnly = true,
            PartyChat = true,
            Console = true,
        },
    },

    Advanced = {
        Evicence_Tolerance = 5, --how many evidence more then average legit to mark as cheater 
        Choke = true, --fakelag
        Warp = true,
        Bhop = true,
        Aimbot = {
            enable = true,
            silent = true,
            plain = true,
            smooth = true,
        },
        triggerbot = true,
        AntyAim = true,
        DuckSpeed = true,
        Strafe_bot = true,

        debug = false,
    },

    Misc = {
        Autovote = true,
        intent = {
            legit = true,
            cheater = true,
            bot = true,
            friend = false,
        },
        Vote_Reveal = {
            Enable = true,
            TargetTeam = {
                MyTeam = true,
                enemyTeam = true,
            },
            PartyChat = true,
            Console = true,
        },
        Chat_notify = true,
    }
}

return Default_Config
