--[[
	Reusable low-poly props for the world. Every function takes a parent and
	a base CFrame (bottom center, LookVector = front) and returns the Model.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Palette = require(script.Parent.Palette)

local Props = {}

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function noShadow(extra: { [string]: any }?): { [string]: any }
	local props = decor(extra)
	props.CastShadow = false
	return props
end

-- Particle helper using built-in textures only.
function Props.emitter(parent: Instance, kind: string, color: Color3?, rate: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = kind .. "Particles"
	if kind == "Smoke" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(color or Color3.fromRGB(120, 110, 104))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(5, 8)
		e.Speed = NumberRange.new(5, 8)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Acceleration = Vector3.new(1.5, 1, 0)
		e.Rate = rate or 3
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Rotation = NumberRange.new(0, 360)
		e.LightInfluence = 1
	elseif kind == "Embers" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color or Palette.ForgeGlow)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.1)
		e.Lifetime = NumberRange.new(1.5, 3)
		e.Speed = NumberRange.new(3, 7)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Rate = rate or 6
		e.LightEmission = 1
		e.LightInfluence = 0
	elseif kind == "Fire" then
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Color = ColorSequence.new(color or Palette.ForgeGlow, Color3.fromRGB(255, 70, 20))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0.4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(10, 10)
		e.Acceleration = Vector3.new(0, 4, 0)
		e.Rate = rate or 18
		e.LightEmission = 1
		e.LightInfluence = 0
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Rotation = NumberRange.new(0, 360)
	elseif kind == "Sparkle" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = rate or 3
		e.LightEmission = 1
		e.LightInfluence = 0
	end
	e.Parent = parent
	return e
end

function Props.pointLight(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = parent
	return light
end

-- Stylized tree: chunky trunk + stacked rotated leaf blocks.
function Props.tree(parent: Instance, base: CFrame, rng: Rng.Rng, style: string?): Model
	local m = model("Tree", parent)
	local height = rng:range(7, 11)
	local trunkWidth = rng:range(1.4, 2)
	Geo.block(m, base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, rng:range(0, 6.28), rng:range(-0.06, 0.06)), Vector3.new(trunkWidth, height, trunkWidth), Geo.vary(Palette.Trunk, rng), nil, decor())
	local leafColors = if style == "Green"
		then { Palette.LeafGreen, Palette.LeafDeep }
		elseif style == "Autumn" then { Palette.LeafOrange, Palette.LeafYellow }
		else { Palette.LeafGreen, Palette.LeafOrange, Palette.LeafYellow, Palette.LeafDeep }
	local leafColor = rng:pick(leafColors)
	local layers = rng:int(2, 3)
	local y = height - 1
	local size = rng:range(7, 9)
	for _ = 1, layers do
		local s = Vector3.new(size, size * rng:range(0.55, 0.75), size)
		Geo.block(m, base * CFrame.new(rng:range(-0.6, 0.6), y + s.Y * 0.35, rng:range(-0.6, 0.6)) * Geo.randomTilt(rng, 0.25), s, Geo.vary(leafColor, rng, 0.05), nil, decor())
		y += s.Y * 0.6
		size *= 0.72
	end
	return m
end

-- Pine-like tree for cliffs: stacked wedge "cones".
function Props.pine(parent: Instance, base: CFrame, rng: Rng.Rng): Model
	local m = model("Pine", parent)
	local trunkH = rng:range(3, 4.5)
	Geo.block(m, base * CFrame.new(0, trunkH / 2, 0), Vector3.new(1.2, trunkH, 1.2), Palette.Trunk, nil, decor())
	local color = Geo.vary(Palette.LeafDeep, rng, 0.06)
	local y = trunkH
	local w = rng:range(6, 7.5)
	for _ = 1, 3 do
		local h = w * 0.8
		local cf = base * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, rng:range(0, 6.28), 0)
		-- four wedges make a low-poly pyramid
		for i = 0, 3 do
			local rot = cf * CFrame.Angles(0, i * math.pi / 2, 0)
			Geo.wedge(m, rot * CFrame.new(0, 0, -w / 4), Vector3.new(w, h, w / 2), color, nil, decor())
		end
		y += h * 0.55
		w *= 0.72
	end
	return m
end

function Props.lantern(parent: Instance, base: CFrame, withLight: boolean?): Model
	local m = model("Lantern", parent)
	Geo.block(m, base * CFrame.new(0, 3.5, 0), Vector3.new(0.6, 7, 0.6), Palette.WoodDark, nil, decor())
	Geo.block(m, base * CFrame.new(0, 7.1, 0.8), Vector3.new(0.4, 0.4, 2), Palette.WoodDark, nil, decor())
	local lamp = Geo.block(m, base * CFrame.new(0, 6.4, 1.6), Vector3.new(1, 1.2, 1), Palette.LampGlow, Enum.Material.Neon, noShadow())
	Geo.block(m, base * CFrame.new(0, 7.1, 1.6), Vector3.new(1.3, 0.3, 1.3), Palette.Metal, nil, noShadow())
	if withLight then
		Props.pointLight(lamp, Palette.LampGlow, 16, 1.2)
	end
	return m
end

