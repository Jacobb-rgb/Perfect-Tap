-- OpeningBubble (capsule reveal overlay, pure builder) under Lune: single and
-- x10 reveals build with their buttons, NEW marks and the best card.
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3

return function(T, Loader)
	local OpeningBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.OpeningBubble")
	local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

	local function golem(id: string, new: boolean, best: boolean)
		return { Id = id, Kind = "PebbleGolem", Name = "Pebble Golem", Rarity = "Common", Color = Color3.new(0.7, 0.7, 0.7), Bonus = "+3% Income", New = new, Best = best }
	end

	T.test("OpeningBubble: single and multi reveals", function()
		for _, scale in { 1.25, 0.62 } do
			local one = OpeningBubble.single(UIKit.screen("A"), scale, { Golems = { golem("A", true, false) }, Again = "OPEN 1 AGAIN", Price = "$1", Currency = "Coins", Lucky = true })
			T.truthy(one.Ok and one.Again, "buttons")
			local many = {}
			for i = 1, 10 do
				table.insert(many, golem("G" .. i, i == 3, i == 5))
			end
			local ten = OpeningBubble.multi(UIKit.screen("B"), scale, { Golems = many, Again = "OPEN 10 AGAIN", Price = "$9", Currency = "Coins" })
			T.truthy(ten.Cards.G3:FindFirstChild("Badge"), "NEW mark")
			T.falsy(ten.Cards.G4:FindFirstChild("Badge"), "no mark on known golems")
			T.eq(ten.Cards.G5:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Gold, "the best golem in gold")
		end
	end)
end
