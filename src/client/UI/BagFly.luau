--[[
	BagFly: the mining reel's last step (owner 2026-10-27: "the crystal floats
	up glowing, then flies into your bag"), drawn on its own overlay. Pure
	builders + poses (MineJuiceController plays them, the Lune previews pose
	the same frames); positions are screen pixels in the overlay. The ore that
	flies is the real 3D chunk (owner 2026-10-28: "the whole 3D ore, not an
	icon"): a ViewportFrame per flyer showing ItemBuilder's model, tumbling.

	  build()  -> View: Gui = ScreenGui "TerraForgeJuice" (DisplayOrder 9, no
	              UIScale: pixels like the level orbs; the controller passes
	              the HUD's UI scale), JuiceConfig.Flyers ores and 3 bumps
	  setOre(flyer, oreId?, kind?, recipe?)
	                                nil = a dirty chunk: the world's Raw chunk
	                                (ItemBuilder) with its glints in the one
	                                neutral JuiceConfig.GlintColor (never a
	                                rarity colour); an ore id = that item's
	                                model (`kind`: Clean when nil, Crushed,
	                                Ingot, Gear, Alloy, Relic (its id), with
	                                `recipe`), its glow tinted
	  poseFlyer(flyer, from, to, t, scale, seed, lift?) -> done
	                                t seconds after the pickup: pops up at
	                                `from` glowing and floats up (Rise), then
	                                flies on an arc into `to`, shrinking (Fly),
	                                tumbling in 3D all the way; `lift` = the
	                                world chunk's size on screen (pixels): it
	                                starts that big (clamped), as if the chunk
	                                itself lifted off the ground
	  poseBump(bump, at, size, t, scale, reduced?, flash?, plusT?) -> done
	                                the landing: a white flash (flash ~= false;
	                                the controller allows one per
	                                MineJuiceRules.flareGap per target) and a
	                                ring round the slot / backpack button
	                                (`size` px) that grows and fades, a +1 pops
	                                above (`plusT` seconds in: a merged landing
	                                pops the +N again, the ring stays as it is)
Perf (phones first): every flyer's dirty chunk is built once (build), a
cleaned item's model once per flyer (setOre; the last CleanCache kept), all
of them still (anchored, no collisions, no welds, sparkles or lights). The
tumble turns the viewport's camera and light round the model: one CFrame
per flyer per frame, no tables, no parts moved.
Reduce motion: the controller (Effects/MineJuiceRules.pickup) plays neither
the flight nor the bump, only the sound; poseBump's `reduced` (a still
ring, the +1 fading in straight) is kept for callers that want it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("Config"):WaitForChild("JuiceConfig"))
local OreData = require(Shared:WaitForChild("Config"):WaitForChild("OreData"))
local ArtifactConfig = require(Shared:WaitForChild("Config"):WaitForChild("ArtifactConfig"))
local ItemBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("ItemBuilder"))
local UIKit = require(script.Parent.UIKit)
local PopWord = require(script.Parent.PopWord)

local BagFly = {}

BagFly.Rise = 0.34 -- seconds: pops up and floats up at the pickup spot
BagFly.Fly = 0.46 -- seconds: the arc into the bag
BagFly.RiseHeight = 54 -- pixels at UI scale 1
BagFly.Icon = 56 -- pixels at UI scale 1: the chunk's size on screen (its viewport is ViewSize times that)
BagFly.ViewSize = 1.7 -- the viewport round the chunk (it tumbles: room for every corner)
BagFly.Fov = 30
BagFly.LiftMin = 0.7 -- a lifted chunk starts 0.7 to 1.8 times the flying size
BagFly.LiftMax = 1.8
BagFly.ChunkStuds = 1.5 -- a chunk's width in the world (the controller measures it on screen)
BagFly.CleanCache = 3 -- cleaned item models kept per flyer
-- the item kinds that fly as their own model (CarryService's Pickup sends the kind; Raw never: the secret)
BagFly.Kinds = { Clean = true, Crushed = true, Ingot = true, Gear = true, Alloy = true, Relic = true } :: { [string]: boolean }
BagFly.BumpSeconds = 0.85
BagFly.Bumps = 3

export type Flyer = {
	Holder: Frame,
	Scale: UIScale,
	Halo: Frame,
	Glow: Frame,
	View: ViewportFrame,
	Camera: Camera,
	Model: Model, -- the one in the view now
	DirtyModel: Model,
	Clean: { [string]: Model }, -- "kind|id|recipe" -> its model (not shown: no parent)
	CleanOrder: { string }, -- oldest first
	Radius: { [Model]: number }, -- every model's reach round its middle (the camera's distance)
	Base: CFrame, -- the camera before the tumble
	Dirty: boolean,
	OreId: string?,
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
-- the camera looks from the front-left, a bit from above (Pop.show's view); the light falls from
-- above the camera, a little from the picture's left: lit top and front, darker far sides
local VIEW_FROM = Vector3.new(-0.55, 0.42, -1).Unit
local LIGHT = Vector3.new(-0.16, -0.74, 0.65).Unit
local CORNERS = {
	Vector3.new(1, 1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, -1),
}

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

--[[
	A built item made still for a viewport: only its parts (no welds,
	sparkles or lights), anchored, no collisions or queries, invisible parts
	dropped, its middle moved to the origin. Returns how far its farthest
	corner reaches from the middle (the same whichever way it turns).
]]
local function still(model: Model): number
	local all: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Parent = model
			table.insert(all, d)
		end
	end
	-- every part sits straight in the model now: the rest (welds, sparkles, lights) goes
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			for _, extra in d:GetChildren() do
				extra:Destroy()
			end
		else
			d:Destroy()
		end
	end
	local parts: { BasePart } = {}
	for _, part in all do
		if part.Transparency >= 0.99 then
			part:Destroy()
		else
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			table.insert(parts, part)
		end
	end
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in parts do
		local half = part.Size / 2
		for _, corner in CORNERS do
			local at = part.CFrame * (corner * half)
			lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
			hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
		end
	end
	if #parts == 0 then
		return 1
	end
	local middle = CFrame.new(-(lo + hi) / 2)
	local reach = 0.5
	for _, part in parts do
		part.CFrame = middle * part.CFrame
		local half = part.Size / 2
		for _, corner in CORNERS do
			reach = math.max(reach, (part.CFrame * (corner * half)).Magnitude)
		end
	end
	return reach
end

-- The dirty chunk: the world's Raw chunk (the same for every ore), its glints in the neutral GlintColor.
local function dirtyModel(): Model
	local model = ItemBuilder.build({ Kind = "Raw", OreId = OreData.List[1].Id }, CFrame.new(), "BagFly")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Glint" then
			d.Color = JuiceConfig.GlintColor
		end
	end
	model.Name = "DirtyOre"
	return model
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
	-- a soft warm glow behind the chunk (two faint discs), the 3D chunk on top
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = JuiceConfig.GlintColor,
		BackgroundTransparency = 0.84,
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
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.05, 1.05),
		ZIndex = 2,
	}, holder)
	round(glow)
	local view = UIKit.new("ViewportFrame", {
		Name = "View",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(BagFly.ViewSize, BagFly.ViewSize),
		Ambient = Color3.fromRGB(150, 146, 142),
		LightColor = Color3.fromRGB(255, 248, 236),
		LightDirection = LIGHT,
		ZIndex = 3,
	}, holder)
	local camera = Instance.new("Camera")
	camera.FieldOfView = BagFly.Fov
	camera.Parent = view
	view.CurrentCamera = camera
	local dirty = dirtyModel()
	local radius: { [Model]: number } = {}
	radius[dirty] = still(dirty)
	dirty.Parent = view
	local f: Flyer = {
		Holder = holder,
		Scale = scale,
		Halo = halo,
		Glow = glow,
		View = view,
		Camera = camera,
		Model = dirty,
		DirtyModel = dirty,
		Clean = {},
		CleanOrder = {},
		Radius = radius,
		Base = CFrame.new(),
		Dirty = true,
		OreId = nil,
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

-- A cleaned item's model for this flyer: built the first time, then kept (the last CleanCache
-- items); nil when the builder can't make it (it flies as a dirty chunk then).
local function cleanModel(f: Flyer, oreId: string, kind: string, recipe: string?): Model?
	local key = `{kind}|{oreId}|{recipe or ""}`
	local kept: Model? = f.Clean[key]
	if kept then
		return kept
	end
	local ok, built = pcall(ItemBuilder.build, { Kind = kind, OreId = oreId, Recipe = recipe }, CFrame.new(), oreId)
	if not ok or typeof(built) ~= "Instance" then
		return nil
	end
	local model = built :: Model
	f.Radius[model] = still(model)
	f.Clean[key] = model
	table.insert(f.CleanOrder, key)
	return model
