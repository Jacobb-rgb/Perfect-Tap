--[[
	HatchFx: the egg hatch with a WOW effect (owner 2026-10-28: "make the
	egg's shaking animation much cooler, so it has a wow effect").
	CapsuleController plays it in the capsule opening; the previews pose the
	same functions frame by frame.

	  build-up  the egg wobbles harder and faster, squashes and stretches,
	            hops; cracks spread over the shell one after another and
	            glow, light rays leak out of them (more, brighter and in the
	            rarest golem's colour for rarer golems); a rising sound,
	            a crack sound per crack, a small camera nudge
	  break     a squash, a stretch, a flash (FlashGap apart at least: no
	            more than 2.5 a second), the halves fly apart, shell pieces
	            and sparkles burst out
	  golem     pops out with a bounce (popAt), SOLID (owner 2026-10-28: "the
	            golems mustn't be see-through"): nothing see-through ever
	            goes over it, no flash, no leak; its rarity glows BEHIND it:
	            the aura bursts out (pulseAura), the turning rays, Mythic's
	            short tint of the backdrop (all under the hero: Tint 1,
	            Aura 2 < the hero's 3); Epic and up get sparkles

	plan(order) says how big each part is per rarity (a longer build-up for
	rarer golems). A plan's numbers, the curves (shakeAt, cracksAt, popAt)
	and the egg's pose (pose: every part placed from its recorded spot, so
	a pooled egg comes back whole with reset) are pure: the Lune specs and
	the previews run them. Several eggs (x3, x10: arrange) wobble together
	and burst one after another (pose's `burstAt`).

	Reduce motion (Motion.reduced(), CapsuleController): none of it; the
	golem only fades in.
]]

local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.UIKit)
local Confetti = require(script.Parent.Confetti)

local HatchFx = {}

HatchFx.FlashGap = 0.4 -- seconds between two flashes at least (2.5 a second at most)
HatchFx.BurstTime = 0.45 -- the halves fly apart and fade
HatchFx.Sequence = 0.14 -- seconds between two eggs bursting (x3, x10)
HatchFx.PopTime = 0.42 -- the golem's bounce
HatchFx.TintTime = 0.7 -- the Mythic screen tint fades out
HatchFx.MaxRays = 12

export type Plan = {
	Order: number, -- the rarest golem's Rarity Order
	Shake: number, -- seconds of build-up
	Rays: number, -- light rays leaking out of the cracks at the end of it
	RayFade: number, -- their transparency at full strength (lower: brighter)
	Sparkles: number, -- sparkles round the golem (0: none)
	Tint: boolean, -- a short tint of the whole screen (Mythic)
	Trauma: number, -- the camera nudge at the break (CameraShake.add)
}

local PLANS: { [number]: Plan } = {
	[1] = { Order = 1, Shake = 1.4, Rays = 4, RayFade = 0.72, Sparkles = 0, Tint = false, Trauma = 0.22 },
	[2] = { Order = 2, Shake = 1.5, Rays = 5, RayFade = 0.66, Sparkles = 0, Tint = false, Trauma = 0.25 },
	[3] = { Order = 3, Shake = 1.7, Rays = 6, RayFade = 0.55, Sparkles = 10, Tint = false, Trauma = 0.3 },
	[4] = { Order = 4, Shake = 1.95, Rays = 8, RayFade = 0.42, Sparkles = 18, Tint = false, Trauma = 0.4 },
	[5] = { Order = 5, Shake = 2.25, Rays = 10, RayFade = 0.3, Sparkles = 24, Tint = false, Trauma = 0.5 },
	[6] = { Order = 6, Shake = 2.55, Rays = 12, RayFade = 0.2, Sparkles = 28, Tint = true, Trauma = 0.6 },
}

-- The hatch for the rarest golem inside (Rarity Order 1..6; outside: the nearest).
function HatchFx.plan(order: number): Plan
	local n = math.clamp(math.floor(if order == order then order else 1), 1, 6)
	return PLANS[n]
end

local function back(x: number): number
	x = math.clamp(x, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

--[[
	The egg `t` seconds into the build-up: its roll (radians), its height
	and width scales (squash and stretch) and a hop (studs). The wobble
	grows and speeds up (3 to 8 a second); the last fifth is a held squash
	(the wobble calms: the egg gathers itself); past Shake (an egg waiting
	its turn to burst) it keeps wobbling at full strength.
]]
function HatchFx.shakeAt(t: number, plan: Plan): (number, number, number, number)
	if t <= 0 then
		return 0, 1, 1, 0
	end
	local d = plan.Shake
	local k = math.clamp(t / d, 0, 1)
	local phase = 2 * math.pi * (3 * t + 2.5 * k * t)
	local amp = 0.06 + 0.32 * k * k
	local squash = (0.03 + 0.11 * k * k) * math.sin(2 * phase)
	local hold = math.clamp((k - 0.8) / 0.2, 0, 1) -- (the last fifth)
	if t >= d then
		hold = 0 -- (waiting its turn: the full wobble)
	end
	local roll = amp * math.sin(phase) * (1 - 0.7 * hold)
	local sy = 1 - squash * (1 - hold) - 0.2 * hold
	local sxz = 1 + squash * 0.5 * (1 - hold) + 0.1 * hold
	local hop = math.max(0, math.sin(phase)) * 0.16 * k * (1 - hold)
	return roll, sy, sxz, hop
end

-- How many of the egg's three cracks glow `t` seconds into the build-up (from a quarter of it on).
function HatchFx.cracksAt(t: number, plan: Plan): number
	local k = t / plan.Shake
	if k < 0.25 then
		return 0
	end
	return math.clamp(math.floor((k - 0.25) / 0.75 * 3) + 1, 1, 3)
end

-- How strong the leaking light is (0..1) `t` seconds into the build-up.
function HatchFx.leakAt(t: number, plan: Plan): number
	local k = t / plan.Shake
	return math.clamp((k - 0.25) / 0.7, 0, 1) ^ 1.5
end

-- The golem's scale `u` seconds after the break: from small, past full size, back (a bounce).
function HatchFx.popAt(u: number): number
	if u <= 0 then
		return 0.25
	end
	return 0.25 + 0.75 * back(u / HatchFx.PopTime)
end

-- May a flash go off now (`last`: the last one's os.clock(); FlashGap apart)?
function HatchFx.flashOk(last: number, now: number): boolean
	return now - last >= HatchFx.FlashGap
end

--[[
	Where `count` eggs stand (x1: one; up to 3: a row; more: rows of five)
	round the origin, and how far the hero camera stands back to see them all.
]]
function HatchFx.arrange(count: number): ({ Vector3 }, number)
	local n = math.clamp(math.floor(count), 1, 10)
	local out: { Vector3 } = {}
	if n == 1 then
		return { Vector3.zero }, 15
	elseif n <= 3 then
		for i = 1, n do
			table.insert(out, Vector3.new((i - (n + 1) / 2) * 3.6, 0, 0))
		end
		return out, 24
	end
	local perRow = 5
	local rows = math.ceil(n / perRow)
	for i = 1, n do
		local col = (i - 1) % perRow
		local row = (i - 1) // perRow
		local inRow = math.min(perRow, n - row * perRow)
		table.insert(out, Vector3.new((col - (inRow - 1) / 2) * 3.5, ((rows - 1) / 2 - row) * 4.4, 0))
	end
	return out, 34
end

---------------------------------------------------------------- the egg

export type Record = {
	Model: Model,
	Parts: { BasePart },
	Base: { CFrame }, -- each part's place from the egg's centre, as built
	Sizes: { Vector3 },
	Trans: { number },
	Colors: { Color3 },
	Top: { [BasePart]: boolean }, -- the parts of the top half
	Cracks: { BasePart },
	Band: BasePart?,
	Center: CFrame,
	-- the rigid moves (many eggs, and every egg once its halves fly): Model:PivotTo moves
	-- the parts in one call instead of one CFrame a part from Lua
	Pivot: CFrame, -- the model's pivot from the centre
	Halves: { { Model: Model, Pivot: CFrame } }?, -- the Top and Bottom halves (with their pivots), when both pivot
	Bent: boolean, -- a part's size or place is squashed or stretched now (the next pose puts each back)
	Faded: boolean, -- every part is fully see-through after the break (nothing more to write)
}

-- Records an egg as built (GolemBuilder.capsule: halves Top / Bottom, Crack1..3, the Band).
function HatchFx.record(model: Model): Record
	local root = model.PrimaryPart
	local center = if root then root.CFrame else model:GetPivot()
	local rec: Record = {
		Model = model,
		Parts = {},
		Base = {},
		Sizes = {},
		Trans = {},
		Colors = {},
		Top = {},
		Cracks = {},
		Band = nil,
		Center = center,
		Pivot = center:ToObjectSpace(model:GetPivot()),
		Halves = nil,
		Bent = false,
		Faded = false,
	}
	local top = model:FindFirstChild("Top")
	local bottom = model:FindFirstChild("Bottom")
	if top and bottom and top:IsA("Model") and bottom:IsA("Model") and top.PrimaryPart and bottom.PrimaryPart then
		rec.Halves = {
			{ Model = top, Pivot = center:ToObjectSpace(top:GetPivot()) },
			{ Model = bottom, Pivot = center:ToObjectSpace(bottom:GetPivot()) },
		}
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(rec.Parts, d)
			table.insert(rec.Base, center:ToObjectSpace(d.CFrame))
			table.insert(rec.Sizes, d.Size)
			table.insert(rec.Trans, d.Transparency)
			table.insert(rec.Colors, d.Color)
			if top and d:IsDescendantOf(top) then
				rec.Top[d] = true
			end
			if d.Name == "Band" then
				rec.Band = d
			end
		end
	end
	for i = 1, 3 do
		local crack = model:FindFirstChild("Crack" .. i, true)
		if crack and crack:IsA("BasePart") then
			rec.Cracks[i] = crack
		end
	end
	return rec
end

-- Puts a pooled egg back as it was built (its parts' size, look and the cracks hidden).
function HatchFx.reset(rec: Record)
	for i, part in rec.Parts do
		part.Size = rec.Sizes[i]
		part.Transparency = rec.Trans[i]
		part.Color = rec.Colors[i]
		part.CFrame = rec.Center * rec.Base[i]
	end
	rec.Bent = false
	rec.Faded = false
end

--[[
	Poses an egg `t` seconds into its hatch at `place` (its centre):
	before `burstAt` the build-up (shakeAt: the roll, the squash and
	stretch when `squash`, the hop; the cracks glowing in `color`, the band
	turning to it); after it the break (a stretch, then the halves fly
	apart and fade in BurstTime). `squash` false (many eggs: cheaper) moves
	the parts rigidly.
]]
function HatchFx.pose(rec: Record, place: CFrame, t: number, burstAt: number, plan: Plan, color: Color3, squash: boolean)
	if t < burstAt then
		local roll, sy, sxz, hop = HatchFx.shakeAt(t, plan)
		if not squash then
			sy, sxz = 1, 1
		end
		local cf = place * CFrame.new(0, hop, 0) * CFrame.Angles(0, 0.4 * math.sin(t * 2), roll)
		local scale = Vector3.new(sxz, sy, sxz)
		if squash then
			for i, part in rec.Parts do
				local base = rec.Base[i]
				part.CFrame = cf * CFrame.new(base.Position * scale) * base.Rotation
				part.Size = rec.Sizes[i] * scale
			end
			rec.Bent = true
		elseif rec.Bent then
			for i, part in rec.Parts do
				part.CFrame = cf * rec.Base[i]
				part.Size = rec.Sizes[i]
			end
			rec.Bent = false
		else
			rec.Model:PivotTo(cf * rec.Pivot) -- (rigid: one call moves every part)
		end
		local lit = HatchFx.cracksAt(t, plan)
		for i, crack in rec.Cracks do
			if i <= lit then
				crack.Transparency = 0
				crack.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
			end
		end
		local band = rec.Band
		if band then
			local k = math.clamp(t / plan.Shake, 0, 1)
			local index = table.find(rec.Parts, band)
			band.Color = (if index then rec.Colors[index] else band.Color):Lerp(color, k)
		end
		return
	end
	-- the break: a stretch, then the halves fly apart and fade
	local u = t - burstAt
	local k = math.clamp(u / HatchFx.BurstTime, 0, 1)
	local stretch = if squash and u < 0.08 then 1.22 else 1
	local up = place * CFrame.new(1.4 * k, 1.4 + 5 * k, 0) * CFrame.Angles(0, 0, -1.6 * k) * CFrame.new(0, -1.4, 0)
	local down = place * CFrame.new(-0.8 * k, -4 * k * k, 0) * CFrame.Angles(0, 0, 0.8 * k)
	if rec.Faded then
		return -- (gone: nothing left to move or fade)
	end
	local halves = rec.Halves
	if stretch ~= 1 or rec.Bent or not halves then
		-- part by part: the stretch, the first frame after it (each part back in place, its
		-- size as built: written once, not every frame), or an egg without two halves
		local s = Vector3.new(0.88, stretch, 0.88)
		for i, part in rec.Parts do
			local base = rec.Base[i]
			local half = if rec.Top[part] then up else down
			if stretch ~= 1 then
				part.CFrame = half * CFrame.new(base.Position * s) * base.Rotation
				part.Size = rec.Sizes[i] * s
			else
				part.CFrame = half * base
				if rec.Bent then
					part.Size = rec.Sizes[i]
				end
			end
		end
		rec.Bent = stretch ~= 1
	else
		-- the halves fly rigidly: two calls (the root pivot stays: it is invisible)
		halves[1].Model:PivotTo(up * halves[1].Pivot)
		halves[2].Model:PivotTo(down * halves[2].Pivot)
	end
	for i, part in rec.Parts do
		if string.sub(part.Name, 1, 5) ~= "Crack" then
			part.Transparency = rec.Trans[i] + (1 - rec.Trans[i]) * k
		else
			part.Transparency = k
		end
	end
	rec.Faded = k >= 1
end

---------------------------------------------------------------- the overlay

export type Overlay = {
	Leak: Frame, -- the light rays leaking out of the cracks (over the egg)
	Rays: { Frame },
	Aura: Frame, -- the golem's soft glow (behind it)
	Rings: { Frame },
	Tint: Frame, -- the Mythic screen tint
	Burst: Frame, -- the layer the pieces fly in (round the hero)
	Shards: { Frame },
	Sparkles: { Frame },
	Confetti: { Frame },
}

-- Builds the hatch's pieces into the opening's gui (place() puts them on the hero).
function HatchFx.overlay(gui: Instance): Overlay
	-- (the tint colours the backdrop only: ZIndex 1, right over the dim, under the rays and the hero)
	local tint = UIKit.new("Frame", {
		Name = "HatchTint",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -40),
		Size = UDim2.new(1, 0, 1, 80),
		ZIndex = 1,
	}, gui) :: Frame
	local aura = UIKit.new("Frame", {
		Name = "HatchAura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 460),
		Visible = false,
		ZIndex = 2,
	}, gui) :: Frame
	UIKit.new("UIScale", { Name = "Pulse", Scale = 1 }, aura)
	local rings: { Frame } = {}
	for i, k in { 1, 0.74, 0.5 } do
		local ring = UIKit.new("Frame", {
			Name = "Ring" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.82 - i * 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			ZIndex = 2,
		}, aura) :: Frame
		UIKit.corner(ring, 999)
		table.insert(rings, ring)
	end
	local leak = UIKit.new("Frame", {
		Name = "HatchLeak",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 460),
		Visible = false,
		ZIndex = 4,
	}, gui) :: Frame
	local rays: { Frame } = {}
	for i = 1, HatchFx.MaxRays do
		-- a thin beam from the middle out, bright at the shell and fading (turned a little unevenly)
		local holder = UIKit.new("Frame", {
			Name = "Beam" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * (360 / HatchFx.MaxRays) + (i % 3) * 11,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, leak) :: Frame
		local ray = UIKit.new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.5, 0, 0, if i % 2 == 0 then 10 else 16),
			ZIndex = 4,
		}, holder) :: Frame
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.18, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(rays, ray)
	end
	local layer = UIKit.new("Frame", {
		Name = "HatchBurst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1100, 900),
		ZIndex = 6,
	}, gui) :: Frame
	return {
		Leak = leak,
		Rays = rays,
		Aura = aura,
		Rings = rings,
		Tint = tint,
		Burst = layer,
		Shards = Confetti.build(layer, 18, 6),
		Sparkles = Confetti.build(layer, 28, 7),
		Confetti = Confetti.build(layer, Confetti.Count, 8),
	}
end

-- Puts the pieces on the hero (its centre and size in the gui's units: CapsuleView.layoutOpening).
function HatchFx.place(fx: Overlay, center: UDim2, size: number)
	fx.Leak.Position = center
	fx.Leak.Size = UDim2.fromOffset(size * 1.5, size * 1.5)
	fx.Aura.Position = center
	fx.Aura.Size = UDim2.fromOffset(size * 1.25, size * 1.25)
	fx.Burst.Position = center
	fx.Burst.Size = UDim2.fromOffset(size * 2.6, size * 2.2)
end

-- The leaking light `t` seconds into the build-up (none after it: `t` nil), in `color`.
function HatchFx.setLeak(fx: Overlay, t: number?, plan: Plan, color: Color3)
	if not t then
		fx.Leak.Visible = false
		return
	end
	local strength = HatchFx.leakAt(t, plan)
	fx.Leak.Visible = strength > 0
	fx.Leak.Rotation = t * 24
	local shown = math.max(1, math.ceil(plan.Rays * strength))
	for i, ray in fx.Rays do
		ray.Visible = i <= shown
		ray.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		ray.BackgroundTransparency = 1 - (1 - plan.RayFade) * strength
		ray.Size = UDim2.new(0.25 + 0.25 * strength, 0, 0, ray.Size.Y.Offset)
	end
end

-- The golem's aura (behind it) in its rarity colour; `strength` 0 hides it.
function HatchFx.setAura(fx: Overlay, color: Color3, strength: number)
	fx.Aura.Visible = strength > 0
	for i, ring in fx.Rings do
		ring.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15 * i)
		ring.BackgroundTransparency = 1 - (0.12 + 0.08 * i) * math.clamp(strength, 0, 1)
	end
end

-- The aura bursts out behind the golem (from small, past full size, back), the
-- golem's glow in place of a flash over it (not with Reduce motion).
function HatchFx.pulseAura(fx: Overlay)
	local pulse = fx.Aura:FindFirstChild("Pulse")
	if pulse and pulse:IsA("UIScale") then
		pulse.Scale = 0.4
		TweenService:Create(pulse, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- The Mythic tint `u` seconds after the break (none once it faded).
function HatchFx.setTint(fx: Overlay, color: Color3, u: number?)
	if not u or u >= HatchFx.TintTime then
		fx.Tint.BackgroundTransparency = 1
		return
	end
	fx.Tint.BackgroundColor3 = color
	fx.Tint.BackgroundTransparency = 0.45 + 0.55 * math.clamp(u / HatchFx.TintTime, 0, 1)
end

-- The shell pieces' colours (the egg's shell) and the sparkles' (white and gold, a touch of the rarity's).
function HatchFx.paint(fx: Overlay, shell: Color3, rarity: Color3)
	for i, piece in fx.Shards do
		piece.BackgroundColor3 = if i % 3 == 0 then shell:Lerp(Color3.new(0, 0, 0), 0.25) else shell
	end
	for i, piece in fx.Sparkles do
		piece.BackgroundColor3 = if i % 3 == 0
			then rarity:Lerp(Color3.new(1, 1, 1), 0.4)
			elseif i % 3 == 1 then Color3.fromRGB(255, 226, 120)
			else Color3.new(1, 1, 1)
	end
end

-- Hides every piece (between two openings).
function HatchFx.clear(fx: Overlay)
	fx.Leak.Visible = false
	fx.Aura.Visible = false
	fx.Tint.BackgroundTransparency = 1
	for _, list in { fx.Shards, fx.Sparkles, fx.Confetti } do
		for _, piece in list do
			piece.Visible = false
		end
	end
end

return HatchFx
