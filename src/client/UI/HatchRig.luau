--[[
	HatchRig: a model on the egg opening's stage moved as one rigid set of
	parts (owner 2026-11-15, the egg quality pass: the eggs and golems stand
	in the real 3D world now, UI/HatchWorld). A rig keeps every part's place
	in its model's own frame, so a pose is one sum per part (no PivotTo
	walking the model every frame) and the world's parts all move in one
	Workspace:BulkMoveTo a frame (HatchWorld.flush).

	  rig = HatchRig.new(model)        its parts and their places round the
	                                   model's pivot now; an egg's parts of
	                                   its "Top" / "Bottom" halves are
	                                   grouped (they fly apart at the burst)
	  HatchRig.place(rig, cf, top?, bottom?, sink?, size?)
	                                   every part where the pose puts it
	                                   (top / bottom: the halves' own moves in
	                                   the model's frame); sink: a buffer the
	                                   world moves in one go, else set now;
	                                   size: the model drawn that much of its
	                                   size round its pivot (the 3D stage
	                                   draws what would stand too far away
	                                   smaller and closer instead: HatchStage)
	  HatchRig.fade(rig, k)            0 seen .. 1 gone (the parts' local
	                                   see-through: their own Transparency
	                                   untouched, so nothing to put back)
	  HatchRig.scale(model, k)         the whole model k times its size round
	                                   its pivot (parts, meshes, particles,
	                                   lights: what the builders use)
	  HatchRig.prepare(model)          a stage model: anchored, never in the
	                                   way (no collisions, queries, touches,
	                                   shadows), no joints, its particles
	                                   riding with it
]]

local HatchRig = {}

-- How far a drawn-smaller model's size may move before its parts are resized (a share of the last size).
HatchRig.ResizeStep = 0.03

export type Sink = { Parts: { BasePart }, Frames: { CFrame } }

export type Rig = {
	Model: Model, -- (its PrimaryPart moves with it: the builders' eggs and golems all have one)
	Parts: { BasePart },
	Offsets: { CFrame }, -- each part round the model's pivot (its own frame)
	Groups: { number }, -- per part: 0 the model, 1 the top half, 2 the bottom half
	Faded: number,
	Sizes: { Vector3 }, -- each part's own size
	Fixed: { boolean }, -- per part: never resized (hidden helpers: pivots, cracks, chips; they show at full size)
	Scaled: number, -- the size the parts are drawn at now (1: their own)
	Reach: number, -- how far its shown parts reach across its floor plan from its pivot (studs at its own size)
}

local function groupOf(part: Instance, model: Model): number
	local node: Instance? = part.Parent
	while node and node ~= model do
		if node:IsA("Model") then
			if node.Name == "Top" then
				return 1
			elseif node.Name == "Bottom" then
				return 2
			end
		end
		node = node.Parent
	end
	return 0
end

function HatchRig.new(model: Model): Rig
	local pivot = model:GetPivot()
	local rig: Rig = {
		Model = model,
		Parts = {},
		Offsets = {},
		Groups = {},
		Faded = 0,
		Sizes = {},
		Fixed = {},
		Scaled = 1,
		Reach = 0,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(rig.Parts, d)
			table.insert(rig.Offsets, pivot:ToObjectSpace(d.CFrame))
			table.insert(rig.Groups, groupOf(d, model))
			table.insert(rig.Sizes, d.Size)
			table.insert(rig.Fixed, d.Transparency >= 1)
			if d.Transparency < 1 then
				-- (across its own floor plan: the stage poses it upright in the camera's frame, so only that
				-- reach, turned toward the camera, can bring a part nearer; its height never does)
				local o, size = rig.Offsets[#rig.Offsets].Position, d.Size
				local across = math.sqrt(o.X * o.X + o.Z * o.Z) + math.sqrt(size.X * size.X + size.Z * size.Z) / 2
				rig.Reach = math.max(rig.Reach, across)
			end
		end
	end
	return rig
end

-- Part `i`'s place in its model's frame (a crack growing, a chip flying: HatchFx.paintEgg; by its place
-- in rig.Parts: the specs' instances are new handles at every read, never the same table key).
function HatchRig.setOffsetAt(rig: Rig, i: number, offset: CFrame)
	if rig.Offsets[i] then
		rig.Offsets[i] = offset
	end
end

function HatchRig.place(rig: Rig, cf: CFrame, top: CFrame?, bottom: CFrame?, sink: Sink?, size: number?)
	local parts, offsets, groups = rig.Parts, rig.Offsets, rig.Groups
	local topCf = if top then cf * top else cf
	local bottomCf = if bottom then cf * bottom else cf
	local k = if size and size == size and math.abs(size - 1) > 1e-4 then math.max(1e-3, size) else 1
	-- (a clamped golem's size moves a little every frame of its pop: its parts take a new size only
	-- once it has moved 3 % from the last, or is back to its own; until then the last one holds, its
	-- places too, so the parts stay together: a Size write costs far more than a move)
	if k ~= 1 and rig.Scaled ~= 1 and math.abs(k - rig.Scaled) <= HatchRig.ResizeStep * rig.Scaled then
		k = rig.Scaled
	end
	if k ~= rig.Scaled then
		-- (drawn smaller round its pivot: its parts' sizes follow; back to their own when it's 1 again)
		rig.Scaled = k
		for i, part in parts do
			if not rig.Fixed[i] then
				part.Size = rig.Sizes[i] * k
			end
		end
	end
	for i, part in parts do
		local g = groups[i]
		local base = if g == 1 then topCf elseif g == 2 then bottomCf else cf
		local offset = offsets[i]
		local target = if k == 1 then base * offset else base * (offset - offset.Position + offset.Position * k)
		if sink then
			table.insert(sink.Parts, part)
			table.insert(sink.Frames, target)
		else
			part.CFrame = target
		end
	end
end

function HatchRig.fade(rig: Rig, k: number)
	local value = math.clamp(if k == k then k else 0, 0, 1)
	if math.abs(value - rig.Faded) < 1e-4 then
		return
	end
	rig.Faded = value
	for _, part in rig.Parts do
		part.LocalTransparencyModifier = value
	end
end

local function scaleSequence(seq: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in seq.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

function HatchRig.scale(model: Model, k: number)
	if k == 1 or k <= 0 or k ~= k then
		return
	end
	local pivot = model:GetPivot()
	local function scaled(cf: CFrame): CFrame
		local local_ = pivot:ToObjectSpace(cf)
		return pivot * (local_ - local_.Position + local_.Position * k)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= k
			d.CFrame = scaled(d.CFrame)
		elseif d:IsA("SpecialMesh") then
			d.Offset *= k
			if d.MeshType == Enum.MeshType.FileMesh then
				d.Scale *= k
			end
		elseif d:IsA("ParticleEmitter") then
			d.Size = scaleSequence(d.Size, k)
			d.Speed = NumberRange.new(d.Speed.Min * k, d.Speed.Max * k)
			d.Acceleration *= k
			d.ZOffset *= k
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			(d :: any).Range = math.max(0.1, (d :: any).Range * k)
		elseif d:IsA("Attachment") then
			d.Position *= k
		end
	end
end

function HatchRig.prepare(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("ParticleEmitter") then
			d.LockedToPart = true -- (the stage rides with the camera: its embers with it, never trailing)
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

return HatchRig
