--[[
	TEST FILE ONLY (HRA_K_TESTOVANI, make_test_place.luau ... eggtest): the egg
	opening checks itself in Roblox Studio (owner 2026-11-15: "actually test the
	complete egg opening sequence"). A few seconds after you spawn it plays real
	openings one after another with the game's own code (CapsuleController: the
	3D stage, the camera's view, the focus, the sounds; nothing is bought, the
	server is never asked): 1 egg, 3, 10, a Legendary, a Mythic, a pack of 20
	(two openings in a row) and Auto's fast ones. After each it checks that
	nothing stays behind (the 3D stage out of the world, its holder empty, the
	camera's view and the depth of field back, the zone's bloom back, the HUD
	back) and how smooth the frames were; during each, that the stage stands
	right in front of the camera (only the golems flying off go further, fading)
	and that the opening's softer bloom stood in for the zone's.
	Output (and the Studio log) says [EGG TEST] PASS / FAIL for each, then a
	summary line. A click in the game view skips an opening (as for a player):
	hands off while it runs.
]]

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local CC = require(client:WaitForChild("Controllers"):WaitForChild("CapsuleController")) :: any
local HatchWorld = require(client:WaitForChild("UI"):WaitForChild("HatchWorld")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig) :: any
local CapsuleConfig = require(Shared.Config.CapsuleConfig) :: any

local function log(text: string)
	print("[EGG TEST] " .. text)
end

-- golems of a rarity a capsule can hold (its odds), else of any capsule
local function kindsOf(rarity: string): (string?, string?)
	for _, capsule in CapsuleConfig.List do
		if capsule.Limited == nil then
			for _, line in CapsuleConfig.odds(capsule.Id, false) do
				local info = GolemConfig.ById[line.Golem]
				if info and info.Rarity == rarity then
					return capsule.Id, line.Golem
				end
			end
		end
	end
	return nil, nil
end

local function golems(kinds: { string }): { any }
	local out = {}
	for i, kind in kinds do
		table.insert(out, { Id = 900000 + i, Kind = kind })
	end
	return out
end

local function dofState(): string
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not dof then
		return "none"
	end
	return string.format("%s %.2f %.2f %.2f", tostring(dof.Enabled), dof.FarIntensity, dof.FocusDistance, dof.InFocusRadius)
end

-- the zone's bloom (LightingController tweens it; the opening switches it off while its own stands in)
local function bloomState(): string
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		return "none"
	end
	return string.format("%s %.2f %.0f %.2f", tostring(bloom.Enabled), bloom.Intensity, bloom.Size, bloom.Threshold)
end

