-- The egg opening (owner 2026-10-29: the clicker-sim video, "open them exactly like there, this
-- clean, glowing by rarity"; docs/plans/CLICKER_VIDEO_2026-10-29.md section 1): the timings (the
-- video's ~3.5 s Open 3, Auto's ~2 s, Reduce motion's calm one), the skips that never hide a
-- golem, where the eggs and golems stand (1 / 3 / 10, the special one centred and bigger, the top
-- centre free), the stage camera's maths, the poses in bounds, the cracks in the
-- colour of the golem inside each egg, ONE flash, the whole opening posed by HatchStage (every golem
-- out, SOLID, named with its "1 in N"), the opening's pieces on PC, phones and TVs, and a seventh
-- Rarity (the secret ores' "Secret") that never reaches the egg screens.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
	local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
	local BrightTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BrightTheme")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")

	local function golemOf(kind: string): (any, number, number)
		local model = GolemBuilder.build(kind)
		return model, model:GetAttribute("Height") or 3, model:GetAttribute("RootHeight") or 1
	end

	-- an opening of `kinds` from `egg` on a `w` x `h` design-unit screen, its eggs from the game's builders
	local function runOf(
		egg: string,
		kinds: { string },
		opts: {
			Fast: boolean?,
			Reduced: boolean?,
			Phone: boolean?,
			W: number?,
			H: number?,
			Deleted: { [number]: boolean }?,
			Waiting: { [number]: boolean }?,
		}?
	): (any, any, { number })
		local o2 = opts or {}
		local o = CapsuleView.buildOpening(o2.Phone == true)
		CapsuleView.layoutOpening(o, o2.Phone == true, o2.W or 1280, o2.H or 720, { Touch = o2.Phone == true, Inset = 36 })
		local eggs = {}
		for _ = 1, #kinds do
			local model = GolemBuilder.capsule(egg)
			HatchFx.addCracks(model, 3)
			model:SetAttribute("Pooled", true)
			table.insert(eggs, HatchFx.record(model))
		end
		local claims = { 0 }
		local run = HatchStage.new({
			Refs = o,
			Capsule = egg,
			Lucky = false,
			Kinds = kinds,
			Eggs = eggs,
			Fast = o2.Fast == true,
			Reduced = o2.Reduced == true,
			Phone = o2.Phone == true,
			Target = Vector2.new(0.5, 0.86),
			Golem = golemOf,
			Claim = function(): boolean
				claims[1] += 1
				return true
			end,
			Deleted = o2.Deleted,
			Waiting = o2.Waiting,
		})
		return o, run, claims
	end

	T.test("EggOpening: the timings (Open 3 about 3.5 s, Auto about 2 s, a Legendary's suspense, Reduce motion calm)", function()
		for order = 1, 6 do
			for _, count in { 1, 3, 10 } do
				for _, mode in { "normal", "fast", "calm" } do
					local tl = HatchFx.timeline(order, count, mode == "fast", mode == "calm")
					local label = `order {order} x{count} {mode}`
					-- the steps in order: pop, the cracks' three steps, the silhouette, the burst, the golems, the flight, the end
					T.truthy(tl.Steps[1] < tl.Steps[2] and tl.Steps[2] < tl.Steps[3], label .. ": three crack steps")
					T.truthy(
						tl.Steps[3] < tl.Silhouette and tl.Silhouette < tl.Burst and tl.Burst <= tl.Reveal,
						label .. ": the burst after the cracks"
					)
					T.truthy(tl.Reveal < tl.Fly and tl.Fly < tl.Total, label .. ": the golems, then their flight")
					T.truthy(
						tl.Fly - tl.Reveal >= HatchFx.namedAt(tl) + HatchFx.MinShow,
						label .. ": the last golem's name shows MinShow at least"
					)
					-- the last egg is in before the first crack (Open 10's ripple)
					T.truthy(tl.Steps[1] >= (count - 1) * tl.Stagger + tl.Times.Pop, label .. ": every egg in before it cracks")
					T.eq(tl.Suspense > 0, order >= 5 and mode ~= "calm", label .. ": the suspense only for a Legendary / Mythic (not calm)")
					if mode == "calm" then
						T.eq(tl.Rings, math.huge, label .. ": no rings with Reduce motion")
					end
				end
			end
		end
		local open3 = HatchFx.timeline(4, 3, false, false)
		T.truthy(open3.Total >= 3.2 and open3.Total <= 3.8, `Open 3 about 3.5 s (the video): {open3.Total}`)
		local fast = HatchFx.timeline(4, 3, true, false)
		T.truthy(fast.Total >= 1.7 and fast.Total <= 2.2, `Auto about 2 s: {fast.Total}`)
		local legendary = HatchFx.timeline(5, 3, false, false)
		T.near(legendary.Total - open3.Total, HatchFx.Suspense, 1e-9, "a Legendary: the suspense on top")
		T.near(HatchFx.timeline(6, 3, true, false).Total - fast.Total, HatchFx.SuspenseFast, 1e-9)
	end)

	T.test("EggOpening: a skip never hides a golem (to the burst, then on only after MinShow)", function()
		local tl = HatchFx.timeline(3, 3, false, false)
		T.eq(HatchFx.skipTo(0.2, tl, 0), tl.Burst, "a tap while the eggs crack: straight to the burst")
		T.eq(HatchFx.skipTo(tl.Reveal + 0.1, tl, 0.1), nil, "the golems just came out: not yet")
		T.eq(HatchFx.skipTo(tl.Reveal + 0.1, tl, HatchFx.namedAt(tl) + HatchFx.MinShow), tl.Fly, "seen: on to their flight")
		-- Open 10 skipped (review 2026-10-30 LOW 5): the flight waits until the LAST golem's name showed MinShow
		for _, fast in { false, true } do
			local ten = HatchFx.timeline(3, 10, fast, false)
			local named = HatchFx.namedAt(ten)
			T.eq(HatchFx.skipTo(ten.Reveal + 0.2, ten, named + HatchFx.MinShow - 0.01), nil, "not before slot 10 was readable MinShow")
			T.eq(HatchFx.golemPose(ten.Reveal + named, ten, 10).Name, 0, "slot 10's name fully shown at namedAt")
			T.truthy(HatchFx.golemPose(ten.Reveal + named - 0.05, ten, 10).Name > 0, "and not before")
		end
		T.eq(HatchFx.skipTo(tl.Fly + 0.1, tl, 2), tl.Fly + 0.1, "the flight: nothing to skip")
		-- the controller: skip-all waits for MinShow in real time, B / Backspace / A / Space are bound
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		T.truthy(string.find(source, "wantFly = true", 1, true), "a skip asks for the flight and waits")
		-- (the bindings, whatever the formatter's line breaks)
		local flat = string.gsub(source, "%s+", " ")
		T.truthy(string.find(flat, "Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA", 1, true), "Space / Enter / A skip")
		T.truthy(string.find(flat, "Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB", 1, true), "Backspace / B skip all")
		T.truthy(string.find(source, 'PromptConfig.keys("Second").Keyboard', 1, true), "Auto's own key (G) works in the opening")
	end)

	T.test("EggOpening: where the eggs and golems stand (1 big, 3 overlapping, 10 in two rows; the special one centred, bigger)", function()
		for _, aspect in { 4 / 3, 16 / 9, 2.16, 844 / 390 } do
			for _, count in { 1, 3, 10 } do
				for _, special in { false, true } do
					local slot = if special then HatchFx.centreSlot(count) else nil
					local l = HatchFx.layout(count, aspect, slot)
					local label = `x{count} at {math.floor(aspect * 100) / 100}{if special then " special" else ""}`
					T.eq(#l.Slots, count, label)
					for i, s in l.Slots do
						-- on the screen, the egg and the golem whole
						T.truthy(s.Egg.Y - s.EggH / 2 >= 0.02 and s.Egg.Y + s.EggH / 2 <= 0.98, `{label} {i}: the egg on the screen`)
						T.truthy(
							s.Golem.Y - s.GolemH / 2 >= 0.02 and s.Golem.Y + s.GolemH / 2 <= 0.9,
							`{label} {i}: the golem with room for its name`
						)
						T.truthy(s.Egg.X > 0.05 and s.Egg.X < 0.95, `{label} {i}: inside the width`)
						-- the top centre stays free (room for a quest card)
						if math.abs(s.Egg.X - 0.5) < 0.2 then
							T.truthy(s.Egg.Y - s.EggH / 2 >= 0.16, `{label} {i}: the top centre free`)
						end
						-- names at least 18 px at 1080p (the HUD's 1.25)
						T.truthy(s.Text * 1.25 >= 18, `{label} {i}: the name's size`)
					end
					if special and slot then
						local s = l.Slots[slot]
						T.near(s.Golem.X, 0.5, 1e-9, label .. ": the special golem centred")
						for i, other in l.Slots do
							if i ~= slot then
								T.truthy(s.GolemH > other.GolemH, label .. ": and bigger")
							end
						end
					end
				end
			end
		end
		-- one egg: in the middle at 60 % of the height; three: the middle one bigger, overlapping
		local one = HatchFx.layout(1, 16 / 9, nil).Slots[1]
		T.near(one.Egg.X, 0.5, 1e-9)
		T.near(one.EggH, 0.6, 1e-9)
		local three = HatchFx.layout(3, 16 / 9, nil).Slots
		T.truthy(three[2].EggH > three[1].EggH and three[2].Front, "the middle one bigger, in front")
		T.truthy((three[2].Egg.X - three[1].Egg.X) * 16 / 9 < (three[1].EggH + three[2].EggH) * 0.36, "side by side, overlapping")
		local ten = HatchFx.layout(10, 16 / 9, nil).Slots
		T.eq(ten[1].Egg.Y, ten[5].Egg.Y, "a row of five")
		T.truthy(ten[6].Egg.Y > ten[1].Egg.Y, "then the second row")
		-- the special one goes to the middle slot; the others keep their order round it
		local order, special = HatchFx.arrange(3, 1, 5)
		T.eq(special, 2)
		T.eq(order[2], 1, "the Legendary in the middle")
		T.eq(order[1] + order[3], 5, "the other two kept")
		local plain, none = HatchFx.arrange(3, 3, 4)
		T.eq(none, nil, "an Epic stays where it is")
		T.eq(plain[3], 3)
		local _, tenSpecial = HatchFx.arrange(10, 9, 6)
		T.eq(tenSpecial, 3, "Open 10: the top row's middle")
	end)

	T.test("EggOpening: the stage camera's maths (a point projects back, a height fills its share)", function()
		for _, aspect in { 4 / 3, 16 / 9, 2.16 } do
			for _, uv in { { 0.5, 0.5 }, { 0.2, 0.7 }, { 0.83, 0.31 } } do
				local p = HatchFx.at(uv[1], uv[2], 12, aspect)
				local back, depth = HatchFx.project(p, aspect)
				T.near(back.X, uv[1], 1e-5) -- (Vector3 holds float32)
				T.near(back.Y, uv[2], 1e-5)
				T.near(depth, 12, 1e-4)
				T.truthy(p.Z < 0, "in front of the camera (it looks along -Z)")
			end
		end
		-- a thing 4.4 studs tall at depthFor(4.4, 0.6) is 60 % of the screen's height
		local z = HatchFx.depthFor(4.4, 0.6)
		local top = HatchFx.project(Vector3.new(0, 2.2, -z), 16 / 9)
		local bottom = HatchFx.project(Vector3.new(0, -2.2, -z), 16 / 9)
		T.near(bottom.Y - top.Y, 0.6, 1e-5)
	end)

	T.test("EggOpening: the eggs pop, wobble about 12 degrees, pulse at each crack step, turn into their colour, burst", function()
		for _, order in { 1, 5 } do
			for _, fast in { false, true } do
				local tl = HatchFx.timeline(order, 3, fast, false)
				local maxRoll, maxScale = 0, 0
				for i = 0, 400 do
					local t = tl.Burst * i / 400
					for slot = 1, 3 do
						local pose = HatchFx.eggPose(t, tl, slot, slot == 2)
						if pose.Shown then
							maxRoll = math.max(maxRoll, math.abs(pose.Roll))
							maxScale = math.max(maxScale, pose.Scale)
							T.truthy(pose.Scale >= 0.25 and pose.Scale <= 1.4, "in bounds")
						end
					end
				end
				T.truthy(maxRoll >= math.rad(8) and maxRoll <= math.rad(20), `a real wobble, never wild ({math.deg(maxRoll)} degrees)`)
				T.truthy(maxScale > 1.05, "it pulses")
				T.falsy(HatchFx.eggPose(tl.Burst, tl, 1, false).Shown, "gone at the burst")
				T.eq(HatchFx.eggPose(tl.Silhouette - 0.01, tl, 1, false).Silhouette, 0)
				T.near(HatchFx.eggPose(tl.Burst - 0.001, tl, 1, false).Silhouette, 1, 1e-9, "a solid silhouette before it bursts")
				T.eq(HatchFx.eggPose(tl.Steps[2] + 0.01, tl, 1, false).Level, 2, "the second step")
				if order >= 5 then
					local mid = tl.Steps[3] + tl.Suspense * 0.5
					T.truthy(HatchFx.eggPose(mid, tl, 2, true).Bright > 0, "the suspense: brighter cracks")
				end
			end
		end
		-- Reduce motion: still, a fade in and out, no rings
		local calm = HatchFx.timeline(5, 3, false, true)
		for i = 0, 100 do
			local t = calm.Burst * i / 100
			local pose = HatchFx.eggPose(t, calm, 2, true)
			T.eq(pose.Roll, 0, "no wobble")
			T.eq(pose.Scale, 1, "no pop")
			local u = HatchFx.ringU(t, calm, 1)
			T.truthy(u < 0 or u >= 1, "no ring")
		end
		T.truthy(HatchFx.eggPose(0.05, calm, 1, false).Fade > 0, "it fades in")
		-- the golems pop, bob, fly to the player shrinking; their names go first
		local tl = HatchFx.timeline(3, 3, false, false)
		T.falsy(HatchFx.golemPose(tl.Reveal - 0.01, tl, 1).Shown)
		local standing = HatchFx.golemPose(tl.Reveal + tl.Times.GolemPop + 0.2, tl, 1)
		T.truthy(standing.Shown and standing.Name == 0 and standing.Fly == 0, "standing, named")
		local flying = HatchFx.golemPose(tl.Fly + tl.Times.Fly * 0.5, tl, 1)
		T.truthy(flying.Fly > 0 and flying.Spin > 0 and flying.Name > 0, "spinning away, the name gone")
		local spot, depth = HatchFx.flyTo(Vector2.new(0.3, 0.4), 10, Vector2.new(0.5, 0.86), 1)
		T.near(spot.X, 0.5, 1e-9)
		T.truthy(depth > 30, "far: small")
		T.falsy(HatchFx.golemPose(tl.Total, tl, 1).Shown, "gone at the end")
		-- ONE flash, never fully opaque, gone in FlashTime; 2.5 a second at most (the shared clock)
		-- (RevealKit's flash frame and fade)
		local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
		local frame = Instance.new("Frame")
		RevealKit.poseFlash(frame, HatchFx.flashU(-0.01), HatchFx.FlashPeak)
		T.eq(frame.BackgroundTransparency, 1, "none before the burst")
		RevealKit.poseFlash(frame, HatchFx.flashU(0), HatchFx.FlashPeak)
		T.truthy(frame.BackgroundTransparency >= 1 - HatchFx.FlashPeak - 1e-6 and HatchFx.FlashPeak < 1, "never fully opaque")
		RevealKit.poseFlash(frame, HatchFx.flashU(HatchFx.FlashTime), HatchFx.FlashPeak)
		T.eq(frame.BackgroundTransparency, 1, "gone in FlashTime")
		T.truthy(1 / RevealKit.FlashGap <= 2.5 + 1e-9, "RevealKit's one gap: 2.5 flashes a second at most")
		T.truthy(HatchFx.FlashTime <= 0.35, "it fades in about 0.3 s (the video)")
	end)

	T.test("EggOpening: the cracks glow in the colour of the golem inside (white Common, a moving rainbow Mythic)", function()
		T.eq(HatchFx.crackColor("Common", 0, 0, 0), BrightTheme.crackColour("Common"), "white for Common")
		T.eq(HatchFx.crackColor("Epic", 0, 0, 0), Rarity.ById.Epic.Color, "the rarity's colour")
		T.truthy(HatchFx.crackColor("Mythic", 0, 0.2, 0) ~= HatchFx.crackColor("Mythic", 0.5, 0.2, 0), "Mythic's rainbow moves")
		T.truthy(HatchFx.crackColor("Mythic", 0, 0, 0) ~= HatchFx.crackColor("Mythic", 0, 0.5, 0), "and runs along the cracks")
		-- the suspense whitens the cracks steadily: no pulse (review 2026-10-30 LOW 8: never over 2.5 a second)
		T.eq(HatchFx.crackColor("Legendary", 1.0, 0.3, 0.8), HatchFx.crackColor("Legendary", 1.07, 0.3, 0.8), "no flicker")
		-- the network: built once on the opening's eggs, hidden, Neon, flat on the shell, three steps
		local model = GolemBuilder.capsule("Stone")
		local before = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				before += 1
			end
		end
		HatchFx.addCracks(model, 3)
		local rec = HatchFx.record(model)
		local levels = { 0, 0, 0 }
		for _, crack in rec.Cracks do
			T.eq(crack.Part.Transparency, 1, crack.Part.Name .. ": hidden until it cracks")
			T.eq(crack.Part.Material, roblox.Enum.Material.Neon)
			levels[crack.Level] += 1
		end
		T.truthy(levels[1] > 0 and levels[2] > 0 and levels[3] > 0, "three steps")
		T.eq(#rec.Cracks, #rec.Parts - before, "every new part a crack")
		T.truthy(rec.Height > 3 and rec.Height < 7, "the egg's height measured")
		local fewer = GolemBuilder.capsule("Stone")
		HatchFx.addCracks(fewer, 2)
		T.truthy(#HatchFx.record(fewer).Cracks < #rec.Cracks, "a phone opening many: two steps built")
		-- lit step by step, each a step thicker; the silhouette paints the whole egg; reset puts it back
		local tl = HatchFx.timeline(4, 1, false, false)
		local lit = function(): number
			local n = 0
			for _, crack in rec.Cracks do
				if crack.Part.Transparency < 1 then
					n += 1
				end
			end
			return n
		end
		HatchFx.paintEgg(rec, HatchFx.eggPose(tl.Steps[1] + 0.01, tl, 1, false), "Epic", tl.Steps[1])
		local first = lit()
		local width1 = rec.Cracks[1].Part.Size.X
		HatchFx.paintEgg(rec, HatchFx.eggPose(tl.Steps[3] + 0.01, tl, 1, false), "Epic", tl.Steps[3])
		T.truthy(first > 0 and lit() > first, "more cracks at each step")
		T.truthy(rec.Cracks[1].Part.Size.X > width1, "thicker")
		T.eq(rec.Cracks[1].Part.Color, Rarity.ById.Epic.Color, "in the golem's colour")
		HatchFx.paintEgg(rec, HatchFx.eggPose(tl.Burst - 0.001, tl, 1, false), "Epic", tl.Burst)
		for i, part in rec.Parts do
			if rec.Trans[i] < 1 then
				T.eq(part.Color, Rarity.ById.Epic.Color, part.Name .. ": the silhouette's colour")
			end
		end
		HatchFx.reset(rec)
		T.eq(lit(), 0, "back in the pool: the cracks hidden")
		for i, part in rec.Parts do
			T.eq(part.Color, rec.Colors[i], part.Name .. ": its own colour back")
		end
	end)

	T.test("EggOpening: an Open 3 posed whole: ONE flash, every golem out SOLID with its name and 1 in N, then gone", function()
		local kinds = { "RoseKnight", "QuartzSprite", "CopperTinker" }
		local o, run, claims = runOf("Stone", kinds)
		local tl = run.Timeline
		local seen: { string } = {}
		local named: { [string]: string } = {}
		local t = 0
		while t <= tl.Total do
			for _, event in HatchStage.pose(run, t) do
				table.insert(seen, event)
			end
			if t >= tl.Reveal + tl.Times.GolemPop and t < tl.Fly then
				for slot = 1, 3 do
					local tag = o.Tags[slot]
					if tag.Frame.Visible and tag.Name.TextTransparency == 0 then
						named[tag.Name.Text] = tag.Chance.Text
					end
				end
				-- SOLID: the stage opaque, the flash, the sunburst and the blobs under it
				T.eq(o.Stage.ImageTransparency, 0, "the golems' view opaque")
				for _, model in HatchStage.golems(run) do
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Transparency > 0 and d.Transparency < 1 then
							T.truthy(false, d.Name .. " see-through")
						end
					end
				end
			end
			t += 1 / 30
		end
		for _, event in HatchStage.pose(run, tl.Total) do
			table.insert(seen, event)
		end
		T.eq(table.concat(seen, ","), "Step1,Step2,Step3,Burst,Reveal,Fly,End", "in order, each once")
		T.eq(claims[1], 1, "ONE flash an opening (asked of the shared clock)")
		T.truthy(
			o.Flash.ZIndex < o.Stage.ZIndex and o.Sunburst.ZIndex < o.Stage.ZIndex and o.Blobs[1].ZIndex < o.Stage.ZIndex,
			"under the golems"
		)
		T.truthy(o.Tags[1].Name.ZIndex > o.Stage.ZIndex, "the names over them")
		for _, kind in kinds do
			local name = GolemConfig.ById[kind].Name
			local chance = HatchStage.chance("Stone", false, kind)
			T.eq(named[name], BrightTheme.oneInText(chance), name .. ": named, its 1 in N")
		end
		T.eq(named["Rose Knight"], "1 in 500")
		-- the end: the golems gone, nothing left on the screen
		for _, tag in o.Tags do
			T.falsy(tag.Frame.Visible, "the names gone")
		end
		HatchStage.clear(o, HatchStage.golems(run))
		local models = 0
		for _, child in o.Stage:GetChildren() do
			if child:IsA("Model") then
				models += 1
			end
		end
		T.eq(models, 0, "the stage empty: the golems freed, the eggs back in the pool")
	end)

	T.test("EggOpening: each egg's shell pieces in its own colour; the names follow the golems when the screen changes", function()
		local kinds = { "RoseKnight", "QuartzSprite", "CopperTinker" }
		local o, run = runOf("Stone", kinds)
		-- poseBits hands egg k the k-th block of `per` pieces: they are its colour (or white)
		local per = math.max(1, math.floor(#o.Shards / run.Count))
		for i, piece in o.Shards do
			local slot = math.min(run.Count, (i - 1) // per + 1)
			local c = piece.BackgroundColor3
			local white = c.R == 1 and c.G == 1 and c.B == 1
			T.truthy(white or c == run.Colors[slot], `piece {i}: egg {slot}'s colour or white`)
		end
		-- the golems out, then the screen turns (a phone rotated, a window resized): the names move with them
		local tl = run.Timeline
		HatchStage.pose(run, tl.Reveal + tl.Times.GolemPop + 0.2)
		local function check(label: string)
			local size = run.Size
			local aspect = size.X / size.Y
			for slot, standing in run.Standing do
				local feet = HatchFx.at(standing.Spot.X, standing.Spot.Y, standing.Depth, aspect) - Vector3.new(0, standing.Height / 2, 0)
				local under = HatchFx.project(feet, aspect)
				local tag = o.Tags[slot]
				T.near(tag.Frame.Position.X.Offset, under.X * size.X, 1.5, `{label} slot {slot}: the name under its golem`)
			end
		end
		check("1280 x 720")
		local before = o.Tags[1].Frame.Position.X.Offset
		CapsuleView.layoutOpening(o, false, 1600, 720, {})
		HatchStage.pose(run, tl.Reveal + tl.Times.GolemPop + 0.3)
		check("1600 x 720")
		T.truthy(math.abs(o.Tags[1].Frame.Position.X.Offset - before) > 4, "(it moved)")
		HatchStage.pose(run, tl.Total)
		HatchStage.clear(o, HatchStage.golems(run))
	end)

	T.test("EggOpening: names step aside for the Auto button only while it shows, never out of their column", function()
		local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
		local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
		-- long names (the review's case: "Dragonscale Knight" under the bottom-left of an Open 10)
		local long = { "ScaleKnight", "HeartstoneColossus", "CelestialSovereign", "MoonstoneOracle", "AmethystAcolyte" }
		for _, n in { 5, 10 } do
			local kinds = {}
			for i = 1, n do
				kinds[i] = long[(i - 1) % #long + 1]
			end
			for _, autoShown in { false, true } do
				local o, run = runOf(if n == 10 then "Crystal" else "Royal", kinds, { Waiting = { [6] = true, [1] = true } })
				CapsuleView.layoutOpening(o, false, 1280, 720, { Inset = 29 })
				CapsuleView.setAuto(o, autoShown, false, "G", nil)
				local tl = run.Timeline
				HatchStage.pose(run, tl.Reveal + HatchFx.namedAt(tl) + 0.05)
				local size = run.Size
				local aspect = size.X / size.Y
				local pitch = run.Layout.Spacing * size.X * 0.96
				local boxes = {}
				for slot, standing in run.Standing do
					local tag = o.Tags[slot]
					local feet = HatchFx.at(standing.Spot.X, standing.Spot.Y, standing.Depth, aspect)
						- Vector3.new(0, standing.Height / 2, 0)
					local under = HatchFx.project(feet, aspect).X * size.X
					local x = tag.Frame.Position.X.Offset
					local label = `n {n}, Auto {if autoShown then "shown" else "hidden"}, slot {slot}`
					-- (offsets are whole units)
					if not autoShown then
						T.near(x, under, 1, label .. ": under its golem")
					else
						T.truthy(x >= under - 1 and x - under <= pitch / 2 + 1, label .. ": within its own column")
					end
					-- (what shows of it: the name as setTag measures it, its note)
					local nameW = TechShopView.textWidth(tag.Name.Text, tag.Name.TextSize) * 1.04 + 8
					local w = math.max(nameW, if tag.Waiting.Visible then tag.Waiting.Size.X.Offset else 0)
					table.insert(boxes, {
						Slot = slot,
						Box = {
							Min = Vector2.new(x - w / 2, tag.Frame.Position.Y.Offset),
							Max = Vector2.new(x + w / 2, tag.Frame.Position.Y.Offset + 30),
						},
					})
				end
				-- no tag runs into a neighbour (the same row)
				for i = 1, #boxes do
					for j = i + 1, #boxes do
						local a, b = boxes[i].Box, boxes[j].Box
						if math.abs(a.Min.Y - b.Min.Y) < 20 then
							T.eq(EggPanel.overlap(a, b), 0, `n {n}: slots {boxes[i].Slot} and {boxes[j].Slot} apart`)
						end
					end
				end
				HatchStage.pose(run, tl.Total)
				HatchStage.clear(o, HatchStage.golems(run))
			end
		end
	end)

	T.test("EggOpening: DELETED and the waiting note fade with the names (Reduce motion's calm fade too)", function()
		for _, calm in { false, true } do
			local o, run = runOf("Stone", { "RoseKnight", "PebbleGolem", "CopperTinker" }, {
				Reduced = calm,
				Deleted = { [2] = true },
				Waiting = { [3] = true },
			})
			local tl = run.Timeline
			local partial, solid = 0, 0
			local t = tl.Reveal
			while t < tl.Total do
				HatchStage.pose(run, t)
				for slot = 1, 3 do
					local tag = o.Tags[slot]
					if tag.Frame.Visible then
						local a = tag.Name.TextTransparency
						for _, mark in { tag.Deleted, tag.Waiting } do
							if mark.Visible then
								T.near(
									mark.BackgroundTransparency,
									a,
									1e-4,
									`{if calm then "calm" else "normal"}: {mark.Name} with its name`
								)
								local rim = mark:FindFirstChild("Rim")
								T.near(rim.Transparency, a, 1e-4)
								partial += if a > 0.05 and a < 0.95 then 1 else 0
								solid += if a == 0 then 1 else 0
							end
						end
						if tag.Waiting.Visible then
							T.near(tag.WaitingText.TextTransparency, a, 1e-4, "the note's words too")
						end
					end
				end
				t += 1 / 30
			end
			T.truthy(partial > 0, "(seen mid-fade)")
			T.truthy(solid > 0, "(and solid)")
			HatchStage.pose(run, tl.Total)
			HatchStage.clear(o, HatchStage.golems(run))
		end
	end)

	T.test("EggOpening: an auto-deleted golem comes out greyed, DELETED under its name, and never flies to the player", function()
		local kinds = { "RoseKnight", "PebbleGolem", "CopperTinker" }
		local o, run = runOf("Stone", kinds, { Deleted = { [2] = true } })
		local tl = run.Timeline
		local aspect = 1280 / 720
		HatchStage.pose(run, tl.Reveal + tl.Times.GolemPop + 0.05)
		local slot: number? = nil
		for s, on in run.Deleted do
			if on then
				slot = s
			end
		end
		T.truthy(slot ~= nil, "the auto-deleted golem has a slot")
		local gone = slot :: number
		T.eq(run.Standing[gone].Model:GetAttribute("Kind") or kinds[2], kinds[2], "the PebbleGolem's slot")
		for s = 1, #kinds do
			local tag = o.Tags[s]
			T.truthy(tag.Frame.Visible, `slot {s} named`)
			T.eq(tag.Deleted.Visible, s == gone, `slot {s}: DELETED only under the auto-deleted one`)
		end
		-- greyed (its shape stays, never see-through, no glow)
		for _, d in run.Standing[gone].Model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local c = d.Color
				T.truthy(math.abs(c.R - c.G) < 0.02 and math.abs(c.B - c.G) < 0.05, d.Name .. ": grey")
				T.truthy(d.Material ~= roblox.Enum.Material.Neon, d.Name .. ": no glow")
			end
		end
		local function screenOf(s: number): Vector2
			local at = HatchFx.project(run.Standing[s].Model:GetPivot().Position, aspect)
			return at
		end
		local other = if gone == 1 then 2 else 1
		local target = Vector2.new(0.5, 0.86)
		local goneAt, otherAt = screenOf(gone), screenOf(other)
		local goneDeep = -run.Standing[gone].Model:GetPivot().Position.Z
		-- the flight: the others go to the player, the auto-deleted one stays where it stood and shrinks away
		HatchStage.pose(run, tl.Fly + tl.Times.Fly * 0.8)
		T.truthy(math.abs(screenOf(gone).X - goneAt.X) < 0.01, "it stays where it stood")
		T.truthy((screenOf(gone) - target).Magnitude > (goneAt - target).Magnitude - 0.03, "never toward the player")
		T.truthy(-run.Standing[gone].Model:GetPivot().Position.Z > goneDeep * 1.2, "it shrinks away (further off)")
		T.truthy((screenOf(other) - target).Magnitude < (otherAt - target).Magnitude - 0.05, "the kept ones fly to the player")
		HatchStage.pose(run, tl.Total)
		HatchStage.clear(o, HatchStage.golems(run))
	end)

	T.test("EggOpening: Open 10 with a Legendary (centred, bigger), a Mythic, Reduce motion and Auto all end, named", function()
		local cases = {
			{
				"Crystal",
				{
					"QuartzSprite",
					"SilverSquire",
					"EmberImp",
					"JadeGardener",
					"CobaltDiver",
					"AmethystAcolyte",
					"MoonstoneOracle",
					"QuartzSprite",
					"RoseKnight",
					"SilverSquire",
				},
				{},
			},
			{ "Crystal", { "HeartstoneColossus" }, {} },
			{ "Stone", { "RoseKnight", "QuartzSprite", "CopperTinker" }, { Reduced = true } },
			{ "Stone", { "PebbleGolem", "SilverSquire", "CoalChomper" }, { Fast = true } },
			{ "Stone", { "PebbleGolem", "SilverSquire", "CoalChomper" }, { Phone = true, W = 1361, H = 629 } },
		}
		for _, case in cases do
			local o, run, claims = runOf(case[1], case[2], case[3])
			local tl = run.Timeline
			local label = `{case[1]} x{#case[2]}`
			HatchStage.pose(run, tl.Reveal + tl.Times.GolemPop + 0.2)
			local shown = 0
			for slot = 1, #case[2] do
				local tag = o.Tags[slot]
				if tag.Frame.Visible then
					shown += 1
					local pos = tag.Frame.Position
					T.truthy(pos.X.Offset > 0 and pos.X.Offset < o.Size.X and pos.Y.Offset < o.Size.Y, label .. ": the name on the screen")
				end
			end
			T.eq(shown, #case[2], label .. ": every golem named")
			if #case[2] == 10 then
				T.eq(run.Special, 3, "the Legendary in the top row's middle")
				T.eq(run.Kinds[3], "MoonstoneOracle")
			end
			HatchStage.pose(run, tl.Total)
			T.eq(claims[1], if case[3].Reduced then 0 else 1, label .. ": the flash (none with Reduce motion)")
		end
	end)

	T.test("EggOpening: the pieces on PC, phones and a TV (Auto 44 pt, clear of the thumbstick, nothing but name and 1 in N)", function()
		-- a phone at the HUD's floor (0.62): 844 x 390 pt = 1361 x 629 design units, Roblox's row 58 pt
		local scale = 0.62
		local o = CapsuleView.buildOpening(true)
		local w, h, inset = 844 / scale, 390 / scale, 58 / scale
		CapsuleView.layoutOpening(o, true, w, h, { Touch = true, Inset = inset })
		T.truthy(o.Auto.Size.Y.Offset * scale >= 44 - 0.5, "the Auto button: 44 pt")
		local bottom = inset + o.AutoHolder.Position.Y.Offset + o.Auto.Size.Y.Offset
		T.truthy(bottom <= h * CapsuleView.ThumbZone.Top + 1, "above the thumbstick's zone")
		-- the taps that skip leave the zone free (the player can walk)
		T.near(o.Tap.Position.X.Offset, w * CapsuleView.ThumbZone.Width, 1, "the taps right of the zone (whole units)")
		T.truthy(o.TapTop.Size.Y.Offset <= h * CapsuleView.ThumbZone.Top + 1e-6, "and over it, its column's top only")
		-- the smallest phone (568 x 320): still above the zone, still 44 pt
		local tiny = CapsuleView.buildOpening(true)
		CapsuleView.layoutOpening(tiny, true, 568 / scale, 320 / scale, { Touch = true, Inset = inset })
		local tinyBottom = inset + tiny.AutoHolder.Position.Y.Offset + tiny.Auto.Size.Y.Offset
		T.truthy(tinyBottom <= (320 / scale) * CapsuleView.ThumbZone.Top + 1, "568 x 320: above the zone")
		-- PC: bottom left; a TV: inside its safe margin
		local pc = CapsuleView.buildOpening(false)
		CapsuleView.layoutOpening(pc, false, 1280, 720, { Inset = 29 })
		T.eq(pc.AutoHolder.AnchorPoint, Vector2.new(0, 1), "bottom left")
		T.falsy(pc.TapTop.Visible, "one tap layer on PC")
		local tv = CapsuleView.buildOpening(true)
		CapsuleView.layoutOpening(tv, true, 1536, 864, { Inset = 29, TenFoot = true })
		T.truthy(tv.AutoHolder.Position.X.Offset >= 1536 * 0.05, "a TV: inside its safe margin")
		-- the "2 / 5" counter: just under the top bar; a TV: inside its 5 % title-safe band too
		CapsuleView.setChain(tv, 2, 5)
		T.truthy(29 + tv.Chain.Position.Y.Offset >= 864 * 0.05 - 1e-6, "a TV: the counter inside the title-safe band")
		T.eq(pc.Chain.Position.Y.Offset, 8, "PC: just under the top bar")
		-- touch: top right (the top middle is a big golem's head there), out of the thumbstick's zone, against
		-- the Controls gui's own right edge (its notch-safe frame, narrower than the viewport on a notched phone)
		T.eq(o.Chain.AnchorPoint, Vector2.new(1, 0))
		T.eq(o.Chain.Position.X.Scale, 1, "the gui's own width, never the viewport's")
		T.truthy(o.Chain.Position.X.Offset < 0, "inside its right edge")
		local chainLeft = w + o.Chain.Position.X.Offset - o.Chain.Size.X.Offset
		T.truthy(chainLeft > w * CapsuleView.ThumbZone.Width, "right of the zone")
		T.truthy(
			inset + o.Chain.Position.Y.Offset + o.Chain.Size.Y.Offset <= h * CapsuleView.ThumbZone.Top,
			"at the top, just under Roblox's row"
		)
		T.truthy(tv.Chain.TextSize * 1.25 >= 18, "the counter: 18 px at 1080p")
		-- text: 18 px at 1080p (1.25), 10 pt on a phone
		for _, label in { pc.AutoLabel, pc.Note } do
			T.truthy(label.TextSize * 1.25 >= 18, label.Name .. ": 18 px at 1080p")
		end
		T.truthy(CapsuleView.TagMin * 1.25 >= 18 and CapsuleView.TagMin * scale >= 9.9, "the names never smaller")
		-- the key: G on a keyboard, a glyph on a gamepad, none on touch; green while on
		CapsuleView.setAuto(pc, true, false, "G", nil)
		T.truthy(pc.AutoKey.Visible and pc.AutoKeyText.Text == "G")
		CapsuleView.setAuto(pc, true, true, "", "rbxasset://textures/ui/Controls/xboxB.png")
		T.truthy(pc.AutoGlyph.Visible and not pc.AutoKeyText.Visible)
		T.eq(pc.Auto.BackgroundColor3, BrightTheme.Paints.Green.Bottom)
		CapsuleView.setAuto(pc, false, false, "", nil)
		T.falsy(pc.AutoHolder.Visible)
		-- the clean look: no headline words, rarity pills, NEW tags, "3 EGGS" titles, SKIP button or hints
		for _, gui in { pc.Gui, pc.Controls } do
			for _, d in gui:GetDescendants() do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					local text = string.upper(d.Text)
					for _, word in { "SKIP", "NEW", "EGGS", "LEGENDARY", "MYTHIC", "EPIC", "CLICK", "SPACE" } do
						T.falsy(string.find(text, word, 1, true), `{d.Name}: no "{word}"`)
					end
				end
			end
		end
		-- nothing golden (owner 2026-10-30: no golden golems)
		T.eq(CapsuleView.setGolden, nil)
		for _, tag in pc.Tags do
			T.eq(tag.Frame:FindFirstChild("Golden"), nil)
		end
		-- the world shows through: nothing dims it; the light UI never re-skins the opening
		T.eq(pc.Stage.BackgroundTransparency, 1)
		T.eq(pc.Flash.BackgroundTransparency, 1, "no flash at rest")
		T.truthy(pc.Gui.IgnoreGuiInset, "the whole screen")
		T.truthy(pc.Gui:GetAttribute("PopSkin") and pc.Controls:GetAttribute("PopSkin"))
	end)

	T.test("EggOpening: the controller (blur, the HUD away, Reduce motion's calm, Auto fast, a phone's fewer cracks)", function()
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local code = string.gsub(source, "%-%-[^\n]*", "")
		T.truthy(string.find(code, 'Instance.new("BlurEffect")', 1, true), "the world softly blurred")
		T.falsy(string.find(code, "Dim", 1, true), "nothing dims it")
		T.truthy(string.find(code, "hideHud(true)", 1, true) and string.find(code, "hideHud(false)", 1, true), "the HUD away and back")
		T.truthy(string.find(code, "Reduced = Motion.reduced()", 1, true), "Reduce motion: the calm version")
		T.truthy(string.find(code, "Fast = autoOn", 1, true), "Auto: the fast one")
		T.truthy(
			string.find(code, "if run.BestOrder >= 5 and not reduced then", 1, true),
			"the camera nudge only for a Legendary / Mythic, never calm"
		)
		T.truthy(string.find(code, "if phone and n > 3 then 2 else 3", 1, true), "a phone opening many: two crack steps")
		T.truthy(string.find(code, 'string.sub(gui.Name, 1, 10) ~= "TerraForge"', 1, true), "only our own guis step away")
		-- (the window keys sunk under it, L3 / R3 and T / B among them: tests/EggPanel.spec's chain spec;
		-- InteractController's held pickup hint: its own spec there)
	end)

	T.test("EggOpening: a seventh Rarity (the secret ores' Secret) never reaches the egg screens or the stall", function()
		local beforeRarities = #CapsuleConfig.rarities()
		local beforeOdds = CapsuleConfig.odds("Crystal", false)
		local beforeLines = EggPanel.lines("Crystal", false, {})
		local beforeView = CapsuleView.oddsLines("Crystal", false)
		local Stall = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Capsules")
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local secret = {
			Id = "Secret",
			Name = "Secret",
			Order = 7,
			Color = Color3.fromRGB(20, 16, 30),
			DarkColor = Color3.fromRGB(8, 6, 12),
			RespawnTime = 300,
			BonusChunkChance = 0,
			DirtThickness = 2,
			FragileSpots = 4,
			Reveal = 3,
		}
		-- the stall's odds board: its row labels and its RarityChips
		local function stallRows(): (number, number, { string })
			local stall = Instance.new("Model")
			Stall.build(stall, Rng.new("Lobby/Districts/capsules"))
			local rows, chips, names = 0, 0, {}
			for _, d in stall:GetDescendants() do
				if d.Name == "RarityChip" then
					chips += 1
				elseif d:IsA("TextLabel") and string.match(d.Name, "^Row%d+$") then
					rows += 1
					table.insert(names, d.Text)
				end
			end
			return rows, chips, names
		end
		local hadSecret = Rarity.ById.Secret
		-- main's shape (the secret ores' Secret in ById only, Order 7), then the worst case: in the List too
		for _, inList in { false, true } do
			local case = if inList then "Secret in the List too" else "Secret in ById only (main)"
			if inList then
				table.insert(Rarity.List, secret)
			end
			Rarity.ById.Secret = if inList then secret else (hadSecret or secret)
			local ok, err = pcall(function()
				T.eq(beforeRarities, 6, "the golems' six")
				T.eq(#CapsuleConfig.rarities(), 6, case .. ": still six")
				-- the client's board: six rows
				local board = Instance.new("Frame")
				CapsuleView.fillBoard(board, "Crystal", false)
				local rows = 0
				for _, child in board:GetChildren() do
					if string.match(child.Name, "^Row%d+$") then
						rows += 1
					end
				end
				T.eq(rows, 6, case .. ": the board's six rows")
				-- the stall's own board (Districts/Capsules): six rows, six chips, never "Secret"
				local stallRowCount, chips, names = stallRows()
				T.eq(stallRowCount, 6, case .. ": the stall's six rows")
				T.eq(chips, 6, case .. ": the stall's six chips")
				T.falsy(table.find(names, "Secret"), case .. ": no Secret row")
				-- the odds, the egg panel's cards and the window's rows: unchanged
				local odds = CapsuleConfig.odds("Crystal", false)
				T.eq(#odds, #beforeOdds)
				for i, line in odds do
					T.eq(line.Golem, beforeOdds[i].Golem)
					T.eq(line.Chance, beforeOdds[i].Chance)
				end
				local lines = EggPanel.lines("Crystal", false, {})
				T.eq(#lines, #beforeLines, case .. ": the panel's cards")
				local view = CapsuleView.oddsLines("Crystal", false)
				T.eq(#view, #beforeView, case .. ": the window's odds rows")
				local layout = EggPanel.layout(#lines, false)
				T.eq(layout.Count, EggPanel.layout(#beforeLines, false).Count, case .. ": the panel's layout")
			end)
			local at = table.find(Rarity.List, secret)
			if at then
				table.remove(Rarity.List, at)
			end
			Rarity.ById.Secret = hadSecret
			if not ok then
				error(err, 0)
			end
		end
	end)
end
