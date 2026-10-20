-- GolemsBubble (the light MY GOLEMS window, pure builder) under Lune: equipped
-- slots, "E" + lock marks on cards, the detail actions, phone sizes.
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3

return function(T, Loader)
	local GolemsBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemsBubble")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

	local function golem(id: string, equipped: boolean, locked: boolean)
		return {
			Id = id,
			Kind = "PebbleGolem",
			Name = "Pebble Golem",
			Rarity = "Common",
			Color = Color3.new(0.7, 0.7, 0.7),
			Bonus = "+3% Income",
			Short = "+3% INCOME",
			Lore = "Stones.",
			Equipped = equipped,
			Locked = locked,
		}
	end

	T.test("GolemsBubble: slots, marks and actions", function()
		local data = { Golems = { golem("A", true, true), golem("B", false, false) }, Selected = "A", Total = "+3% Income", Count = 2, Cap = 60 }
		for _, scale in { 1.25, 0.62 } do
			local refs = GolemsBubble.build(UIKit.screen("Test"), scale, data)
			T.eq(#refs.Slots, 3, "three equipped slots")
			T.truthy(refs.Slots[1]:FindFirstChild("Name"), "slot 1 shows the equipped golem")
			T.truthy(refs.Slots[2]:FindFirstChild("Empty"), "slot 2 empty")
			T.truthy(refs.Cards.A:FindFirstChild("Badge"), "E on the equipped golem")
			T.truthy(refs.Cards.A:FindFirstChild("CornerIcon"), "lock on the locked golem")
			T.falsy(refs.Cards.B:FindFirstChild("Badge"), "no E when not equipped")
			T.eq((refs.Unequip:FindFirstChild("Label") :: any).Text, "UNEQUIP", "equipped -> UNEQUIP")
			T.eq((refs.Lock:FindFirstChild("Label") :: any).Text, "UNLOCK", "locked -> UNLOCK")
		end
	end)

	T.test("GolemsBubble: phone buttons >= 44 pt", function()
		local layout = GolemsBubble.layout(0.62)
		T.truthy(layout.Compact, "compact")
		T.truthy(layout.Slot.Y * 0.62 >= 44, "slots")
		T.truthy(layout.Action.Y * 0.62 >= 44, "actions")
		T.truthy(layout.Button * 0.62 >= 44, "detail buttons")
	end)
end
