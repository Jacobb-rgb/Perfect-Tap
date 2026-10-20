--[[
	The five STAR blasters (Config/StarBlasterData, the owner's picks)
	on a starry stage: scene "star_blasters" for tools/lune/export_scene.luau,
	shots in tools/preview/star_blasters_shots.json.
	  each gun floats over a dark pedestal with a glowing ring in its glow
	  colour, turned toward the camera; a plate under it names it, the
	  rebirth that opens it and its prices (R$ / Forge Stars).
	The guns are the game's own Kenney shapes (KenneyBlaster.parts, shapes 11-15)
	with KenneyBlaster's skins, crystals, crown and the level 10 sparks / flames.
]]

local Preview = {}

function Preview.build(Loader: any, workspace: any)
	local roblox = Loader.roblox
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local Color3 = roblox.Color3
	local UDim2 = roblox.UDim2
	local Enum = roblox.Enum
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local KenneyBlaster = Loader.requirePath("ReplicatedStorage.Shared.Builders.KenneyBlaster")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

	local rgb = Color3.fromRGB
	local stage = Instance.new("Model")
	stage.Name = "StarBlasterStage"
	stage.Parent = workspace

	local function block(name: string, cf: any, size: any, color: any, material: any?): any
		return Geo.make("Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
		}, stage)
	end

	local function plate(cf: any, size: any, lines: { string }, color: any)
		local p = block("Plate", cf, size, rgb(16, 14, 30))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back -- (the +Z side: the camera's)
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.94, 0.86)
		t.Position = UDim2.fromScale(0.03, 0.07)
		t.Text = table.concat(lines, "\n")
		t.TextScaled = true
		t.TextColor3 = color
		t.TextStrokeColor3 = rgb(8, 6, 14)
		t.TextStrokeTransparency = 0.2
		t.FontFace = roblox.Font.fromEnum(Enum.Font.LuckiestGuy)
		t.Parent = gui
	end

	-- the floor and the starry back wall
	block("Floor", CFrame.new(0, -0.5, 0), Vector3.new(80, 1, 40), rgb(22, 20, 40))
	block("Wall", CFrame.new(0, 12, -12), Vector3.new(80, 26, 1), rgb(12, 10, 28))
	local rng = Rng.new(2026)
	for i = 1, 70 do
		local s = rng:range(0.08, 0.22)
		local star = block(
			"Star" .. i,
			CFrame.new(rng:range(-38, 38), rng:range(1, 24), -11.4) * CFrame.Angles(0, 0, math.pi / 4),
			Vector3.new(s, s, 0.1),
			rgb(255, 244, 220),
			Enum.Material.Neon
		)
		star.Transparency = rng:range(0, 0.5)
	end
	-- the STAR FORGE title
	plate(CFrame.new(0, 17.5, -10.8), Vector3.new(26, 3.2, 0.2), { "STAR BLASTERS" }, rgb(255, 206, 72))

	local spacing = 10.5
	for i, star in StarBlasterData.List do
		local x = (i - 3) * spacing
		local base = CFrame.new(x, 0, 0)
		-- the pedestal: a dark column with a ring in the gun's glow
		block("Pedestal", base * CFrame.new(0, 1.2, 0), Vector3.new(3.4, 2.4, 3.4), rgb(34, 30, 56))
		block("Front", base * CFrame.new(0, 1.2, 1.65), Vector3.new(5.8, 2.4, 0.1), rgb(20, 18, 36))
		-- a thin glowing rim round the pedestal's top (a full neon top blooms white)
		for _, edge in { { 0, 1.72, 3.6, 0.14 }, { 0, -1.72, 3.6, 0.14 }, { 1.72, 0, 0.14, 3.6 }, { -1.72, 0, 0.14, 3.6 } } do
			block("Ring", base * CFrame.new(edge[1], 2.43, edge[2]), Vector3.new(edge[3], 0.08, edge[4]), star.Glow, Enum.Material.Neon)
		end
		-- the gun, turned to the camera, floating over it
		local level, ore, skin = BlasterBuilder.starSkin(star) -- the game's own skin
		local frame = base * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, -math.pi / 2 + 0.3, 0) * CFrame.Angles(0.06, 0, 0)
		local gun = Instance.new("Model")
		gun.Name = star.Id
		gun.Parent = stage
		local k = 1.5 -- bigger than held, so the jewels read on the stage
		local function scaled(cf: any): any
			return CFrame.new(cf.Position * k) * cf.Rotation
		end
		KenneyBlaster.parts(level, ore, skin, function(name, cf, size, color, material, className)
			return Geo.make(className or "Part", {
				Name = name,
				CFrame = frame * scaled(cf),
				Size = size * k,
				Color = color,
				Material = material or Enum.Material.SmoothPlastic,
				Anchored = true,
				CanCollide = false,
				CastShadow = false,
			}, gun)
		end)
		local fxCf, fxSize = KenneyBlaster.effects(level)
		if fxCf and fxSize then
			local holder = Geo.make("Part", {
				Name = "Effects",
				CFrame = frame * scaled(fxCf),
				Size = fxSize * k,
				Transparency = 1,
				Anchored = true,
				CanCollide = false,
			}, gun)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = if star.Magma
				then "rbxasset://textures/particles/fire_main.dds"
				else "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = roblox.ColorSequence.new(star.Glow)
			emitter.LightEmission = 1
			emitter.Name = if star.Magma then "GunFlame" else "GunSpark" -- (the renderer's small gun effects, as held)
			emitter.Rate = 8
			emitter.Lifetime = roblox.NumberRange.new(0.3, 0.6)
			emitter.Speed = roblox.NumberRange.new(0.3, 1)
			emitter.Size = roblox.NumberSequence.new(if star.Magma then 0.35 else 0.18)
			emitter.Parent = holder
		end
		-- the gun's own glow (BlasterBuilder.buildStar's StarGlow light)
		local glowLight = Instance.new("PointLight")
		glowLight.Color = star.Glow
		glowLight.Range = 8
		glowLight.Brightness = 1.2
		local glowHolder = block("GlowLight", frame, Vector3.new(0.1, 0.1, 0.1), star.Glow)
		glowHolder.Transparency = 1
		glowLight.Parent = glowHolder
		-- a soft white fill in front of the gun (its body reads) and a glow light under it
		local fill = Instance.new("PointLight")
		fill.Color = Color3.new(1, 1, 1)
		fill.Range = 12
		fill.Brightness = 1.3 -- (the jewels glow on their own)
		local lamp = block("Fill", base * CFrame.new(0, 6.5, 4.5), Vector3.new(0.1, 0.1, 0.1), rgb(255, 255, 255))
		lamp.Transparency = 1
		fill.Parent = lamp
		-- the plate on the pedestal's front
		local ink = star.Glow:Lerp(Color3.new(1, 1, 1), 0.35)
		plate(base * CFrame.new(0, 1.75, 1.75), Vector3.new(5.6, 0.95, 0.2), { string.upper(star.Name) }, ink)
		plate(
			base * CFrame.new(0, 0.75, 1.75),
			Vector3.new(5.6, 0.8, 0.2),
			{ `REBIRTH {star.Unlock} · R$ {star.Robux} · ⭐ {star.Stars}` },
			Color3.new(1, 1, 1)
		)
	end
