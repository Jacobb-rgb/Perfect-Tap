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
	local roblox = require("@lune/roblox") :: any
	local Instance, Enum, Vector3, Color3 = roblox.Instance, roblox.Enum, roblox.Vector3, roblox.Color3
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

	T.test("Shots: the hit light holds steady while shots land, it never strobes", function()
		local shots = BlasterFeel.Shots
		for _, rate in { 4, 8, 12, 24 } do
			local dt, glare, nextLand, lastLand = 1 / 60, 0, 0, -math.huge
			local low, high = math.huge, 0
			for frame = 1, 60 * 4 do
				local t = frame * dt
				if t >= nextLand then
					lastLand, nextLand = t, nextLand + 1 / rate
				end
				glare = BlasterFeel.glareStep(glare, dt, t - lastLand < shots.LightHold, shots.LightLevel)
				if t > shots.LightUp + dt then
					low, high = math.min(low, glare), math.max(high, glare)
				end
			end
			T.near(high - low, 0, 1e-6, rate .. " shots a second: no pulse at all")
			T.near(high, shots.LightLevel, 1e-6, rate .. " shots a second: at its level")
			-- the last shot: it fades, no jump
			local frames = 0
			while glare > 0 do
				local was = glare
				glare = BlasterFeel.glareStep(glare, dt, false, shots.LightLevel)
				T.le(was - glare, dt / shots.LightDown + 1e-9, "a soft fade")
				frames += 1
			end
			T.le(frames * dt, shots.LightDown + 2 * dt, "out in LightDown")
		end
		T.lt(1 / shots.SlowRate, shots.LightHold, "the slowest gap between shots keeps it on")
	end)

	-- a gun firing for real in BlasterShots: Env and Vfx stood in; returns what it flashed and its light
	local function firing(own: boolean, reduced: boolean, place: any?): any
		local Vfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Vfx")
		local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
		local BlasterShots = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BlasterShots")
		local out = { Muzzle = 0, Impact = 0, Sparks = 0, Shot = 0, Hit = 0, Bright = {} }
		local env = BlasterShots.Env
		local savedEnv, savedBurst, savedFolder = table.clone(env), Vfx.burst, Vfx.folder
		local fx = Instance.new("Folder")
		Vfx.folder = function()
			return fx
		end
		env.inWorld = function()
			return true
		end
		env.isPhone = function()
			return false
		end
		env.worldOf = function()
			return if place then place.Muzzle else Vector3.zero
		end
		local now = 1000
		env.clock = function()
			return now
		end
		local stepFn: any = nil
		env.connect = function(fn)
			stepFn = fn
			return {
				Disconnect = function()
					stepFn = nil
				end,
			}
		end
		env.move = function(parts, frames)
			for i, p in parts do
				p.CFrame = frames[i]
			end
		end
		env.emit = function()
			out.Muzzle += 1
		end
		Vfx.burst = function(kind: string)
			if kind == "Impact" then
				out.Impact += 1
			elseif kind == "Sparks" then
				out.Sparks += 1
			end
		end
		Motion.setReduced(reduced)
		local holder = Instance.new("Part")
		holder.Parent = fx
		if place then
			holder.CFrame = holder.CFrame + place.Hand
		end
		local muzzle = Instance.new("Attachment")
		muzzle.Parent = holder
		local key = {}
		local hooks = if own
			then {
				Shot = function()
					out.Shot += 1
				end,
				Hit = function(point: Vector3, back: Vector3)
					out.Hit += 1
					out.Back = back
					Vfx.impact(point, Color3.new(1, 0, 1), back, 1)
				end,
			}
			else nil
		local to = if place then place.To else Vector3.new(0, 0, -24)
		local ok, err = pcall(function()
			local dt = 1 / 30
			for frame = 1, 30 * 3 do
				now += dt
				BlasterShots.aim(key, muzzle, Vector3.zero, to, true, Color3.new(1, 0, 1), 10, if own then nil else 0.35, hooks)
				stepFn(dt)
				local lamp = out.Lamp
				if not lamp then
					for _, d in Vfx.folder():GetChildren() do
						if d.Name == "ShotLamp" then
							lamp = d
						end
					end
					out.Lamp = lamp
				end
				local light = lamp and lamp:FindFirstChildOfClass("PointLight")
				if light and frame * dt > 1 then
					table.insert(out.Bright, light.Brightness)
				end
			end
			BlasterShots.release(key)
		end)
		Motion.setReduced(false)
		-- let the shots in the air land and the module go back to sleep
		for _ = 1, 90 do
			now += 1 / 30
			if stepFn then
				stepFn(1 / 30)
			end
		end
		Vfx.burst, Vfx.folder = savedBurst, savedFolder
		for k, v in savedEnv do
			env[k] = v
		end
		if not ok then
			error(err)
		end
		return out
	end

	local function spread(list: { number }): number
		local low, high = math.huge, -math.huge
		for _, v in list do
			low, high = math.min(low, v), math.max(high, v)
		end
		return high - low
	end

	T.test("Shots: firing for real: separate shots, a steady light, your own hooks", function()
		local mine = firing(true, false)
		T.truthy(mine.Muzzle > 20, "muzzle flashes: " .. mine.Muzzle)
		T.truthy(mine.Impact > 20, "small impacts: " .. mine.Impact)
		T.eq(mine.Shot, mine.Muzzle, "your sound and recoil with each shot")
		T.truthy(mine.Hit > 20, "your hit pulses")
		T.truthy(#mine.Bright > 0, "the light was sampled")
		T.near(spread(mine.Bright), 0, 1e-6, "your gun's light never pulses")
		local theirs = firing(false, false)
		T.truthy(theirs.Impact > 10, "their small impacts: " .. theirs.Impact)
		T.near(spread(theirs.Bright), 0, 1e-6, "their gun's light never pulses")
		T.lt(theirs.Muzzle, mine.Muzzle, "their guns fire slower")
	end)

	T.test("Shots: close to a rock a shot still flies forward and lands (every gun is long)", function()
		local Shots = BlasterFeel.Shots
		local hand, muzzle = Vector3.new(0, 3, 0), Vector3.new(0, 3, -5.25) -- the gun's real reach, barrel along -Z
		local forward = Vector3.new(0, 0, -1)
		-- far enough: from the muzzle, as ever
		T.eq(BlasterFeel.shotStart(hand, muzzle, Vector3.new(0, 3, -24)), muzzle, "far: the muzzle")
		T.eq(BlasterFeel.shotStart(hand, muzzle, muzzle + forward * Shots.MinPath), muzzle, "just far enough: the muzzle")
		T.eq(BlasterFeel.shotStart(muzzle, muzzle, Vector3.new(0, 3, -24)), muzzle, "no gun length: the muzzle")
		T.eq(Shots.MinPath, 2.5, "a shot flies 2.5 studs when it can")
		T.eq(Shots.MinShot, 0.5, "a shorter one than half a stud is not drawn")
		-- right against a rock: from the hand, a shorter shot, never from behind the player's back
		T.eq(BlasterFeel.shotStart(hand, muzzle, hand + forward * 1.2), hand, "a rock 1.2 ahead: from the hand")
		T.eq(BlasterFeel.shotStart(hand, muzzle, hand + forward * 0.2), hand, "the hand in the rock: still the hand")
		-- every target from past the hand to beyond the muzzle, straight ahead and off to the sides
		for z = 0, 12, 0.25 do
			for _, side in { Vector3.zero, Vector3.new(1.5, 0, 0), Vector3.new(-3, -1, 0), Vector3.new(0, 2, 0) } do
				local to = hand + forward * z + side
				local start = BlasterFeel.shotStart(hand, muzzle, to)
				local path = to - start
				local label = string.format(" (a target %.2f ahead, %.1f aside)", z, side.Magnitude)
				-- as far as it can: MinPath, or all the way from the hand
				local can = math.min(Shots.MinPath, (to - hand).Magnitude)
				T.le(can - 1e-3, path.Magnitude, "it flies" .. label)
				T.le(0, path:Dot(forward), "forward" .. label)
				local along = (start - hand):Dot(forward)
				T.le(-1e-3, along, "never behind the hand" .. label)
				T.le(along, 5.25 + 1e-3, "never past the muzzle" .. label)
			end
		end
		-- the FIRE button's aim finds the rock's surface from the body (a ray from a muzzle inside the rock finds none)
		local mining = require("@lune/fs").readFile(Loader.root .. "/src/client/Controllers/MiningController.luau")
		T.truthy(string.find(mining, "surfacePoint(root.Position, rock)", 1, true), "aim assist from the body")
		-- a rock 2-6 studs ahead of the hand, firing for real: the shots, the flashes, the hits, all there
		for _, ahead in { 1, 2, 4, 5.25, 5.5, 6, 7 } do
			local out = firing(true, false, { Hand = hand, Muzzle = muzzle, To = hand + forward * ahead })
			local label = ahead .. " studs ahead: "
			T.lt(20, out.Muzzle, label .. "muzzle flashes: " .. out.Muzzle)
			T.lt(20, out.Hit, label .. "hit pulses: " .. out.Hit)
			T.lt(20, out.Impact, label .. "small impacts: " .. out.Impact)
			T.lt((out.Back :: any):Dot(forward), 0, label .. "the last shot flew forward")
		end
		-- the hand in the rock: no shots drawn, your sound and recoil still play
		local inside = firing(true, false, { Hand = hand, Muzzle = muzzle, To = hand + forward * 0.3 })
		T.eq(inside.Impact, 0, "the hand in the rock: nothing drawn")
		T.eq(inside.Muzzle, 0, "the hand in the rock: no muzzle flashes")
		T.lt(20, inside.Shot, "the hand in the rock: the sound and recoil still play: " .. inside.Shot)
	end)

	T.test("Shots: Reduce motion: no muzzle or impact flashes, a dim steady light", function()
		local shots = BlasterFeel.Shots
		for _, own in { true, false } do
			local out = firing(own, true)
			local label = if own then "your gun: " else "their gun: "
			T.eq(out.Muzzle, 0, label .. "no muzzle flashes")
			T.eq(out.Impact, 0, label .. "no impact flashes")
			T.near(spread(out.Bright), 0, 1e-6, label .. "a constant light")
			T.near(out.Bright[1], BlasterFeel.tier(10).Light * shots.ReducedLight, 1e-6, label .. "a dim one")
		end
		T.lt(shots.ReducedLight, shots.LightLevel, "dimmer than the normal one")
	end)

	T.test("Shots: other players' guns leave room for yours", function()
		local shots = BlasterFeel.Shots
		local range = BlasterData.Levels[BlasterData.MaxLevel].Range
		T.le(math.ceil(range / shots.Speed * shots.FastRate), shots.Reserve, "your longest stream fits the reserve")
		T.lt(shots.Reserve, shots.PhonePool, "others still fly on phones")
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
