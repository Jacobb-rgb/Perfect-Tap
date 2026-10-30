--[[
	HatchStage: one egg opening posed frame by frame on CapsuleView's
	opening (the owner's clicker-sim video, 2026-10-29; the flow and the
	numbers are UI/HatchFx's). CapsuleController plays it (input, sounds,
	the camera nudge, the HUD and the blur are its); the previews call the
	very same pose(), so a picture shows exactly what the game draws.

	  run = HatchStage.new(args)       the eggs placed, the colours chosen
	  events = HatchStage.pose(run, t) everything at `t` seconds; returns
	                                   what happened since the last call:
	                                   "Charge" (the energy starts),
	                                   "Step1".."Step3" (a crack step),
	                                   "Burst", "Reveal", "Banner" (a
	                                   Legendary / Mythic's), "Fly", "End"
	  HatchStage.clear(refs)           every piece hidden, the golems freed,
	                                   the pooled eggs out of the stage

	Deterministic: no tweens, no clock of its own (the shell pieces and the
	confetti are posed too: Confetti.pose). The stage's camera sits at the
	origin looking along -Z (HatchFx.at / project); the eggs and golems
	face it and get their size by their distance (HatchFx.depthFor), so
	everything moves rigidly (one PivotTo a model a frame).

	V2 (owner 2026-10-30) adds layers, each posed by its own function from
	HatchFx's pure poses (the owner's names in brackets):
	  poseEggs       the entrance, the float, the charge's pulse and shake
	                 (playEggEntrance, playFloatingAnimation)
	  posePlatforms  the glowing platform under each egg
	  poseOrbits     two energy rings round each egg, opposite ways
	                 (playEnergyCharging, with poseMotes and poseAuras)
	  poseMotes      motes rising round the eggs, then streaming into them
	  poseAuras      the glow behind each charging egg, then each golem's aura
	  poseRings, poseBits, the flash   the burst (playEggExplosion)
	  reveal, poseGolems, poseBadges   the golems, their names, "1 in N",
	                 their rarity and bonus (playPetReveal)
	  poseRarity     the best rarity's show: the rays' colour, its pulses, the
	                 banner, Mythic's light (playRarityEffect)
	  "End"          the controller gives the HUD back (playOpeningComplete)
	Everything is pooled (CapsuleView.buildOpening) and hidden again by
	clear(); a cancelled opening is just a clear().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrightTheme = require(Shared.Config.BrightTheme)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local HatchFx = require(script.Parent.HatchFx)
local Confetti = require(script.Parent.Confetti)
local CapsuleView = require(script.Parent.CapsuleView)
local RevealKit = require(script.Parent.Parent.Effects.RevealKit)

local HatchStage = {}

HatchStage.SunSpin = 9 -- degrees a second (Reduce motion: still)

export type Args = {
	Refs: CapsuleView.OpenRefs,
	Capsule: string,
	Lucky: boolean, -- the odds the result was rolled at (its "1 in N")
	Kinds: { string }, -- the result's golems, in the server's order
	Eggs: { HatchFx.Record }, -- one pooled egg per golem (the capsule's, with their cracks)
	Fast: boolean, -- Auto
	Reduced: boolean, -- Reduce motion
	Phone: boolean, -- fewer rings
	Target: Vector2, -- where the golems fly (the player on the screen, shares)
	Golem: (kind: string) -> (Model, number, number), -- a golem's model, its height, its pivot over its feet
	Claim: () -> boolean, -- may the flash go off now (RevealKit.takeFlash: the game's one flash gap; false with Reduce motion)
	Wait: (() -> number)?, -- seconds until the next flash may (RevealKit.nextFlashAt): a refused flash waits, at most FlashGap
	Deleted: { [number]: boolean }?, -- the result's golems the player auto-deletes (by index): greyed, they stay
	Waiting: { [number]: boolean }?, -- won past the inventory's hard cap (a Robux pack's, by index): a note under the name
}

type Standing = { Model: Model, Height: number, Root: number, Depth: number, Spot: Vector2, Turn: number }

export type Run = {
	Args: Args,
	Refs: CapsuleView.OpenRefs,
	Timeline: HatchFx.Timeline,
	Count: number,
	Special: number?, -- the slot of a Legendary / Mythic (centred, bigger)
	Order: { number }, -- slot -> the result's index
	Kinds: { string }, -- per slot
	Rarities: { string }, -- per slot
	Colors: { Color3 }, -- per slot: its crack colour
	Deleted: { [number]: boolean }, -- per slot: auto-deleted (greyed, DELETED, no flight)
	Waiting: { [number]: boolean }, -- per slot: won but waiting for room ("Waiting: inventory full")
	Marked: boolean, -- two rows, a golem's tag carries a mark (DELETED, a waiting note): HatchStage.marks
	SafeBottom: number, -- the opening's SafeBottom the layout was made for (it settles: laid out again)
	BestRarity: string,
	BestOrder: number,
	Size: Vector2, -- the screen (design units) the layout is for
	Layout: HatchFx.Layout,
	EggDepth: { number },
	Standing: { [number]: Standing },
	Tier: HatchFx.Tier, -- the best rarity's cinematic (its Timeline's)
	BestSlot: number, -- the slot of the batch's best golem (its pulses, the banner's bonus)
	BestColor: Color3,
	Bonuses: { [number]: string }, -- per slot: its golem's bonus ("+10% Income"; none: no entry)
	Badged: boolean, -- up to CapsuleView.BadgeSlots golems: a rarity pill over each head
	MotesPer: number, -- motes per egg (fewer for many eggs, fewer on a phone)
	OrbitsPer: number, -- energy rings per egg (a phone opening many: 1)
	BadgeSize: { [number]: number }, -- per slot: the text size its pill was measured at (measured once, placed each frame)
	EggPoses: { [number]: HatchFx.EggPose }, -- each egg's pose this frame (its orbits and motes follow it)
	Fired: { [string]: boolean },
	FlashFrom: number?, -- t when the burst's flash went off (nil: not yet / none)
	FlashRetry: number?, -- t when a refused flash asks again (it waited for the shared gap)
	Spin: number, -- the sunburst's turn
	Last: number, -- the last pose's t
}

-- The chance a golem had in this result: the odds it was rolled at (Triple Lucky's if it ran).
function HatchStage.chance(capsuleId: string, lucky: boolean, kind: string): number
	for _, line in CapsuleConfig.odds(capsuleId, lucky) do
		if line.Golem == kind then
			return line.Chance
		end
	end
	return 0
end

--[[
	How much room the marks need when tags of two rows carry some
	(HatchFx.Marks; nil: none): the tallest tag under a golem's feet in each
	row (its name, its "1 in N" and its mark, as CapsuleView.setTag builds
	them; a tag beside the Auto button may need two lines for its name and
	its note) and the safe bottom (above a phone's home indicator: the
	opening's SafeBottom), as shares of the screen's height.
]]
function HatchStage.marks(run: Run): HatchFx.Marks?
	if not run.Marked then
		return nil
	end
	local o = run.Refs
	local height = math.max(1, o.Size.Y)
	local aspect = o.Size.X / height
	-- (a tag beside the Auto button may need two lines, its name's and its note's: the second row's
	-- first golem of a PC Open 10, its column reaching over the button at the bottom left; on touch
	-- the button sits top left)
	local function beside(slot: number): boolean
		if o.Touch or not o.AutoHolder.Visible or slot <= 5 then
			return false
		end
		local x, dx = HatchFx.rowX(slot, run.Count, aspect)
		local left = (x - dx * 0.48) * o.Size.X
		for _, keep in o.AutoKeep do
			if left < keep.Max.X then
				return true
			end
		end
		return false
	end
	local function tagOf(slot: number, fit: number): number
		local two = beside(slot)
		local lines = if two then 2 else 1
		local small = math.max(CapsuleView.TagMin, math.floor(fit * HatchFx.ChanceShare + 0.5))
		local note = (if two then 2 else 1) * (CapsuleView.TagMin + 2) + 10
		local mark = if run.Deleted[slot] then 30 elseif run.Waiting[slot] then note else 0
		return (4 + lines * (fit + 2) + small + 6 + mark) / height
	end
	local top, low = 0, 0
	for slot = 1, run.Count do
		local fit = if run.Special == slot then 26 else 22
		if slot <= 5 then
			top = math.max(top, tagOf(slot, fit))
		else
			low = math.max(low, tagOf(slot, fit))
		end
	end
	return { Top = top, Low = low, Floor = 1 - (o.SafeBottom + 6) / height }
end

local function relayout(run: Run)
	local size = run.Refs.Size
	run.Size = size
	run.SafeBottom = run.Refs.SafeBottom
	local aspect = size.X / math.max(1, size.Y)
	run.Layout = HatchFx.layout(run.Count, aspect, run.Special, HatchStage.marks(run))
	-- (a screen too short for the second row's marks even with the smallest golems: said, as setTag's
	-- UnderAuto; the specs hold it never is)
	run.Refs.Gui:SetAttribute("MarksOverrun", run.Layout.Overrun)
	for slot, rec in run.Args.Eggs do
		local s = run.Layout.Slots[slot]
		if s then
			run.EggDepth[slot] = HatchFx.depthFor(rec.Height, s.EggH)
		end
	end
end

function HatchStage.new(args: Args): Run
	local o = args.Refs
	local n = math.clamp(#args.Kinds, 1, CapsuleView.StageTags)
	local best = CapsuleView.best(args.Kinds) or args.Kinds[1]
	local bestOrder = GolemConfig.order(best)
	local golem = GolemConfig.ById[best]
	local bestRarity = if golem then golem.Rarity else "Common"
	local bestIndex = table.find(args.Kinds, best) or 1
	local order, special = HatchFx.arrange(n, bestIndex, bestOrder)
	local timeline = HatchFx.timeline(bestOrder, n, args.Fast, args.Reduced)
	local motes = if n <= 3 then 8 elseif n <= 5 then 5 else 3
	local run: Run = {
		Args = args,
		Refs = o,
		Timeline = timeline,
		Count = n,
		Special = special,
		Order = order,
		Kinds = {},
		Rarities = {},
		Colors = {},
		Deleted = {},
		Waiting = {},
		Marked = false,
		SafeBottom = o.SafeBottom,
		BestRarity = bestRarity,
		BestOrder = bestOrder,
		Size = o.Size,
		Layout = HatchFx.layout(n, 16 / 9, special),
		EggDepth = {},
		Standing = {},
		Tier = timeline.Tier,
		BestSlot = table.find(order, bestIndex) or 1,
		BestColor = BrightTheme.crackColour(bestRarity),
		Bonuses = {},
		Badged = n <= CapsuleView.BadgeSlots,
		MotesPer = math.min(if args.Phone then math.ceil(motes * 0.6) else motes, math.floor(#o.Motes / n)),
		OrbitsPer = if args.Phone and n > 3 then 1 else HatchFx.OrbitCount,
		EggPoses = {},
		BadgeSize = {},
		Fired = {},
		FlashFrom = nil,
		FlashRetry = nil,
		Spin = 0,
		Last = 0,
	}
	for slot = 1, n do
		local kind = args.Kinds[order[slot]]
		local info = GolemConfig.ById[kind]
		run.Kinds[slot] = kind
		run.Rarities[slot] = if info then info.Rarity else "Common"
		run.Colors[slot] = BrightTheme.crackColour(run.Rarities[slot])
		run.Deleted[slot] = args.Deleted ~= nil and args.Deleted[order[slot]] == true
		run.Waiting[slot] = args.Waiting ~= nil and args.Waiting[order[slot]] == true
		local bonus = if info then HatchFx.bonusText(info.Bonus.Type, info.Bonus.Value, GolemConfig.BonusTypes) else nil
		if bonus then
			run.Bonuses[slot] = bonus
		end
		-- (two rows: a top-row mark hangs toward the second row's golems, a second-row one toward the
		-- screen's safe bottom)
		if n > 5 and (run.Deleted[slot] or run.Waiting[slot]) then
			run.Marked = true
		end
	end
	relayout(run)
	-- the blobs in the best colour, the shell pieces in each egg's (and white)
	local bestColor = BrightTheme.crackColour(bestRarity)
	for _, blob in o.Blobs do
		for _, disc in blob:GetChildren() do
			if disc:IsA("Frame") then
				disc.BackgroundColor3 = bestColor
			end
		end
	end
	-- (each egg's pieces in its own colour: poseBits hands every egg a block of `per` shards)
	local per = math.max(1, math.floor(#o.Shards / n))
	for i, piece in o.Shards do
		local c = run.Colors[math.min(n, (i - 1) // per + 1)]
		piece.BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else c
	end
	for _, rec in args.Eggs do
		rec.Model.Parent = nil
	end
	HatchStage.dress(run)
	return run
end

-- The confetti's own colours (Confetti.build's), put back between openings.
local function confettiColor(i: number): Color3
	return Confetti.Colors[(i - 1) % #Confetti.Colors + 1]
end

--[[
	(V2) The best rarity's colours on the pooled pieces of a new run: the
	sunburst (soft white; a Common's to an Epic's core lightly tinted;
	Legendary golden rays, Mythic rainbow rays), the confetti (Legendary
	gold, Mythic a rainbow, else its own), the banner's word and its sub
	line (the best golem's bonus).
]]
function HatchStage.dress(run: Run)
	local o = run.Refs
	local tier = run.Tier
	local rarity = run.BestRarity
	local white = Color3.new(1, 1, 1)
	local tint = if rarity == "Common" then white else run.BestColor:Lerp(white, if tier.Rays then 0.15 else 0.6)
	for i, piece in o.Sunburst:GetChildren() do
		if piece:IsA("Frame") then
			if piece.Name == "Glow" or piece.Name == "Core" then
				piece.BackgroundColor3 = tint
			elseif tier.Rays and rarity == "Mythic" then
				piece.BackgroundColor3 = Color3.fromHSV((i / 16) % 1, 0.55, 1)
			else
				piece.BackgroundColor3 = if tier.Rays then tint else white
			end
		end
	end
	local gold = { Color3.fromRGB(255, 214, 64), Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 170, 30), white }
	for i, piece in o.Confetti do
		if rarity == "Legendary" then
			piece.BackgroundColor3 = gold[(i - 1) % #gold + 1]
		elseif rarity == "Mythic" then
			piece.BackgroundColor3 = Color3.fromHSV((i * 0.13) % 1, 0.65, 1)
		else
			piece.BackgroundColor3 = confettiColor(i)
		end
	end
	local word = tier.Banner
	if word then
		CapsuleView.setBanner(o, word, run.Bonuses[run.BestSlot], rarity)
	end
end

-- Every piece hidden, the golems freed, the pooled eggs out of the stage (between two openings).
function HatchStage.clear(o: CapsuleView.OpenRefs, golems: { Model }?)
	for _, child in o.Stage:GetChildren() do
		if child:GetAttribute("Pooled") == true then
			child.Parent = nil
		elseif child:IsA("Model") then
			child:Destroy()
		end
	end
	if golems then
		for _, model in golems do
			model:Destroy()
		end
	end
	for _, tag in o.Tags do
		tag.Frame.Visible = false
	end
	for i, list in o.Rings do
		for _, ring in list do
			ring.Visible = false
		end
		o.Puffs[i].Visible = false
	end
	for _, blob in o.Blobs do
		blob.Visible = false
	end
	for _, piece in o.Shards do
		piece.Visible = false
	end
	for _, piece in o.Confetti do
		piece.Visible = false
	end
	o.Sunburst.Visible = false
	o.Flash.BackgroundTransparency = 1
	o.Stage.ImageTransparency = 0
	-- (V2) the platforms, orbits, motes, auras, pills and the banner; the stage's own light back
	for i, platform in o.Platforms do
		platform.Visible = false
		for _, ring in o.Orbits[i] do
			ring.Visible = false
		end
		o.Auras[i].Visible = false
	end
	for _, mote in o.Motes do
		mote.Visible = false
	end
	for _, badge in o.Badges do
		badge.Frame.Visible = false
	end
	o.Banner.Frame.Visible = false
	o.Stage.Ambient = CapsuleView.StageAmbient
	o.Stage.LightColor = CapsuleView.StageLight
	for i, piece in o.Confetti do
		piece.BackgroundColor3 = confettiColor(i)
	end
end

-- An auto-deleted golem: every part a stone grey (its shape stays; never see-through).
function HatchStage.grey(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local v = 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
			local g = 0.28 + 0.42 * v
			d.Color = Color3.new(g, g, math.min(1, g * 1.04))
			if d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

-- The golems of a run (the controller frees them when it ends).
function HatchStage.golems(run: Run): { Model }
	local out: { Model } = {}
	for _, g in run.Standing do
		table.insert(out, g.Model)
	end
	return out
end

local function poseEggs(run: Run, t: number, aspect: number)
	local tl = run.Timeline
	local o = run.Refs
	for slot, rec in run.Args.Eggs do
		local s = run.Layout.Slots[slot]
		if not s then
			continue
		end
		local pose = HatchFx.eggPose(t, tl, slot, slot == run.Special)
		run.EggPoses[slot] = pose
		if pose.Shown then
			if rec.Model.Parent ~= o.Stage then
				rec.Model.Parent = o.Stage
			end
			-- (bigger by coming closer; it rises and bobs (Drop); it rocks about its foot; it faces the
			-- camera, turned a little to the middle, and turns slowly (Yaw))
			local depth = run.EggDepth[slot] / pose.Scale
			local middle = HatchFx.at(s.Egg.X, s.Egg.Y + pose.Drop, depth, aspect)
			local foot = middle + Vector3.new(0, rec.Foot - rec.Mid, 0)
			local cf = CFrame.new(foot)
				* CFrame.Angles(0, 0, pose.Roll)
				* CFrame.new(0, -rec.Foot, 0)
				* CFrame.Angles(0, math.pi + (0.5 - s.Egg.X) * 0.5 + pose.Yaw, 0)
			rec.Model:PivotTo(cf)
			HatchFx.paintEgg(rec, pose, run.Rarities[slot], t)
		elseif rec.Model.Parent then
			rec.Model.Parent = nil
		end
	end
end

local function poseRings(run: Run, t: number)
	local tl = run.Timeline
	local o = run.Refs
	local size = run.Size
	local rings = if run.Count > 3 and run.Args.Phone then 1 else HatchFx.RingCount
	for slot = 1, run.Count do
		local s = run.Layout.Slots[slot]
		local center = Vector2.new(s.Egg.X * size.X, s.Egg.Y * size.Y)
		local eggPx = s.EggH * size.Y
		-- (RevealKit's shockwave rings, thin and white round each egg; the best golem's slot: its
		-- rarity's energy pulses at the reveal, in its colour, round the golem: HatchFx.pulseU)
		for j, ring in o.Rings[slot] do
			local u = if j <= rings then HatchFx.ringU(t, tl, j) else -1
			local pu = if slot == run.BestSlot and not (u >= 0 and u < 1) then HatchFx.pulseU(t, tl, j) else -1
			if pu >= 0 and pu < 1 and s then
				local golemPx = s.GolemH * size.Y
				ring.Position = UDim2.fromOffset(s.Golem.X * size.X, s.Golem.Y * size.Y)
				ring.Size = UDim2.fromOffset(golemPx, golemPx)
				RevealKit.poseRing(ring, pu, HatchFx.crackColor(run.BestRarity, t, j / 3, 0), {
					From = 0.55,
					Grow = 1.5,
					Thickness = math.max(3, golemPx * 0.022),
				})
				continue
			end
			ring.Position = UDim2.fromOffset(center.X, center.Y)
			ring.Size = UDim2.fromOffset(eggPx, eggPx)
			RevealKit.poseRing(ring, u, Color3.new(1, 1, 1), {
				From = HatchFx.RingFrom,
				Grow = HatchFx.RingGrow,
				Thickness = math.max(3, eggPx * 0.016),
			})
		end
		-- the puff: with the rings, and again (bigger) at the burst
		local puffK, puffAlpha = HatchFx.puffAt(t - tl.Rings)
		if not tl.Reduced then
			local burstK, burstAlpha = HatchFx.puffAt(t - tl.Burst)
			if burstAlpha < 1 then
				-- (bigger at the burst; a batch of many: smaller, they would wash the screen white)
				puffK, puffAlpha = burstK * (if run.Count > 3 then 0.9 else 1.3), burstAlpha
			end
		end
		local puff = o.Puffs[slot]
		puff.Visible = puffAlpha < 1
		if puff.Visible then
			puff.Position = UDim2.fromOffset(center.X, center.Y)
			puff.Size = UDim2.fromOffset(eggPx * puffK, eggPx * puffK)
			for _, disc in puff:GetChildren() do
				if disc:IsA("Frame") then
					disc.BackgroundTransparency = puffAlpha
				end
			end
		end
	end
end

-- (V2) The soft white-blue the platforms and motes glow in before the charge colours them.
HatchStage.Neutral = Color3.fromRGB(205, 232, 255)

-- An egg's energy colour at `t` (its golem's rarity: the cracks'; Mythic a moving rainbow) from the
-- soft neutral as the charge grows (so nothing tells the rarity before the cracks do).
local function energyOf(run: Run, slot: number, t: number, along: number): Color3
	local charge = HatchFx.chargeAt(t, run.Timeline)
	local c = HatchFx.crackColor(run.Rarities[slot], t, along, 0)
	return if charge >= 1 or t >= run.Timeline.Burst then c else HatchStage.Neutral:Lerp(c, charge)
end

-- An egg's middle on the screen now (design units) and its height there: its place, its rise and bob.
local function eggOnScreen(run: Run, slot: number): (Vector2, number)
	local s = run.Layout.Slots[slot]
	local pose = run.EggPoses[slot]
	local drop = if pose and pose.Shown then pose.Drop else 0
	local scale = if pose and pose.Shown then pose.Scale else 1
	return Vector2.new(s.Egg.X * run.Size.X, (s.Egg.Y + drop) * run.Size.Y), s.EggH * run.Size.Y * scale
end

-- (V2) The glowing platform under each egg: it grows in with its egg, glows with the charge, flares at the burst.
local function posePlatforms(run: Run, t: number, aspect: number)
	local o = run.Refs
	local size = run.Size
	for slot, platform in o.Platforms do
		local s = run.Layout.Slots[slot]
		local strength, k = 0, 1
		if s and slot <= run.Count then
			strength, k = HatchFx.platformAt(t, run.Timeline, slot)
		end
		platform.Visible = strength > 0.01
		if not platform.Visible then
			continue
		end
		local width = s.EggH * size.Y * 0.78 * k -- (an Open 3's overlapping eggs: their platforms only touch)
		-- (at its egg's feet where it rests: the egg rises into it and floats over it)
		local rec = run.Args.Eggs[slot]
		local y = (s.Egg.Y + s.EggH * 0.4) * size.Y
		if rec and run.EggDepth[slot] then
			local middle = HatchFx.at(s.Egg.X, s.Egg.Y, run.EggDepth[slot], aspect)
			y = HatchFx.project(middle + Vector3.new(0, rec.Foot - rec.Mid, 0), aspect).Y * size.Y
		end
		platform.Position = UDim2.fromOffset(s.Egg.X * size.X, y)
		platform.Size = UDim2.fromOffset(width, width * 0.26)
		local color = energyOf(run, slot, t, 0.5)
		local outer = platform:FindFirstChild("Outer")
		local core = platform:FindFirstChild("Core")
		if outer and outer:IsA("Frame") then
			outer.BackgroundColor3 = color
			outer.BackgroundTransparency = 1 - 0.9 * strength
			local rim = outer:FindFirstChild("Rim")
			if rim and rim:IsA("UIStroke") then
				rim.Color = color
				rim.Thickness = math.max(2, width * 0.012)
				rim.Transparency = 1 - 0.75 * strength
			end
		end
		if core and core:IsA("Frame") then
			core.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
			core.BackgroundTransparency = 1 - 0.85 * strength
		end
	end
end

-- (V2) Two energy rings orbiting each charging egg (opposite ways, faster and faster); they fly apart at the burst.
local function poseOrbits(run: Run, t: number)
	local o = run.Refs
	local tl = run.Timeline
	for slot, list in o.Orbits do
		for j, ring in list do
			local strength, turn, k = 0, 0, 1
			if slot <= run.Count and j <= run.OrbitsPer then
				strength, turn, k = HatchFx.orbitAt(t, tl, slot, j)
			end
			ring.Visible = strength > 0.01
			if not ring.Visible then
				continue
			end
			local center, eggPx = eggOnScreen(run, slot)
			local d = eggPx * k
			local charge = HatchFx.chargeAt(t, tl)
			local color = energyOf(run, slot, t, j / 2)
			ring.Position = UDim2.fromOffset(center.X, center.Y)
			ring.Size = UDim2.fromOffset(d, d)
			ring.Rotation = turn
			local line = ring:FindFirstChild("Line")
			if line and line:IsA("UIStroke") then
				line.Color = color
				line.Thickness = math.max(2, eggPx * (0.008 + 0.01 * charge))
				line.Transparency = 1 - strength
			end
			local spark = ring:FindFirstChild("Spark")
			if spark and spark:IsA("Frame") then
				spark.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6)
				spark.BackgroundTransparency = 1 - strength
			end
		end
	end
end

-- (V2) The motes: a few rising round each floating egg, then streaming into it while it charges.
local function poseMotes(run: Run, t: number)
	local o = run.Refs
	local tl = run.Timeline
	local per = run.MotesPer
	for i, mote in o.Motes do
		local slot = (i - 1) // math.max(1, per) + 1
		local k = (i - 1) % math.max(1, per) + 1
		local shown, x, y, share, strength = false, 0, 0, 0, 0
		if per > 0 and slot <= run.Count then
			shown, x, y, share, strength = HatchFx.moteAt(t, tl, slot, k, per)
		end
		mote.Visible = shown and strength > 0.02
		if not mote.Visible then
			continue
		end
		local center, eggPx = eggOnScreen(run, slot)
		local d = math.max(4, eggPx * share)
		mote.Position = UDim2.fromOffset(center.X + x * eggPx, center.Y + y * eggPx)
		mote.Size = UDim2.fromOffset(d, d)
		mote.BackgroundColor3 = energyOf(run, slot, t, k / per):Lerp(Color3.new(1, 1, 1), 0.3)
		mote.BackgroundTransparency = 1 - strength
	end
end

-- (V2) The glow behind each charging egg, then the soft aura behind each golem (its rarity's colour).
local function poseAuras(run: Run, t: number)
	local o = run.Refs
	local tl = run.Timeline
	local size = run.Size
	for slot, aura in o.Auras do
		local strength = if slot <= run.Count then HatchFx.auraAt(t, tl, slot) else 0
		if run.Deleted[slot] and t >= tl.Reveal then
			strength = 0 -- (an auto-deleted golem: greyed, no glow)
		end
		aura.Visible = strength > 0.01
		if not aura.Visible then
			continue
		end
		local s = run.Layout.Slots[slot]
		local center: Vector2, px: number, color: Color3
		if t < tl.Reveal then
			local eggPx
			center, eggPx = eggOnScreen(run, slot)
			px = eggPx * 1.35
			color = energyOf(run, slot, t, 0.3)
		else
			center = Vector2.new(s.Golem.X * size.X, s.Golem.Y * size.Y)
			px = s.GolemH * size.Y * 1.3
			color = HatchFx.crackColor(run.Rarities[slot], t, 0.3, 0)
		end
		aura.Position = UDim2.fromOffset(center.X, center.Y)
		aura.Size = UDim2.fromOffset(px, px)
		for _, disc in aura:GetChildren() do
			if disc:IsA("Frame") then
				local j = tonumber(string.sub(disc.Name, 5)) or 1
				disc.BackgroundColor3 = color
				disc.BackgroundTransparency = 1 - (0.1 + 0.08 * j) * strength
			end
		end
	end
end

local function poseBlobs(run: Run, t: number)
	local tl = run.Timeline
	local o = run.Refs
	local size = run.Size
	local strength = HatchFx.blobsAt(t, tl)
	for i, blob in o.Blobs do
		blob.Visible = strength > 0
		if strength > 0 then
			local a = i * 1.7 + (if tl.Reduced then 0 else t * 0.5)
			local x = 0.5 + 0.28 * math.cos(a) * (if i % 2 == 0 then 1 else 0.8)
			local y = 0.5 + 0.2 * math.sin(a * 1.3)
			blob.Position = UDim2.fromOffset(x * size.X, y * size.Y)
			for _, disc in blob:GetChildren() do
				if disc:IsA("Frame") then
					local j = tonumber(string.sub(disc.Name, 5)) or 1
					disc.BackgroundTransparency = 1 - (0.14 + 0.07 * j) * strength
					if run.BestRarity == "Mythic" then
						disc.BackgroundColor3 = HatchFx.crackColor("Mythic", t, i / #o.Blobs, 0)
					end
				end
			end
		end
	end
end

-- A golem's 3/4 look: turned a little toward the middle, the middle one a little to its left.
local function turnOf(spot: Vector2): number
	return (spot.X - 0.5) * 0.45 + (if math.abs(spot.X - 0.5) < 0.01 then HatchFx.Turn else 0)
end

--[[
	Every standing golem's name under its feet, "1 in N" in the rarity's
	colour (nothing else; DELETED when auto-deleted, "Waiting: inventory
	full" for a won golem past the inventory's hard cap): at the reveal and
	again when the screen changes mid-opening (the golems moved).
]]
local function placeTags(run: Run, aspect: number)
	local o = run.Refs
	local size = run.Size
	local args = run.Args
	for slot, standing in run.Standing do
		local kind = run.Kinds[slot]
		local s = run.Layout.Slots[slot]
		local info = GolemConfig.ById[kind]
		local feet = HatchFx.at(standing.Spot.X, standing.Spot.Y, standing.Depth, aspect) - Vector3.new(0, standing.Height / 2, 0)
		local under = HatchFx.project(feet, aspect)
		CapsuleView.setTag(
			o,
			slot,
			if info then info.Name else kind,
			BrightTheme.oneInText(HatchStage.chance(args.Capsule, args.Lucky, kind)),
			run.Colors[slot],
			Vector2.new(under.X * size.X, under.Y * size.Y + 4),
			s.Text,
			-- (the name fits between its neighbours. The big middle one of two rows stands well under
			-- the top row's names: the room of one and a half. Of one row it stands only a little
			-- lower than its neighbours: its own column, a long name on two lines; its neighbours'
			-- too where one line won't fit at the text floor)
			run.Layout.Spacing
				* size.X
				* (if slot == run.Special and run.Count > 5 then 1.5 else 0.96),
			run.Deleted[slot],
			run.Waiting[slot],
			run.Layout.Spacing * size.X * 0.96, -- (a note never wider than the golems' pitch)
			if run.Count > 5 then nil elseif slot == run.Special then s.Text else CapsuleView.TagMin
		)
	end
end

-- The names placed again (the Auto button showed or hid: they step aside for it only while it shows).
function HatchStage.retag(run: Run)
	if next(run.Standing) ~= nil then
		placeTags(run, run.Size.X / math.max(1, run.Size.Y))
	end
end

local function reveal(run: Run, aspect: number)
	local args = run.Args
	for slot = 1, run.Count do
		local kind = run.Kinds[slot]
		local s = run.Layout.Slots[slot]
		local model, height, root = args.Golem(kind)
		run.Standing[slot] = {
			Model = model,
			Height = height,
			Root = root,
			Depth = HatchFx.depthFor(height, s.GolemH),
			Spot = s.Golem,
			Turn = turnOf(s.Golem),
		}
		if run.Deleted[slot] then
			HatchStage.grey(model)
		end
	end
	placeTags(run, aspect)
end

local function poseGolems(run: Run, t: number, aspect: number)
	local tl = run.Timeline
	local o = run.Refs
	for slot, g in run.Standing do
		local pose = HatchFx.golemPose(t, tl, slot)
		local tag = o.Tags[slot]
		if not pose.Shown then
			g.Model.Parent = nil
			tag.Frame.Visible = false
			continue
		end
		local spot, depth = HatchFx.flyTo(g.Spot, g.Depth / pose.Scale, run.Args.Target, pose.Fly)
		local spin = pose.Spin
		if run.Deleted[slot] then
			-- auto-deleted: it never flies to the player; it shrinks away where it stood
			spot, depth, spin = g.Spot, g.Depth / pose.Scale * (1 + 5 * pose.Fly * pose.Fly), 0
		end
		local middle = HatchFx.at(spot.X, spot.Y, depth, aspect) + Vector3.new(0, g.Height * pose.Lift, 0)
		g.Model:PivotTo(CFrame.new(middle + Vector3.new(0, g.Root - g.Height / 2, 0)) * CFrame.Angles(0, math.pi + g.Turn + spin, 0))
		if g.Model.Parent ~= o.Stage then
			g.Model.Parent = o.Stage
		end
		tag.Frame.Visible = pose.Name < 1
		if tag.Frame.Visible then
			for _, label in { tag.Name, tag.Chance } do
				label.TextTransparency = pose.Name
				local edge = label:FindFirstChild("Edge")
				if edge and edge:IsA("UIStroke") then
					edge.Transparency = pose.Name
				end
			end
			CapsuleView.fadeMarks(tag, pose.Name) -- (DELETED and the waiting note fade with the name)
		end
	end
	if tl.Reduced then
		-- (Reduce motion: the golems fade in and out with the whole stage; the eggs fade part by part)
		o.Stage.ImageTransparency = if t < tl.Burst then 0 else HatchFx.golemPose(t, tl, 1).Fade
	end
end

local function poseSunburst(run: Run, t: number, dt: number)
	local o = run.Refs
	local sun = HatchFx.sunburstAt(t, run.Timeline)
	o.Sunburst.Visible = sun > 0
	if sun <= 0 then
		return
	end
	if not run.Timeline.Reduced then
		run.Spin += dt * HatchStage.SunSpin
	end
	o.Sunburst.Rotation = run.Spin
	local rays = run.Tier.Rays -- (V2: a Legendary's golden rays, a Mythic's rainbow ones: stronger)
	local mythic = rays and run.BestRarity == "Mythic"
	for i, piece in o.Sunburst:GetChildren() do
		if piece:IsA("Frame") then
			local base = if piece.Name == "Glow" then 0.55 elseif rays and piece.Name ~= "Core" then 0.2 else 0.35
			piece.BackgroundTransparency = 1 - (1 - base) * sun
			if mythic and piece.Name ~= "Glow" and piece.Name ~= "Core" then
				piece.BackgroundColor3 = Color3.fromHSV((i / 16 + t * 0.2) % 1, 0.55, 1)
			end
		end
	end
end

--[[
	(V2) Each standing golem's rarity pill over its head (openings of up to
	BadgeSlots): its rarity and its bonus, fading with its name; none for
	an auto-deleted golem, nor for the best one when the banner says its
	rarity (its bonus is the banner's sub line).
]]
local function poseBadges(run: Run, t: number, aspect: number)
	local o = run.Refs
	local tl = run.Timeline
	local size = run.Size
	for slot = 1, #o.Badges do
		local g = run.Standing[slot]
		local s = run.Layout.Slots[slot]
		local pose = if g and run.Badged then HatchFx.golemPose(t, tl, slot) else nil
		local banner = run.Tier.Banner ~= nil and slot == run.BestSlot
		if not g or not s or not pose or not pose.Shown or pose.Name >= 1 or run.Deleted[slot] or banner then
			o.Badges[slot].Frame.Visible = false
			continue
		end
		-- (over its head as it stands now: its pop, its bob; measured once, at its text size)
		local depth = g.Depth / pose.Scale
		local middle = HatchFx.at(g.Spot.X, g.Spot.Y, depth, aspect) + Vector3.new(0, g.Height * pose.Lift, 0)
		local head = HatchFx.project(middle + Vector3.new(0, g.Height / 2, 0), aspect)
		local at = Vector2.new(head.X * size.X, head.Y * size.Y - 6)
		local text = math.max(CapsuleView.TagMin, math.floor(s.Text * 0.62 + 0.5))
		if run.BadgeSize[slot] ~= text then
			run.BadgeSize[slot] = text
			CapsuleView.setBadge(o, slot, run.Rarities[slot], run.Bonuses[slot], at, text)
		end
		local badge = o.Badges[slot]
		badge.Frame.Position = UDim2.fromOffset(math.floor(at.X), math.floor(at.Y))
		badge.Frame.Visible = true
		CapsuleView.fadeBadge(badge, pose.Name)
	end
end

--[[
	(V2) The best rarity's show (Tier): LEGENDARY! / MYTHIC! slamming in
	over the golems (in the band they leave free, under the top bar and
	the chain's "2 / 5"; Mythic's letters a moving rainbow), and Mythic's
	stronger, rainbow-tinted stage light.
]]
local function poseRarity(run: Run, t: number)
	local o = run.Refs
	local tl = run.Timeline
	local b = o.Banner
	local scale, alpha = HatchFx.bannerAt(t, tl)
	b.Frame.Visible = run.Tier.Banner ~= nil and alpha < 1
	if b.Frame.Visible then
		local chain = o.Chain.Visible and not o.Touch -- (touch: the chain sits top right)
		local top = o.Inset + 8 + (if chain then o.Chain.Size.Y.Offset + 6 else 0)
		local height = b.Frame.Size.Y.Offset
		local fit = if chain then 0.75 else 1
		-- (a wide phone: the pills over the neighbours' heads reach the band; the word gets smaller
		-- until it clears them, never under 0.6 of its size)
		local half = CapsuleView.bannerWidth(o) / 2 + 12
		local middle = run.Size.X / 2
		for _, badge in o.Badges do
			if badge.Frame.Visible then
				local by = badge.Frame.Position.Y.Offset
				local bh = badge.Frame.Size.Y.Offset
				if by - bh < top + height * fit and by > top then
					local room = math.abs(badge.Frame.Position.X.Offset - middle) - badge.Frame.Size.X.Offset / 2
					fit = math.min(fit, math.max(0.6, room / half))
				end
			end
		end
		b.Frame.Position = UDim2.fromOffset(middle, top + height * fit / 2)
		b.Scale.Scale = scale * fit
		b.Word.TextTransparency = alpha
		b.Edge.Transparency = alpha
		b.Sub.TextTransparency = alpha
		local subEdge = b.Sub:FindFirstChild("Edge")
		if subEdge and subEdge:IsA("UIStroke") then
			subEdge.Transparency = alpha
		end
		if run.BestRarity == "Mythic" and not tl.Reduced then
			b.Paint.Color = RevealKit.rainbow(t * 0.35)
		end
	end
	local light = HatchFx.lightAt(t, tl)
	if light > 0 then
		local hue = (t * 0.15) % 1
		o.Stage.Ambient = CapsuleView.StageAmbient:Lerp(Color3.fromHSV(hue, 0.22, 1), light)
		o.Stage.LightColor = CapsuleView.StageLight:Lerp(Color3.fromHSV((hue + 0.5) % 1, 0.3, 1), light * 0.8)
	elseif o.Stage.Ambient ~= CapsuleView.StageAmbient then
		o.Stage.Ambient = CapsuleView.StageAmbient
		o.Stage.LightColor = CapsuleView.StageLight
	end
end

-- The shell pieces (from each egg at the burst) and a little confetti (at the reveal), posed (no tweens).
local function poseBits(run: Run, t: number)
	local tl = run.Timeline
	local o = run.Refs
	if tl.Reduced then
		return
	end
	local per = math.max(1, math.floor(#o.Shards / run.Count))
	local u = t - tl.Burst
	for slot = 1, run.Count do
		local s = run.Layout.Slots[slot]
		local from = (slot - 1) * per + 1
		local pieces: { Frame } = {}
		for i = from, math.min(#o.Shards, from + per - 1) do
			table.insert(pieces, o.Shards[i])
		end
		if u >= 0 and u < Confetti.Seconds then
			Confetti.pose(pieces, s.Egg, slot * 7, u * 1.2)
		else
			for _, piece in pieces do
				piece.Visible = false
			end
		end
	end
	-- (V2: as many pieces as the best rarity's Tier, gold for a Legendary, a rainbow for a Mythic: dress)
	local c = t - tl.Reveal
	local many = math.clamp(run.Tier.Confetti, 0, #o.Confetti)
	local pieces = table.move(o.Confetti, 1, many, 1, {})
	for i = many + 1, #o.Confetti do
		o.Confetti[i].Visible = false
	end
	if c >= 0 and c < Confetti.Seconds then
		Confetti.pose(pieces, Vector2.new(0.5, 0.42), 11, c)
	else
		for _, piece in pieces do
			piece.Visible = false
		end
	end
end

--[[
	Poses everything at `t` seconds (see the header) and returns the events
	since the last call, in order.
]]
function HatchStage.pose(run: Run, t: number): { string }
	local tl = run.Timeline
	local o = run.Refs
	local events: { string } = {}
	local dt = math.max(0, t - run.Last)
	run.Last = t
	local function once(name: string): boolean
		if run.Fired[name] then
			return false
		end
		run.Fired[name] = true
		table.insert(events, name)
		return true
	end
	if o.Size ~= run.Size or o.SafeBottom ~= run.SafeBottom then
		relayout(run) -- (the screen turned or changed size mid-opening, or its safe frame settled)
		if next(run.Standing) ~= nil then
			-- (the golems out already: where they stand and their names follow the new layout)
			for slot, standing in run.Standing do
				local s = run.Layout.Slots[slot]
				standing.Depth = HatchFx.depthFor(standing.Height, s.GolemH)
				standing.Spot = s.Golem
				standing.Turn = turnOf(s.Golem)
			end
			placeTags(run, run.Size.X / math.max(1, run.Size.Y))
		end
	end
	local aspect = run.Size.X / math.max(1, run.Size.Y)
	if t >= tl.Charge then
		once("Charge") -- (V2: the energy starts)
	end
	local level = HatchFx.levelAt(t, tl)
	for step = 1, level do
		once("Step" .. step)
	end
	poseEggs(run, t, aspect)
	posePlatforms(run, t, aspect)
	poseOrbits(run, t)
	poseMotes(run, t)
	poseAuras(run, t)
	poseRings(run, t)
	poseBlobs(run, t)
	-- ONE flash in the best colour (RevealKit's, its one gap: refused, it waits for the next slot
	-- (nextFlashAt, at most FlashGap); the reveal's timing never waits for it)
	if t >= tl.Burst and once("Burst") and not tl.Reduced then
		o.Flash.BackgroundColor3 = HatchFx.crackColor(run.BestRarity, t, 0.3, 0)
		if run.Args.Claim() then
			run.FlashFrom = tl.Burst
		else
			local wait = if run.Args.Wait then run.Args.Wait() else RevealKit.FlashGap
			run.FlashRetry = tl.Burst + math.clamp(wait, 0, RevealKit.FlashGap)
		end
	end
	local retry = run.FlashRetry
	if retry and t >= retry then
		run.FlashRetry = nil
		if run.Args.Claim() then
			run.FlashFrom = t
		end
	end
	local from = run.FlashFrom
	-- (V2: stronger for the rarer: the Tier's)
	RevealKit.poseFlash(o.Flash, if from then HatchFx.flashU(t - from) else -1, HatchFx.flashPeakOf(tl))
	if t >= tl.Reveal and once("Reveal") then
		reveal(run, aspect)
	end
	if t >= tl.Banner then
		once("Banner") -- (V2: LEGENDARY! / MYTHIC!)
	end
	poseGolems(run, t, aspect)
	poseBadges(run, t, aspect)
	poseSunburst(run, t, dt)
	poseRarity(run, t)
	poseBits(run, t)
	if t >= tl.Fly then
		once("Fly")
	end
	if t >= tl.Total then
		once("End")
	end
	return events
end

return HatchStage
