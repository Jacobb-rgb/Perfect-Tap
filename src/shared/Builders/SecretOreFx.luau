--[[
	SecretOreFx: what makes a SECRET ore alive (owner 2026-10-29: "udělej to
	ještě mnohem mnohem víc cool, jak ty věci, tak ty animace"). Shared, pure
	builders + poses; nothing runs on its own (the podium, the jackpot screen
	and the Lune previews call pose()).

	Moving parts: a recipe in SecretOreShapes gives a part a Move kind and
	ItemBuilder.makePart calls mark(): the kind, its speed / phase / amount
	and its pivot point + axis as attributes, both in the part's OWN space,
	so they survive any rigid move of the whole model (PivotTo, a viewport's
	re-centring). Kinds:
	  Spin     turns round Pivot about Axis (Speed radians a second)
	  Swing    swings to and fro round Pivot about Axis (Amount radians)
	  Look     the Hollow Eye's iris: swings, and hides while the eye blinks
	  Lid      the Hollow Eye's lid: only there while it blinks
	  Beat     grows and shrinks round Pivot, lub-dub (Amount: how much)
	  Pulse    breathes round its own middle (Amount)
	  Flicker  lightning: on and off, a little jitter
	  Rise     bubbles: rise along Axis by Amount, fading, again and again
	  Hue      goes round the rainbow (Speed turns a second), stays put

	dress(model, oreId, pivot, reach, floorY) adds the aura every secret
	display has: a ring of six rainbow bars round it (Halo, gold on Rainbow
	Nova), rising rainbow sparkles and a dim glowing floor disc (Floor); the
	Mythic motes get an orbit too.
	sparkly(model, body) is the dirty chunk's hint: rainbow glints, sparkles,
	a soft light.

	rig(model, pivot) -> Rig, then pose(rig, pivot, t, reduced) every frame:
	`pivot` is the CFrame the caller turns the model by (the podium's
	spinning frame, a viewport's still frame). Reduce motion: everything
	stands still, only the colours drift.
	Perf: a secret display has <= ItemBuilder.Budget.SecretDisplay parts and
	about 20 movers; pose sets CFrames (sizes only for Beat / Pulse / Rise).
]]

local SecretOreFx = {}

SecretOreFx.Rainbow = {
	Color3.fromRGB(255, 70, 96),
	Color3.fromRGB(255, 156, 48),
	Color3.fromRGB(255, 228, 64),
	Color3.fromRGB(80, 236, 120),
	Color3.fromRGB(64, 156, 255),
	Color3.fromRGB(176, 92, 255),
}
SecretOreFx.Gold = { Color3.fromRGB(255, 206, 72), Color3.fromRGB(255, 244, 196) }
SecretOreFx.HaloBars = 6
SecretOreFx.BlinkEvery = 3.6 -- seconds between two blinks of the Hollow Eye
SecretOreFx.BlinkTime = 0.16

export type Entry = {
	Part: BasePart,
	Offset: CFrame, -- the part in pivot space
	Size: Vector3,
	Transparency: number,
	Color: Color3,
	Kind: string,
	Pivot: Vector3, -- pivot space
	Axis: Vector3, -- pivot space, unit
	Speed: number,
	Phase: number,
	Amount: number,
}
export type Rig = { Entries: { Entry } }

local NEON = Enum.Material.Neon

local function make(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = NEON
	local loose: any = part
	for key, value in props do
		loose[key] = value
	end
	return part
end

local function rainbowSequence(): ColorSequence
	local keys = {}
	for k, color in SecretOreFx.Rainbow do
		table.insert(keys, ColorSequenceKeypoint.new((k - 1) / (#SecretOreFx.Rainbow - 1), color))
	end
	return ColorSequence.new(keys)
end

local function shine(parent: BasePart, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SecretShine"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = rainbowSequence()
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(1.1, 1.8)
	emitter.Speed = NumberRange.new(0.6, 1.3)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Rate = rate
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = parent
end

-- Gives a part its Move kind (pivot and axis in world space now; kept in the part's own space).
function SecretOreFx.mark(part: BasePart, kind: string, pivot: Vector3, axis: Vector3, speed: number?, phase: number?, amount: number?)
	part:SetAttribute("Move", kind)
	part:SetAttribute("MovePivot", part.CFrame:PointToObjectSpace(pivot))
	part:SetAttribute("MoveAxis", part.CFrame:VectorToObjectSpace(if axis.Magnitude > 1e-6 then axis.Unit else Vector3.yAxis))
	part:SetAttribute("MoveSpeed", speed or 1)
	part:SetAttribute("MovePhase", phase or 0)
	part:SetAttribute("MoveAmount", amount or 0)
end

--[[
	The aura of a secret display. `pivot` = the ore's middle (turned like the
	display), `reach` = how far the ore reaches from it, `floorY` = the
	bottom it stands on.
]]
function SecretOreFx.dress(model: Model, oreId: string, pivot: CFrame, reach: number, floorY: number)
	local nova = oreId == "RainbowNova"
	local center = pivot.Position
	local radius = reach + 0.35
	-- a dashed ring of six bars, tilted open towards the front, turning
	local ring = pivot * CFrame.Angles(-0.55, 0, 0.12)
	local chord = 2 * radius * math.sin(math.pi / SecretOreFx.HaloBars)
	for i = 1, SecretOreFx.HaloBars do
		local a = (i - 0.5) * math.pi * 2 / SecretOreFx.HaloBars
		local at = ring:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
		local tangent = ring:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		local bar = make({
			Name = "Halo",
			Size = Vector3.new(0.06, 0.06, chord * 0.5),
			CFrame = CFrame.lookAt(at, at + tangent, ring.UpVector),
			Color = if nova then SecretOreFx.Gold[(i % 2) + 1] else SecretOreFx.Rainbow[i],
		})
		bar.Parent = model
		SecretOreFx.mark(bar, "Spin", center, ring.UpVector, if nova then 1.3 else 0.9)
	end
	-- rainbow sparkles rising out of it
	local main = model.PrimaryPart
	if main then
		shine(main, if nova then 10 else 6, 0.24)
	end
	-- a dim glowing disc on the floor going round the rainbow
	local floor = make({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, radius * 1.25, radius * 1.25),
		CFrame = CFrame.new(center.X, floorY + 0.04, center.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = SecretOreFx.Rainbow[1],
		Transparency = 0.78,
	})
	floor.Parent = model
	SecretOreFx.mark(floor, "Hue", floor.CFrame.Position, Vector3.yAxis, 0.12)
	-- the Mythic motes (ItemBuilder) circle on their tilted orbit
	local orbit = pivot * CFrame.Angles(0.35, 0, 0.2)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Mote" then
			SecretOreFx.mark(d, "Spin", center, orbit.UpVector, 1.6)
		end
	end
end

-- The dirty chunk of a secret ore: its rainbow glints go round the rainbow, it sparkles and glows a little.
function SecretOreFx.sparkly(model: Model, body: BasePart)
	local k = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Glint" then
			k += 1
			SecretOreFx.mark(d, "Hue", d.CFrame.Position, Vector3.yAxis, 0.35, k * 0.5)
		end
	end
	shine(body, 8, 0.2)
	local light = Instance.new("PointLight")
	light.Name = "SecretLight"
	light.Color = Color3.fromRGB(220, 170, 255)
	light.Range = 7
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = body
end

---------------------------------------------------------------- moving

-- Every moving part of a model, measured against `pivot`.
function SecretOreFx.rig(model: Instance, pivot: CFrame): Rig
	local entries: { Entry } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("Move")
			if type(kind) == "string" then
				local localPivot = d:GetAttribute("MovePivot")
				local localAxis = d:GetAttribute("MoveAxis")
				local p = if typeof(localPivot) == "Vector3" then localPivot else Vector3.zero
				local a = if typeof(localAxis) == "Vector3" then localAxis else Vector3.yAxis
				local speed, phase, amount = d:GetAttribute("MoveSpeed"), d:GetAttribute("MovePhase"), d:GetAttribute("MoveAmount")
				table.insert(entries, {
					Part = d,
					Offset = pivot:ToObjectSpace(d.CFrame),
					Size = d.Size,
					Transparency = d.Transparency,
					Color = d.Color,
					Kind = kind,
					Pivot = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(p)),
					Axis = pivot:VectorToObjectSpace(d.CFrame:VectorToWorldSpace(a)).Unit,
					Speed = if type(speed) == "number" then speed else 1,
					Phase = if type(phase) == "number" then phase else 0,
					Amount = if type(amount) == "number" then amount else 0,
				})
			end
		end
	end
	return { Entries = entries }
end

local function about(point: Vector3, axis: Vector3, angle: number): CFrame
	return CFrame.new(point) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-point)
end

-- lub-dub: two quick swells a beat (x in beats)
local function beat(x: number): number
	local u = x % 1
	return math.exp(-((u / 0.07) ^ 2)) + 0.6 * math.exp(-(((u - 0.24) / 0.07) ^ 2))
end

-- Is the Hollow Eye shut right now?
function SecretOreFx.blinking(t: number, phase: number): boolean
	local u = (t + phase) % SecretOreFx.BlinkEvery
	return u >= SecretOreFx.BlinkEvery - SecretOreFx.BlinkTime
end

-- Lightning's on / off steps: a fixed scramble of 12 steps a second.
local function lit(t: number, phase: number): boolean
	local step = math.floor(t * 12 + phase * 7)
	return (step * 7919 + 13) % 11 >= 3
end

-- One frame `t` seconds in; `pivot` is where the model is now (as in rig).
function SecretOreFx.pose(rig: Rig, pivot: CFrame, t: number, reduced: boolean?)
	local still = reduced == true
	for _, e in rig.Entries do
		local kind = e.Kind
		local part = e.Part
		local m = CFrame.identity
		local scale = 1
		local transparency = e.Transparency
		local x = t * e.Speed + e.Phase
		if kind == "Hue" then
			part.Color = Color3.fromHSV((if still then t * e.Speed * 0.25 + e.Phase else x) % 1, 0.8, 0.85)
		elseif still then
			if kind == "Lid" then
				transparency = 1
			end
		elseif kind == "Spin" then
			m = about(e.Pivot, e.Axis, x)
		elseif kind == "Swing" then
			m = about(e.Pivot, e.Axis, math.sin(x) * e.Amount)
		elseif kind == "Look" then
			m = about(e.Pivot, e.Axis, math.sin(x) * e.Amount + math.sin(x * 2.3) * e.Amount * 0.3)
			if SecretOreFx.blinking(t, e.Phase) then
				transparency = 1
			end
		elseif kind == "Lid" then
			transparency = if SecretOreFx.blinking(t, e.Phase) then 0 else 1
		elseif kind == "Beat" then
			scale = 1 + e.Amount * beat(x)
		elseif kind == "Pulse" then
			scale = 1 + e.Amount * math.sin(x)
		elseif kind == "Flicker" then
			if not lit(t, e.Phase) then
				transparency = 0.85
			end
			m = about(e.Pivot, e.Axis, math.sin(t * 37 + e.Phase) * 0.05)
		elseif kind == "Rise" then
			local u = x % 1
			m = CFrame.new(e.Axis * (u * e.Amount))
			scale = 1 - 0.35 * u
			transparency = e.Transparency + (1 - e.Transparency) * u * u
		end
		local offset = m * e.Offset
		local size = e.Size
		if scale ~= 1 then
			-- grow round the pivot (Beat) or its own middle (Pulse, Rise)
			local around = if kind == "Beat" then e.Pivot else offset.Position
			offset = CFrame.new(around + (offset.Position - around) * scale) * offset.Rotation
			size = e.Size * scale
		end
		-- (only what changed is written: a podium poses many parts every frame)
		if (part.Size - size).Magnitude > 1e-4 then
			part.Size = size
		end
		part.CFrame = pivot * offset
		if part.Transparency ~= transparency then
			part.Transparency = transparency
		end
	end
end

-- Every moving part back where, how big, how see-through and what colour it was built
-- (a podium out of range: the next rig reads the rest pose again, never a moved one).
function SecretOreFx.rest(rig: Rig, pivot: CFrame)
	for _, e in rig.Entries do
		e.Part.CFrame = pivot * e.Offset
		e.Part.Size = e.Size
		e.Part.Transparency = e.Transparency
		e.Part.Color = e.Color
	end
end

return SecretOreFx