end

--[[
	What flies: nil = a dirty chunk (the world's Raw chunk, its glints and
	glow the neutral GlintColor: the same for every ore); an id = that
	item's model (`kind` nil = Clean; Crushed, Ingot, Gear, Alloy with
	`recipe`; Relic with an ArtifactConfig id), its glow tinted in the ore's
	colour. An unknown id or kind flies as a dirty chunk.
]]
function BagFly.setOre(f: Flyer, oreId: string?, kind: string?, recipe: string?)
	local itemKind = if kind and BagFly.Kinds[kind] then kind else "Clean"
	-- (a relic's id is an ArtifactConfig one; everything else is made of an ore)
	local known = oreId ~= nil and (if itemKind == "Relic" then ArtifactConfig.ById[oreId] ~= nil else OreData.ById[oreId] ~= nil)
	local built = if known and oreId then cleanModel(f, oreId, itemKind, recipe) else nil
	local ore = if built and oreId then OreData.ById[oreId] else nil
	f.Dirty = built == nil
	f.OreId = if built then oreId else nil
	local model = built or f.DirtyModel
	if f.Model ~= model then
		f.Model.Parent = nil
		model.Parent = f.View
		f.Model = model
	end
	-- the oldest cleaned ores beyond the cache go (a new one is the newest: the one showing stays)
	while #f.CleanOrder > math.max(1, BagFly.CleanCache) do
		local id = table.remove(f.CleanOrder, 1) :: string
		local old = f.Clean[id]
		f.Clean[id] = nil
		f.Radius[old] = nil
		old:Destroy()
	end
	-- far enough that the model's farthest corner stays in view however it turns
	local distance = (f.Radius[model] or 1) / math.sin(math.rad(BagFly.Fov / 2))
	f.Base = CFrame.lookAt(VIEW_FROM * distance, Vector3.zero)
	f.Camera.CFrame = f.Base
	f.View.LightDirection = LIGHT
	local glow = if ore then ore.Color else JuiceConfig.GlintColor
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
	The tumble: the model turned `angle` about a tilted axis of its own
	(`seed`). The camera and the light go round it the other way instead,
	which looks the same and moves no parts.
]]
local function tumble(f: Flyer, seed: number, angle: number)
	local axis = Vector3.new(math.sin(seed * 3.7), 0.9, math.cos(seed * 5.3)).Unit
	local back = CFrame.fromAxisAngle(axis, -angle)
	f.Camera.CFrame = back * f.Base
	f.View.LightDirection = back:VectorToWorldSpace(LIGHT)
