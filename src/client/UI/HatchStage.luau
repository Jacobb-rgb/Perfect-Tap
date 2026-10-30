--[[
	HatchStage: one egg opening posed frame by frame on CapsuleView's
	opening (the owner's clicker-sim video, 2026-10-29; the flow and the
	numbers are UI/HatchFx's). CapsuleController plays it (input, sounds,
	the camera nudge, the HUD and the blur are its); the previews call the
	very same pose(), so a picture shows exactly what the game draws.

	  run = HatchStage.new(args)       the eggs placed, the colours chosen
	  events = HatchStage.pose(run, t) everything at `t` seconds; returns
	                                   what happened since the last call:
	                                   "Step1".."Step3" (a crack step),
	                                   "Burst", "Reveal", "Fly", "End"
	  HatchStage.clear(refs)           every piece hidden, the golems freed,
	                                   the pooled eggs out of the stage

	Deterministic: no tweens, no clock of its own (the shell pieces and the
	confetti are posed too: Confetti.pose). The stage's camera sits at the
	origin looking along -Z (HatchFx.at / project); the eggs and golems
	face it and get their size by their distance (HatchFx.depthFor), so
	everything moves rigidly (one PivotTo a model a frame).
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
	BestRarity: string,
	BestOrder: number,
	Size: Vector2, -- the screen (design units) the layout is for
	Layout: HatchFx.Layout,
	EggDepth: { number },
	Standing: { [number]: Standing },
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

local function relayout(run: Run)
	local size = run.Refs.Size
	run.Size = size
	local aspect = size.X / math.max(1, size.Y)
	run.Layout = HatchFx.layout(run.Count, aspect, run.Special)
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
	local order, special = HatchFx.arrange(n, table.find(args.Kinds, best) or 1, bestOrder)
	local run: Run = {
		Args = args,
		Refs = o,
		Timeline = HatchFx.timeline(bestOrder, n, args.Fast, args.Reduced),
		Count = n,
		Special = special,
		Order = order,
		Kinds = {},
		Rarities = {},
		Colors = {},
		Deleted = {},
		Waiting = {},
		BestRarity = bestRarity,
		BestOrder = bestOrder,
		Size = o.Size,
		Layout = HatchFx.layout(n, 16 / 9, special),
		EggDepth = {},
		Standing = {},
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
	return run
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
		if pose.Shown then
			if rec.Model.Parent ~= o.Stage then
				rec.Model.Parent = o.Stage
			end
			-- (bigger by coming closer; it rocks about its foot; it faces the camera, turned a little to the middle)
			local depth = run.EggDepth[slot] / pose.Scale
			local middle = HatchFx.at(s.Egg.X, s.Egg.Y, depth, aspect)
			local foot = middle + Vector3.new(0, rec.Foot - rec.Mid, 0)
			local cf = CFrame.new(foot)
				* CFrame.Angles(0, 0, pose.Roll)
				* CFrame.new(0, -rec.Foot, 0)
				* CFrame.Angles(0, math.pi + (0.5 - s.Egg.X) * 0.5, 0)
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
		-- (RevealKit's shockwave rings, thin and white round each egg)
		for j, ring in o.Rings[slot] do
			local u = if j <= rings then HatchFx.ringU(t, tl, j) else -1
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
			-- (the name fits between its neighbours: a big one gets the room of one and a half)
			run.Layout.Spacing
				* size.X
				* (if slot == run.Special then 1.5 else 0.96),
			run.Deleted[slot],
			run.Waiting[slot],
			run.Layout.Spacing * size.X * 0.96 -- (a note never wider than the golems' pitch)
		)
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
	for _, piece in o.Sunburst:GetChildren() do
		if piece:IsA("Frame") then
			local base = if piece.Name == "Glow" then 0.55 else 0.35
			piece.BackgroundTransparency = 1 - (1 - base) * sun
		end
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
	local c = t - tl.Reveal
	if c >= 0 and c < Confetti.Seconds then
		Confetti.pose(o.Confetti, Vector2.new(0.5, 0.42), 11, c)
	else
		for _, piece in o.Confetti do
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
	if o.Size ~= run.Size then
		relayout(run) -- (the screen turned or changed size mid-opening)
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
	local level = HatchFx.levelAt(t, tl)
	for step = 1, level do
		once("Step" .. step)
	end
	poseEggs(run, t, aspect)
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
	RevealKit.poseFlash(o.Flash, if from then HatchFx.flashU(t - from) else -1, HatchFx.FlashPeak)
	if t >= tl.Reveal and once("Reveal") then
		reveal(run, aspect)
	end
	poseGolems(run, t, aspect)
	poseSunburst(run, t, dt)
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
