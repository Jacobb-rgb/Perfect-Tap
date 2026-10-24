-- Build mode's overlay (client Effects/GridOverlay): a plate's text tag comes and goes
-- (owner 2026-10-24: no words over the chutes unless a belt there is turned wrong).
return function(T, Loader)
	local GridOverlay = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GridOverlay")
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local Color3 = roblox.Color3

	T.test("GridOverlay: a tag over a plate, and untag takes it away (the plate stays)", function()
		GridOverlay.plate("ChuteTest", CF.new(0, 0, 0), 4, 4)
		GridOverlay.tag("ChuteTest", "PEN: TURN THE BELT", Color3.new(1, 0, 0))
		local plate = GridOverlay.folder():FindFirstChild("Plate_ChuteTest")
		T.truthy(plate, "the plate")
		local tag = plate:FindFirstChild("Tag")
		T.truthy(tag, "the tag")
		T.eq(tag.Text.Text, "PEN: TURN THE BELT")
		GridOverlay.untag("ChuteTest")
		T.eq(plate:FindFirstChild("Tag"), nil, "the words are gone")
		T.truthy(plate.Parent, "the plate is still shown")
		GridOverlay.untag("ChuteTest") -- twice is fine
		GridOverlay.untag("Nope") -- an unknown plate too
		GridOverlay.tag("ChuteTest", "TRAIN: TURN THE BELT", Color3.new(1, 0, 0))
		T.eq(plate:FindFirstChild("Tag").Text.Text, "TRAIN: TURN THE BELT", "a tag can come back")
		GridOverlay.hidePlate("ChuteTest")
	end)
end
