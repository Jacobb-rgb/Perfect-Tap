-- The bright window style's text helpers (Config/BrightTheme): the odds a card and the egg opening show.
return function(T, Loader)
	local BrightTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BrightTheme")

	T.test("BrightTheme: odds cards say a short percentage, and 1 in N for the rarest", function()
		T.eq(BrightTheme.chanceText(0.4633), "46.33%")
		T.eq(BrightTheme.chanceText(0.3), "30%")
		T.eq(BrightTheme.chanceText(0.065), "6.5%")
		T.eq(BrightTheme.chanceText(0.07), "7%", "no float noise")
		T.eq(BrightTheme.chanceText(0.025), "2.5%")
		T.eq(BrightTheme.chanceText(0.001), "0.1%", "0.1 % is still a percentage")
		T.eq(BrightTheme.chanceText(0.0007), "1 in 1,429")
		T.eq(BrightTheme.chanceText(0.0003), "1 in 3,333")
		T.eq(BrightTheme.chanceText(1), "100%")
		T.eq(BrightTheme.chanceText(0), "-")
	end)

	T.test("BrightTheme: the opening says 1 in N under every golem", function()
		T.eq(BrightTheme.oneInText(0.4633), "1 in 2")
		T.eq(BrightTheme.oneInText(0.3), "1 in 3")
		T.eq(BrightTheme.oneInText(0.17), "1 in 6")
		T.eq(BrightTheme.oneInText(0.065), "1 in 15")
		T.eq(BrightTheme.oneInText(1 / 25000), "1 in 25,000")
		T.eq(BrightTheme.oneInText(1e-6), "1 in 1,000,000")
		T.eq(BrightTheme.oneInText(1), "1 in 1")
		T.eq(BrightTheme.oneInText(0), "-")
	end)

	T.test("BrightTheme: every rarity has a card paint and a crack colour", function()
		for _, id in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Nope" } do
			local paint = BrightTheme.rarityPaint(id)
			T.truthy(paint.Top and paint.Bottom and paint.Edge, id)
			T.truthy(BrightTheme.crackColour(id), id)
		end
	end)
end
