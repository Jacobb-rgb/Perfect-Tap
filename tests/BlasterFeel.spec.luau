--[[
	The blaster shooting feel (Config/BlasterFeel, Effects/BlasterFx,
	Effects/BlasterShots) and the sound ids: separate shots that get faster as
	the barrels spin up, never a beam (owner 2026-11-06), the tiers grow with
	the level (Lv7+ swirl, Lv10 rings), phones get the light version within the
	mobile caps, the recoil settles quickly, and every SoundConfig id plays in today's Roblox clients (a file
	still shipped in content/sounds, or an uploaded asset id) with no key of
	the shared list lost.
]]
return function(T, Loader)
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local BlasterFeel = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterFeel")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")

	T.test("BlasterFeel: the tiers grow with the level", function()
		local tiers = BlasterFeel.Tiers
		T.eq(tiers[1].MinLevel, 1, "level 1 has a tier")
		for i = 2, #tiers do
			local a, b = tiers[i - 1], tiers[i]
			T.lt(a.MinLevel, b.MinLevel, "tiers in order")
			for _, key in { "ShotWidth", "ShotCore", "Light", "Flash", "Sparks", "Chips", "Swirl" } do
				T.le(a[key], b[key], key .. " never shrinks")
			end
			T.lt(a.ShotWidth, b.ShotWidth, "each tier's shot is thicker")
		end
		for level = 1, BlasterData.MaxLevel do
			local tier = BlasterFeel.tier(level)
			T.le(tier.MinLevel, level, "level " .. level .. " tier")
			T.eq(tier.Swirl > 0, level >= 7, "level " .. level .. " swirl from 7")
			T.eq(tier.Rings, level >= 10, "level " .. level .. " rings at 10")
			T.lt(tier.ShotCore, tier.ShotWidth, "the core is inside the glow")
		end
		T.eq(BlasterFeel.tier(0), tiers[1], "below 1")
		T.eq(BlasterFeel.tier(0 / 0), tiers[1], "NaN")
		T.eq(BlasterFeel.tier("7"), tiers[1], "not a number")
		T.eq(BlasterFeel.tier(99), tiers[#tiers], "above the top")
	end)

	T.test("BlasterFeel: phones get the light version, within the caps", function()
		local lim = BlasterFeel.Limits
		for level = 1, BlasterData.MaxLevel do
			local pc = BlasterFeel.resolve(level, false)
			local phone = BlasterFeel.resolve(level, true)
			for _, key in { "Sparks", "Chips", "Swirl", "Rings" } do
				T.le(phone[key], pc[key], "level " .. level .. " phone " .. key)
				T.truthy(pc[key] == 0 or phone[key] >= 1, "level " .. level .. " phone keeps some " .. key)
			end
			T.le(pc.Sparks, lim.SparksPerShot, "sparks cap")
			T.le(pc.Chips, lim.ChipsPerPulse, "chips cap")
			T.eq(pc.FlashEvery, 1, "a flash on every shot")
			T.lt(1, phone.FlashEvery, "fewer flashes on phones")
			T.le(pc.Swirl, lim.SwirlRate, "swirl cap")
			T.le(pc.Rings, lim.Rings, "rings cap")
			T.eq(pc.CameraKick, 1, "PC camera kick")
			T.eq(phone.CameraKick, 0, "no camera kick on phones")
			T.lt(phone.GunKick, 1, "a smaller gun kick on phones")
			T.eq(pc.Level, level, "level")
		end
		-- particles per second while firing at a rock at full spin, worst case (Lv10 PC): each shot's
		-- flash, impact and sparks + the swirl + chips and glints per chip pulse
		local rate = BlasterFeel.Shots.FastRate
		local top = BlasterFeel.resolve(BlasterData.MaxLevel, false)
		local perSecond = rate * (1 / top.FlashEvery + 1 + top.Sparks)
			+ top.Swirl
			+ (top.Chips + top.Sparks) / (BlasterFeel.Pulse * BlasterFeel.ChipEvery)
		T.le(perSecond, 200, "Lv10 on PC stays light")
		local phoneTop = BlasterFeel.resolve(BlasterData.MaxLevel, true)
		local phoneRate = rate * (1 / phoneTop.FlashEvery + 1 + phoneTop.Sparks) + phoneTop.Swirl
		T.le(phoneRate, perSecond * 0.7, "phones lighter")
	end)

	T.test("BlasterFeel: the recoil is small and settles quickly", function()
		T.eq(BlasterFeel.settle(0), 1, "full kick at once")
		T.eq(BlasterFeel.settle(-1), 1, "before the kick")
		T.lt(BlasterFeel.settle(0.05), 1, "settling")
		T.lt(BlasterFeel.settle(0.25), 0.05, "gone in a quarter second")
		T.lt(BlasterFeel.settle(0.2), BlasterFeel.settle(0.1), "keeps settling")
		local r = BlasterFeel.Recoil
		T.le(r.StartKick, math.rad(1.5), "the start kick is small")
		T.le(r.PulseKick, math.rad(0.3), "the pulse kick is tiny")
		T.le(r.GunBack * 2, 0.4, "the gun jumps back less than 0.4 studs")
		T.le(r.GunLift * 2, math.rad(12), "the muzzle climbs at most 12 degrees")
		-- the pulse kicks can't pile up: a pulse every Pulse seconds settles enough in between
		T.lt(BlasterFeel.settle(BlasterFeel.Pulse), 0.25, "settles between pulses")
	end)

	T.test("Shots: the fire rate climbs with the spin, slow to a very fast minigun", function()
		local shots = BlasterFeel.Shots
		T.eq(BlasterFeel.shotRate(0), shots.SlowRate, "slow when the barrels start")
		T.eq(BlasterFeel.shotRate(1), shots.FastRate, "fast at full spin")
		T.eq(BlasterFeel.shotRate(2), shots.FastRate, "never past it")
		T.le(20, shots.FastRate, "a very fast minigun")
		T.le(shots.SlowRate, 5, "each first shot on its own")
		T.eq(BlasterFeel.shotRate(1, shots.OtherRate), shots.OtherRate, "the others' top")
		-- a run at 60 fps: the first shot at once, the gaps shrinking down to the top rate
		local spin, due, times = 0, 1, {}
		for frame = 1, 60 * 4 do
			local count
			spin, due, count = BlasterFeel.shotStep(spin, due, 1 / 60, true)
			for _ = 1, count do
				table.insert(times, frame / 60)
			end
		end
		T.near(times[1], 1 / 60, 1e-6, "the trigger fires at once")
		T.eq(spin, 1, "full spin")
		local function gap(from: number, to: number): number
			local a = 0
			for i = from, to do
				a += times[i + 1] - times[i]
			end
			return a / (to - from + 1)
		end
		T.lt(1 / 8, gap(1, 2), "slow at the start: under 8 shots a second")
		T.near(gap(#times - 12, #times - 1), 1 / shots.FastRate, 0.002, "fast at the end")
		local before = math.huge
		for from = 1, #times - 7, 6 do
			local now = gap(from, from + 5)
			T.le(now, before + 1e-3, "faster and faster")
			before = now
		end
		-- let go: no more shots, the spin runs down, the next press fires at once
		local count
		spin, due, count = BlasterFeel.shotStep(1, 0.5, 1 / 60, false)
		T.eq(count, 0, "no shots")
		T.lt(spin, 1, "runs down")
		T.eq(due, 1, "due again")
		-- a slow frame fires only so many
		local _, _, many = BlasterFeel.shotStep(1, 0, 1, true)
		T.eq(many, shots.MaxPerFrame, "the slow frame's cap")
	end)

	T.test("Shots: separate shots, never a beam", function()
		local shots = BlasterFeel.Shots
		-- at the top rate the next shot's head is a clear gap behind the last one's tail
		local spacing = shots.Speed / shots.FastRate
		T.lt(shots.Trail + 1, spacing, "a gap between two shots at full spin")
		T.eq(shots.Pool >= shots.PhonePool, true, "phones fly fewer")
		-- the longest shot's flight (the top range) at the top rate fits the pool
		local range = BlasterData.Levels[BlasterData.MaxLevel].Range
		T.le(range / shots.Speed * shots.FastRate, shots.PhonePool, "your stream fits the smallest pool")
		-- one barrel goes by for every shot at full spin
		T.near(BlasterFeel.barrelSpeed() / (math.pi * 2) * shots.Barrels, shots.FastRate, 1e-6, "barrels and shots in step")
		local Vfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Vfx")
		T.eq((Vfx :: any).setBeam, nil, "the beam is gone")
		local BlasterFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BlasterFx")
		T.eq(BlasterFx.beamStyle, nil, "and its style")
		T.truthy(Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BlasterShots").aim, "the shots are there")
	end)

	T.test("Sounds: every id plays in today's clients, no key lost", function()
		-- the only files still shipped in content/sounds (checked in Roblox Studio and Roblox, 2026-10)
		local shipped = {
			["rbxasset://sounds/action_falling.ogg"] = true,
			["rbxasset://sounds/action_footsteps_plastic.mp3"] = true,
			["rbxasset://sounds/action_get_up.mp3"] = true,
			["rbxasset://sounds/action_jump.mp3"] = true,
			["rbxasset://sounds/action_jump_land.mp3"] = true,
			["rbxasset://sounds/action_swim.mp3"] = true,
			["rbxasset://sounds/impact_explosion_03.mp3"] = true,
			["rbxasset://sounds/impact_water.mp3"] = true,
			["rbxasset://sounds/oof.ogg"] = true,
			["rbxasset://sounds/ouch.ogg"] = true,
			["rbxasset://sounds/volume_slider.ogg"] = true,
		}
		local count = 0
		for name, def in SoundConfig do
			count += 1
			T.truthy(shipped[def.Id] or string.match(def.Id, "^rbxassetid://%d+$") ~= nil, name .. " plays (" .. def.Id .. ")")
			T.truthy(def.Volume > 0 and def.Volume <= 1, name .. " volume")
			T.eq(#def.Pitch, 2, name .. " pitch range")
			T.truthy(def.Pitch[1] > 0 and def.Pitch[1] <= def.Pitch[2], name .. " pitch order")
		end
		T.truthy(count >= 40, "the sounds are there")
		-- other packages play these by key (steps 6-7, machines, mine floors, the vault): never rename them
		local keys = {
			"BlasterHum",
			"BlasterStart",
			"BlasterStop",
			"BlastHit",
			"BlastBounce",
			"NodeCrack",
			"NodeShatter",
			"Pickup",
			"Drop",
			"Throw",
			"ChiselCrack",
			"ChiselScratch",
			"Chip",
			"Scrape",
			"DirtPop",
			"Polish",
			"Reveal",
			"Sell",
			"Furnace",
			"Crusher",
			"AnvilClang",
			"Place",
			"Gulp",
			"MachineDone",
			"MachineHum",
			"Reject",
			"CoinBurst",
			"BuildRotate",
			"UIClick",
			"UIDeny",
			"Discovery",
			"TrainChuff",
			"TrainWhistle",
			"CaseLand",
			"CaseCharge",
			"CaseBurst",
			"CaseBoom",
			"CaseRise",
			"BlasterShot",
			"BlasterZap",
			"BlastThud",
			"RockBreak",
			"ElevatorDing",
			"DoorThud",
		}
		for _, key in keys do
			T.truthy(SoundConfig[key], "key " .. key)
		end
		for _, key in { "BlasterHum", "Scrape", "MachineHum", "TrainChuff", "TrainWhistle", "CaseCharge" } do
			T.truthy(SoundConfig[key].Looped, key .. " loops")
		end
		for _, key in { "BlasterShot", "BlasterZap", "BlastHit", "BlastThud", "NodeShatter", "RockBreak" } do
			T.falsy(SoundConfig[key].Looped, key .. " plays once")
		end
	end)
end
