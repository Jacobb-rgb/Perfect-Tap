-- BackpackBubble (the light Backpack window, pure builder) under Lune: a card
-- per item with its value, the selected one outlined, touch sizes on phones.
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3

return function(T, Loader)
	local BackpackBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BackpackBubble")
	local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

	local data = {
		Tab = "Ores",
		Items = {
			{ Id = "A", Name = "Clean Ruby", Icon = "item_Clean_Ruby", Color = Color3.new(0.2, 0.6, 1), Rarity = "Rare", Grade = "Clean", Value = "$4.8K" },
			{ Id = "B", Name = "Raw Copper", Icon = "item_Raw_Copper", Color = Color3.new(0.7, 0.7, 0.7), Rarity = "Common", Value = "?" },
		},
		Selected = "B",
		Coins = "$1",
		Shards = "2",
		Used = 2,
		Capacity = 40,
	}

	T.test("BackpackBubble: cards, values, selection and the action buttons", function()
		for _, scale in { 1.25, 0.62 } do
			local refs = BackpackBubble.build(UIKit.screen("Test"), scale, data)
			for _, tab in BackpackBubble.Tabs do
				T.truthy(refs.Tabs[tab.Id], "tab " .. tab.Id)
			end
			T.eq(refs.Cards.A:FindFirstChild("Chance", true):FindFirstChild("Text").Text, "$4.8K", "value chip")
			T.eq(refs.Cards.B:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Gold, "selected card")
			T.eq(refs.Cards.A:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Outline, "other cards plain")
			T.truthy(refs.Sell and refs.Podium and refs.Keep, "actions")
		end
	end)

	T.test("BackpackBubble: phone buttons >= 44 pt", function()
		local layout = BackpackBubble.layout(0.62)
		T.truthy(layout.Compact, "compact")
		T.truthy(layout.Tab.Y * 0.62 >= 44, "tabs")
		T.truthy(layout.Button * 0.62 >= 44, "action buttons")
		T.truthy(layout.Card.Y * 0.62 >= 44, "cards")
	end)
end
