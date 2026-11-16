-- The egg opening's 3D stage (owner 2026-11-15: "the eggs look pixelated, blurry ... fix the
-- underlying cause"; UI/HatchWorld): the eggs and golems as real models in the world right in front
-- of the camera (a viewport had no anti-aliasing on its edges and a flat light), posed by the same
-- HatchStage. Held here: Roblox's easing curves (Util/Ease), the rigs (UI/HatchRig: a pose, the
-- halves, the fade, the scale), the stage landing on the same spot of the screen whatever the
-- camera's view, the backdrop filling the view behind every model, a whole opening on the stage
-- (in front of the camera, small, the golems never far, nothing left after it, a second opening as
-- clean as the first), the five stages' new moves (the turn, the running cracks, the chips, the
-- halves, the golem's scale-in, the camera's breath) and the controller's hooks.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Ease = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.Ease")
	local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
	local HatchRig = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchRig")
	local HatchWorld = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchWorld")
	local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")

	-- an egg of the 3D stage, made as the controller makes them (CapsuleController.makeEgg)
	local function stageEgg(capsule: string): any
		local model = GolemBuilder.capsule(capsule)
		HatchFx.addCracks(model, 3)
		HatchRig.prepare(model)
		HatchRig.scale(model, HatchWorld.Scale)
		model:SetAttribute("StageScale", HatchWorld.Scale)
		model:SetAttribute("Pooled", true)
		return HatchFx.record(model)
	end

	local function golemOf(kind: string): (any, number, number)
		local model = GolemBuilder.build(kind)
		return model, model:GetAttribute("Height") or 3, model:GetAttribute("RootHeight") or 1
	end

	-- a camera somewhere in the world, tilted, as a player's is
	local CAMERA = CFrame.new(40, 22, -15) * CFrame.Angles(math.rad(-18), math.rad(130), 0)

	T.test("EggWorld: Roblox's easing curves (TweenService's own numbers), spans at rest at both ends", function()
		local expect = {
			{ "Sine", "Out", 0.5, 0.70710678 },
			{ "Sine", "InOut", 0.25, 0.14644661 },
			{ "Quad", "Out", 0.5, 0.75 },
			{ "Quad", "InOut", 0.75, 0.875 },
			{ "Quint", "Out", 0.5, 0.96875 },
			{ "Back", "Out", 0.5, 1.0876975 },
			{ "Back", "In", 0.5, -0.0876975 },
			{ "Exponential", "Out", 0.5, 0.96875 },
			{ "Circular", "Out", 0.5, 0.8660254 },
		}
		for _, e in expect do
			T.near(Ease.pure(e[3], e[1], e[2]), e[4], 1e-6, `{e[1]} {e[2]} at {e[3]}`)
			T.near(Ease.get(e[3], e[1], e[2]), e[4], 1e-6, "Ease.get (no TweenService in the specs: the same curve)")
		end
		for _, style in { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back" } do
			for _, dir in { "In", "Out", "InOut" } do
				T.near(Ease.pure(0, style, dir), 0, 1e-9, style .. dir .. " starts at 0")
				T.near(Ease.pure(1, style, dir), 1, 1e-9, style .. dir .. " ends at 1")
			end
		end
		T.eq(Ease.span(0.5, 1, 2, "Sine", "Out"), 0, "before the span: 0")
		T.eq(Ease.span(4, 1, 2, "Sine", "Out"), 1, "after it: 1")
		T.near(Ease.span(2, 1, 2, "Quad", "Out"), 0.75, 1e-9, "half way")
		T.eq(Ease.UseTweenService, false, "the specs have no TweenService")
	end)

	T.test("EggWorld: a rig poses a model as PivotTo would, moves an egg's halves, fades and scales it", function()
		local model = GolemBuilder.capsule("Crystal")
		HatchFx.addCracks(model, 3)
		local twin = model:Clone()
		local rig = HatchRig.new(model)
		local target = CFrame.new(3, 4, -5) * CFrame.Angles(0.3, 1.1, -0.2)
		HatchRig.place(rig, target)
		twin:PivotTo(target)
		local a, b = {}, {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				a[d:GetFullName()] = d.CFrame
			end
		end
		for _, d in twin:GetDescendants() do
			if d:IsA("BasePart") then
				b[d:GetFullName()] = d.CFrame
			end
		end
		for name, cf in a do
			local other = b[name]
			T.truthy(other ~= nil and (cf.Position - other.Position).Magnitude < 1e-4, name .. " where PivotTo puts it")
		end
		-- the halves: grouped from the egg's Top / Bottom models, moved on their own
		local tops, bottoms = 0, 0
		for i, part in rig.Parts do
			if part:IsDescendantOf(model:FindFirstChild("Top")) then
				T.eq(rig.Groups[i], 1, part.Name .. ": the top half")
				tops += 1
			elseif part:IsDescendantOf(model:FindFirstChild("Bottom")) then
				T.eq(rig.Groups[i], 2, part.Name .. ": the bottom half")
				bottoms += 1
			end
		end
		T.truthy(tops > 10 and bottoms > 10, "both halves grouped")
		local top, bottom = HatchFx.halves(1, 5, 1)
		HatchRig.place(rig, CFrame.new(), top, bottom)
		local shell = model:FindFirstChild("Top"):FindFirstChild("Shell")
		T.truthy(shell.CFrame.Position.Y > 1.5, "the top flew up")
		T.truthy(shell.CFrame.Position.Z > 0.5, "and back, away from the camera (the egg's front is -Z)")
		-- the fade: local, the parts' own see-through untouched
		local before = shell.Transparency
		HatchRig.fade(rig, 0.4)
		T.near(shell.LocalTransparencyModifier, 0.4, 1e-6)
		T.eq(shell.Transparency, before, "its own Transparency untouched")
		-- the scale: sizes and places round the pivot, particles and lights with them
		local big = GolemBuilder.build("CloudColossus")
		local part = big.PrimaryPart
		local size = part.Size
		local pivot = big:GetPivot()
		local probe
		for _, d in big:GetDescendants() do
			if d:IsA("BasePart") and d ~= part then
				probe = d
				break
			end
		end
		local offset = pivot:PointToObjectSpace(probe.CFrame.Position)
		local emitter = big:FindFirstChildWhichIsA("ParticleEmitter", true)
		local emitSize = if emitter then emitter.Size.Keypoints[1].Value else 0
		HatchRig.scale(big, 0.05)
		T.near(part.Size.X, size.X * 0.05, 1e-4, "sizes scaled")
		local after = big:GetPivot():PointToObjectSpace(probe.CFrame.Position)
		T.near(after.Magnitude, offset.Magnitude * 0.05, 1e-4, "places scaled round the pivot")
		if emitter then
			T.near(emitter.Size.Keypoints[1].Value, emitSize * 0.05, 1e-6, "its particles scaled")
		end
		-- a stage model: anchored, never in the way, no joints
		HatchRig.prepare(big)
		for _, d in big:GetDescendants() do
			if d:IsA("BasePart") then
				T.truthy(
					d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow,
					d.Name .. " out of the way"
				)
			end
			T.falsy(d:IsA("JointInstance") or d:IsA("WeldConstraint"), "no joints")
		end
	end)

	T.test("EggWorld: a stage point lands on the same spot of the screen whatever the camera and its view", function()
		local world = HatchWorld.new()
		local aspect = 16 / 9
		for _, fov in { 40, 55, 70, 90 } do
			HatchWorld.begin(world, CAMERA, fov)
			for _, uv in { { 0.5, 0.5, 3 }, { 0.12, 0.3, 1.2 }, { 0.88, 0.78, 2.2 } } do
				local p = HatchFx.at(uv[1], uv[2], uv[3], aspect)
				local w = HatchWorld.toWorld(world, CFrame.new(p))
				local q = CAMERA:PointToObjectSpace(w.Position)
				T.truthy(q.Z < 0, "in front of the camera")
				local screen = HatchFx.project(q, aspect, fov)
				T.near(screen.X, uv[1], 1e-5, `fov {fov}: u`)
				T.near(screen.Y, uv[2], 1e-5, `fov {fov}: v`)
			end
		end
		-- the backdrop: fills the view exactly, faces the camera, behind the farthest model
		HatchWorld.begin(world, CAMERA, 70)
		HatchWorld.flush(world, aspect, 4.5)
		local b = world.Backdrop
		local depth = -CAMERA:PointToObjectSpace(b.CFrame.Position).Z
		T.truthy(depth >= HatchWorld.BackdropDepth - 1e-4, "never closer than BackdropDepth")
		T.truthy(depth >= 4.5 * world.DepthK * HatchWorld.BackdropBehind - 1e-4, "behind the farthest model")
		T.truthy(depth <= HatchWorld.BackdropMost + 1e-4, "never so far the world cuts into it")
		for _, corner in { Vector3.new(-1, -1, 0), Vector3.new(1, 1, 0), Vector3.new(1, -1, 0) } do
			local p = b.CFrame:PointToWorldSpace(Vector3.new(corner.X * b.Size.X / 2, corner.Y * b.Size.Y / 2, 0))
			local screen = HatchFx.project(CAMERA:PointToObjectSpace(p), aspect, 70)
			T.near(math.abs(screen.X - 0.5), 0.5, 1e-4, "a corner on the screen's edge (x)")
			T.near(math.abs(screen.Y - 0.5), 0.5, 1e-4, "(y)")
		end
		T.truthy(b.CFrame.LookVector:Dot((CAMERA.Position - b.CFrame.Position).Unit) > 0.999, "its Front face toward the camera")
		T.eq(world.Surface.Face, roblox.Enum.NormalId.Front)
		T.eq(world.Surface.AlwaysOnTop, false, "depth-tested: the eggs and golems in front of it")
		T.eq(world.Surface.LightInfluence, 0, "as bright as on the screen")
		-- the lights ride with the camera
		local f = world.Back / HatchWorld.BackdropDepth
		T.truthy((world.KeyPart.CFrame.Position - CAMERA:PointToWorldSpace(HatchWorld.Key.Position * f)).Magnitude < 1e-3, "the key light")
		T.truthy(world.KeyPart.CFrame.LookVector:Dot(CAMERA.LookVector) > 0.5, "aimed at the stage")
	end)

	-- a whole opening on the 3D stage, as the controller plays it
	local function playOnStage(world: any, o: any, capsule: string, kinds: { string }, eggs: { any }?, fast: boolean?): (any, { any })
		local list = eggs or {}
		if not eggs then
			for _ = 1, #kinds do
				table.insert(list, stageEgg(capsule))
			end
		end
		for _, rec in list do
			HatchFx.reset(rec)
		end
		local run = HatchStage.new({
			Refs = o,
			Capsule = capsule,
			Lucky = false,
			Kinds = kinds,
			Eggs = list,
			Fast = fast == true,
			Reduced = false,
			Phone = false,
			Target = Vector2.new(0.5, 0.86),
			Golem = golemOf,
			Claim = function(): boolean
				return true
			end,
			World = world,
		})
		return run, list
	end

	T.test("EggWorld: a whole opening on the stage: in front of the camera, small, behind nothing, nothing left after", function()
		local holderParent = Instance.new("Folder")
		local emits = {}
		local world = HatchWorld.new({
			Parent = holderParent,
			Emit = function(e, n)
				table.insert(emits, { e, n })
			end,
		})
		local o = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
		CapsuleView.useBackdrop(o, world.Surface)
		for _, piece in o.Behind do
			T.eq(piece.Parent, world.Surface, piece.Name .. " on the backdrop")
		end
		T.eq(o.Stage.Visible, false, "the viewport empty and hidden")
		HatchWorld.show(world, true)
		T.eq(world.Folder.Parent, holderParent, "in the world while it plays")
		for _, case in { { "Stone", { "PebbleGolem" } }, { "Crystal", { "PebbleGolem", "PebbleGolem", "PebbleGolem" } } } do
			local run, eggs = playOnStage(world, o, case[1], case[2])
			local tl = run.Timeline
			local t, sawEggs, sawGolems = 0, false, false
			local fov = 70
			while t < tl.Total do
				t = math.min(tl.Total, t + 1 / 30)
				-- (the view easing in to the stage's as the opening begins)
				fov = math.max(HatchFx.Fov, fov - 2)
				HatchStage.pose(run, t, { Space = CAMERA, Fov = fov })
				local far = 0
				for _, model in world.Holder:GetChildren() do
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Transparency < 1 then
							local q = CAMERA:PointToObjectSpace(d.CFrame.Position)
							T.truthy(q.Z < -0.05, d.Name .. " in front of the camera")
							far = math.max(far, -q.Z)
						end
					end
					if model:GetAttribute("Golem") then
						sawGolems = true
					else
						sawEggs = true
					end
				end
				if t < tl.Fly then
					-- (within this frame's band, and in front of the backdrop)
					T.truthy(far <= world.Most + 0.5, `{case[1]} at {t}: the stage within its band ({far} vs {world.Most})`)
					local backdrop = -CAMERA:PointToObjectSpace(world.Backdrop.CFrame.Position).Z
					T.truthy(far < backdrop, "every model in front of the backdrop")
				end
			end
			T.truthy(sawEggs and sawGolems, "the eggs, then the golems, on the stage")
			for _, g in run.Standing do
				T.eq(g.Rig.Faded, 1, "the golems melted into the player at the end")
				T.truthy(g.Model:GetAttribute("StageScale") <= HatchWorld.GolemScale + 1e-9, "made small for the stage")
			end
			T.truthy(#emits >= #case[2], "sparks at the burst, out of every egg")
			HatchStage.clear(o, HatchStage.golems(run), world)
			T.eq(#world.Holder:GetChildren(), 0, "nothing left on the stage")
			for _, rec in eggs do
				T.eq(rec.Model.Parent, nil, "the eggs back in the pool")
			end
			for _, e in world.MoteFx do
				T.eq(e.Rate, 0, "no motes")
			end
		end
		HatchWorld.show(world, false)
		T.eq(world.Folder.Parent, nil, "out of the world after")
	end)

	T.test("EggWorld: what would stand too far is drawn smaller and closer: the same on the screen, never past DepthMost", function()
		local world = HatchWorld.new()
		local o = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
		CapsuleView.useBackdrop(o, world.Surface)
		local kinds = table.create(10, "PebbleGolem")
		local run, eggs = playOnStage(world, o, "Stone", kinds)
		-- the first frame of Open 10: the eggs come in at PopFrom of their size, from far, if it were by distance
		HatchStage.pose(run, 0.02, { Space = CAMERA, Fov = 40 })
		local rec = eggs[1]
		T.truthy(rec.Rig.Scaled < 1, "the first egg drawn smaller")
		local shell = rec.Model:FindFirstChild("Top"):FindFirstChild("Shell")
		local i = 0
		for at, part in rec.Rig.Parts do
			if part == shell then
				i = at
			end
		end
		T.truthy(i > 0, "the shell in the rig")
		T.near(shell.Size.X, rec.Rig.Sizes[i].X * rec.Rig.Scaled, 1e-4, "its parts' sizes follow")
		for _, model in world.Holder:GetChildren() do
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local z = -CAMERA:PointToObjectSpace(d.CFrame.Position).Z
					T.truthy(z <= world.Most + 0.4, `{d.Name}: never past the band ({z} vs {world.Most})`)
				end
			end
		end
		-- the same spot of the screen as the pose without the cap
		local s = run.Layout.Slots[1]
		local pose = run.EggPoses[1]
		local middle = HatchFx.at(s.Egg.X, s.Egg.Y + pose.Drop, run.EggDepth[1] / pose.Scale, 16 / 9)
		local want = HatchFx.project(middle, 16 / 9)
		local root = rec.Model.PrimaryPart
		local got = HatchFx.project(CAMERA:PointToObjectSpace(root.CFrame.Position), 16 / 9)
		T.truthy((got - want).Magnitude < 0.05, `the egg where its pose puts it on the screen ({got} vs {want})`)
		-- settled: its own size again
		HatchStage.pose(run, run.Timeline.Float + 0.2, { Space = CAMERA, Fov = 40 })
		T.eq(rec.Rig.Scaled, 1, "its own size once it's in")
		T.near(shell.Size.X, rec.Rig.Sizes[i].X, 1e-4, "its parts too")
	end)

	T.test("EggWorld: the band follows the camera: off its near plane, nearer than the player, the backdrop too", function()
		local world = HatchWorld.new()
		HatchWorld.begin(world, CAMERA, 70, 0.5, 2)
		T.near(world.Least, HatchWorld.NearMargin * 0.5, 1e-9, "off a half-stud near plane")
		T.near(world.Most, HatchWorld.FocusShare * 2, 1e-9, "nearer than the player pushed in to 2 studs")
		T.truthy(world.BackFar <= HatchWorld.BackShare * 2 + 1e-9, "the backdrop too")
		HatchWorld.begin(world, CAMERA, 40, 0.1, 30)
		T.eq(world.Least, HatchWorld.DepthLeast, "a near plane of 0.1: the least")
		T.eq(world.Most, HatchWorld.DepthMost, "a player far away: the most")
		-- a whole Open 3 with the view wide (Reduce motion keeps the player's 70 degrees), in the two tight
		-- spots a camera meets: a half-stud near plane at its least zoom (4 studs), and pushed in to 2 studs
		-- by a wall (a tenth of a stud near plane). (A half-stud plane AND 2 studs: the big egg can't fit
		-- between; the near side wins, nothing is ever cut.)
		for _, spot in { { Near = 0.5, Reach = 4 }, { Near = 0.1, Reach = 2 } } do
			local o = CapsuleView.buildOpening(false)
			CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
			CapsuleView.useBackdrop(o, world.Surface)
			local run = playOnStage(world, o, "Crystal", { "PebbleGolem", "PebbleGolem", "PebbleGolem" })
			local tl = run.Timeline
			local t = 0
			local label = `near {spot.Near}, the player {spot.Reach} studs away`
			while t < tl.Fly do
				t += 1 / 20
				HatchStage.pose(run, t, { Space = CAMERA, Fov = 70, Near = spot.Near, Reach = spot.Reach })
				local near, far = math.huge, 0
				for _, model in world.Holder:GetChildren() do
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Transparency < 1 then
							local z = -CAMERA:PointToObjectSpace(d.CFrame.Position).Z
							near = math.min(near, z)
							far = math.max(far, z)
						end
					end
				end
				if far > 0 then
					T.truthy(near > spot.Near * 1.2, `{label}: never cut by the near plane ({near} at {t})`)
					T.truthy(far < spot.Reach - 0.25, `{label}: nearer than the player ({far} at {t})`)
					local back = -CAMERA:PointToObjectSpace(world.Backdrop.CFrame.Position).Z
					T.truthy(back < spot.Reach and back > far - 0.15, `{label}: the backdrop between them ({back})`)
				end
			end
			HatchStage.clear(o, HatchStage.golems(run), world)
		end
	end)

	T.test("EggWorld: a pooled egg's second opening starts as clean as its first (cracks, chips, halves, fade)", function()
		local world = HatchWorld.new()
		local o = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
		CapsuleView.useBackdrop(o, world.Surface)
		local first, eggs = playOnStage(world, o, "Royal", { "PebbleGolem" })
		local function shape(rec: any): { [string]: Vector3 }
			local pivot = rec.Model:GetPivot()
			local out = {}
			for _, d in rec.Model:GetDescendants() do
				if d:IsA("BasePart") then
					out[d:GetFullName()] = pivot:PointToObjectSpace(d.CFrame.Position)
				end
			end
			return out
		end
		HatchStage.pose(first, 0.05, { Space = CAMERA, Fov = 40 })
		local fresh = shape(eggs[1])
		-- through the cracks, the chips and the break
		local tl = first.Timeline
		local t = 0.05
		while t < tl.Burst + tl.Times.Break * 0.8 do
			t += 1 / 30
			HatchStage.pose(first, t, { Space = CAMERA, Fov = 40 })
		end
		HatchStage.clear(o, HatchStage.golems(first), world)
		local second = playOnStage(world, o, "Royal", { "PebbleGolem" }, eggs)
		HatchStage.pose(second, 0.05, { Space = CAMERA, Fov = 40 })
		local again = shape(eggs[1])
		for name, p in fresh do
			T.truthy(again[name] and (again[name] - p).Magnitude < 1e-4, name .. " back in its place")
		end
		for _, crack in eggs[1].Cracks do
			T.eq(crack.Part.Transparency, 1, "the cracks hidden")
		end
		for _, chip in eggs[1].Chips do
			T.eq(chip.Part.Transparency, 1, "the chips hidden")
		end
		T.eq(eggs[1].Rig.Faded, 0, "no fade left")
		for i, part in eggs[1].Parts do
			if eggs[1].Trans[i] < 1 then
				T.eq(part.Material, eggs[1].Materials[i], part.Name .. ": its own material back (not the silhouette's Neon)")
				break
			end
		end
	end)

	T.test("EggWorld: stage 1-2: the egg turns from facing you to facing you, slowly, faster, settling; none for Auto", function()
		local tl = HatchFx.timeline(1, 1, false, false)
		T.near(HatchFx.spinAt(0, tl, 1), 0, 1e-9, "comes in facing you")
		T.near(HatchFx.spinAt(tl.Steps[1], tl, 1), 0, 1e-9, "faces you at the first crack")
		local last, fastest = HatchFx.spinAt(0, tl, 1), 0
		local dt = 0.001
		local t = dt
		-- (an angle: a whole turn is no jump)
		local function turned(a: number, b: number): number
			return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
		end
		while t <= tl.Steps[1] + 0.01 do
			local yaw = HatchFx.spinAt(t, tl, 1)
			local step = turned(yaw, last)
			T.truthy(step < 0.01, `no jump at {t}`)
			fastest = math.max(fastest, step / dt)
			last = yaw
			t += dt
		end
		T.truthy(fastest <= 2 * math.pi * 1.0, `never faster than a turn a second ({fastest / (2 * math.pi)} turns/s)`)
		T.truthy(fastest >= 2 * math.pi * 0.4, "a real turn, not a wobble")
		-- slow at first: the first tenth of the way turns far less than a tenth of the turn
		local early = math.abs(HatchFx.spinAt(tl.Steps[1] * 0.25, tl, 1) - 2 * math.pi)
		T.truthy(early < 2 * math.pi * 0.15, "slowly at first")
		T.eq(HatchFx.spinAt(0.3, HatchFx.timeline(1, 1, true, false), 1), 0, "Auto: no turn")
		T.eq(HatchFx.spinAt(0.3, HatchFx.timeline(1, 1, false, true), 1), 0, "Reduce motion: none")
	end)

	T.test("EggWorld: stage 3: each crack line runs out in order, chips fly and fall, the halves fly apart and fade", function()
		local world = HatchWorld.new()
		local o = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
		CapsuleView.useBackdrop(o, world.Surface)
		local run, eggs = playOnStage(world, o, "Stone", { "PebbleGolem" })
		local tl = run.Timeline
		local rec = eggs[1]
		local function pose(t: number)
			HatchStage.pose(run, t, { Space = CAMERA, Fov = 40 })
		end
		-- a line's segments come out in order, then the whole line
		pose(tl.Steps[1] + HatchFx.CrackGrow * 0.35)
		local line1: { any } = {}
		for _, crack in rec.Cracks do
			if crack.Line == 1 then
				line1[crack.Seg] = crack
			end
		end
		T.truthy(#line1 >= 3, "a line of several segments")
		T.eq(line1[1].Part.Transparency, 0, "its first segment out")
		T.eq(line1[#line1].Part.Transparency, 1, "its last not yet")
		-- (a segment part way out: shorter, its middle moved back toward its start, in the rig)
		local partway
		for _, crack in line1 do
			if crack.Shown > 0 and crack.Shown < 1 then
				partway = crack
			end
		end
		T.truthy(partway ~= nil, "a segment part way out")
		T.truthy(partway.Part.Size.Y < partway.Length - 1e-4, "shorter while it runs out")
		T.truthy((rec.Rig.Offsets[partway.At].Position - partway.Base.Position).Magnitude > 1e-5, "moved back toward its start")
		pose(tl.Steps[1] + HatchFx.CrackGrow + 0.01)
		for _, crack in line1 do
			T.eq(crack.Part.Transparency, 0, "the whole line out")
			T.near(crack.Part.Size.Y, crack.Length, 1e-4, "each segment its full length")
			T.truthy((rec.Rig.Offsets[crack.At].Position - crack.Base.Position).Magnitude < 1e-4, "back in its whole place")
		end
		-- the chips: none before the second step; three fly then, outward and down, gone after
		pose(tl.Steps[2] - 0.01)
		for _, chip in rec.Chips do
			T.eq(chip.Part.Transparency, 1, "no chip before the second step")
		end
		pose(tl.Steps[2] + 0.12)
		local flying = 0
		for _, chip in rec.Chips do
			if chip.Part.Transparency < 1 then
				flying += 1
			end
		end
		T.eq(flying, 3, "three chips at the second step")
		local cf1 = HatchFx.chipPose(1, 0.3, tl)
		local cf2 = HatchFx.chipPose(1, 1, tl)
		T.truthy(cf2.Position.Y < cf1.Position.Y, "they fall")
		local start = HatchFx.eggFront(HatchFx.Chips[1].X, HatchFx.Chips[1].Y)
		T.truthy((cf1.Position - start).Magnitude > 0.3, "away from the shell")
		local _, see = HatchFx.chipPose(1, 0.99, tl)
		T.truthy(see > 0.9, "fading at the end")
		-- the burst: the halves apart, fading, the cracks gone with the shell
		pose(tl.Burst + tl.Times.Break * 0.5)
		local pose1 = run.EggPoses[1]
		T.truthy(pose1.Shown and pose1.Break > 0.3 and pose1.Break < 0.7, "breaking")
		T.truthy(pose1.Fade > 0 and pose1.Fade < 1, "fading")
		local top = rec.Model:FindFirstChild("Top"):FindFirstChild("Shell")
		local bottom = rec.Model:FindFirstChild("Bottom"):FindFirstChild("Shell")
		local up = rec.Model:GetPivot().UpVector
		T.truthy((top.CFrame.Position - bottom.CFrame.Position):Dot(up) > rec.Height * 0.35, "the halves apart")
		for _, crack in rec.Cracks do
			T.eq(crack.Part.Transparency, 1, "no crack on the flying halves")
		end
		pose(tl.Burst + tl.Times.Break + 0.02)
		T.eq(run.EggPoses[1].Shown, false, "gone after its burst")
		T.eq(rec.Model.Parent, nil)
	end)

	T.test("EggWorld: stage 4: the golem grows out smoothly and turns into its look; the camera's breath; stage 2's motes", function()
		for _, fast in { false, true } do
			local tl = HatchFx.timeline(1, 1, fast, false)
			local first = HatchFx.golemPose(tl.Reveal + 0.001, tl, 1)
			T.truthy(first.Scale < 0.15, "it comes out small")
			local peak, last = 0, first.Scale
			local t = tl.Reveal
			while t < tl.Reveal + tl.GolemPop + 0.2 do
				local p = HatchFx.golemPose(t, tl, 1)
				peak = math.max(peak, p.Scale)
				T.truthy(math.abs(p.Scale - last) < 0.12, `smooth at {t}`)
				last = p.Scale
				t += 0.005
			end
			T.truthy(peak > 1.02 and peak <= HatchStage.PopPeak, `past its size and back (Back Out): {peak}`)
			local settled = HatchFx.golemPose(tl.Reveal + tl.GolemPop * 1.3 + 0.01, tl, 1)
			T.near(settled.Scale, 1, 1e-6, "its own size")
			T.truthy(math.abs(settled.Spin) < 1e-3, "turned into its 3/4 look")
		end
		local tl = HatchFx.timeline(1, 1, false, false)
		T.eq(HatchFx.breathAt(tl.Burst - 0.01, tl), 0, "no breath before the burst")
		local most = 0
		for k = 0, 100 do
			most = math.max(most, HatchFx.breathAt(tl.Burst + k * 0.01, tl))
		end
		T.truthy(most > 2 and most <= HatchFx.Breath + 1e-9, "a breath at the burst")
		T.near(HatchFx.breathAt(tl.Burst + 0.95, tl), 0, 1e-9, "eased back")
		T.eq(HatchFx.breathAt(tl.Burst + 0.1, HatchFx.timeline(1, 1, false, true)), 0, "Reduce motion: none")
		T.truthy(HatchFx.breathAt(tl.Burst + 0.14, HatchFx.timeline(1, 1, true, false)) <= 2, "Auto: a little")
		-- the motes: a few while it floats, more with the charge, none from the burst
		T.eq(HatchFx.energyAt(tl.Float - 0.01, tl), 0)
		T.truthy(HatchFx.energyAt(tl.Float + 0.4, tl) > 0, "a few while it floats")
		T.truthy(HatchFx.energyAt(tl.Burst - 0.01, tl) > 0.9, "most at the peak")
		T.eq(HatchFx.energyAt(tl.Burst, tl), 0, "none from the burst")
		-- the aura from the entrance on (soft), the energy's glow after it
		T.truthy(
			HatchFx.auraAt(tl.Float, tl, 1) > 0 and HatchFx.auraAt(tl.Float, tl, 1) <= HatchFx.EarlyAura + 1e-9,
			"a soft aura with the egg"
		)
		T.truthy(HatchFx.auraAt(tl.Silhouette - 0.01, tl, 1) > HatchFx.EarlyAura, "brighter with the energy")
	end)

	T.test("EggWorld: the controller (the stage, its frame after the camera, the focus, the view's ease, cleaned up)", function()
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local code = string.gsub(source, "%-%-[^\n]*", "")
		T.truthy(
			string.find(code, 'FindFirstChildOfClass("DepthOfFieldEffect")', 1, true),
			"the world softly out of focus behind the stage"
		)
		T.falsy(string.find(code, 'Instance.new("BlurEffect")', 1, true), "no blur: it would blur the stage too")
		T.truthy(string.find(code, "World = ensureWorld()", 1, true), "every opening on the 3D stage")
		T.truthy(
			string.find(code, "CapsuleView.useBackdrop(o, ensureWorld().Surface)", 1, true),
			"the pieces under the stage on its backdrop"
		)
		T.truthy(
			string.find(code, "RunService:BindToRenderStep(HATCH_STEP, Enum.RenderPriority.Last.Value", 1, true),
			"one pose a frame after everything that moves the camera"
		)
		T.truthy(string.find(code, "HatchStage.pose(run, t, stageView())", 1, true), "the stage in front of the camera of the frame")
		T.truthy(string.find(code, "Near = math.abs(camera.NearPlaneZ)", 1, true), "it keeps off the camera's near plane")
		T.truthy(string.find(code, "Reach = (cf.Position - camera.Focus.Position).Magnitude", 1, true), "and nearer than the player")
		T.truthy(string.find(code, "dof.FocusDistance = stage.Back * 0.5", 1, true), "the focus follows the stage")
		local _, clears = string.gsub(code, "pcall%(RunService.UnbindFromRenderStep, RunService, HATCH_STEP%)", "")
		T.truthy(clears >= 2, "the frame unbound when a chain ends and when a stuck opening is stopped")
		T.truthy(
			string.find(code, "HatchWorld.show(made, false)", 1, true) and string.find(code, "zoomOut()", 1, true),
			"out of the world, the view back"
		)
		T.truthy(string.find(code, "HatchStage.clear(o, stageGolems, world)", 1, true), "the stage cleared after every opening")
		T.truthy(string.find(code, "if Motion.reduced() then zoom.Home", 1, true), "Reduce motion keeps the player's view")
		T.truthy(string.find(code, "HatchRig.scale(model, HatchWorld.Scale)", 1, true), "the pooled eggs made for the stage")
	end)

	-- (owner 2026-11-15 evening, his Studio test of the 3D stage: "the egg opening is too bright and
	-- overexposed ... lower the Bloom and glow, fewer bright flashes and particles; the eggs and pets
	-- clearly visible with all their details; the magic kept, softer and balanced")
	T.test("EggWorld: the opening's light is soft: stage lights, motes, sparks, the silhouette, the flat pieces, the bloom", function()
		local Color3 = roblox.Color3
		local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
		local white = Color3.new(1, 1, 1)
		-- the stage's own light: a soft fill; its motes and sparks see-through, in their colour
		T.truthy(HatchWorld.Key.Brightness <= 0.7 and HatchWorld.Rim.Brightness <= 0.6, "the key and rim lights a quarter down")
		T.truthy(HatchWorld.MoteRate <= 32, "fewer motes")
		T.truthy(HatchWorld.Glow <= 0.5 and HatchWorld.White <= 0.2 and HatchWorld.SparkWhite <= 0.5, "less additive, less white")
		local world = HatchWorld.new({ Emit = function() end })
		for _, list in { world.MoteFx, world.SparkFx } do
			for _, e in list do
				T.near(e.LightEmission, HatchWorld.Glow, 1e-6, e.Name .. ": LightEmission")
				local least = 1
				for _, k in e.Transparency.Keypoints do
					least = math.min(least, k.Value)
				end
				T.truthy(least >= 0.25, e.Name .. ": never more than 3/4 opaque")
			end
		end
		local teal = Color3.fromRGB(40, 200, 220)
		HatchWorld.energy(world, 1, CFrame.new(0, 0, -1), 0.3, 20, teal)
		local moteStart = world.MoteFx[1].Color.Keypoints[1].Value
		T.near(moteStart.R, teal:Lerp(white, HatchWorld.White).R, 0.01, "a mote starts near its colour")
		HatchWorld.burst(world, 1, CFrame.new(0, 0, -1), 0.2, teal, 10)
		local sparkStart = world.SparkFx[1].Color.Keypoints[1].Value
		T.truthy(sparkStart.R < 0.9, "a spark starts a soft white, not pure white")
		HatchWorld.setLight(world, 1, 0.3)
		T.truthy(world.KeyLight.Brightness <= HatchWorld.Key.Brightness * 1.25 + 1e-6, "a Mythic's key light lifts gently")
		T.truthy(world.RimLight.Brightness <= HatchWorld.Rim.Brightness * 1.4 + 1e-6, "and its rim light")
		HatchWorld.clear(world)
		T.near(world.KeyLight.Brightness, HatchWorld.Key.Brightness, 1e-6, "back after it")

		-- the silhouette on the stage: its Neon at SilhouetteGlow of the colour (Neon draws at about
		-- twice its colour in the world); a viewport's egg as before (flat, the colour itself)
		T.truthy(HatchFx.SilhouetteGlow >= 0.4 and HatchFx.SilhouetteGlow <= 0.7, "about half: the colour, not a white blaze")
		local tl = HatchFx.timeline(4, 1, false, false)
		local pose = HatchFx.eggPose(tl.Burst - 0.001, tl, 1, false)
		local tint = HatchFx.crackColor("Epic", tl.Burst, 0.5, 0)
		local onStage = stageEgg("Stone")
		T.truthy(onStage.InWorld, "an egg made for the stage knows it")
		HatchFx.paintEgg(onStage, pose, "Epic", tl.Burst)
		local painted = 0
		for i, part in onStage.Parts do
			if onStage.Trans[i] < 1 then
				painted += 1
				T.eq(part.Material.Name, "Neon", part.Name .. ": glowing")
				T.near(part.Color.R, tint.R * HatchFx.SilhouetteGlow, 0.01, part.Name .. ": R")
				T.near(part.Color.G, tint.G * HatchFx.SilhouetteGlow, 0.01, part.Name .. ": G")
				T.near(part.Color.B, tint.B * HatchFx.SilhouetteGlow, 0.01, part.Name .. ": B")
			end
		end
		T.truthy(painted > 5, "the whole egg")
		HatchFx.reset(onStage)
		for i, part in onStage.Parts do
			T.eq(part.Color, onStage.Colors[i], part.Name .. ": its own colour back")
		end
		local flat = GolemBuilder.capsule("Stone")
		HatchFx.addCracks(flat, 3)
		local inViewport = HatchFx.record(flat)
		T.falsy(inViewport.InWorld, "a viewport's egg")
		HatchFx.paintEgg(inViewport, pose, "Epic", tl.Burst)
		for i, part in inViewport.Parts do
			if inViewport.Trans[i] < 1 then
				T.eq(part.Color, tint, part.Name .. ": the colour itself there")
			end
		end

		-- the flat pieces: a share of their old strength (HatchStage.Glow), the rings too
		for name, share in HatchStage.Glow do
			T.truthy(share > 0 and share <= 0.7, `Glow.{name}: softer, still there ({share})`)
		end
		local o = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(o, false, 1280, 720, { Touch = false, Inset = 36 })
		local ring = o.Rings[1][1]
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		RevealKit.poseRing(ring, 0, white, { Alpha = 0.5 })
		T.near(stroke.Transparency, 0.5, 1e-6, "a ring at half its strength")
		RevealKit.poseRing(ring, 0, white)
		T.near(stroke.Transparency, 0, 1e-6, "the other reveals' rings as before")
		-- a whole opening of three with a Legendary on the stage (its rays, aura and flash): nothing
		-- ever stronger than its share
		local stage = HatchWorld.new()
		CapsuleView.useBackdrop(o, stage.Surface)
		local run = playOnStage(stage, o, "Stone", { "PebbleGolem", "DiamondDuke", "CopperTinker" })
		local glow = HatchStage.Glow
		local flashLeast = 1 - HatchFx.flashPeakOf(run.Timeline) * glow.Flash - 1e-6
		local strongest = { Flash = 1, Orbit = 1, Aura = 1, Platform = 1, Sun = 1, Puff = 1 }
		local t = 0
		while t <= run.Timeline.Total + 0.1 do
			HatchStage.pose(run, t, { Space = CAMERA, Fov = 40 })
			if o.Flash.BackgroundTransparency < strongest.Flash then
				strongest.Flash = o.Flash.BackgroundTransparency
			end
			for _, list in o.Orbits do
				for _, orbit in list do
					local line = orbit:FindFirstChild("Line")
					if orbit.Visible and line then
						strongest.Orbit = math.min(strongest.Orbit, line.Transparency)
					end
				end
			end
			for _, aura in o.Auras do
				for _, disc in aura:GetChildren() do
					if aura.Visible and disc:IsA("Frame") then
						strongest.Aura = math.min(strongest.Aura, disc.BackgroundTransparency)
					end
				end
			end
			for _, platform in o.Platforms do
				local outer = platform:FindFirstChild("Outer")
				if platform.Visible and outer then
					strongest.Platform = math.min(strongest.Platform, outer.BackgroundTransparency)
				end
			end
			for _, piece in o.Sunburst:GetChildren() do
				if o.Sunburst.Visible and piece:IsA("Frame") then
					strongest.Sun = math.min(strongest.Sun, piece.BackgroundTransparency)
				end
			end
			for _, puff in o.Puffs do
				for _, disc in puff:GetChildren() do
					if puff.Visible and disc:IsA("Frame") then
						strongest.Puff = math.min(strongest.Puff, disc.BackgroundTransparency)
					end
				end
			end
			t += 0.02
		end
		T.truthy(strongest.Flash < 1 and strongest.Flash >= flashLeast, `one soft flash ({strongest.Flash})`)
		T.truthy(strongest.Orbit >= 1 - glow.Orbits - 1e-6, `the orbits ({strongest.Orbit})`)
		T.truthy(strongest.Aura >= 1 - 0.34 * glow.Auras - 1e-6, `the auras ({strongest.Aura})`)
		T.truthy(strongest.Platform >= 1 - 0.9 * glow.Platforms - 1e-6, `the platforms ({strongest.Platform})`)
		T.truthy(strongest.Sun >= 1 - 0.8 * glow.Sunburst - 1e-6, `the sunburst ({strongest.Sun})`)
		T.truthy(strongest.Puff >= 1 - 0.38 * glow.Puffs - 1e-6, `the puffs ({strongest.Puff})`)
		HatchStage.clear(o, nil, stage)

		-- the opening's own softer bloom in the camera, the zone's handed back (CapsuleController)
		local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
		local soft = CC.SoftBloom
		T.truthy(soft.Intensity <= 0.25 and soft.Size <= 16 and soft.Threshold >= 1.5, "a soft, small bloom over a high threshold")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local code = string.gsub(source, "%-%-[^\n]*", "")
		T.truthy(string.find(code, 'Lighting:FindFirstChildOfClass("BloomEffect")', 1, true), "the zone's bloom found")
		T.truthy(string.find(code, "bloom.Parent = camera", 1, true), "its own in the camera (LightingController never tweens it)")
		T.truthy(string.find(code, "zone.Enabled = false", 1, true), "the zone's off while it stands in")
		T.truthy(string.find(code, "zone.Enabled = home.Enabled", 1, true), "and back as it was")
		T.truthy(string.find(code, "Intensity = math.min(zone.Intensity, soft.Intensity)", 1, true), "never stronger than the zone's")
		T.truthy(string.find(code, "Threshold = math.max(zone.Threshold, soft.Threshold)", 1, true), "never a lower threshold")
		local _, ons = string.gsub(code, "setGlow%(true%)", "")
		T.truthy(ons >= 2, "on as a chain begins and for each opening of it")
		T.truthy(string.find(code, "setGlow(false)", 1, true), "off as the chain ends")
	end)

	-- (integrator review 2026-11-16)
	T.test("EggWorld: the player's own view for other camera features, Auto's wait, few resizes", function()
		local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
		-- the view still easing home after a chain: a camera feature saving it now gets the player's own
		local Workspace = Loader.game:GetService("Workspace")
		local RunService = Loader.game:GetService("RunService")
		local old = rawget(Workspace, "CurrentCamera")
		local oldUnbind = rawget(RunService, "UnbindFromRenderStep")
		local cam = { FieldOfView = 45 }
		local unbound: { string } = {}
		rawset(Workspace, "CurrentCamera", cam)
		rawset(RunService, "UnbindFromRenderStep", function(_, name: string)
			table.insert(unbound, name)
		end)
		local z = CC._test.zoom()
		local ok, err = pcall(function()
			CC._test.setPlaying(false)
			z.Bound, z.Home, z.Breath = true, 70, 0.4
			T.eq(CC.settleView(), 70, "the player's own view")
			T.eq(cam.FieldOfView, 70, "the camera back to it at once")
			T.eq(z.Bound, false, "the view's step let go")
			T.eq(unbound[1], "TerraForgeHatchZoom", "its render step unbound")
			T.eq(z.Home, nil, "no home kept for the next opening")
			T.eq(CC.settleView(), nil, "nothing easing: the camera's view is the player's")
			-- while an opening plays its view stays; the player's own is still named (a ride sent meanwhile)
			table.clear(unbound)
			CC._test.setPlaying(true)
			z.Bound, z.Home = true, 70
			cam.FieldOfView = 40
			T.eq(CC.settleView(), 70, "an opening plays: the player's own view named")
			T.eq(cam.FieldOfView, 40, "the stage's view untouched")
			T.eq(z.Bound, true, "its step kept")
			T.eq(#unbound, 0, "its render step kept")
			-- Auto stopped between two eggs: the view waiting AutoWait for the next egg eases back now
			CC._test.setPlaying(false)
			CC.setAuto(true)
			z.Start = os.clock() + CC.AutoWait
			CC.setAuto(false)
			T.near(z.Start, os.clock(), 0.05, "Auto stopped: the view eases back now")
			T.eq(z.To, 70, "to the player's own")
		end)
		CC._test.setPlaying(false)
		pcall(CC.setAuto, false)
		z.Bound, z.Home, z.Breath = false, nil, 0
		rawset(Workspace, "CurrentCamera", old)
		rawset(RunService, "UnbindFromRenderStep", oldUnbind)
		assert(ok, err)
		-- settleView puts the focus and the zone's bloom back at once too; Auto's stop sends all three out
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local code = string.gsub(controller, "%-%-[^\n]*", "")
		local settle = string.match(code, "function CapsuleController%.settleView%(%).-\nend\n") or ""
		T.truthy(
			string.find(settle, "setFocus(false, true)", 1, true) and string.find(settle, "setGlow(false, true)", 1, true),
			"settleView: the focus and the bloom back at once"
		)
		local stops = string.match(code, "afterAutoStops = function%(%).-\nend\n") or ""
		T.truthy(
			string.find(stops, "zoomOut()", 1, true)
				and string.find(stops, "setFocus(false)", 1, true)
				and string.find(stops, "setGlow(false)", 1, true),
			"Auto stopped: the view, the focus and the bloom go back"
		)
		-- the features that save the view and put it back later save the player's own
		local dir = Loader.root .. "/src/client/Controllers/"
		local placement = fs.readFile(dir .. "PlacementController.luau")
		T.truthy(
			string.find(placement, "savedFov = require(script.Parent.CapsuleController).settleView() or cam.FieldOfView", 1, true),
			"building saves the player's own view"
		)
		for file, save in
			{
				CleaningController = "ctx.savedFov = restoreFov or ownFov or camera.FieldOfView",
				ElevatorTravelController = "SavedFov = ownFov or (if camera then camera.FieldOfView",
				VaultController = "savedFov = ownFov or camera.FieldOfView",
			}
		do
			local source = fs.readFile(dir .. file .. ".luau")
			local settle = string.find(source, "local ownFov = CapsuleController.settleView()", 1, true)
			local saved = string.find(source, save, 1, true)
			T.truthy(settle ~= nil and saved ~= nil and settle < saved, file .. " saves the player's own view")
		end
		-- Auto: the view and the focus wait for its next egg (EggPanelController.LuckySettle and the answer)
		local panel = fs.readFile(dir .. "EggPanelController.luau")
		local settle = tonumber(string.match(panel, "EggPanelController%.LuckySettle = ([%d%.]+)"))
		T.truthy(settle ~= nil and CC.AutoWait >= (settle :: number) + 0.3, "Auto's next egg comes before the view goes")
		-- a drawn-smaller golem: its parts resized only once its size moved HatchRig.ResizeStep
		local golem = GolemBuilder.build("CloudColossus")
		local rig = HatchRig.new(golem)
		local index = 1
		while rig.Fixed[index] do
			index += 1
		end
		local part = rig.Parts[index]
		local own = rig.Sizes[index]
		HatchRig.place(rig, CFrame.new(), nil, nil, nil, 0.5)
		T.near(part.Size.X, own.X * 0.5, 1e-4, "drawn at half")
		HatchRig.place(rig, CFrame.new(), nil, nil, nil, 0.51)
		T.near(part.Size.X, own.X * 0.5, 1e-4, "a hair more: the last size holds")
		T.eq(rig.Scaled, 0.5, "and the scale the places use")
		HatchRig.place(rig, CFrame.new(), nil, nil, nil, 0.53)
		T.near(part.Size.X, own.X * 0.53, 1e-4, "past the step: resized")
		HatchRig.place(rig, CFrame.new())
		T.near(part.Size.X, own.X, 1e-4, "back to its own size")
	end)
end
