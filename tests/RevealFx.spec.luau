-- The cleaning reveal's feel (RevealFx): the moment grows with rarity, the
-- slow-motion warp keeps its ends and never runs backwards, the shine bar
-- and the grade stamp build as small cheap parts; the cosmetic streak chip.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local CFrame = roblox.CFrame
	local Color3 = roblox.Color3
	local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.RevealFx")
	local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")

	T.test("RevealFx: the moment grows with rarity, slow motion and a FOV punch for Legendary / Mythic", function()
		local last = nil
		for order = 1, 6 do
			local plan = RevealFx.plan(order)
			if last then
				T.truthy(plan.Duration >= last.Duration, "never shorter at order " .. order)
				T.truthy(plan.Shake >= last.Shake, "never softer at order " .. order)
				T.truthy(plan.Spins >= last.Spins, "never fewer turns at order " .. order)
			end
			T.eq(plan.SlowMo, order >= 5, "slow motion only Legendary+ (" .. order .. ")")
			T.eq(plan.FovPunch > 0, order >= 5, "FOV punch only Legendary+ (" .. order .. ")")
			T.eq(plan.Rays > 0, order >= 5, "rays only Legendary+ (" .. order .. ")")
			last = plan
		end
		T.eq(RevealFx.plan(6).Rays, 12, "Mythic has the most rays")
		T.truthy(RevealFx.TouchShake < 1, "phones shake less")
	end)

	T.test("RevealFx: the slow-motion warp keeps 0 and 1 and never runs backwards", function()
		T.eq(RevealFx.warp(0, true), 0)
		T.near(RevealFx.warp(1, true), 1, 1e-9)
		T.eq(RevealFx.warp(0.3, false), 0.3, "no warp without slow motion")
		local prev = 0
		local slowest = math.huge
		for i = 1, 200 do
			local p = i / 200
			local v = RevealFx.warp(p, true)
			T.truthy(v >= prev - 1e-9, "monotonic at " .. p)
			slowest = math.min(slowest, (v - prev) * 200)
			prev = v
		end
		T.truthy(slowest < 0.4, "the middle runs at about a quarter speed")
		T.eq(RevealFx.warp(-1, true), 0, "clamped")
	end)

	T.test("RevealFx: the shine bar and the grade stamp are one small part each", function()
		local folder = Instance.new("Folder")
		local face = CFrame.new(0, 5, 0)
		local bar, at = RevealFx.sweep(folder, face, 1.2, 1.5)
		T.eq(bar.Parent, folder)
		T.eq(bar.Transparency, 1, "invisible before it starts")
		at(0.5)
		T.truthy(bar.Transparency < 0.5, "bright in the middle")
		at(1)
		T.near(bar.Transparency, 1, 1e-6, "gone at the end")
		local plate, pop = RevealFx.stamp(folder, face, 1.3, "Flawless", Color3.fromRGB(255, 225, 110))
		T.eq(plate.Parent, folder)
		T.eq(plate.Transparency, 1, "the plate itself is clear")
		local label = plate:FindFirstChild("Stamp"):FindFirstChild("Box"):FindFirstChild("Grade")
		T.eq(label.Text, "FLAWLESS")
		T.eq(pop.Scale, 1)
		local parts = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		T.eq(parts, 2, "one bar + one stamp plate")
	end)

	T.test("CleaningView: the streak counts cleans within the window and resets after it", function()
		T.eq(CleaningView.nextStreak(0, nil, 100), 1, "the first clean")
		T.eq(CleaningView.nextStreak(1, 100, 150), 2, "within the window")
		T.eq(CleaningView.nextStreak(2, 150, 150 + CleaningView.StreakWindow), 3, "right at the edge")
		T.eq(CleaningView.nextStreak(3, 150, 151 + CleaningView.StreakWindow), 1, "too late: starts again")
		T.eq(CleaningView.streakText(1), "", "no chip for a single clean")
		T.truthy(CleaningView.streakText(4):find("x4", 1, true), "x4")
		local view = CleaningView.build({ Touch = false })
		CleaningView.setStreak(view, 3)
		T.truthy(view.CardStreak.Visible, "chip shown")
		CleaningView.setStreak(view, 1)
		T.falsy(view.CardStreak.Visible, "chip hidden")
	end)
end
