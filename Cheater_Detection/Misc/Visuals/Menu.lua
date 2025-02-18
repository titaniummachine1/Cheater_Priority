--[[ Imports ]]
local Common = require("Cheater_Detection.Common")
--local FileBrowser = require("Cheater_Detection.Modules.FileBrowser")
local G = require("Cheater_Detection.Globals")
local Config = require("Cheater_Detection.Config")

local Menu = {}

local Log = Common.Log
local Lib = Common.Lib
local Notify = Lib.UI.Notify
local Fonts = Lib.UI.Fonts
local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)

local ImMenu = Common.ImMenu



local function DrawMenu()

    ImMenu.BeginFrame(1)

    if G.Menu.Main.debug then
        draw.Color(255, 0, 0, 255)
        draw.SetFont(Fonts.Verdana)
        draw.Text(20, 120, "Debug Mode!!! Some Features Might malfunction")
    end

    if gui.IsMenuOpen() == true and ImMenu.Begin("Cheater Detection", true) then
        -- Tabs for different sections
        ImMenu.BeginFrame(1)
            local tabs = {"Main", "Visuals", "AutoVote"}
            G.Menu.currentTab = ImMenu.TabControl(tabs, G.Menu.currentTab)
        ImMenu.EndFrame()

        draw.SetFont(Fonts.Verdana)
        draw.Color(255, 255, 255, 255)

            -- Main Section
            if G.Menu.currentTab == 1 then
                local Main = G.Menu.Main

                -- Strike Limit Slider
                ImMenu.BeginFrame(1)
                    Main.StrikeLimit = ImMenu.Slider("Strikes Limit", Main.StrikeLimit, 4, 17)
                ImMenu.EndFrame()

                -- Aimbot FOV Slider
                ImMenu.BeginFrame(1)
                    Main.AimbotDetection.Enable = ImMenu.Checkbox("aimbot ", Main.AimbotDetection.Enable)
                    if Main.AimbotDetection.Enable == true then
                        Main.AimbotDetection.MAXfov = ImMenu.Slider("Aimbot Fov", Main.AimbotDetection.MAXfov, 1, 180)
                    end
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Main.WarpDetection.Enable = ImMenu.Checkbox("Warp Detection ",  Main.WarpDetection.Enable)
                    if Main.WarpDetection.Enable == true then
                        Main.WarpDetection.MinWarp = ImMenu.Slider("Min Warp ticks ", Main.WarpDetection.MinWarp, 2, 24)
                    end
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Main.ChokeDetection.Enable = ImMenu.Checkbox("Choke Detection ", Main.ChokeDetection.Enable)
                    if Main.ChokeDetection.Enable == true then
                        Main.ChokeDetection.MaxChoke = ImMenu.Slider("Max Packet Choke ", Main.ChokeDetection.MaxChoke, 7, 22)
                    end
                ImMenu.EndFrame()

                -- Enable_bhopcheck
                ImMenu.BeginFrame(1)
                    Main.BhopDetection.Enable = ImMenu.Checkbox("bhop    ", Main.BhopDetection.Enable)
                    if Main.BhopDetection.Enable == true then
                        Main.BhopDetection.MaxBhop = ImMenu.Slider("Max Bhops", Main.BhopDetection.MaxBhop, 2, 15)
                    end
                ImMenu.EndFrame()

                -- Menu
                ImMenu.BeginFrame(1)
                    Main.AntyAimDetection = ImMenu.Checkbox("Anty-Aim ", Main.AntyAimDetection)
                    Main.DuckSpeedDetection = ImMenu.Checkbox("Duck-Speed ", Main.DuckSpeedDetection)
                ImMenu.EndFrame()

                -- Menu
                ImMenu.BeginFrame(1)
                    Main.AutoMark = ImMenu.Checkbox("Auto Mark", Main.AutoMark)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Main.debug = ImMenu.Checkbox("Debug", Main.debug)
                ImMenu.EndFrame()

                G.Menu.Main = Main --update changes
            end

            -- Visuals Section
            if G.Menu.currentTab == 2 then
                ImMenu.BeginFrame(1)
                    G.Menu.Visuals.Cheater_Tags = ImMenu.Checkbox("Draw Tags", G.Menu.Visuals.Cheater_Tags)
                    G.Menu.Visuals.Chat_Prefix = ImMenu.Checkbox("Chat_Prefix", G.Menu.Visuals.Chat_Prefix)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    G.Menu.Visuals.partyCallaut = ImMenu.Checkbox("Party Callout", G.Menu.Visuals.partyCallaut)
                ImMenu.EndFrame()
            end

            --autovote
            if G.Menu.currentTab == 3 then
                --autovote
                ImMenu.BeginFrame(1)
                    G.Menu.AutoVote.Enable = ImMenu.Checkbox("AutoVote", G.Menu.AutoVote.Enable)
                    if G.Menu.AutoVote.Enable then
                        G.Menu.AutoVote.intent.cheater = ImMenu.Checkbox("Cheater", G.Menu.AutoVote.intent.cheater)
                        G.Menu.AutoVote.intent.legit = ImMenu.Checkbox("legit", G.Menu.AutoVote.intent.legit)
                    end
                ImMenu.EndFrame()

                --Vote Reveal
                ImMenu.BeginFrame(1)
                    G.Menu.AutoVote.Vote_Reveal.Enable = ImMenu.Checkbox("Vote Reveal" , G.Menu.AutoVote.Vote_Reveal.Enable)

                if G.Menu.AutoVote.Vote_Reveal.Enable then
                --Reveal options
                    G.Menu.AutoVote.Vote_Reveal.PartyChat = ImMenu.Checkbox("Party Chat", G.Menu.AutoVote.Vote_Reveal.PartyChat)
                    G.Menu.AutoVote.Vote_Reveal.Console = ImMenu.Checkbox("Console", G.Menu.AutoVote.Vote_Reveal.Console)
                end
                ImMenu.EndFrame()

                --Vote anouncer
                ImMenu.BeginFrame(1)
                    G.Menu.AutoVote.Vote_Anouncer = ImMenu.Checkbox("Vote Anouncer",  G.Menu.AutoVote.Vote_Anouncer)
                ImMenu.EndFrame()
            end

            --[[PlayerList Section
            if Menu.Tabs.PlayerList then
                ImMenu.Text("Name: [Player Name] | SteamID: [Steam ID] | Strikes: [Number of Strikes] | Cause: [Cause] | Date: [Date]")
                local maxCheatersToDisplay = 24
                local cheatersDisplayed = 0

                if RuntimeData then
                    for steamId, data in pairs(RuntimeData) do
                        if cheatersDisplayed >= maxCheatersToDisplay then
                            break
                        end

                        local entity = data.EntityData.entity
                        if entity and entity:IsValid() and Config.IsKnownCheater(steamId) then
                            ImMenu.BeginFrame(1)  -- Begin a new frame for each player

                            -- Display player information in a single row
                            local playerName = entity:GetName() or "N/A"
                            local strikes = Config.GetStrikes(steamId) or "N/A"
                            local cause = Config.GetCause(steamId) or "N/A"
                            local date = Config.GetDate(steamId) or "N/A"
                            ImMenu.Text(string.format("Name: %s | SteamID: %s | Strikes: %s | Cause: %s | Date: %s", playerName, steamId, strikes, cause, date))

                            -- Button to remove the player from the list
                            if ImMenu.Button("Remove " .. playerName .. "###" .. steamId) then
                                Config.RemovePlayer(steamId)
                            end

                            ImMenu.EndFrame(1)  -- End the frame for the current player
                            cheatersDisplayed = cheatersDisplayed + 1
                        end
                    end
                end
            end]]
            ImMenu.End()
        end
    end

--[[ Callbacks ]]
callbacks.Unregister("Draw", "CD_MENU")                                   -- unregister the "Draw" callback
callbacks.Register("Draw", "CD_MENU", DrawMenu)                              -- Register the "Draw" callback 

return Menu
