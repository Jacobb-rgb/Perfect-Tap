--[[
	BagFly: the mining reel's last step (owner 2026-10-27: "the crystal floats
	up glowing, then flies into your bag"), drawn on its own overlay. Pure
	builders + poses (MineJuiceController plays them, the Lune previews pose
	the same frames); positions are screen pixels in the overlay.

	  build()  -> View: Gui = ScreenGui "TerraForgeJuice" (DisplayOrder 9, no
	              UIScale: pixels like the level orbs; the controller passes
	              the HUD's UI scale), JuiceConfig.Flyers ore icons and 3 bumps
	  setOre(flyer, color?)         nil = a dirty chunk (grey stone with gold
	                                flecks: never a rarity colour), a colour =
	                                a cleaned ore's gem
	  poseFlyer(flyer, from, to, t, scale, seed) -> done
	                                t seconds after the pickup: pops up at
	                                `from` glowing and floats up (Rise), then
	                                flies on an arc into `to`, shrinking (Fly)
	  poseBump(bump, at, size, t, scale, reduced?) -> done
	                                the landing: a white flash and a ring
	                                round the slot / backpack button (`size`
	                                px) that grows and fades, a +1 pops above
	Reduce motion: the controller (Effects/MineJuiceRules.pickup) plays neither
	the flight nor the bump, only the sound; poseBump's `reduced` (a still
	ring, the +1 fading in straight) is kept for callers that want it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("Config"):WaitForChild("JuiceConfig"))
local PopTheme = require(Shared:WaitForChild("Config"):WaitForChild("PopTheme"))
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local PopWord = require(script.Parent.PopWord)

local BagFly = {}

BagFly.Rise = 0.34 -- seconds: pops up and floats up at the pickup spot
BagFly.Fly = 0.46 -- seconds: the arc into the bag
BagFly.RiseHeight = 54 -- pixels at UI scale 1
BagFly.Icon = 56 -- pixels at UI scale 1
BagFly.BumpSeconds = 0.85
BagFly.Bumps = 3

export type Flyer = {
	Holder: Frame,
	Scale: UIScale,
	Halo: Frame,
	Glow: Frame,
	Chunk: Frame,
	Facet: Frame,
	Flecks: { Frame },
	Dirty: boolean,
}

export type Bump = {
	Ring: Frame,
	RingScale: UIScale,
	RingStroke: UIStroke,
	Flash: Frame,
	Plus: PopWord.Word,
	PlusAt: Frame,
	Fit: UIScale,
}

export type View = {
	Gui: ScreenGui,
	Flyers: { Flyer },
	Bumps: { Bump },
}

local WHITE = Color3.new(1, 1, 1)

local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end

local function easeOutBack(x: number): number
	local c1, c3 = 2.0, 3.0
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function round(frame: Frame)
	UIKit.corner(frame, 999)
end

local function flyer(gui: ScreenGui, i: number): Flyer
	local size = BagFly.Icon
	local holder = UIKit.new("Frame", {
		Name = "Ore" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Visible = false,
		ZIndex = 2,
	}, gui)
	local scale = UIKit.new("UIScale", { Scale = 1 }, holder)
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = JuiceConfig.GlintColor,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.7, 1.7),
		ZIndex = 1,
	}, holder)
	round(halo)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = JuiceConfig.GlintColor:Lerp(WHITE, 0.35),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.05, 1.05),
		ZIndex = 2,
	}, holder)
	round(glow)
	local chunk = UIKit.new("Frame", {
		Name = "Chunk",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.66, 0.56),
		Rotation = -14,
		ZIndex = 3,
	}, holder)
	UIKit.corner(chunk, 11)
	UIKit.new("UIGradient", { Name = "Shade", Color = ColorSequence.new(WHITE, WHITE), Rotation = 90 }, chunk)
	Pop.border(chunk, 3)
	local facet = UIKit.new("Frame", {
		Name = "Facet",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.16, 0.14),
		Size = UDim2.fromScale(0.42, 0.26),
		Rotation = -8,
		ZIndex = 4,
	}, chunk)
	UIKit.corner(facet, 5)
	local flecks: { Frame } = {}
	for k, spot in { Vector3.new(0.66, 0.58, 0.2), Vector3.new(0.34, 0.66, 0.14) } do
		local fleck = UIKit.new("Frame", {
			Name = "Fleck" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = JuiceConfig.GlintColor,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(spot.X, spot.Y),
			Size = UDim2.fromScale(spot.Z, spot.Z * 1.15),
			Rotation = 45,
			ZIndex = 5,
		}, chunk)
		UIKit.new("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 0.3 }, fleck)
		table.insert(flecks, fleck)
	end
	local f: Flyer = {
		Holder = holder,
		Scale = scale,
		Halo = halo,
		Glow = glow,
		Chunk = chunk,
		Facet = facet,
		Flecks = flecks,
		Dirty = true,
	}
	BagFly.setOre(f, nil)
	return f
end

local function bump(gui: ScreenGui, i: number): Bump
	local ring = UIKit.new("Frame", {
		Name = "Bump" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(60, 60),
		Visible = false,
		ZIndex = 3,
	}, gui)
	UIKit.corner(ring, 14)
	local ringScale = UIKit.new("UIScale", { Scale = 1 }, ring)
	local stroke = UIKit.new("UIStroke", {
		Name = "Ring",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = JuiceConfig.GlintColor:Lerp(WHITE, 0.4),
		Thickness = 4,
	}, ring)
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, ring)
	UIKit.corner(flash, 14)
	local plusHolder = UIKit.new("Frame", {
		Name = "PlusAt" .. i,
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1, 1),
		ZIndex = 6,
	}, gui)
	local fit = UIKit.new("UIScale", { Scale = 1 }, plusHolder)
	local plus = PopWord.build(plusHolder, "+1", 34, { Colors = "Gold", Tilt = -8, Seconds = BagFly.BumpSeconds, Rise = 26, Z = 7 })
	plus.Holder.AnchorPoint = Vector2.new(0.5, 1)
	plus.Holder.Position = UDim2.fromScale(0.5, 0)
	return { Ring = ring, RingScale = ringScale, RingStroke = stroke, Flash = flash, Plus = plus, PlusAt = plusHolder, Fit = fit }
