--[[
	The weapon cases (Builders/CaseBuilder) and the crate-opening cinematic's
	stage (Builders/CrateOpeningStage): every level builds within a part
	budget with mobile-safe parts, the blaster is shown at its hero size, the
	whole 10 seconds pose without errors or NaN, the timeline (case lands,
	bursts, the blaster appears only after the burst), the camera stays in the
	room, and two builds pose the same (deterministic).
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
	local STAGE_BUDGET = 1100

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

	local function build(level: number): (any, any)
		local holder = Instance.new("Model")
		local ore = BlasterData.vaultOre(level)
		local stage = Stage.build(holder, ORIGIN, level, ore, Stage.blasterModel(level, ore))
		return stage, holder
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

	T.test("CrateOpening: the stage poses the whole opening without errors or NaN", function()
		local stage, holder = build(7)
		local list = parts(holder)
		T.le(#list, STAGE_BUDGET, "stage parts")
		local lights = 0
		for _, d in holder:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			end
		end
		T.le(lights, 4, "at most 4 lights")
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
