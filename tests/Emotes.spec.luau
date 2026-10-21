--[[
	The emote concepts (Config/EmoteConfig, owner 2026-10-21: he picks which
	ones go in): the list and its original names, that none is wired into
	the game yet, every joint / key / duration valid, the loops lining up,
	the outros ending at rest, the body above the floor and no limb through
	the body over the intro, two loops and the outro from several stops
	(R15 block rig, lib/move_pose). Also the MoveMath features the emotes
	added (LoopFrom, a last key at Duration, Outro, RootPivot, the Root's
	YXZ turn order).
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local CFrame = Loader.CFrame
	local Vector3 = (require("@lune/roblox") :: any).Vector3
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local EmoteConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EmoteConfig")
	local MoveMath = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveMath")
	local MoveRules = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRules")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local MovePose = require("../tools/lune/lib/move_pose")

	local DEG = math.pi / 180

	local function angleBetween(a: any, b: any): number
		local _, angle = (a:Inverse() * b):ToAxisAngle()
		return math.abs(angle)
	end
	local function near(a: any, b: any, degrees: number, studs: number?): boolean
		return angleBetween(a, b) <= degrees * DEG and (a.Position - b.Position).Magnitude <= (studs or 1e-3)
	end
	local function samePose(a: { [string]: any }, b: { [string]: any }, degrees: number, studs: number): (boolean, string?)
		for joint, cf in a do
			if not b[joint] or not near(cf, b[joint], degrees, studs) then
				return false, joint
			end
		end
		return true, nil
	end

	---------------------------------------------------------------- the list

	T.test("emotes: twelve original concepts with Czech captions", function()
		local list = EmoteConfig.List
		T.truthy(#list >= 10 and #list <= 12, "10-12 emotes")
		local must = {
			"Breakdance",
			"Headspin",
			"Robot",
			"DiscoPoint",
			"BackGlide",
			"Worm",
			"Victory",
			"AirGuitar",
			"ForgeHammer",
			"GolemStomp",
			"GemJuggle",
			"BlasterSpin",
		}
		for _, name in must do
			T.truthy(table.find(list, name), name .. " is one of them")
		end
		-- names from other games are never used
		local banned = {
			"floss",
			"default",
			"griddy",
			"orange",
			"justice",
			"take the l",
			"takethel",
			"dab",
			"moonwalk",
			"gangnam",
			"hype",
			"renegade",
		}
		for _, name in list do
			local move = EmoteConfig.Emotes[name]
			T.truthy(move and move.Name == name, name .. " exists and is named")
			T.eq((EmoteConfig :: any)[name], move, name .. " is also EmoteConfig." .. name)
			local caption = EmoteConfig.Captions[name]
			T.truthy(type(caption) == "string" and #caption > 5, name .. " has a Czech caption")
			for _, word in banned do
				T.falsy(string.lower(name):find(word, 1, true), `{name}: no "{word}"`)
				T.falsy(string.lower(caption):find(word, 1, true), `{name} caption: no "{word}"`)
			end
		end
		T.truthy(EmoteConfig.Captions.Breakdance:find("větrník", 1, true), "the breakdance caption names the windmill")
	end)

	-- (live since the owner's yes: their own Net "Emote", attribute and menu, tests/EmotesLive.spec)
	T.test("emotes: kept apart from the player moves (their own whitelist and attribute)", function()
		for _, name in EmoteConfig.List do
			T.eq(MoveConfig.Moves[name], nil, name .. " is no player move")
			T.falsy(MoveConfig.ClientMoves[name], name .. " is not in the Move whitelist")
			T.falsy(MoveRules.clientAllowed(name), name .. ": not through Net Move")
			T.eq(MoveRules.decode(MoveRules.encode(name, 1)), nil, name .. ": the Move attribute ignores it")
		end
		T.truthy(Net.Events.Emote, "the emotes have their own remote")
		T.falsy(
			fs.readFile(Loader.root .. "/src/server/Services/MoveService.luau"):find("EmoteConfig", 1, true),
			"MoveService never plays emotes"
		)
	end)

	---------------------------------------------------------------- data and timing

	local R15_JOINTS: { [string]: boolean } = {}
	for _, joint in MoveConfig.Joints do
		R15_JOINTS[joint] = true
	end

	T.test("emotes: joints, keys, loop lengths, intros and outros are valid", function()
		for _, name in EmoteConfig.List do
			local move = EmoteConfig.Emotes[name]
			T.truthy(move.Loop, name .. " loops until stopped")
			T.eq(move.Slot, "Emote", name .. ": its own slot")
			T.eq(#move.Override, #MoveConfig.Joints, name .. ": owns every R15 joint")
			for _, joint in move.Override do
				T.truthy(R15_JOINTS[joint], name .. " overrides " .. joint)
			end
			local from = move.LoopFrom or 0
			local loopLength = move.Duration - from
			T.truthy(from >= 0 and from <= 1, name .. ": a short intro")
			T.truthy(loopLength >= 1.2 and loopLength <= 4, `{name}: the loop lasts 1.2-4 s ({loopLength})`)
			local last, found = -1, false
			for i, k in move.Keys do
				T.truthy(k.T > last, `{name} key {i}: times rise`)
				last = k.T
				if math.abs(k.T - from) < 1e-6 then
					found = true
				end
				T.truthy(k.Ease == nil or MoveMath.Eases[k.Ease], `{name} key {i}: ease`)
				for joint, e in k.Pose or {} do
					T.truthy(MoveMath.JointIndex[joint], `{name} key {i}: {joint} is a joint`)
					T.eq(#e, 3, `{name} key {i} {joint}: x, y, z`)
				end
			end
			T.truthy(found, name .. ": a key at LoopFrom")
			T.truthy(last <= move.Duration + 1e-9, name .. ": no key after Duration")
			local outro = move.Outro
			T.truthy(outro and #outro >= 2, name .. ": an outro (the finishing pose)")
			local ot = 0
			for i, k in outro do
				T.truthy(k.T > ot, `{name} outro key {i}: times rise`)
				ot = k.T
				for joint in k.Pose or {} do
					T.truthy(MoveMath.JointIndex[joint], `{name} outro {i}: {joint}`)
				end
			end
			T.truthy(ot >= 0.6 and ot <= 2, `{name}: the outro lasts 0.6-2 s ({ot})`)
			local final = outro[#outro]
			T.eq(next(final.Pose or {}), nil, name .. ": the outro ends standing (rest)")
			T.eq(final.Offset, nil, name .. ": with no offset")
			T.eq(move.NeedsTool == true, name == "BlasterSpin", name .. ": only the Blaster Spin needs a tool")
		end
		T.truthy(EmoteConfig.BlasterSpin.Keys[4].Pose.RightGrip, "the Blaster Spin turns the grip")
	end)

	T.test("emotes: loops line up and wrap, outros start from the stop and end at rest", function()
		for _, name in EmoteConfig.List do
			local move = EmoteConfig.Emotes[name]
			local from = move.LoopFrom or 0
			local loopLength = move.Duration - from
			-- the seam: the end of the loop is its start
			local a = MoveMath.evaluate(move, from, 1, {})
			local b = MoveMath.evaluate(move, move.Duration - 1e-4, 1, {})
			local ok, joint = samePose(a, b, 1.5, 0.01)
			T.truthy(ok, `{name}: the loop lines up ({joint})`)
			-- later passes repeat the first
			for _, x in { 0.13, 0.5, 0.91 } do
				local first = MoveMath.evaluate(move, from + loopLength * x, 1, {})
				local third = MoveMath.evaluate(move, from + loopLength * (2 + x), 1, {})
				local same, j = samePose(first, third, 0.01, 1e-3)
				T.truthy(same, `{name}: pass 3 = pass 1 at {x} ({j})`)
			end
			-- an outro from a few stops
			local outroEnd = move.Outro[#move.Outro].T
			for _, x in { 0.2, 0.55, 0.85 } do
				local stopAt = from + loopLength * (1 + x)
				local before = MoveMath.evaluate(move, stopAt - 1e-4, 1, {})
				local at = MoveMath.evaluate(move, stopAt + 1e-4, 1, {}, stopAt)
				local same, j = samePose(before, at, 2, 0.02)
				T.truthy(same, `{name}: the outro starts from the pose at the stop ({j})`)
				local finish = MoveMath.evaluate(move, stopAt + outroEnd, 1, {}, stopAt)
				for jn, cf in finish do
					T.truthy(near(cf, CFrame.identity, 0.5, 0.01), `{name}: {jn} at rest after the outro`)
				end
				T.eq(MoveMath.weight(move, stopAt + outroEnd, stopAt), 0, name .. ": gone after the outro")
				T.truthy(MoveMath.done(move, stopAt + outroEnd, stopAt), name .. ": done after the outro")
				T.near(MoveMath.weight(move, stopAt + outroEnd * 0.4, stopAt), 1, 1e-9, name .. ": the outro plays at full weight")
			end
		end
	end)

	T.test("emotes: the body stays above the floor and no limb goes through it", function()
		for _, name in EmoteConfig.List do
			local move = EmoteConfig.Emotes[name]
			local lowest, lowAt, worst, clipAt = math.huge, "", 0, ""
			for _, stop in { 0.15, 0.6, 0.9 } do
				for _, s in MovePose.timeline(move, 1, stop, 30) do
					local parts = MovePose.solve(Loader, move, s.t, s.stop)
					local y, part = MovePose.lowest(parts)
					if y < lowest then
						lowest, lowAt = y, `t={string.format("%.2f", s.t)} {part}`
					end
					local depth, at = MovePose.clip(parts)
					if depth > worst then
						worst, clipAt = depth, `t={string.format("%.2f", s.t)} {at}`
					end
				end
			end
			T.truthy(lowest >= -0.12, `{name}: above the floor (lowest {string.format("%.2f", lowest)} {lowAt})`)
			T.le(worst, 0.1, `{name}: limbs out of the body ({clipAt})`)
		end
	end)

	---------------------------------------------------------------- the MoveMath features the emotes use

	T.test("emotes: MoveMath LoopFrom, a last key at Duration, Outro, RootPivot, YXZ", function()
		local probe = {
			Name = "Probe",
			Duration = 2,
			Loop = true,
			Slot = "Emote",
			BlendIn = 0,
			BlendOut = 0,
			Override = {},
			MinGap = 0,
			Priority = 0,
			LoopFrom = 1,
			RootPivot = { 0, 3, 0 },
			Keys = {
				{ T = 0, Pose = {} },
				{ T = 1, Ease = "Linear", Pose = { Root = { 90, 0, 0 } } },
				{ T = 2, Ease = "Linear", Pose = { Root = { 90, 360, 0 } } },
			},
			Outro = {
				{ T = 0.5, Ease = "Linear", Pose = { Waist = { 30, 0, 0 } } },
				{ T = 1, Ease = "Linear", Pose = {} },
			},
		}
		-- the intro plays once, the loop repeats from LoopFrom
		local intro = MoveMath.evaluate(probe, 0.5, 1, {})
		local x = intro.Root:ToEulerAnglesYXZ()
		T.near(math.abs(x), 45 * DEG, 1e-3, "half way through the intro")
		local a, b = MoveMath.segment(probe, 2.5)
		T.eq(a, 2, "after Duration: back in the loop (key 2)")
		T.eq(b, 3, "to key 3")
		-- a last key at Duration: a full spin, no ease back
		local quarter = MoveMath.evaluate(probe, 1.25, 1, {})
		local again = MoveMath.evaluate(probe, 3.25, 1, {})
		T.truthy(samePose(quarter, again, 0.01, 1e-3), "the second pass = the first")
		-- the pivot stays put: the point 3 studs up never moves, whatever the turn
		for _, t in { 0.3, 1.1, 1.6 } do
			local pose = MoveMath.evaluate(probe, t, 1, {})
			local p = pose.Root * Vector3.new(0, 3, 0)
			T.truthy((p - Vector3.new(0, 3, 0)).Magnitude < 1e-4, "the RootPivot doesn't move at t=" .. t)
		end
		-- YXZ: lying flat (x 90), the spin turns about the vertical, the body stays flat
		local spun = MoveMath.evaluate(probe, 1.5, 1, {}).Root
		T.near(spun.UpVector.Y, 0, 1e-3, "still lying flat half way round")
		-- the outro: from the pose at the stop (taken the short way) to rest
		local stopAt = 1.5
		local u0 = MoveMath.evaluate(probe, stopAt, 1, {}, stopAt)
		local held = MoveMath.evaluate(probe, stopAt - 1e-6, 1, {})
		T.truthy(near(u0.Root, held.Root, 0.1, 1e-3), "the outro starts at the stop pose")
		local mid = MoveMath.evaluate(probe, stopAt + 0.5, 1, {}, stopAt)
		T.truthy(near(mid.Waist, CFrame.Angles(30 * DEG, 0, 0), 0.1), "the outro's key")
		local finish = MoveMath.evaluate(probe, stopAt + 1, 1, {}, stopAt)
		T.truthy(near(finish.Root, CFrame.identity, 0.1), "rest at the end")
		T.truthy(MoveMath.done(probe, stopAt + 1, stopAt), "done after the outro")
		T.falsy(MoveMath.done(probe, stopAt + 0.9, stopAt), "not before")
		-- the live moves keep their old behaviour (no LoopFrom / Outro / pivot)
		T.eq(MoveMath.compile(MoveConfig.Moves.Carry).LoopStart, 1, "Carry loops from its first key")
		T.eq(MoveMath.compile(MoveConfig.Moves.Carry).OutroTimes, nil, "no outro on the live moves")
	end)
end