end

function BagFly.build(): View
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeJuice",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9,
	})
	local flyers: { Flyer } = {}
	for i = 1, JuiceConfig.Flyers do
		table.insert(flyers, flyer(gui, i))
	end
	local bumps: { Bump } = {}
	for i = 1, BagFly.Bumps do
		table.insert(bumps, bump(gui, i))
	end
	return { Gui = gui, Flyers = flyers, Bumps = bumps }
end

--[[
	The icon's look: nil = a dirty chunk (stone grey, gold flecks, the warm
	gold glow; the same for every ore), a colour = a cleaned ore (a gem in
	its colour, its glow tinted).
]]
function BagFly.setOre(f: Flyer, color: Color3?)
	local dirty = color == nil
	f.Dirty = dirty
	local base = color or JuiceConfig.DirtyChunk
	f.Chunk.BackgroundColor3 = WHITE
	local shade = f.Chunk:FindFirstChild("Shade") :: UIGradient?
	if shade then
		shade.Color = ColorSequence.new(base:Lerp(WHITE, 0.35), base:Lerp(PopTheme.Outline, 0.3))
	end
	f.Chunk.Rotation = if dirty then -14 else 45
	f.Chunk.Size = if dirty then UDim2.fromScale(0.66, 0.56) else UDim2.fromScale(0.52, 0.52)
	for _, fleck in f.Flecks do
		fleck.Visible = dirty
	end
	local glow = if dirty then JuiceConfig.GlintColor else base
	f.Halo.BackgroundColor3 = glow
	f.Glow.BackgroundColor3 = glow:Lerp(WHITE, 0.35)
end

-- A point on the quadratic arc a -> c -> b at u (0..1).
local function arc(a: Vector2, c: Vector2, b: Vector2, u: number): Vector2
	local p = a:Lerp(c, u)
	local q = c:Lerp(b, u)
	return p:Lerp(q, u)
