--[[
	Lightning on the hoverboards (owner 2026-10-24: "cool effects, e.g.
	lightning shooting out of the hoverboard"). Pure: only Instance creation,
	so Lune tests and previews can build it; the client (HoverboardController
	through HoverboardFx) re-shapes the bolts a few times a second.

	A bolt is a jagged line: Segments + 1 Attachments under the board's Root
	and, per segment, a thin white-hot core Beam plus a wide coloured glow
	Beam (no textures: solid beams, FaceCamera). Made once per effect set and
	pooled with it; flicker() only moves attachments and toggles beams.

	  Arcs    bolts that crackle out of the board's edges (wing tips, nose,
	          tail, thrusters) down to the ground around it, or crawl across
	          the deck from one edge to another. A dark arc lights with the
	          chance Duty + speed and surges (the hop on, the top speed burst,
	          a landing) and then HOLDS its shape for OnTicks flickers, goes
	          dark and stays dark for at least OffTicks: no strobing (each arc
	          changes at most about twice a second, review 2026-10-25)
	  Strike  one big bolt from the sky onto the board, for the hop on: shaped
	          once, then faded out (strike alpha)

	Per board effect (HoverboardData.Effect), colour = the board's Glow:
	  Sparks  Timber Drifter      1 arc, rare
	  Vents   Cart Cruiser        2 arcs
	  Lava    Emberglass Glider   2 arcs
	  Phoenix Royal Phoenix       3 arcs, often, longer
	  Custom  Terra Forge Custom  3 arcs, often, longer, each in a rainbow colour
	Lite (phones, crowds): half the arcs (at least 1), no glow beams on arcs.
]]

local HoverboardBolts = {}

HoverboardBolts.Segments = 5 -- per arc
HoverboardBolts.StrikeSegments = 8
HoverboardBolts.StrikeHeight = 28 -- studs above the board the strike comes from
HoverboardBolts.FlickerEvery = 0.18 -- seconds between flicker ticks (HoverboardController)
HoverboardBolts.OnTicks = 3 -- a lit arc holds its shape for 3..4 ticks
HoverboardBolts.OffTicks = 2 -- then stays dark for at least 2 ticks
HoverboardBolts.CoreWidth = 0.09
HoverboardBolts.GlowWidth = 0.34
HoverboardBolts.CoreTransparency = 0.3
HoverboardBolts.GlowTransparency = 0.65
-- where arcs may start: Root attachments of every board (HoverboardBuilder contract)
HoverboardBolts.StartMounts = { "TipLeft", "TipRight", "Nose", "TrailLeft", "TrailRight", "Exhaust1" }

export type Spec = { Arcs: number, Duty: number, Reach: number }
HoverboardBolts.Specs = {
	Sparks = { Arcs = 1, Duty = 0.1, Reach = 1.8 },
	Vents = { Arcs = 2, Duty = 0.14, Reach = 2.0 },
	Lava = { Arcs = 2, Duty = 0.18, Reach = 2.2 },
	Phoenix = { Arcs = 3, Duty = 0.32, Reach = 2.7 },
	Custom = { Arcs = 3, Duty = 0.32, Reach = 2.7 },
} :: { [string]: Spec }

export type Bolt = {
	Points: { Attachment },
	Cores: { Beam },
	Glows: { Beam },
	Visible: boolean,
	Ticks: number, -- > 0: lit ticks left; < 0: dark ticks left before it may light again
	Alpha: number, -- the strike's fade (1 = full)
}
export type BoltSet = {
	Arcs: { Bolt },
	Strike: Bolt,
	Duty: number,
	Reach: number,
	Starts: { Vector3 },
	Root: BasePart?,
}

local WHITE = Color3.new(1, 1, 1)

local function beam(a0: Attachment, a1: Attachment, color: Color3, width: number, transparency: number): Beam
	local b = Instance.new("Beam")
	b.Name = "Bolt"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.Width0 = width
	b.Width1 = width
	b.FaceCamera = true
	b.Segments = 1
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Texture = ""
	b.Enabled = false
	return b
end

local function bolt(segments: number, color: Color3, coreWidth: number, glowWidth: number?): Bolt
	local points: { Attachment } = {}
	for i = 1, segments + 1 do
		local a = Instance.new("Attachment")
		a.Name = "BoltPoint" .. i
		table.insert(points, a)
	end
	local cores: { Beam } = {}
	local glows: { Beam } = {}
	local core = color:Lerp(WHITE, 0.7)
	for i = 1, segments do
		-- thinner toward the far end
		local taper = 1 - 0.45 * (i - 1) / math.max(1, segments - 1)
		table.insert(cores, beam(points[i], points[i + 1], core, coreWidth * taper, HoverboardBolts.CoreTransparency))
		if glowWidth then
			table.insert(glows, beam(points[i], points[i + 1], color, glowWidth * taper, HoverboardBolts.GlowTransparency))
		end
	end
	return { Points = points, Cores = cores, Glows = glows, Visible = false, Ticks = 0, Alpha = 1 }
