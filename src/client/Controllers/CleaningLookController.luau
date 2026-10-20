--[[
	Puts the store-card spray look (Cleaning/CardLook: DefaultLook plus flying
	dirt chunks, the green % CLEAN bar, the rarity-glow card and the NEW ORE
	DISCOVERED! banner) on the cleaning minigame (CleaningController.setLook).
]]

local CleaningController = require(script.Parent.CleaningController)
local CardLook = require(script.Parent.Parent.Cleaning.CardLook)

local CleaningLookController = {}

function CleaningLookController.init()
	CleaningController.setLook(CardLook)
end

function CleaningLookController.start() end

return CleaningLookController
