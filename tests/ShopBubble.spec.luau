-- ShopBubble (the light Robux Shop window, pure builder) under Lune: the hero
-- offer and every row get a price button (OWNED when owned), touch sizes.
return function(T, Loader)
	local ShopBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ShopBubble")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

	local data = {
		Tab = "Passes",
		Hero = { Id = "Big", Name = "Big Pass", Description = "", Icon = "medal", Price = "560", Tag = "BEST VALUE", Perks = { "A", "B" } },
		Offers = {
			{ Id = "One", Name = "One", Description = "First", Icon = "podium", Price = "100" },
			{ Id = "Two", Name = "Two", Description = "Second", Icon = "moon", Price = "99", Owned = true },
		},
	}

	T.test("ShopBubble: a buy button per offer, OWNED for owned passes", function()
		for _, scale in { 1.25, 0.62 } do
			local refs = ShopBubble.build(UIKit.screen("Test"), scale, data)
			for _, tab in ShopBubble.Tabs do
				T.truthy(refs.Tabs[tab.Id], "tab " .. tab.Id)
			end
			T.eq((refs.Buy.Big:FindFirstChild("Label") :: any).Text, "560", "hero price")
			T.eq((refs.Buy.One:FindFirstChild("Label") :: any).Text, "100", "row price")
			T.eq((refs.Buy.Two:FindFirstChild("Label") :: any).Text, "OWNED", "owned pass")
			T.eq(refs.Buy.One:FindFirstChild("Icon"):GetAttribute("Icon"), "robux", "Roblox's Robux icon")
		end
	end)

	T.test("ShopBubble: phone buttons >= 44 pt", function()
		local layout = ShopBubble.layout(0.62)
		T.truthy(layout.Compact, "compact")
		T.truthy(layout.Tab.Y * 0.62 >= 44, "tabs")
		T.truthy(layout.Button * 0.62 >= 44, "buy buttons")
	end)
end
