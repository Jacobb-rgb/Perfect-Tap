--[[
	The cleaning reveal as a frame strip (scene "cleaning_reveal_strip", shot
	in tools/preview/ore_shots.json): a Common ore (Coal) on the top row and a
	Mythic one (Heartstone Shard) below, four moments each, built with the same
	parts CleaningController plays (OreShellBuilder, RevealFx):
	  1 CLEANED  the dirt is washed off, the ore waits in the clump
	  2 REVEAL   the rarity burst (Mythic: 12 rays, a strong light)
	  3 SHINE    the ore rises and spins (Mythic in slow motion), the shine bar crosses it
	  4 STAMP    the grade stamp lands on the ore
]]

local roblox = require("@lune/roblox") :: any

local Strip = {}

Strip.Rows = {
	{ Ore = "Coal", Grade = "Clean" },
	{ Ore = "Heartstone", Grade = "Flawless" },
}
Strip.Frames = { "CLEANED", "REVEAL", "SHINE", "STAMP" }
Strip.Gap = 6.5 -- studs between frames
Strip.RowGap = 6

function Strip.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local NEON = roblox.Enum.Material.Neon
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
	local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.RevealFx")
	local root = roblox.Instance.new("Model")
	root.Name = "RevealStrip"
	root.Parent = parent
	-- a dark workbench backdrop
	Geo.block(root, CF.new(0, 5, -3), V3.new(60, 24, 1), C3.fromRGB(28, 24, 30))
	Geo.block(root, CF.new(0, -0.5, 4), V3.new(60, 1, 16), C3.fromRGB(46, 36, 32))
	-- a soft fill light from the camera side, like the workbench lamp
	local fill = Geo.ball(root, V3.new(-2, 9, 10), 0.1, C3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false })
	local lamp = roblox.Instance.new("PointLight")
	lamp.Range = 30
	lamp.Brightness = 1.2
	lamp.Color = C3.fromRGB(255, 236, 214)
	lamp.Parent = fill

	local function label(cf: any, width: number, text: string, color: any)
		local board = Geo.block(root, cf, V3.new(width, 0.6, 0.08), C3.fromRGB(18, 16, 22))
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = color
		textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.LuckiestGuy)
		textLabel.Parent = gui
	end

	for r, row in Strip.Rows do
		local ore = OreData.get(row.Ore)
		local rarity = Rarity.get(ore.Rarity)
		local order = rarity.Order
		local plan = RevealFx.plan(order)
		local grade = ItemData.GradeById[row.Grade]
		local y = 2.6 + (#Strip.Rows - r) * Strip.RowGap
		label(
			CF.new(-((#Strip.Frames + 1) / 2) * Strip.Gap + 0.6, y + 2.4, 0.5),
			4.6,
			string.upper(ore.Name) .. " · " .. string.upper(rarity.Name),
			rarity.Color
		)
		for f, frame in Strip.Frames do
			local x = (f - (#Strip.Frames + 1) / 2) * Strip.Gap
			local pos = V3.new(x, y, 0)
			-- the shell faces the camera (+Z); its LookVector points away
			local workCf = CF.lookAt(pos, pos + V3.new(0, 0, -1))
			local pattern = Patterns.generate(row.Ore, 4242)
			local shell = OreShellBuilder.build(pattern, workCf, root)
			for _, patch in shell.Dirt do
				patch:Destroy()
			end
			for _, part in shell.CoreRim do
				part.Transparency = if f >= 2 then 0.6 else 0
			end
			for _, part in shell.Core do
				part.Color = ore.Color
				part.Reflectance = 0.25
			end
			if r == 1 then
				label(CF.new(x, y + 3.4, 0.5), 3.4, frame, C3.fromRGB(255, 214, 120))
			end
			local center = workCf:PointToWorldSpace(V3.new(0, 0, OreShellBuilder.CoreFront))
			if f >= 2 then
				-- the ore's light
				local holder = Geo.ball(root, center, 0.1, ore.Glow, nil, { Transparency = 1, CanCollide = false })
				local light = roblox.Instance.new("PointLight")
				light.Color = ore.Glow
				light.Range = 8
				light.Brightness = if f == 2 then 6 + order else 2
				light.Parent = holder
			end
			if f == 2 then
				-- the burst caught growing, and the rays of a Legendary / Mythic
				Geo.ball(root, center + V3.new(0, 0, 0.3), 3.2, rarity.Color, NEON, { Transparency = 0.55, CanCollide = false })
				for i = 1, plan.Rays do
					local a = i / plan.Rays * math.pi * 2 + 0.4
					local dir = V3.new(math.cos(a), math.sin(a), 0.15)
					Geo.block(
						root,
						CF.lookAt(center + dir * 2.6, center + dir * 3.4),
						V3.new(0.12, 0.12, 4.2),
						rarity.Color,
						NEON,
						{ Transparency = 0.35, CanCollide = false }
					)
				end
			end
			if f >= 3 then
				-- the ore risen and turned (Mythic in slow motion: less turned at the same moment)
				local p = if f == 3 then 0.45 else 1
				local ease = 1 - (1 - RevealFx.warp(p, plan.SlowMo)) ^ 3
				local lift = 1 - (1 - math.min(1, p * 2.2)) ^ 2
				local pivot = workCf * CF.new(0, 0, OreShellBuilder.CoreFront - 0.4)
				local turn = pivot * CF.new(0, 0.2 * lift, 0.9 * lift) * CF.Angles(0, 0, ease * plan.Spins * math.pi * 2)
				local parts = {}
				for _, part in shell.Core do
					table.insert(parts, part)
				end
				for _, part in shell.CoreRim do
					table.insert(parts, part)
				end
				for _, part in parts do
					part.CFrame = turn * pivot:ToObjectSpace(part.CFrame)
				end
			end
			if f == 3 then
				local _, at = RevealFx.sweep(root, workCf, OreShellBuilder.CoreFront + 1.1, 1.5)
				at(0.5)
			elseif f == 4 then
				-- the game's stamp (a clear plate with a nested SurfaceGui), and a stand-in the
				-- preview renderer can draw at the same spot (it skips clear parts)
				local plate = RevealFx.stamp(root, workCf, OreShellBuilder.CoreFront + 1.2, grade.Name, grade.Color)
				Geo.block(
					root,
					plate.CFrame * CF.new(0, 0, 0.02),
					plate.Size + V3.new(0.12, 0.12, 0),
					grade.Color,
					NEON,
					{ CanCollide = false }
				)
				local board =
					Geo.block(root, plate.CFrame * CF.new(0, 0, -0.01), plate.Size, C3.fromRGB(20, 14, 12), nil, { CanCollide = false })
				local gui = roblox.Instance.new("SurfaceGui")
				gui.Face = roblox.Enum.NormalId.Front
				gui.LightInfluence = 0
				gui.Parent = board
				local text = roblox.Instance.new("TextLabel")
				text.Text = string.upper(grade.Name)
				text.TextColor3 = grade.Color
				text.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.LuckiestGuy)
				text.Parent = gui
			end
		end
	end
	print("Reveal strip: Coal (Common) and Heartstone Shard (Mythic), 4 moments each")
	return root
end

return Strip