end

-- A new (unmounted, hidden) bolt set for a board effect, or nil for effects without lightning.
-- `palette`: one colour per arc, in turn (the Custom's rainbow); else every arc is `color`.
function HoverboardBolts.create(effect: string, color: Color3, lite: boolean?, palette: { Color3 }?): BoltSet?
	local spec = HoverboardBolts.Specs[effect]
	if not spec then
		return nil
	end
	local count = if lite then math.max(1, math.floor(spec.Arcs / 2)) else spec.Arcs
	local arcs: { Bolt } = {}
	for i = 1, count do
		-- spread over the palette (3 arcs on 6 colours: red, yellow, blue)
		local step = if palette then math.max(1, math.floor(#palette / count)) else 1
		local tint = if palette and #palette > 0 then palette[((i - 1) * step) % #palette + 1] else color
		table.insert(arcs, bolt(HoverboardBolts.Segments, tint, HoverboardBolts.CoreWidth, if lite then nil else HoverboardBolts.GlowWidth))
	end
	return {
		Arcs = arcs,
		Strike = bolt(HoverboardBolts.StrikeSegments, color, 0.22, 0.9),
		Duty = spec.Duty,
		Reach = spec.Reach,
		Starts = {},
		Root = nil,
	}
end

local function eachOf(b: Bolt, fn: (Instance) -> ())
	for _, a in b.Points do
		fn(a)
	end
	for _, beamPart in b.Cores do
		fn(beamPart)
	end
	for _, beamPart in b.Glows do
		fn(beamPart)
	end
end

local function each(set: BoltSet, fn: (Instance) -> ())
	for _, b in set.Arcs do
		eachOf(b, fn)
	end
	eachOf(set.Strike, fn)
end

local function show(b: Bolt, on: boolean)
	if b.Visible == on then
		return
	end
	b.Visible = on
	for _, beamPart in b.Cores do
		beamPart.Enabled = on
	end
	for _, beamPart in b.Glows do
		beamPart.Enabled = on
	end
end

-- Hides every bolt.
function HoverboardBolts.hide(set: BoltSet)
	for _, b in set.Arcs do
		b.Visible = true
		show(b, false)
		b.Ticks = 0
	end
	set.Strike.Visible = true
	show(set.Strike, false)
end

-- Puts the bolts under a board's Root; arcs start from its StartMounts attachments.
-- false when the board has none of them (nothing is moved).
function HoverboardBolts.mount(set: BoltSet, root: BasePart): boolean
	local starts: { Vector3 } = {}
	for _, name in HoverboardBolts.StartMounts do
		local a = root:FindFirstChild(name)
		if a and a:IsA("Attachment") then
			table.insert(starts, a.CFrame.Position)
		end
	end
	if #starts == 0 then
		return false
	end
	HoverboardBolts.hide(set)
	set.Starts = starts
	set.Root = root
	each(set, function(inst: Instance)
		inst.Parent = root
	end)
	return true
end

function HoverboardBolts.unmount(set: BoltSet)
	HoverboardBolts.hide(set)
	each(set, function(inst: Instance)
		inst.Parent = nil
	end)
	set.Root = nil
end

function HoverboardBolts.destroy(set: BoltSet)
	each(set, function(inst: Instance)
		inst:Destroy()
	end)
	set.Root = nil
end

--[[
	Shapes a bolt from `a` to `b` (Root space): the points in between jump
	sideways by up to `jag` x the length (most in the middle), plus `bulge`
	at the middle (crawling arcs hump over the deck).
]]
function HoverboardBolts.shape(b: Bolt, a: Vector3, z: Vector3, rand: () -> number, jag: number, bulge: Vector3?)
	local points = b.Points
	local n = #points - 1
	local delta = z - a
	local length = delta.Magnitude
	local dir = if length > 1e-3 then delta / length else Vector3.yAxis
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then
		side = dir:Cross(Vector3.xAxis)
	end
	side = side.Unit
	local up = dir:Cross(side).Unit
	for i = 0, n do
		local f = i / n
		local p = a + delta * f
		if i > 0 and i < n then
			local envelope = math.sin(math.pi * f)
			local amount = jag * length * envelope
			p += side * ((rand() * 2 - 1) * amount) + up * ((rand() * 2 - 1) * amount * 0.6)
			if bulge then
				p += bulge * envelope
			end
		end
		points[i + 1].CFrame = CFrame.new(p)
	end
end

--[[
	One flicker tick of the arcs. A lit arc keeps its shape until its ticks
	run out, then goes dark for OffTicks; a dark arc that may light lights
	with the chance Duty + 0.35 x speed + surge (speed and surge 0..1) with a
	new shape: 70 % from an edge down to the ground outward (Reach studs,
	longer while surging), 30 % crawling over the deck to another edge.
	At most `maxArcs` show (0 = none: Reduce Motion). Returns how many show.
]]
function HoverboardBolts.flicker(set: BoltSet, rand: () -> number, speed: number, surge: number, maxArcs: number?): number
	local starts = set.Starts
	local limit = maxArcs or #set.Arcs
	if not set.Root or #starts == 0 or limit <= 0 then
		HoverboardBolts.hide(set)
		return 0
	end
	local chance = math.clamp(set.Duty + 0.35 * math.clamp(speed, 0, 1) + math.clamp(surge, 0, 1), 0, 0.95)
	local shown = 0
	for _, b in set.Arcs do
		if b.Visible then
			b.Ticks -= 1
			if b.Ticks > 0 and shown < limit then
				shown += 1 -- holds its shape
			else
				show(b, false)
				b.Ticks = -HoverboardBolts.OffTicks
			end
			continue
		end
		if b.Ticks < 0 then
			b.Ticks += 1 -- resting after it went dark
			continue
		end
		if shown >= limit or rand() >= chance then
			continue
		end
		local i = math.clamp(math.floor(rand() * #starts) + 1, 1, #starts)
		local a = starts[i]
		if #starts > 1 and rand() < 0.3 then
			local j = math.clamp(math.floor(rand() * (#starts - 1)) + 1, 1, #starts - 1)
			if j >= i then
				j += 1
			end
			HoverboardBolts.shape(b, a, starts[j], rand, 0.18, Vector3.new(0, 0.5, 0))
		else
			local out = Vector3.new(a.X, 0, a.Z)
			local angle = (rand() * 2 - 1) * 0.7
			if out.Magnitude < 0.3 then
				angle = rand() * math.pi * 2
				out = Vector3.xAxis
			end
			local o = CFrame.Angles(0, angle, 0):VectorToWorldSpace(out.Unit)
			local reach = set.Reach * (0.55 + 0.45 * rand()) * (1 + 0.4 * math.clamp(surge, 0, 1))
			local z = Vector3.new(a.X + o.X * reach, 0.05, a.Z + o.Z * reach)
			HoverboardBolts.shape(b, a, z, rand, 0.22)
		end
		show(b, true)
		b.Ticks = HoverboardBolts.OnTicks + (if rand() < 0.5 then 1 else 0)
		shown += 1
	end
	return shown
end

--[[
	The strike from the sky onto the deck. alpha 1..0 over its life: the
	first call shapes it (once) and shows it, later calls only fade it
	(Transparency toward 1); alpha <= 0 hides it.
]]
function HoverboardBolts.strike(set: BoltSet, rand: () -> number, alpha: number, deck: number)
	local b = set.Strike
	if alpha <= 0 or not set.Root then
		show(b, false)
		return
	end
	if not b.Visible then
		local top = Vector3.new((rand() * 2 - 1) * 3, HoverboardBolts.StrikeHeight, (rand() * 2 - 1) * 3)
		HoverboardBolts.shape(b, top, Vector3.new(0, deck, 0), rand, 0.12)
		b.Alpha = -1 -- forces the transparency below
		show(b, true)
	end
	local a = math.clamp(alpha, 0, 1)
	if math.abs(a - b.Alpha) >= 0.04 then
		b.Alpha = a
		local core = NumberSequence.new(1 - (1 - HoverboardBolts.CoreTransparency) * a)
		local glow = NumberSequence.new(1 - (1 - HoverboardBolts.GlowTransparency) * a)
		for _, beamPart in b.Cores do
			beamPart.Transparency = core
		end
		for _, beamPart in b.Glows do
			beamPart.Transparency = glow
		end
	end
end

-- Arcs showing right now (tests).
function HoverboardBolts.visible(set: BoltSet): number
	local n = 0
	for _, b in set.Arcs do
		if b.Visible then
			n += 1
		end
	end
	return n
end

return HoverboardBolts
