--[[
	The elevator's travel cinematic, its pure pieces under Lune: the cabin and
	shaft set (Builders/ElevatorCabinStage: the phone budget, nothing anyone can
	touch or hit, the doors, where the cabin stands, the shaft only behind shut
	doors and never inside the cabin, the digital counter, the fade, the camera
	in the cabin and back behind the player), the mines' arrival effects
	(Builders/ElevatorArrivalFx) and the words on screen (UI/ElevatorTravelView),
	with and without Reduce motion.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local Config = Loader.requirePath("ReplicatedStorage.Shared.Config.ElevatorTravelConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.ElevatorCabinStage")
	local Fx = Loader.requirePath("ReplicatedStorage.Shared.Builders.ElevatorArrivalFx")
	local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorTravelView")
	local timing = Config.Timing

	local FROM = CFrame.new(100, -12, -180) * CFrame.Angles(0, 0.7, 0)
	local TO = CFrame.new(-28, -296, -751) * CFrame.Angles(0, -math.pi / 2, 0)

	local function pose(stage: any, plan: any, t: number, reduced: boolean?): any
		local p = {
			T = t,
			Travel = Stage.travelAt(plan, t),
			Speed = Stage.speedAt(plan, t),
			Reduced = reduced == true,
			FromAt = FROM,
			StopAt = TO,
		}
		Stage.pose(stage, plan, p)
		return p
	end

	-- a point in the frame of a stop
	local function local_(at: any, part: any): any
		return at:PointToObjectSpace(part.CFrame.Position)
	end

	T.test("cabin stage: within the phone budget, nothing anyone can touch, hit or stand on", function()
		local stage = Stage.build()
		local parts = Stage.parts(stage)
		T.truthy(#parts >= 120, "a detailed set: " .. #parts)
		T.le(#parts, 260, "phone budget: " .. #parts .. " parts")
		local lights, emitters = 0, 0
		for _, part in parts do
			T.truthy(part.Anchored, part.Name .. " anchored")
			T.falsy(part.CanCollide, part.Name .. " no collisions")
			T.falsy(part.CanQuery, part.Name .. " no raycasts (the camera and the blaster pass)")
			T.falsy(part.CanTouch, part.Name .. " no touch")
			for _, child in part:GetChildren() do
				if child:IsA("PointLight") then
					lights += 1
					T.falsy(child.Shadows, "no light shadows (phones)")
				elseif child:IsA("ParticleEmitter") then
					emitters += 1
					T.eq(child.Rate, 0, "emitters start quiet")
				end
			end
		end
		T.le(lights, 6, "a few lights")
		T.le(emitters, 9, "a few pooled emitters")
		-- nothing is in the world until a ride
		T.eq(stage.CabinFolder.Parent, nil, "cabin off")
		T.eq(stage.ShaftFolder.Parent, nil, "shaft off")
	end)

	T.test("cabin stage: the shaft never reaches into the cabin or the shut doors", function()
		local stage = Stage.build()
		-- the cabin's outer box with the doors shut (stage frame): |x| <= 3.15, z -3.14 .. 3.35
		for _, ring in stage.Rings do
			for i, part in ring.Group.Parts do
				local cf = ring.Group.Rest[i]
				local half = part.Size / 2
				local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
				local ex = math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z
				local ez = math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
				local p = cf.Position
				local inside = p.X + ex > -3.15 and p.X - ex < 3.15 and p.Z + ez > -3.14 and p.Z - ez < 3.35
				T.falsy(inside, `ring {ring.Slot} {part.Name} stays out of the cabin`)
			end
		end
	end)

	T.test("cabin stage: the doors, the cabin's place and the shaft follow the plan", function()
		local stage = Stage.build()
		local plan = Config.plan(2, 5)
		-- the preparation: only the beacon on the real cage, flashing
		pose(stage, plan, 0.1)
		T.eq(stage.BeaconFolder.Parent, stage.Folder, "the beacon is out")
		T.eq(stage.CabinFolder.Parent, nil, "no cabin yet (the real cage is seen)")
		T.near((local_(FROM, stage.Beacon) - Vector3.new(0, 8.25, -2.75)).Magnitude, 0, 1e-4, "on the cage's roof")
		T.truthy(stage.BeaconLight.Brightness > 0, "lit in a flash")
		pose(stage, plan, 0.3)
		T.eq(stage.BeaconLight.Brightness, 0, "dark between the flashes")
		-- behind the dip: the cabin over the stop left, the doors open
		pose(stage, plan, plan.DipMid + 0.01)
		T.eq(stage.BeaconFolder.Parent, nil, "the beacon goes")
		T.eq(stage.CabinFolder.Parent, stage.Folder, "the cabin is in")
		T.eq(stage.ShaftFolder.Parent, nil, "no shaft while the doors are open")
		local floor = stage.Cabin.Parts[1]
		T.near((local_(FROM, floor) - stage.Cabin.Rest[1].Position).Magnitude, 0, 1e-4, "over the stop left")
		local left = stage.DoorLeft.Parts[1]
		T.truthy(local_(FROM, left).X < -Stage.DoorHalf, "the left door is open")
		-- the doors meet: the shaft appears around the cabin
		pose(stage, plan, plan.DoorsShut + 0.01)
		T.near(Stage.closedness(plan, plan.DoorsShut), 1, 1e-9, "shut")
		T.truthy(local_(FROM, left).X < 0 and local_(FROM, left).X > -Stage.DoorHalf, "the left door is shut")
		T.eq(stage.ShaftFolder.Parent, stage.Folder, "the shaft rushes past")
		-- every ring stays in the column round the cabin
		local mid = plan.TravelStart + 1.2
		pose(stage, plan, mid)
		for _, ring in stage.Rings do
			local y = local_(FROM, ring.Group.Parts[1]).Y
			T.truthy(y >= Stage.RingLow - 0.01 and y <= Stage.RingLow + Stage.RingHeight * Stage.RingCount + 0.01, "ring in the column")
			T.truthy(ring.PaintKey >= 2 and ring.PaintKey <= 5, "painted with a floor on the way")
		end
		T.truthy(Stage.speedAt(plan, mid) == 1, "full speed mid-ride")
		-- the stop: the cabin now stands at the target stop, the shaft is gone
		pose(stage, plan, plan.StopAt + 0.01)
		T.eq(stage.ShaftFolder.Parent, nil, "no shaft at the stop")
		T.near((local_(TO, floor) - stage.Cabin.Rest[1].Position).Magnitude, 0, 1e-4, "at the target stop")
		-- the doors open; on the way out the cabin fades
		pose(stage, plan, plan.OpenedAt + 0.01)
		T.truthy(local_(TO, left).X < -Stage.DoorHalf + 0.01, "open again")
		pose(stage, plan, plan.EndAt - 0.01)
		for _, entry in stage.Fade do
			T.truthy(entry.Part.Transparency > 0.97, entry.Part.Name .. " faded")
		end
		pose(stage, plan, plan.EndAt + 0.01)
		T.eq(stage.CabinFolder.Parent, nil, "gone at the end")
		Stage.reset(stage)
		for _, entry in stage.Fade do
			T.eq(entry.Part.Transparency, entry.Base, "solid again for the next ride")
		end
	end)

	T.test("cabin stage: the digital counter counts to the target in each floor's colour", function()
		local stage = Stage.build()
		local plan = Config.plan(1, 4)
		local function shown(): number?
			local ones = stage.Digits[2]
			for n = 0, 9 do
				local match = true
				for s = 1, 7 do
					local lit = ones[s].Transparency < 0.5
					if lit ~= Stage.segmentOn(n, s) then
						match = false
					end
				end
				if match then
					return n
				end
			end
			return nil
		end
		pose(stage, plan, plan.DipMid + 0.05)
		T.eq(shown(), 1, "the floor left")
		for _, tick in plan.Ticks do
			pose(stage, plan, tick.Time + 0.3)
			T.eq(shown(), tick.Floor, "floor " .. tick.Floor)
			T.eq(stage.Digits[2][1].Color, Stage.floorGlow(tick.Floor), "in its colour")
		end
		pose(stage, plan, plan.StopAt + 0.5)
		T.eq(shown(), 4, "the target")
		-- a single-digit floor leaves the tens dark
		for _, seg in stage.Digits[1] do
			T.truthy(seg.Transparency > 0.9, "no tens digit")
		end
		-- every number has its segments (8 lights all, 1 two)
		local all, one = 0, 0
		for s = 1, 7 do
			all += if Stage.segmentOn(8, s) then 1 else 0
			one += if Stage.segmentOn(1, s) then 1 else 0
		end
		T.eq(all, 7)
		T.eq(one, 2)
	end)

	T.test("cabin stage: Reduce motion: no shake, no hard flash, no flicker, no light streaks", function()
		local plan = Config.plan(1, 6)
		for k = 0, 120 do
			local t = k * 0.05
			local x, y = Stage.shakeAt(plan, t, 1, true)
			T.eq(x, 0)
			T.eq(y, 0)
			T.le(Stage.flashAt(plan, t, true), 0.6, "a soft swell at most")
			T.eq(Stage.lightLevel(plan, t, true), 1, "no flicker")
			local beacon = Stage.warnAt(plan, t, true, true)
			T.truthy(beacon == 0 or beacon == 0.7, "a steady glow, no flash")
		end
		-- with motion: the jolt and the stop's bump shake the camera; one flash at the stop
		local _, jolt = Stage.shakeAt(plan, plan.DoorsShut + 0.12, 0, false)
		T.truthy(jolt < -0.05, "the cabin jolts")
		T.truthy(Stage.flashAt(plan, plan.StopAt + 0.05, false) > 2, "the stop's flash")
		T.eq(Stage.flashAt(plan, plan.StopAt + 0.5, false), 0, "and only one")
		local stage = Stage.build()
		pose(stage, plan, plan.TravelStart + 1, true)
		for _, part in stage.Streaks.Parts do
			T.eq(part.Transparency, 1, "no light streaks")
		end
		for i, e in stage.Emitters do
			if (i - 1) % 3 == 2 then
				T.eq(e.Rate, 0, "no streak particles")
			end
		end
	end)

	T.test("cabin stage: the camera stands in the cabin, then glides back behind the player", function()
		local plan = Config.plan(3, 1)
		local target = TO * CFrame.new(0, 3.6, -3.9)
		local info = { FromAt = FROM, StopAt = TO, Target = target, Zoom = 12, Fov = 75, Reduced = false, Speed = 1, CutAt = nil }
		local before = Stage.camera(plan, 0.3, info)
		T.eq(before, nil, "the game's own camera in the preparation")
		for _, t in { plan.DipMid + 0.02, plan.DoorsShut + 0.5, plan.BrakeAt, plan.StopAt - 0.01 } do
			local cf = Stage.camera(plan, t, info)
			local p = FROM:PointToObjectSpace(cf.Position)
			T.truthy(math.abs(p.X) < Stage.HalfWidth and p.Z > Stage.FrontZ and p.Z < Stage.BackZ, "inside the cabin at " .. t)
			T.truthy(cf.LookVector:Dot(FROM.LookVector) > 0.9, "looking at the doors")
		end
		local atStop = Stage.camera(plan, plan.StopAt + 0.1, info)
		local q = TO:PointToObjectSpace(atStop.Position)
		T.truthy(math.abs(q.X) < Stage.HalfWidth and q.Z < Stage.BackZ, "in the cabin at the target stop")
		local final, fov = Stage.camera(plan, plan.EndAt, info)
		local wanted = Stage.exitCamera(target, 12)
		T.near((final.Position - wanted.Position).Magnitude, 0, 1e-3, "behind the player at the end")
		T.near(fov, 75, 1e-6, "the player's own field of view")
		local focus = target.Position + Vector3.new(0, Stage.HeadLift, 0)
		T.near((wanted.Position - focus).Magnitude, 12, 1e-3, "at the player's zoom")
		T.truthy(wanted.LookVector:Dot(target.LookVector) > 0.9, "looking where the player faces")
		-- a cut (reduced motion): in the cabin until the dip is black, then straight behind the player
		info.CutAt = plan.ExitAt
		local inside = Stage.camera(plan, plan.ExitAt + 0.05, info)
		T.truthy(TO:PointToObjectSpace(inside.Position).Z < Stage.BackZ, "still in the cabin")
		local cut = Stage.camera(plan, plan.ExitAt + timing.DipOut + 0.01, info)
		T.near((cut.Position - wanted.Position).Magnitude, 0, 1e-3, "then behind the player")
	end)

	T.test("arrival effects: every mine's look, pooled, never left behind", function()
		local fx = Fx.build()
		local count = 0
		for _, d in fx.Folder:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
				T.falsy(d.CanCollide or d.CanQuery or d.CanTouch, d.Name .. ": not touchable")
			end
		end
		T.le(count, 30, "a small pool: " .. count)
		for _, floor in MineFloors.List do
			local theme = Config.theme(floor.Id)
			Fx.setTheme(fx, theme, TO)
			-- the emitters it uses are on holders, the others off the world
			T.eq(fx.Dust.Parent ~= nil, theme.Dust ~= nil, floor.Id .. " dust")
			T.eq(fx.Sparks.Parent ~= nil, theme.Sparks ~= nil, floor.Id .. " sparks")
			T.eq(fx.Motes.Parent ~= nil, theme.Motes ~= nil, floor.Id .. " motes")
			if theme.Motes and theme.MotesRise < 0 then
				T.eq(fx.Motes.Parent, fx.Top, "glitter falls from over the doorway")
			end
			local peak = 0
			for k = 0, 52 do
				local since = k * 0.05
				Fx.pose(fx, since, false)
				peak = math.max(peak, fx.Light.Brightness)
				for _, pebble in fx.Pebbles do
					if pebble.Part.Transparency < 1 then
						local y = (TO * Fx.Spot):PointToObjectSpace(pebble.Part.CFrame.Position).Y
						T.truthy(y >= 0.62 + pebble.Part.Size.Y / 2 - 1e-3, "a pebble never sinks into the plate (float32 world positions)")
					end
				end
			end
			T.truthy(peak > 2, floor.Id .. ": its light")
			Fx.pose(fx, Config.ArrivalTime, false)
			T.eq(fx.Light.Brightness, 0, floor.Id .. ": dark at the end")
			for _, part in fx.Folder:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "Ground" and part.Name ~= "Top" and part.Name ~= "Light" then
					T.eq(part.Transparency, 1, floor.Id .. ": " .. part.Name .. " gone at the end")
				end
			end
			T.eq(fx.Light.Color, theme.Light, floor.Id .. ": its colour")
		end
		-- the quarry's rocks land and lie still; the Rift's arcs never with reduced motion
		local quarry = Config.theme("Quarry")
		Fx.setTheme(fx, quarry, TO)
		Fx.pose(fx, 1.4, false)
		local resting = Fx.pebbleHeight(10, 0.5, 3)
		T.near(resting, 0.62 + 0.25, 1e-9, "a pebble rests on the plate")
		Fx.setTheme(fx, Config.theme("StormglassRift"), TO)
		for k = 0, 40 do
			Fx.pose(fx, k * 0.05, true)
			for _, arc in fx.Arcs do
				for _, piece in arc.Parts do
					T.eq(piece.Transparency, 1, "no arcs with reduced motion")
				end
			end
		end
		local shown = 0
		for k = 0, 40 do
			Fx.pose(fx, k * 0.025 + 0.25, false)
			for _, arc in fx.Arcs do
				if arc.Parts[1].Transparency < 1 then
					shown += 1
				end
			end
		end
		T.truthy(shown > 0, "arcs crackle with motion")
	end)

	T.test("travel words: PREPARING ELEVATOR..., the dip, the bars, ARRIVED! and the mine's name", function()
		local refs = View.build()
		T.falsy(refs.Gui.Enabled, "off until a ride")
		T.truthy(refs.Gui.DisplayOrder > 60, "over the floor window")
		local plan = Config.plan(2, 4)
		local info =
			{ Name = "Sunken Palace", Floor = 4, Glow = Config.Themes.SunkenPalace.Glow, Down = true, Reduced = false, CutAt = nil }
		View.setRide(refs, info)
		T.eq(refs.Way.Text, "DOWN TO FLOOR 4 · SUNKEN PALACE")
		T.eq(refs.Name.Text, "SUNKEN PALACE")
		T.eq(refs.Floor.Text, "FLOOR 4")
		View.pose(refs, plan, 0.3, info)
		T.truthy(refs.Prepare.Visible, "PREPARING ELEVATOR... in the preparation")
		T.eq(string.sub(refs.PrepareText.Text, 1, 18), "PREPARING ELEVATOR")
		T.falsy(refs.Dip.Visible, "no dip yet")
		View.pose(refs, plan, plan.DipMid, info)
		T.near(1 - refs.Dip.BackgroundTransparency, 1, 1e-6, "black while the camera steps in")
		View.pose(refs, plan, plan.DoorsShut + 0.5, info)
		T.falsy(refs.Prepare.Visible, "the pill is gone")
		T.falsy(refs.Dip.Visible, "the dip is over")
		T.truthy(refs.TopBar.Visible and refs.BottomBar.Visible, "cinema bars")
		T.truthy(refs.Way.Visible, "the way in the bottom bar")
		T.falsy(refs.Arrived.Visible, "not arrived yet")
		View.pose(refs, plan, plan.StopAt + 0.5, info)
		T.truthy(refs.Arrived.Visible, "ARRIVED!")
		T.near(refs.ArrivedScale.Scale, 1, 0.02, "popped in")
		T.eq(refs.Word.TextTransparency, 0, "readable")
		View.pose(refs, plan, plan.EndAt + 0.01, info)
		T.falsy(refs.Arrived.Visible, "gone at the end")
		T.falsy(refs.TopBar.Visible, "bars out")
		T.eq(
			View.wayText({ Name = "Greystone Quarry", Floor = 1, Glow = info.Glow, Down = false, Reduced = false, CutAt = nil }),
			"UP TO FLOOR 1 · GREYSTONE QUARRY"
		)
		-- reduced motion: no pop and no slide, the dots stand still
		info.Reduced = true
		View.pose(refs, plan, plan.StopAt + 0.05, info)
		T.eq(refs.ArrivedScale.Scale, 1, "no pop")
		T.eq(View.prepareText(0.1, true), View.prepareText(0.4, true), "the dots stand still")
		T.truthy(View.prepareText(0.1, false) ~= View.prepareText(0.3, false), "they run with motion")
		View.pose(refs, plan, plan.DoorsShut + 0.5, info)
		T.near(refs.TopBar.Position.Y.Scale, View.BarHeight, 1e-6, "the bars stand (they fade in)")
		-- a cut way out dips again; a cut short ride comes back from black
		info.CutAt = plan.ExitAt
		T.near(View.dipAt(plan, plan.ExitAt + timing.DipOut, info, nil), 1, 1e-6, "black at the cut")
		T.near(View.dipAt(plan, 2.0, info, 2.0), 1, 1e-6, "black when cut short ...")
		T.eq(View.dipAt(plan, 2.5, info, 2.0), 0, "... and clear soon after")
	end)
end
