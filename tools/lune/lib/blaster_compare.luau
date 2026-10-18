--[[
	Preview scene "blaster_compare" (tools/lune/export_scene.luau): the ten
	blaster levels in their case ores, side by side, seen from their right
	side, in three rows:
	  top     BEFORE: the classic in-game guns (BlasterBuilder.buildClassic)
	  middle  AFTER: the owner-approved Kenney shapes as the game builds them
	          now (BlasterBuilder.build, Builders/KenneyBlaster: <= 90 parts)
	  bottom  the full preview prototype (tools/lune/lib/blaster_kenney.luau,
	          139-408 parts) the owner approved, for checking the light version
	Shots: tools/preview/blaster_compare_shots.json.
]]

local roblox = require("@lune/roblox") :: any

local Compare = {}

function Compare.build(Loader: any, parent: any, withPrototype: boolean?)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local Kenney = require("./blaster_kenney")
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterCompare"
	root.Parent = parent
	local rows = { "Classic", "Kenney" }
	if withPrototype then
		table.insert(rows, "Prototype")
	end
	-- a dark studio wall and floor
	Geo.block(root, CF.new(0, 0, -70), V3.new(300, 160, 1), C3.fromRGB(150, 156, 172))
	local counts = {}
	for r, kind in rows do
		for level = 1, BlasterData.MaxLevel do
			local ore = BlasterData.vaultOre(level)
			local model: any
			if kind == "Classic" then
				model = BlasterBuilder.buildClassic(level, ore)
			elseif kind == "Kenney" then
				model = BlasterBuilder.build(level, ore)
			else
				model = Kenney.gun(Loader, level, ore)
			end
			local parts = {}
			local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					table.insert(parts, d)
					local p = d.CFrame.Position
					lo = V3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
					hi = V3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
				end
			end
			local center = (lo + hi) / 2
			-- the prototype is in design studs (x1.2 smaller than held): show it at held size too
			local k = if kind == "Prototype" then 1.2 else 1
			local at = CF.new(-36 + (level - 1) * 8, 6 - (r - 1) * 6, 0) * CF.Angles(0, -math.pi / 2, 0)
			for _, d in parts do
				local rel = d.CFrame
				d.Size *= k
				d.CFrame = at * CF.new((rel.Position - center) * k) * rel.Rotation
				d.Anchored = true
				d.Parent = root
			end
			counts[kind .. level] = #parts
		end
	end
	return root, counts
end

return Compare
