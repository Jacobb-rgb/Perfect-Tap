--[[
	The blaster shooting feel (Config/BlasterFeel, Effects/BlasterFx) and the
	sound ids: the tiers grow with the level (Lv7+ energy, Lv10 rings),
	phones get the light version within the mobile caps, the recoil settles
	quickly, and every SoundConfig id plays in today's Roblox clients (a file
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
			for _, key in { "BeamWidth", "CoreWidth", "Light", "Flash", "FlashRate", "Sparks", "Chips", "Swirl" } do
				T.le(a[key], b[key], key .. " never shrinks")
			end
			T.lt(a.BeamWidth, b.BeamWidth, "each tier's beam is thicker")
		end
		for level = 1, BlasterData.MaxLevel do
			local tier = BlasterFeel.tier(level)
			T.le(tier.MinLevel, level, "level " .. level .. " tier")
			T.eq(tier.Energy, level >= 7, "level " .. level .. " energy stream from 7")
			T.eq(tier.Rings, level >= 10, "level " .. level .. " rings at 10")
			T.eq(tier.Swirl > 0, tier.Energy, "the swirl comes with the energy stream")
			T.lt(tier.CoreWidth, tier.BeamWidth, "the core is inside the glow")
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
			for _, key in { "Sparks", "Chips", "FlashRate", "Swirl", "Rings" } do
				T.le(phone[key], pc[key], "level " .. level .. " phone " .. key)
				T.truthy(pc[key] == 0 or phone[key] >= 1, "level " .. level .. " phone keeps some " .. key)
			end
			T.le(pc.Sparks, lim.SparksPerPulse, "sparks cap")
			T.le(pc.Chips, lim.ChipsPerPulse, "chips cap")
			T.le(pc.FlashRate, lim.FlashRate, "flash cap")
			T.le(pc.Swirl, lim.SwirlRate, "swirl cap")
			T.le(pc.Rings, lim.Rings, "rings cap")
			T.eq(pc.CameraKick, 1, "PC camera kick")
			T.eq(phone.CameraKick, 0, "no camera kick on phones")
			T.lt(phone.GunKick, 1, "a smaller gun kick on phones")
			T.eq(pc.Level, level, "level")
		end
		-- particles per second while firing at a rock, worst case (Lv10 PC): flash + swirl +
		-- sparks per spark tick (MiningController: every 0.07 s) + chips and glints per chip pulse
		local top = BlasterFeel.resolve(BlasterData.MaxLevel, false)
		local perSecond = top.FlashRate
			+ top.Swirl
			+ top.Sparks / 0.07
			+ (top.Chips + top.Sparks) / (BlasterFeel.Pulse * BlasterFeel.ChipEvery)
		T.le(perSecond, 200, "Lv10 on PC stays light")
		local phoneTop = BlasterFeel.resolve(BlasterData.MaxLevel, true)
		local phoneRate = phoneTop.FlashRate + phoneTop.Swirl + phoneTop.Sparks / 0.07
		T.le(phoneRate, perSecond * 0.6, "phones about half")
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

	T.test("BlasterFeel: other players' beams get their tier look", function()
		local BlasterFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BlasterFx")
		for level = 1, BlasterData.MaxLevel do
			local style = BlasterFx.styleFor(level)
			local tier = BlasterFeel.tier(level)
			T.eq(style.Width, tier.BeamWidth, "width")
			T.eq(style.Energy, level >= 7, "energy stream")
		end
		T.eq(BlasterFx.styleFor(nil).Width, BlasterFeel.Tiers[1].BeamWidth, "unknown level: the plain beam")
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
			"BlasterBeam",
			"BlasterZap",
			"BlastThud",
			"RockBreak",
			"ElevatorDing",
			"DoorThud",
		}
		for _, key in keys do
			T.truthy(SoundConfig[key], "key " .. key)
		end
		for _, key in { "BlasterHum", "BlasterBeam", "Scrape", "MachineHum", "TrainChuff", "TrainWhistle", "CaseCharge" } do
			T.truthy(SoundConfig[key].Looped, key .. " loops")
		end
		for _, key in { "BlasterZap", "BlastHit", "BlastThud", "NodeShatter", "RockBreak" } do
			T.falsy(SoundConfig[key].Looped, key .. " plays once")
		end
	end)
end
