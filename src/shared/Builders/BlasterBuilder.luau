--[[
	Builds the laser Blaster tool (design v2, replaces the pickaxe): the
	owner-approved Kenney Blaster Kit shapes (CC0, rebuilt from parts, never
	meshes) with the Ore Glow skins, made by Builders/KenneyBlaster (shapes
	traced by tools/kenney/blaster_lite.py into Builders/KenneyShapes).

	  look        the colors of a level in an ore (BlasterData.skin): body,
	              accents, steel, the glows; level 1 (or no ore) is the
	              rusty starter. Bright glows are pulled toward the body color
	              and darkened by luminance, so neon never blooms into white
	              blobs; the beam (Look.Glow, attribute Glow) keeps the ore's
	              own glow. MiningService and the previews read it too.
	  build       the held Tool (at most MaxParts parts): an invisible Handle
	              at the hand (Tool.Grip = identity: the barrel straight along
	              the arm), every part welded to it, the Muzzle attachment at
	              the barrel's tip (the client beam starts there)
	  buildStar   a STAR blaster (StarBlasterData) in the player's hand:
	              its own Kenney shape (KenneyBlaster.Models 11-15) and sky
	              skin (starSkin, the previews use it too), the forged
	              level's Range and Level (the client's range and gates),
	              the star's Glow as the beam, attribute Star = its id
	  silhouette  a level's black outline (the Foundry's NEXT rack, the
	              gallery's LV 11)

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local KenneyBlaster = require(script.Parent.KenneyBlaster)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)
local StarBlasterData = require(script.Parent.Parent.Config.StarBlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
BlasterBuilder.MaxParts = KenneyBlaster.MaxParts
BlasterBuilder.StarLightRange = 8 -- studs: a STAR blaster's own glow

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local STEEL = Color3.fromRGB(150, 158, 180) -- Kenney's light blue-grey steel (front blocks, handles, magazines)
local STEEL_DARK = Color3.fromRGB(70, 73, 84) -- steel next to light grey ore bodies (two-tone instead of grey on grey)
local STEEL_MID = Color3.fromRGB(120, 124, 136) -- handles and posts next to light grey ore bodies (they stay visible)
local WOOD = Color3.fromRGB(92, 60, 40)
local RUST_RED = Color3.fromRGB(140, 82, 64) -- the starter's body is pulled toward this brown-red rust
local RUST_STEEL = Color3.fromRGB(100, 104, 114) -- the starter's cool, dark worn iron

local PLASTIC = Enum.Material.SmoothPlastic

export type Look = {
	Level: number,
	Rusty: boolean,
	Body: Color3,
	Accent: Color3,
	Glow: Color3, -- the ore's own glow: the beam color (attribute Glow)
	GlowSoft: Color3, -- bigger glowing pieces (vents, lit slots)
	GlowCore: Color3, -- small glowing pieces (core, muzzle, lens, cell)
	Dark: Color3,
	Grip: Color3,
	Steel: Color3,
	Trim: Color3, -- carry handles and sight posts
	BodyMaterial: Enum.Material,
	SteelMaterial: Enum.Material,
	LitSlots: boolean, -- light grey bodies: the side slots glow (one clear color accent)
}

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

local function luma(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

--[[
	Neon blooms into a white blob when all three channels are high (bright cyan, gold,
	mint and pale glows). Decided by luminance: the brighter the glow, the more it is
	saturated (one channel drops, so it glows in its color instead of white) and a
	little dimmed; near-white glows (diamond, quartz) only get a hint of their hue and
	are dimmed more. `amount` = how much dimmer in general.
]]
local function softGlow(glow: Color3, amount: number): Color3
	local hue, sat, v = glow:ToHSV()
	local bright = math.clamp((luma(glow) - 0.4) / 0.35, 0, 1)
	local colored = math.clamp((sat - 0.08) / 0.2, 0, 1)
	local target = 0.35 + 0.5 * colored
	local s = sat + math.max(0, target - sat) * bright
	local dim = amount + (0.25 + 0.08 * (1 - colored)) * bright
	return Color3.fromHSV(hue, s, v * (1 - dim))
end

-- The colors of a blaster (also used for the beam color: Look.Glow).
function BlasterBuilder.look(level: any, oreId: string?): Look
	local info = BlasterData.get(level)
	local rusty = info.Level <= 1 or not oreId or oreId == ""
	local body, glow = BlasterData.skin(if rusty then "" else oreId)
	if rusty then
		-- a desaturated brown-red rust body on cool, dark worn iron (no copper orange);
		-- the corrosion is only on the rear chamfer
		return {
			Level = info.Level,
			Rusty = true,
			Body = body:Lerp(RUST_RED, 0.85),
			Accent = Color3.fromRGB(112, 62, 42),
			Glow = glow,
			GlowSoft = softGlow(glow, 0.2),
			GlowCore = softGlow(glow, 0.05),
			Dark = darker(IRON, 0.25),
			Grip = WOOD,
			Steel = RUST_STEEL,
			Trim = RUST_STEEL,
			BodyMaterial = PLASTIC,
			SteelMaterial = PLASTIC,
			LitSlots = false,
		}
	end
	-- very dark ores (coal, obsidian) keep a readable body
	local _, sat, v = body:ToHSV()
	if v < 0.32 then
		body = lighter(body, 0.18)
	end
	-- light grey bodies (silver, iron, quartz, diamond, moonstone): dark steel and glowing slots,
	-- so the gun stays two-tone and keeps one clear color accent
	local greyish = sat < 0.3 and v > 0.5
	return {
		Level = info.Level,
		Rusty = false,
		Body = body,
		-- accents are a darker body color (a lighter one vanished next to the body)
		Accent = if v < 0.45 then lighter(body, 0.45) else darker(body, if v > 0.85 then 0.3 else 0.25),
		Glow = glow,
		GlowSoft = softGlow(glow, 0.2),
		GlowCore = softGlow(glow, 0.05),
		Dark = if v < 0.32 then IRON_LIGHT elseif greyish then darker(IRON, 0.3) else IRON,
		Grip = IRON:Lerp(body, 0.12),
		Steel = if greyish then STEEL_DARK else STEEL,
		Trim = if greyish then STEEL_MID else STEEL,
		BodyMaterial = PLASTIC,
		SteelMaterial = PLASTIC, -- Kenney's steel is flat, like toy plastic
		LitSlots = greyish,
	}
end

-- A new Blaster tool (no parts yet) with the attributes the client reads.
local function newTool(tip: string, level: number, oreId: string?, glow: Color3): Tool
	local tool = Instance.new("Tool")
	tool.Name = BlasterBuilder.ToolName
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.identity
	tool:SetAttribute("Level", level)
	tool:SetAttribute("OreId", if oreId then oreId else "")
	tool:SetAttribute("Range", BlasterData.get(level).Range)
	tool:SetAttribute("Glow", glow)
	return tool
end

-- The gun's parts on an invisible Handle (model = KenneyBlaster's shape 1-15).
local function assemble(tool: Tool, model: number, ore: string, skin: KenneyBlaster.Skin): Tool
	local lv = model
	local handle = Geo.make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.3, 0.6, 0.3),
		Color = skin.Base,
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = true,
		CastShadow = false,
		CFrame = CFrame.identity,
	})
	handle.Parent = tool
	local function part(name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, className: string?): BasePart
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or PLASTIC,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			CastShadow = false,
		})
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local anchors = KenneyBlaster.parts(lv, ore, skin, part)
	-- flames (hot ores) or sparks around the gun from level 7: slow, short-lived (phones)
	local fxCf, fxSize = KenneyBlaster.effects(lv)
	if fxCf and fxSize then
		local holder = part("Effects", fxCf, fxSize, skin.Glow)
		holder.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = if skin.Magma then "GunFlame" else "GunSpark"
		emitter.Texture = if skin.Magma
			then "rbxasset://textures/particles/fire_main.dds"
			else "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(skin.Glow)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Rate = if lv >= 10 then 8 else 5
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, if skin.Magma then 3 else 0.5, 0)
		emitter.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, if skin.Magma then 0.35 else 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = holder
	end
	-- where the beam leaves the barrel
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = anchors.Muzzle
	muzzle.Parent = handle
	return tool
