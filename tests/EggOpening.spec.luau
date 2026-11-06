-- The egg opening (owner 2026-10-29: the clicker-sim video, "open them exactly like there, this
-- clean, glowing by rarity"; docs/plans/CLICKER_VIDEO_2026-10-29.md section 1; V2 2026-10-30:
-- docs/plans/EGG_OPENING_V2.md): the timings (V2: Open 3 of Commons ~4.6 s, Auto's ~2 s, Reduce
-- motion's calm one), the skips that never hide a
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
			Auto: boolean?, -- the Auto button shown (true) or hidden (false) before the run lays itself out
		}?
	): (any, any, { number })
		local o2 = opts or {}
		local o = CapsuleView.buildOpening(o2.Phone == true)
		CapsuleView.layoutOpening(o, o2.Phone == true, o2.W or 1280, o2.H or 720, { Touch = o2.Phone == true, Inset = 36 })
		if o2.Auto ~= nil then
			CapsuleView.setAuto(o, o2.Auto, false, "", nil)
		end
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

	T.test("EggOpening: the timings (V2: Open 3 of Commons about 4.6 s, Auto about 2 s, the rarer's Tier, Reduce motion calm)", function()
		for order = 1, 6 do
			for _, count in { 1, 3, 10 } do
				for _, mode in { "normal", "fast", "calm" } do
					local tl = HatchFx.timeline(order, count, mode == "fast", mode == "calm")
					local label = `order {order} x{count} {mode}`
					-- (V2) the entrance, the float, then the charge: every egg is in before it floats, it floats before it charges
					T.truthy(tl.Float >= (count - 1) * tl.Stagger + tl.Times.Pop - 1e-9, label .. ": every egg in before the float")
					T.truthy(tl.Charge > tl.Float and tl.Charge <= tl.Steps[1], label .. ": the float, then the charge, then the cracks")
					T.eq(tl.Tier, HatchFx.Tiers[order], label .. ": the best rarity's Tier")
					T.eq(tl.Banner < math.huge, HatchFx.Tiers[order].Banner ~= nil, label .. ": a banner only for a Tier with one")
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
		-- (V2, the owner's brief 2026-10-30: the entrance to about 0.6 s, the float to about 1.5 s, the charge
		-- to about 3 s, the burst, the reveal; a Common never unnecessarily slow)
		local open3 = HatchFx.timeline(1, 3, false, false)
		T.truthy(open3.Total >= 4.3 and open3.Total <= 4.9, `Open 3 of Commons about 4.6 s: {open3.Total}`)
		T.truthy(open3.Float >= 0.5 and open3.Float <= 0.8, `the entrance ends about 0.6 s: {open3.Float}`)
		T.truthy(open3.Charge >= 1.0 and open3.Charge <= 1.6, `the charge starts about 1.5 s: {open3.Charge}`)
		T.truthy(open3.Burst >= 2.5 and open3.Burst <= 3.2, `the burst about 3 s: {open3.Burst}`)
		local epic = HatchFx.timeline(4, 3, false, false)
		T.truthy(epic.Total - open3.Total <= 0.3 + 1e-9, "an Epic only a little longer (its hold)")
		local fast = HatchFx.timeline(4, 3, true, false)
		T.truthy(fast.Total >= 1.7 and fast.Total <= 2.3, `Auto about 2 s: {fast.Total}`)
		local fastCommon = HatchFx.timeline(1, 3, true, false)
		T.truthy(fastCommon.Total <= fast.Total, "Auto: a Common never slower than an Epic")
		-- a Legendary / Mythic: the suspense, the slow-motion pop and a longer hold on top (the banner is read)
		for order = 5, 6 do
			local tier = HatchFx.Tiers[order]
			local tl = HatchFx.timeline(order, 3, false, false)
			local extra = tier.Suspense + ((tier.GolemPop or open3.Times.GolemPop) - open3.Times.GolemPop) + tier.Hold
			T.near(tl.Total - open3.Total, extra, 1e-9, `order {order}: its Tier on top`)
			T.truthy(tl.GolemPop > open3.GolemPop, `order {order}: a slow-motion reveal`)
			T.truthy(tl.Total <= 7.5, `order {order}: a cinematic, never a wait ({tl.Total} s)`)
			T.near(
				HatchFx.timeline(order, 3, true, false).Total - HatchFx.timeline(1, 3, true, false).Total,
				tier.SuspenseFast + tier.HoldFast,
				1e-9
			)
			local calm = HatchFx.timeline(order, 3, false, true)
			T.eq(calm.Suspense, 0, "Reduce motion: no suspense")
			T.eq(calm.GolemPop, calm.Times.GolemPop, "Reduce motion: no slow motion")
		end
		-- the Tiers grow with the rarity: the flash, the aura, the pulses, never smaller for the rarer
		for order = 2, 6 do
			local a, b = HatchFx.Tiers[order - 1], HatchFx.Tiers[order]
			T.truthy(b.Flash >= a.Flash and b.Aura >= a.Aura and b.Pulses >= a.Pulses, `Tier {order} at least Tier {order - 1}`)
			T.truthy(b.Flash <= HatchFx.FlashPeak, "never over the flash's cap")
		end
		T.eq(HatchFx.Tiers[5].Banner, "LEGENDARY!")
		T.eq(HatchFx.Tiers[6].Banner, "MYTHIC!")
		T.truthy(HatchFx.Tiers[5].Rays and HatchFx.Tiers[6].Rays and not HatchFx.Tiers[4].Rays, "golden / rainbow rays from Legendary")
		T.truthy(HatchFx.Tiers[6].Light > 0 and HatchFx.Tiers[5].Light == 0, "only a Mythic lifts the stage's light")
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
		-- (and with marks under the top row's names: the rows part downward only, the top centre stays free)
		local markCases: { any } = {
			false,
			{ Top = 0.13, Low = 0.15, Floor = 0.95 }, -- PC-like
			{ Top = 0.16, Low = 0.19, Floor = 0.93 }, -- a phone with a home indicator
		}
		for _, aspect in { 4 / 3, 16 / 9, 2.16, 844 / 390 } do
			for _, count in { 1, 3, 10 } do
				for _, special in { false, true } do
					for _, marks in markCases do
						local slot = if special then HatchFx.centreSlot(count) else nil
						local l = HatchFx.layout(count, aspect, slot, if marks then marks else nil)
						local label = `x{count} at {math.floor(aspect * 100) / 100}{if special then " special" else ""}{if marks
							then " marked"
							else ""}`
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
						if marks and count == 10 then
							local plain = HatchFx.layout(count, aspect, slot)
							T.eq(l.Slots[1].Egg.Y, plain.Slots[1].Egg.Y, label .. ": the top row stays")
							T.truthy(l.Slots[6].Egg.Y >= plain.Slots[6].Egg.Y, label .. ": the second row only moves down")
							-- the second row's golem heads under the top row's tags
							local feet = 0
							for i = 1, 5 do
								feet = math.max(feet, l.Slots[i].Golem.Y + l.Slots[i].GolemH / 2)
							end
							local head = l.Slots[6].Golem.Y - l.Slots[6].GolemH / 2
							T.truthy(feet + marks.Top <= head + 1e-6, label .. ": no top-row mark over a second-row head")
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

	T.test("EggOpening: the eggs rise in, float, pulse and shake with the charge, turn into their colour, burst", function()
		for _, order in { 1, 5 } do
			for _, fast in { false, true } do
				local tl = HatchFx.timeline(order, 3, fast, false)
				local maxRoll, maxScale, maxYaw = 0, 0, 0
				local floatDrops: { number } = {}
				for i = 0, 400 do
					local t = tl.Burst * i / 400
					for slot = 1, 3 do
						local pose = HatchFx.eggPose(t, tl, slot, slot == 2)
						if pose.Shown then
							maxRoll = math.max(maxRoll, math.abs(pose.Roll))
							maxScale = math.max(maxScale, pose.Scale)
							T.truthy(pose.Scale >= 0.25 and pose.Scale <= 1.4, "in bounds")
							T.truthy(pose.Drop >= -0.05 and pose.Drop <= HatchFx.Rise + 1e-9, "it rises from below, bobs a little")
							T.truthy(pose.Charge >= 0 and pose.Charge <= 1, "the charge 0..1")
							if t > tl.Float + 0.3 and t < tl.Charge and slot == 1 then
								table.insert(floatDrops, pose.Drop)
							end
							if t >= tl.Float then
								maxYaw = math.max(maxYaw, math.abs(pose.Yaw))
							end
						end
					end
				end
				-- (V2: the video's +-12 degree wobble became the float and the charge's growing shake)
				T.truthy(maxRoll >= math.rad(3) and maxRoll <= math.rad(20), `a real shake, never wild ({math.deg(maxRoll)} degrees)`)
				T.truthy(maxScale > 1.05, "it pulses")
				T.truthy(maxYaw > 0.05 and maxYaw <= HatchFx.FloatTurn + 1e-6, `a slow turn while it floats ({maxYaw})`)
				if not fast then
					local low, high = math.huge, -math.huge
					for _, d in floatDrops do
						low, high = math.min(low, d), math.max(high, d)
					end
					T.truthy(high - low > HatchFx.Bob * 0.5, "it bobs while it floats")
				end
				local first = HatchFx.eggPose(0.01, tl, 1, false)
				T.truthy(first.Drop > HatchFx.Rise * 0.8 and first.Scale < 0.5, "it starts small, below its place")
				T.truthy(HatchFx.eggPose(tl.Charge - 0.01, tl, 1, false).Charge == 0, "no charge while it floats")
				T.truthy(HatchFx.eggPose(tl.Silhouette - 0.01, tl, 1, false).Charge > 0.95, "fully charged at the silhouette")
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

	-- (V2) a golem of each rarity (the roster's first)
	local function kindOf(rarityId: string): string
		for _, g in GolemConfig.List do
			if g.Rarity == rarityId then
				return g.Id
			end
		end
		error("no golem of " .. rarityId)
	end

	T.test(
		"EggOpening V2: the platforms, orbits, motes and auras: posed in bounds, only while they belong, calm with Reduce motion",
		function()
			for _, count in { 1, 3, 10 } do
				for _, phone in { false, true } do
					local kinds = {}
					for i = 1, count do
						kinds[i] = kindOf(if i == 1 then "Rare" else "Common")
					end
					local o, run = runOf("Stone", kinds, { Phone = phone })
					local tl = run.Timeline
					local label = `x{count} {if phone then "phone" else "PC"}`
					T.truthy(run.MotesPer * count <= #o.Motes, label .. ": the motes' pool is enough")
					T.eq(run.OrbitsPer, HatchFx.OrbitCount, label .. ": orbits per egg (the full show on phones too)")
					local sawOrbit, sawMote, sawPlatform, sawAura = false, false, false, false
					local t = 0
					while t <= tl.Total do
						HatchStage.pose(run, t)
						for slot = 1, CapsuleView.StageTags do
							local platform = o.Platforms[slot]
							if platform.Visible then
								sawPlatform = true
								T.truthy(
									slot <= count and t < tl.Burst + 0.4,
									label .. ": a platform only under an egg, gone after the burst"
								)
							end
							for j, ring in o.Orbits[slot] do
								if ring.Visible then
									sawOrbit = true
									T.truthy(slot <= count and j <= run.OrbitsPer, label .. ": orbits only round the eggs")
									T.truthy(
										t >= tl.Charge and t < tl.Burst + 0.35,
										label .. ": orbits only while charging (and flying apart)"
									)
								end
							end
							if o.Auras[slot].Visible then
								sawAura = true
								T.truthy(slot <= count and t >= tl.Charge and t < tl.Total, label .. ": an aura only while it belongs")
							end
						end
						for _, mote in o.Motes do
							if mote.Visible then
								sawMote = true
								T.truthy(t >= tl.Float and t < tl.Burst, label .. ": motes from the float to the burst")
								T.truthy(
									mote.BackgroundTransparency >= 0 and mote.BackgroundTransparency <= 1,
									label .. ": a mote's glow in bounds"
								)
							end
						end
						t += 1 / 30
					end
					T.truthy(sawOrbit and sawMote and sawPlatform and sawAura, label .. ": every layer shows")
					-- the end: everything hidden (the controller's clear between openings)
					HatchStage.clear(o, HatchStage.golems(run))
					for slot = 1, CapsuleView.StageTags do
						T.falsy(o.Platforms[slot].Visible or o.Auras[slot].Visible, label .. ": cleared")
						for _, ring in o.Orbits[slot] do
							T.falsy(ring.Visible, label .. ": orbits cleared")
						end
					end
					for _, mote in o.Motes do
						T.falsy(mote.Visible, label .. ": motes cleared")
					end
				end
			end
			-- Reduce motion: no orbit, no mote, no pulse; the platform and the aura fade, still
			local o, run = runOf("Stone", { kindOf("Legendary"), kindOf("Common"), kindOf("Common") }, { Reduced = true })
			local tl = run.Timeline
			local t = 0
			while t <= tl.Total do
				HatchStage.pose(run, t)
				for slot = 1, 3 do
					for _, ring in o.Orbits[slot] do
						T.falsy(ring.Visible, "Reduce motion: no orbit")
					end
				end
				for _, mote in o.Motes do
					T.falsy(mote.Visible, "Reduce motion: no mote")
				end
				T.truthy(HatchFx.pulseU(t, tl, 1) < 0, "Reduce motion: no pulse")
				t += 1 / 30
			end
		end
	)

	T.test(
		"EggOpening V2: each rarity's show (rays, pulses, confetti, flash, LEGENDARY! / MYTHIC!, Mythic's light) and the rarity pills",
		function()
			for _, rarityId in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
				local best = kindOf(rarityId)
				local kinds = { kindOf("Common"), best, kindOf("Common") }
				local o, run, claims = runOf("Stone", kinds)
				local tl = run.Timeline
				local tier = HatchFx.Tiers[Rarity.ById[rarityId].Order]
				T.eq(run.Tier, tier, rarityId .. ": its Tier")
				T.eq(run.Kinds[run.BestSlot], best, rarityId .. ": the best slot holds the best golem")
				local seen: { string } = {}
				local bannerShown, maxConfetti, sawPulse, sawBadges, mythicLight = false, 0, false, 0, false
				local t = 0
				while t <= tl.Total do
					for _, event in HatchStage.pose(run, t) do
						table.insert(seen, event)
					end
					if o.Banner.Frame.Visible and o.Banner.Word.TextTransparency < 1 then
						bannerShown = true
						T.eq(o.Banner.Word.Text, tier.Banner, rarityId .. ": its word")
						T.truthy(o.Banner.Frame.Position.Y.Offset < 0.2 * o.Size.Y, rarityId .. ": in the band over the golems")
					end
					local shown = 0
					for _, piece in o.Confetti do
						if piece.Visible then
							shown += 1
						end
					end
					maxConfetti = math.max(maxConfetti, shown)
					for _, ring in o.Rings[run.BestSlot] do
						if ring.Visible and t >= tl.Reveal then
							sawPulse = true
						end
					end
					if t >= tl.Reveal + tl.GolemPop and t < tl.Fly then
						local badges = 0
						for slot, badge in o.Badges do
							if badge.Frame.Visible and badge.Rarity.TextTransparency < 1 then
								badges += 1
								T.eq(
									badge.Rarity.Text,
									string.upper(Rarity.ById[run.Rarities[slot]].Name),
									rarityId .. ": the pill says its rarity"
								)
								T.truthy(string.find(badge.Bonus.Text, "%", 1, true) ~= nil, rarityId .. ": and its bonus")
								T.truthy(
									badge.Frame.Position.Y.Offset < o.Tags[slot].Frame.Position.Y.Offset,
									rarityId .. ": over its head, the name under its feet"
								)
							end
						end
						sawBadges = math.max(sawBadges, badges)
						if o.Stage.Ambient ~= CapsuleView.StageAmbient then
							mythicLight = true
						end
					end
					t += 1 / 30
				end
				for _, event in HatchStage.pose(run, tl.Total) do
					table.insert(seen, event)
				end
				T.eq(bannerShown, tier.Banner ~= nil, rarityId .. ": a banner only from Legendary")
				T.eq(table.find(seen, "Banner") ~= nil, tier.Banner ~= nil, rarityId .. ": its Banner event")
				T.eq(maxConfetti, tier.Confetti, rarityId .. ": its Tier's confetti")
				T.eq(sawPulse, tier.Pulses > 0, rarityId .. ": its energy pulses")
				T.eq(mythicLight, tier.Light > 0, rarityId .. ": only a Mythic lifts the stage's light")
				-- every golem a pill but the best one when the banner says its rarity (its bonus is the banner's sub line)
				T.eq(sawBadges, if tier.Banner then 2 else 3, rarityId .. ": the rarity pills")
				if tier.Banner then
					T.truthy(
						o.Banner.Sub.Visible and string.find(o.Banner.Sub.Text, "%", 1, true) ~= nil,
						rarityId .. ": the best golem's bonus under the word"
					)
				end
				T.eq(claims[1], 1, rarityId .. ": ONE flash")
				T.truthy(HatchFx.flashPeakOf(tl) <= HatchFx.FlashPeak, rarityId .. ": never over the cap")
				HatchStage.clear(o, HatchStage.golems(run))
				T.falsy(o.Banner.Frame.Visible, rarityId .. ": the banner cleared")
				T.eq(o.Stage.Ambient, CapsuleView.StageAmbient, rarityId .. ": the stage's own light back")
				for _, badge in o.Badges do
					T.falsy(badge.Frame.Visible, rarityId .. ": the pills cleared")
				end
			end
			-- no pills on an Open 10 (two rows: the names and "1 in N" say enough); a bonus's words
			local kinds = {}
			for i = 1, 10 do
				kinds[i] = kindOf("Common")
			end
			local o, run = runOf("Stone", kinds)
			HatchStage.pose(run, run.Timeline.Reveal + run.Timeline.GolemPop + 0.2)
			for _, badge in o.Badges do
				T.falsy(badge.Frame.Visible, "Open 10: no pills")
			end
			T.eq(HatchFx.bonusText("Income", 0.03, GolemConfig.BonusTypes), "+3% Income")
			T.eq(HatchFx.bonusText("Luck", 0.125, GolemConfig.BonusTypes), "+12.5% Ore luck")
			T.eq(HatchFx.bonusText("Nope", 0.1, GolemConfig.BonusTypes), nil)
			T.eq(HatchFx.bonusText("Income", 0, GolemConfig.BonusTypes), nil)
		end
	)

	T.test("EggOpening V2: LEGENDARY! clears the neighbours' pills, fitted ONCE, its words never under TagMin", function()
		-- (design units: PC; 1361 x 629, the reference phone; 916 x 516 and 1310 x 605, 568 x 320 and
		-- 812 x 375 pt phones at the phone scale; an iPad-like 4:3; PC under the chain's "2 / 5")
		local shrunk = false
		for _, screen in
			{
				{ 1280, 720, false },
				{ 1361, 629, true },
				{ 916, 516, true },
				{ 1310, 605, true },
				{ 1688, 780, true },
				{ 1100, 825, false },
				{ 1280, 720, false, true },
			}
		do
			for _, rarityId in { "Legendary", "Mythic" } do
				local o, run = runOf(
					"Crystal",
					{ kindOf("Uncommon"), kindOf(rarityId), kindOf("Rare") },
					{ W = screen[1], H = screen[2], Phone = screen[3] }
				)
				if screen[4] then
					CapsuleView.setChain(o, 2, 5)
				end
				local tl = run.Timeline
				local label = `{rarityId} {screen[1]}x{screen[2]}{if screen[4] then " chain" else ""}`
				local t = 0
				local words: { number } = {}
				while t < tl.Fly - 0.05 do
					t = math.min(tl.Fly - 0.05, t + 1 / 60)
					HatchStage.pose(run, t)
					local b = o.Banner
					if b.Frame.Visible then
						table.insert(words, b.Word.TextSize)
						-- (once settled: the slam over; the words never under the floor)
						if t >= tl.Banner + 0.35 then
							T.near(b.Scale.Scale, 1, 1e-6, label .. ": settled, the slam alone scales")
							T.truthy(b.Word.TextSize * b.Scale.Scale >= CapsuleView.TagMin, label .. ": the word at TagMin or more")
							if b.Sub.Visible then
								T.truthy(b.Sub.TextSize * b.Scale.Scale >= CapsuleView.TagMin, label .. ": the sub line at TagMin or more")
							end
						end
					end
				end
				-- fitted once: the word's size never changes frame to frame (no jumps from the bobbing pills)
				for i = 2, #words do
					T.eq(words[i], words[i - 1], label .. ": the word's size fixed for the run")
				end
				local b = o.Banner
				if b.Word.TextSize < b.WordSize then
					shrunk = true
				end
				T.truthy(b.Frame.Visible and b.Word.TextSize >= math.floor(b.WordSize * 0.6), label .. ": the banner shows, never tiny")
				local half = CapsuleView.bannerWidth(o) * b.Scale.Scale / 2
				local mid = b.Frame.Position.X.Offset
				local top = b.Frame.Position.Y.Offset - b.Frame.Size.Y.Offset * b.Scale.Scale / 2
				local bottom = top + b.Frame.Size.Y.Offset * b.Scale.Scale
				for _, badge in o.Badges do
					if badge.Frame.Visible then
						local bx, by = badge.Frame.Position.X.Offset, badge.Frame.Position.Y.Offset
						local bw, bh = badge.Frame.Size.X.Offset, badge.Frame.Size.Y.Offset
						if by - bh < bottom and by > top then
							T.truthy(math.abs(bx - mid) - bw / 2 >= half - 1, label .. ": the word clears a pill beside it")
						end
					end
				end
			end
		end
		T.truthy(shrunk, "a wide phone's banner really shrinks to clear the pills")
	end)

	T.test("EggOpening V2: the rarity pills step aside for AUTO like the names (phones, Open 3 and 5)", function()
		for _, screen in { { 916, 516 }, { 1310, 605 }, { 1361, 629 } } do
			for _, count in { 3, 5 } do
				local kinds = {}
				for i = 1, count do
					kinds[i] = kindOf(if i % 2 == 0 then "Rare" else "Common")
				end
				local o, run = runOf("Stone", kinds, { W = screen[1], H = screen[2], Phone = true, Auto = true })
				local tl = run.Timeline
				HatchStage.pose(run, tl.Reveal + tl.GolemPop + 0.3)
				local label = `x{count} {screen[1]}x{screen[2]}`
				for _, badge in o.Badges do
					if badge.Frame.Visible then
						local x, y = badge.Frame.Position.X.Offset, badge.Frame.Position.Y.Offset
						local w, h = badge.Frame.Size.X.Offset, badge.Frame.Size.Y.Offset
						for _, keep in o.AutoKeep do
							local over = x - w / 2 < keep.Max.X and x + w / 2 > keep.Min.X and y - h < keep.Max.Y and y > keep.Min.Y
							T.falsy(over, label .. ": no pill under the Auto button")
						end
					end
				end
			end
		end
	end)

	T.test("EggOpening V2: an auto-deleted best golem is never celebrated (no banner, no pulses, no tint)", function()
		local legendary = kindOf("Legendary")
		local o, run = runOf("Crystal", { kindOf("Common"), legendary, kindOf("Uncommon") }, { Deleted = { [2] = true } })
		local tl = run.Timeline
		T.eq(run.ShowRarity, "Uncommon", "the show follows the best golem kept")
		T.eq(run.Tier, HatchFx.Tiers[2])
		T.truthy(run.Kinds[run.BestSlot] ~= legendary, "its pulses are not the deleted golem's")
		T.eq(run.ShowOrder, 2, "the tint follows the kept Uncommon: none (CapsuleController.MoodFrom is 4, Epic)")
		local seen: { string } = {}
		local t = 0
		while t <= tl.Total do
			for _, event in HatchStage.pose(run, t) do
				table.insert(seen, event)
			end
			T.falsy(o.Banner.Frame.Visible, "no LEGENDARY! for a deleted golem")
			t += 1 / 30
		end
		T.falsy(table.find(seen, "Banner"), "no Banner event (no chime)")
		-- all deleted: the calmest show
		local _, none = runOf("Crystal", { legendary }, { Deleted = { [1] = true } })
		T.eq(none.Tier, HatchFx.Tiers[1])
		T.eq(none.BestSlot, 0, "no pulses")
	end)

	T.test("EggOpening V2: Reduce motion: the new layers stay still (no rise, turn, grow, slam, breathe or turning rainbow)", function()
		for _, order in { 1, 5, 6 } do
			local tl = HatchFx.timeline(order, 3, false, true)
			local t = 0
			local aura: number? = nil
			while t <= tl.Total do
				for slot = 1, 3 do
					local pose = HatchFx.eggPose(t, tl, slot, slot == 2)
					T.eq(pose.Drop, 0, "no rise or bob")
					T.eq(pose.Yaw, 0, "no turn")
					local _, k = HatchFx.platformAt(t, tl, slot)
					T.eq(k, 1, "the platform never grows or flares")
				end
				local scale, alpha = HatchFx.bannerAt(t, tl)
				if alpha < 1 then
					T.eq(scale, 1, "the banner fades in at its size")
				end
				if t >= tl.Reveal + 0.25 and t < tl.Fly then
					local a = HatchFx.auraAt(t, tl, 1)
					if aura then
						T.near(a, aura, 1e-9, "the aura never breathes")
					end
					aura = a
				end
				t += 1 / 30
			end
		end
		-- the Mythic banner's rainbow stays put
		local o, run = runOf("Crystal", { kindOf("Mythic") }, { Reduced = true })
		local tl = run.Timeline
		local rotation: number? = nil
		local t = tl.Banner
		while t < tl.Fly do
			HatchStage.pose(run, t)
			if rotation then
				T.eq(o.Banner.Paint.Rotation, rotation, "the rainbow never turns")
			end
			rotation = o.Banner.Paint.Rotation
			t += 1 / 30
		end
	end)

	T.test("EggOpening V2: MYTHIC! keeps the full rainbow: set once, never turned; a Legendary after it gets its gold", function()
		local o, run = runOf("Crystal", { kindOf("Mythic") })
		local tl = run.Timeline
		local color = o.Banner.Paint.Color
		local t = tl.Banner
		while t < tl.Fly do
			HatchStage.pose(run, t)
			T.eq(o.Banner.Paint.Rotation, 90, "never turned: a turned gradient shows a slice of one hue")
			T.eq(o.Banner.Paint.Color, color, "the same sequence: never rebuilt")
			t += 1 / 60
		end
		T.eq(#color.Keypoints >= 6, true, "the whole rainbow")
		CapsuleView.setBanner(o, "LEGENDARY!", nil, "Legendary")
		T.eq(o.Banner.Paint.Rotation, 90)
		T.truthy(o.Banner.Paint.Color ~= color, "a Legendary's gold replaces it")
	end)

	T.test("EggOpening V2: the pills never flicker: form and x decided once a run (4:3 tablets, touch, Auto), no AUTO overlap", function()
		for _, screen in { { 1100, 825 }, { 916, 516 }, { 1361, 629 } } do
			for _, count in { 3, 5 } do
				local kinds = {}
				for i = 1, count do
					kinds[i] = kindOf(if i % 2 == 0 then "Rare" else "Common")
				end
				local o, run = runOf("Stone", kinds, { W = screen[1], H = screen[2], Phone = true, Auto = true })
				local tl = run.Timeline
				local label = `x{count} {screen[1]}x{screen[2]}`
				local seen: { [number]: { Text: string, X: number } } = {}
				local t = tl.Reveal
				while t < tl.Fly do
					HatchStage.pose(run, t)
					for slot, badge in o.Badges do
						if badge.Frame.Visible then
							local now = { Text = badge.Bonus.Text, X = badge.Frame.Position.X.Offset, Size = badge.Frame.Size.X.Offset }
							local before = seen[slot] :: any
							if before then
								T.eq(now.Text, before.Text, label .. ": the form never swaps")
								T.eq(now.X, before.X, label .. ": the x never jumps")
								T.eq(now.Size, before.Size, label .. ": the width never changes")
							end
							seen[slot] = now :: any
							local x, y = now.X, badge.Frame.Position.Y.Offset
							local w, h = now.Size, badge.Frame.Size.Y.Offset
							for _, keep in o.AutoKeep do
								local over = x - w / 2 < keep.Max.X and x + w / 2 > keep.Min.X and y - h < keep.Max.Y and y > keep.Min.Y
								T.falsy(over, label .. ": no pill under the Auto button")
							end
						end
					end
					t += 1 / 60
				end
				-- the Auto button hides: decided again, the rarity and its bonus back where they fit
				CapsuleView.setAuto(o, false, false, "", nil)
				HatchStage.retag(run)
				HatchStage.pose(run, tl.Reveal + tl.GolemPop + 0.2)
				T.eq(next(run.BadgePlan) ~= nil, true, label .. ": planned again")
			end
		end
	end)

	T.test("EggOpening V2: the eggs rock smoothly (owner 2026-10-30: no stutter): sampled every ms, no jumps anywhere", function()
		for _, order in { 1, 4, 5, 6 } do
			for _, count in { 1, 3, 10 } do
				for _, fast in { false, true } do
					local tl = HatchFx.timeline(order, count, fast, false)
					local special = HatchFx.centreSlot(count)
					for slot = 1, count do
						local last: number? = nil
						local lastScale: number? = nil
						local t = tl.Float
						while t < tl.Burst do
							local pose = HatchFx.eggPose(t, tl, slot, order >= 5 and slot == special)
							if pose.Shown and last and lastScale then
								-- (review 2026-10-30: through the silhouette too, at most 0.5 degrees and 0.4 % a ms)
								T.truthy(
									math.abs(pose.Roll - last) <= math.rad(0.5),
									`order {order} x{count} slot {slot}: a smooth rock at {t}`
								)
								T.truthy(
									math.abs(pose.Scale / lastScale - 1) <= 0.004,
									`order {order} x{count} slot {slot}: a smooth size at {t}`
								)
							end
							last, lastScale = pose.Roll, pose.Scale
							t += 0.001
						end
					end
				end
			end
		end
		-- the rock grows with the charge; the special egg swells with the suspense
		for _, order in { 1, 5 } do
			local tl = HatchFx.timeline(order, 3, false, false)
			local function maxRoll(from: number, to: number): number
				local m = 0
				local t = from
				while t < to do
					m = math.max(m, math.abs(HatchFx.eggPose(t, tl, 1, false).Roll))
					t += 0.002
				end
				return m
			end
			local early = maxRoll(tl.Charge, tl.Charge + 0.3)
			local late = maxRoll(tl.Silhouette - 0.3, tl.Silhouette)
			T.truthy(late > 1.5 * early, `order {order}: the rock grows with the charge ({early} -> {late})`)
		end
		for _, order in { 5, 6 } do
			local tl = HatchFx.timeline(order, 3, false, false)
			T.truthy(HatchFx.eggPose(tl.Silhouette - 0.005, tl, 2, true).Scale >= 1.05, `order {order}: the special egg swells`)
		end
		-- the sway: slow waves, -1..1
		for i = 0, 600 do
			local v = HatchFx.sway(i / 100, HatchFx.SwayHz.Suspense, 1.3)
			T.truthy(math.abs(v) <= 1 + 1e-9, "the sway in -1..1")
		end
		for _, hz in HatchFx.SwayHz do
			T.truthy(hz <= 5, "a few times a second: never a buzz")
		end
	end)

	T.test("EggOpening V2: the show follows the RAREST golem, whatever a golem's score weighs", function()
		local had = GolemConfig.score
		local ok, err = pcall(function()
			-- (a score that puts bonuses above rarity, as a golem-stats change may: the opening must not follow it)
			GolemConfig.score = function(kind: string): number
				local golem = GolemConfig.ById[kind]
				return if golem then golem.Bonus.Value * 1000 - GolemConfig.order(kind) else -1
			end
			local legendary = kindOf("Legendary")
			local _, run = runOf("Crystal", { kindOf("Common"), legendary, kindOf("Uncommon") })
			T.eq(run.ShowRarity, "Legendary", "the Legendary's show")
			T.eq(run.Kinds[run.BestSlot], legendary, "its slot")
			T.eq(CapsuleView.best({ kindOf("Rare"), kindOf("Mythic"), kindOf("Epic") }), kindOf("Mythic"))
		end)
		GolemConfig.score = had
		if not ok then
			error(err, 0)
		end
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
		local kinds = { "CoalChomper", "PebbleGolem", "CopperTinker" }
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
		T.eq(table.concat(seen, ","), "Charge,Step1,Step2,Step3,Burst,Reveal,Fly,End", "in order, each once")
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
		T.eq(named["Coal Chomper"], "1 in 100")
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

	T.test("EggOpening: names step aside for the Auto button only while it shows, within their column, never under it", function()
		local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
		local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
		-- long names (the review's: "Amethyst Acolyte" lost its "A" under the bottom-left of an Open 10)
		local long = { "AmethystAcolyte", "MoonstoneOracle", "CelestialSovereign", "HeartstoneColossus", "EmberHatchling", "ScaleKnight" }
		-- a part of a tag (`x` its middle, `y` its top, `w` x `h`) as a box
		local function boxAt(x: number, y: number, w: number, h: number): any
			return { Min = Vector2.new(x - w / 2, y), Max = Vector2.new(x + w / 2, y + h) }
		end
		for _, screen in
			{
				{ 1280, 720, false, false },
				{ 1100, 825, false, false }, -- (4:3-ish: the review's notes and pills beside AUTO ON)
				{ 1100, 880, false, false },
				{ 1152, 720, false, false },
				{ 1536, 864, true, true }, -- (a TV: its compact layout, the ten-foot Auto)
			}
		do
			local W, H, compact, tv = screen[1], screen[2], screen[3], screen[4]
			for _, n in { 5, 10 } do
				for shift = 0, #long - 1 do
					local kinds = {}
					for i = 1, n do
						kinds[i] = long[(i - 1 + shift) % #long + 1]
					end
					-- (waiting notes and DELETED pills in turn: the first golem of each row carries one)
					local marked = { [6] = true, [1] = true }
					local marks = if shift % 2 == 0 then { Waiting = marked } else { Deleted = marked }
					for _, autoShown in { false, true } do
						local o, run = runOf(if n == 10 then "Crystal" else "Royal", kinds, marks)
						CapsuleView.layoutOpening(o, compact, W, H, { Inset = 29, TenFoot = tv })
						CapsuleView.setAuto(o, autoShown, true, "G", nil) -- ("AUTO ON": the wider label)
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
							local label = `{W}x{H} n {n}, Auto {if autoShown then "shown" else "hidden"}, slot {slot} ({tag.Name.Text})`
							-- (offsets are whole units)
							if not autoShown then
								T.near(x, under, 1, label .. ": under its golem")
							else
								T.truthy(x >= under - 1 and x - under <= pitch / 2 + 1, label .. ": within its own column")
							end
							T.truthy(tag.Name.TextSize >= CapsuleView.TagMin, label .. ": never under the text floor")
							T.eq(tag.Frame:GetAttribute("UnderAuto"), nil, label .. ": setTag found a form clear of the Auto button")
							-- what shows of it: the name as setTag measures it (a line at a time), its "1 in N",
							-- its waiting note or DELETED pill
							local widest, lines = 0, 0
							for line in string.gmatch(tag.Name.Text, "[^\n]+") do
								widest = math.max(widest, TechShopView.textWidth(line, tag.Name.TextSize))
								lines += 1
							end
							local y = tag.Frame.Position.Y.Offset
							local parts = {
								{ "name", boxAt(x, y, widest * 1.04 + 8, lines * (tag.Name.TextSize + 2) + 4) },
								{
									"1 in N",
									boxAt(
										x,
										y + tag.Chance.Position.Y.Offset,
										TechShopView.textWidth(tag.Chance.Text, tag.Chance.TextSize) + 8,
										tag.Chance.Size.Y.Offset
									),
								},
							}
							for _, mark in { tag.Waiting, tag.Deleted } do
								if mark.Visible then
									local part = boxAt(
										x + mark.Position.X.Offset,
										y + mark.Position.Y.Offset,
										mark.Size.X.Offset,
										mark.Size.Y.Offset
									)
									table.insert(parts, { if mark == tag.Waiting then "note" else "DELETED", part })
									table.insert(boxes, { Slot = slot, Box = part })
								end
							end
							if tag.Deleted.Visible then
								-- the pill: its trash mark and DELETED; beside the button the trash mark alone, in
								-- its middle (the word never spills out of the narrow pill)
								local narrow = tag.Deleted.Size.X.Offset == CapsuleView.DeletedNarrow
								T.truthy(narrow or tag.Deleted.Size.X.Offset == CapsuleView.DeletedWide, label .. ": one of its two forms")
								T.eq(tag.DeletedWord.Visible, not narrow, label .. ": DELETED only in the wide pill")
								local can = tag.DeletedCan
								if narrow then
									T.eq(can.AnchorPoint, Vector2.new(0.5, 0.5), label .. ": the trash mark centred")
									T.eq(can.Position, roblox.UDim2.fromScale(0.5, 0.5))
								else
									T.eq(can.AnchorPoint, Vector2.new(0, 0.5), label .. ": the trash mark left of the word")
								end
							end
							-- (all of it on the screen: nothing under its bottom, the stroke round a pill included)
							for _, part in parts do
								local rim = if part[1] == "note" or part[1] == "DELETED" then 2 else 0
								T.truthy(
									part[2].Max.Y + rim <= size.Y - o.SafeBottom,
									`{label}: its {part[1]} on the screen ({part[2].Max.Y + rim} of {size.Y - o.SafeBottom})`
								)
							end
							table.insert(boxes, { Slot = slot, Box = parts[1][2] })
							if autoShown then
								-- (the keep boxes carry a 4-unit margin round the button: a hair of it may touch, nothing more)
								for _, keep in o.AutoKeep do
									local inner = { Min = keep.Min + Vector2.new(1, 1), Max = keep.Max - Vector2.new(1, 1) }
									for _, part in parts do
										T.eq(EggPanel.overlap(part[2], inner), 0, `{label}: its {part[1]} never under the Auto button`)
									end
								end
							end
						end
						T.eq(o.Gui:GetAttribute("MarksOverrun"), nil, `{W}x{H} n {n}: the marks fit the screen`)
						-- no tag runs into a neighbour's (its name, its mark)
						for i = 1, #boxes do
							for j = i + 1, #boxes do
								local a, b = boxes[i].Box, boxes[j].Box
								if boxes[i].Slot ~= boxes[j].Slot then
									T.eq(EggPanel.overlap(a, b), 0, `{W}x{H} n {n}: slots {boxes[i].Slot} and {boxes[j].Slot} apart`)
								end
							end
						end
						HatchStage.pose(run, tl.Total)
						HatchStage.clear(o, HatchStage.golems(run))
					end
				end
			end
		end
	end)

	T.test("EggOpening: of one row, long names keep to their columns (the big middle one's on two lines), above the safe bottom", function()
		local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
		local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
		-- (its neighbours' names are as long: one and a half rooms ran its name into theirs)
		for _, screen in { { 844, 390, 0.62, 21 }, { 568, 320, 0.62, 0 }, { 1280, 720, 1, 0 } } do
			local scale = screen[3]
			local W, H, phone = screen[1] / scale, screen[2] / scale, scale < 1
			for _, n in { 2, 3, 5 } do
				for _, mark in { "none", "wait", "del" } do
					local kinds, marks = {}, {}
					for i = 1, n do
						kinds[i] = if i == 1 then "CelestialSovereign" else "HeartstoneColossus"
						marks[i] = true
					end
					local o, run = runOf("Royal", kinds, {
						Phone = phone,
						W = W,
						H = H,
						Waiting = if mark == "wait" then marks else nil,
						Deleted = if mark == "del" then marks else nil,
					})
					CapsuleView.layoutOpening(o, phone, W, H, { Touch = phone, Inset = 58 / scale, SafeBottom = screen[4] / scale })
					HatchStage.pose(run, run.Timeline.Reveal + HatchFx.namedAt(run.Timeline) + 0.05)
					local label = `{screen[1]}x{screen[2]} n {n}, {mark}`
					local special = run.Special
					T.truthy(special ~= nil and run.Kinds[special] == "CelestialSovereign", label .. ": the Mythic in the middle")
					local pitch = run.Layout.Spacing * run.Size.X * 0.96
					local boxes = {}
					for slot in run.Standing do
						local tag = o.Tags[slot]
						local widest, lines = 0, 0
						for line in string.gmatch(tag.Name.Text, "[^\n]+") do
							widest = math.max(widest, TechShopView.textWidth(line, tag.Name.TextSize))
							lines += 1
						end
						local w = widest * 1.04 + 8
						local x, y = tag.Frame.Position.X.Offset, tag.Frame.Position.Y.Offset
						boxes[slot] = {
							Min = Vector2.new(x - w / 2, y),
							Max = Vector2.new(x + w / 2, y + lines * (tag.Name.TextSize + 2) + 4),
						}
						T.truthy(y + tag.Frame.Size.Y.Offset <= run.Size.Y - o.SafeBottom, `{label}, slot {slot}: above the safe bottom`)
						if slot == special then
							T.truthy(w <= pitch + 1, label .. ": the middle one in its own column")
							T.eq(lines, 2, label .. ": the long name on two lines")
							T.truthy(tag.Name.TextSize >= CapsuleView.TagMin, label .. ": never under the text floor")
						end
					end
					-- (no name runs into another's: the middle one's nor its neighbours')
					for slot, box in boxes do
						for other, box2 in boxes do
							if other > slot then
								T.eq(EggPanel.overlap(box, box2), 0, `{label}: slots {slot} and {other} apart`)
							end
						end
					end
					HatchStage.pose(run, run.Timeline.Total)
					HatchStage.clear(o, HatchStage.golems(run))
				end
			end
		end
	end)

	T.test("EggOpening: second-row marks keep above a phone's home indicator; touch's Auto costs the golems nothing", function()
		-- a Robux Open 10 with a Legendary (the top row's middle), the second row's golems waiting or
		-- deleted (none in the top row: the rows still mind the safe bottom)
		local kinds = {
			"EmberImp",
			"CobaltDiver",
			"StormTitan",
			"GildedPorter",
			"RoseKnight",
			"SapphireSage",
			"DiamondDuke",
			"MoonstoneOracle",
			"EmberImp",
			"CobaltDiver",
		}
		local scale = 0.62
		-- (notched iPhones: their home indicator, 21 pt; the smallest phone has none)
		for _, phone in { { 812, 375, 21 }, { 844, 390, 21 }, { 568, 320, 0 } } do
			local W, H, safe = phone[1] / scale, phone[2] / scale, phone[3] / scale
			for _, mark in { "Waiting", "Deleted" } do
				local marked = { [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
				local heights = {}
				for _, autoShown in { false, true } do
					local o, run = runOf("Royal", kinds, {
						Phone = true,
						W = W,
						H = H,
						Waiting = if mark == "Waiting" then marked else nil,
						Deleted = if mark == "Deleted" then marked else nil,
						Auto = autoShown, -- (laid out with it from the start: the comparison below is real)
					})
					local label = `{phone[1]}x{phone[2]}, {mark}, Auto {if autoShown then "shown" else "hidden"}`
					T.truthy(run.Marked, label .. ": marks in the second row count too")
					T.eq(run.Special, 3, "(the Legendary in the top row's middle)")
					T.eq(o.AutoHolder.Visible, autoShown, "(laid out with Auto shown or hidden)")
					local before = run.Layout.Slots[6].Golem.Y
					-- (the safe frame settles after the opening began: the home indicator under it)
					CapsuleView.layoutOpening(o, true, W, H, { Touch = true, Inset = 58 / scale, SafeBottom = safe })
					HatchStage.pose(run, run.Timeline.Reveal + HatchFx.namedAt(run.Timeline) + 0.05)
					if safe > 0 then
						T.truthy(run.Layout.Slots[6].Golem.Y ~= before, label .. ": laid out again for it")
					end
					local floor = run.Size.Y - o.SafeBottom
					T.eq(o.Gui:GetAttribute("MarksOverrun"), nil, label .. ": the marks fit above the home indicator")
					for slot = 6, 10 do
						local tag = o.Tags[slot]
						local m = if mark == "Waiting" then tag.Waiting else tag.Deleted
						T.truthy(m.Visible, `{label}, slot {slot}: its mark`)
						-- (the pill's 2-unit rim drawn outside it)
						local bottom = tag.Frame.Position.Y.Offset + m.Position.Y.Offset + m.Size.Y.Offset + 2
						T.truthy(bottom <= floor, `{label}, slot {slot}: above the home indicator ({bottom} of {floor})`)
					end
					table.insert(heights, run.Layout.Slots[1].GolemH)
					HatchStage.pose(run, run.Timeline.Total)
					HatchStage.clear(o, HatchStage.golems(run))
				end
				-- (touch: the Auto button sits top left, no tag beside it: the golems keep their size)
				T.eq(heights[2], heights[1], `{phone[1]}x{phone[2]}, {mark}: Auto shown, the golems as big`)
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
					"JadeGardener",
					"AmethystAcolyte",
					"JadeGardener",
					"SapphireSage",
					"AmethystAcolyte",
					"DiamondDuke",
					"QuartzSprite",
					"SapphireSage",
					"JadeGardener",
				},
				{},
			},
			{ "Crystal", { "HeartstoneColossus" }, {} },
			{ "Stone", { "CoalChomper", "CobaltDiver", "CopperTinker" }, { Reduced = true } },
			{ "Stone", { "PebbleGolem", "CopperTinker", "CoalChomper" }, { Fast = true } },
			{ "Stone", { "PebbleGolem", "CopperTinker", "CoalChomper" }, { Phone = true, W = 1361, H = 629 } },
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
				T.eq(run.Kinds[3], "DiamondDuke")
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
