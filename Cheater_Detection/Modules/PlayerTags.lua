local PlayerTags = {}

--[[ Imports ]]
local Common = require("Cheater_Detection.Common")

local function handleUserMessageNametags(msg)
    if msg:GetID() ~= 4 then return end -- 4 is the ID for SayText2

    local bf = msg:GetBitBuffer()
    bf:SetCurBit(0)  -- Start from the beginning of the message

    -- Read and print all data from the message
    print("Reading SayText2 Message:")

    local dataBitsLength = bf:GetDataBitsLength()
    print("Data Bits Length:", dataBitsLength)

    while bf:GetCurBit() < dataBitsLength do
        local byteValue = bf:ReadByte()
        print(string.format("Byte Value: %02X", byteValue))
    end

    -- Reset the bit buffer for re-reading
    bf:SetCurBit(0)

    -- Read the known fields
    local team = bf:ReadByte()
    local playerIndex = bf:ReadByte()
    local dispStr = bf:ReadString(64)
    local detailsStr = bf:ReadString(64)

    -- Print all known fields to the console
    print("Team:", team)
    print("Player Index:", playerIndex)
    print("Display String:", dispStr)
    print("Details String:", detailsStr)

    -- Get player information
    local playerInfo = client.GetPlayerInfo(playerIndex)
    local steamID = playerInfo.SteamID
    local playerName = playerInfo.Name
    local message = detailsStr

    print("Player Name:", playerName)
    print("SteamID:", steamID)

    -- Modify the message if the player is a cheater
    if Common.IsCheater(steamID) then
        message = "[Cheater] " .. message
    end

    -- Write the modified message back into the bit buffer
    bf:SetCurBit(0)
    bf:WriteByte(team)
    bf:WriteByte(playerIndex)
    bf:WriteString(dispStr, 64)
    bf:WriteString(message, 64)

    -- Print the modified message to the console
    print("Modified Message:", message)
end


-- Register and unregister callbacks for clean setup
callbacks.Unregister('DispatchUserMessage', 'playertagsCD_DispatchUserMessage')
callbacks.Register('DispatchUserMessage', 'playertagsCD_DispatchUserMessage', handleUserMessageNametags)

return PlayerTags