end

--[[
	The icon `t` seconds after the pickup, from `from` to `to` (overlay
	pixels), `scale` = the HUD's UI scale, `seed` varies the arc. Returns
	true when it has landed (then hidden).
]]
function BagFly.poseFlyer(f: Flyer, from: Vector2, to: Vector2, t: number, scale: number, seed: number): boolean
	local total = BagFly.Rise + BagFly.Fly
	if t < 0 or t >= total then
		f.Holder.Visible = false
		return t >= total
	end
	f.Holder.Visible = true
	local risen = from - Vector2.new(0, BagFly.RiseHeight * scale)
	local size: number
	local p: Vector2
	if t < BagFly.Rise then
		-- pops out at the pickup spot and floats up, glowing
		local k = span(t, 0, BagFly.Rise)
		p = from:Lerp(risen, easeOut(k)) + Vector2.new(0, math.sin(t * 20) * 2 * scale * k)
		size = easeOutBack(span(t, 0, 0.16)) * (1 + 0.06 * math.sin(t * 16))
		f.Holder.Rotation = 8 * math.sin(t * 12)
		f.Glow.BackgroundTransparency = 0.25 + 0.15 * math.sin(t * 24)
		f.Halo.Size = UDim2.fromScale(1.4 + 0.6 * easeOut(k), 1.4 + 0.6 * easeOut(k))
		f.Halo.BackgroundTransparency = 0.7
	else
		-- flies on an arc into the bag, faster and faster, shrinking
		local u = span(t, BagFly.Rise, total)
		local e = u * u * (2.2 - 1.2 * u)
		local side = math.sin(seed * 12.9898) * 70 * scale
		local control = (risen + to) / 2 + Vector2.new(side, -90 * scale)
		p = arc(risen, control, to, e)
		size = 1 - 0.45 * e
		f.Holder.Rotation = 200 * e * (if math.cos(seed * 7.1) > 0 then 1 else -1)
		f.Glow.BackgroundTransparency = 0.35 + 0.3 * u
		f.Halo.Size = UDim2.fromScale(2 - 0.6 * u, 2 - 0.6 * u)
		f.Halo.BackgroundTransparency = 0.7 + 0.25 * u
	end
	f.Holder.Position = UDim2.fromOffset(math.floor(p.X + 0.5), math.floor(p.Y + 0.5))
	f.Scale.Scale = math.max(0, size * scale)
	return false
end

--[[
	The landing at `at` (overlay pixels) on a target `size` pixels big, `t`
	seconds after it landed: a white flash, a gold ring that grows and fades,
	a +1 above. Returns true when it is over (then hidden).
]]
function BagFly.poseBump(b: Bump, at: Vector2, size: Vector2, t: number, scale: number, reduced: boolean?): boolean
	local done = PopWord.pose(b.Plus, t, reduced)
	b.Fit.Scale = scale
	-- (the +1 sits on its own holder just above the target)
	b.PlusAt.Position = UDim2.fromOffset(math.floor(at.X + 0.5), math.floor(at.Y - size.Y / 2 - 4 * scale))
	local ringOver = t < 0 or t >= 0.45
	b.Ring.Visible = not ringOver
	if not ringOver then
		b.Ring.Position = UDim2.fromOffset(math.floor(at.X + 0.5), math.floor(at.Y + 0.5))
		b.Ring.Size = UDim2.fromOffset(math.floor(size.X + 8 * scale), math.floor(size.Y + 8 * scale))
		local k = span(t, 0, 0.45)
		b.RingScale.Scale = if reduced then 1 else 1 + 0.45 * easeOut(k)
		b.RingStroke.Transparency = k
		b.RingStroke.Thickness = math.max(1, 5 * scale * (1 - 0.6 * k))
		b.Flash.BackgroundTransparency = 0.3 + 0.7 * span(t, 0, 0.25)
	end
	return done and ringOver
end

return BagFly
