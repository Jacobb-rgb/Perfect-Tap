--[[
	Hoverboard preview pictures (mine floors point 3, PHASE 1 models):
	  scene "hoverboards"       (lune run tools/lune/export_scene.luau hoverboards)
	    - the showroom: the 5 boards (HoverboardBuilder) floating over pedestals
	      on a round stage, coin boards on the left, the Robux boards on the
	      right under a glowing ROBUX arch, a sign in front of each (name,
	      price, speed and a 5-step speed bar), a HOVERBOARDS sign behind
	    - close-ups: each Robux board banking through a turn at COMET_AT /
	      PHOENIX_AT with its HoverboardFx effects drawn as stand-ins
	    - a lineup of all 5 boards in a row (LINEUP_AT) for the size check
	  scene "hoverboard_ride"   (lune run tools/lune/export_scene.luau hoverboard_ride)
	    the Greystone Quarry floor (mine_floor_scene 1) with a blocky rider on
	    the Timber Drifter racing down the main path to the Ember Caves tunnel
	    and two friends ahead on the Robux boards (effects as stand-ins): the
	    player's own camera, also the phone-size frame
	  scene "hoverboard_hero"   the same three riders coming out of the quarry gate
	    toward the camera (the "first sight" picture)
	Shots: tools/preview/hoverboard_shots.json. The renderer can't draw Trails
	or emitters inside Attachments, so effectStandIns turns each trail into a
	fading neon ribbon along the flight path and each emitter into small
	"Gun" sparkle boxes (tools/lune/lib/export.luau).
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local NEON = Enum.Material.Neon

Preview.COMET_AT = V3.new(140, 0, 0)
Preview.PHOENIX_AT = V3.new(220, 0, 0)
Preview.CUSTOM_RIDE_AT = V3.new(0, 0, 220)
Preview.LINEUP_AT = V3.new(0, 0, 120)
Preview.RIDE_VIEWER = V3.new(1.5, 7.5, 10.5) -- the ride shots' camera (trail ribbons face it)
Preview.HERO_VIEWER = V3.new(0, 7.5, 31.5) -- the hero shot's camera

local CF: any
local Builder: any
local Fx: any
local Pose: any
local Data: any
local Format: any

local function init(Loader: any)
	CF = Loader.CFrame
	Builder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardBuilder")
	Fx = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardFx")
	Data = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	Pose = Loader.requirePath("ReplicatedStorage.Shared.Moves.BoardPose")
	Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
end

local function part(parent: any, cf: any, size: any, color: any, material: any?, shape: string?, transparency: number?): any
	local p = roblox.Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	if transparency then
		p.Transparency = transparency
	end
	p.Parent = parent
	return p
end

-- A disc standing on Y (center cf).
local function disc(parent: any, cf: any, diameter: number, thick: number, color: any, material: any?, transparency: number?): any
	return part(parent, cf * CF.Angles(0, 0, math.pi / 2), V3.new(thick, diameter, diameter), color, material, "Cylinder", transparency)
end

-- Text on the +Z face of a nearly invisible plate (the renderer fits the text into the plate).
local function text(parent: any, cf: any, w: number, h: number, str: string, color: any, font: any?, selfLit: boolean?): any
	local plate = part(parent, cf, V3.new(w, h, 0.04), C3.new(0, 0, 0), nil, nil, 0.97)
	plate.CastShadow = false
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	if selfLit then
		gui.LightInfluence = 0
	end
	gui.Parent = plate
	local label = roblox.Instance.new("TextLabel")
	label.Text = str
	label.TextColor3 = color
	label.FontFace = roblox.Font.fromEnum(font or Enum.Font.FredokaOne)
	label.Parent = gui
	return plate
end

local function lamp(parent: any, position: any, color: any, range: number, brightness: number)
	local p = part(parent, CF.new(position.X, position.Y, position.Z), V3.new(0.2, 0.2, 0.2), color, nil, nil, 1)
	local l = roblox.Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

local function boardAt(parent: any, boardId: string, cf: any): any
	local model = Builder.build(boardId)
	model:PivotTo(cf)
	model.Parent = parent
	return model
end

local function worldOf(model: any, name: string): any
	local root = model.PrimaryPart
	local a = root:FindFirstChild(name)
	return root.CFrame * a.CFrame
end

local function keyColors(sequence: any): { any }
	local list = {}
	for _, k in sequence.Keypoints do
		table.insert(list, k.Value)
	end
	return list
end

local function colorAt(list: { any }, t: number): any
	if #list == 1 then
		return list[1]
	end
	local x = math.clamp(t, 0, 1) * (#list - 1)
	local i = math.min(#list - 2, math.floor(x))
	return list[i + 1]:Lerp(list[i + 2], x - i)
end

local function sparkleBox(parent: any, position: any, size: number, color: any, kind: string)
	local p = part(parent, CF.new(position.X, position.Y, position.Z), V3.new(size, size, size), color, nil, nil, 1)
	local e = roblox.Instance.new("ParticleEmitter")
	e.Name = kind
	e.Color = roblox.ColorSequence.new(color)
	e.Parent = p
end

--[[
	Draws a board's effect set for the renderer. `path(d)` gives the world
	position of the board's tail line `d` studs back along its flight (d = 0 at
	the board); trail ribbons turn their face to `viewer` (Trail.FaceCamera).
]]
local function effectStandIns(parent: any, model: any, boardId: string, path: (number) -> any, viewer: any, length: number?): any
	local set = Fx.create(boardId)
	if not set then
		return nil
	end
	local folder = roblox.Instance.new("Model")
	folder.Name = "FxStandIns"
	folder.Parent = parent
	local left, right = worldOf(model, "TrailLeft").Position, worldOf(model, "TrailRight").Position
	local width = (right - left).Magnitude
	for _, trail in set.Trails do
		local list = keyColors(trail.Color)
		local len = length or trail.Lifetime * 26 -- studs the trail covers at ride speed
		local n = 28
		for i = 1, n do
			local t0, t1 = (i - 1) / n, i / n
			local a, b = path(t0 * len), path(t1 * len)
			local mid = (a + b) / 2
			local w = width * (1 - 0.8 * (t0 + t1) / 2)
			-- Trail.FaceCamera: the ribbon turns its face to the viewer
			local along = (b - a).Unit
			local toViewer = viewer - mid
			local up = (toViewer - along * toViewer:Dot(along)).Unit
			local cf = CF.lookAt(mid, b, up)
			part(
				folder,
				cf,
				V3.new(w, 0.05, (b - a).Magnitude + 0.08),
				colorAt(list, (t0 + t1) / 2),
				NEON,
				nil,
				math.min(0.9, 0.15 + 0.8 * t0)
			)
		end
	end
	for _, e in set.Emitters do
		local mount = e:GetAttribute("Mount")
		local at = worldOf(model, mount).Position
		local list = keyColors(e.Color)
		local flame = e.Texture == Fx.Fire
		local kind = if flame then "GunFlame" else "GunSpark"
		if e.LightEmission < 0.5 then
			-- dust: a few soft grey puffs just above the ground behind the board
			for k, d in { 0.6, 1.8, 3.2 } do
				local p = path(d) + (at - path(0)) + V3.new(0, -0.35, 0)
				sparkleBox(folder, p, 0.5 + d * 0.2, colorAt(list, (k - 1) / 2), "GunSpark")
			end
		elseif string.sub(mount, 1, 7) == "Exhaust" then
			for k, d in { 0.3, 1.2, 2.4, 3.8 } do
				local p = path(d) + (at - path(0))
				sparkleBox(folder, p, 0.35 + d * 0.22, colorAt(list, (k - 1) / 3), kind)
			end
		elseif mount == "Pad" then
			-- drips / star dust falling behind the board
			for k, d in { 0.4, 1.4, 2.6 } do
				local p = path(d) + (at - path(0)) + V3.new(0, -0.25 * k, 0)
				sparkleBox(folder, p, 0.3, colorAt(list, (k - 1) / 2), kind)
			end
		elseif mount == "Aura" then
			sparkleBox(folder, at + V3.new(0, 0.6, 0), 2.6, list[1], kind)
		elseif string.sub(mount, 1, 3) == "Tip" and flame then
			-- wings of fire: flames rising off the tips
			sparkleBox(folder, at + V3.new(0, 0.3, 0), 0.6, colorAt(list, 0.2), kind)
			sparkleBox(folder, at + V3.new(0, 0.9, 0), 0.45, colorAt(list, 0.6), kind)
		else
			sparkleBox(folder, at, 0.6, colorAt(list, 0.3), kind)
		end
	end
	return set
end

-- Draws one burst of a board's effect set ("Start": a splash ring on the ground
-- under the pad; "Boost": a cone out of the exhausts / a flare up through the rider).
local function burstStandIns(parent: any, model: any, set: any, kind: string, path: (number) -> any)
	for _, e in set.Bursts do
		if e:GetAttribute("Burst") ~= kind then
			continue
		end
		local mount = e:GetAttribute("Mount")
		local at = worldOf(model, mount).Position
		local list = keyColors(e.Color)
		local style = if e.Texture == Fx.Fire then "GunFlame" else "GunSpark"
		if mount == "Pad" then
			local n = 10
			for i = 1, n do
				local a = (i - 1) / n * math.pi * 2
				local r = 2.2 + (i % 2) * 0.5
				local p = V3.new(at.X + math.cos(a) * r, at.Y - 0.3, at.Z + math.sin(a) * r)
				sparkleBox(parent, p, 0.55, colorAt(list, (i - 1) / (n - 1)), style)
			end
		elseif string.sub(mount, 1, 7) == "Exhaust" then
			for k, d in { 1.2, 2.6, 4.2 } do
				local p = path(d) + (at - path(0))
				sparkleBox(parent, p, 0.5 + d * 0.35, colorAt(list, (k - 1) / 2), style)
			end
		elseif mount == "Aura" then
			sparkleBox(parent, at + V3.new(0, 1.6, 0), 2.2, colorAt(list, 0.2), style)
			sparkleBox(parent, at + V3.new(0, 3.4, 0), 1.6, colorAt(list, 0.6), style)
		else
			sparkleBox(parent, at, 1.6, colorAt(list, 0), style)
		end
	end
end

---------------------------------------------------------------- showroom

local STONE = C3.fromRGB(120, 112, 124)
local STONE_DARK = C3.fromRGB(72, 66, 78)
local COPPER = C3.fromRGB(206, 116, 60)
local GOLD = C3.fromRGB(246, 188, 62)
local VIOLET = C3.fromRGB(92, 44, 168)
local INK = C3.fromRGB(255, 244, 228)
local COIN = C3.fromRGB(255, 206, 72)
local ROBUX_GREEN = C3.fromRGB(110, 230, 120)

-- A pedestal with its top at `top` (world height); Robux pedestals are royal.
local function pedestal(parent: any, at: any, top: number, board: any)
	local robux = board.Kind == "Robux"
	local glow = board.Colors.Glow
	local base = if robux then VIOLET:Lerp(C3.new(0, 0, 0), 0.25) else STONE_DARK
	local column = if robux then VIOLET else STONE
	local band = if robux then GOLD else COPPER
	disc(parent, CF.new(at.X, 0.35, at.Z), 4.6, 0.7, base)
	disc(parent, CF.new(at.X, 0.72, at.Z), 4.2, 0.08, band, Enum.Material.Metal)
	local colH = top - 1.2
	disc(parent, CF.new(at.X, 0.7 + colH / 2, at.Z), 3.0, colH, column)
	disc(parent, CF.new(at.X, top - 0.65, at.Z), 3.3, 0.16, band, Enum.Material.Metal)
	disc(parent, CF.new(at.X, top - 0.25, at.Z), 4.0, 0.5, base)
	disc(parent, CF.new(at.X, top + 0.02, at.Z), 3.6, 0.06, glow, NEON)
	disc(parent, CF.new(at.X, top + 0.05, at.Z), 3.1, 0.07, base:Lerp(C3.new(0, 0, 0), 0.3))
	if robux then
		-- crystals at the foot and gold rings
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local p = at + V3.new(math.cos(a) * 2.2, 0.7, math.sin(a) * 2.2)
			part(
				parent,
				CF.new(p.X, p.Y + 0.5, p.Z) * CF.Angles(0.25 * math.cos(a), a, 0.25 * math.sin(a)) * CF.Angles(0, math.pi / 4, 0),
				V3.new(0.4, 1.3, 0.4),
				glow,
				NEON
			)
		end
		disc(parent, CF.new(at.X, 0.27, at.Z), 6.0, 0.04, glow, NEON, 0.3)
	end
	lamp(parent, V3.new(at.X, top + 0.6, at.Z), glow, 9, if robux then 1.6 else 1.1)
end

-- The sign in front of a pedestal: name, price chip, speed and a 5-step bar.
local function sign(parent: any, at: any, board: any)
	local robux = board.Kind == "Robux"
	local tilt = CF.new(at.X, 1.25, at.Z + 3.4) * CF.Angles(-0.42, 0, 0)
	local plateColor = if robux then C3.fromRGB(40, 22, 70) else C3.fromRGB(46, 32, 28)
	local frame = if robux then GOLD else COPPER
	part(parent, CF.new(at.X, 0.2, at.Z + 3.6), V3.new(0.5, 0.4, 0.3), frame, Enum.Material.Metal)
	part(parent, tilt, V3.new(4.4, 2.3, 0.18), frame, Enum.Material.Metal)
	part(parent, tilt * CF.new(0, 0, 0.06), V3.new(4.15, 2.05, 0.1), plateColor)
	text(
		parent,
		tilt * CF.new(0, 0.58, 0.14),
		3.9,
		0.66,
		string.upper(board.Name),
		if robux then GOLD else INK,
		Enum.Font.LuckiestGuy,
		true
	)
	local price = if robux then `{board.Robux} R$` else Format.money(board.Price)
	text(parent, tilt * CF.new(-0.95, -0.12, 0.14), 1.8, 0.5, price, if robux then ROBUX_GREEN else COIN, Enum.Font.FredokaOne, true)
	text(parent, tilt * CF.new(1.0, -0.12, 0.14), 1.8, 0.46, `SPEED {board.Speed}`, INK, Enum.Font.FredokaOne, true)
	-- speed bar: 5 steps, lit up to the board's order
	for k = 1, 5 do
		local lit = k <= board.Order
		local color = if lit then board.Colors.Glow else C3.fromRGB(30, 26, 34)
		part(parent, tilt * CF.new(-1.6 + (k - 1) * 0.8, -0.7, 0.12), V3.new(0.66, 0.2, 0.06), color, if lit then NEON else nil)
	end
end

local function showroom(parent: any)
	local root = roblox.Instance.new("Model")
	root.Name = "HoverboardShowroom"
	root.Parent = parent
	-- grass and the round stage of two-tone tiles
	part(root, CF.new(0, -0.5, 0), V3.new(240, 1, 240), C3.fromRGB(96, 168, 70))
	disc(root, CF.new(0, 0.05, -2), 50, 0.3, STONE_DARK)
	local tiles = { C3.fromRGB(160, 150, 156), C3.fromRGB(136, 126, 136) }
	for ix = -11, 11 do
		for iz = -12, 6 do
			local x, z = ix * 2, iz * 2
			if x * x + (z + 2) ^ 2 < 23 * 23 then
				part(root, CF.new(x, 0.22, z), V3.new(1.94, 0.06, 1.94), tiles[(ix + iz) % 2 + 1])
			end
		end
	end
	disc(root, CF.new(0, 0.08, -2), 50.8, 0.2, COPPER, Enum.Material.Metal)
	-- the back wall with the HOVERBOARDS sign
	local wallZ = -15
	part(root, CF.new(0, 3.5, wallZ), V3.new(44, 7, 2), STONE)
	part(root, CF.new(0, 7.3, wallZ), V3.new(45, 0.6, 2.4), STONE_DARK)
	for _, x in { -22, -11, 0, 11, 22 } do
		part(root, CF.new(x, 3.9, wallZ + 0.8), V3.new(1.4, 7.8, 1.2), STONE_DARK)
	end
	for _, x in { -8, 8 } do
		part(root, CF.new(x, 9, wallZ + 0.2), V3.new(0.7, 4, 0.7), STONE_DARK)
	end
	part(root, CF.new(0, 11.4, wallZ + 0.4), V3.new(24, 4.2, 0.6), C3.fromRGB(46, 32, 28))
	part(root, CF.new(0, 11.4, wallZ + 0.15), V3.new(24.8, 5.0, 0.4), COPPER, Enum.Material.Metal)
	text(root, CF.new(0, 11.5, wallZ + 0.75), 22, 3.1, "HOVERBOARDS", C3.fromRGB(255, 176, 64), Enum.Font.LuckiestGuy, true)
	-- lay out: coin boards left, Robux boards right
	local spots = {
		{ x = -13.6, z = -2.6, top = 2.4 },
		{ x = -7.7, z = -4.2, top = 2.6 },
		{ x = -1.8, z = -5.2, top = 2.8 },
		{ x = 5.4, z = -5.2, top = 3.4 },
		{ x = 12.6, z = -3.6, top = 3.6 },
	}
	for i, board in Data.List do
		local spot = spots[i]
		local at = V3.new(spot.x, 0, spot.z)
		pedestal(root, at, spot.top, board)
		sign(root, at, board)
		-- the board floats over its pedestal, nose toward the camera's side, deck tilted to the camera
		local yaw = (math.pi - 0.8) * (if board.Kind == "Robux" then -1 else 1)
		local cf = CF.new(at.X, spot.top + 0.25, at.Z) * CF.Angles(0.3, 0, 0) * CF.Angles(0, yaw, 0) * CF.Angles(0.08, 0, 0)
		boardAt(root, board.Id, cf)
	end
	-- the COINS sign over the coin side (wood), the ROBUX arch over the Robux side (glow)
	local woodSign = CF.new(-4.6, 6.4, -10)
	part(root, woodSign, V3.new(11, 2, 0.4), C3.fromRGB(120, 76, 44), Enum.Material.Wood)
	for _, x in { -9.5, 0.3 } do
		part(root, CF.new(x, 3.2, -10.2), V3.new(0.5, 6.4, 0.5), C3.fromRGB(92, 58, 34), Enum.Material.Wood)
	end
	text(root, woodSign * CF.new(0, 0, 0.23), 8, 1.6, "COINS", COIN, Enum.Font.LuckiestGuy, true)
	local archZ = -9.6
	for _, x in { 8.4, 16.8 } do
		part(root, CF.new(x, 3.6, archZ), V3.new(0.9, 7.2, 0.9), GOLD, Enum.Material.Metal)
		part(root, CF.new(x, 3.6, archZ), V3.new(0.5, 7.4, 1.0), C3.fromRGB(176, 80, 255), NEON)
	end
	local robuxSign = CF.new(12.6, 7.0, archZ)
	part(root, robuxSign, V3.new(8.4, 2.6, 0.5), C3.fromRGB(40, 22, 70))
	part(root, robuxSign * CF.new(0, 0, -0.1), V3.new(9.2, 3.2, 0.4), GOLD, Enum.Material.Metal)
	part(root, robuxSign * CF.new(0, 1.42, 0.1), V3.new(8.6, 0.14, 0.2), C3.fromRGB(255, 110, 200), NEON)
	part(root, robuxSign * CF.new(0, -1.42, 0.1), V3.new(8.6, 0.14, 0.2), C3.fromRGB(70, 186, 255), NEON)
	text(root, robuxSign * CF.new(0, 0.1, 0.28), 7, 1.9, "ROBUX", ROBUX_GREEN, Enum.Font.LuckiestGuy, true)
	lamp(root, V3.new(12.6, 6.5, -7), C3.fromRGB(255, 160, 230), 18, 1.4)
	lamp(root, V3.new(-7.7, 6, -7), C3.fromRGB(255, 196, 120), 16, 0.9)
end

---------------------------------------------------------------- close-ups

-- A board banking through a left turn at `at`, its effects streaming behind it.
local function closeUp(parent: any, boardId: string, at: any, viewer: any)
	local root = roblox.Instance.new("Model")
	root.Name = "CloseUp" .. boardId
	root.Parent = parent
	-- a dark studio: a round floor with glow rings and a ring of tall panels, so the glow pops
	local glowColor = Data.get(boardId).Colors.Glow
	local dark = if boardId == "RoyalPhoenix" then C3.fromRGB(58, 44, 86) else C3.fromRGB(44, 40, 72)
	disc(root, CF.new(at.X, -0.25, at.Z), 44, 0.5, dark)
	for k, r in { 7, 12.5 } do
		disc(root, CF.new(at.X, 0.02 + k * 0.01, at.Z), r * 2, 0.04, glowColor, NEON, 0.55)
		disc(root, CF.new(at.X, 0.03 + k * 0.01, at.Z), r * 2 - 0.5, 0.05, dark)
	end
	for k = 0, 23 do
		local a = k * math.pi / 12
		local p = at + V3.new(math.cos(a) * 20, 4, math.sin(a) * 20)
		part(root, CF.lookAt(p, V3.new(at.X, 4, at.Z)), V3.new(5.4, 8, 0.6), dark:Lerp(C3.new(0, 0, 0), 0.25 - 0.08 * (k % 2)))
		if k % 2 == 0 then
			part(root, CF.lookAt(p, V3.new(at.X, 4, at.Z)) * CF.new(0, 0, -0.35), V3.new(0.18, 7.4, 0.1), glowColor, NEON, nil, 0.3)
		end
	end
	local bank, height = if boardId == "RoyalPhoenix" then 0.1 else 0.32, 2.6
	-- flight path: the board flies toward -X, curving; d studs back along the path
	local radius = 22
	local center = at + V3.new(0, height, -radius)
	local function path(d: number): any
		local a = d / radius
		return center + V3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
	end
	local function tangentBack(d: number): any
		local a = d / radius
		return V3.new(math.cos(a), 0, -math.sin(a))
	end
	local pos = path(0)
	local back = tangentBack(0)
	-- board frame: front = -back, banked into the turn (left = toward the center)
	local cf = CF.lookAt(pos, pos - back) * CF.Angles(0, 0, bank) * CF.Angles(0.06, 0, 0)
	local model = boardAt(root, boardId, cf)
	local tailOffset = (worldOf(model, "TrailLeft").Position + worldOf(model, "TrailRight").Position) / 2 - pos
	local function trailPath(d: number): any
		return path(d) + tailOffset
	end
	effectStandIns(root, model, boardId, trailPath, viewer, 13)
	local glow = Data.get(boardId).Colors.Glow
	lamp(root, pos + V3.new(0, -1, 0), glow, 10, 1.2)
	lamp(root, viewer + V3.new(0, 1, 0), C3.fromRGB(255, 236, 214), 18, 0.6)
	return model
end

-- All 5 boards side by side, noses toward -Z, for the size / readability check.
local function lineup(parent: any)
	local root = roblox.Instance.new("Model")
	root.Name = "Lineup"
	root.Parent = parent
	local at = Preview.LINEUP_AT
	part(root, CF.new(at.X, -0.5, at.Z), V3.new(60, 1, 30), C3.fromRGB(150, 140, 146))
	for i, board in Data.List do
		local x = at.X + (i - 3) * 6.2
		boardAt(root, board.Id, CF.new(x, 0, at.Z) * CF.Angles(0, 0.35, 0))
		text(root, CF.new(x, 0.05, at.Z + 4.4) * CF.Angles(-math.pi / 2, 0, 0), 5.4, 0.9, board.Name, INK, Enum.Font.FredokaOne)
	end
end

---------------------------------------------------------------- rider

local SKIN = C3.fromRGB(236, 190, 150)

--[[
	A blocky rider (tools/lune/lib/dummy.luau proportions) standing on a board's
	Feet attachment in a riding pose: feet apart, knees and hips bent a little,
	leaning into the ride, arms out for balance.
]]
local function rider(parent: any, feet: any, colors: any)
	local m = roblox.Instance.new("Model")
	m.Name = "Rider"
	m.Parent = parent
	local shirt, pants, hair = colors.shirt, colors.pants, colors.hair
	local lean = feet * CF.Angles(-0.12, 0, 0) -- lean forward (-Z)
	local function legBlock(side: number, angle: number)
		local hip = feet * CF.new(side * 0.5, 2, 0)
		local cf = hip * CF.Angles(angle, 0, side * -0.06) * CF.new(0, -1, 0)
		part(m, cf, V3.new(0.95, 2, 0.95), pants)
	end
	legBlock(-1, 0.18)
	legBlock(1, -0.22)
	local hips = feet * CF.new(0, 1.95, 0)
	local torso = hips * CF.Angles(-0.16, 0, 0) * CF.new(0, 1.0, 0)
	part(m, torso, V3.new(2, 2, 1), shirt)
	part(m, torso * CF.new(0, -0.3, -0.53), V3.new(1.6, 2.3, 0.08), C3.fromRGB(110, 70, 40))
	local head = torso * CF.new(0, 1.65, 0) * CF.Angles(0.14, 0, 0)
	part(m, head, V3.new(1.2, 1.2, 1.2), SKIN)
	part(m, head * CF.new(0, 0.65, 0.1), V3.new(1.28, 0.32, 1.28), hair)
	for _, s in { -1, 1 } do
		part(m, head * CF.new(s * 0.27, 0.1, -0.61), V3.new(0.16, 0.26, 0.04), C3.fromRGB(40, 30, 30))
	end
	-- arms out for balance: the left one forward and out, the right one back and out
	for _, spec in { { -1, 0.45, -1.0 }, { 1, -0.35, 1.1 } } do
		local s, swing, out = spec[1], spec[2], spec[3]
		local shoulder = torso * CF.new(s * 1.5, 0.9, 0)
		part(m, shoulder * CF.Angles(swing, 0, out) * CF.new(0, -0.9, 0), V3.new(0.95, 2, 0.95), shirt)
	end
	return m
end

-- A board with a rider at `cf` (the board's Root frame).
-- The board lies across under the rider (BoardPose.Across); the rider faces along `cf`.
local function ridingBoard(parent: any, boardId: string, cf: any, colors: any): any
	local model = boardAt(parent, boardId, cf * Pose.Across)
	rider(parent, CF.new(worldOf(model, "Feet").Position) * cf.Rotation, colors)
	return model
end

function Preview.build(Loader: any, workspace: any)
	init(Loader)
	showroom(workspace)
	closeUp(workspace, "TerraForgeCustom", Preview.COMET_AT, Preview.COMET_AT + V3.new(-6, 6, 7))
	closeUp(workspace, "RoyalPhoenix", Preview.PHOENIX_AT, Preview.PHOENIX_AT + V3.new(-6, 6, 7))
	lineup(workspace)
	-- a rider on the Terra Forge Custom on plain tiles (shots hover_custom_*): the board lies across
	local at = Preview.CUSTOM_RIDE_AT
	local floor = roblox.Instance.new("Model")
	floor.Name = "CustomRide"
	floor.Parent = workspace
	part(floor, CF.new(at.X, -0.5, at.Z), V3.new(80, 1, 80), C3.fromRGB(96, 168, 70))
	disc(floor, CF.new(at.X, 0.05, at.Z), 22, 0.2, C3.fromRGB(160, 150, 156))
	ridingBoard(floor, "TerraForgeCustom", CF.new(at.X, 0.45, at.Z) * CF.Angles(0, 0.35, 0), {
		shirt = C3.fromRGB(40, 170, 220),
		pants = C3.fromRGB(36, 40, 70),
		hair = C3.fromRGB(40, 30, 30),
	})
	lamp(floor, at + V3.new(0, 0.6, 0), C3.fromRGB(255, 110, 200), 9, 1.0)
end

-- hero = false: everyone rides away from the camera toward the Ember Caves tunnel
-- (the player's own view, shots hover_ride*); hero = true: the riders come out of
-- the quarry gate toward the camera (scene "hoverboard_hero", shot hover_hero).
function Preview.buildRide(Loader: any, workspace: any, hero: boolean?)
	init(Loader)
	local floor = require("./mine_floor_scene").build(Loader, workspace, 1)
	-- the floor scene's idle stand-in at the entrance gives way to the riders
	for _, d in floor:GetChildren() do
		if d.Name == "Dummy" then
			d.Parent = nil
		end
	end
	local folder = roblox.Instance.new("Model")
	folder.Name = "Riders"
	folder.Parent = workspace
	local PLAYER = { shirt = C3.fromRGB(186, 98, 48), pants = C3.fromRGB(60, 54, 70), hair = C3.fromRGB(80, 50, 30) }
	local VIOLET_FRIEND = { shirt = C3.fromRGB(120, 60, 200), pants = C3.fromRGB(40, 36, 60), hair = C3.fromRGB(250, 214, 120) }
	local CYAN_FRIEND = { shirt = C3.fromRGB(40, 170, 220), pants = C3.fromRGB(36, 40, 70), hair = C3.fromRGB(40, 30, 30) }
	local riders = if hero
		then {
			-- racing to the left across the open sand between the gate and the railway:
			-- the Robux boards lead, the player on the Timber Drifter catches up
			{ "RoyalPhoenix", V3.new(-8.6, 0.6, 15.2), math.pi / 2 + 0.24, 0.1, VIOLET_FRIEND },
			{ "TerraForgeCustom", V3.new(0, 0.5, 16.2), math.pi / 2 + 0.26, 0.12, CYAN_FRIEND },
			{ "TimberDrifter", V3.new(8.6, 0.35, 15.2), math.pi / 2 + 0.24, 0.08, PLAYER },
		}
		else {
			-- the player on the Timber Drifter, a little banked, racing to the tunnel
			{ "TimberDrifter", V3.new(0.6, 0.35, -2.5), -0.06, 0.06, PLAYER },
			-- friends on the Robux boards ahead on the left and right
			{ "RoyalPhoenix", V3.new(-4.6, 0.6, -8), 0.1, -0.14, VIOLET_FRIEND },
			{ "TerraForgeCustom", V3.new(4.2, 0.5, -11.5), -0.08, 0.12, CYAN_FRIEND },
		}
	local viewer = if hero then Preview.HERO_VIEWER else Preview.RIDE_VIEWER
	for _, spec in riders do
		local boardId, pos, yaw, bank, colors = spec[1], spec[2], spec[3], spec[4], spec[5]
		local cf = CF.new(pos.X, pos.Y, pos.Z) * CF.Angles(0, yaw, 0) * CF.Angles(0, 0, bank)
		local model = ridingBoard(folder, boardId, cf, colors)
		local back = cf.LookVector * -1
		local tail = cf.Position + cf.LookVector * -1.4 + V3.new(0, 1.2, 0) -- the back edge of the board across
		effectStandIns(folder, model, boardId, function(d: number): any
			return tail + back * d
		end, viewer, 11)
		lamp(folder, pos + V3.new(0, 0.4, 0), Data.get(boardId).Colors.Glow, 9, 1.0)
	end
end

Preview.FX_VIEWER = V3.new(1, 8, 40) -- the effects shots' camera

--[[
	All five boards racing out of the quarry gate toward the camera with their
	ride effects (scene "hoverboard_fx", shot hover_fx); moment = "Boost" adds
	the top-speed bursts, "Start" shows the five standing with their hop-on
	splash (scene "hoverboard_fx_start").
]]
function Preview.buildFx(Loader: any, workspace: any, moment: string?)
	init(Loader)
	local floor = require("./mine_floor_scene").build(Loader, workspace, 1)
	for _, d in floor:GetChildren() do
		if d.Name == "Dummy" then
			d.Parent = nil
		end
	end
	local folder = roblox.Instance.new("Model")
	folder.Name = "Riders"
	folder.Parent = workspace
	local shirts = {
		C3.fromRGB(186, 98, 48),
		C3.fromRGB(60, 140, 90),
		C3.fromRGB(200, 60, 60),
		C3.fromRGB(40, 170, 220),
		C3.fromRGB(120, 60, 200),
	}
	local start = moment == "Start"
	for i, board in Data.List do
		-- racing to the left across the sand in two staggered rows (effects stream out to
		-- the right); "Start": standing in a row facing the camera
		local x = if start then (i - 3) * 6.2 else (i - 3) * 6.2 + 1.5
		local z = if start then 14 else (if i % 2 == 1 then 23 else 19.5)
		local yaw = if start then math.pi + (i - 3) * -0.08 else math.pi / 2 + 0.22
		local bank = if start then 0 else 0.1
		local cf = CF.new(x, if start then 0.2 else 0.5, z) * CF.Angles(0, yaw, 0) * CF.Angles(0, 0, bank)
		local model =
			ridingBoard(folder, board.Id, cf, { shirt = shirts[i], pants = C3.fromRGB(50, 46, 66), hair = C3.fromRGB(70, 46, 30) })
		local back = cf.LookVector * -1
		local tail = cf.Position + cf.LookVector * -1.4 + V3.new(0, 1.2, 0) -- the back edge of the board across
		local function path(d: number): any
			return tail + back * d
		end
		if start then
			local set = Fx.create(board.Id)
			if set then
				burstStandIns(folder, model, set, "Start", path)
			end
		else
			local set = effectStandIns(folder, model, board.Id, path, Preview.FX_VIEWER, if board.Kind == "Robux" then 12 else nil)
			if set and moment == "Boost" then
				burstStandIns(folder, model, set, "Boost", path)
			end
		end
		lamp(folder, cf.Position + V3.new(0, 0.4, 0), board.Colors.Glow, 9, 1.0)
	end
end

---------------------------------------------------------------- UI overlays

--[[
	The hoverboards panel and the RIDE button over the ride scene (PHASE 2 UI):
	  ui_hover_hud         PC HUD: the BASE / LOBBY / VAULT bar, main's left side
	                       menu (ELEVATOR and HOVER among its buttons), RIDE above
	                       BUILD on the right
	  ui_hover_panel       PC HUD + the hoverboards panel (owns the Timber Drifter,
	                       equipped; $120K)
	  ui_hover_phone       an iPhone SE-sized landscape screen (667 x 375 pt) at
	                       the 0.62 phone scale: compact panel
	  ui_hover_hud_phone   the phone HUD with the RIDE button and stand-ins for
	                       Roblox's touch thumbstick and jump button
	  ui_hover_phone_small a small 568 x 320 pt phone: the compact panel's cards scroll
	The Robux cards show their live R$ button (game pass ids simulated; with id 0
	the game shows COMING SOON).
]]
function Preview.buildUi(Loader: any): { [string]: any }
	init(Loader)
	local UiExport = require("./uiexport")
	local Client = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local HudView = Loader.requirePath(Client .. "HudView")
	local TeleportView = Loader.requirePath(Client .. "TeleportView")
	local BuildView = Loader.requirePath(Client .. "BuildView")
	local SideMenuView = Loader.requirePath(Client .. "SideMenuView")
	local HoverboardView = Loader.requirePath(Client .. "HoverboardView")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local UDim2 = roblox.UDim2

	local pc = 1.25 -- 900 px tall render / 720 design height
	local phone = 0.62 * 900 / 375

	local function hud(scale: number, uiScale: number, riding: boolean, touch: boolean): { any }
		local refs = HudView.build()
		refs.Gui.Scale.Scale = scale
		BuildView.menuButton(refs.Menu)
		local ride = HoverboardView.rideButton(refs.Menu)
		HoverboardView.setRiding(ride, riding, if touch then "" else "H", "")
		local teleport = TeleportView.build(refs.TopBar, uiScale)
		TeleportView.relayout(teleport, refs.TopBar, uiScale)
		refs.Coins.Text = Format.money(120000)
		refs.Income.Text = Format.perSecond(240)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		refs.CarryLabel.Text = "HANDS 0/3"
		-- main's left side menu (ELEVATOR and HOVER among its buttons; STORE hidden like in
		-- today's game); phones get its MENU button
		local side = SideMenuView.build()
		side.Gui.Scale.Scale = scale
		SideMenuView.setHidden(side, "Store", true)
		local designW = if touch then 667 / uiScale else 1600 / scale
		local designH = if touch then (375 - 36) / uiScale else (900 - 36) / scale
		SideMenuView.apply(
			side,
			SideMenuView.layout(uiScale, designH, { Count = #SideMenuView.shown(side), Touch = touch, DesignWidth = designW })
		)
		return { refs.Gui, side.Gui }
	end

	local function panel(scale: number, compact: boolean, maxWidth: number, maxHeight: number): any
		local refs = HoverboardView.build(compact)
		refs.Gui.Scale.Scale = scale
		refs.Gui.Enabled = true
		HoverboardView.setCards(refs, { TimberDrifter = true }, "TimberDrifter", 120000)
		HoverboardView.layout(refs, compact, maxWidth, maxHeight)
		HoverboardView.pose(refs, HoverboardView.OpenTime)
		if not compact then
			HoverboardView.setHint(refs, "Mouse", "Click a card · H: ride · Backspace: close")
		end
		return refs.Gui
	end

	-- Roblox's touch controls (preview stand-ins): the thumbstick and the jump button
	local function touchControls(): any
		local gui = roblox.Instance.new("ScreenGui")
		gui.Name = "RobloxTouchStandIn"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 1
		local function circle(name: string, position: any, size: number, transparency: number)
			local f = roblox.Instance.new("Frame")
			f.Name = name
			f.Position = position
			f.Size = UDim2.fromOffset(size, size)
			f.BackgroundColor3 = C3.new(1, 1, 1)
			f.BackgroundTransparency = transparency
			f.Parent = gui
			local corner = roblox.Instance.new("UICorner")
			corner.CornerRadius = roblox.UDim.new(0.5, 0)
			corner.Parent = f
			local stroke = roblox.Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = C3.new(1, 1, 1)
			stroke.Transparency = 0.35
			stroke.Parent = f
		end
		-- 900 px / 375 pt: the jump button is 70 pt at (1, -95, 1, -90) on small screens
		local k = 900 / 375
		circle("JumpButton", UDim2.new(1, -95 * k, 1, -90 * k), 70 * k, 0.7)
		-- the classic thumbstick on small screens: 70 pt at (0, 25, 1, -90)
		circle("Thumbstick", UDim2.new(0, 25 * k, 1, -90 * k), 70 * k, 0.8)
		return gui
	end

	local exports: { [string]: any } = {}
	local saved = {}
	for key, entry in MonetizationConfig.Entries do
		saved[key] = entry.Id
		entry.Id = 9100000 + #key
	end
	-- the receipts gate is on in these pictures (the live game publishes it from the server)
	local realReady = HoverboardView.receiptsReady
	HoverboardView.receiptsReady = function(): boolean
		return true
	end
	local ok, err = pcall(function()
		exports.ui_hover_hud = UiExport.export(hud(pc, 1, false, false))
		local withPanel = hud(pc, 1, false, false)
		table.insert(withPanel, panel(pc, false, 1600 / pc, 900 / pc))
		exports.ui_hover_panel = UiExport.export(withPanel)
		local phonePanel = hud(phone, 0.62, false, true)
		table.insert(phonePanel, panel(phone, true, 667 / 0.62, (375 - 36) / 0.62))
		exports.ui_hover_phone = UiExport.export(phonePanel)
		-- a small 568 x 320 pt phone: the cards scroll (the second row peeks in)
		local small = 0.62 * 900 / 320
		local smallPanel = hud(small, 0.62, false, true)
		table.insert(smallPanel, panel(small, true, 568 / 0.62, (320 - 36) / 0.62))
		exports.ui_hover_phone_small = UiExport.export(smallPanel)
		local phoneHud = hud(phone, 0.62, true, true)
		table.insert(phoneHud, touchControls())
		exports.ui_hover_hud_phone = UiExport.export(phoneHud)
	end)
	for key, id in saved do
		MonetizationConfig.Entries[key].Id = id
	end
	HoverboardView.receiptsReady = realReady
	if not ok then
		error(err, 0)
	end
	return exports
end

return Preview
