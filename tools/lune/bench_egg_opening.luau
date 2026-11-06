--[[
	The egg opening's script cost a frame (V2, integrator 2026-10-30: "measure the new opening's frame
	cost on a phone-size run, and Reduce motion"): HatchStage.pose at 60 frames a second over a whole
	opening, timed (os.clock). Lune's instances are slower than Roblox's: an upper bound for the
	script, nothing of the GPU (the blur and the ColorCorrection are full-screen passes on the device).
	  lune run tools/lune/bench_egg_opening.luau [root]   (root: another checkout's src, e.g. the
	                                                      opening V2 grew from, to compare)
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")
Loader.init(process.args[1] or process.cwd)

local Vector2 = roblox.Vector2
local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")

local function golemOf(kind: string): (any, number, number)
	local model = GolemBuilder.build(kind)
	return model, model:GetAttribute("Height") or 3, model:GetAttribute("RootHeight") or 1
end

local function bench(label: string, egg: string, kinds: { string }, phone: boolean, reduced: boolean, fast: boolean)
	local o = CapsuleView.buildOpening(phone)
	-- (a phone: 844 x 390 pt at the phone's UI scale is about 1360 x 630 design units)
	local w, h = if phone then 1360 else 1280, if phone then 630 else 720
	CapsuleView.layoutOpening(o, phone, w, h, { Touch = phone, Inset = 36 })
	local eggs = {}
	for _ = 1, #kinds do
		local model = GolemBuilder.capsule(egg)
		HatchFx.addCracks(model, 3)
		model:SetAttribute("Pooled", true)
		table.insert(eggs, HatchFx.record(model))
	end
	local run = HatchStage.new({
		Refs = o,
		Capsule = egg,
		Lucky = false,
		Kinds = kinds,
		Eggs = eggs,
		Fast = fast,
		Reduced = reduced,
		Phone = phone,
		Target = Vector2.new(0.5, 0.86),
		Golem = golemOf,
		Claim = function(): boolean
			return true
		end,
	})
	local tl = run.Timeline
	local times: { number } = {}
	local t = 0
	while t <= tl.Total do
		local start = os.clock()
		HatchStage.pose(run, t)
		table.insert(times, (os.clock() - start) * 1000)
		t += 1 / 60
	end
	table.sort(times)
	local sum = 0
	for _, ms in times do
		sum += ms
	end
	local frames = 0
	for _, d in o.Gui:GetDescendants() do
		if d:IsA("GuiObject") then
			frames += 1
		end
	end
	print(
		string.format(
			"%-34s %3d frames  mean %.3f ms  p95 %.3f ms  max %.3f ms  (%d GuiObjects in the opening)",
			label,
			#times,
			sum / #times,
			times[math.max(1, math.floor(#times * 0.95))],
			times[#times],
			frames
		)
	)
end

local MYTHIC10 = {
	"QuartzSprite",
	"SilverSquire",
	"EmberImp",
	"JadeGardener",
	"CelestialSovereign",
	"AmethystAcolyte",
	"MoonstoneOracle",
	"QuartzSprite",
	"RoseKnight",
	"SilverSquire",
}
local OPEN3 = { "QuartzSprite", "StormTitan", "CobaltDiver" }
for _ = 1, 2 do -- (the first round warms the builders up: the second is the one to read)
	print("--")
	bench("phone Open 10, a Mythic", "Crystal", MYTHIC10, true, false, false)
	bench("phone Open 3, a Legendary", "Crystal", OPEN3, true, false, false)
	bench("phone Open 10, Auto", "Crystal", MYTHIC10, true, false, true)
	bench("phone Open 10, Reduce motion", "Crystal", MYTHIC10, true, true, false)
	bench("PC Open 3, a Legendary", "Crystal", OPEN3, false, false, false)
end