end

--[[
	Scene "star_blasters_held": LV 10's blaster and the five STAR blasters
	in a dummy's hand (Roblox's tool hold: the right arm forward), the
	held tools as ToolService gives them (BlasterBuilder.build / buildStar),
	so their size next to the body shows.
]]
function Preview.buildHeld(Loader: any, workspace: any)
	local roblox = Loader.roblox
	local CFrame = Loader.CFrame
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
	local Dummy = require("./dummy")
	local rgb = Color3.fromRGB
	local stage = roblox.Instance.new("Model")
	stage.Name = "HeldStage"
	stage.Parent = workspace
	Geo.make("Part", {
		Name = "Floor",
		CFrame = CFrame.new(0, -0.5, 0),
		Size = Vector3.new(80, 1, 30),
		Color = rgb(70, 74, 92),
		Anchored = true,
	}, stage)
	Geo.make("Part", {
		Name = "Wall",
		CFrame = CFrame.new(0, 10, -8),
		Size = Vector3.new(80, 22, 1),
		Color = rgb(36, 34, 58),
		Anchored = true,
	}, stage)
	local tools = { BlasterBuilder.build(10, "Amethyst") }
	for _, star in StarBlasterData.List do
		table.insert(tools, BlasterBuilder.buildStar(star, 10, "Gold"))
	end
	for i, tool in tools do
		-- facing the camera's right (+X), the gun hand toward the camera
		local root = CFrame.new((i - 3.5) * 8 - 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		Dummy.build(stage, CFrame, root, "hold", nil, tool)
	end
end

return Preview