end

--[[
	The blaster tool of a level in an ore's look: the owner-approved Kenney
	Blaster Kit shapes with the Ore Glow skins (Builders/KenneyBlaster, at
	most BlasterBuilder.MaxParts parts). The Handle is an invisible block at
	the hand (Tool.Grip = identity: the barrel straight along the arm), every
	part is welded to it, the Muzzle attachment sits at the barrel's tip.
	From level 7 a slow GunFlame / GunSpark emitter rides along the gun.
]]
function BlasterBuilder.build(level: any, oreId: string?): Tool
	local lv = BlasterData.get(level).Level
	local look = BlasterBuilder.look(lv, oreId)
	local ore = if look.Rusty or not oreId then "" else oreId
	local skin = KenneyBlaster.skin(lv, ore, look)
	return assemble(newTool(BlasterData.displayName(lv, oreId), lv, oreId, look.Glow), lv, ore, skin)
end

--[[
	A STAR blaster's shape and skin: (KenneyBlaster model 11-15, the ore key
	its skin is made with, the skin): Tier 4, the jewellery (KenneyBlaster:
	a bigger cluster in a gold setting, a crown of six on a gold collar, the
	star's cut gems in gold bezels, gold trim). They are paid weapons.
]]
function BlasterBuilder.starSkin(star: StarBlasterData.StarBlaster): (number, string, KenneyBlaster.Skin)
	local model = 10 + star.Index
	-- (only CaseBuilder.HotOres matters: Emberite burns, StarCore is a cool sky)
	local ore = if star.Magma then "Emberite" else "StarCore"
	local skin = KenneyBlaster.skin(model, ore, { Body = star.Body, Glow = star.Glow, Rusty = false })
	skin.Tier = 4
	skin.Gem = star.Gem
	return model, ore, skin
end

-- A STAR blaster for a player whose forged blaster is `level` in `oreId`
-- (the range and the client's level gates follow the forged one).
function BlasterBuilder.buildStar(star: StarBlasterData.StarBlaster, level: any, oreId: string?): Tool
	local lv = BlasterData.get(level).Level
	local model, ore, skin = BlasterBuilder.starSkin(star)
	local tool = newTool(star.Name, lv, oreId, star.Glow)
	tool:SetAttribute("Star", star.Id)
	assemble(tool, model, ore, skin)
	-- a paid weapon glows: a soft light in its color around the player (no shadows: phones)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local light = Instance.new("PointLight")
		light.Name = "StarGlow"
		light.Color = star.Glow
		light.Range = BlasterBuilder.StarLightRange
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = handle
	end
	return tool
end

--[[
	A level's black silhouette (the whole outline in one color, 8-23 parts):
	a Model of anchored, non-colliding parts in the gun's frame (the hand at
	the origin, the barrel along -Z). The Foundry's NEXT rack and the
	gallery's LV 11 use it.
]]
function BlasterBuilder.silhouette(level: any, color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "Silhouette"
	local lv = math.max(2, BlasterData.get(level).Level)
	KenneyBlaster.silhouette(lv, color or Color3.fromRGB(20, 18, 26), function(name, cf, size, c, material, className)
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = c,
			Material = material or PLASTIC,
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		})
		p.Parent = model
		return p
	end)
	return model
end

return BlasterBuilder
