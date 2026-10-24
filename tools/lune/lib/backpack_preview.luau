--[[
	Backpack preview pictures (art/backpacks, the owner's reference picture
	of a blue rune backpack, 2026-10-24):
	  scene "backpacks"       the ten packs (BackpackBuilder) worst to best on
	                          rising pedestals in a shop, a rarity glow ring on
	                          each, a plate in front (number, name, ore, price)
	  scene "backpacks_worn"  stand-in miners on a meadow path seen from
	                          behind (the player's own camera), each wearing a
	                          pack, like the owner's reference shots
	  scene "backpack_stall"  the world with the BACKPACKS stall (Districts/
	                          Backpacks) and its three display packs as the
	                          clients build them (BackpackWearController), two
	                          shoppers wearing packs at the counter
	  scene "backpack_shop"   the showroom + the shop window overlays
	                          (Preview.buildUi) and the packs' 3D pictures for
	                          them (Preview.exportIcons: build/preview/icon_parts,
	                          then node tools/preview/render_icons.mjs backpack_...)
	Shots: tools/preview/backpack_shots.json.
]]

local Preview = {}

Preview.Spacing = 3.4
Preview.WornSpacing = 4.2

local function setup(Loader: any)
	local roblox = Loader.roblox
	return {
		roblox = roblox,
		CFrame = Loader.CFrame,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo"),
		Builder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackBuilder"),
		Fx = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackFx"),
		Data = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData"),
		Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity"),
		Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format"),
		Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng"),
	}
end

local function blockMaker(k: any, parent: any)
	return function(name: string, cf: any, size: any, color: any, material: any?, shape: string?): any
		local p = k.Geo.make("Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or k.Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, parent)
		if shape == "Cylinder" then
			p.Shape = k.Enum.PartType.Cylinder
		end
		return p
	end
end

-- A plate whose +Z face shows `lines` (one TextLabel per line, own colours).
local function plate(k: any, block: any, cf: any, size: any, lines: { { any } })
	local p = block("Plate", cf, size, k.Color3.fromRGB(38, 30, 26))
	local gui = k.roblox.Instance.new("SurfaceGui")
	gui.Face = k.Enum.NormalId.Back
	gui.SizingMode = k.Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = p
	local n = #lines
	for i, line in lines do
		local t = k.roblox.Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = k.roblox.UDim2.fromScale(0.94, 0.86 / n)
		t.Position = k.roblox.UDim2.fromScale(0.03, 0.07 + (i - 1) * 0.86 / n)
		t.Text = line[1]
		t.TextScaled = true
		t.TextColor3 = line[2]
		t.TextStrokeColor3 = k.Color3.fromRGB(10, 8, 6)
		t.TextStrokeTransparency = 0.25
		t.FontFace = k.roblox.Font.fromEnum(k.Enum.Font.LuckiestGuy)
		t.Parent = gui
	end
end

-- How far each effect kind drifts up from its box, how long one particle
-- lives (rate x life = how many are out at once) and its size.
local RISE = { Sparkle = 0.7, Rune = 1.1, Ember = 1.6, Fire = 0.35, Star = 0.2, Glint = 0 }
local LIFE = { Sparkle = 1.2, Rune = 1.5, Ember = 1.6, Star = 1.1, Glint = 0.5 }
local SIZE = { Sparkle = 0.11, Rune = 0.09, Ember = 0.07, Star = 0.2, Glint = 0.26 }

--[[
	BackpackFx's effects on a placed pack, frozen in one moment the way the
	renderer can draw them: as many particles as are out at once (rate x
	lifetime) as small Neon bits spread over the volume they fill (rising
	kinds stretched upward; glints and stars as four-point twinkles), fire as
	a "GunFlame" box (tools/lune/lib/export.luau), smoke as three grey puffs.
	The light stays (the renderer draws PointLights).
]]
local function withFx(k: any, model: any)
	local emitters = k.Fx.apply(model)
	local rng = k.Rng.new(#model.Name * 7919 + math.floor(model:GetPivot().Position.X * 13))
	local function bit(name: string, cf: any, size: any, color: any, transparency: number?)
		return k.Geo.make("Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = k.Enum.Material.Neon,
			Transparency = transparency or 0,
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
		}, model)
	end
	for _, e in emitters do
		local box = e.Parent
		local kind = string.sub(e.Name, #"Backpack" + 1)
		local color = e.Color.Keypoints[1].Value
		local size = box.Size
		if kind == "Smoke" then
			for i = 1, 3 do
				local d = 0.24 + i * 0.16
				local puff = bit(
					"SmokePuff",
					box.CFrame * k.CFrame.new(0.06 * i, 0.2 + i * 0.3, -0.04 * i),
					k.Vector3.new(d, d, d),
					color:Lerp(k.Color3.new(1, 1, 1), 0.15 * i),
					0.3 + i * 0.15
				)
				puff.Material = k.Enum.Material.SmoothPlastic
				puff.Shape = k.Enum.PartType.Ball
			end
		elseif kind == "Fire" then
			local standIn = bit(
				"FxStandIn",
				box.CFrame * k.CFrame.new(0, RISE.Fire / 2, 0),
				k.Vector3.new(size.X, size.Y + RISE.Fire, size.Z),
				color,
				1
			)
			local flame = k.roblox.Instance.new("ParticleEmitter")
			flame.Name = "GunFlame"
			flame.Color = k.roblox.ColorSequence.new(color)
			flame.Parent = standIn
		else
			local rise = RISE[kind] or 0
			local count = math.max(1, math.floor(e.Rate * (LIFE[kind] or 1) + 0.5))
			for i = 1, count do
				local t = (i - 0.5) / count -- how far along its life (rising kinds: higher)
				local offset =
					k.Vector3.new(rng:range(-0.5, 0.5) * size.X, rng:range(-0.5, 0.5) * size.Y + rise * t, rng:range(-0.5, 0.5) * size.Z)
				local cf = box.CFrame * k.CFrame.new(offset.X, offset.Y, offset.Z)
				local s = (SIZE[kind] or 0.1) * (if kind == "Star" or kind == "Glint" then rng:range(0.6, 1.1) else 1 - 0.5 * t)
				if kind == "Star" or kind == "Glint" then
					bit("Twinkle", cf, k.Vector3.new(s, s * 0.16, 0.02), color)
					bit("Twinkle", cf, k.Vector3.new(s * 0.16, s, 0.02), color)
				else
					bit("Mote", cf * k.CFrame.Angles(0, 0, math.pi / 4), k.Vector3.new(s, s, s * 0.5), color, 0.15 * t)
				end
			end
		end
		e:Destroy()
	end
end

-- Puts a built pack (with its effects) so its bag stands centered on (x, floorY, z), facing +Z.
local function placePack(k: any, parent: any, packId: string, x: number, floorY: number, z: number): any
	local model = k.Builder.build(packId, true)
	local pack = k.Data.ById[packId]
	local bottom = model:GetAttribute("BottomY")
	model:PivotTo(k.CFrame.new(x, floorY - bottom, z - k.Builder.Gap - pack.Size.Z / 2))
	model.Parent = parent
	withFx(k, model)
	return model
end

local function priceText(k: any, price: number): string
	if price <= 0 then
		return "FREE"
	end
	return k.Format.short(price) .. " COINS"
end

--[[
	Scene "backpacks": the ten packs left (worst) to right (best) on rising
	stone pedestals in a warm shop with a plank floor and a back wall.
]]
function Preview.build(Loader: any, workspace: any)
	local k = setup(Loader)
	local rgb = k.Color3.fromRGB
	local stage = k.roblox.Instance.new("Model")
	stage.Name = "BackpackShowroom"
	stage.Parent = workspace
	local block = blockMaker(k, stage)
	local CF, V3 = k.CFrame, k.Vector3
	local NEON = k.Enum.Material.Neon

	-- the shop: planks, a wall with a wainscot, a sign strip
	block("Floor", CF.new(0, -0.5, 4), V3.new(60, 1, 34), rgb(104, 74, 54), k.Enum.Material.WoodPlanks)
	block("Wall", CF.new(0, 10, -6), V3.new(60, 22, 1), rgb(92, 128, 140))
	block("Wainscot", CF.new(0, 1.6, -5.4), V3.new(60, 3.2, 0.4), rgb(120, 80, 50), k.Enum.Material.Wood)
	block("Rail", CF.new(0, 3.25, -5.3), V3.new(60, 0.2, 0.6), rgb(96, 62, 38), k.Enum.Material.Wood)
	plate(k, block, CF.new(0, 9.2, -5.4), V3.new(14, 2.2, 0.2), { { "BACKPACKS", rgb(255, 214, 90) } })

	for i, pack in k.Data.List do
		local x = (i - 5.5) * Preview.Spacing
		local height = 0.6 + (i - 1) * 0.2
		local rarity = k.Rarity.ById[pack.Rarity]
		-- the pedestal: stone, a glowing rarity ring under a stone top
		block(
			"Pedestal",
			CF.new(x, height / 2, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(height, 2.5, 2.5),
			rgb(120, 116, 128),
			nil,
			"Cylinder"
		)
		block(
			"PedestalRing",
			CF.new(x, height - 0.12, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(0.1, 2.7, 2.7),
			rarity.Color,
			NEON,
			"Cylinder"
		)
		block(
			"PedestalTop",
			CF.new(x, height - 0.02, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(0.12, 2.5, 2.5),
			rgb(150, 146, 158),
			nil,
			"Cylinder"
		)
		placePack(k, stage, pack.Id, x, height + 0.04, 0)
		-- the plate in front, tilted back
		plate(k, block, CF.new(x, 0.86, 2.1) * CF.Angles(-0.35, 0, 0), V3.new(3.1, 0.5, 0.14), {
			{ `{i}. {string.upper(pack.Name)}`, rarity.Color },
		})
		plate(k, block, CF.new(x, 0.38, 2.27) * CF.Angles(-0.35, 0, 0), V3.new(3.1, 0.46, 0.14), {
			{ `{k.Format.commas(pack.Capacity)} ORE · {priceText(k, pack.Price)}`, rgb(255, 236, 170) },
		})
	end
end

--[[
	Scene "backpacks_worn": miners seen from behind on a meadow path, each
	wearing a pack (Root on the back of the dummy's torso), like the owner's
	reference shots. Row 1 (z = 0): packs 1-5; row 2 (z = -14): packs 6-10.
]]
function Preview.buildWorn(Loader: any, workspace: any)
	local k = setup(Loader)
	local rgb = k.Color3.fromRGB
	local CF, V3 = k.CFrame, k.Vector3
	local Dummy = require("./dummy")
	local stage = k.roblox.Instance.new("Model")
	stage.Name = "BackpackMeadow"
	stage.Parent = workspace
	local block = blockMaker(k, stage)
	local rng = k.Rng.new(2410)

	block("Grass", CF.new(0, -0.5, -8), V3.new(80, 1, 60), rgb(98, 168, 72), k.Enum.Material.Grass)
	-- two stone paths of flat slate stones
	for _, rowZ in { 0, -14 } do
		for _ = 1, 70 do
			local x = rng:range(-13, 13)
			local z = rowZ + rng:range(-2.6, 2.6)
			local s = rng:range(0.7, 1.4)
			block("Stone", CF.new(x, 0.02, z) * CF.Angles(0, rng:range(0, math.pi), 0), V3.new(s, 0.12, s * 0.7), rgb(112, 118, 150))
		end
	end
	-- leafy bushes with purple fruit along the far edge
	for i = 1, 16 do
		local x = (i - 8.5) * 3.4 + rng:range(-0.6, 0.6)
		local z = -22 + rng:range(-1, 1)
		local leaf = block(
			"Bush",
			CF.new(x, 1.1, z) * CF.Angles(0, rng:range(0, 1.5), 0),
			V3.new(2.6, 2.2, 2.6),
			rgb(86, 170, 60),
			k.Enum.Material.Grass
		)
		leaf.Shape = k.Enum.PartType.Ball
		for _ = 1, 3 do
			local berry = block(
				"Fruit",
				CF.new(x + rng:range(-1, 1), rng:range(1.2, 2.2), z + rng:range(0.6, 1.2)),
				V3.new(0.5, 0.7, 0.5),
				rgb(98, 50, 200)
			)
			berry.Shape = k.Enum.PartType.Ball
		end
	end

	local shirts = {
		{ shirt = rgb(120, 120, 140), pants = rgb(70, 60, 50) },
		{ shirt = rgb(186, 98, 48), pants = rgb(60, 54, 70) },
		{ shirt = rgb(70, 120, 186), pants = rgb(52, 52, 64) },
		{ shirt = rgb(220, 220, 228), pants = rgb(60, 70, 110) },
		{ shirt = rgb(120, 62, 48), pants = rgb(46, 44, 56) },
	}
	for i, pack in k.Data.List do
		local row = if i <= 5 then 0 else 1
		local col = if i <= 5 then i else i - 5
		local x = (col - 3) * Preview.WornSpacing
		local z = -row * 14
		-- facing away from the camera (-Z): the back and the pack face +Z
		local root = CF.new(x, 0, z)
		local look = shirts[(i - 1) % #shirts + 1]
		Dummy.build(stage, CF, root, "idle", { shirt = look.shirt, pants = look.pants })
		local model = k.Builder.build(pack.Id)
		model:PivotTo(root * CF.new(0, 3.2, 0.5))
		model.Parent = stage
		withFx(k, model)
	end
end

--[[
	Scene "backpack_stall": after WorldBuilder.build, every display marker of
	the stall (attribute BackpackId) gets its display pack the way BackpackWearController
	places it (outer face to the marker's front, the bag centred, standing on
	it) with its effects; two shoppers with packs stand at the counter.
]]
function Preview.buildStall(Loader: any, workspace: any)
	local k = setup(Loader)
	local CF, V3 = k.CFrame, k.Vector3
	local Dummy = require("./dummy")
	local stage = k.roblox.Instance.new("Model")
	stage.Name = "BackpackStallPreview"
	stage.Parent = workspace
	local counter: any = nil
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("BackpackId") ~= nil and d.Parent and d.Parent.Name == "BackpackStall" then
			local id = d:GetAttribute("BackpackId")
			local pack = k.Data.ById[id]
			if pack then
				local model = k.Builder.build(id, true)
				local bottom = model:GetAttribute("BottomY")
				model:PivotTo(d.CFrame * CF.Angles(0, math.pi, 0) * CF.new(0, d.Size.Y / 2 - bottom, -(k.Builder.Gap + pack.Size.Z / 2)))
				model.Parent = stage
				withFx(k, model)
			end
		elseif d:IsA("BasePart") and d:HasTag("BackpackCounter") then
			counter = d
		end
	end
	if counter then
		-- two shoppers in front of the counter, facing it (their packs toward the plaza)
		local rgb = k.Color3.fromRGB
		for _, spec in { { -6.6, "MinersPack", rgb(70, 120, 186) }, { 6.8, "AmethystPack", rgb(186, 98, 48) } } do
			-- beside the stall, turned half toward it (their packs to the camera on the plaza)
			local front = counter.CFrame * CF.new(spec[1], 0, -4.2)
			local feet = V3.new(front.Position.X, 0.5, front.Position.Z)
			local toStall = (counter.CFrame.Position - front.Position) * V3.new(1, 0, 1)
			local root = CF.lookAt(feet, feet + toStall.Unit)
			Dummy.build(stage, CF, root, "idle", { shirt = spec[3], pants = rgb(52, 52, 64) })
			local model = k.Builder.build(spec[2])
			model:PivotTo(root * CF.new(0, 3.2, 0.5))
			model.Parent = stage
			withFx(k, model)
		end
	end
end

--[[
	The packs' 3D pictures for the shop window's preview (in the game they are
	live ViewportFrames: PictureModels "backpack_<Id>"): the display build of
	every pack to build/preview/icon_parts/backpack_<Id>.json for
	tools/preview/render_icons.mjs (icons.js: backpack_*).
]]
function Preview.exportIcons(Loader: any)
	local k = setup(Loader)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Export = require("./export")
	local dir = Loader.root .. "/build/preview/icon_parts"
	fs.writeDir(dir)
	for _, pack in k.Data.List do
		local model = k.Builder.build(pack.Id, true)
		fs.writeFile(`{dir}/backpack_{pack.Id}.json`, serde.encode("json", Export.collect(model)))
	end
end

--[[
	The shop window over the showroom:
	  ui_backpack_shop        PC: the shop (owns the first three packs, wears
	                          the Leather Rucksack, 140K coins)
	  ui_backpack_shop_phone  an iPhone SE-sized landscape screen (667 x 375 pt)
	                          at the 0.62 phone scale: the compact window, its
	                          cards scroll
]]
function Preview.buildUi(Loader: any): { [string]: any }
	local k = setup(Loader)
	local UiExport = require("./uiexport")
	local Client = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local ShopView = Loader.requirePath(Client .. "BackpackShopView")
	local pc = 1.25 -- 900 px tall render / 720 design height
	local phone = 0.62 * 900 / 375

	local function window(scale: number, compact: boolean, maxWidth: number, maxHeight: number): { any }
		local refs = ShopView.build(compact)
		refs.Gui.Scale.Scale = scale
		refs.Gui.Enabled = true
		local owned = { RookiePack = true, TrailPack = true, LeatherRucksack = true }
		ShopView.setCards(refs, owned, "LeatherRucksack", 140000)
		ShopView.setStatus(refs, ShopView.statusText("LeatherRucksack", 12, 30))
		ShopView.layout(refs, compact, maxWidth, maxHeight)
		ShopView.pose(refs, ShopView.OpenTime)
		if not compact then
			ShopView.setHint(refs, "Mouse", "Click a card · Backspace: close")
		end
		return { refs.Gui }
	end

	return {
		-- (the renderer puts a ScreenGui under the 36 px top bar, tools/preview/ui.js TOPBAR_INSET)
		ui_backpack_shop = UiExport.export(window(pc, false, 1600 / pc, (900 - 36) / pc)),
		ui_backpack_shop_phone = UiExport.export(window(phone, true, 667 / 0.62, (375 - 36) / 0.62)),
	}
end

return Preview