local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
task.wait(8) -- (the game's own start: the HUD, the controllers, the map streaming in)

local camera = Workspace.CurrentCamera
local fovBefore = camera.FieldOfView
-- (the stage keeps 1.6 times this far from the camera at least: HatchWorld.NearMargin)
log(string.format("camera: near plane %.2f studs, view %.0f degrees", math.abs(camera.NearPlaneZ), camera.FieldOfView))
log("zone bloom (on, intensity, size, threshold): " .. bloomState() .. " | hands off: a click skips an opening")
local dofBefore = dofState()
local bloomBefore = bloomState()
local _, common = kindsOf("Common")
local _, uncommon = kindsOf("Uncommon")
local _, rare = kindsOf("Rare")
local legendaryEgg, legendary = kindsOf("Legendary")
local mythicEgg, mythic = kindsOf("Mythic")
assert(common and uncommon and rare, "no common, uncommon or rare golem in the capsules' odds")

type Scenario = { Name: string, Capsule: string, Kinds: { string }, Auto: boolean? }
local scenarios: { Scenario } = {
	{ Name = "1 egg (Stone)", Capsule = "Stone", Kinds = { common :: string } },
	{ Name = "3 eggs (Crystal)", Capsule = "Crystal", Kinds = { common :: string, uncommon :: string, rare :: string } },
	{ Name = "10 eggs (Stone)", Capsule = "Stone", Kinds = table.create(10, common :: string) },
}
if legendary and legendaryEgg then
	table.insert(scenarios, { Name = "Legendary (" .. legendaryEgg .. ")", Capsule = legendaryEgg, Kinds = { legendary } })
end
if mythic and mythicEgg then
	table.insert(scenarios, {
		Name = "Mythic in 3 (" .. mythicEgg .. ")",
		Capsule = mythicEgg,
		Kinds = { common :: string, mythic, uncommon :: string },
	})
end
table.insert(scenarios, { Name = "pack of 20 (2 openings in a row)", Capsule = "Stone", Kinds = table.create(20, uncommon :: string) })
table.insert(
	scenarios,
	{ Name = "Auto x3 (fast)", Capsule = "Crystal", Kinds = { common :: string, rare :: string, common :: string }, Auto = true }
)

local passed, failed = 0, 0
for _, scenario in scenarios do
	local problems: { string } = {}
	if scenario.Auto then
		pcall(CC.setAuto, true)
	end
	-- frame times and the stage's place while it plays (and how far the player is: the golems fly there)
	local frames, longest, slow = 0, 0, 0
	local farthest, behind, sawStage, reach = 0, 0, false, 0
	local softest, zoneOff = math.huge, true
	local watch = RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		longest = math.max(longest, dt)
		if dt > 1 / 30 then
			slow += 1
		end
		local world = CC._test.world()
		if world and world.Folder.Parent == Workspace then
			local cam = Workspace.CurrentCamera
			reach = math.max(reach, (cam.CFrame.Position - cam.Focus.Position).Magnitude)
			-- (the opening's own bloom on, the zone's off)
			local own, home = CC._test.glow()
			if own and home and own.Enabled then
				softest = math.min(softest, own.Intensity)
			end
			local zone = Lighting:FindFirstChildOfClass("BloomEffect")
			if home and zone and zone.Enabled then
				zoneOff = false
			end
			for _, model in world.Holder:GetChildren() do
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 1 and d.LocalTransparencyModifier < 1 then
						sawStage = true
						local z = -cam.CFrame:PointToObjectSpace(d.Position).Z
						farthest = math.max(farthest, z)
						if z < 0 then
							behind += 1
						end
					end
				end
			end
		end
	end)
	local started = os.clock()
	CC._test.result({ Capsule = scenario.Capsule, Golems = golems(scenario.Kinds) })
	while not CC._test.playing() and os.clock() - started < 3 do
		task.wait()
	end
	while CC._test.playing() and os.clock() - started < 60 do
		task.wait()
	end
	local played = os.clock() - started
	watch:Disconnect()
	if scenario.Auto then
		pcall(CC.setAuto, false)
	end
	-- (the view eases back out, the focus and the opening's bloom go; under Auto they wait AutoWait first,
	-- unless Auto stops: wait until all of it has settled, at most AutoWait and a few seconds)
	local settleBy = os.clock() + CC.AutoWait + 3
	task.wait(0.2)
	while os.clock() < settleBy do
		local _, home = CC._test.glow()
		local z = CC._test.zoom()
		if not CC._test.playing() and not z.Bound and z.Home == nil and home == nil and dofState() == dofBefore then
			break
		end
		task.wait(0.1)
	end
	if CC._test.playing() then
		table.insert(problems, "still playing after 60 s")
	end
	if not sawStage then
		table.insert(problems, "the 3D stage never showed a part")
	end
	if behind > 0 then
		table.insert(problems, behind .. " stage part frames behind the camera")
	end
	-- (only the golems flying off go further than the stage's band, fading: toward the player, at most 4x
	-- their resting depth (HatchFx.flyTo), an auto-deleted one 6x; never further, however near the player)
	local limit = math.max(reach + 3, 6 * HatchWorld.GolemDepth + 1)
	if farthest > limit then
		table.insert(problems, string.format("a stage part %.1f studs away (at most %.1f)", farthest, limit))
	end
	local soft = CC.SoftBloom
	if string.sub(bloomBefore, 1, 4) == "true" then
		if softest > soft.Intensity + 0.02 then
			table.insert(problems, string.format("the opening's bloom never got soft (%.2f)", softest))
		end
		if not zoneOff then
			table.insert(problems, "the zone's bloom stayed on during the opening")
		end
	end
	local own, home = CC._test.glow()
	if home ~= nil or (own and own.Enabled) then
		table.insert(problems, "the opening's bloom was not handed back")
	end
	if bloomState() ~= bloomBefore then
		table.insert(problems, "the zone's bloom is " .. bloomState() .. ", was " .. bloomBefore)
	end
	local world = CC._test.world()
	if world then
		if world.Folder.Parent ~= nil then
			table.insert(problems, "the 3D stage is still in the world")
		end
		local left = #world.Holder:GetChildren()
		if left > 0 then
			table.insert(problems, left .. " models left on the stage")
		end
	else
		table.insert(problems, "no 3D stage was made")
	end
	if math.abs(Workspace.CurrentCamera.FieldOfView - fovBefore) > 0.5 then
		table.insert(problems, string.format("the camera's view is %.1f, was %.1f", Workspace.CurrentCamera.FieldOfView, fovBefore))
	end
	local zoom = CC._test.zoom()
	if zoom.Bound or zoom.Home ~= nil then
		table.insert(problems, "the view's step is still bound")
	end
	if dofState() ~= dofBefore then
		table.insert(problems, "the depth of field is " .. dofState() .. ", was " .. dofBefore)
	end
	if CC._test.hudHidden() then
		table.insert(problems, "the HUD is still away")
	end
	local summary = string.format(
		"%s: %.1f s, %d frames, longest %d ms, %d over 33 ms, stage within %.2f studs (player %.1f), bloom %s",
		scenario.Name,
		played,
		frames,
		math.floor(longest * 1000),
		slow,
		farthest,
		reach,
		if softest < math.huge then string.format("%.2f", softest) else "-"
	)
	if #problems == 0 then
		passed += 1
		log("PASS " .. summary)
	else
		failed += 1
		log("FAIL " .. summary .. " | " .. table.concat(problems, "; "))
	end
	task.wait(1)
end
log(string.format("DONE %d passed, %d failed (of %d)", passed, failed, passed + failed))
