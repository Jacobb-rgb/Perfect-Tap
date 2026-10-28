--[[
	Hover rings: the ripples on the ground under a hoverboard (owner
	2026-10-28: "like Pet Simulator 99", where every board leaves soft white
	rings under it). Pure: only Instance creation, so Lune tests and previews
	can build it; the client (HoverboardController) moves them every frame
	for the boards on screen.

	Each ring is a circle of two half-circle Beams between two Attachments on
	the board's Root at ground height (Beam curves: a cubic half circle has its
	control points 4/3 x the radius out), FaceCamera so the line reads from any
	angle. Under each hover pad (front and back) the rings grow out from the
	pad and fade, one after the other (Period seconds each, Rings per pad).
	Nothing is made while riding: step() only moves the attachments, sets the
	curve sizes and picks a precomputed Transparency.

	The Root bobs, pitches, rolls into turns and kickflips; the rings must not
	(they would sink into the floor on one side): step() takes the ground's
	frame in Root space (groundFrame: level, at the floor, turned only with the
	board's carve), so they stay flat on the ground.

	Lite (phones, crowds): one ring per pad.
]]

local HoverboardRings = {}

HoverboardRings.Period = 1.1 -- seconds a ring takes to grow out and fade
HoverboardRings.Rings = 2 -- per pad (Lite: 1)
HoverboardRings.From = 0.5 -- start radius (studs)
HoverboardRings.To = 2.0 -- end radius
HoverboardRings.Width = 0.13
HoverboardRings.Lift = 0.06 -- above the ground
HoverboardRings.Steps = 12 -- transparency steps (no NumberSequence made per frame)
local K = 4 / 3 -- cubic Bezier half circle
local TURN = CFrame.Angles(0, -math.pi / 2, 0)

export type Ring = {
	A: Attachment,
	B: Attachment,
	Halves: { Beam },
	Phase: number, -- 0..1 offset in the period
	Step: number, -- the transparency step shown (-1 = hidden)
}
export type RingSet = {
	Rings: { Ring },
	Pads: { number }, -- each ring's pad z (Root space)
	Root: BasePart?,
	Shown: boolean,
}

local FADE: { NumberSequence } = {}
for i = 0, HoverboardRings.Steps do
	-- 0 = a fresh ring (0.25 transparent) .. Steps = gone
	FADE[i + 1] = NumberSequence.new(0.25 + 0.75 * i / HoverboardRings.Steps)
end

