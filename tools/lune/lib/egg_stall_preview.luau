--[[
	EGG STALL concepts (owner 2026-10-21: "instead of the capsule stall, a
	stall with these eggs, open, just a roof; the player walks up to a
	spinning egg on a small podium and gets the offer"). Three looks built
	in the lobby where the CapsuleStall stands (the old stall is removed),
	each with the game's own eggs (GolemBuilder.capsule: Stone, Royal,
	Crystal) on podiums under an open roof:

	  scene "eggstall_A"   GOLDEN PAVILION: a round slate dais, four gold
	                       pillars, a stepped pagoda roof with gold trim and
	                       upturned corners, hanging lanterns
	  scene "eggstall_B"   CRYSTAL ARCHES: three glowing arches carrying a
	                       glass roof, crystals on the arches, a floating sign
	  scene "eggstall_C"   FESTIVAL TENT: a striped peaked canopy on four
	                       poles, a scalloped valance, flags, string lights

	Shots in tools/preview/egg_stall_shots.json (the old stall's camera).
	Preview only: nothing here is in the game yet.
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum
local rgb = Color3.fromRGB
local M = Enum.Material
local PI = math.pi

local function findStall(workspace: any): any
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.PrimaryPart and d.PrimaryPart.Name == "CapsuleMachine" then
			return d
		end
	end
	error("no CapsuleStall in the world")
end

function Preview.build(Loader: any, workspace: any, variant: string)
	local CF = Loader.CFrame
	Loader.requirePath("ServerScriptService.Server.World.WorldBuilder").build(workspace)
	local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Kit")
	local Tech = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Tech")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	findStall(workspace):Destroy()
	local _, cf = Kit.piece("CapsuleStall")
	local m = Instance.new("Model")
	m.Name = "EggStall" .. variant
	m.Parent = workspace

	local function at(x: number, y: number, z: number): any
		return cf * CF.new(x, y, z)
	end
	local function part(c: any, size: any, color: any, material: any?, shape: any?): any
		local p = Geo.make("Part", {
			CFrame = c,
			Size = size,
			Color = color,
			Material = material or M.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
		}, m)
		if shape then
			p.Shape = shape
		end
		return p
	end
	local function cyl(c: any, h: number, d: number, color: any, material: any?): any
		return part(c * CF.Angles(0, 0, PI / 2), Vector3.new(h, d, d), color, material, Enum.PartType.Cylinder)
	end
	local function ball(p: any, d: number, color: any, material: any?): any
		return part(CF.new(p), Vector3.new(d, d, d), color, material, Enum.PartType.Ball)
	end
	local function seg(a: any, b: any, w: number, color: any, material: any?): any
		local dir = (b - a).Unit
		local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		return part(CF.lookAt((a + b) / 2, b, up), Vector3.new(w, w, (b - a).Magnitude + w * 0.5), color, material)
	end
	local function tri(a: any, b: any, c: any, thick: number, color: any, material: any?)
		Geo.triangle(m, a, b, c, thick, color, material or M.SmoothPlastic)
	end
	local function P(x: number, y: number, z: number): any
		return at(x, y, z).Position
	end
	local function light(p: any, color: any, range: number, brightness: number)
		local holder = part(CF.new(p), Vector3.new(0.2, 0.2, 0.2), color)
		holder.Transparency = 1
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Parent = holder
	end

	local FLOOR = 0.7
	local gold, goldDark = rgb(255, 196, 56), rgb(200, 132, 30)
	local slate, slateDark = rgb(70, 72, 84), rgb(46, 48, 58)

	-- the eggs on their podiums: Stone (left), ROYAL in the middle (raised), Crystal (right)
	local podiums = {
		{ Id = "Stone", X = 4.3, Z = -0.6, H = 1.1, Ring = rgb(255, 160, 50) },
		{ Id = "Royal", X = 0, Z = 0.9, H = 1.7, Ring = rgb(255, 210, 80) },
		{ Id = "Crystal", X = -4.3, Z = -0.6, H = 1.1, Ring = rgb(90, 230, 255) },
	}
	local function podiumsAndEggs(base: any, rim: any, material: any)
		for i, pd in podiums do
			local top = FLOOR + pd.H
			cyl(at(pd.X, FLOOR + pd.H / 2, pd.Z), pd.H, 3.0, base, material)
			cyl(at(pd.X, top + 0.06, pd.Z), 0.14, 3.2, rim, M.Foil)
			cyl(at(pd.X, top + 0.16, pd.Z), 0.06, 2.6, pd.Ring, M.Neon)
			-- the egg turning slowly over its podium (here: caught at an angle)
			-- (bigger than the opening's egg: a pet game's egg stands about as tall as a player)
			local k = 1.45
			local center = at(pd.X, top + (1.25 + 0.15) * k, pd.Z) * CF.Angles(0, 0.35 * (i - 2), 0)
			local egg = GolemBuilder.capsule(pd.Id, center, { Calm = true })
			for _, d in egg:GetDescendants() do
				if d:IsA("BasePart") then
					local rel = center:ToObjectSpace(d.CFrame)
					d.CFrame = center * CF.new(rel.Position * k) * rel.Rotation
					d.Size = d.Size * k
				end
			end
			egg.Parent = m
			-- a name plate on the podium's front
			local capsule = CapsuleConfig.ById[pd.Id]
			local name = string.upper(capsule.Name)
			local _ = name
		end
	end
	local function dais(color: any, rim: any)
		cyl(at(0, FLOOR / 2, 0), FLOOR, 14.2, color, M.Slate)
		cyl(at(0, FLOOR + 0.02, 0), 0.06, 13.4, rim, M.Neon).Transparency = 0.3
		cyl(at(0, FLOOR + 0.05, 0), 0.06, 13.0, color, M.Slate)
		-- two steps up at the front
		part(at(0, FLOOR * 0.35, -7.0), Vector3.new(6, FLOOR * 0.7, 1.2), slateDark, M.Slate)
	end

	if variant == "A" then
		------------------------------------------------ GOLDEN PAVILION
		local teal, tealDark = rgb(40, 150, 150), rgb(26, 100, 106)
		dais(slate, gold)
		podiumsAndEggs(rgb(250, 244, 230), gold, M.SmoothPlastic)
		-- four gold pillars
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = sx * 5.9, sz * 4.6
				cyl(at(x, FLOOR + 4.6, z), 9.2, 0.7, gold, M.Foil)
				cyl(at(x, FLOOR + 0.3, z), 0.6, 1.1, goldDark, M.Foil)
				cyl(at(x, FLOOR + 9.1, z), 0.4, 1.0, goldDark, M.Foil)
			end
		end
		-- the stepped pagoda roof: three tiers, gold trim, upturned corners
		local y = FLOOR + 9.4
		for t, k in { { 15.2, 12.2, 0.7 }, { 11.4, 9.0, 0.7 }, { 7.4, 5.8, 0.8 } } do
			part(at(0, y + k[3] / 2, 0), Vector3.new(k[1], k[3], k[2]), if t % 2 == 1 then teal else tealDark, M.SmoothPlastic)
			part(at(0, y + 0.06, 0), Vector3.new(k[1] + 0.25, 0.14, k[2] + 0.25), gold, M.Foil)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = P(sx * k[1] / 2, y + k[3], sz * k[2] / 2)
					local tip = c + (cf.RightVector * sx + cf.LookVector * -sz).Unit * 0.9 + Vector3.new(0, 0.9, 0)
					seg(c, tip, 0.28, gold, M.Foil)
					ball(tip, 0.42, gold, M.Foil)
				end
			end
			y += k[3] + 0.35
		end
		-- the crown jewel on the roof: a gold spire and a glowing egg-gem
		cyl(at(0, y + 0.6, 0), 1.2, 0.5, gold, M.Foil)
		part(at(0, y + 1.8, 0) * CF.Angles(0, PI / 4, PI / 4), Vector3.new(1.1, 1.1, 1.1), rgb(255, 214, 90), M.Neon)
		-- the EGGS sign over the front
		Tech.sign(m, at(0, FLOOR + 10.6, -6.4), "EGGS", 5.2, 1.6, {})
		-- lanterns hanging between the front pillars
		for _, x in { -3, 3 } do
			seg(P(x, FLOOR + 9.3, -4.6), P(x, FLOOR + 7.9, -4.6), 0.06, goldDark, M.Foil)
			cyl(at(x, FLOOR + 7.5, -4.6), 0.9, 0.7, rgb(220, 40, 40), M.SmoothPlastic)
			light(P(x, FLOOR + 7.4, -5.2), rgb(255, 180, 90), 12, 1)
		end
	elseif variant == "B" then
		------------------------------------------------ CRYSTAL ARCHES
		local cyan, pink, white = rgb(90, 230, 255), rgb(220, 120, 255), rgb(240, 250, 255)
		dais(rgb(40, 44, 70), cyan)
		podiumsAndEggs(rgb(52, 58, 92), rgb(214, 222, 236), M.SmoothPlastic)
		-- three arches front to back, each a half circle of 8 segments with a neon edge
		for _, z in { -4.8, 0, 4.8 } do
			local n = 8
			local radius = 6.6
			for i = 1, n do
				local a0, a1 = (i - 1) / n * PI, i / n * PI
				local p0 = P(math.cos(a0) * radius, FLOOR + 3 + math.sin(a0) * radius * 1.05, z)
				local p1 = P(math.cos(a1) * radius, FLOOR + 3 + math.sin(a1) * radius * 1.05, z)
				seg(p0, p1, 0.7, rgb(214, 222, 236), M.Metal)
				seg(p0 - cf.LookVector * 0.38, p1 - cf.LookVector * 0.38, 0.18, cyan, M.Neon)
			end
			-- the arch's feet
			for _, sx in { -1, 1 } do
				seg(P(sx * radius, FLOOR, z), P(sx * radius, FLOOR + 3, z), 0.8, rgb(214, 222, 236), M.Metal)
			end
			-- a crystal on the arch's crown
			part(
				at(0, FLOOR + 3 + radius * 1.05 + 0.6, z) * CF.Angles(0, PI / 4, 0),
				Vector3.new(0.6, 1.6, 0.6),
				if z == 0 then pink else cyan,
				M.Neon
			)
		end
		-- the glass roof: curved panes between the arches
		for i = 1, 7 do
			local a = (i - 0.5) / 7 * PI
			local p = P(math.cos(a) * 6.5, FLOOR + 3 + math.sin(a) * 6.5 * 1.05, 0)
			local glass = part(
				CF.lookAt(p, p + Vector3.new(0, 0, 1)) * CF.Angles(0, 0, a - PI / 2) * CF.new(0, 0, 0),
				Vector3.new(0.1, 3.0, 9.6),
				white,
				M.Glass
			)
			glass.CFrame = CF.new(p) * cf.Rotation * CF.Angles(0, 0, a - PI / 2)
			glass.Size = Vector3.new(0.08, 3.0, 9.6)
			glass.Transparency = 0.55
		end
		-- the floating sign and crystals on the dais
		Tech.sign(m, at(0, FLOOR + 11.2, -5.4), "EGGS", 5.2, 1.6, {})
		for i, k in { { 6.4, -5.6, 1.4 }, { -6.4, -5.6, 1.2 }, { 6.2, 5.4, 1.0 }, { -6.2, 5.4, 1.3 } } do
			part(
				at(k[1], FLOOR + k[3] / 2, k[2]) * CF.Angles(0, PI / 4, if i % 2 == 0 then 0.25 else -0.25),
				Vector3.new(0.5, k[3], 0.5),
				if i % 2 == 0 then pink else cyan,
				M.Neon
			)
		end
	else
		------------------------------------------------ FESTIVAL TENT
		local red, cream = rgb(214, 40, 60), rgb(255, 240, 210)
		dais(rgb(150, 110, 80), gold)
		podiumsAndEggs(rgb(120, 76, 44), gold, M.Wood)
		-- four striped poles
		local corners = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = sx * 6.2, sz * 5.0
				for s = 1, 4 do
					cyl(at(x, FLOOR + (s - 0.5) * 2.1, z), 2.1, 0.5, if s % 2 == 0 then red else cream, M.SmoothPlastic)
				end
				ball(P(x, FLOOR + 8.6, z), 0.7, gold, M.Foil)
				table.insert(corners, P(x, FLOOR + 8.4, z))
			end
		end
		-- the striped peaked canopy: eight triangles in red and cream
		local peak = P(0, FLOOR + 13.4, 0)
		local ring = {}
		for i = 1, 8 do
			local a = (i - 0.5) / 8 * 2 * PI
			ring[i] = P(math.cos(a) * 8.2, FLOOR + 8.3, math.sin(a) * 6.8)
		end
		for i = 1, 8 do
			tri(peak, ring[i], ring[i % 8 + 1], 0.12, if i % 2 == 0 then red else cream)
		end
		-- the scalloped valance round the canopy's edge
		for i = 1, 8 do
			local a, b = ring[i], ring[i % 8 + 1]
			for j = 1, 3 do
				local p = a:Lerp(b, (j - 0.5) / 3) - Vector3.new(0, 0.45, 0)
				local look = CF.lookAt(p, p + (p - P(0, p.Y - cf.Position.Y, 0)).Unit)
				part(look * CF.Angles(0, 0, PI / 4), Vector3.new(0.9, 0.9, 0.08), if (i + j) % 2 == 0 then gold else red, M.Fabric)
			end
		end
		-- a flag on the peak, string lights from the peak to the poles
		seg(peak, peak + Vector3.new(0, 2.2, 0), 0.14, goldDark, M.Foil)
		tri(peak + Vector3.new(0, 2.2, 0), peak + Vector3.new(0, 1.3, 0), peak + Vector3.new(1.6, 1.8, 0), 0.08, rgb(255, 210, 60))
		for _, c in corners do
			for j = 1, 5 do
				local p = peak:Lerp(c, j / 6) - Vector3.new(0, math.sin(j / 6 * PI) * 0.6, 0)
				ball(p, 0.28, if j % 2 == 0 then rgb(255, 220, 120) else rgb(255, 120, 160), M.Neon)
			end
		end
		Tech.sign(m, at(0, FLOOR + 9.3, -6.7), "EGGS", 5.2, 1.6, {})
	end
end

--[[
	The OFFER window (a mock-up): what a player sees on walking up to an egg:
	the egg turning on the left, every golem inside with its chance on the
	right (the rarest last, odds before buying), and three ways to open it:
	OPEN 1 / OPEN 3 for coins and OPEN 10 for Robux (owner 2026-10-21). The
	Royal egg is all Robux (its products 1 / 3 / 10).
]]
function Preview.ui(Loader: any): { [string]: any }
	local UiExport = require("./uiexport")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local UDim2 = roblox.UDim2
	local Vector2 = roblox.Vector2

	local function offer(eggId: string, robuxTen: number): any
		local capsule = CapsuleConfig.ById[eggId]
		local gui = UIKit.screen("EggOffer", 20)
		local scale = UIKit.new("UIScale", { Name = "Scale", Scale = 1.25 }, gui)
		local _ = scale
		local holder = UIKit.new("Frame", {
			Name = "Fit",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, gui)
		local w, h = 940, 540
		local window =
			Pop.window(holder, string.upper(capsule.Name), Vector2.new(w, h), 70, if eggId == "Royal" then "Purple" else "Yellow")
		window.Root.Position = UDim2.new(0.5, 0, 0.5, 10)
		local body = window.Body
		-- the egg on the left, turning, on a glowing plate
		local plate = UIKit.new("Frame", {
			Name = "EggPlate",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6,
			Position = UDim2.fromOffset(16, 14),
			Size = UDim2.fromOffset(290, 330),
			ZIndex = 2,
		}, body)
		UIKit.corner(plate, 14)
		Pop.rays(plate, UDim2.fromScale(0.5, 0.45), 10, 260, 0.82, 2)
		Pop.model(plate, "capsule_" .. eggId, 270, nil, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			ZIndex = 3,
		})
		Pop.text(plate, capsule.Description, 15, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 40),
			TextWrapped = true,
			ZIndex = 4,
		})
		-- every golem inside with its chance (odds before buying)
		local list = CapsuleConfig.odds(eggId, false)
		local cols, tile, gap = 5, 104, 8
		local x0, y0 = 322, 14
		for i, line in list do
			local golem = GolemConfig.ById[line.Golem]
			local info = Rarity.ById[golem.Rarity]
			local col, row = (i - 1) % cols, (i - 1) // cols
			local t = UIKit.new("Frame", {
				Name = "Golem" .. i,
				BackgroundColor3 = info.DarkColor,
				BackgroundTransparency = 0.15,
				Position = UDim2.fromOffset(x0 + col * (tile + gap), y0 + row * (tile + gap)),
				Size = UDim2.fromOffset(tile, tile),
				ZIndex = 2,
			}, body)
			UIKit.corner(t, 10)
			Pop.border(t, 3, info.Color)
			Pop.model(t, "golem_" .. golem.Id, tile - 14, nil, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.44),
				ZIndex = 3,
			})
			Pop.text(t, string.format("%g%%", math.floor(line.Chance * 10000 + 0.5) / 100), 17, {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -4, 1, -2),
				Size = UDim2.new(1, -6, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 4,
			})
		end
		-- the three ways to open it
		local bw, bh, by = 196, 66, h - 70 - 92
		local function label(x: number, text: string)
			Pop.text(body, text, 18, {
				Position = UDim2.fromOffset(x, by - 26),
				Size = UDim2.fromOffset(bw, 24),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 3,
			})
		end
		local xs = { 330, 330 + bw + 18, 330 + 2 * (bw + 18) }
		if capsule.Currency == "Coins" then
			for i, n in { 1, 3 } do
				local price = CapsuleConfig.price(eggId, n) or 0
				label(xs[i], if n == 1 then "OPEN 1" else "OPEN 3")
				Pop.button(body, Format.money(price), "Yellow", Vector2.new(bw, bh), {
					Position = UDim2.fromOffset(xs[i], by),
					ZIndex = 3,
				})
			end
		else
			for i, n in { 1, 3 } do
				label(xs[i], if n == 1 then "OPEN 1" else "OPEN 3")
				Pop.price(body, ({ 79, 199 })[i], Vector2.new(bw, bh), { Position = UDim2.fromOffset(xs[i], by), ZIndex = 3 })
			end
		end
		label(xs[3], "OPEN 10")
		Pop.price(body, robuxTen, Vector2.new(bw, bh), { Position = UDim2.fromOffset(xs[3], by), ZIndex = 3 })
		Pop.tag(body, "BEST VALUE", "Red", Vector2.new(140, 30), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(xs[3] + bw - 30, by + bh + 4),
			Rotation = 8,
			ZIndex = 5,
		})
		Pop.close(window.Root, 52, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9) })
		local _ = PopTheme
		return UiExport.export({ gui })
	end
	return {
		ui_egg_offer_stone = offer("Stone", 99),
		ui_egg_offer_royal = offer("Royal", 599),
	}
end

return Preview
