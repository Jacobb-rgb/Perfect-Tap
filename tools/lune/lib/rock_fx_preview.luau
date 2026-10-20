--[[
	Previews of the rock labels and the breaking animation (client UI/RockLabel,
	Effects/RockFxLogic) for the owner, rendered without Studio by
	tools/lune/export_rock_fx.luau.

	  labels   a real mine floor area (mine_floor_scene) seen from behind a player
	           who blasts a rock; the labels the game would show (RockLabel.pick,
	           the same builder, fade and focus rules) are projected onto the
	           picture as a UI overlay (desktop and phone-sized versions)
	  shatter  a storyboard: one rock frozen at moments of the animation (beam,
	           crack pop, shatter at 0.05 / 0.2 / 0.5 / 1.0 s) and a Giant
	           Crystal; the debris pieces are placed by RockFxLogic.sample (the
	           exact in-game motion), particles (dust, sparkles, flash) are
	           stand-in translucent balls at their simulated positions

	Each builder returns its shots (camera + ui name) so the cameras used for
	the label projection and for the render are the same numbers.
]]

local roblox = require("@lune/roblox") :: any

local RockFxPreview = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance

local W, H = 1600, 900
local GRAVITY = 196.2 -- Roblox physics (server-flung pieces, ore chunks)
local WHITE = C3.new(1, 1, 1)

---------------------------------------------------------------- helpers

local function topOf(model): number
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

-- bounding box center and horizontal radius of a model's visible parts
local function bounds(model): (any, number)
	local lo = V3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local p = d.CFrame.Position
			local r = d.Size.Magnitude / 2
			lo = V3.new(math.min(lo.X, p.X - r), math.min(lo.Y, p.Y - r), math.min(lo.Z, p.Z - r))
			hi = V3.new(math.max(hi.X, p.X + r), math.max(hi.Y, p.Y + r), math.max(hi.Z, p.Z + r))
		end
	end
	local size = hi - lo
	return (lo + hi) / 2, math.max(size.X, size.Z) / 2 * 0.8
end

-- screen pixel (x, y, depth) of a world point for a shot camera (three.js perspective, vertical fov)
local function project(CF, cam, point): (number?, number?, number?)
	local cf = CF.lookAt(cam.position, cam.target)
	local rel = cf:PointToObjectSpace(point)
	if rel.Z > -0.5 then
		return nil, nil, nil
	end
	local t = math.tan(math.rad(cam.fov) / 2)
	local x = (rel.X / -rel.Z) / (t * W / H)
	local y = (rel.Y / -rel.Z) / t
	return (x + 1) / 2 * W, (1 - y) / 2 * H, -rel.Z
end

local function list(v): { number }
	return { math.floor(v.X * 100 + 0.5) / 100, math.floor(v.Y * 100 + 0.5) / 100, math.floor(v.Z * 100 + 0.5) / 100 }
end