local function half(a: Attachment, b: Attachment, color: Color3): Beam
	local beam = Instance.new("Beam")
	beam.Name = "HoverRing"
	beam.Attachment0 = a
	beam.Attachment1 = b
	beam.Color = ColorSequence.new(color)
	beam.Transparency = FADE[#FADE]
	beam.Width0 = HoverboardRings.Width
	beam.Width1 = HoverboardRings.Width
	beam.FaceCamera = true
	beam.Segments = 12
	beam.LightEmission = 0.6
	beam.LightInfluence = 0.2
	beam.Texture = ""
	beam.Enabled = false
	return beam
end

-- A new (unmounted, hidden) ring set; `color` tints the rings (white with a touch of the board's glow).
function HoverboardRings.create(color: Color3?, lite: boolean?): RingSet
	local tint = (color or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 1, 1), 0.7)
	local rings: { Ring } = {}
	local pads: { number } = {}
	local perPad = if lite then 1 else HoverboardRings.Rings
	for pad = 1, 2 do
		for i = 1, perPad do
			local a = Instance.new("Attachment")
			a.Name = "HoverRingA"
			local b = Instance.new("Attachment")
			b.Name = "HoverRingB"
			table.insert(rings, {
				A = a,
				B = b,
				Halves = { half(a, b, tint), half(a, b, tint) },
				Phase = (i - 1) / perPad + (pad - 1) * 0.25,
				Step = -1,
			})
			table.insert(pads, 0)
		end
	end
	return { Rings = rings, Pads = pads, Root = nil, Shown = false }
end

local function each(set: RingSet, fn: (Instance) -> ())
	for _, ring in set.Rings do
		fn(ring.A)
		fn(ring.B)
		for _, beam in ring.Halves do
			fn(beam)
		end
	end
end

-- Puts the rings under a board's Root: the pads sit at `padZ` and -`padZ` (Root space).
function HoverboardRings.mount(set: RingSet, root: BasePart, padZ: number)
	set.Root = root
	local n = #set.Rings
	for i = 1, n do
		set.Pads[i] = if i <= n / 2 then -padZ else padZ
	end
	each(set, function(inst: Instance)
		inst.Parent = root
	end)
	HoverboardRings.hide(set)
end

function HoverboardRings.unmount(set: RingSet)
	HoverboardRings.hide(set)
	each(set, function(inst: Instance)
		inst.Parent = nil
	end)
	set.Root = nil
end

function HoverboardRings.destroy(set: RingSet)
	each(set, function(inst: Instance)
		inst:Destroy()
	end)
	set.Root = nil
end

function HoverboardRings.hide(set: RingSet)
	for _, ring in set.Rings do
		ring.Step = -1
		for _, beam in ring.Halves do
			beam.Enabled = false
		end
	end
	set.Shown = false
end

-- The radius (studs) and the fade step (0 .. Steps) of a ring at time `t`.
function HoverboardRings.at(phase: number, t: number): (number, number)
	local u = (t / HoverboardRings.Period + phase) % 1
	local radius = HoverboardRings.From + (HoverboardRings.To - HoverboardRings.From) * (1 - (1 - u) * (1 - u))
	return radius, math.clamp(math.floor(u * HoverboardRings.Steps + 0.5), 0, HoverboardRings.Steps)
end

--[[
	The ground's frame in the board Root's space, for a Root welded to the
	character with `c0` (Weld.C1 = identity): `floor` = the floor under the
	character in its root's space (the weld's rest offset), `drop` = studs the
	ground lies below that floor (a jump: the ground stays where it was), `yaw`
	= the board's carve. Level and at the floor whatever the Root's bob, pitch,
	roll and flip.
]]
function HoverboardRings.groundFrame(c0: CFrame, floor: CFrame, drop: number, yaw: number): CFrame
	return c0:Inverse() * floor * CFrame.new(0, -drop, 0) * CFrame.Angles(0, yaw, 0)
end

--[[
	One frame: every ring grows out from its pad and fades. `alpha` 0..1 fades the
	whole set (0 = hidden: in the air, off screen). `ground` = the ground's frame in
	Root space (groundFrame; nil = the Root's own, a board resting on the ground).
]]
function HoverboardRings.step(set: RingSet, t: number, alpha: number, ground: CFrame?)
	if not set.Root or alpha <= 0.02 then
		if set.Shown then
			HoverboardRings.hide(set)
		end
		return
	end
	set.Shown = true
	local base = ground or CFrame.identity
	local y = HoverboardRings.Lift
	local extra = math.floor((1 - math.clamp(alpha, 0, 1)) * HoverboardRings.Steps + 0.5)
	for i, ring in set.Rings do
		local radius, step = HoverboardRings.at(ring.Phase, t)
		step = math.min(HoverboardRings.Steps, step + extra)
		local z = set.Pads[i]
		-- the attachments' X axis (Beam curve direction) points along +Z
		ring.A.CFrame = base * CFrame.new(radius, y, z) * TURN
		ring.B.CFrame = base * CFrame.new(-radius, y, z) * TURN
		local curve = K * radius
		local front, back = ring.Halves[1], ring.Halves[2]
		front.CurveSize0, front.CurveSize1 = curve, -curve
		back.CurveSize0, back.CurveSize1 = -curve, curve
		if step ~= ring.Step then
			ring.Step = step
			local fade = FADE[step + 1]
			local on = step < HoverboardRings.Steps
			for _, beam in ring.Halves do
				beam.Transparency = fade
				beam.Enabled = on
			end
		end
	end
end

-- Rings showing right now (tests).
function HoverboardRings.visible(set: RingSet): number
	local n = 0
	for _, ring in set.Rings do
		if ring.Halves[1].Enabled then
			n += 1
		end
	end
	return n
end

return HoverboardRings
