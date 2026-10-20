--[[
	Mine floor concepts for the owner (2026-10-17, docs/plans/MINE_FLOORS_PLAN.md):
	the rocks of all 5 floors (RockBuilder) side by side, the Giant Crystals, and a
	storyboard of a rock breaking. Scene "mine_rocks"
	(lune run tools/lune/export_scene.luau mine_rocks), shots in
	tools/preview/mine_shots.json.

	Layout: floor i is a row at z = -(i - 1) * ROW with a ground pad and a back
	wall in the floor's colors; columns Small, Big, Crystal, Golden, Geode,
	Artifact. Giant Crystals stand in a row at x = GIANT_X. The breaking
	storyboard is at z = STORY_Z.
]]

local roblox = require("@lune/roblox") :: any

local MineConcepts = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum

MineConcepts.ROW = 56
MineConcepts.COL = 9.5
MineConcepts.GIANT_X = 320
MineConcepts.GIANT_GAP = 30
MineConcepts.STORY_Z = 60

local KINDS = { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact" }
local KIND_TEXT = {
	Small = "Small rock",
	Big = "Big rock",
	Crystal = "Crystal 10%",
	Golden = "Golden rock",
	Geode = "Geode",
	Artifact = "Artifact rock",
}

local function label(Geo, CF, parent, cf, width, height, text, color)
	local board = Geo.block(parent, cf, V3.new(width, height, 0.08), C3.fromRGB(36, 30, 40))
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.Parent = board
	local textLabel = roblox.Instance.new("TextLabel")
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.FontFace = roblox.Font.fromEnum(Enum.Font.FredokaOne)
	textLabel.Parent = gui
	return board
end

-- an invisible lamp (only its light shows in the preview)
local function lamp(Geo, CF, parent, position, color, range, brightness)
	local p = Geo.block(parent, CF.new(position.X, position.Y, position.Z), V3.new(0.2, 0.2, 0.2), color, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	local l = roblox.Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	return p
end


-- highest point of a built model
local function topOf(model)
	local top = -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
			local h = d.Size / 2
			top = math.max(top, d.CFrame.Position.Y + math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z)
		end
	end
	return top
end

-- the in-game rock label (src/client/UI/RockLabel.luau) drawn as boards facing +Z for the preview:
-- name in its color on the left, HP on the right, a red bar under them
local function rockLabel(Geo, CF, parent, x, y, z, name, color, hpText, fraction)
	local function textBoard(cx, w, h, text, textColor)
		local board = Geo.block(parent, CF.new(cx, y, z), V3.new(w, h, 0.05), C3.new(0, 0, 0), nil, { Transparency = 0.97, CanCollide = false, CastShadow = false })
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.Parent = board
		local t = roblox.Instance.new("TextLabel")
		t.Text = text
		t.TextColor3 = textColor
		t.FontFace = roblox.Font.fromEnum(Enum.Font.FredokaOne)
		t.Parent = gui
	end
	textBoard(x - 0.75, 3.6, 0.72, name, color)
	textBoard(x + 1.85, 1.5, 0.56, hpText, C3.fromRGB(255, 240, 220))
	local barW = 5.0
	Geo.block(parent, CF.new(x, y - 0.6, z), V3.new(barW + 0.12, 0.3, 0.06), C3.fromRGB(18, 11, 9), nil, { CanCollide = false, CastShadow = false })
	Geo.block(parent, CF.new(x - barW / 2 + barW * fraction / 2, y - 0.6, z + 0.03), V3.new(barW * fraction, 0.2, 0.06), C3.fromRGB(236, 84, 70), nil, { CanCollide = false, CastShadow = false })
end

local function rollOres(Rng, weights, count, seed)
	local rng = Rng.new(seed)
	local list = {}
	for _ = 1, count do
		table.insert(list, rng:weighted(weights))
	end
	return list
end

local function hpText(MineFloors, index, kind)
	local hp = MineFloors.rockHealth(index, kind)
	if hp >= 1000 then
		return string.format("%.1fK HP", hp / 1000)
	end
	return tostring(hp) .. " HP"
end

function MineConcepts.buildRocks(Loader, workspace)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")

	local Dummy = require("./dummy")
	local function person(parent, x, z)
		Dummy.build(parent, CF, CF.lookAt(V3.new(x, 0, z), V3.new(x, 0, z + 10)), "idle")
	end
	local root = roblox.Instance.new("Model")
	root.Name = "MineConcepts"
	root.Parent = workspace
	local ROW, COL = MineConcepts.ROW, MineConcepts.COL
	local TEXT = C3.fromRGB(246, 232, 206)

	---------------------------------------------------------------- floor rows
	for _, floor in MineFloors.List do
		local i = floor.Index
		local pal = floor.Palette
		local z = -(i - 1) * ROW
		local row = roblox.Instance.new("Model")
		row.Name = "Floor" .. i
		row.Parent = root
		Geo.block(row, CF.new(0, -0.5, z - 2), V3.new(66, 1, 30), pal.Ground)
		Geo.block(row, CF.new(0, 8, z - 14), V3.new(70, 18, 2), pal.Dark)
		local lampColor = C3.fromRGB(255, 238, 220):Lerp(pal.Light, 0.25)
		local power = if i == 1 then 0.5 elseif i == 5 then 2.2 else 1.8
		for _, lx in { -20, 0, 20 } do
			lamp(Geo, CF, row, V3.new(lx, 10, z + 8), lampColor, 30, power)
		end
		for col, kind in KINDS do
			local x = (col - 3.5) * COL
			local count = MineFloors.OreCount[kind]
			local weights = if kind == "Crystal" or kind == "Golden" then floor.CrystalOres else floor.Ores
			local ores = rollOres(Rng, weights, count, i * 100 + col)
			local rock = RockBuilder.build(i, kind, ores, CF.new(x, 0, z - 3), i * 31 + col * 7)
			rock.Parent = row
			local maxHp = MineFloors.rockHealth(i, kind)
			local hp = if col == 2 then math.ceil(maxHp * 0.55) else maxHp
			rockLabel(Geo, CF, row, x, topOf(rock) + 1.3, z - 1, MineFloors.rockName(i, kind), MineFloors.labelColor(i, kind), (if hp >= 1e4 then string.format("%.1fK", hp / 1000) else tostring(hp)) .. " HP", hp / maxHp)
			local hp = if kind == "Small" or kind == "Big" or kind == "Crystal" then " · " .. hpText(MineFloors, i, kind) else ""
			label(Geo, CF, row, CF.new(x, 0.32, z + 4.2) * CF.Angles(-1.05, 0, 0), 8.6, 0.9, KIND_TEXT[kind] .. hp, TEXT)
		end
		person(row, 30.5, z - 1)
		local title = string.format("%d · %s · Blaster %d+%s", i, string.upper(floor.Name), floor.MinBlaster, if floor.ViaElevator then " · elevator" else "")
		label(Geo, CF, row, CF.new(0, 0.32, z + 7.4) * CF.Angles(-1.05, 0, 0), 30, 1.3, title, TEXT)
	end

	---------------------------------------------------------------- giant crystals
	for _, floor in MineFloors.List do
		local i = floor.Index
		local x = MineConcepts.GIANT_X + (i - 3) * MineConcepts.GIANT_GAP
		Geo.block(root, CF.new(x, -0.5, 0), V3.new(30, 1, 30), floor.Palette.Ground)
		local giant = RockBuilder.build(i, "Giant", {}, CF.new(x, 0, -2), i * 13)
		giant.Parent = root
		person(root, x + 8.5, 4)
		label(Geo, CF, root, CF.new(x, 0.32, 10.5) * CF.Angles(-1.05, 0, 0), 20, 1.2, floor.Name .. " · Giant Crystal", TEXT)
	end

	---------------------------------------------------------------- breaking storyboard
	-- floor 2, a big rock: 1 intact (beam on it), 2 cracks, 3 a chunk + ore break off, 4 shatter
	local floor = MineFloors.get(2)
	local zS = MineConcepts.STORY_Z
	Geo.block(root, CF.new(0, -0.5, zS), V3.new(76, 1, 26), floor.Palette.Ground)
	Geo.block(root, CF.new(0, 8, zS - 12), V3.new(80, 18, 2), floor.Palette.Dark)
	local ores = rollOres(Rng, floor.Ores, 4, 777)
	local frames = { "1 · blasting", "2 · crack: ore 1 drops", "3 · more cracks: ores 2 + 3", "4 · shatter: last ore" }
	local center: any = nil
	local function fling(pieces, x, lift)
		for _, piece in pieces do
			local out = (piece.CFrame.Position - center) * V3.new(1, 0, 1)
			local dir = if out.Magnitude > 0.01 then out.Unit else V3.new(1, 0, 0)
			piece.CFrame = (piece.CFrame + dir * 2.4 + V3.new(0, lift, 0)) * CF.Angles(0.5, 0.3, 0.4)
		end
	end
	for f = 1, 4 do
		local x = (f - 2.5) * 16.5
		local base = CF.new(x, 0, zS - 2)
		local rock = RockBuilder.build(2, "Big", ores, base, 4242)
		rock.Parent = root
		local rock1 = rock:FindFirstChild("Rock1")
		center = rock1.CFrame.Position
		if f == 2 then
			fling(RockBuilder.applyStage(rock, 1, 9), x, 2.6)
			local chunk = ItemBuilder.build({ Kind = "Raw", OreId = ores[1] }, CF.new(x + 3.6, 2.6, zS + 0.8) * CF.Angles(0.4, 0.6, 0.2), 7)
			chunk.Parent = root
		elseif f >= 3 then
			for stage = 1, 3 do
				local pieces = RockBuilder.applyStage(rock, stage, 9)
				if f == 3 and stage == 3 then
					fling(pieces, x, 2.6)
				else
					for _, piece in pieces do
						piece:Destroy()
					end
				end
			end
			if f == 3 then
				for k = 1, 3 do
					local chunk = ItemBuilder.build({ Kind = "Raw", OreId = ores[k] }, CF.new(x - 4 + k * 2.2, 0.5, zS + 2.2) * CF.Angles(0, k, 0), k)
					chunk.Parent = root
				end
			end
		end
		if f == 4 then
			-- shatter: every part flies outward, dust and a flash, ore chunks on the ground
			for _, d in rock:GetDescendants() do
				if d:IsA("BasePart") then
					local out = d.CFrame.Position - (center - V3.new(0, 1, 0))
					local dir = if out.Magnitude > 0.01 then out.Unit else V3.new(0, 1, 0)
					d.CFrame = (d.CFrame + dir * (2 + out.Magnitude * 0.7)) * CF.Angles(out.X * 0.3, out.Y * 0.2, out.Z * 0.3)
					if d.Size.Magnitude > 3 then
						d.Size = d.Size * 0.55
					end
				end
			end
			local rng = Rng.new("dust")
			for _ = 1, 9 do
				local p = center + V3.new(rng:range(-3.5, 3.5), rng:range(-1.5, 2.5), rng:range(-3, 3))
				local s = rng:range(0.9, 1.8)
				Geo.block(root, CF.new(p.X, p.Y, p.Z) * CF.Angles(rng:range(0, 3), rng:range(0, 3), 0), V3.new(s, s, s), floor.Palette.Light:Lerp(C3.new(1, 1, 1), 0.2), nil, { Transparency = 0.55, CastShadow = false })
			end
						for k = 1, 10 do
				local p = center + V3.new(rng:range(-4, 4), rng:range(0, 4), rng:range(-3, 3))
				Geo.block(root, CF.new(p.X, p.Y, p.Z) * CF.Angles(rng:range(0, 3), rng:range(0, 3), 0), V3.new(0.3, 0.3, 0.3), if k % 2 == 0 then C3.fromRGB(255, 170, 70) else C3.fromRGB(255, 230, 150), Enum.Material.Neon, { CastShadow = false })
			end
			for k, oreId in ores do
				local a = k * 1.6
				local chunk = ItemBuilder.build({ Kind = "Raw", OreId = oreId }, CF.new(x + math.cos(a) * 3.2, 0.6, zS - 2 + math.sin(a) * 2.6 + 1.5) * CF.Angles(0, a, 0), k)
				chunk.Parent = root
			end
		end
		if f == 1 or f == 2 then
			-- the laser beam coming from the camera side
			local from = V3.new(x - 3, 3.4, zS + 9)
			local to = center + V3.new(0, 0.4, 1.6)
			local mid = (from + to) / 2
			local beam = Geo.block(root, CF.lookAt(mid, to), V3.new(0.22, 0.22, (to - from).Magnitude), C3.fromRGB(255, 150, 70), Enum.Material.Neon, { CastShadow = false })
			beam.Name = "Beam"
			Geo.ball(root, to, 0.9, C3.fromRGB(255, 200, 120), Enum.Material.Neon, { CastShadow = false })
		end
		label(Geo, CF, root, CF.new(x, 0.32, zS + 5.4) * CF.Angles(-1.05, 0, 0), 12, 1, frames[f], TEXT)
	end
	for _, lx in { -25, -8, 8, 25 } do
		lamp(Geo, CF, root, V3.new(lx, 10, zS + 8), C3.fromRGB(255, 214, 170), 28, 1.8)
	end
end


--[[
	The ore-shelf showcase (after the owner's reference picture): a stepped
	display in a dark hall, one shelf per floor with a neon edge in the floor's
	color, floor 1 at the top back and floor 5 at the front, the six rock kinds
	of each floor on it with name plates. Scene "mine_showcase".
]]
local SHELF_COLORS = {
	C3.fromRGB(255, 196, 130),
	C3.fromRGB(255, 96, 40),
	C3.fromRGB(70, 214, 255),
	C3.fromRGB(196, 130, 255),
	C3.fromRGB(255, 70, 160),
}
local PLATE_TEXT = {
	Small = "SMALL ROCK",
	Big = "BIG ROCK",
	Crystal = "CRYSTAL 10%",
	Golden = "GOLDEN ROCK",
	Geode = "GEODE",
	Artifact = "ARTIFACT ROCK",
}

-- shrinks a built model around `origin` (display copies on the shelf)
local function scaleModel(model, origin, k)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = origin:ToObjectSpace(d.CFrame)
			d.Size = d.Size * k
			d.CFrame = origin * (rel - rel.Position + rel.Position * k)
		elseif d:IsA("PointLight") then
			d.Range = d.Range * k
		end
	end
end

function MineConcepts.buildShowcase(Loader, workspace)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local NEON = Enum.Material.Neon
	local root = roblox.Instance.new("Model")
	root.Name = "MineShowcase"
	root.Parent = workspace
	local H, D, W, GAP, K = 7, 13, 72, 11, 0.78
	local SHELF = C3.fromRGB(34, 34, 44)
	local EDGE = C3.fromRGB(24, 24, 32)

	-- hall: polished dark floor, back wall, light pillars
	Geo.block(root, CF.new(0, -0.5, -20), V3.new(200, 1, 160), C3.fromRGB(46, 46, 58), nil, { Reflectance = 0.12 })
	Geo.block(root, CF.new(0, 30, -64), V3.new(200, 60, 2), C3.fromRGB(30, 30, 40))
	for _, x in { -60, 60 } do
		Geo.block(root, CF.new(x, 26, -54), V3.new(5, 52, 5), C3.fromRGB(36, 36, 48))
		Geo.block(root, CF.new(x + (if x < 0 then 2.6 else -2.6), 26, -54), V3.new(0.3, 50, 0.6), C3.fromRGB(200, 230, 255), NEON)
		lamp(Geo, CF, root, V3.new(x * 0.8, 20, -40), C3.fromRGB(190, 210, 255), 50, 0.8)
	end
	label(Geo, CF, root, CF.new(0, 47, -62.9), 52, 6.5, "TERRA FORGE  ·  MINE FLOORS", C3.fromRGB(255, 190, 90))

	for _, floor in MineFloors.List do
		local r = 5 - floor.Index -- floor 5 in front (r = 0), floor 1 at the top back (r = 4)
		local top = (r + 1) * H
		local front = -r * D
		local color = SHELF_COLORS[floor.Index]
		Geo.block(root, CF.new(0, top / 2, front - D / 2), V3.new(W, top, D), SHELF)
		Geo.block(root, CF.new(0, top - 0.2, front - D / 2), V3.new(W + 0.4, 0.4, D + 0.1), EDGE)
		-- neon edges along the shelf front, top and bottom of the face
		Geo.block(root, CF.new(0, top - 0.15, front + 0.08), V3.new(W, 0.24, 0.2), color, NEON, { CastShadow = false })
		Geo.block(root, CF.new(0, top - H + 0.5, front + 0.08), V3.new(W, 0.16, 0.2), color:Lerp(C3.new(0, 0, 0), 0.3), NEON, { CastShadow = false })
		-- floor banner straddling the top edge, with a neon frame
		local banner = string.format("FLOOR %d  ·  %s", floor.Index, string.upper(floor.Name))
		Geo.block(root, CF.new(0, top - 1.3, front + 0.06), V3.new(27, 2.1, 0.1), color, NEON, { CastShadow = false })
		label(Geo, CF, root, CF.new(0, top - 1.3, front + 0.14), 26.4, 1.75, banner, color:Lerp(C3.new(1, 1, 1), 0.55))
		local rng = Rng.new("shelf" .. floor.Index)
		for col, kind in KINDS do
			local x = (col - 3.5) * GAP
			local count = MineFloors.OreCount[kind]
			local weights = if kind == "Crystal" or kind == "Golden" then floor.CrystalOres else floor.Ores
			local ores = rollOres(Rng, weights, count, floor.Index * 100 + col)
			local origin = CF.new(x, top, front - D * 0.55) * CF.Angles(0, rng:range(-0.3, 0.3), 0)
			local rock = RockBuilder.build(floor.Index, kind, ores, origin, floor.Index * 31 + col * 7)
			scaleModel(rock, origin, K)
			rock.Parent = root
			-- a small dark pedestal plate and the name plate in front of it
			Geo.block(root, CF.new(x, top + 0.08, front - D * 0.55), V3.new(7, 0.16, 7), C3.fromRGB(22, 22, 30))
			Geo.block(root, CF.new(x, top + 0.1, front - D * 0.55 + 3.55), V3.new(7, 0.12, 0.14), color, NEON, { CastShadow = false })
			label(Geo, CF, root, CF.new(x, top + 0.45, front - 1.9) * CF.Angles(-1.0, 0, 0), 8.6, 0.95, PLATE_TEXT[kind], C3.fromRGB(236, 236, 246))
		end
		for _, lx in { -24, 0, 24 } do
			lamp(Geo, CF, root, V3.new(lx, top + 6, front + 3), C3.fromRGB(255, 244, 232), 20, 1.6)
		end
	end
end

return MineConcepts
