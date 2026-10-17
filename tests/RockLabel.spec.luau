-- The name + HP label over mine rocks (client UI builder).
return function(T, Loader)
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockLabel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RockLabel")

	T.test("RockLabel: name, HP and a full bar, hidden beyond 45 studs and behind walls", function()
		local hp = MineFloors.rockHealth(1, "Small")
		local refs = RockLabel.build(MineFloors.rockName(1, "Small"), MineFloors.labelColor(1, "Small"), hp, 4)
		T.eq(refs.Name.Text, "Greystone", "name")
		T.eq(refs.Hp.Text, hp .. " HP", "hp text")
		T.eq(refs.Fill.Size.X.Scale, 1, "full bar")
		T.eq(refs.Gui.MaxDistance, 45, "max distance")
		T.eq(refs.Gui.AlwaysOnTop, false, "not through walls")
		T.near(refs.Gui.StudsOffset.Y, 5.4, 1e-3, "above the rock")
	end)

	T.test("RockLabel: set shows damage, clamps, and Lv N for locked rocks", function()
		local refs = RockLabel.build("Basalt", MineFloors.labelColor(2, "Small"), 80, 4)
		RockLabel.set(refs, 20, 80)
		T.eq(refs.Hp.Text, "20 HP", "hp after damage")
		T.near(refs.Fill.Size.X.Scale, 0.25, 1e-6, "quarter bar")
		RockLabel.set(refs, -5, 80)
		T.eq(refs.Hp.Text, "0 HP", "never negative")
		RockLabel.set(refs, 80, 80, 5)
		T.eq(refs.Hp.Text, "Lv 5", "locked")
		T.eq(refs.Hp.TextColor3, Theme.Bad, "locked in red")
		RockLabel.set(refs, 12345, 20000)
		T.eq(refs.Hp.Text, "12.3K HP", "big numbers shortened")
	end)

	T.test("RockLabel: names and colors for every floor and kind", function()
		for _, floor in MineFloors.List do
			for _, kind in { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" } do
				local name = MineFloors.rockName(floor.Index, kind)
				T.truthy(#name > 0 and #name <= 22, floor.Id .. " " .. kind .. " name fits: " .. name)
				T.truthy(MineFloors.labelColor(floor.Index, kind) ~= nil, floor.Id .. " " .. kind .. " color")
			end
		end
		T.eq(MineFloors.rockName(2, "Big"), "Basalt Boulder", "big rock name")
		T.eq(MineFloors.rockName(3, "Crystal"), "Azure Shard", "crystal name")
	end)
end