end

--[[
	The ore `t` seconds after the pickup, from `from` to `to` (overlay
	pixels), `scale` = the HUD's UI scale, `seed` varies the arc and the
	tumble, `lift` = the world chunk's size on screen (pixels; nil: it pops
	in from nothing). Returns true when it has landed (then hidden).
]]
function BagFly.poseFlyer(f: Flyer, from: Vector2, to: Vector2, t: number, scale: number, seed: number, lift: number?): boolean
	local total = BagFly.Rise + BagFly.Fly
	if t < 0 or t >= total then
		f.Holder.Visible = false
		return t >= total
	end
	f.Holder.Visible = true
	local risen = from - Vector2.new(0, BagFly.RiseHeight * scale)
	local turn = if math.cos(seed * 7.1) > 0 then 1 else -1
	local size: number
	local p: Vector2
	local angle: number
	if t < BagFly.Rise then
		-- lifts off at the pickup spot and floats up, glowing, slowly turning
		local k = span(t, 0, BagFly.Rise)
		p = from:Lerp(risen, easeOut(k)) + Vector2.new(0, math.sin(t * 20) * 2 * scale * k)
		if lift then
			-- from the chunk's own size on the ground to the flying size, with a small pop
			local icon = BagFly.Icon * scale
			local start = math.clamp(lift, icon * BagFly.LiftMin, icon * BagFly.LiftMax) / icon
			size = start + (1 - start) * easeOut(k) + 0.1 * math.sin(math.pi * span(t, 0, 0.2))
		else
			size = easeOutBack(span(t, 0, 0.16)) * (1 + 0.06 * math.sin(t * 16))
		end
		angle = 2.2 * t
		f.Glow.BackgroundTransparency = 0.48 + 0.1 * math.sin(t * 24)
		f.Halo.Size = UDim2.fromScale(1.4 + 0.6 * easeOut(k), 1.4 + 0.6 * easeOut(k))
		f.Halo.BackgroundTransparency = 0.76
	else
		-- flies on an arc into the bag, faster and faster, shrinking, tumbling over
		local u = span(t, BagFly.Rise, total)
		local e = u * u * (2.2 - 1.2 * u)
		local side = math.sin(seed * 12.9898) * 70 * scale
		local control = (risen + to) / 2 + Vector2.new(side, -90 * scale)
		p = arc(risen, control, to, e)
		size = 1 - 0.45 * e
		angle = 2.2 * BagFly.Rise + 6.5 * e
		f.Glow.BackgroundTransparency = 0.55 + 0.35 * u
		f.Halo.Size = UDim2.fromScale(2 - 0.6 * u, 2 - 0.6 * u)
		f.Halo.BackgroundTransparency = 0.78 + 0.2 * u
	end
	f.Holder.Position = UDim2.fromOffset(math.floor(p.X + 0.5), math.floor(p.Y + 0.5))
	f.Scale.Scale = math.max(0, size * scale)
	tumble(f, seed, turn * angle)
	return false
end

--[[
	The landing at `at` (overlay pixels) on a target `size` pixels big, `t`
	seconds after it landed: a white flash, a gold ring that grows and fades,
	a +1 above. Returns true when it is over (then hidden).
]]
function BagFly.poseBump(
	b: Bump,
	at: Vector2,
	size: Vector2,
	t: number,
	scale: number,
	reduced: boolean?,
	flash: boolean?,
	plusT: number?
): boolean
	local done = PopWord.pose(b.Plus, plusT or t, reduced)
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
		b.Flash.BackgroundTransparency = if flash == false then 1 else 0.3 + 0.7 * span(t, 0, 0.25)
	end
	return done and ringOver
end

return BagFly
