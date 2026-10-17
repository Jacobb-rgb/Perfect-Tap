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
			local case = CaseBuilder.build(m, CFrame.new(), level, BlasterData.vaultOre(level))
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
		CaseBuilder.build(low, CFrame.new(), 2, BlasterData.vaultOre(2))
		CaseBuilder.build(high, CFrame.new(), 10, BlasterData.vaultOre(10))
		T.lt(#parts(low), #parts(high), "level 10 has more detail than level 2")
	end)

	T.test("CrateOpening: hot ores get lava cracks, cool ores a galaxy glow", function()
		local _, _, glowHot, hot = CaseBuilder.look("Emberite")
		T.truthy(hot, "Emberite is hot")
		local _, _, glowCool, cool = CaseBuilder.look("Sapphire")
		T.falsy(cool, "Sapphire is cool")
		T.truthy(glowHot ~= glowCool, "different glows")
		local _, _, _, starter = CaseBuilder.look("")
		T.truthy(starter, "the rusty starter case glows warm")
	end)

	T.test("CrateOpening: the blaster is shown centered at its hero size", function()
		for level = 1, BlasterData.MaxLevel do
			local model = Stage.blasterModel(level, BlasterData.vaultOre(level))
			local zLo, zHi = math.huge, -math.huge
			local count = 0
			for _, p in parts(model) do
				count += 1
				T.truthy(p.Anchored, "anchored")
				T.eq(#p:GetChildren() > 0 and p:FindFirstChildOfClass("WeldConstraint") or nil, nil, "no welds")
				local z = p.CFrame.Position.Z
				zLo = math.min(zLo, z - p.Size.Magnitude / 2)
				zHi = math.max(zHi, z + p.Size.Magnitude / 2)
			end
			T.truthy(count > 5, "level " .. level .. " has parts")
			T.le(zHi - zLo, Stage.BlasterLength * 1.6, "level " .. level .. " not too long")
			T.le(Stage.BlasterLength * 0.7, zHi - zLo, "level " .. level .. " not too short")
			T.near((zHi + zLo) / 2, 0, 1.2, "level " .. level .. " centered")
		end
	end)

	T.test("CrateOpening: the stage poses all 10 seconds without errors or NaN", function()
		local stage, holder = build(7)
		local list = parts(holder)
		T.le(#list, STAGE_BUDGET, "stage parts")
		local lights = 0
		for _, d in holder:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			end
		end
		T.le(lights, 3, "at most 3 lights")
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
		local shown = gunY(stage.Duration)
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
		T.truthy(caseY(0) > 5, "starts in the air")
		T.near(caseY(2), 0, 0.6, "rests on the disc")
	end)

	T.test("CrateOpening: the camera stays inside the room and looks at the stage", function()
		local stage = build(10)
		local t = 0
		while t <= stage.Duration do
			local cf = stage.camera(t)
			local local_ = ORIGIN:PointToObjectSpace(cf.Position)
			T.truthy(math.sqrt(local_.X ^ 2 + local_.Z ^ 2) < 50, "inside the round wall at " .. t)
			T.truthy(local_.Y > 1 and local_.Y < 60, "under the ceiling at " .. t)
			local toStage = (ORIGIN.Position + Vector3.new(0, 3, 0) - cf.Position).Unit
			T.truthy(cf.LookVector:Dot(toStage) > 0.9, "looks at the stage at " .. t)
			t += 0.25
		end
	end)

	T.test("CrateOpening: deterministic (two builds pose the same)", function()
		local a, ha = build(9)
		local b, hb = build(9)
		for _, t in { 0.3, 2.0, 3.1, 4.0, 8.0 } do
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
