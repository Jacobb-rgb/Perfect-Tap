-- Movement check (docs/plans/MOVEMENT_CHECK_PLAN.md, rollout step 1): the pure
-- rules in MovementLogic (allowed distance per dt and speed, hoverboards,
-- belts, jumps, grace windows, violations, flags, the trusted anchor) and
-- MovementService on fake characters (sampling, serverMoved, isFlagged,
-- trustedPosition with Enforce on / off, the log line, never a kick or a
-- move, cleanup on leave), plus a scan that every server PivotTo of a
-- character calls MovementService.serverMoved.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Enum = roblox.Enum
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MovementConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MovementConfig")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local MovementLogic = Loader.requirePath("ServerScriptService.Server.MovementLogic")
	local MovementService = Loader.requirePath("ServerScriptService.Server.Services.MovementService")
	local ConveyorService = Loader.requirePath("ServerScriptService.Server.Services.ConveyorService")

	local Players = Loader.game:GetService("Players")
	local GRAVITY = 196.2
	local cfg = MovementConfig
	local DT = cfg.SampleInterval
	local WALK = 18 * cfg.SpeedFactor -- maxSpeed on foot at the base walk speed

	local function v(x: number, y: number, z: number): any
		return Vector3.new(x, y, z)
	end

	---------------------------------------------------------------- pure rules

	-- A sample at `position` (walking, 18 studs/s, default jump).
	local function sample(position: any, extra: { [string]: any }?): any
		local s: any = {
			Position = position,
			Character = "char",
			Seated = false,
			Exempt = false,
			WalkSpeed = 18,
			BoardSpeed = 0,
			JumpHeight = 7.2,
			BeltSpeed = 0,
			OnBelt = nil,
		}
		for k, value in extra or {} do
			s[k] = value
		end
		return s
	end

	-- A state past its join window with a first sample at the origin (time 100).
	local function started(): any
		local state = MovementLogic.newState(100 - cfg.JoinGrace - 1)
		MovementLogic.step(state, sample(v(0, 3, 0)), 100, cfg)
		return state
	end

	T.test("Movement: allowed distance grows with dt and speed, plus the slack", function()
		T.near(MovementLogic.maxSpeed(18, 0, cfg), WALK, 1e-9, "walk x SpeedFactor")
		T.near(MovementLogic.allowedHorizontal(WALK, 0.3, 0, cfg), WALK * 0.3 + cfg.Slack, 1e-9, "0.3 s")
		T.near(MovementLogic.allowedHorizontal(WALK, 1, 0, cfg), WALK + cfg.Slack, 1e-9, "1 s")
		T.near(MovementLogic.allowedHorizontal(WALK, -5, 0, cfg), cfg.Slack, 1e-9, "a negative dt is 0")
		T.near(MovementLogic.maxSpeed(26, 0, cfg), 26 * cfg.SpeedFactor, 1e-9, "Miner's Boots 26")
		-- unreadable speeds fall back to the maximum, negative ones to 0
		T.near(MovementLogic.maxSpeed(0 / 0, 0, cfg), cfg.MaxWalkSpeed * cfg.SpeedFactor, 1e-9, "NaN walk")
		T.near(MovementLogic.maxSpeed(math.huge, 0, cfg), cfg.MaxWalkSpeed * cfg.SpeedFactor, 1e-9, "inf walk")
		T.near(MovementLogic.maxSpeed(-4, 0, cfg), 0, 1e-9, "negative walk")
		local limit = WALK * DT + cfg.Slack
		T.le(MovementLogic.excess(v(0, 0, 0), v(limit - 0.01, 0, 0), DT, WALK, 7.2, 0, cfg), 0, "just inside")
		T.lt(0, MovementLogic.excess(v(0, 0, 0), v(limit + 0.01, 0, 0), DT, WALK, 7.2, 0, cfg), "just outside")
		T.le(MovementLogic.excess(v(0, 0, 0), v(0, 0, limit - 0.01), DT, WALK, 7.2, 0, cfg), 0, "any horizontal direction")
		-- through the state: one step of each
		local state = started()
		local outcome = MovementLogic.step(state, sample(v(limit - 0.1, 3, 0)), 100 + DT, cfg)
		T.eq(outcome, "Ok", "inside the limit")
		outcome = MovementLogic.step(state, sample(v(limit * 2 + 1, 3, 0)), 100 + DT * 2, cfg)
		T.eq(outcome, "Violation", "over the limit")
		-- a long gap between samples (server hitch) allows more
		outcome = MovementLogic.step(state, sample(v(limit * 2 + 1 + WALK * 2, 3, 0)), 100 + DT * 2 + 2.2, cfg)
		T.eq(outcome, "Ok", "2.2 s of walking after a hitch")
		-- the walk speed the server sets (gear) counts, and the higher of two samples
		local fast = started()
		local bootsLimit = 26 * cfg.SpeedFactor * DT + cfg.Slack
		T.eq(MovementLogic.step(fast, sample(v(bootsLimit - 0.1, 3, 0), { WalkSpeed = 26 }), 100 + DT, cfg), "Ok", "boots")
		T.eq(
			MovementLogic.step(fast, sample(v(bootsLimit * 2 - 0.2, 3, 0), { WalkSpeed = 18 }), 100 + DT * 2, cfg),
			"Ok",
			"slowed at this sample: the faster one before still counts"
		)
	end)

	T.test("Movement: the hoverboard's speed adds to the walk speed", function()
		T.near(MovementLogic.maxSpeed(18, 35, cfg), (18 + 35) * cfg.SpeedFactor, 1e-9, "walk + board")
		T.near(MovementLogic.maxSpeed(18, 0 / 0, cfg), (18 + cfg.MaxHoverboardSpeed) * cfg.SpeedFactor, 1e-9, "unknown board = max")
		local state = started()
		local boardLimit = (18 + 35) * cfg.SpeedFactor * DT + cfg.Slack
		T.eq(MovementLogic.step(state, sample(v(boardLimit - 0.1, 3, 0), { BoardSpeed = 35 }), 100 + DT, cfg), "Ok", "riding")
		local walker = started()
		T.eq(MovementLogic.step(walker, sample(v(boardLimit - 0.1, 3, 0)), 100 + DT, cfg), "Violation", "the same move on foot")
	end)

	T.test("Movement: standing on a belt adds the fastest belt's speed, asked only for a move over the limit", function()
		T.eq(
			MovementLogic.fastestBelt({ { IsConveyor = true }, { IsConveyor = true, SpeedMult = 2 }, { SpeedMult = 9 } }, 7),
			14,
			"Express"
		)
		T.eq(MovementLogic.fastestBelt({ { IsConveyor = true, SpeedMult = 0 / 0 } }, 7), 7, "a broken multiplier counts as 1")
		T.eq(MovementService.FastestBelt, GameConfig.ConveyorSpeed * 2, "the Express Conveyor runs at 2x")
		T.eq(MovementConfig.BeltGroup, ConveyorService.CollisionGroup, "belt parts are found by their collision group")
		local belt = MovementService.FastestBelt
		local walkLimit = WALK * DT + cfg.Slack
		local beltLimit = (WALK + belt) * DT + cfg.Slack
		local asked = 0
		local onBelt = true
		local function ask(): boolean
			asked += 1
			return onBelt
		end
		local state = started()
		T.eq(MovementLogic.step(state, sample(v(walkLimit - 0.1, 3, 0), { BeltSpeed = belt, OnBelt = ask }), 100 + DT, cfg), "Ok")
		T.eq(asked, 0, "a move inside the walking limit never asks")
		local x = walkLimit - 0.1 + (beltLimit + walkLimit) / 2
		T.eq(MovementLogic.step(state, sample(v(x, 3, 0), { BeltSpeed = belt, OnBelt = ask }), 100 + DT * 2, cfg), "Ok", "on a belt")
		T.eq(asked, 1, "asked once")
		onBelt = false
		x += (beltLimit + walkLimit) / 2
		T.eq(
			MovementLogic.step(state, sample(v(x, 3, 0), { BeltSpeed = belt, OnBelt = ask }), 100 + DT * 3, cfg),
			"Violation",
			"off the belt"
		)
		T.eq(asked, 2, "asked once more (the trusted anchor reuses the answer)")
		onBelt = true
		x += beltLimit + 1
		T.eq(
			MovementLogic.step(state, sample(v(x, 3, 0), { BeltSpeed = belt, OnBelt = ask }), 100 + DT * 4, cfg),
			"Violation",
			"faster than a belt"
		)
	end)

	T.test("Movement: upward moves up to the Humanoid's jump height + UpSlack (+ climbing), falling is free", function()
		T.near(MovementLogic.jumpHeight(true, 50, 7.2, GRAVITY, cfg), 50 * 50 / (2 * GRAVITY), 1e-9, "JumpPower 50")
		T.near(MovementLogic.jumpHeight(false, 50, 7.2, GRAVITY, cfg), 7.2, 1e-9, "JumpHeight")
		T.near(MovementLogic.jumpHeight(false, 50, 12, GRAVITY, cfg), 12, 1e-9, "a higher JumpHeight")
		T.near(MovementLogic.jumpHeight(true, 0 / 0, 7.2, GRAVITY, cfg), cfg.DefaultJumpHeight, 1e-9, "NaN power")
		T.near(MovementLogic.jumpHeight(true, 50, 7.2, 0, cfg), cfg.DefaultJumpHeight, 1e-9, "no gravity")
		T.near(MovementLogic.jumpHeight(false, 50, 1e9, GRAVITY, cfg), cfg.MaxJumpHeight, 1e-9, "capped")
		local jump = 7.2
		local up = jump + cfg.UpSlack + WALK * DT * cfg.ClimbPerStud
		T.near(MovementLogic.allowedUp(jump, WALK, DT, cfg), up, 1e-9, "allowed rise")
		local state = started()
		T.eq(MovementLogic.step(state, sample(v(0, 3 + up - 0.1, 0)), 100 + DT, cfg), "Ok", "a jump")
		T.eq(MovementLogic.step(state, sample(v(0, -300, 0)), 100 + DT * 2, cfg), "Ok", "falling any distance")
		T.eq(MovementLogic.step(state, sample(v(0, -300 + up + 0.5, 0)), 100 + DT * 3, cfg), "Violation", "rising too high")
		local springy = started()
		T.eq(
			MovementLogic.step(springy, sample(v(0, 3 + up + 4, 0), { JumpHeight = jump + 5 }), 100 + DT, cfg),
			"Ok",
			"a higher jump from the Humanoid allows more"
		)
	end)

	T.test("Movement: grace windows (server move, new character, joining, seated, knocked over)", function()
		-- joining: the first JoinGrace seconds only reset
		local joining = MovementLogic.newState(100)
		T.eq(MovementLogic.step(joining, sample(v(0, 3, 0)), 100.1, cfg), "Start")
		T.eq(MovementLogic.step(joining, sample(v(300, 3, 0)), 100.4, cfg), "Grace", "streaming in")
		T.eq(MovementLogic.step(joining, sample(v(600, 3, 0)), 100 + cfg.JoinGrace - 0.1, cfg), "Grace")
		T.eq(MovementLogic.step(joining, sample(v(900, 3, 0)), 100 + cfg.JoinGrace + 0.2, cfg), "Violation", "after the window")
		-- a server move
		local state = started()
		MovementLogic.serverMoved(state, 100.1, cfg)
		T.eq(state.Trusted, nil, "the live position until the next sample")
		T.eq(MovementLogic.step(state, sample(v(500, 3, 0)), 100 + DT, cfg), "Grace", "teleported")
		T.eq(MovementLogic.step(state, sample(v(500, 3, 0)), 100.1 + cfg.ServerMoveGrace - 0.05, cfg), "Grace")
		T.eq(state.Trusted, v(500, 3, 0), "the anchor starts at the new place")
		T.eq(MovementLogic.step(state, sample(v(510, 3, 0)), 100.1 + cfg.ServerMoveGrace + 0.25, cfg), "Ok", "walking on")
		T.eq(MovementLogic.step(state, sample(v(700, 3, 0)), 100.1 + cfg.ServerMoveGrace + 0.55, cfg), "Violation", "grace over")
		T.eq(#state.Violations, 1)
		-- a new character starts over
		local respawn = started()
		T.eq(MovementLogic.step(respawn, sample(v(400, 3, 0), { Character = "new" }), 100 + DT, cfg), "Grace", "respawned")
		-- seated: no check
		local seated = started()
		T.eq(MovementLogic.step(seated, sample(v(80, 3, 0), { Seated = true }), 100 + DT, cfg), "Skip")
		T.eq(#seated.Violations, 0)
		T.eq(MovementLogic.step(seated, sample(v(82, 3, 0)), 100 + DT * 2, cfg), "Ok", "standing up where the seat went")
		-- FallingDown / Ragdoll / Physics: skipped within the budget only
		local flung = started()
		local now = 100
		local x = 0
		local skipped, checked = 0, 0
		for _ = 1, 30 do
			now += DT
			x += 40
			local outcome = MovementLogic.step(flung, sample(v(x, 3, 0), { Exempt = true }), now, cfg)
			if outcome == "Skip" then
				skipped += 1
			elseif outcome == "Violation" then
				checked += 1
			end
		end
		T.eq(skipped, math.floor(cfg.StateGraceBudget / DT + 1e-9), "skipped for the budget")
		T.lt(0, checked, "a state held past its budget is checked again (the client reports it)")
		-- the budget comes back after the window
		now += cfg.StateGraceWindow + 1
		T.eq(MovementLogic.step(flung, sample(v(x, 3, 0), { Exempt = true }), now, cfg), "Skip", "budget refilled")
	end)

	T.test("Movement: 3 violations within 10 s flag for 30 s; old violations expire", function()
		local state = started()
		local now, x = 100, 0
		local function jumpAhead(seconds: number): (string, boolean)
			now += seconds
			x += 100
			local outcome, flagged = MovementLogic.step(state, sample(v(x, 3, 0)), now, cfg)
			return outcome, flagged
		end
		local _, f1 = jumpAhead(DT)
		local _, f2 = jumpAhead(DT)
		T.falsy(f1 or f2, "two violations: not yet")
		T.falsy(MovementLogic.isFlagged(state, now))
		local outcome, f3 = jumpAhead(DT)
		T.eq(outcome, "Violation")
		T.truthy(f3, "the third flags")
		T.truthy(MovementLogic.isFlagged(state, now + cfg.FlagSeconds - 0.1), "for FlagSeconds")
		T.falsy(MovementLogic.isFlagged(state, now + cfg.FlagSeconds + 0.1), "then it expires")
		T.eq(#state.Violations, 0, "a flag starts the count over")
		-- violations spread wider than the window never flag
		local slow = started()
		local t = 100
		for i = 1, 6 do
			t += cfg.ViolationWindow / 2 + 0.1
			local _, flagged = MovementLogic.step(slow, sample(v(i * 1000, 3, 0)), t, cfg)
			T.falsy(flagged, "violation " .. i .. " alone in its window")
			-- an honest sample in between
			t += DT
			MovementLogic.step(slow, sample(v(i * 1000, 3, 0)), t, cfg)
		end
		T.falsy(MovementLogic.isFlagged(slow, t))
	end)

	T.test("Movement: the trusted anchor stays behind a teleport until the walk there would have taken that long", function()
		local state = started()
		T.eq(MovementLogic.trusted(state, 100), nil, "not flagged: nil (= live)")
		local now = 100
		for i = 1, 3 do
			now += DT
			MovementLogic.step(state, sample(v(i * 200, 3, 0)), now, cfg)
		end
		T.truthy(MovementLogic.isFlagged(state, now))
		T.eq(MovementLogic.trusted(state, now), v(0, 3, 0), "the last good sample")
		-- standing still far away: the anchor only follows once the time covers the walk
		now += 1
		MovementLogic.step(state, sample(v(600, 3, 0)), now, cfg)
		T.eq(MovementLogic.trusted(state, now), v(0, 3, 0), "600 studs need more than 1.9 s")
		local need = (600 - cfg.Slack) / WALK
		now = 100 + need + 0.2
		MovementLogic.step(state, sample(v(600, 3, 0)), now, cfg)
		T.eq(MovementLogic.trusted(state, now), v(600, 3, 0), "caught up")
		-- an honest walk keeps the anchor on the live position
		local walker = started()
		for i = 1, 10 do
			MovementLogic.step(walker, sample(v(i * 5, 3, 0)), 100 + i * DT, cfg)
			T.eq(walker.Trusted, v(i * 5, 3, 0), "follows step " .. i)
		end
	end)

	T.test("Movement: 5 flags within 5 minutes ask for one log line", function()
		local state = started()
		local now, x = 100, 0
		local logs = 0
		for _ = 1, cfg.FlagsToLog * cfg.ViolationsToFlag * 2 do
			now += DT
			x += 100
			local _, _, log = MovementLogic.step(state, sample(v(x, 3, 0)), now, cfg)
			if log then
				logs += 1
			end
		end
		T.eq(logs, 2, "one line per FlagsToLog flags")
		T.eq(state.Logs, 2)
		T.lt(0, state.LoggedWorst, "the worst move goes in the line")
		-- flags spread over more than FlagLogWindow never log
		local spread = started()
		local t = 100
		local logged = false
		for i = 1, cfg.FlagsToLog * 2 do
			t += cfg.FlagLogWindow / (cfg.FlagsToLog - 1) + 1
			for j = 1, cfg.ViolationsToFlag do
				local _, _, log = MovementLogic.step(spread, sample(v(i * 10000 + j * 100, 3, 0)), t + j * DT, cfg)
				logged = logged or log
			end
		end
		T.falsy(logged, "never 5 flags in one window")
	end)

	---------------------------------------------------------------- the service

	local function fakePlayer(userId: number): any
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(0, 3, 0)
		local humanoid: any = {
			Health = 100,
			WalkSpeed = 18,
			UseJumpPower = true,
			JumpPower = 50,
			JumpHeight = 7.2,
			SeatPart = nil,
			Sit = false,
			State = Enum.HumanoidStateType.Running,
		}
		humanoid.GetState = function(self)
			return self.State
		end
		local p: any = { UserId = userId, Name = "Mover" .. userId, Parent = Players, attrs = {}, kicks = 0, pivots = 0 }
		local character: any = {}
		character.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		character.FindFirstChildOfClass = function(_, className: string)
			return if className == "Humanoid" then humanoid else nil
		end
		character.FindFirstChild = function(_, name: string)
			return if name == "HumanoidRootPart" then root else nil
		end
		character.PivotTo = function()
			p.pivots += 1
		end
		p.Character = character
		p.humanoid = humanoid
		p.root = root
		p.Kick = function()
			p.kicks += 1
		end
		p.at = function(x: number, y: number, z: number)
			root.CFrame = CFrame.new(x, y, z)
		end
		return p
	end

	local function withService(name: string, fn: (any) -> ())
		T.test(name, function()
			local w: any = { now = 1000, lines = {}, belt = false }
			MovementService._test.reset()
			MovementService._test.setClock(function()
				return w.now
			end)
			MovementService._test.setGravity(function()
				return GRAVITY
			end)
			MovementService._test.setLog(function(text: string)
				table.insert(w.lines, text)
			end)
			MovementService._test.setBeltCheck(function()
				return w.belt
			end)
			MovementService._test.setBoardSpeed(nil)
			w.sample = function(p: any, seconds: number?)
				w.now += seconds or DT
				MovementService._test.sample(p, w.now)
			end
			local enforce = MovementConfig.Enforce
			local ok, err = pcall(fn, w)
			MovementConfig.Enforce = enforce
			MovementService._test.reset()
			if not ok then
				error(err, 0)
			end
		end)
	end

	-- A player sampled once at the origin, past the join window.
	local function joined(w: any, userId: number): any
		local p = fakePlayer(userId)
		w.sample(p, 0)
		w.now += cfg.JoinGrace + 0.1
		w.sample(p)
		return p
	end

	withService("MovementService: samples the character, counts violations, flags, never kicks or moves anyone", function(w)
		local p = joined(w, 9001)
		local state = MovementService._test.state(p)
		T.truthy(state, "state for a player in Players")
		T.eq(state.Last, v(0, 3, 0))
		p.at(5, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 0, "walking")
		T.falsy(MovementService.isFlagged(p))
		for i = 1, 3 do
			p.at(5 + i * 100, 3, 0)
			w.sample(p)
		end
		T.eq(MovementService.stats().Violations, 3)
		T.truthy(MovementService.isFlagged(p), "flagged")
		-- keep teleporting: 5 flags write one line with the UserId
		for i = 1, cfg.FlagsToLog * cfg.ViolationsToFlag do
			p.at(1000 + i * 100, 3, 0)
			w.sample(p)
		end
		T.eq(#w.lines, 1, "one log line")
		T.truthy(w.lines[1]:find("9001", 1, true), "with the UserId")
		T.eq(MovementService.stats().Logs, 1)
		T.eq(p.kicks, 0, "never a kick")
		T.eq(p.pivots, 0, "never a pull-back")
		-- a dead character is not sampled
		p.humanoid.Health = 0
		local before = MovementService.stats().Samples
		w.sample(p)
		T.eq(MovementService.stats().Samples, before, "dead: skipped")
	end)

	withService("MovementService: walk speed, jump and hoverboard come from the server's character", function(w)
		local p = joined(w, 9002)
		local boardLimit = (18 + 35) * cfg.SpeedFactor * DT + cfg.Slack
		-- riding a board whose speed the hoverboard service knows
		p.attrs[cfg.HoverboardAttribute] = "TerraForgeCustom"
		MovementService._test.setBoardSpeed(function(player)
			return if player == p then 35 else 0
		end)
		p.at(boardLimit - 0.2, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 0, "riding")
		-- no speed source: an unknown board counts as the fastest
		MovementService._test.setBoardSpeed(nil)
		local maxLimit = (18 + cfg.MaxHoverboardSpeed) * cfg.SpeedFactor * DT + cfg.Slack
		p.at(boardLimit - 0.2 + maxLimit - 0.2, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 0, "unknown board = MaxHoverboardSpeed")
		-- off the board: the same distance is too far
		p.attrs[cfg.HoverboardAttribute] = nil
		w.sample(p) -- standing still (the board's speed still counts for this pair)
		p.at(boardLimit - 0.2 + maxLimit - 0.2 + boardLimit - 0.2, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "on foot")
		-- the jump: JumpPower with UseJumpPower, else JumpHeight
		local x = p.root.CFrame.Position.X
		local up = 50 * 50 / (2 * GRAVITY) + cfg.UpSlack + WALK * DT * cfg.ClimbPerStud
		w.sample(p)
		p.at(x, 3 + up - 0.2, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "a JumpPower jump")
		p.humanoid.UseJumpPower = false
		p.humanoid.JumpHeight = 20
		p.at(x, -10, 0)
		w.sample(p)
		w.sample(p)
		p.at(x, -10 + 20 + cfg.UpSlack + WALK * DT - 0.2, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "a JumpHeight jump")
		-- a belt under the feet (only looked at for a move over the limit)
		w.belt = true
		local walkLimit = WALK * DT + cfg.Slack
		p.at(x + walkLimit + 2, 4, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "carried by a belt")
		w.belt = false
		p.at(x + walkLimit * 2 + 4, 4, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 2, "no belt")
	end)

	withService("MovementService: grace after serverMoved, a respawn, joining, seated and knocked over", function(w)
		local p = fakePlayer(9003)
		w.sample(p, 0)
		p.at(300, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 0, "joining")
		w.now += cfg.JoinGrace
		w.sample(p)
		-- the server moves the character (teleport bar, sendHome, lift-out, push-out)
		MovementService.serverMoved(p)
		p.at(-400, 3, 50)
		w.sample(p)
		w.sample(p, 1)
		T.eq(MovementService.stats().Violations, 0, "teleported by the server")
		w.now += cfg.ServerMoveGrace
		p.at(-200, 3, 50)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "after the grace a jump counts")
		-- a new character (respawn)
		local character = p.Character
		p.Character = table.clone(character)
		p.at(0, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "respawned")
		-- seated
		p.humanoid.SeatPart = Instance.new("Seat")
		p.at(90, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "seated")
		p.humanoid.SeatPart = nil
		w.sample(p)
		-- knocked over
		p.humanoid.State = Enum.HumanoidStateType.FallingDown
		p.at(160, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 1, "falling down")
		p.humanoid.State = Enum.HumanoidStateType.Running
		p.at(260, 3, 0)
		w.sample(p)
		T.eq(MovementService.stats().Violations, 2, "running again")
	end)

	withService("MovementService: trustedPosition is live with Enforce off, the last good sample when flagged with Enforce on", function(w)
		local p = joined(w, 9004)
		for i = 1, 3 do
			p.at(i * 150, 3, 0)
			w.sample(p)
		end
		T.truthy(MovementService.isFlagged(p))
		MovementConfig.Enforce = false
		T.eq(MovementService.trustedPosition(p), v(450, 3, 0), "Enforce off: live (rollout step 1)")
		T.eq(MovementService.rangeOrigin(p, v(7, 7, 7)), v(7, 7, 7), "rangeOrigin: the caller's live position")
		MovementConfig.Enforce = true
		T.eq(MovementService.trustedPosition(p), v(0, 3, 0), "Enforce on: the last good sample")
		T.eq(MovementService.rangeOrigin(p, v(7, 7, 7)), v(0, 3, 0), "rangeOrigin: the last good sample")
		T.eq(MovementService.rangeOrigin(nil, v(7, 7, 7)), v(7, 7, 7), "rangeOrigin: no player")
		-- the flag runs out: live again
		w.now += cfg.FlagSeconds + 1
		T.eq(MovementService.trustedPosition(p), v(450, 3, 0), "flag expired")
		-- an honest player is never affected
		local honest = joined(w, 9005)
		honest.at(4, 3, 0)
		w.sample(honest)
		T.eq(MovementService.trustedPosition(honest), v(4, 3, 0), "not flagged: live")
		-- a server move while flagged uses the live position until the next sample
		w.sample(p) -- (after a long gap the first jump would still be in reach)
		for i = 1, 3 do
			p.at(1000 + i * 150, 3, 0)
			w.sample(p)
		end
		T.eq(MovementService.trustedPosition(p), v(450, 3, 0), "flagged again")
		MovementService.serverMoved(p)
		p.at(-50, 3, -50)
		T.eq(MovementService.trustedPosition(p), v(-50, 3, -50), "moved by the server")
		-- no character: nil
		p.Character = nil
		T.eq(MovementService.trustedPosition(p), nil)
	end)

	withService("MovementService: state only for players in Players, cleaned on leave", function(w)
		local p = joined(w, 9006)
		T.truthy(MovementService._test.state(p))
		MovementService._test.forget(p)
		T.eq(MovementService._test.state(p), nil, "PlayerRemoving clears it")
		T.falsy(MovementService.isFlagged(p))
		-- events after leaving never bring the state back
		p.Parent = nil
		MovementService.serverMoved(p)
		w.sample(p)
		T.eq(MovementService._test.state(p), nil, "a player no longer in Players")
		T.eq(MovementService.trustedPosition(p), v(0, 3, 0), "the live position, no state")
	end)

	---------------------------------------------------------------- config and wiring

	T.test("Movement: config switches for rollout step 1, limits match the game", function()
		T.eq(MovementConfig.Enforce, false, "step 1: logging only")
		T.eq(MovementConfig.PullBack, false, "no pull-back yet")
		T.eq(MovementConfig.BeamLos, true, "beam line of sight on")
		local huge = Bonuses.walkSpeed({ WalkSpeed = 1e6, WalkSpeedPct = 1e6 } :: any)
		T.le(huge, MovementConfig.MaxWalkSpeed, "no walk speed beats MaxWalkSpeed")
	end)

	T.test("Movement: every server PivotTo of a character calls MovementService.serverMoved", function()
		local root = Loader.root .. "/src/server"
		local found = 0
		local function scan(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					scan(path)
				elseif entry:match("%.luau$") then
					local lines = string.split(fs.readFile(path), "\n")
					for i, line in lines do
						if line:find("[Cc]haracter:PivotTo%(") and not line:match("^%s*%-%-") then
							found += 1
							local near = (lines[i - 1] or "") .. (lines[i + 1] or "") .. (lines[i + 2] or "")
							T.truthy(near:find("MovementService.serverMoved(", 1, true), path .. ":" .. i .. " calls serverMoved")
						end
					end
				end
			end
		end
		scan(root)
		T.le(4, found, "teleport bar, sendHome, lift-out, grotto push-out (+ the mine elevator once it lands)")
	end)
end
