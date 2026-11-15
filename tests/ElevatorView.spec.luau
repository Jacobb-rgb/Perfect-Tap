-- ElevatorView (what the elevator's screens share; the floor picker itself is ElevatorWindow,
-- tests/ElevatorWindow.spec) under Lune: the floors' colours and ore rarities, a word's width
-- and the void rescue's fade. (The side menu's ELEVATOR button is main's: tests/SideMenu.spec;
-- the Pop window pieces are the backpack shop's: tests/BackpackShop*.spec.)
return function(T, Loader)
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local ElevatorView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorView")

	T.test("ElevatorView: a colour per floor (the owner's: stone, ember, cyan, gold, violet, magenta)", function()
		local seen: { [string]: boolean } = {}
		for _, floor in MineFloors.List do
			local color = ElevatorView.floorColor(floor.Index)
			T.truthy(color ~= ElevatorView.SoonColor, floor.Name .. " has its own colour")
			local key =
				string.format("%d,%d,%d", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
			T.falsy(seen[key], floor.Name .. ": not another floor's")
			seen[key] = true
		end
		T.eq(ElevatorView.floorColor(MineFloors.ComingSoon.Index), ElevatorView.SoonColor, "coming soon: grey")
		T.eq(ElevatorView.floorColor(99), ElevatorView.SoonColor)
	end)

	T.test("ElevatorView: a floor's rarities come from its ores, rarest last", function()
		for _, floor in MineFloors.List do
			local list = ElevatorView.floorRarities(floor.Index)
			T.truthy(#list >= 1, floor.Name .. " has ores")
			local want: { [string]: boolean } = {}
			for _, weights in { floor.Ores, floor.CrystalOres } do
				for id in weights do
					if OreData.exists(id) then
						want[OreData.get(id).Rarity] = true
					end
				end
			end
			local last = 0
			for _, rarity in list do
				T.truthy(want[rarity], floor.Name .. ": " .. rarity .. " is one of its ores'")
				local at = table.find(ElevatorView.RarityOrder, rarity) or 0
				T.truthy(at > last, floor.Name .. ": in order")
				last = at
			end
		end
		T.eq(#ElevatorView.floorRarities(99), 0, "no such floor")
	end)

	T.test("ElevatorView: text widths (tables in Lune, the game's TextService when set)", function()
		T.truthy(ElevatorView.measure("GO", 24) > 20, "measures")
		T.near(ElevatorView.measure("ab", 100), ElevatorView.measure("a", 100) + ElevatorView.measure("b", 100), 1e-6, "adds up")
		T.truthy(ElevatorView.measure("ELEVATOR", 50, true) > 0, "title font")
		local saved = ElevatorView.Measure
		ElevatorView.Measure = function(text: string, size: number)
			return #text * size
		end
		T.eq(ElevatorView.measure("abc", 10), 30, "the game's measure wins")
		ElevatorView.Measure = function()
			error("no TextService")
		end
		T.truthy(ElevatorView.measure("abc", 10) > 0, "a failing measure falls back")
		ElevatorView.Measure = saved
	end)

	T.test("ElevatorView: the ride fade covers the screen and names the floor", function()
		local fade = ElevatorView.buildFade()
		T.falsy(fade.Gui.Enabled, "off until a ride")
		T.truthy(fade.Gui.IgnoreGuiInset, "covers the top bar too")
		T.eq(fade.Black.Size.X.Scale, 1, "full width")
		T.eq(fade.Black.Size.Y.Scale, 1, "full height")
		T.eq(fade.Black.BackgroundTransparency, 1, "clear at first")
		T.eq(fade.Gui:FindFirstChildOfClass("UIScale"), nil, "no UIScale (would shrink the black layer)")
		ElevatorView.setFadeText(fade, 4, MineFloors.get(4).Name)
		T.eq(fade.Title.Text, "FLOOR 4")
		T.eq(fade.Name.Text, MineFloors.get(4).Name)
	end)
end