function Props.barrel(parent: Instance, base: CFrame, rng: Rng.Rng): Model
	local m = model("Barrel", parent)
	local h = 2.6
	local p = base.Position
	Geo.cylinder(m, p + Vector3.new(0, h / 2, 0), h, 2.2, Geo.vary(Palette.Wood, rng), nil, decor())
	Geo.cylinder(m, p + Vector3.new(0, h * 0.25, 0), 0.25, 2.3, Palette.Metal, nil, noShadow())
	Geo.cylinder(m, p + Vector3.new(0, h * 0.75, 0), 0.25, 2.3, Palette.Metal, nil, noShadow())
	return m
end

function Props.crate(parent: Instance, base: CFrame, rng: Rng.Rng, size: number?): Model
	local m = model("Crate", parent)
	local s = size or rng:range(2, 2.8)
	local cf = base * CFrame.Angles(0, rng:range(-0.4, 0.4), 0)
	Geo.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Geo.vary(Palette.WoodLight, rng), nil, decor())
	Geo.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.1, s * 0.22, s + 0.1), Palette.WoodDark, nil, noShadow())
	return m
end

function Props.fence(parent: Instance, from: Vector3, to: Vector3): Model
	local m = model("Fence", parent)
	local delta = to - from
	local length = delta.Magnitude
	local cf = CFrame.lookAt(from, to)
	local posts = math.max(1, math.floor(length / 6))
	for i = 0, posts do
		local p = cf * CFrame.new(0, 1.6, -length * i / posts)
		Geo.block(m, p, Vector3.new(0.7, 3.2, 0.7), Palette.WoodDark, nil, decor())
	end
	Geo.block(m, cf * CFrame.new(0, 2.4, -length / 2), Vector3.new(0.35, 0.4, length), Palette.Wood, nil, noShadow())
	Geo.block(m, cf * CFrame.new(0, 1.3, -length / 2), Vector3.new(0.35, 0.4, length), Palette.Wood, nil, noShadow())
	return m
end

function Props.brazier(parent: Instance, base: CFrame, withLight: boolean?): Model
	local m = model("Brazier", parent)
	local p = base.Position
	Geo.cylinder(m, p + Vector3.new(0, 1.5, 0), 3, 0.9, Palette.Metal, nil, decor())
	Geo.cylinder(m, p + Vector3.new(0, 3.3, 0), 0.8, 2.6, Palette.Metal, nil, decor())
	local coals = Geo.cylinder(m, p + Vector3.new(0, 3.75, 0), 0.25, 2.2, Palette.Ember, Enum.Material.Neon, noShadow())
	Props.emitter(coals, "Fire", nil, 14)
	Props.emitter(coals, "Embers", nil, 4)
	if withLight then
		Props.pointLight(coals, Palette.ForgeGlow, 20, 1.6)
	end
	return m
end

-- Blocky villager. `colors` = { shirt, pants, hat? }
function Props.npc(parent: Instance, base: CFrame, name: string, shirt: Color3, pants: Color3, hat: Color3?): Model
	local m = model(name, parent)
	local skin = Palette.Skin
	Geo.block(m, base * CFrame.new(-0.5, 1, 0), Vector3.new(0.9, 2, 0.9), pants, nil, decor())
	Geo.block(m, base * CFrame.new(0.5, 1, 0), Vector3.new(0.9, 2, 0.9), pants, nil, decor())
	local torso = Geo.block(m, base * CFrame.new(0, 3, 0), Vector3.new(2, 2, 1), shirt, nil, decor())
	Geo.block(m, base * CFrame.new(-1.5, 3, 0) * CFrame.Angles(0, 0, -0.08), Vector3.new(0.9, 2, 0.9), shirt, nil, decor())
	Geo.block(m, base * CFrame.new(1.5, 3, 0) * CFrame.Angles(0, 0, 0.08), Vector3.new(0.9, 2, 0.9), shirt, nil, decor())
	local head = Geo.block(m, base * CFrame.new(0, 4.65, 0), Vector3.new(1.25, 1.25, 1.25), skin, nil, decor())
	-- eyes
	Geo.block(m, base * CFrame.new(-0.28, 4.75, -0.63), Vector3.new(0.18, 0.28, 0.05), Color3.fromRGB(40, 30, 30), nil, noShadow())
	Geo.block(m, base * CFrame.new(0.28, 4.75, -0.63), Vector3.new(0.18, 0.28, 0.05), Color3.fromRGB(40, 30, 30), nil, noShadow())
	if hat then
		Geo.block(m, base * CFrame.new(0, 5.4, 0), Vector3.new(1.5, 0.35, 1.5), hat, nil, decor())
		Geo.block(m, base * CFrame.new(0, 5.7, 0), Vector3.new(1.1, 0.6, 1.1), hat, nil, decor())
	end
	-- apron
	Geo.block(m, base * CFrame.new(0, 2.6, -0.55), Vector3.new(1.6, 2.2, 0.1), Palette.WoodDark, nil, noShadow())
	m.PrimaryPart = torso

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 40)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.fromRGB(255, 236, 200)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = tag
	tag.Parent = head
	return m
end

-- Wooden sign with text on a SurfaceGui (front = base LookVector).
function Props.sign(parent: Instance, base: CFrame, text: string, width: number, height: number, color: Color3?, textColor: Color3?): Part
	local board = Geo.block(parent, base, Vector3.new(width, height, 0.5), color or Palette.WoodDark, nil, decor())
	board.Name = "Sign"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor or Palette.Gold
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = gui
	return board
end

return Props
