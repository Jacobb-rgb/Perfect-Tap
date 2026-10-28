--[[
	The effects of the backpacks (owner 2026-10-24 on the first proposal:
	"doplnil nejake efekty a detaily ... mega efektové"): particles and a
	light, on top of BackpackBuilder's parts. The two starter packs have none;
	from the Leather Rucksack up each pack has more:

	  LeatherRucksack  a gold glint on the brass shield                   1.5/s
	  MinersPack       the lantern glows (light) and glints, the spilled
	                   teal ore twinkles                                   5/s
	  IronboundPack    the blue gem glints and sparkles (light)            6/s
	  ExplorersPack    teal sparkles round the compass (light)             5/s
	  AmethystPack     violet sparkles rising off the crystal clusters
	                   (light)                                            12/s
	  RuneboundPack    cyan rune motes rising off the flap, the star
	                   crystal glints (light)                             10/s
	  EmberforgePack   fire and smoke out of both chimneys, embers round
	                   the pack, the fire crystal glints (light)          36/s
	  StarforgePack    stars twinkling round the top, sparkles off both
	                   wings, the star crystal glints (light)             22/s

	Emitters go into the model's FxBox parts (BackpackBuilder: attribute
	"FxBox" = the box name) and emit from the box volume, so they ride along
	when the pack is rigged to a character. The light (one PointLight,
	Shadows off) is created Enabled = false: the client turns on only the
	local player's own (like the head lamps, GearConfig.LampBudget).
	`lite` (low-end phones, other players' packs) halves every rate.

	Pure: only Instance creation (no services), so Lune tests and previews can
	build it.
]]

