--[[
	Preview for the owner's decision (NOT in the game): the relic-cleaning flow
	with the real artifact and museum builders. Scene "relic_flow", shots
	relic_1..relic_4 in tools/preview/relic_flow_shots.json:
	  1 a broken rock, a DUSTY relic popping out of the rubble
	  2 the relic in the Cleaning Station's vise, half scrubbed (hand cleaning)
	  3 the Restoration Table cleaning one on its own (lamp on, sparkles)
	  4 the cleaned relic in the yard museum (MuseumBuilder.show)
]]

local roblox = require("@lune/roblox") :: any

local Flow = {}

Flow.Relic = "EmberCrown"
Flow.Spacing = 60 -- studs between the vignettes (x)
Flow.Dust = { roblox.Color3.fromRGB(122, 106, 92), roblox.Color3.fromRGB(146, 128, 108), roblox.Color3.fromRGB(92, 78, 66) }

-- Paints a relic dusty: every part (or every part for which `which` says yes)
-- goes to a crust colour, no glow, no light.
local function dusty(model: any, which: ((any, number) -> boolean)?)
	local i = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			i += 1
			if not which or which(d, i) then
				d.Color = Flow.Dust[(i % #Flow.Dust) + 1]:Lerp(d.Color, 0.15)
				d.Material = roblox.Enum.Material.Slate
			end
		elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") then
			if not which then
				d:Destroy()
			end
		end
	end
end

function Flow.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local NEON = roblox.Enum.Material.Neon
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local ArtifactBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ArtifactBuilder")
	local MuseumBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MuseumBuilder")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local Old = require("./machines_gallery")
	local root = roblox.Instance.new("Model")
	root.Name = "RelicFlow"
	root.Parent = parent
	Geo.block(root, CF.new(90, -0.5, 0), V3.new(320, 1, 160), C3.fromRGB(122, 178, 78))

	-- 1 the broken rock and the dusty relic over the rubble
	do
		local center = V3.new(0, 0, 0)
		Geo.block(root, CF.new(0, -0.45, 0), V3.new(22, 1, 22), C3.fromRGB(150, 128, 100))
		local rock = OreNodeBuilder.buildRock("Quarry", { "Copper", "Gold" }, CF.new(center), 11)
		rock.Parent = root
		local rng = Rng.new("shatter")
		local i = 0
		for _, part in rock:GetChildren() do
			if part:IsA("BasePart") then
				if part.Name == "Crack" or part.Name == "Moss" then
					part:Destroy()
				else
					i += 1
					local angle = i * 2.39996 + rng:range(-0.3, 0.3)
					local reach = rng:range(1.4, 3.4)
					local size = part.Size * 0.5
					part.Size = size
					part.CFrame = CF.new(center + V3.new(math.cos(angle) * reach, size.Y / 2 - 0.1, math.sin(angle) * reach))
						* CF.Angles(rng:range(-0.5, 0.5), rng:range(0, 6.28), rng:range(-0.5, 0.5))
				end
			end
		end
		local lift = center + V3.new(0, 3.2, 0)
		local relic = ArtifactBuilder.build(Flow.Relic, CF.new(lift) * CF.Angles(0.15, 2.6, 0.2), 1.6, true)
		if relic then
			dusty(relic)
			relic.Parent = root
		end
		-- a puff of dust round it
		for k = 1, 10 do
			local a = k * 2.39996
			local r = 1.1 + (k % 3) * 0.5
			Geo.ball(
				root,
				lift + V3.new(math.cos(a) * r, -0.6 + (k % 4) * 0.4, math.sin(a) * r),
				0.35 + (k % 3) * 0.15,
				Flow.Dust[(k % 3) + 1],
				nil,
				{ Transparency = 0.35, CanCollide = false }
			)
		end
	end

	-- 2 the Cleaning Station with the relic in its vise, half scrubbed
	do
		local x = Flow.Spacing
		local station = KitMachines.build("CleaningStation", 0)
		station:PivotTo(CF.new(x, 0, 0))
		station.Parent = root
		Old.paintGuis(Loader, root, station)
		local base = station.PrimaryPart
		local point = base.CFrame * base:FindFirstChild("OrePoint").CFrame
		local relic = ArtifactBuilder.build(Flow.Relic, CF.new(point.Position) * CF.Angles(0, math.pi, 0), 1.3)
		if relic then
			-- the left half still dusty, the right half scrubbed clean
			local center = point.Position
			dusty(relic, function(part: any, _i: number): boolean
				return part.CFrame.Position.X > center.X
			end)
			relic.Parent = root
			-- the brush in the scrubbed half and the dust it lifts
			local tip = center + V3.new(-0.4, 0.9, -0.5)
			for k = -1, 1 do
				Geo.block(root, CF.new(tip + V3.new(k * 0.12, 0, 0)) * CF.Angles(0.5, 0, 0), V3.new(0.08, 0.26, 0.34), C3.fromRGB(230, 205, 140))
			end
			Geo.block(root, CF.new(tip + V3.new(0, 0.25, 0.12)) * CF.Angles(0.5, 0, 0), V3.new(0.44, 0.18, 0.42), C3.fromRGB(150, 98, 56))
			Geo.block(root, CF.new(tip + V3.new(0, 0.65, 0.35)) * CF.Angles(0.5, 0, 0), V3.new(0.16, 0.7, 0.16), C3.fromRGB(120, 80, 48))
			for k = 1, 7 do
				local a = k * 2.39996
				Geo.ball(root, tip + V3.new(math.cos(a) * 0.7, 0.2 + (k % 3) * 0.25, math.sin(a) * 0.5), 0.22, Flow.Dust[(k % 3) + 1], nil, {
					Transparency = 0.3,
					CanCollide = false,
				})
			end
		end
	end

	-- 3 the Restoration Table working on its own
	do
		local x = Flow.Spacing * 2
		local tableModel = KitMachines.build("RestorationTable", 0)
		tableModel:PivotTo(CF.new(x, 0, 0))
		tableModel.Parent = root
		Old.paintGuis(Loader, root, tableModel)
		local base = tableModel.PrimaryPart
		local intake = base:FindFirstChild("Intake")
		local spot = (base.CFrame * intake.CFrame).Position - V3.new(0, 0.6, 0)
		local relic = ArtifactBuilder.build(Flow.Relic, CF.new(spot) * CF.Angles(0, math.pi * 0.9, 0), 1.2)
		if relic then
			-- nearly done: only a few dusty bits left
			dusty(relic, function(_part: any, i: number): boolean
				return i % 4 == 0
			end)
			relic.Parent = root
		end
		for k = 1, 8 do
			local a = k * 2.39996
			Geo.block(
				root,
				CF.new(spot + V3.new(math.cos(a) * 1.1, 0.5 + (k % 4) * 0.35, math.sin(a) * 1.1)) * CF.Angles(a, a * 0.7, 0.4),
				V3.new(0.14, 0.14, 0.14),
				C3.fromRGB(255, 214, 130),
				NEON
			)
		end
	end

	-- 4 the yard museum with the cleaned relic (and two earlier finds)
	do
		local x = Flow.Spacing * 3
		local plotCF = CF.lookAt(V3.new(x, 0.3, -48), V3.new(x, 0.3, -49))
		local museum = MuseumBuilder.build(plotCF)
		museum.Parent = root
		MuseumBuilder.show(museum, plotCF, { Found = { [Flow.Relic] = 1, CrownCoin = 1, RoyalSeal = 1 } })
		Old.paintGuis(Loader, root, museum)
		local spot = MuseumBuilder.spot(plotCF, Flow.Relic)
		if spot then
			print(string.format("museum relic spot: %.1f %.1f %.1f", spot.Position.X, spot.Position.Y, spot.Position.Z))
		end
	end
	print("Relic flow preview built")
	return root
end

return Flow
