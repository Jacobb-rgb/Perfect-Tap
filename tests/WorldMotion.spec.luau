-- World animations (client Effects/WorldMotionLogic + Controllers/WorldMotionController):
-- the golem hop / sway / happy jump curves, the ore pop's arc, pop-in and squash,
-- the hit flash / spikes / ore cubes, dust, the cash burst counts and motion, the
-- caps for phones and Reduce motion, the part pool's reuse, and the controller's
-- hooks on a rig in Lune (hits, pops, sales, golems; every part parked again).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local CFrame = roblox.CFrame
	local Instance = roblox.Instance
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.WorldMotionLogic")
	local CashBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.CashBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")

	local TAU = math.pi * 2
	local G = Logic.Golem
	local P = Logic.Pop
	local ORE = Color3.fromRGB(80, 170, 255)

	local function wrap(a: number): number
		return (a + math.pi) % TAU - math.pi
	end

	---------------------------------------------------------------- golems

	T.test("WorldMotion: the golem happy jump crouches, peaks at JumpHeight, spins once and ends at rest", function()
		local minLift, maxLift = math.huge, -math.huge
		local lastLift, lastYaw = 0, 0
		local yawAtLanding = 0
		local u = 0
		while u < G.JumpTime do
			local lift, _, yaw = Logic.golemPose(10, 0, 1, false, false, false, u, false)
			minLift, maxLift = math.min(minLift, lift), math.max(maxLift, lift)
			T.lt(math.abs(lift - lastLift), 0.35, "no jump in the lift at " .. u)
			T.lt(math.abs(wrap(yaw - lastYaw)), 0.7, "no jump in the turn at " .. u)
			lastLift, lastYaw = lift, yaw
			if u < G.JumpEnd then
				yawAtLanding = yaw
			end
			u += 1 / 60
		end
		T.near(minLift, -G.CrouchDepth, 0.01, "the crouch")
		T.near(maxLift, G.JumpHeight, 0.02, "the top of the jump")
		T.near(yawAtLanding, TAU, 0.05, "one whole turn by the landing")
		T.near(lastLift, 0, 0.06, "lands back on its feet")
		-- over: nothing (a far golem without a jump gets no extras)
		local lift, pitch, yaw, roll = Logic.golemPose(10, 0, 1, false, false, false, G.JumpTime, false)
		T.eq(lift + pitch + yaw + roll, 0, "after the jump, far: nothing")
		local l2 = Logic.golemPose(10, 0, 1, false, false, false, nil, false)
		T.eq(l2, 0, "far and no jump: nothing")
		-- far golems still jump on equip (it happens where you look)
		local mid = Logic.golemPose(10, 0, 1, false, false, false, (G.Crouch + G.JumpEnd) / 2, false)
		T.near(mid, G.JumpHeight, 0.02, "mid-jump while far")
	end)

	T.test("WorldMotion: Premium golems keep their hover: never sink, never hop, rise and spin on equip", function()
		local maxLift = 0
		for i = 0, 120 do
			local u = i / 120 * G.JumpTime
			local lift = Logic.golemPose(5, 0, 2, false, true, true, u, false)
			T.truthy(lift >= -1e-6, "a hovering golem never dips below its hover (" .. u .. ")")
			maxLift = math.max(maxLift, lift)
		end
		T.near(maxLift, G.FloatRise, 0.02, "the rise")
		for i = 0, 40 do
			local lift = Logic.golemPose(i * 0.37, i * 0.4, 3, true, true, true, nil, false)
			T.eq(lift, 0, "walking: it glides (no hop)")
		end
	end)

	T.test("WorldMotion: walking hops are rounder and wiggle left and right; standing sways and hops now and then", function()
		for i = 0, 200 do
			local phase = i / 200 * TAU
			local lift, pitch, yaw = Logic.golemPose(1, phase, 1, true, true, false, nil, false)
			T.truthy(lift >= -1e-9 and lift <= G.Hang, "extra hang time stays small and never sinks")
			T.le(math.abs(yaw), G.Wiggle + 1e-9, "wiggle")
			T.truthy(pitch <= 0 and pitch >= -G.Nod - 1e-9, "a forward nod")
		end
		local _, _, left = Logic.golemPose(1, math.pi / 2, 1, true, true, false, nil, false)
		local _, _, right = Logic.golemPose(1, math.pi * 1.5, 1, true, true, false, nil, false)
		T.truthy(left > 0 and right < 0, "the wiggle turns the other way on the next hop")
		-- standing: a sway and, within 20 s, at least one little hop in place (each golem at its own time)
		for _, seed in { 1, 2.7, 9.1 } do
			local hops = 0
			local wasUp = false
			for i = 0, 600 do
				local lift, _, yaw, roll = Logic.golemPose(i / 30, 0, seed, false, true, false, nil, false)
				T.truthy(lift >= -1e-9, "idle never sinks")
				T.le(math.abs(roll), G.Sway + 1e-9, "sway")
				T.le(math.abs(yaw), G.IdleWave + 1e-9, "wave")
				local up = lift > 0.2
				if up and not wasUp then
					hops += 1
				end
				wasUp = up
			end
			T.truthy(hops >= 2, "idle hops for seed " .. seed .. ": " .. hops)
		end
		local a = Logic.golemPose(3.3, 0, 1, false, true, false, nil, false)
		local b = Logic.golemPose(3.3, 0, 4.2, false, true, false, nil, false)
		local _ = a + b
		-- Reduce motion: only a small hop on equip, no spin
		for i = 0, 30 do
			local lift, pitch, yaw, roll = Logic.golemPose(i * 0.3, i * 0.5, 1, i % 2 == 0, true, false, nil, true)
			T.eq(lift + pitch + yaw + roll, 0, "Reduce motion: no extras")
		end
		local lift, _, yaw = Logic.golemPose(1, 0, 1, false, true, false, G.JumpTime / 2, true)
		T.truthy(lift > 0.3 and lift <= 0.5 + 1e-9, "Reduce motion: a small hop")
		T.eq(yaw, 0, "Reduce motion: no spin")
	end)

	---------------------------------------------------------------- ore pop

	T.test("WorldMotion: the ore pop grows in with an overshoot, arcs, spins once and lands on the real chunk", function()
		T.near(Logic.popScale(0), P.Start, 1e-9, "starts small")
		local peak = 0
		for i = 0, 100 do
			peak = math.max(peak, Logic.popScale(i / 100 * P.PopIn))
		end
		T.truthy(peak > 1.1 and peak < 1.22, "overshoot " .. peak)
		T.eq(Logic.popScale(P.PopIn), 1, "full size")
		local flight = 0.5
		local lift0, spin0 = Logic.popPose(0, flight, nil)
		T.near(lift0, 0, 1e-9, "the arc starts on the real chunk")
		T.near(spin0, 0, 1e-9, "no turn yet")
		local top = Logic.popPose(flight / 2, flight, nil)
		T.near(top, P.Lift, 1e-6, "the top of the arc")
		local liftEnd = Logic.popPose(flight, flight, nil)
		T.near(liftEnd, 0, 1e-6, "back on the real chunk at the landing")
		local lastSpin = 0
		for i = 1, 60 do
			local _, spin = Logic.popPose(i / 60 * flight, flight, nil)
			T.truthy(spin >= 0 and spin < TAU, "spin in one turn")
			if spin > 0 then
				T.truthy(spin >= lastSpin - 1e-9, "turns one way")
				lastSpin = spin
			end
		end
		-- a landing: squash, then settle exactly
		local landed = 0.45
		local _, spinAfter, wide, tall = Logic.popPose(landed, flight, landed)
		T.eq(spinAfter, 0, "the turn is done by the landing")
		T.near(tall, 1 - P.Squash, 1e-6, "flat on impact")
		T.truthy(wide > 1.1, "and wide")
		local _, _, w2, t2, done = Logic.popPose(landed + P.SquashTime, flight, landed)
		T.truthy(done and w2 == 1 and t2 == 1, "settled and done")
		local _, _, _, _, late = Logic.popPose(P.MaxTime, 0.3, nil)
		T.truthy(late, "a pop always ends")
		-- the squash keeps about the same volume and ends smoothly
		for i = 0, 40 do
			local u = i / 40 * P.SquashTime
			local sw, st = Logic.squash(u)
			T.near(sw * sw * st, 1, 1e-6, "volume at " .. u)
		end
		local _, nearEnd = Logic.squash(P.SquashTime - 1e-3)
		T.near(nearEnd, 1, 0.02, "no snap at the end")
		-- predicted landing time: the ballistic fall really is at the ground then
		local vy, h, g = 16, 3, 196.2
		local tl = Logic.landTime(vy, h, g)
		T.near(h + vy * tl - 0.5 * g * tl * tl, 0, 1e-6, "lands then")
		T.truthy(Logic.landed(-12, -1, 0.3, 0.4), "a sharp stop is a landing")
		T.falsy(Logic.landed(-12, -11, 0.3, 0.4), "still falling")
		T.falsy(Logic.landed(4, 3, 0.1, 0.4), "still rising")
		T.truthy(Logic.landed(0, 0, 0.8, 0.4), "no fall seen: landed after its flight")
		-- the look-alike's parts: exactly on the real ones at rest, squashed along the body's up axis
		local body = CFrame.new(3, 1, -2) * CFrame.Angles(0.3, 1.2, -0.4)
		local offset = CFrame.new(0.4, 0.42, -0.1) * CFrame.Angles(0.4, 0.2, -0.5)
		local size = Vector3.new(0.9, 0.7, 0.8)
		local cf, s = Logic.popPart(Logic.popRoot(body, 0, 0, 0), Vector3.one, offset, size)
		T.near((cf.Position - (body * offset).Position).Magnitude, 0, 1e-5, "on the real part")
		T.near((s - size).Magnitude, 0, 1e-6, "its real size")
		local flatBody = CFrame.new(0, 1, 0)
		local axes = Logic.squashAxes(flatBody, 1.2, 0.7)
		T.near(axes.Y, 0.7, 1e-6, "squashed along up")
		T.near(axes.X, 1.2, 1e-6, "wide on the sides")
		local sideways = Logic.squashAxes(CFrame.Angles(0, 0, math.pi / 2), 1.2, 0.7)
		T.near(sideways.X, 0.7, 1e-6, "a chunk on its side squashes along its own X")
		local _, liftedSize = Logic.popPart(Logic.popRoot(flatBody, 2, 0, 0), axes, CFrame.identity, Vector3.one)
		T.near(liftedSize.Y, 0.7, 1e-6)
	end)

	---------------------------------------------------------------- bits

	T.test("WorldMotion: a hit is one white flash, a star of spikes and ore cubes (fewer on phones and with Reduce motion)", function()
		T.eq(select(1, Logic.hitCounts(false, false, false)), 6, "PC spikes")
		T.eq(select(2, Logic.hitCounts(false, false, false)), 5, "PC cubes")
		T.eq(select(1, Logic.hitCounts(true, false, false)), 4, "phone spikes")
		T.eq(select(2, Logic.hitCounts(true, false, false)), 3, "phone cubes")
		T.eq(select(1, Logic.hitCounts(false, true, false)), 0, "Reduce motion: no spikes")
		local s1, c1 = Logic.hitCounts(false, false, true)
		T.truthy(s1 < 6 and c1 < 5, "another player's hit is smaller")
		local back = Vector3.new(0, 0, 1)
		local bits = Logic.hitPlan({
			Position = Vector3.new(0, 2, 0),
			Back = back,
			Color = ORE,
			Right = Vector3.new(1, 0, 0),
			Up = Vector3.new(0, 1, 0),
			Ground = 0,
			Seed = 3,
		})
		T.eq(#bits, 1 + 6 + 5, "flash + spikes + cubes")
		T.eq(bits[1].Kind, "Flash")
		T.truthy(bits[1].Neon and bits[1].Color == Color3.new(1, 1, 1), "a white glowing flash")
		local normal = Vector3.new(0, 0, 1)
		for _, bit in bits do
			T.le(bit.Life, 0.75, "short")
			local cf, size, transparency = Logic.sample(bit, 0.001)
			T.truthy(size.X > 0 and size.Y > 0 and size.Z > 0, "a real size")
			T.le(transparency, 0.3, "visible at the start")
			local _, _, _, done = Logic.sample(bit, bit.Life + 1e-3)
			T.truthy(done, bit.Kind .. " done after its life")
			if bit.Kind == "Spike" then
				-- in the plane facing the camera, moving out
				local a = Logic.sample(bit, bit.Life * 0.2).Position - bit.Origin
				local b = Logic.sample(bit, bit.Life * 0.8).Position - bit.Origin
				T.near(a:Dot(normal), 0, 1e-4, "in the camera plane")
				T.truthy(b.Magnitude > a.Magnitude, "shoots out")
				local _ = cf
			elseif bit.Kind == "Cube" then
				T.truthy(bit.Velocity:Dot(back) > 0 and bit.Velocity.Y > 0, "sprays back toward the shooter and up")
				local h = bit.Color:ToHSV()
				local oh = ORE:ToHSV()
				T.near(h, oh, 0.02, "in the ore's colour (or its tints)")
				for i = 0, 20 do
					local p = Logic.sample(bit, i / 20 * bit.Life)
					T.truthy(p.Position.Y >= bit.Ground - 1e-6, "never below the ground")
				end
			end
		end
		local room = Logic.hitPlan({
			Position = Vector3.zero,
			Color = ORE,
			Right = Vector3.xAxis,
			Up = Vector3.yAxis,
			Ground = 0,
			Seed = 1,
			Room = 4,
		})
		T.eq(#room, 4, "a full pool gives fewer")
		T.eq(#Logic.hitPlan({
			Position = Vector3.zero,
			Color = ORE,
			Right = Vector3.xAxis,
			Up = Vector3.yAxis,
			Ground = 0,
			Seed = 1,
			Room = 0,
		}), 0)
		local reduced = Logic.hitPlan({
			Position = Vector3.zero,
			Color = ORE,
			Right = Vector3.xAxis,
			Up = Vector3.yAxis,
			Ground = 0,
			Seed = 1,
			Reduce = true,
		})
		T.eq(#reduced, 1 + 2, "Reduce motion: the flash and two cubes")
	end)

	T.test("WorldMotion: dust puffs up and out where a chunk pops and spreads flat where it lands", function()
		for _, landing in { false, true } do
			local n = Logic.dustCount(false, false, landing)
			local bits = Logic.dustPlan({
				Position = Vector3.new(0, 3, 0),
				Color = Color3.fromRGB(150, 130, 110),
				Ground = 0,
				Seed = 5,
				Landing = landing,
				Count = n,
			})
			T.eq(#bits, n)
			for _, bit in bits do
				T.eq(bit.Kind, "Dust")
				T.le(bit.Life, 0.6, "short")
				if landing then
					T.truthy(bit.Velocity.Y < 2.5 and Vector3.new(bit.Velocity.X, 0, bit.Velocity.Z).Magnitude > 6, "flat ring")
				else
					T.truthy(bit.Velocity.Y > 2, "puffs up")
				end
				for i = 0, 10 do
					local cf = Logic.sample(bit, i / 10 * bit.Life)
					T.truthy(cf.Position.Y >= bit.Ground, "never below the ground")
				end
			end
		end
		T.truthy(Logic.dustCount(true, false, true) < Logic.dustCount(false, false, true), "fewer on phones")
		T.le(Logic.dustCount(false, true, false), 3, "Reduce motion")
	end)

	T.test("WorldMotion: the cash burst scales with the items, is capped, halves on phones and is a third with Reduce motion", function()
		local n1, c1 = Logic.cashCounts(1, false, false)
		T.eq(n1, 4, "one item: notes")
		T.eq(c1, 4, "one item: coins")
		local n, c = Logic.cashCounts(500, false, false)
		T.eq(n, Logic.Cash.Notes[2], "notes cap")
		T.eq(c, Logic.Cash.Coins[2], "coins cap")
		T.le(n + c, 24, "a few dozen parts at most")
		local pn, pc = Logic.cashCounts(500, true, false)
		T.truthy(pn <= math.ceil(n / 2) and pc <= math.ceil(c / 2), "half on phones")
		local rn, rc = Logic.cashCounts(500, false, true)
		T.truthy(rn <= math.ceil(n * 0.34) and rc <= math.ceil(c * 0.34) and rn >= 1 and rc >= 1, "a third with Reduce motion")
		T.eq(select(1, Logic.cashCounts(0 / 0, false, false)), n1, "a broken count is one item")
		T.eq(Logic.Cash.Note, CashBuilder.Note, "the notes are the HUD's banknote green")
		T.eq(Logic.Cash.NoteLight, CashBuilder.NoteLight)
		T.eq(Logic.Cash.Coin, Theme.Coin, "the coins are the HUD's coin gold")
		local home = Vector3.new(6, 2, 0)
		local bits = Logic.cashPlan({ Position = Vector3.new(0, 0, 0), Ground = 0, Home = home, Seed = 2, Items = 8 })
		local notes, coins = 0, 0
		for _, bit in bits do
			if bit.Kind == "Note" then
				notes += 1
				T.eq(bit.Shape, "Block")
				-- rises, then flutters down; lies flat once it is down
				local top = 0
				for i = 0, 40 do
					local cf = Logic.sample(bit, i / 40 * bit.Life)
					top = math.max(top, cf.Position.Y)
					T.truthy(cf.Position.Y >= bit.Ground, "never below the ground")
				end
				T.truthy(top - bit.Origin.Y > 1.8, "flies up out of the stall")
				local slow = Logic.sample(bit, 3)
				T.near(slow.UpVector.Y, 1, 1e-4, "lies flat on the ground")
			else
				coins += 1
				T.eq(bit.Kind, "Coin")
				T.eq(bit.Shape, "Cylinder")
				local cf = Logic.sample(bit, bit.Life - 1e-4)
				T.lt((cf.Position - home).Magnitude, 0.2, "flies into the player")
			end
		end
		T.eq(notes, select(1, Logic.cashCounts(8, false, false)))
		T.eq(coins, select(2, Logic.cashCounts(8, false, false)))
		local tight = Logic.cashPlan({ Position = Vector3.zero, Ground = 0, Seed = 2, Items = 8, Room = 5 })
		local tn, tc = 0, 0
		for _, bit in tight do
			if bit.Kind == "Note" then
				tn += 1
			else
				tc += 1
			end
		end
		T.truthy(tn + tc <= 5 and tn >= 1 and tc >= 1, "a full pool: fewer of both, one of each")
		-- no player near: the coins just fall and fade
		for _, bit in tight do
			if bit.Kind == "Coin" then
				local cf = Logic.sample(bit, bit.Life * 0.99)
				T.near(cf.Position.Y, bit.Ground + bit.Size.Y / 2, 0.05, "on the ground")
			end
		end
	end)

	T.test("WorldMotion: caps halve on phones, Reduce motion drops the look-alikes, spikes and spins; budget", function()
		local pc = Logic.caps(false, false)
		local phone = Logic.caps(true, false)
		local reduce = Logic.caps(false, true)
		T.eq(pc.Bits, Logic.Caps.PC.Bits)
		T.eq(phone.Bits, Logic.Caps.Phone.Bits)
		T.truthy(phone.Bits * 2 <= pc.Bits and phone.Pops * 2 <= pc.Pops, "half on phones")
		T.eq(reduce.Pops, 0, "Reduce motion: no pop look-alikes")
		T.falsy(reduce.Spikes)
		T.falsy(reduce.Spin)
		T.le(reduce.Bits, pc.Bits / 2)
		T.le(pc.Bits, 64, "phones-first budget")
		T.eq(Logic.budget(10, 60, 64), 4)
		T.eq(Logic.budget(10, 70, 64), 0)
		T.eq(Logic.budget(3, 0, 64), 3)
	end)

	T.test("WorldMotion: the pool hands its parts out again and never makes more than its cap", function()
		local made = 0
		local pool = Logic.newPool(function()
			made += 1
			return { Id = made }
		end, 3)
		local a, b, c = Logic.take(pool), Logic.take(pool), Logic.take(pool)
		T.eq(made, 3)
		T.eq(Logic.take(pool), nil, "full")
		Logic.give(pool, a)
		Logic.give(pool, b)
		local again = Logic.take(pool)
		T.truthy(again == a or again == b, "an idle one again")
		Logic.give(pool, c)
		Logic.take(pool)
		Logic.take(pool)
		T.eq(made, 3, "nothing new made")
		T.eq(pool.Made, 3)
	end)

	T.test("WorldMotion: machines (proposal helpers): a small rumble with the heat, a hop and a glow flash when a job is done", function()
		local M = Logic.Machine
		T.eq(Logic.machineShake(1, 0, 1), CFrame.identity, "idle: still")
		for i = 0, 200 do
			local cf = Logic.machineShake(i / 60, 1, 3)
			T.le(Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude, M.Shake * 1.42, "rumble stays tiny")
			T.near(cf.Position.Y, 0, 1e-9, "never lifts off its base")
			local half = Logic.machineShake(i / 60, 0.5, 3)
			T.le(half.Position.Magnitude, M.Shake * 0.72, "half the heat, half the rumble")
		end
		T.eq(Logic.machinePop(-0.1), CFrame.identity)
		T.eq(Logic.machinePop(M.PopTime), CFrame.identity, "back on its base after the hop")
		local top = 0
		for i = 0, 60 do
			local cf = Logic.machinePop(i / 60 * M.PopTime)
			T.truthy(cf.Position.Y >= -1e-9, "never sinks")
			top = math.max(top, cf.Position.Y)
		end
		T.near(top, M.PopLift, 0.01, "the hop")
		T.eq(Logic.machineGlow(-1), 0)
		T.eq(Logic.machineGlow(M.GlowTime), 0, "the flash is over")
		T.near(Logic.machineGlow(M.GlowTime * 0.15), 1, 1e-9, "a quick flash")
	end)

	---------------------------------------------------------------- the controller on a rig

	T.test("WorldMotionController: hooks run in Lune on a rig and every part is pooled and parked again", function()
		local Players = Loader.game:GetService("Players")
		local hadLocal = rawget(Players, "LocalPlayer")
		local me = { Name = "Me", UserId = 1 }
		rawset(Players, "LocalPlayer", me)
		local ok, err = pcall(function()
			local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldMotionController")
			local folder = Instance.new("Folder")
			local rig = {
				Folder = folder,
				Eye = Vector3.new(0, 6, 20),
				Right = Vector3.new(1, 0, 0),
				Up = Vector3.new(0, 1, 0),
				Ground = 0,
				Clock = 100,
				Phone = false,
				Reduce = false,
				Firing = true,
				Root = Vector3.new(2, 3, 8),
				Gravity = 196.2,
			}
			Controller.useRig(rig)
			local function run(seconds: number)
				local frames = math.ceil(seconds * 30)
				for _ = 1, frames do
					rig.Clock += 1 / 30
					Controller.step(1 / 30)
				end
			end

			-- another player's hit, then your own (a Health drop while firing)
			Controller.onFx("BlastHit", Vector3.new(0, 2, 0), Color3.fromRGB(255, 150, 70), 1, { Name = "Other" })
			local bits, _, fl = Controller.stats()
			T.truthy(bits > 0 and fl == 1, "a flash and its bits")
			local rock = Instance.new("Model")
			local stone = Instance.new("Part")
			stone.Size = Vector3.new(4, 4, 4)
			stone.CFrame = CFrame.new(0, 2, 0)
			stone.Parent = rock
			local crystal = Instance.new("Part")
			crystal.Material = roblox.Enum.Material.Neon
			crystal.Color = ORE
			crystal.Parent = rock
			rock.PrimaryPart = stone
			Controller.onHealthDrop(rock)
			local bits2, _, fl2 = Controller.stats()
			T.truthy(bits2 > bits and fl2 == 2, "your hit adds a flash")
			Controller.onHealthDrop(rock)
			T.eq(select(3, Controller.stats()), 2, "one flash per rock per Gap")
			local cubes = 0
			for _, part in folder:GetChildren() do
				if part.Transparency < 1 and part.Color == ORE then
					cubes += 1
				end
			end
			T.truthy(cubes >= 1, "cubes in the rock's crystal colour")

			-- a sale near you: notes and coins
			Controller.onEarned({ Source = "Sell", Position = Vector3.new(4, 0, 0), Count = 6, Amount = 120 })
			Controller.onEarned({ Source = "Offline", Position = Vector3.new(4, 0, 0), Count = 6 })
			Controller.onEarned("junk")
			local bits3 = Controller.stats()
			T.truthy(bits3 > bits2, "the cash burst")

			-- a fresh chunk next to a crack pops (the Fx first, then the chunk)
			local items = Instance.new("Folder")
			local chunk = ItemBuilder.build({ Kind = "Raw", OreId = "Copper" }, CFrame.new(0, 4, 1), 7)
			chunk:SetAttribute("Kind", "Raw")
			chunk:SetAttribute("State", "Loose")
			-- (Lune has no default for it; Roblox starts every part at 0)
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
			chunk.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 16, 6)
			chunk.Parent = items
			Controller.onFx("NodeCrack", Vector3.new(0, 2.5, 1.5), Color3.fromRGB(150, 130, 110), 2, nil, 4)
			Controller.onItemAdded(chunk)
			local _, pops = Controller.stats()
			T.eq(pops, 1, "the chunk pops")
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					T.eq(d.LocalTransparencyModifier, 1, "the real chunk is hidden on this client while its look-alike pops")
				end
			end
			Controller.onItemAdded(chunk)
			T.eq(select(2, Controller.stats()), 1, "once per chunk")
			-- the chunk falls and lands (what physics would do)
			local body = chunk.PrimaryPart
			for i = 1, 6 do
				rig.Clock += 1 / 30
				body.AssemblyLinearVelocity = Vector3.new(0, 16 - i * 6.5, 6)
				Controller.step(1 / 30)
			end
			body.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			run(3)
			local b, p, f, made = Controller.stats()
			T.eq(b + p + f, 0, "all done within 3 s")
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					T.eq(d.LocalTransparencyModifier, 0, "the real chunk shows again")
				end
			end
			for _, part in folder:GetChildren() do
				T.eq(part.Transparency, 1, "parked: hidden")
				T.truthy(part.CFrame.Position.Y < -1000, "parked: out of the way")
				T.falsy(part.CanCollide or part.CanQuery or part.CanTouch, "never collides, never queried")
				T.truthy(part.Anchored, "anchored")
			end
			-- the same again reuses the pooled parts
			Controller.onFx("BlastHit", Vector3.new(0, 2, 0), Color3.fromRGB(255, 150, 70), 1, { Name = "Other2" })
			rig.Clock += 1
			Controller.onHealthDrop(rock)
			Controller.onEarned({ Source = "Sell", Position = Vector3.new(4, 0, 0), Count = 6, Amount = 120 })
			run(3)
			T.eq(select(4, Controller.stats()), made, "no new parts: the pool is reused")

			-- caps: many hits at once never go over the flash and bit caps
			for i = 1, 30 do
				Controller.onFx("BlastHit", Vector3.new(i * 0.1, 2, 0), Color3.fromRGB(255, 150, 70), 1, { Name = "P" .. i })
			end
			local cb, _, cf = Controller.stats()
			T.le(cf, Logic.Caps.PC.Flashes, "flash cap")
			T.le(cb, Logic.Caps.PC.Bits, "bit cap")
			run(2)
			-- far away or a phone with Reduce motion
			Controller.onFx("BlastHit", Vector3.new(0, 2, 500), Color3.new(1, 1, 1), 1, { Name = "Far" })
			T.eq(select(1, Controller.stats()), 0, "far hits are skipped")
			rig.Phone, rig.Reduce = true, true
			Controller.useRig(rig)
			Controller.onEarned({ Source = "Sell", Position = Vector3.new(4, 0, 0), Count = 50, Amount = 900 })
			local pb = Controller.stats()
			local rn, rc = Logic.cashCounts(50, true, true)
			T.le(pb, rn + rc, "phone + Reduce motion: a small burst")
			local chunk2 = ItemBuilder.build({ Kind = "Raw", OreId = "Copper" }, CFrame.new(0, 4, 1), 8)
			chunk2:SetAttribute("Kind", "Raw")
			chunk2:SetAttribute("State", "Loose")
			for _, d in chunk2:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
			chunk2.Parent = items
			Controller.onItemAdded(chunk2)
			Controller.onFx("NodeShatter", Vector3.new(0, 2, 0), Color3.fromRGB(150, 130, 110), Color3.new(1, 0.5, 0), 1, "Big", 2)
			T.eq(select(2, Controller.stats()), 0, "Reduce motion: dust only, no look-alike")
			run(2)

			-- golems: a kind that was just equipped jumps, one that was on already doesn't
			rig.Phone, rig.Reduce = false, false
			Controller.useRig(rig)
			local owner = { Name = "Owner" } :: any
			Controller.noteEquipped(owner, "PebbleGolem", 49)
			Controller.noteEquipped(owner, "PebbleGolem,EmberImp", 50)
			local fresh = { Kind = "EmberImp", Phase = 0, Seed = 1, Floats = false }
			local old = { Kind = "PebbleGolem", Phase = 0, Seed = 2, Floats = false }
			local first = Controller.golemOffset(fresh, owner, 50.2, false, true)
			local _ = first
			local mid = Controller.golemOffset(fresh, owner, 50.2 + (G.Crouch + G.JumpEnd) / 2, false, true)
			T.truthy(mid.Position.Y > G.JumpHeight * 0.9, "the new golem jumps")
			local still = Controller.golemOffset(old, owner, 50.5, false, true)
			T.truthy(still.Position.Y < 0.5, "the golem that was on already doesn't jump")
			T.eq(Controller.golemOffset(old, owner, 60, true, false), CFrame.identity, "far: nothing")
			local late = { Kind = "EmberImp", Phase = 0, Seed = 3, Floats = false }
			T.truthy(Controller.golemOffset(late, owner, 70, false, true).Position.Y < 0.5, "built long after the equip: no jump")
			Controller.useRig(nil)
		end)
		rawset(Players, "LocalPlayer", hadLocal)
		if not ok then
			error(err, 0)
		end
	end)

	T.test("WorldMotionController: the GolemController hook is one call per follower and the controller is in the client ORDER", function()
		local fs = require("@lune/fs")
		local golem = fs.readFile(Loader.root .. "/src/client/Controllers/GolemController.luau")
		local _, calls = string.gsub(golem, "WorldMotionController%.golemOffset%(", "")
		T.eq(calls, 1, "one hook")
		local init = fs.readFile(Loader.root .. "/src/client/init.client.luau")
		T.truthy(string.find(init, '"WorldMotionController"', 1, true) ~= nil, "in ORDER")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/WorldMotionController.luau")
		T.falsy(string.find(source, "BindAction", 1, true), "binds no inputs (E prompts, F grab)")
		local _, loops = string.gsub(source, "RenderStepped:Connect", "")
		local _, beats = string.gsub(source, "Heartbeat:Connect", "")
		T.eq(loops + beats, 1, "one RunService loop")
	end)
end
