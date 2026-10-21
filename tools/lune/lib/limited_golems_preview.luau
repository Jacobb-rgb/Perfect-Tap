--[[
	The LIMITED EDITION banner picture (Config/LimitedGolems): the set's
	diorama, its 6 golems and the banner overlay, as the concept the owner
	picked (Dragonforge, 2026-10-20) and the look the shop's FEATURED banner
	is built after.

	  scene "limited_<SetId>" (Dragonforge) for tools/lune/export_scene.luau,
	  shots in tools/preview/limited_golems_shots.json (1600 x 900, the
	  scene's own camera):
	    the sky in the scene's own Surface preset (deep purple to crimson to
	    lava orange), a volcano with lava falls and an eruption, a cliff with
	    a lava waterfall into a glowing pool, a lava river, a huge moon with a
	    dragon flying across it and two more dragons far off, embers in the
	    air, dark rocks framing the corners, and a stage with the set's 6
	    golems built by the game's GolemBuilder (left to right: Epic,
	    Legendary | the MYTHIC on a pedestal, bigger | Epic, Rare, Rare).
	    The UI overlay "ui_limited_<SetId>" (the Pop kit): LIMITED EDITION,
	    the title, the tagline, the real end date (Current.EndsAt), each
	    golem's name, rarity and odds under its feet, and the four packs with
	    their Robux prices.
	  Everything at once (the picture, the golem and capsule icons, the
	  sheets in docs/screenshots/limited_golems/): bash tools/preview/limited_golems.sh
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local Enum = roblox.Enum
local rgb = Color3.fromRGB
local M = Enum.Material
local PI = math.pi

Preview.Width = 1600
Preview.Height = 900
Preview.Camera = { Position = Vector3.new(-1.5, 8.8, -46), Target = Vector3.new(-1.5, 10.2, 0), Fov = 40 }
Preview.StageTop = 1
Preview.ShardSpot = Vector3.new(-22, 15.5, -8) -- the floating shard (world -X = the picture's right)
Preview.PedestalTop = 2.8
-- where the set's golems stand: { index in the set, x, z, size }; the Mythic on its pedestal
-- (the camera looks along +Z: world -X is the picture's right)
Preview.Slots = {
	{ 2, -30.5, 9, 2.2 },
	{ 1, -21, 4.5, 2.2 },
	{ 3, -11.4, 1, 2.2 },
	{ 6, 0, -3.5, 2.9 },
	{ 5, 12.6, 1, 2.2 },
	{ 4, 24.5, 4.5, 2.2 },
}
Preview.Months = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

---------------------------------------------------------------- part helpers

type Kit = {
	Folder: any,
	CF: any,
	Rng: any,
	Geo: any,
}

local function new(kit: Kit, className: string, props: { [string]: any }): any
	local p = kit.Geo.make(className, props, kit.Folder)
	p.CastShadow = props.CastShadow == true
	p.CanCollide = false
	return p
end

local function block(kit: Kit, cf: any, size: any, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function ball(kit: Kit, pos: any, diameter: number, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		Shape = Enum.PartType.Ball,
		CFrame = kit.CF.new(pos),
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

-- an upright cylinder (Roblox cylinders run along X)
local function disc(kit: Kit, cf: any, height: number, diameter: number, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = cf * kit.CF.Angles(0, 0, PI / 2),
		Size = Vector3.new(height, diameter, diameter),
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function light(kit: Kit, pos: any, color: any, range: number, brightness: number)
	local holder = block(kit, kit.CF.new(pos), Vector3.new(0.2, 0.2, 0.2), color, nil, 1)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = holder
end

local function emitter(kit: Kit, pos: any, size: number, color: any, texture: string, name: string)
	local holder = block(kit, kit.CF.new(pos), Vector3.new(size, 1, size), color, nil, 1)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = roblox.ColorSequence.new(color)
	e.Parent = holder
end

-- a flat strip lying on the ground from a to b (rivers, cracks)
local function strip(kit: Kit, a: any, b: any, width: number, y: number, color: any, material: any?, transparency: number?): any
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = kit.CF.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	return block(kit, cf, Vector3.new(width, 0.08, length + width * 0.6), color, material, transparency)
end

---------------------------------------------------------------- the sets

-- (the exported helpers every backdrop uses: limited_backdrops/<Set>.luau)
export type Look = {
	Preset: { [string]: any }, -- the scene's Surface preset (sky, light, fog, colour)
	Stage: any, -- stage colour
	StageMaterial: any,
	Rim: any, -- the stage's glowing rim
	Pedestal: any,
}

Preview.Helpers = {
	block = block,
	ball = ball,
	disc = disc,
	light = light,
	emitter = emitter,
	strip = strip,
	rgb = rgb,
	M = M,
	PI = PI,
	Vector3 = Vector3,
	Color3 = Color3,
	Instance = Instance,
	Enum = Enum,
}

-- set id -> its backdrop (tools/lune/lib/limited_backdrops/<Set>.luau)
Preview.SetIds = { "Dragonforge", "Galaxy", "MechaNeon", "FrostTitans" }
local SETS: { [string]: (kit: Kit) -> Look } = {}
local BACKDROPS: { [string]: () -> any } = {
	Dragonforge = function()
		return require("./limited_backdrops/Dragonforge")
	end,
	Galaxy = function()
		return require("./limited_backdrops/Galaxy")
	end,
	MechaNeon = function()
		return require("./limited_backdrops/MechaNeon")
	end,
	FrostTitans = function()
		return require("./limited_backdrops/FrostTitans")
	end,
}
for _, id in Preview.SetIds do
	local ok, backdrop = pcall(BACKDROPS[id])
	if ok and type(backdrop) == "function" then
		SETS[id] = function(kit: Kit): Look
			return backdrop(kit, Preview.Helpers)
		end
	end
end

-- A set's banner data, on sale (LimitedGolems + its capsule) or upcoming
-- (Config/LimitedUpcoming: the usual odds and prices, "COMING SOON").
function Preview.setData(Loader: any, setId: string): { [string]: any }
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local LimitedUpcoming = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedUpcoming")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local live = LimitedGolems.Sets[setId]
	if live then
		local capsule = CapsuleConfig.ById[live.CapsuleId]
		local prices = {}
		for _, count in { 1, 3, 10, 50 } do
			prices[count] = MonetizationConfig.get(CapsuleConfig.product(live.CapsuleId, count) :: string).Robux
		end
		return {
			Id = setId,
			Title = live.Title,
			Tagline = live.Tagline,
			Backdrop = live.Backdrop,
			CapsuleId = live.CapsuleId,
			Golems = LimitedGolems.golems(setId),
			Odds = capsule.Odds,
			Prices = prices,
			EndsAt = if LimitedGolems.Current.Id == setId then LimitedGolems.Current.EndsAt else nil,
		}
	end
	local set = LimitedUpcoming.Sets[setId]
	assert(set, "unknown limited set " .. tostring(setId))
	local odds = {}
	for i, g in set.Golems do
		odds[g.Id] = ({ 0.34, 0.28, 0.2, 0.12, 0.05, 0.01 })[i]
	end
	return {
		Id = setId,
		Title = set.Title,
		Tagline = set.Tagline,
		Backdrop = set.Backdrop,
		CapsuleId = nil,
		Golems = set.Golems,
		Odds = odds,
		Prices = { [1] = 99, [3] = 249, [10] = 799, [50] = 3499 },
		EndsAt = nil,
	}
end

---------------------------------------------------------------- the scene

-- Where the set's golems stand (feet CFrames, facing the camera a little inward).
function Preview.golemFrames(CF: any): { { Index: number, Feet: any, Size: number } }
	local out = {}
	local cam = Preview.Camera.Position
	for _, slot in Preview.Slots do
		local y = if slot[1] == 6 then Preview.PedestalTop else Preview.StageTop
		local pos = Vector3.new(slot[2], y, slot[3])
		local look = Vector3.new(cam.X + slot[2] * 0.3, y, cam.Z)
		table.insert(out, { Index = slot[1], Feet = CF.lookAt(pos, look), Size = slot[4] })
	end
	return out
end

-- Builds scene "limited_<setId>"; returns the scene's Surface preset and camera.
function Preview.build(Loader: any, workspace: any, setId: string, backdropOnly: boolean?): ({ [string]: any }, { [string]: any })
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local data = Preview.setData(Loader, setId)
	local golems = data.Golems
	assert(#golems == 6 and SETS[setId], "unknown limited set " .. tostring(setId))

	local folder = Instance.new("Model")
	folder.Name = "Limited" .. setId
	folder.Parent = workspace
	local kit: Kit = { Folder = folder, CF = CF, Rng = Rng.new(2026), Geo = Geo }
	local look = SETS[setId](kit)

	-- the stage: a wide platform with a glowing front rim, the Mythic's round pedestal
	local top = Preview.StageTop
	block(kit, CF.new(0, top / 2, 5), Vector3.new(84, top, 26), look.Stage, look.StageMaterial).CastShadow = false
	block(kit, CF.new(0, top + 0.02, -8.05), Vector3.new(84, 0.06, 0.16), look.Rim, M.Neon)
	local pedestal = Preview.PedestalTop - top
	disc(kit, CF.new(0, top + pedestal / 2, -3.5), pedestal, 11, look.Pedestal, look.StageMaterial)
	disc(kit, CF.new(0, Preview.PedestalTop - 0.25, -3.5), 0.12, 11.2, look.Rim, M.Neon)
	-- soft lights on the golems' faces
	light(kit, Vector3.new(0, 18, -22), rgb(255, 255, 255), 40, 0.7)
	light(kit, Vector3.new(-22, 12, -14), rgb(255, 255, 255), 34, 1.0)
	light(kit, Vector3.new(22, 12, -14), rgb(255, 255, 255), 34, 1.0)

	-- (backdropOnly: the shop banner's painted background, banner_<Set>.png:
	-- the shop draws its own golem tiles and the shard over it)
	for _, g in if backdropOnly then {} else Preview.golemFrames(CF) do
		GolemBuilder.build(golems[g.Index].Id, g.Feet, { Size = g.Size }).Parent = folder
	end
	-- the set's SHARD floating high on the picture's right (under the end
	-- date, where the shop's banner shows it), turned to the camera
	if backdropOnly then
		return look.Preset,
			{
				camera = { Preview.Camera.Position.X, Preview.Camera.Position.Y, Preview.Camera.Position.Z },
				target = { Preview.Camera.Target.X, Preview.Camera.Target.Y, Preview.Camera.Target.Z },
				fov = Preview.Camera.Fov,
			}
	end
	local spot = Preview.ShardSpot
	local shardCf = CF.new(spot) * CF.Angles(0.12, 0.35, -0.08)
	local shard = if data.CapsuleId
		then GolemBuilder.capsule(data.CapsuleId, shardCf)
		else GolemBuilder.shard(setId, shardCf, data.Backdrop.Ground, data.Backdrop.Accent)
	shard.Parent = folder
	light(kit, spot + Vector3.new(2, 1, -5), data.Backdrop.Accent, 14, 1.4)
	return look.Preset,
		{
			camera = { Preview.Camera.Position.X, Preview.Camera.Position.Y, Preview.Camera.Position.Z },
			target = { Preview.Camera.Target.X, Preview.Camera.Target.Y, Preview.Camera.Target.Z },
			fov = Preview.Camera.Fov,
		}
end

-- Builds scene "limitedshard_<setId>": the set's SHARD (GolemBuilder.shard)
-- on the Mythic's pedestal, a cracked one shaking on the left, a burst one
-- on the right with the Mythic stepping out; returns the preset and camera.
function Preview.buildShard(Loader: any, workspace: any, setId: string): ({ [string]: any }, { [string]: any })
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	assert(SETS[setId], "unknown limited set " .. tostring(setId))
	local data = Preview.setData(Loader, setId)
	local function shard(cf: any): any
		if data.CapsuleId then
			return GolemBuilder.capsule(data.CapsuleId, cf)
		end
		return GolemBuilder.shard(setId, cf, data.Backdrop.Ground, data.Backdrop.Accent)
	end
	local folder = Instance.new("Model")
	folder.Name = "Shard" .. setId
	folder.Parent = workspace
	local kit: Kit = { Folder = folder, CF = CF, Rng = Rng.new(2026), Geo = Geo }
	local look = SETS[setId](kit)
	local top = Preview.StageTop
	block(kit, CF.new(0, top / 2, 5), Vector3.new(84, top, 26), look.Stage, look.StageMaterial).CastShadow = false
	block(kit, CF.new(0, top + 0.02, -8.05), Vector3.new(84, 0.06, 0.16), look.Rim, M.Neon)
	local pedestal = Preview.PedestalTop - top
	disc(kit, CF.new(0, top + pedestal / 2, -3.5), pedestal, 6, look.Pedestal, look.StageMaterial)
	disc(kit, CF.new(0, Preview.PedestalTop - 0.25, -3.5), 0.12, 6.2, look.Rim, M.Neon)
	light(kit, Vector3.new(0, 14, -16), rgb(255, 255, 255), 30, 0.8)
	light(kit, Vector3.new(-12, 9, -10), rgb(255, 255, 255), 24, 1.0)
	light(kit, Vector3.new(12, 9, -10), rgb(255, 255, 255), 24, 1.0)
	local r = 1.25
	-- the hero shard on the pedestal, turned a little to the camera
	shard(CF.new(0, Preview.PedestalTop + r, -3.5) * CF.Angles(0, 0.25, 0)).Parent = folder
	-- right (on screen): shaking, its cracks lit
	local cracked = shard(CF.new(5.2, top + r, -6.5) * CF.Angles(0, -0.5, 0.12))
	for _, d in cracked:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Crack" then
			d.Transparency = 0
		end
	end
	cracked.Parent = folder
	-- left (on screen): burst open, the Mythic stepping out of the lower shell
	local burst = shard(CF.new(-5.4, top + r, -6.5) * CF.Angles(0, 0.4, 0))
	local upper = burst:FindFirstChild("Top")
	if upper then
		upper:PivotTo(CF.new(-7.4, top + r + 3.6, -6.0) * CF.Angles(0.3, 0.6, 0.9))
	end
	burst.Parent = folder
	local mythic = data.Golems[6]
	if mythic then
		GolemBuilder.build(mythic.Id, CF.new(-5.4, top + 0.7, -6.7) * CF.Angles(0, 0.35, 0), { Size = 0.8 }).Parent = folder
	end
	return look.Preset, {
		camera = { 0, 5.8, -21 },
		target = { 0, 4.0, 0 },
		fov = 40,
	}
end

-- The set's data for the picture sheet (tools/preview/limited_sheet.mjs):
-- build/preview/limited_<setId>_info.json.
function Preview.info(Loader: any, setId: string): { [string]: any }
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local set = Preview.setData(Loader, setId)
	local golems = {}
	for _, g in set.Golems do
		local c = Rarity.ById[g.Rarity].Color
		table.insert(golems, {
			Id = g.Id,
			Name = g.Name,
			Rarity = g.Rarity,
			Odds = set.Odds[g.Id],
			Bonus = if GolemConfig.ById[g.Id] then GolemConfig.describe(g.Id) else "",
			Color = string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)),
		})
	end
	return { Id = setId, Title = set.Title, Tagline = set.Tagline, CapsuleId = set.CapsuleId or ("shard_" .. setId), Golems = golems }
end

---------------------------------------------------------------- the overlay

-- A world point -> render pixels (the scene camera).
function Preview.project(CF: any, point: any): (number, number)
	local cam = CF.lookAt(Preview.Camera.Position, Preview.Camera.Target)
	local p = cam:PointToObjectSpace(point)
	local depth = -p.Z
	local tanY = math.tan(math.rad(Preview.Camera.Fov) / 2)
	local tanX = tanY * Preview.Width / Preview.Height
	return Preview.Width / 2 + p.X / depth / tanX * Preview.Width / 2, Preview.Height / 2 - p.Y / depth / tanY * Preview.Height / 2
end

-- The overlay "ui_limited_<setId>": the exported ScreenGui list.
function Preview.ui(Loader: any, setId: string): any
	local CF = Loader.CFrame
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local set = Preview.setData(Loader, setId)
	local golems = set.Golems

	local gui = Instance.new("ScreenGui")
	gui.Name = "LimitedBanner"
	gui.IgnoreGuiInset = true
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	-- LIMITED EDITION over the title, the tagline under it, the real end date
	Pop.title(root, set.Title, 108, set.Backdrop.Title, {
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 116),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Pop.tag(root, "LIMITED EDITION GOLEMS", "Red", Vector2.new(400, 46), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 44),
		Rotation = -3,
	})
	Pop.text(root, set.Tagline, 34, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local ends = if set.EndsAt then os.date("!*t", set.EndsAt) :: any else nil
	local endsText = if ends then `ENDS {Preview.Months[ends.month]} {ends.day}` else "COMING SOON"
	Pop.tag(root, endsText, "Night", Vector2.new(210, 44), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 28),
	})

	-- each golem's name, rarity and odds under its feet
	for _, g in Preview.golemFrames(CF) do
		local golem = golems[g.Index]
		local info = Rarity.ById[golem.Rarity]
		local mythic = golem.Rarity == "Mythic"
		local px, py = Preview.project(CF, g.Feet.Position + Vector3.new(0, 0, -2.4))
		local w, h = if mythic then 240 else 180, if mythic then 76 else 58
		local plate = Instance.new("Frame")
		plate.Name = "Odds" .. golem.Id
		plate.AnchorPoint = Vector2.new(0.5, 0)
		plate.Position = UDim2.fromOffset(math.floor(px + 0.5), math.floor(py + 6))
		plate.Size = UDim2.fromOffset(w, h)
		plate.Parent = root
		Pop.face(plate, { Top = rgb(40, 40, 52), Bottom = rgb(16, 16, 24), Edge = PopTheme.Outline }, 12, false)
		plate.BackgroundTransparency = 0.12
		Pop.text(plate, golem.Name, if mythic then 24 else 19, {
			Position = UDim2.fromOffset(0, if mythic then 5 else 4),
			Size = UDim2.new(1, 0, 0, if mythic then 28 else 22),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local percent = string.format("%g%%", set.Odds[golem.Id] * 100)
		Pop.title(
			plate,
			string.upper(info.Name) .. "  " .. percent,
			if mythic then 30 else 22,
			{ info.Color:Lerp(Color3.new(1, 1, 1), 0.45), info.Color },
			{
				Position = UDim2.fromOffset(0, if mythic then 36 else 28),
				Size = UDim2.new(1, 0, 0, if mythic then 34 else 26),
				TextXAlignment = Enum.TextXAlignment.Center,
			}
		)
	end

	-- the four packs: how many golems, the Robux price
	local packs = Instance.new("Frame")
	packs.Name = "Packs"
	packs.BackgroundTransparency = 1
	packs.AnchorPoint = Vector2.new(0.5, 1)
	packs.Position = UDim2.new(0.5, 0, 1, -10)
	packs.Size = UDim2.fromOffset(4 * 170 + 3 * 22, 84)
	packs.Parent = root
	for i, count in { 1, 3, 10, 50 } do
		local x = (i - 1) * 192
		Pop.text(packs, if count == 1 then "1 GOLEM" else `{count} GOLEMS`, 20, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(170, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Pop.price(packs, set.Prices[count], Vector2.new(170, 54), {
			Position = UDim2.fromOffset(x, 30),
		})
	end
	return UiExport.export({ gui })
end

return Preview