local BackpackData = require(script.Parent.Parent.Config.BackpackData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local BackpackFx = {}

BackpackFx.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"
BackpackFx.Fire = "rbxasset://textures/particles/fire_main.dds"
BackpackFx.Smoke = "rbxasset://textures/particles/smoke_main.dds"
BackpackFx.LightName = "BackpackLight"

export type Kind = "Glint" | "Sparkle" | "Rune" | "Fire" | "Smoke" | "Ember" | "Star"

export type Effect = {
	Box: string, -- the FxBox the particles come out of
	Kind: Kind,
	Color: Color3,
	Rate: number, -- particles per second (full mode)
}

export type LightSpec = {
	Box: string,
	Color: Color3,
	Range: number,
	Brightness: number,
}

export type Spec = {
	Effects: { Effect },
	Light: LightSpec?,
}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

local function packGlow(id: string): Color3
	return glow(BackpackData.ById[id].Colors.Glow)
end

BackpackFx.Specs = {
	LeatherRucksack = {
		Effects = {
			{ Box = "Gem", Kind = "Glint", Color = rgb(255, 214, 120), Rate = 1.5 },
		},
	},
	MinersPack = {
		Effects = {
			{ Box = "Lantern", Kind = "Glint", Color = packGlow("MinersPack"), Rate = 3 },
			{ Box = "Ore", Kind = "Glint", Color = glow(rgb(60, 220, 200)), Rate = 2 },
		},
		Light = { Box = "Light", Color = rgb(255, 190, 110), Range = 8, Brightness = 0.5 },
	},
	IronboundPack = {
		Effects = {
			{ Box = "Gem", Kind = "Glint", Color = packGlow("IronboundPack"), Rate = 3 },
			{ Box = "Gem", Kind = "Sparkle", Color = packGlow("IronboundPack"), Rate = 3 },
		},
		Light = { Box = "Light", Color = rgb(90, 170, 255), Range = 6, Brightness = 0.43 },
	},
	ExplorersPack = {
		Effects = {
			{ Box = "Gem", Kind = "Sparkle", Color = packGlow("ExplorersPack"), Rate = 4 },
			{ Box = "Gem", Kind = "Glint", Color = WHITE, Rate = 1 },
		},
		Light = { Box = "Light", Color = rgb(90, 240, 200), Range = 6, Brightness = 0.25 },
	},
	AmethystPack = {
		Effects = {
			{ Box = "Crystals", Kind = "Sparkle", Color = packGlow("AmethystPack"), Rate = 5 },
			{ Box = "TopCrystals", Kind = "Sparkle", Color = packGlow("AmethystPack"), Rate = 4 },
			{ Box = "TopCrystals", Kind = "Glint", Color = glow(rgb(200, 170, 255)), Rate = 3 },
		},
		Light = { Box = "Light", Color = rgb(180, 120, 255), Range = 8, Brightness = 0.5 },
	},
	RuneboundPack = {
		Effects = {
			{ Box = "Runes", Kind = "Rune", Color = packGlow("RuneboundPack"), Rate = 6 },
			{ Box = "Gem", Kind = "Glint", Color = glow(rgb(190, 240, 255)), Rate = 4 },
		},
		Light = { Box = "Light", Color = rgb(110, 210, 255), Range = 8, Brightness = 0.54 },
	},
	EmberforgePack = {
		Effects = {
			{ Box = "ChimneyLeft", Kind = "Fire", Color = packGlow("EmberforgePack"), Rate = 10 },
			{ Box = "ChimneyRight", Kind = "Fire", Color = packGlow("EmberforgePack"), Rate = 10 },
			{ Box = "ChimneyLeft", Kind = "Smoke", Color = rgb(70, 64, 66), Rate = 3 },
			{ Box = "ChimneyRight", Kind = "Smoke", Color = rgb(70, 64, 66), Rate = 3 },
			{ Box = "Aura", Kind = "Ember", Color = glow(rgb(255, 150, 40)), Rate = 7 },
			{ Box = "Gem", Kind = "Glint", Color = glow(rgb(255, 220, 90)), Rate = 3 },
		},
		Light = { Box = "Light", Color = rgb(255, 140, 60), Range = 9, Brightness = 0.58 },
	},
	StarforgePack = {
		Effects = {
			{ Box = "Aura", Kind = "Star", Color = glow(rgb(200, 180, 255)), Rate = 8 },
			{ Box = "WingLeft", Kind = "Sparkle", Color = packGlow("StarforgePack"), Rate = 5 },
			{ Box = "WingRight", Kind = "Sparkle", Color = packGlow("StarforgePack"), Rate = 5 },
			{ Box = "Gem", Kind = "Glint", Color = glow(rgb(160, 235, 255)), Rate = 4 },
		},
		Light = { Box = "Light", Color = rgb(170, 140, 255), Range = 9, Brightness = 0.4 },
	},
} :: { [string]: Spec }

local function seq(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i, v in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(points)
end

-- One emitter of `kind` (the look of each kind lives here).
local function emitter(effect: Effect, lite: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Backpack" .. effect.Kind
	e.Texture = BackpackFx.Sparkle
	e.Color = ColorSequence.new(effect.Color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Transparency = seq(0.1, 0.3, 1)
	e.SpreadAngle = Vector2.new(20, 20)
	e.EmissionDirection = Enum.NormalId.Top
	local kind = effect.Kind
	if kind == "Glint" then
		-- a quick twinkle that sits still and shrinks away
		e.Size = seq(0.35, 0.2, 0)
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(0, 0)
	elseif kind == "Sparkle" then
		e.Size = seq(0.22, 0.16, 0)
		e.Lifetime = NumberRange.new(0.9, 1.5)
		e.Speed = NumberRange.new(0.4, 0.9)
		e.Drag = 1
	elseif kind == "Rune" then
		-- motes drifting up off the runes, speeding up a little
		e.Size = seq(0.16, 0.22, 0)
		e.Lifetime = NumberRange.new(1.2, 1.8)
		e.Speed = NumberRange.new(0.4, 0.7)
		e.Acceleration = Vector3.new(0, 0.5, 0)
		e.SpreadAngle = Vector2.new(8, 8)
		e.RotSpeed = NumberRange.new(0, 0)
	elseif kind == "Fire" then
		e.Texture = BackpackFx.Fire
		e.Size = seq(0.42, 0.3, 0.05)
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(1.4, 2)
		e.SpreadAngle = Vector2.new(10, 10)
		e.Transparency = seq(0.15, 0.4, 1)
	elseif kind == "Smoke" then
		e.Texture = BackpackFx.Smoke
		e.LightEmission = 0
		e.LightInfluence = 1
		e.Size = seq(0.35, 0.9, 1.4)
		e.Lifetime = NumberRange.new(1.4, 2)
		e.Speed = NumberRange.new(1, 1.5)
		e.Transparency = seq(0.55, 0.75, 1)
		e.Drag = 0.6
	elseif kind == "Ember" then
		e.Size = seq(0.12, 0.1, 0)
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(0.5, 1.2)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, 0.6, 0)
	else -- Star
		e.Size = seq(0, 0.3, 0)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.1, 0.3)
		e.RotSpeed = NumberRange.new(-120, 120)
	end
	e.Rate = if lite then effect.Rate * 0.5 else effect.Rate
	return e
end

-- The FxBox parts of a built pack by name.
local function boxes(model: Model): { [string]: BasePart }
	local out: { [string]: BasePart } = {}
	for _, p in model:GetChildren() do
		local name = p:GetAttribute("FxBox")
		if p:IsA("BasePart") and type(name) == "string" then
			out[name] = p
		end
	end
	return out
end

--[[
	Puts a pack's effects into its model (BackpackBuilder.build, rigged or
	not): the emitters (returned, enabled) and the light (Enabled = false,
	see the header). A pack with no effects gets nothing.
]]
function BackpackFx.apply(model: Model, lite: boolean?): ({ ParticleEmitter }, PointLight?)
	local id = model:GetAttribute("BackpackId")
	local spec = if type(id) == "string" then BackpackFx.Specs[id] else nil
	local made: { ParticleEmitter } = {}
	if not spec then
		return made, nil
	end
	local byName = boxes(model)
	for _, effect in spec.Effects do
		local box = byName[effect.Box]
		if box then
			local e = emitter(effect, lite == true)
			e.Parent = box
			table.insert(made, e)
		end
	end
	local light: PointLight? = nil
	local lightSpec = spec.Light
	local lightBox = if lightSpec then byName[lightSpec.Box] else nil
	if lightSpec and lightBox then
		local l = Instance.new("PointLight")
		l.Name = BackpackFx.LightName
		l.Color = lightSpec.Color
		l.Range = lightSpec.Range
		l.Brightness = lightSpec.Brightness
		l.Shadows = false
		l.Enabled = false
		l.Parent = lightBox
		light = l
	end
	return made, light
end

return BackpackFx
