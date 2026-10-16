--[[
	Laser blaster previews (scenes for tools/lune/export_scene.luau, shots in
	tools/preview/blaster_shots.json):
	  blasters      the 10 blaster levels in different ore skins on pedestals
	                (shot "blasters"), plus two walls off to the side: every
	                level in a straight side view like the Kenney Blaster Kit
	                sheet (shot "blasters_side") and two levels in many ore
	                skins (shot "blaster_skins")
	  blaster_fire  a forgekeeper in the quarry blasting a rock
	Beams are drawn as thin neon parts here (the preview can't render Beam
	instances; the game uses Beams from the tool's Muzzle).
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

-- The ore skin shown for each level in the gallery ("" = rusty starter).
Gallery.Skins = { "", "Copper", "Azurium", "Amethyst", "Gold", "Ruby", "Sapphire", "Emerald", "Stormcore", "Heartstone" }

-- A few levels in many skins (the skins wall).
Gallery.SkinRows = {
	{ Level = 4, Spacing = 5.4, Ores = { "Iron", "Jade", "Cobalt", "Emberite" } },
	{ Level = 7, Spacing = 6.4, Ores = { "Obsidian", "Moonstone", "Verdantine" } },
	{ Level = 10, Spacing = 7.4, Ores = { "Diamond", "Magmacore", "Prismite" } },
}

local function label(Loader: any, parent: any, cf: any, size: any, text: string, face: string?)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local plate = Geo.block(parent, cf, size, roblox.Color3.fromRGB(40, 28, 24), nil, { CanCollide = false })
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = roblox.Enum.NormalId[face or "Back"] -- Back = the +Z side, toward the gallery camera
	gui.Parent = plate
	local textLabel = roblox.Instance.new("TextLabel")
	textLabel.Text = text
	textLabel.TextColor3 = roblox.Color3.fromRGB(255, 226, 170)
	textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
	textLabel.Parent = gui
	return plate
end

-- Moves a built tool to `cf` (tools are built in their design frame).
function Gallery.place(tool: any, cf: any, parent: any)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
			d.Anchored = true
		end
	end
	tool.Parent = parent
	return tool
end

-- World position of a placed tool's Muzzle.
function Gallery.muzzle(tool: any): any
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle:FindFirstChild("Muzzle")
	return handle.CFrame:PointToWorldSpace(muzzle.Position)
end

--[[
	Measures an unplaced tool in its design frame: the hand (grip frame), the
	muzzle point and the rough extents { minY, maxY, minZ, maxZ }.
]]
function Gallery.measure(tool: any): (any, any, { [string]: number })
	local handle = tool:FindFirstChild("Handle")
	local hand = handle.CFrame * tool.Grip
	local box = { minY = math.huge, maxY = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			-- half extent along world Y / Z of the rotated box
			local r = d.CFrame
			local s = d.Size / 2
			local hy = math.abs(r.RightVector.Y) * s.X + math.abs(r.UpVector.Y) * s.Y + math.abs(r.LookVector.Y) * s.Z
			local hz = math.abs(r.RightVector.Z) * s.X + math.abs(r.UpVector.Z) * s.Y + math.abs(r.LookVector.Z) * s.Z
			box.minY = math.min(box.minY, p.Y - hy)
			box.maxY = math.max(box.maxY, p.Y + hy)
			box.minZ = math.min(box.minZ, p.Z - hz)
			box.maxZ = math.max(box.maxZ, p.Z + hz)
		end
	end
	return hand, Gallery.muzzle(tool), box
end

--[[
	A blocky forgekeeper holding a blaster with both hands and firing at
	`aim`. root: CFrame at the feet. Returns the tool and the muzzle position.
]]
function Gallery.forgekeeper(Loader: any, parent: any, root: any, aim: any, level: number, oreId: string, colors: any?)
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local m = roblox.Instance.new("Model")
	m.Name = "Forgekeeper"
	m.Parent = parent
	local shirt = colors and colors.shirt or C3.fromRGB(186, 98, 48)
	local pants = colors and colors.pants or C3.fromRGB(60, 54, 70)
	local skin = C3.fromRGB(236, 190, 150)
	local function block(cf: any, size: any, color: any)
		return Geo.block(m, cf, size, color)
	end
	block(root * CF.new(-0.5, 1, 0), V3.new(0.95, 2, 0.95), pants)
	block(root * CF.new(0.5, 1, 0.15) * CF.Angles(0.15, 0, 0), V3.new(0.95, 2, 0.95), pants)
	block(root * CF.new(0, 3, 0), V3.new(2, 2, 1), shirt)
	block(root * CF.new(0, 2.7, -0.53), V3.new(1.6, 2.3, 0.08), C3.fromRGB(110, 70, 40)) -- apron
	block(root * CF.new(0, 4.65, 0), V3.new(1.2, 1.2, 1.2), skin)
	block(root * CF.new(0, 5.3, 0.1), V3.new(1.28, 0.32, 1.28), C3.fromRGB(80, 50, 30))
	-- goggles on the forehead
	block(root * CF.new(0, 5.02, -0.6), V3.new(1.24, 0.22, 0.12), C3.fromRGB(50, 40, 36))
	for _, side in { -1, 1 } do
		local lens = root * CF.new(side * 0.3, 5.02, -0.68)
		Geo.cylinder(m, lens.Position, 0.08, 0.34, C3.fromRGB(120, 200, 230), roblox.Enum.Material.Glass)
		block(root * CF.new(side * 0.27, 4.75, -0.61), V3.new(0.16, 0.26, 0.04), C3.fromRGB(40, 30, 30))
	end
	-- the blaster: its grip in the right hand, the barrel line on the target
	local tool = BlasterBuilder.build(level, oreId)
	local handDesign, muzzleDesign = Gallery.measure(tool)
	local hand = root * CF.new(1.1, 3.75, -1.9)
	local barrelUp = muzzleDesign.Y - handDesign.Position.Y
	local gunCf = CF.lookAt(hand.Position, aim - V3.new(0, barrelUp, 0)) * CF.new(-handDesign.Position)
	-- arms: the right one points at the target, the left one steadies the blaster under the body
	local function arm(shoulder: any, handPos: any)
		local length = (handPos - shoulder).Magnitude
		local cf = CF.lookAt((shoulder + handPos) / 2, handPos)
		block(cf, V3.new(0.9, 0.9, length + 0.6), shirt)
		block(CF.lookAt(handPos, handPos + (handPos - shoulder)), V3.new(0.7, 0.7, 0.7), skin)
	end
	local support = V3.new(-0.42, -0.05, (handDesign.Position.Z + muzzleDesign.Z) / 2)
	arm((root * CF.new(1.4, 3.9, -0.1)).Position, hand.Position)
	arm((root * CF.new(-1.4, 3.9, -0.1)).Position, (gunCf * CF.new(support)).Position)
	Gallery.place(tool, gunCf, m)
	return tool, Gallery.muzzle(tool)
end

-- The point on a rock's main block facing `from` (where a beam would hit).
function Gallery.surface(rock: any, from: any, up: number): any
	local primary = rock.PrimaryPart
	local center = primary.CFrame.Position
	local flat = (from - center) * roblox.Vector3.new(1, 0, 1)
	local radius = math.max(primary.Size.X, primary.Size.Z) * 0.45
	return center + flat.Unit * radius + roblox.Vector3.new(0, up, 0)
end

-- A laser beam (outer glow + white core) from a to b, with a hot impact.
function Gallery.beam(Loader: any, parent: any, a: any, b: any, color: any)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local length = (b - a).Magnitude
	local mid = CF.lookAt((a + b) / 2, b)
	local neon = roblox.Enum.Material.Neon
	local props = { CanCollide = false, CastShadow = false }
	Geo.block(parent, mid, V3.new(0.42, 0.42, length), color, neon, { CanCollide = false, CastShadow = false, Transparency = 0.45 })
	Geo.block(parent, mid, V3.new(0.14, 0.14, length), roblox.Color3.new(1, 1, 1), neon, props)
	Geo.ball(parent, b, 1.1, color, neon, { CanCollide = false, CastShadow = false, Transparency = 0.35 })
	Geo.ball(parent, b, 0.5, roblox.Color3.new(1, 1, 1), neon, props)
	Geo.ball(parent, a, 0.5, color, neon, { CanCollide = false, CastShadow = false, Transparency = 0.3 })
	-- sparks bouncing back from the rock
	local back = (a - b).Unit
	for i = 1, 9 do
		local angle = i * 2.4
		local spread = V3.new(math.cos(angle), math.sin(angle) * 0.8 + 0.5, math.sin(angle * 1.7)) * (0.5 + (i % 3) * 0.45)
		local p = b + back * (0.4 + (i % 4) * 0.35) + spread
		Geo.ball(parent, p, 0.12 + (i % 3) * 0.05, color:Lerp(roblox.Color3.new(1, 1, 1), 0.5), neon, props)
	end
	local light = roblox.Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	local holder = Geo.ball(parent, b + back * 0.8, 0.1, color, nil, { CanCollide = false, Transparency = 1 })
	light.Parent = holder
end

--[[
	Builds a blaster and stands it at `at` (bottom center of where it rests),
	turned by `yaw` (0 = barrel along -Z). The gun is centered along its
	length and rests on its lowest part. Returns the tool.
]]
local function showcase(Loader: any, parent: any, level: number, oreId: string, at: any, yaw: number, lift: number?)
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local CF = Loader.CFrame
	local tool = BlasterBuilder.build(level, oreId)
	local _, _, box = Gallery.measure(tool)
	local center = roblox.Vector3.new(0, box.minY - (lift or 0), (box.minZ + box.maxZ) / 2)
	Gallery.place(tool, CF.new(at) * CF.Angles(0, yaw, 0) * CF.new(-center), parent)
	return tool
end

function Gallery.build(Loader: any, parent: any, sceneName: string)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterGallery"
	root.Parent = parent
	local SLATE = roblox.Enum.Material.Slate
	local METAL = roblox.Enum.Material.Metal

	if sceneName == "blasters" then
		-- a stone workshop floor, a dark forge wall behind the display
		Geo.block(root, CF.new(0, -0.5, 0), V3.new(120, 1, 90), C3.fromRGB(104, 92, 88), SLATE)
		Geo.block(root, CF.new(0, 7, -9.6), V3.new(40, 16, 1), C3.fromRGB(64, 58, 62), SLATE)
		for _, y in { 7.6, 13.4 } do
			Geo.block(root, CF.new(0, y, -9.05), V3.new(40, 0.3, 0.2), C3.fromRGB(176, 112, 52), METAL)
		end
		label(Loader, root, CF.new(0, 9.9, -9.0), V3.new(13, 1.5, 0.1), "LASER BLASTERS  Lv 1 - 10")
		-- a stepped display stand, three steps like the side-view wall: pistols and SMGs at the
		-- back, the carbines in the middle, the long rifles in front
		local STAND = C3.fromRGB(84, 76, 78)
		local TRIM = C3.fromRGB(176, 106, 48)
		local tiers = {
			{ z = -7, top = 5.8, spacing = 5.2, levels = { 1, 2, 3, 4 } },
			{ z = -3, top = 3.4, spacing = 6.8, levels = { 5, 6, 7 } },
			{ z = 1, top = 1.0, spacing = 7.2, levels = { 8, 9, 10 } },
		}
		for _, tier in tiers do
			Geo.block(root, CF.new(0, tier.top / 2, tier.z), V3.new(24, tier.top, 3.6), STAND, SLATE)
			-- a dark top with a copper edge strip in front
			Geo.block(root, CF.new(0, tier.top + 0.05, tier.z - 0.1), V3.new(24, 0.1, 3.4), C3.fromRGB(58, 54, 58), METAL)
			Geo.block(root, CF.new(0, tier.top + 0.06, tier.z + 1.72), V3.new(24.2, 0.12, 0.2), TRIM, METAL)
			local n = #tier.levels
			for i, level in tier.levels do
				local x = (i - (n + 1) / 2) * tier.spacing
				local oreId = Gallery.Skins[level]
				local name = BlasterData.displayName(level, oreId)
				label(
					Loader,
					root,
					CF.new(x, tier.top - 0.42, tier.z + 1.82),
					V3.new(tier.spacing - 0.5, 0.56, 0.06),
					"Lv " .. level .. "  " .. name
				)
				-- like the Kenney sheet: the right side toward the camera, the barrel pointing right and a little away
				local tool = showcase(Loader, root, level, oreId, V3.new(x, tier.top + 0.1, tier.z), -1.2)
				-- the core's glow
				if level >= 6 then
					local light = roblox.Instance.new("PointLight")
					light.Color = BlasterBuilder.look(level, oreId).Glow
					light.Range = 5
					light.Brightness = 0.6
					light.Parent = tool:FindFirstChild("Handle")
				end
			end
		end
		-- two braziers with embers (warm light from the sides)
		for _, side in { -1, 1 } do
			local x = side * 14.5
			Geo.cylinder(root, V3.new(x, 1, 1), 2, 2.2, C3.fromRGB(58, 52, 54), METAL)
			local coals = Geo.cylinder(root, V3.new(x, 2.1, 1), 0.3, 1.8, C3.fromRGB(255, 120, 40), roblox.Enum.Material.Neon)
			local embers = roblox.Instance.new("ParticleEmitter")
			embers.Name = "Embers"
			embers.Color = roblox.ColorSequence.new(C3.fromRGB(255, 150, 60))
			embers.Parent = coals
			local light = roblox.Instance.new("PointLight")
			light.Color = C3.fromRGB(255, 150, 70)
			light.Range = 14
			light.Brightness = 1.2
			light.Parent = coals
		end

		-- two dark display walls off to the side (x ~ 100 and ~ 160), like the Kenney sheet
		local wallZ = 0
		Geo.block(root, CF.new(130, -0.5, 0), V3.new(120, 1, 90), C3.fromRGB(70, 64, 66), SLATE)
		for _, wallX in { 100, 160 } do
			Geo.block(root, CF.new(wallX, 7, wallZ - 0.6), V3.new(30, 15, 1), C3.fromRGB(58, 58, 70), SLATE)
		end
		-- rows of guns on a wall: { y, spacing, entries = { { level, oreId, label } } }
		local function wallRows(centerX: number, rows: { any }, yaw: number)
			for _, row in rows do
				local n = #row.entries
				for i, entry in row.entries do
					local x = centerX + (i - (n + 1) / 2) * row.spacing
					showcase(Loader, root, entry[1], entry[2], V3.new(x, row.y, wallZ + 1.5), yaw)
					label(
						Loader,
						root,
						CF.new(x, row.y - 0.75, wallZ - 0.05),
						V3.new(math.min(row.spacing - 0.4, 5.4), 0.46, 0.06),
						entry[3]
					)
				end
			end
		end
		-- the side-view wall: every level straight from the side, barrel to the right
		local sideRows =
			{ { y = 9.4, spacing = 5.2, entries = {} }, { y = 5.9, spacing = 7.2, entries = {} }, { y = 2.4, spacing = 7.4, entries = {} } }
		for level = 1, BlasterData.MaxLevel do
			local row = sideRows[if level <= 4 then 1 elseif level <= 7 then 2 else 3]
			table.insert(row.entries, { level, Gallery.Skins[level], "Lv " .. level .. "  " .. BlasterData.get(level).Name })
		end
		wallRows(100, sideRows, -math.pi / 2)
		-- the skins wall: a few levels in many ore skins, turned a little toward the camera
		local skinRows = {}
		for r, rowInfo in Gallery.SkinRows do
			local entries = {}
			for _, oreId in rowInfo.Ores do
				table.insert(entries, { rowInfo.Level, oreId, BlasterData.displayName(rowInfo.Level, oreId) })
			end
			table.insert(skinRows, { y = 9.4 - (r - 1) * 3.5, spacing = rowInfo.Spacing, entries = entries })
		end
		wallRows(160, skinRows, -1.35)
	elseif sceneName == "blaster_fire" then
		local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
		local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
		local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
		WorldBuilder.build(parent)
		-- a quarry rock with two ores, cracked by the beam
		local rockPos = V3.new(-30, -12, -165)
		local rock = OreNodeBuilder.buildRock("Quarry", { "Silver", "Iron" }, CF.new(rockPos) * CF.Angles(0, 0.6, 0), 42)
		rock.Parent = root
		pcall(OreNodeBuilder.applyStage, rock, 1, 42)
		local center = rock.PrimaryPart.CFrame.Position
		local feet = rockPos + V3.new(8.5, 0, 6.5)
		local aimAt = Gallery.surface(rock, feet, 0.6)
		local rootCf = CF.lookAt(feet, V3.new(center.X, feet.Y, center.Z))
		local level, oreId = 9, "Azurium"
		local _, muzzle = Gallery.forgekeeper(Loader, root, rootCf, aimAt, level, oreId)
		local glow = BlasterBuilder.look(level, oreId).Glow
		Gallery.beam(Loader, root, muzzle, aimAt, glow)
		-- dirty ore chunks that already dropped
		for i, spot in { V3.new(-27, -11.4, -160.5), V3.new(-24.5, -11.4, -163) } do
			local item =
				ItemBuilder.build({ Kind = "Raw", OreId = if i == 1 then "Silver" else "Iron" }, CF.new(spot) * CF.Angles(i, i * 2, 0), i)
			item.Parent = root
		end
		-- a second forgekeeper with a rusty starter blaster on another rock
		local rock2Pos = V3.new(-48, -12, -182)
		local rock2 = OreNodeBuilder.buildRock("Quarry", { "Coal" }, CF.new(rock2Pos), 7)
		rock2.Parent = root
		local center2 = rock2.PrimaryPart.CFrame.Position
		local feet2 = rock2Pos + V3.new(-7, 0, 6)
		local aim2 = Gallery.surface(rock2, feet2, 0.4)
		local _, muzzle2 = Gallery.forgekeeper(Loader, root, CF.lookAt(feet2, V3.new(center2.X, feet2.Y, center2.Z)), aim2, 1, "", {
			shirt = C3.fromRGB(70, 120, 170),
			pants = C3.fromRGB(50, 50, 60),
		})
		Gallery.beam(Loader, root, muzzle2, aim2, BlasterBuilder.look(1, "").Glow)
	end
	return root
end

return Gallery
