--[[
	The weapon cases (Builders/CaseBuilder) and the crate-opening cinematic's
	stage (Builders/CrateOpeningStage): every level builds within a part
	budget with mobile-safe parts, the blaster is shown at its hero size, the
	whole 10 seconds pose without errors or NaN, the timeline (case lands,
	bursts, the blaster appears only after the burst), the camera stays in the
	room, two builds pose the same (deterministic), and with Reduce motion nothing
	flashes, frame by frame through the burst and the reveal.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local Color3 = roblox.Color3
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local CaseBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.CaseBuilder")
	local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")

	local ORIGIN = CFrame.new(0, 3000, 0)
	local CASE_BUDGET = 260
	-- raised on purpose (owner 2026-11-06: "more animations, a bigger wow"; main had about 500): LV 10 is 1110.
	-- A Studio check on a phone still has to back it (budget-policy: measured, phones still smooth).
	local STAGE_BUDGET = 1120

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function finite(v: any): boolean
		return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e7 and math.abs(v.Y) < 1e7 and math.abs(v.Z) < 1e7
	end

	local function build(level: number, calm: boolean?): (any, any)
		local holder = Instance.new("Model")
		local ore = BlasterData.vaultOre(level)
		local stage = Stage.build(holder, ORIGIN, level, ore, Stage.blasterModel(level, ore), calm)
		return stage, holder
	end

	-- The named parts and lights of a stage.
	local function named(holder: any, name: string): { any }
		local out = {}
		for _, d in holder:GetDescendants() do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		T.truthy(#out > 0, "the stage has " .. name)
		return out
	end

	-- How much a part shows now: 0 when hidden (parked far below) or see-through.
	local function shows(p: any): number
		return if p.CFrame.Position.Y < -1000 then 0 else 1 - p.Transparency
	end

	T.test("CrateOpening: every level's case builds, mobile-safe, within budget", function()
		for level = 1, BlasterData.MaxLevel do
			local m = Instance.new("Model")
			local case = CaseBuilder.build(m, CFrame.new(), level, Color3.fromRGB(255, 80, 170))
			T.truthy(case.Base and case.Lid and case.Seam and case.Inside, "level " .. level .. " parts")
			T.truthy(case.Height > case.BaseHeight, "the lid sits on the base")
			local list = parts(m)
			T.le(#list, CASE_BUDGET, "level " .. level .. " case parts")
			for _, p in list do
				T.falsy(p.CanCollide, p.Name .. " no collision")
				T.falsy(p.CastShadow, p.Name .. " no shadow")
				T.truthy(p.Anchored, p.Name .. " anchored")
			end
		end
		-- higher levels get more detail
		local low, high = Instance.new("Model"), Instance.new("Model")
		CaseBuilder.build(low, CFrame.new(), 2, Color3.fromRGB(255, 80, 170))
		CaseBuilder.build(high, CFrame.new(), 10, Color3.fromRGB(255, 80, 170))
		T.lt(#parts(low), #parts(high), "level 10 has more detail than level 2")
	end)

	T.test("CrateOpening: the whole opening follows the blaster's colour", function()
		local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
		local function hueGap(a: number, b: number): number
			local gap = math.abs(a - b)
			return math.min(gap, 1 - gap)
		end
		local seen = {}
		for level = 1, BlasterData.MaxLevel do
			local ore = BlasterData.vaultOre(level)
			local color = BlasterBuilder.colors(level, ore).Color
			local m = Instance.new("Model")
			local case = CaseBuilder.build(m, CFrame.new(), level, color)
			T.eq(case.Glow, color, "level " .. level .. ": the crate in its blaster's colour")
			T.truthy(case.Core and case.LidA and case.LidB and #case.Panels == 4, "a core, two lid halves, four walls")
			seen[string.format("%.2f", color:ToHSV())] = true
			-- the stage: every coloured part but the blaster's own, at every moment, is in its hue
			local stage, holder = build(level)
			local hue = color:ToHSV()
			local blaster = holder:FindFirstChild("Blaster", true)
			for _, t in { 0.1, 1.1, 2.5, 3, 4.3, stage.Hold } do
				stage.update(t)
				for _, p in parts(holder) do
					if not p:IsDescendantOf(blaster) then
						local h, s = p.Color:ToHSV()
						if s > 0.1 then
							T.le(
								hueGap(h, hue),
								0.015,
								string.format("level %d %s at %.1f: hue %.3f, its blaster %.3f", level, p.Name, t, h, hue)
							)
						end
					end
				end
			end
			-- the lights too
			for _, d in holder:GetDescendants() do
				if d:IsA("Light") then
					local h, s = d.Color:ToHSV()
					if s > 0.1 then
						T.le(hueGap(h, hue), 0.015, "level " .. level .. " light")
					end
				end
			end
		end
		local kinds = 0
		for _ in seen do
			kinds += 1
		end
		T.truthy(kinds >= 5, "really different colours: " .. kinds)
		-- a blaster in another ore than its case's (an older save): its own colour, the shades its hue
		local other = BlasterBuilder.colors(5, "Sapphire").Color
		T.truthy(other ~= BlasterBuilder.colors(5, BlasterData.vaultOre(5)).Color, "another ore, another colour")
		local body = CaseBuilder.shades(Color3.fromRGB(70, 160, 255))
		T.lt(hueGap((body:ToHSV()), (Color3.fromRGB(70, 160, 255):ToHSV())), 0.01, "the dark body in the same hue")
	end)

	T.test("CrateOpening: the blaster is shown centered at its hero size", function()
		for level = 1, BlasterData.MaxLevel do
			local model = Stage.blasterModel(level, BlasterData.vaultOre(level))
			local lo, hi = { math.huge, math.huge }, { -math.huge, -math.huge }
			local count = 0
			for _, p in parts(model) do
				count += 1
				T.truthy(p.Anchored, "anchored")
				T.eq(p:FindFirstChildOfClass("WeldConstraint"), nil, "no welds")
				local pos = p.CFrame.Position
				local r = math.min(p.Size.X, p.Size.Y, p.Size.Z) / 2
				lo = { math.min(lo[1], pos.Y - r), math.min(lo[2], pos.Z - r) }
				hi = { math.max(hi[1], pos.Y + r), math.max(hi[2], pos.Z + r) }
			end
			T.truthy(count > 5, "level " .. level .. " has parts")
			local height, length = hi[1] - lo[1], hi[2] - lo[2]
			T.le(length, Stage.BlasterLength * 1.05, "level " .. level .. " not too long")
			T.le(height, Stage.BlasterHeight * 1.05, "level " .. level .. " not too tall")
			T.truthy(length > Stage.BlasterLength * 0.6 or height > Stage.BlasterHeight * 0.6, "level " .. level .. " big enough")
			T.near((hi[2] + lo[2]) / 2, 0, 1.2, "level " .. level .. " centered")
		end
	end)

	T.test("CrateOpening: every level's stage stays within its budgets", function()
		for level = 1, BlasterData.MaxLevel do
			local _, holder = build(level)
			T.le(#parts(holder), STAGE_BUDGET, "level " .. level .. " stage parts")
			local lights = 0
			for _, d in holder:GetDescendants() do
				if d:IsA("Light") then
					lights += 1
				end
			end
			T.le(lights, 4, "level " .. level .. ": at most 4 lights")
		end
	end)

	T.test("CrateOpening: the stage goes into the world only when it is whole", function()
		local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
		local holder = Instance.new("Model")
		local block = Geo.block
		local calls, early = 0, 0
		Geo.block = function(...)
			calls += 1
			if #holder:GetChildren() > 0 then
				early += 1
			end
			return block(...)
		end
		local ore = BlasterData.vaultOre(5)
		local ok, stage = pcall(Stage.build, holder, ORIGIN, 5, ore, Stage.blasterModel(5, ore))
		Geo.block = block
		T.truthy(ok, tostring(stage))
		T.lt(100, calls, "the parts go through Geo.block")
		T.eq(early, 0, "none of them is made inside the world")
		T.eq(stage.Root.Parent, holder, "then it goes in")
		T.lt(stage.Hold, stage.Duration, "it is posed")
	end)

	T.test("CrateOpening: the stage poses the whole opening without errors or NaN", function()
		local stage, holder = build(7)
		local list = parts(holder)
		local t = 0
		while t <= stage.Duration + 0.5 do
			stage.update(t)
			local cf, fov = stage.camera(t)
			T.truthy(finite(cf.Position), "camera at " .. t)
			T.truthy(fov > 20 and fov < 80, "fov at " .. t)
			for _, p in list do
				if not finite(p.CFrame.Position) or not finite(p.Size) then
					error(string.format("%s broken at t=%.2f", p:GetFullName(), t))
				end
			end
			t += 0.1
		end
	end)

	T.test("CrateOpening: his timeline, second by second", function()
		T.eq(Stage.T_PREP, 0.3, "the scene")
		T.eq(Stage.T_LAND, 1.0, "the portal and the arrival")
		T.eq(Stage.T_IMPACT, 1.4, "the impact")
		T.eq(Stage.T_ORBIT, 2.0, "the orbit")
		T.eq(Stage.T_BURST, 2.8, "charging")
		T.eq(Stage.T_OPEN, 3.3, "the explosive opening")
		T.eq(Stage.T_RISE_END, 4.0, "the blaster flies in")
		T.eq(Stage.T_SETTLE, 5.2, "the hero moment (slower: owner 2026-11-06)")
		T.eq(Stage.T_HOLD, 6.3, "the words")
		T.eq(Stage.Duration, 7.3, "collected")
	end)

	T.test("CrateOpening: the portal opens, the crate lands, the lid flies, the walls fold", function()
		local stage, holder = build(10)
		local function lowestOf(model: any): number
			local lo = math.huge
			for _, p in parts(model) do
				lo = math.min(lo, p.CFrame.Position.Y - p.Size.Y / 2)
			end
			return lo - ORIGIN.Position.Y
		end
		local function middleOf(model: any): any
			local sum = Vector3.zero
			local list = parts(model)
			for _, p in list do
				sum += p.CFrame.Position
			end
			return ORIGIN:PointToObjectSpace(sum / #list)
		end
		local lidA = holder:FindFirstChild("LidA", true)
		local lidB = holder:FindFirstChild("LidB", true)
		local front = holder:FindFirstChild("Front", true)
		stage.update(Stage.T_BURST - 0.01)
		local closedFront = middleOf(front)
		local closedA = middleOf(lidA)
		stage.update(Stage.T_BURST + 0.3)
		T.lt(closedA.Y + 2, middleOf(lidA).Y, "the lid flies up")
		T.lt(middleOf(lidA).Z, closedA.Z - 2, "half A to its side")
		T.lt(0, middleOf(lidB).Z, "half B to the other")
		T.lt(closedFront.X + 0.5, middleOf(front).X, "the front wall folds out")
		stage.update(Stage.T_RISE_END + 0.1)
		T.lt(lowestOf(lidA), -1000, "the crate is gone when the reveal starts")
		-- the portal: a neon ring high up from T_PREP, gone by the orbit's end
		local function high(t: number): number
			stage.update(t)
			local n = 0
			for _, p in parts(holder) do
				local rel = ORIGIN:PointToObjectSpace(p.CFrame.Position)
				if
					p.Material == Enum.Material.Neon
					and p.Size.X < 1
					and rel.Y > Stage.PortalHeight - 3
					and rel.Y < Stage.PortalHeight + 3
				then
					n += 1
				end
			end
			return n
		end
		T.lt(50, high(0.7), "the portal is open: " .. high(0.7))
		T.lt(high(Stage.T_ORBIT + 0.1), 20, "and closed again")
	end)

	T.test("CrateOpening: the end: close, the blaster on the left like the secret ore, its barrels turning", function()
		local stage, holder = build(10)
		local blaster = holder:FindFirstChild("Blaster", true)
		local gun = parts(blaster)
		local function middle(): any
			local sum = Vector3.zero
			for _, p in gun do
				sum += p.CFrame.Position
			end
			return sum / #gun
		end
		stage.update(stage.Hold, 1)
		local cf = stage.camera(stage.Hold, 1)
		local seen = cf:PointToObjectSpace(middle())
		T.lt(seen.X, -1, "on the left of the screen: " .. seen.X)
		T.lt(-seen.Z, 10, "close: " .. -seen.Z)
		local hero = stage.camera(stage.Reveal + 0.6)
		stage.update(stage.Reveal + 0.6)
		T.lt(math.abs(hero:PointToObjectSpace(middle()).X), 0.6, "in the middle at the hero moment")
		-- the barrels turn while it waits, the rest of the gun holds still
		local spinning, still = nil, nil
		for _, p in gun do
			if p:GetAttribute("Spins") == true then
				spinning = p
			else
				still = p
			end
		end
		T.truthy(spinning and still, "barrels and body")
		local function local_(p: any, t: number, idle: number): any
			stage.update(t, idle)
			return blaster:IsA("Model") and p.CFrame.Position
		end
		local a = local_(spinning, stage.Hold, 1)
		local b = local_(spinning, stage.Hold, 1.2)
		T.lt(0.01, (a - b).Magnitude, "the barrels turn")
		-- its burst of shots has its moments in the hero part, the sound follows them
		T.lt(stage.Reveal, stage.ShotTimes[1], "the burst after the reveal")
		T.lt(stage.ShotTimes[#stage.ShotTimes], Stage.T_SETTLE, "and before it settles")
		-- gone at the end
		stage.update(stage.Duration)
		T.lt(gun[1].CFrame.Position.Y - ORIGIN.Position.Y, -1000, "collected")
	end)

	T.test("CrateOpening: the crate's strips pulse under 3 times a second", function()
		local stage, holder = build(7)
		local strip = holder:FindFirstChild("Case", true):FindFirstChild("Base", true)
		local lit = nil
		for _, p in parts(strip) do
			if p.Material == Enum.Material.Neon and p.Name ~= "Inside" and p.Name ~= "Seam" then
				lit = p
				break
			end
		end
		T.truthy(lit, "a strip")
		local times = {}
		local last, rising = nil, nil
		local t = Stage.T_IMPACT
		while t < Stage.T_BURST do
			stage.update(t)
			local a = lit.Transparency
			if last and a ~= last then
				local up = a > last
				if rising ~= nil and up ~= rising then
					table.insert(times, t)
				end
				rising = up
			end
			last = a
			t += 1 / 240
		end
		T.lt(1, #times, "it does pulse")
		for i = 3, #times do
			-- (two turning points = one whole pulse)
			T.le(1 / (times[i] - times[i - 2]), 3, string.format("pulses a second at %.2f", times[i]))
		end
	end)

	-- Every frame from `from` to `to` at 60 frames a second.
	local function posed(stage: any, from: number, to: number, each: (t: number) -> ())
		for frame = math.floor(from * 60), math.ceil(to * 60) do
			local t = frame / 60
			stage.update(t)
			each(t)
		end
	end

	T.test("CrateOpening: Reduce motion: no shake, no blur, nothing that only flashes", function()
		local FLASHES = { "Flare", "RevealRing", "BurstRing", "EnergyWave", "FloorRing", "ShotGlow" }
		local function each(holder: any, fn: (name: string, list: { any }) -> ())
			for _, name in FLASHES do
				fn(name, named(holder, name))
			end
		end
		for _, level in { 5, 10 } do
			local stage, holder = build(level, true)
			local label = "level " .. level .. " "
			posed(stage, Stage.T_LAND - 0.02, Stage.T_SETTLE + 1, function(t: number)
				T.eq(stage.blur(t), 0, label .. "blur")
				T.eq(stage.shake(t), Vector3.zero, label .. "shake")
				each(holder, function(name: string, list: { any })
					for _, p in list do
						T.eq(shows(p), 0, string.format("%s%s at %.3f", label, name, t))
					end
				end)
			end)
		end
		-- (the normal opening has them all: what this looks for is really there)
		local stage, holder = build(10)
		local seen = {}
		posed(stage, Stage.T_LAND - 0.02, Stage.T_SETTLE + 1, function()
			each(holder, function(name: string, list: { any })
				seen[name] = seen[name] or shows(list[1]) > 0
			end)
		end)
		for _, name in FLASHES do
			T.truthy(seen[name], "the normal opening shows " .. name)
		end
		T.lt(0, stage.blur(stage.Burst + 0.02), "the normal opening's blur")
		T.truthy(stage.shake(stage.Burst + 0.02).Magnitude > 0, "the normal opening's shake")
	end)

	T.test("CrateOpening: Reduce motion: the pillar and every light come up slowly and never jump", function()
		for _, level in { 5, 10 } do
			local stage, holder = build(level, true)
			local label = "level " .. level .. " "
			local core, wide = named(holder, "PillarCore")[1], named(holder, "PillarWide")[1]
			local rim = named(holder, "PlatformRim")[1]
			local inside = named(holder, "Inside")[1]
			local coreLight, gunLight = named(holder, "CoreLight")[1], named(holder, "GunLight")[1]
			local ray = named(holder, "GodRay")[1]
			local prev: any = nil
			local fullAt = nil
			posed(stage, Stage.T_LAND - 0.02, Stage.T_RISE_END + 0.5, function(t: number)
				local now = {
					core = shows(core),
					wide = shows(wide),
					rim = rim.Color,
					inside = shows(inside),
					ray = shows(ray),
					coreLight = coreLight.Brightness,
					gunLight = gunLight.Brightness,
				}
				local at = label .. string.format("at %.3f: ", t)
				if now.core > 0 then
					T.le(core.Size.Y, 1.5 + 1e-3, at .. "no swell")
					T.le(wide.Size.Y, 4.4 + 1e-3, at .. "no swell")
				end
				if prev then
					T.le(now.core - prev.core, 0.025, at .. "the pillar's core comes up slowly")
					T.le(prev.core - now.core, 0.025, at .. "the pillar's core goes down slowly")
					T.le(prev.wide - now.wide, 0.01, at .. "the pillar goes down slowly")
					T.le(prev.ray - now.ray, 0.01, at .. "the god rays go down slowly")
					if t < Stage.T_RISE_END then -- (then the crate has sunk into the platform)
						T.le(prev.inside - now.inside, 0.025, at .. "the inside's glow goes down slowly")
					end
					T.le(now.wide - prev.wide, 0.01, at .. "the pillar comes up slowly")
					T.le(now.inside - prev.inside, 0.025, at .. "the inside's glow comes up slowly")
					T.le(now.ray - prev.ray, 0.005, at .. "the god rays come up slowly")
					T.le(now.coreLight - prev.coreLight, 0.12, at .. "the core light")
					T.le(prev.coreLight - now.coreLight, 0.25, at .. "the core light falls gently")
					T.le(now.gunLight - prev.gunLight, 0.12, at .. "the blaster's light")
					T.le(math.abs(now.rim.R - prev.rim.R), 0.015, at .. "no white jump on the rim")
					T.le(math.abs(now.rim.G - prev.rim.G), 0.015, at .. "no white jump on the rim")
					T.le(math.abs(now.rim.B - prev.rim.B), 0.015, at .. "no white jump on the rim")
				end
				if not fullAt and now.core >= 0.25 then
					fullAt = t
				end
				prev = now
			end)
			T.truthy(fullAt, label .. "the pillar does show")
			T.lt(Stage.T_BURST + 0.15, fullAt, label .. "a slow fade, not a pop")
		end
		-- (the normal burst does jump: the check above can tell the two apart)
		local stage, holder = build(10)
		local wide = named(holder, "PillarWide")[1]
		stage.update(Stage.T_BURST)
		local a = shows(wide)
		stage.update(Stage.T_BURST + 3 / 60)
		T.lt(a + 0.1, shows(wide), "the normal pillar is fast")
	end)

	T.test("CrateOpening: Reduce motion: what the charge lit fades at the burst, no cut", function()
		-- what it lit, with how much it may lose in a frame
		local function chargeParts(holder: any): { { any } }
			return {
				{ named(holder, "MiniHeart")[1], 0.04 },
				{ named(holder, "MiniRay")[1], 0.06 },
				{ named(holder, "MiniRing")[1], 0.06 },
				{ named(holder, "CometArc")[1], 0.06 },
				{ named(holder, "CometArcB")[1], 0.06 },
				{ named(holder, "Seam")[1], 0.06 },
			}
		end
		local function alive(holder: any): { any }
			local out = {}
			for _, p in named(holder, "Streak") do
				if shows(p) > 0 then
					table.insert(out, p)
				end
			end
			return out
		end
		for _, level in { 4, 9 } do
			local stage, holder = build(level, true)
			local label = "level " .. level .. " "
			local watched = chargeParts(holder)
			local before = {}
			stage.update(Stage.T_BURST - 1 / 60)
			for i, w in watched do
				before[i] = shows(w[1])
				T.lt(0.3, before[i], label .. w[1].Name .. " is lit before the burst")
			end
			local streaks = alive(holder)
			T.lt(0, #streaks, label .. "streaks fly into it before the burst")
			local streakWas = {}
			for i, p in streaks do
				streakWas[i] = shows(p)
			end
			posed(stage, Stage.T_BURST, Stage.T_BURST + Stage.CalmChargeOut - 1 / 60, function(t: number)
				for i, w in watched do
					local now = shows(w[1])
					T.le(before[i] - now, w[2], string.format("%s%s fades at %.3f", label, w[1].Name, t))
					before[i] = now
				end
				for i, p in streaks do
					local now = shows(p)
					T.le(streakWas[i] - now, 0.2, string.format("%sa streak fades at %.3f", label, t))
					streakWas[i] = now
				end
			end)
			stage.update(Stage.T_BURST + Stage.CalmChargeOut)
			for _, w in watched do
				T.eq(shows(w[1]), 0, label .. w[1].Name .. " is gone")
			end
			T.eq(#alive(holder), 0, label .. "the streaks are gone")
			stage.update(Stage.T_OPEN + 0.3)
			T.lt(0, shows(named(holder, "CometArc")[1]), label .. "the arcs come back round the blaster")
		end
		-- the normal burst cuts them all on its first frame (the check above can tell the two apart)
		local stage, holder = build(10)
		local watched = chargeParts(holder)
		stage.update(Stage.T_BURST - 1 / 60)
		for _, w in watched do
			T.lt(0.3, shows(w[1]), w[1].Name .. " is lit before the burst")
		end
		T.lt(0, #alive(holder), "streaks fly into it")
		stage.update(Stage.T_BURST)
		for _, w in watched do
			T.eq(shows(w[1]), 0, "the normal burst cuts " .. w[1].Name)
		end
		T.eq(#alive(holder), 0, "the normal burst cuts the streaks")
		stage.update(Stage.T_OPEN + 0.3)
		T.lt(0, shows(named(holder, "CometArc")[1]), "the arcs come back round the blaster")
	end)

	T.test("CrateOpening: Reduce motion: the crate's strips hold steady, the wheel of rays comes up slowly", function()
		local stage, holder = build(10, true)
		local strips = {}
		for _, p in parts(holder:FindFirstChild("Case", true)) do
			if p.Material == Enum.Material.Neon and p.Name ~= "Inside" and p.Name ~= "Seam" then
				table.insert(strips, p)
			end
		end
		T.lt(4, #strips, "strips")
		local base = named(holder, "Inside")[1]
		local t = Stage.T_IMPACT
		while t < Stage.T_BURST do
			stage.update(t)
			T.eq(strips[1].Transparency, 0, string.format("steady at %.3f", t))
			T.near(base.CFrame.Position.X, 0, 1e-3, string.format("the crate does not rattle at %.3f", t))
			t += 1 / 60
		end
		local wedges = {}
		for _, d in holder:GetDescendants() do
			if d:IsA("WedgePart") and d.Parent == stage.Root then
				table.insert(wedges, d)
			end
		end
		T.lt(10, #wedges, "the wheel of rays")
		local prev, prevLen = 0, 0
		posed(stage, Stage.T_RISE_END - 0.1, Stage.T_SETTLE + 1, function(time: number)
			local w = wedges[1]
			local now = shows(w)
			T.le(now - prev, 0.003, string.format("it comes up slowly at %.3f", time))
			T.le(prev - now, 1e-6, string.format("no kick that falls back at %.3f", time))
			if now > 0 then
				T.le(w.Size.Z - prevLen, 0.6, string.format("it grows slowly at %.3f", time))
				prevLen = w.Size.Z
			end
			prev = now
		end)
		T.lt(0, prev, "and it does come")
	end)

	T.test("CrateOpening: a narrow screen pulls the camera back", function()
		local stage = build(10)
		local wide = (stage.camera(stage.Hold).Position - ORIGIN.Position).Magnitude
		stage.aspect = 4 / 3
		local narrow = (stage.camera(stage.Hold).Position - ORIGIN.Position).Magnitude
		T.lt(wide, narrow, "further back")
	end)

	T.test("CrateOpening: moves few parts per frame; waiting at the reveal keeps it alive", function()
		local stage = build(10)
		local most = 0
		stage.bulk = function(list: { any }, frames: { any })
			most = math.max(most, #list)
			for i, p in list do
				p.CFrame = frames[i]
			end
		end
		local t = 0
		while t <= stage.Duration do
			stage.update(t)
			t += 1 / 30
		end
		T.le(most, 560, "parts moved in a frame at the most")
		local cf0 = stage.camera(stage.Hold, 0)
		local cf1 = stage.camera(stage.Hold, 1.5)
		T.lt(0.01, (cf0.Position - cf1.Position).Magnitude, "the camera drifts while it waits")
		T.eq(stage.blur(0.1), 0, "no blur at the start")
		T.lt(0, stage.blur(0.85), "the fall's blur")
		T.lt(0, stage.blur(stage.Burst + 0.02), "the burst's blur")
	end)

	T.test("CrateOpening: timeline (lands, bursts, the blaster appears after the burst)", function()
		local stage, holder = build(5)
		T.truthy(stage.Burst > 1 and stage.Burst < stage.Reveal, "burst before the reveal")
		T.truthy(stage.SkipTo > 0.6 and stage.SkipTo < stage.Burst, "a skip still shows the burst")
		local blaster = holder:FindFirstChild("Blaster", true)
		T.truthy(blaster, "the blaster is on the stage")
		local gun = parts(blaster)
		local function gunY(t: number): number
			stage.update(t)
			local y = 0
			for _, p in gun do
				y += p.CFrame.Position.Y
			end
			return y / #gun - ORIGIN.Position.Y
		end
		T.lt(gunY(stage.Burst - 0.2), -1000, "hidden before the burst")
		local shown = gunY(stage.Hold)
		T.truthy(shown > 3 and shown < 12, "floats above the case at the end")
		T.lt(gunY(stage.Burst + 0.2), shown, "rises")
		-- the case drops in from above and rests on the disc
		local case = holder:FindFirstChild("Case", true)
		local function caseY(t: number): number
			stage.update(t)
			local lo = math.huge
			for _, p in parts(case) do
				lo = math.min(lo, p.CFrame.Position.Y - p.Size.Y / 2)
			end
			return lo - ORIGIN.Position.Y
		end
		T.lt(caseY(0), -1000, "not there yet")
		T.truthy(caseY(0.7) > 5, "shoots down from the portal")
		T.near(caseY(Stage.T_LAND + 0.3), 0, 0.6, "rests on the platform")
	end)

	T.test("CrateOpening: the camera stays inside the room and looks at the stage", function()
		local stage = build(10)
		local t = 0
		while t <= stage.Duration do
			local cf = stage.camera(t)
			local local_ = ORIGIN:PointToObjectSpace(cf.Position)
			T.truthy(math.sqrt(local_.X ^ 2 + local_.Z ^ 2) < 50, "inside the round wall at " .. t)
			T.truthy(local_.Y > 1 and local_.Y < 60, "under the ceiling at " .. t)
			-- the crate, then the blaster up there
			local focus = if t > stage.Burst + 0.6 then Stage.GunRest else 3
			local toStage = (ORIGIN.Position + Vector3.new(0, focus, 0) - cf.Position).Unit
			T.truthy(cf.LookVector:Dot(toStage) > 0.85, "looks at the stage at " .. t)
			t += 0.25
		end
	end)

	T.test("CrateOpening: deterministic (two builds pose the same)", function()
		local a, ha = build(9)
		local b, hb = build(9)
		for _, t in { 0.3, 2.0, 3.1, 4.0, 5.2, 7.0 } do
			a.update(t)
			b.update(t)
			local pa, pb = parts(ha), parts(hb)
			T.eq(#pa, #pb, "same parts")
			for i = 1, #pa, 7 do
				T.truthy((pa[i].CFrame.Position - pb[i].CFrame.Position).Magnitude < 1e-6, "same pose at " .. t)
			end
		end
	end)
end
