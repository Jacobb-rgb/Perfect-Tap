--[[
	Prints how simulated players score at spray-washing (calibration of
	SprayScoring.Par / Weights). lune run tools/lune/spray_calibrate.luau
]]
local process = require("@lune/process")
local Loader = require("./lib/loader")
Loader.init(process.cwd)
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
local Players = require("./lib/spray_players")(Loader)

local byRarity = {}
for _, ore in OreData.List do
	byRarity[ore.Rarity] = byRarity[ore.Rarity] or ore.Id
end

local function row(label, results)
	local s, t, a, c, minS, maxS = 0, 0, 0, 0, 1, 0
	for _, r in results do
		s += r.Score
		t += r.Time
		a += r.Aim
		c += r.Cracks
		minS = math.min(minS, r.Score)
		maxS = math.max(maxS, r.Score)
	end
	local n = #results
	print(string.format("  %-22s score %.3f (%.3f..%.3f) time %5.1fs aim %.2f cracks %.1f", label, s / n, minS, maxS, t / n, a / n, c / n))
end

for _, info in Rarity.List do
	local oreId = byRarity[info.Id]
	local amount, cells = 0, 0
	local players = {
		{
			"sweep v2/thick",
			function(p, seed)
				return Players.sweep(p, { Speed = 1.9 / info.DirtThickness, Seed = seed })
			end,
		},
		{
			"sweep v1.2/thick",
			function(p, seed)
				return Players.sweep(p, { Speed = 1.2 / info.DirtThickness, Seed = seed })
			end,
		},
		{
			"sweep v3",
			function(p, seed)
				return Players.sweep(p, { Speed = 3, Seed = seed })
			end,
		},
		{
			"sweep wide 1.4R",
			function(p, seed)
				return Players.sweep(p, { Speed = 1.9 / info.DirtThickness, Spacing = 1.4, Seed = seed })
			end,
		},
		{
			"sweep touch",
			function(p, seed)
				return Players.sweep(p, { Speed = 1.9 / info.DirtThickness, Input = "Touch", Seed = seed })
			end,
		},
		{
			"linger 0.5 crystals",
			function(p, seed)
				return Players.sweep(p, { Speed = 1.9 / info.DirtThickness, Linger = 0.5, Seed = seed })
			end,
		},
		{
			"scribble v3",
			function(p, seed)
				return Players.scribble(p, { Speed = 3, Seed = seed })
			end,
		},
		{
			"scribble v1.5",
			function(p, seed)
				return Players.scribble(p, { Speed = 1.5, Seed = seed })
			end,
		},
	}
	local out = {}
	for seed = 1, 12 do
		local pattern = Patterns.generate(oreId, seed * 977)
		amount += pattern.TotalAmount
		cells += #pattern.Cells
		for k, player in players do
			out[k] = out[k] or {}
			local submission = player[2](pattern, seed)
			local r = Scoring.score(pattern, submission)
			if not r.Valid then
				print("INVALID", player[1], r.Reason)
			end
			table.insert(out[k], r)
		end
	end
	local pattern = Patterns.generate(oreId, 977)
	print(
		string.format(
			"%s (%s): cells %.0f, dirt %.1f, par %.1fs, crystals %d",
			info.Id,
			oreId,
			cells / 12,
			amount / 12,
			Scoring.par(pattern, "Mouse"),
			#pattern.Crystals
		)
	)
	for k, player in players do
		row(player[1], out[k])
	end
end