local function lamp(Geo, CF, parent, position, color, range, brightness)
	local p = Geo.block(parent, CF.new(position.X, position.Y, position.Z), V3.new(0.2, 0.2, 0.2), color, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	return p
end

--[[
	The labels the game would show for `items` ({ Rock, Distance, Focused, Note,
	Level }), as a ScreenGui overlay for the shot camera. `viewScale` is
	RockLabel.screenScale for the screen (bigger for the phone-equivalent shot).
]]
local function overlay(Loader, CF, cam, items, viewScale: number)
	local RockLabel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RockLabel")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local gui = Instance.new("ScreenGui")
	gui.Name = "RockLabels"
	gui.IgnoreGuiInset = true
	local placed = {}
	for _, item in items do
		local rock = item.Rock
		local primary = rock.PrimaryPart
		local name, color = RockLabel.rockInfo(rock:GetAttribute("Floor"), rock:GetAttribute("Kind"))
		local max = rock:GetAttribute("MaxHealth") or 1
		local hp = rock:GetAttribute("Health") or max
		local refs = RockLabel.build(name, color, max, topOf(rock) - primary.CFrame.Position.Y)
		local locked, vip = RockLabel.lockOf(item.Level, rock:GetAttribute("MinBlaster"), rock:GetAttribute("VipOnly"), false)
		RockLabel.set(refs, hp, max, locked, vip)
		local scale, fade = RockLabel.fade(item.Distance)
		if item.Focused then
			scale, fade = math.max(scale, 1) * 1.12, 0
		end
		RockLabel.setLook(refs, scale * viewScale, fade)
		RockLabel.setNote(refs, item.Note or "", if item.Note == "Get closer" then Theme.TextDim else Theme.Bad)
		local anchor = primary.CFrame.Position + refs.Gui.StudsOffsetWorldSpace
		local x, y, depth = project(CF, cam, anchor)
		if x and y and depth and x > -150 and x < W + 150 and y > -60 and y < H + 60 then
			table.insert(placed, { Refs = refs, X = x, Y = y, Depth = depth, Focused = item.Focused, Distance = item.Distance })
		end
		local _ = MineFloors
	end
	-- the game's declutter: the aimed rock first, then nearest; covered labels hide
	table.sort(placed, function(a, b)
		if a.Focused ~= b.Focused then
			return a.Focused == true
		end
		return a.Distance < b.Distance
	end)
	local rects = {}
	for _, p in placed do
		table.insert(rects, RockLabel.rect(p, p.X, p.Y, p.Refs.Shown.Scale))
	end
	local shown = RockLabel.declutter(rects)
	local kept = {}
	for _, p in placed do
		if shown[p] then
			table.insert(kept, p)
		end
	end
	placed = kept
	-- nearer labels draw over farther ones (BillboardGuis are depth sorted)
	table.sort(placed, function(a, b)
		return a.Depth > b.Depth
	end)
	for rank, p in placed do
		local holder = Instance.new("Frame")
		holder.Name = "Label" .. rank
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = roblox.Vector2.new(0.5, 0.5)
		holder.Position = roblox.UDim2.fromOffset(p.X, p.Y)
		holder.Size = p.Refs.Gui.Size
		holder.ZIndex = rank
		holder.Parent = gui
		p.Refs.Box.Parent = holder
	end
	local UiExport = require("./uiexport")
	return UiExport.export({ gui }), #placed
end

-- server attributes on a preview rock (what MiningService sets)
local function serverAttributes(MineFloors, rock, floorIndex: number)
	local kind = rock:GetAttribute("Kind")
	local max = MineFloors.rockHealth(floorIndex, kind)
	rock:SetAttribute("MaxHealth", max)
	rock:SetAttribute("Health", max)
	rock:SetAttribute("MinBlaster", MineFloors.get(floorIndex).MinBlaster)
end

---------------------------------------------------------------- labels in a floor area

--[[
	Floor `index` with rocks on its spawns, a player at `player` (feet) blasting
	the rock nearest to `aimAt`, the camera behind them. `level` = the player's
	blaster level (below the floor's MinBlaster -> "Lv N" labels). Returns the
	shots ({ name = shot }) and ui exports ({ name = guis }).
]]
function RockFxPreview.labels(Loader, workspace, opts)
	local CF = Loader.CFrame
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockLabel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RockLabel")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Gallery = require("./blaster_gallery")
	local index = opts.floor
	local floor = MineFloors.get(index)
	local area = require("./mine_floor_scene").build(Loader, workspace, index)
	local rocks = {}
	for _, rock in area:FindFirstChild("Rocks"):GetChildren() do
		serverAttributes(MineFloors, rock, index)
		table.insert(rocks, rock)
	end
	local player = opts.player
	-- the blasted rock: nearest to aimAt, a crack stage in, HP part-way down
	local target, best = nil, math.huge
	for _, rock in rocks do
		local d = (rock.PrimaryPart.CFrame.Position - opts.aimAt).Magnitude
		if d < best and rock:GetAttribute("Kind") ~= "Giant" then
			target, best = rock, d
		end
	end
	local locked = opts.level < floor.MinBlaster
	if not locked then
		local max = target:GetAttribute("MaxHealth")
		target:SetAttribute("Health", math.ceil(max * 0.45))
		for _, piece in RockBuilder.applyStage(target, 1, 7) do
			piece:Destroy()
		end
	end
	local tpos = target.PrimaryPart.CFrame.Position
	local root = CF.lookAt(player, V3.new(tpos.X, player.Y, tpos.Z))
	local aim = Gallery.surface(target, player, 0.6)
	local _, muzzle = Gallery.forgekeeper(Loader, area, root, aim, opts.level, opts.ore)
	local glow = if locked then C3.fromRGB(200, 200, 220) else BlasterBuilder.look(opts.level, opts.ore).Glow
	Gallery.beam(Loader, area, muzzle, aim, glow)

	-- cameras: the default Roblox zoom (~11 studs behind the head) and zoomed out
	local forward = ((opts.look or tpos) - player) * V3.new(1, 0, 1)
	forward = forward.Unit
	local right = V3.new(-forward.Z, 0, forward.X)
	local cameras = {
		{ suffix = "", position = player - forward * 10 + right * 3 + V3.new(0, 8.5, 0), target = player + forward * 8 + V3.new(0, 2.5, 0) },
		{ suffix = "_far", position = player - forward * 15 + right * 4 + V3.new(0, 15, 0), target = player + forward * 7 + V3.new(0, 1, 0) },
	}
	local shots = {}
	local uis = {}
	local name = opts.name
	for _, c in cameras do
		local cam = { position = c.position, target = c.target, fov = 70 }
		local camLook = (cam.target - cam.position).Unit
		local function items(count: number)
			local candidates = {}
			for _, rock in rocks do
				local p = rock.PrimaryPart.CFrame.Position
				table.insert(candidates, { Rock = rock, Distance = (p - player).Magnitude, Behind = (p - cam.position):Dot(camLook) < 0 })
			end
			local out = {}
			for _, cand in RockLabel.pick(candidates, count) do
				local gate = ""
				local needed = cand.Rock:GetAttribute("MinBlaster")
				if needed > opts.level then
					gate = "Needs Lv " .. needed
				end
				table.insert(out, { Rock = cand.Rock, Distance = cand.Distance, Focused = cand.Rock == target, Note = if cand.Rock == target then gate else "", Level = opts.level })
			end
			return out
		end
		local desktop, nDesk = overlay(Loader, CF, cam, items(RockLabel.maxLabels(H)), RockLabel.screenScale(H))
		-- phone (390 pt tall, labels at 0.6): the same share of the screen height as on the phone
		local phoneScale = RockLabel.screenScale(390) * H / 390
		local phone, nPhone = overlay(Loader, CF, cam, items(RockLabel.maxLabels(390)), phoneScale)
		print(string.format("labels %s%s: %d shown on desktop, %d phone-sized", name, c.suffix, nDesk, nPhone))
		local shot = {
			scene = name,
			position = list(cam.position),
			target = list(cam.target),
			fov = cam.fov,
			preset = floor.Lighting,
			shadowExtent = 120,
			maxLights = 24,
			sunDir = { -0.5, 0.72, 0.48 },
		}
		for _, variant in { "", "_phone" } do
			local s = table.clone(shot)
			local ui = "ui_" .. name .. c.suffix .. variant
			s.ui = ui
			s.uiInset = 0
			shots[name .. c.suffix .. variant] = s
			uis[ui] = if variant == "" then desktop else phone
		end
	end
	return shots, uis
end

---------------------------------------------------------------- shatter storyboard

-- stand-in particles of one Vfx burst frozen at time t (dust puffs, sparkles, glints)
local function particles(Geo, CF, parent, rng, kind: string, center, count: number, color, t: number, scale: number?)
	local k = scale or 1
	for _ = 1, count do
		local dir = V3.new(rng:range(-1, 1), rng:range(-1, 1), rng:range(-1, 1))
		dir = if dir.Magnitude > 0.05 then dir.Unit else V3.new(0, 1, 0)
		if kind == "Dust" then
			local life = rng:range(0.6, 1.1)
			if t < life then
				local speed = rng:range(3, 8) * k
				local p = center + dir * (speed / 4 * (1 - math.exp(-4 * t)))
				local f = t / life
				Geo.ball(parent, p, (1 + 2.2 * f) * k * 0.9, color, nil, { CastShadow = false, CanCollide = false, Transparency = 0.5 + 0.45 * f })
			end
		elseif kind == "Burst" then
			local life = rng:range(0.5, 1.1)
			if t < life then
				local speed = rng:range(10, 24) * k
				local p = center + dir * (speed / 2.5 * (1 - math.exp(-2.5 * t)))
				Geo.ball(parent, p, math.max(0.08, 0.5 * (1 - t / life)) * k, color, Enum.Material.Neon, { CastShadow = false, CanCollide = false })
			end
		elseif kind == "Glint" then
			local life = rng:range(0.4, 0.9)
			if t < life then
				local speed = rng:range(2, 7) * k
				local p = center + dir * (speed / 2 * (1 - math.exp(-2 * t)))
				local f = t / life
				local size = if f < 0.4 then 0.7 * f / 0.4 else 0.7 * (1 - (f - 0.4) / 0.6)
				Geo.ball(parent, p, math.max(0.06, size * 0.6) * k, color, Enum.Material.Neon, { CastShadow = false, CanCollide = false })
			end
		end
	end
end

-- a stand-in of Vfx.flash (a big soft glow) at time t
local function flashBall(Geo, parent, position, color, size: number, t: number)
	local life = 0.17
	if t < life then
		local f = t / life
		Geo.ball(parent, position, size * (0.7 + 0.3 * f) * 0.55, color, Enum.Material.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.35 + 0.6 * f })
	end
end

local function debris(Geo, CF, parent, pieces, t: number, Logic)
	for _, piece in pieces do
		local cf, scale, transparency, done = Logic.sample(piece, t)
		if not done and transparency < 0.98 then
			local material = if piece.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local props = { CastShadow = true, CanCollide = false, Transparency = transparency }
			if piece.Wedge then
				Geo.wedge(parent, cf, piece.Size * scale, piece.Color, material, props)
			else
				Geo.block(parent, cf, piece.Size * scale, piece.Color, material, props)
			end
		end
	end
end

-- the ground ring the way RockFx draws it: thin neon bars around a circle (RockFxLogic.ringSegments)
local function ringBars(Geo, parent, Logic, center, color, diameter: number, transparency: number, width: number)
	local frames, length = Logic.ringSegments(center, diameter, 16)
	for _, cf in frames do
		Geo.block(parent, cf, V3.new(width, 0.12, length), color, Enum.Material.Neon, { CastShadow = false, CanCollide = false, Transparency = transparency })
	end
end

local FRAMES = {
	{ Id = "blast", Caption = "1  blasting: beam sparks, the rock trembles", Mode = "blast" },
	{ Id = "crack", Caption = "2  crack stage +0.09 s: pop, glow shards, flash", Mode = "crack", T = 0.09 },
	{ Id = "s005", Caption = "3  shatter +0.05 s: flash, burst", Mode = "shatter", T = 0.05 },
	{ Id = "s020", Caption = "4  +0.2 s: chunks + crystal shards fly", Mode = "shatter", T = 0.2 },
	{ Id = "s050", Caption = "5  +0.5 s: bounce, dust, ore pops out", Mode = "shatter", T = 0.5 },
	{ Id = "s100", Caption = "6  +1.0 s: shrink + fade (all gone by 1.5 s)", Mode = "shatter", T = 1.0 },
	{ Id = "g012", Caption = "Giant Crystal +0.12 s (bigger burst)", Mode = "shatter", T = 0.12, Floor = 3, Kind = "Giant" },
	{ Id = "g045", Caption = "Giant Crystal +0.45 s", Mode = "shatter", T = 0.45, Floor = 3, Kind = "Giant" },
}
RockFxPreview.Frames = FRAMES

function RockFxPreview.shatter(Loader, workspace, sceneName: string)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
	local Gallery = require("./blaster_gallery")
	local root = Instance.new("Model")
	root.Name = "RockShatter"
	root.Parent = workspace
	local shots = {}
	local uis = {}
	local ores = { "Tin", "Copper", "Quartz", "Coal" } -- stage 2 drops Copper (orange glow)
	for i, frame in FRAMES do
		local floorIndex = frame.Floor or 1
		local kind = frame.Kind or "Big"
		local floor = MineFloors.get(floorIndex)
		local pal = floor.Palette
		local giant = kind == "Giant"
		local x = (i - 1) * 90
		local base = V3.new(x, 0, 0)
		local frameModel = Instance.new("Model")
		frameModel.Name = "Frame_" .. frame.Id
		frameModel.Parent = root
		-- the stage: ground pad, a back wall, lamps
		Geo.block(frameModel, CF.new(x, -0.5, 0), V3.new(70, 1, 60), pal.Ground)
		Geo.block(frameModel, CF.new(x, 12, -18), V3.new(74, 26, 2), pal.Dark)
		local lampColor = C3.fromRGB(255, 238, 220):Lerp(pal.Light, 0.25)
		for _, lx in { -12, 12 } do
			lamp(Geo, CF, frameModel, V3.new(x + lx, 12, 10), lampColor, 34, if floorIndex == 1 then 0.6 else 1.6)
		end
		local seed = if giant then 39 else 4242
		local rock = RockBuilder.build(floorIndex, kind, if giant then {} else ores, CF.new(x, 0, 0), seed)
		rock.Parent = frameModel
		serverAttributes(MineFloors, rock, floorIndex)
		local center, radius = bounds(rock)
		if giant then
			radius = math.max(radius, 6)
		end
		local camDistance = if giant then 34 else 17
		local cam = {
			position = V3.new(x + (if giant then 6 else 3.5), if giant then 13 else 6.5, camDistance),
			target = V3.new(x, if giant then 6 else 2.6, 0),
			fov = 50,
		}
		local camFlat = (cam.position - center) * V3.new(1, 0, 1)
		local glowOre = OreData.ById[ores[2]]
		local glow = if giant then pal.Crystal else (glowOre and glowOre.Glow or C3.fromRGB(255, 150, 70))
		local rng = Rng.new("frame" .. i)
		local labelItems = nil
		if frame.Mode == "blast" or frame.Mode == "crack" then
			local max = rock:GetAttribute("MaxHealth")
			if frame.Mode == "blast" then
				rock:SetAttribute("Health", math.ceil(max * 0.2))
				for stage = 1, 2 do
					for _, piece in RockBuilder.applyStage(rock, stage, 9) do
						piece:Destroy()
					end
				end
				-- the shooter at the left, the beam on the rock
				local feet = V3.new(x - 9, 0, 6)
				local aim = Gallery.surface(rock, feet, 0.6)
				local _, muzzle = Gallery.forgekeeper(Loader, frameModel, CF.lookAt(feet, V3.new(x, 0, 0)), aim, 2, "Copper")
				Gallery.beam(Loader, frameModel, muzzle, aim, BlasterBuilder.look(2, "Copper").Glow)
				particles(Geo, CF, frameModel, rng, "Dust", aim, 2, pal.Light, 0.3)
			else
				rock:SetAttribute("Health", math.ceil(max * 0.5))
				for _, piece in RockBuilder.applyStage(rock, 1, 9) do
					piece:Destroy()
				end
				-- stage 2 just happened: its pieces were flung by the server (physics)
				local t = frame.T
				for _, piece in RockBuilder.applyStage(rock, 2, 9) do
					local out = (piece.CFrame.Position - center) * V3.new(1, 0, 1)
					local away = if out.Magnitude > 0.1 then out.Unit else V3.new(0, 0, 1)
					local v = away * 10 + V3.new(0, 14, 0)
					piece.CFrame = (piece.CFrame + v * t - V3.new(0, 0.5 * GRAVITY * t * t, 0)) * CF.Angles(t * 6, t * 4, t * 5)
				end
				local hit = center + camFlat.Unit * radius * 0.8 + V3.new(0, 0.2, 0)
				local stageGlow = glow
				debris(Geo, CF, frameModel, Logic.crackPlan({ Position = hit, Crust = pal.Mid, Glow = stageGlow, Stage = 2, Stages = 4, Out = camFlat, Ground = 0, Seed = 77 }), t, Logic)
				particles(Geo, CF, frameModel, rng, "Dust", hit, 7, pal.Light, t)
				particles(Geo, CF, frameModel, rng, "Glint", hit, 6, stageGlow:Lerp(WHITE, 0.3), t)
				particles(Geo, CF, frameModel, rng, "Burst", hit, 8, stageGlow, t * 0.7)
				flashBall(Geo, frameModel, hit, stageGlow, 3.2, t)
				local l = lamp(Geo, CF, frameModel, hit + camFlat.Unit * 0.8, stageGlow, 14, 2.6 * Logic.flash(t, 0.22) * 2)
				local _ = l
				-- the stage's ore chunk pops out (server physics)
				local out = camFlat.Unit
				local origin = center + V3.new(0, radius * 0.5 + 1.5, 0) + out * 0.8
				local v = out * 9 + V3.new(0, 16, 0)
				local p = origin + v * t - V3.new(0, 0.5 * GRAVITY * t * t, 0)
				ItemBuilder.build({ Kind = "Raw", OreId = ores[2] }, CF.new(p.X, p.Y, p.Z) * CF.Angles(0.4, 0.6, 0.2), 7).Parent = frameModel
			end
			labelItems = { { Rock = rock, Distance = 12, Focused = true, Note = "", Level = 2 } }
		else
			-- shatter: the rock is gone, its pieces fly
			local t = frame.T
			rock:Destroy()
			local pieces = Logic.shatterPlan({ Position = center, Crust = pal.Mid, Glow = glow, Floor = floorIndex, Kind = kind, Radius = radius, Ground = 0, Seed = 5 })
			debris(Geo, CF, frameModel, pieces, t, Logic)
			local colors = Logic.colors(floorIndex, kind, pal.Mid, glow)
			local k = if giant then 1.8 else 1
			particles(Geo, CF, frameModel, rng, "Dust", center, if giant then 26 else 16, colors.Rock[2], t, k)
			particles(Geo, CF, frameModel, rng, "Dust", V3.new(center.X, 0.8, center.Z), if giant then 14 else 8, colors.Rock[1], t, k)
			particles(Geo, CF, frameModel, rng, "Burst", center, if giant then 30 else 18, glow, t, k)
			particles(Geo, CF, frameModel, rng, "Glint", center + V3.new(0, radius * 0.4, 0), if giant then 14 else 8, colors.Crystal[1]:Lerp(WHITE, 0.3), t, k)
			flashBall(Geo, frameModel, center, glow:Lerp(WHITE, 0.25), if giant then 16 else 8, t)
			local duration = if giant then 0.45 else 0.3
			lamp(Geo, CF, frameModel, center, glow, radius * 4 + 6, (if giant then 7 else 4) * Logic.flash(t, duration))
			local ringTime = if giant then 0.5 else 0.38
			if t < ringTime then
				local diameter, transparency = Logic.ring(t, ringTime, radius * 0.6, radius * (if giant then 1.9 else 2.2))
				ringBars(Geo, frameModel, Logic, V3.new(center.X, 0.2, center.Z), colors.Crystal[1]:Lerp(WHITE, 0.2), diameter, transparency, if giant then 0.6 else 0.3)
			end
			if not giant then
				-- the last ore chunk pops out (server physics), then lies on the ground
				local out = camFlat.Unit
				local origin = center + V3.new(0, radius * 0.5 + 1.5, 0) + out * 0.8
				local v = out * 9 + V3.new(0, 16, 0)
				local tl = math.min(t, (v.Y + math.sqrt(v.Y * v.Y + 2 * GRAVITY * (origin.Y - 0.6))) / GRAVITY)
				local p = origin + v * tl - V3.new(0, 0.5 * GRAVITY * tl * tl, 0)
				ItemBuilder.build({ Kind = "Raw", OreId = ores[3] }, CF.new(p.X, p.Y, p.Z) * CF.Angles(0.4, t * 3, 0.2), 9).Parent = frameModel
			end
		end
		local name = sceneName .. "_" .. frame.Id
		local shot = {
			scene = sceneName,
			position = list(cam.position),
			target = list(cam.target),
			fov = cam.fov,
			preset = floor.Lighting,
			shadowExtent = 80,
			maxLights = 24,
			sunDir = { -0.5, 0.72, 0.48 },
		}
		if labelItems then
			local RockLabel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RockLabel")
			uis["ui_" .. name] = overlay(Loader, CF, cam, labelItems, RockLabel.screenScale(H))
			shot.ui = "ui_" .. name
			shot.uiInset = 0
		end
		shots[name] = shot
	end
	return shots, uis
end

return RockFxPreview
