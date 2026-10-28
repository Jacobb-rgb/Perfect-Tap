--[[
	The weather (Config/WeatherConfig, Weather/WeatherLogic): the config is
	sane (fits its slots, shipped textures, sound ids that play), the
	schedule is deterministic and follows the weights (a kind that is off
	never comes), the fades ramp smoothly, a rainbow only follows rain, the
	WeatherForce override, lightning windows and the flash, tints and caps,
	where weather shows (surface yes, mine floors no) and the rainbow's arc.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WeatherConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WeatherConfig")
	local WeatherLogic = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherLogic")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")

	local S = WeatherConfig.Schedule
	local SLOTS = 4000
	local BASE = 3300000 -- slots around today's server time (os.time / 540)

	-- a copy of the config with the kinds changed by `change`
	local function withKinds(change: (any) -> ())
		local kinds = {}
		for name, look in WeatherConfig.Kinds do
			kinds[name] = table.clone(look)
		end
		change(kinds)
		local cfg = table.clone(WeatherConfig)
		cfg.Kinds = kinds
		return cfg
	end

	T.test("weather: the config is sane", function()
		T.truthy(type(WeatherConfig.Enabled) == "boolean", "a master switch")
		T.eq(#WeatherConfig.Order, 6, "six kinds")
		T.eq(WeatherConfig.Kinds.Fog, nil, "no fog (owner 2026-10-27)")
		T.eq(WeatherConfig.Particles.Mist, nil, "no mist puffs")
		T.eq(WeatherLogic.parseForce("fog"), nil, "fog cannot be forced either")
		local longest = 0
		for _, kind in WeatherConfig.Order do
			local look = WeatherConfig.Kinds[kind]
			T.truthy(look, kind .. " has a look")
			T.truthy(type(look.On) == "boolean" and look.Weight >= 0, kind .. " switch and weight")
			T.truthy(look.Duration[1] >= S.FadeIn + S.FadeOut + 1, kind .. " lasts longer than its fades")
			T.le(look.Duration[1], look.Duration[2], kind .. " duration range")
			T.le(look.Duration[2], 260, kind .. " is a 2-4 minute event")
			local tail = if (look.Rainbow or 0) > 0 then WeatherConfig.Rainbow.Seconds - WeatherConfig.Rainbow.Lead else 0
			longest = math.max(longest, look.Duration[2] + tail)
			for _, key in { "Rain", "Hail", "Snow", "Leaves", "Heat", "Splash", "Bounce", "Settle", "Clack" } do
				local rate = look[key]
				if rate ~= nil then
					T.truthy(rate > 0 and rate <= 1200, `{kind}.{key} rate {rate}`)
				end
			end
			for name in look.Loops or {} do
				T.truthy(WeatherConfig.Sounds[name] and WeatherConfig.Sounds[name].Looped, `{kind} loop {name}`)
			end
		end
		T.le(longest + 2 * S.Margin, S.Slot, "the longest event and its rainbow fit in a slot")
		T.truthy(S.EventChance > 0.3 and S.EventChance < 1, "some slots stay clear")
		T.truthy(WeatherConfig.Kinds.Storm.Lightning, "storms have lightning")
		T.truthy((WeatherConfig.Kinds.Rain.Rainbow or 0) > 0, "a rainbow may follow the rain")
		for zone in WeatherConfig.Zones do
			T.truthy(WorldLayout.ZoneById[zone], "zone " .. zone .. " exists")
		end
		T.truthy(WeatherConfig.Phone.Rate > 0 and WeatherConfig.Phone.Rate < 1, "phones get fewer particles")
		T.le(WeatherConfig.Phone.GroundPoints, WeatherConfig.Ground.Points, "phone pads")
		T.truthy(WeatherConfig.Reduced.Rate < 1 and WeatherConfig.Reduced.Flash == false, "Reduce motion: no flashes, fewer particles")
		local shipped = {
			["rbxasset://textures/particles/SquareParticle.png"] = true,
			["rbxasset://textures/particles/smoke_main.dds"] = true,
			["rbxasset://textures/particles/sparkles_main.dds"] = true,
			["rbxasset://textures/particles/explosion01_shockwave_main.dds"] = true,
		}
		for name, p in WeatherConfig.Particles do
			T.truthy(shipped[p.Texture], name .. " uses a shipped texture")
			T.le(p.Size[1], p.Size[2], name .. " size range")
			T.le(p.Lifetime[1], p.Lifetime[2], name .. " lifetime range")
			T.truthy(p.Transparency >= 0 and p.Transparency < 1, name .. " visible")
		end
		local files = {
			["rbxasset://sounds/action_falling.ogg"] = true,
			["rbxasset://sounds/action_swim.mp3"] = true,
			["rbxasset://sounds/impact_water.mp3"] = true,
		}
		for name, def in WeatherConfig.Sounds do
			T.truthy(files[def.Id] or string.match(def.Id, "^rbxassetid://%d+$") ~= nil, name .. " plays (" .. def.Id .. ")")
			T.truthy(def.Volume > 0 and def.Volume <= 0.8, name .. " volume")
		end
		T.truthy(WeatherConfig.Sounds.Rain.Looped and WeatherConfig.Sounds.Wind.Looped, "rain and wind loop")
		T.falsy(WeatherConfig.Sounds.Thunder.Looped, "thunder plays once")
		T.eq(WeatherConfig.ParentGroup, "TerraForgeSfx", "under the SETTINGS sound group")
	end)

	T.test("weather: the hash and the schedule are deterministic", function()
		for i = 1, 200 do
			local h = WeatherLogic.hash(S.Seed, BASE + i, 3)
			T.truthy(h >= 0 and h < 1, "hash in [0, 1)")
			T.eq(h, WeatherLogic.hash(S.Seed, BASE + i, 3), "same input, same hash")
		end
		T.truthy(WeatherLogic.hash(1, 2, 3) ~= WeatherLogic.hash(1, 2, 4), "the salt matters")
		T.truthy(WeatherLogic.hash(1, 2, 3) ~= WeatherLogic.hash(2, 2, 3), "the seed matters")
		T.truthy(WeatherLogic.hash(-5, -7, 3) >= 0, "negative inputs")
		local t0 = BASE * S.Slot
		for i = 0, 300 do
			local t = t0 + i * 37.5
			local a, b = WeatherLogic.at(t), WeatherLogic.at(t)
			T.eq(a.Kind, b.Kind, "same kind at the same time")
			T.eq(a.Intensity, b.Intensity, "same strength")
			T.eq(a.Rainbow, b.Rainbow, "same rainbow")
		end
		-- a different seed gives a different sequence
		local other = table.clone(WeatherConfig)
		other.Schedule = table.clone(S)
		other.Schedule.Seed = S.Seed + 1
		local differ = 0
		for slot = BASE, BASE + 99 do
			local a, b = WeatherLogic.event(slot), WeatherLogic.event(slot, other)
			if (a and a.Kind) ~= (b and b.Kind) then
				differ += 1
			end
		end
		T.truthy(differ > 20, "another seed, other weather")
	end)

	T.test("weather: events fit their slots, mostly clear between, kinds by weight", function()
		local counts: { [string]: number } = {}
		local events = 0
		local covered = 0
		for slot = BASE, BASE + SLOTS - 1 do
			local e = WeatherLogic.event(slot)
			if e then
				events += 1
				counts[e.Kind] = (counts[e.Kind] or 0) + 1
				local tail = if e.Rainbow then WeatherConfig.Rainbow.Seconds - WeatherConfig.Rainbow.Lead else 0
				T.truthy(e.Start >= slot * S.Slot + S.Margin - 1e-6, "starts after the margin")
				T.truthy(e.Start + e.Length + tail <= (slot + 1) * S.Slot - S.Margin + 1e-6, "ends (with its rainbow) in its slot")
				local d = WeatherConfig.Kinds[e.Kind].Duration
				T.truthy(e.Length >= d[1] - 1e-6 and e.Length <= d[2] + 1e-6, e.Kind .. " length in range")
				T.truthy(e.WindYaw >= 0 and e.WindYaw < math.pi * 2, "wind yaw")
				covered += e.Length
			end
		end
		T.near(events / SLOTS, S.EventChance, 0.03, "share of slots with weather")
		T.lt(covered / (SLOTS * S.Slot), 0.5, "mostly clear between events")
		local total = 0
		for _, kind in WeatherConfig.Order do
			total += WeatherConfig.Kinds[kind].Weight
		end
		for _, kind in WeatherConfig.Order do
			local want = WeatherConfig.Kinds[kind].Weight / total
			T.truthy((counts[kind] or 0) > 0, kind .. " comes")
			T.near((counts[kind] or 0) / events, want, 0.035, kind .. " share follows its weight")
		end
	end)

	T.test("weather: a kind that is off never comes", function()
		local cfg = withKinds(function(kinds)
			kinds.Snow.On = false
			kinds.Hail.Weight = 0
		end)
		for slot = BASE, BASE + 3000 do
			local e = WeatherLogic.event(slot, cfg)
			if e then
				T.truthy(e.Kind ~= "Snow" and e.Kind ~= "Hail", "no snow, no hail")
			end
		end
		for i = 0, 99 do
			local k = WeatherLogic.pick(i / 100, cfg)
			T.truthy(k ~= "Snow" and k ~= "Hail", "pick skips them")
		end
		local none = withKinds(function(kinds)
			for _, look in kinds do
				look.On = false
			end
		end)
		T.eq(WeatherLogic.pick(0.5, none), "Clear", "all off: clear")
		for slot = BASE, BASE + 200 do
			T.eq(WeatherLogic.event(slot, none), nil, "all off: no events")
		end
		local only = withKinds(function(kinds)
			for name, look in kinds do
				look.On = name == "Snow"
			end
		end)
		for i = 0, 50 do
			T.eq(WeatherLogic.pick(i / 50, only), "Snow", "only snow")
		end
		local off = table.clone(WeatherConfig)
		off.Enabled = false
		for slot = BASE, BASE + 50 do
			T.eq(WeatherLogic.at(slot * S.Slot + 200, nil, off).Kind, "Clear", "Enabled = false: clear")
		end
	end)

	T.test("weather: the fades ramp up and down smoothly", function()
		T.eq(WeatherLogic.ramp(0, 100, 20, 25), 0, "starts at 0")
		T.eq(WeatherLogic.ramp(20, 100, 20, 25), 1, "full after the fade in")
		T.eq(WeatherLogic.ramp(50, 100, 20, 25), 1, "held")
		T.eq(WeatherLogic.ramp(100, 100, 20, 25), 0, "ends at 0")
		T.eq(WeatherLogic.ramp(-5, 100, 20, 25), 0, "before")
		T.eq(WeatherLogic.ramp(120, 100, 20, 25), 0, "after")
		local prev = 0
		for t = 1, 20 do
			local v = WeatherLogic.ramp(t, 100, 20, 25)
			T.truthy(v >= prev, "rises")
			prev = v
		end
		prev = 1
		for t = 76, 100 do
			local v = WeatherLogic.ramp(t, 100, 20, 25)
			T.truthy(v <= prev, "falls")
			prev = v
		end
		-- through real events: no jumps, 0 at both ends, full in the middle
		local checked = 0
		for slot = BASE, BASE + 60 do
			local e = WeatherLogic.event(slot)
			if e then
				checked += 1
				T.eq(WeatherLogic.at(e.Start - 1).Intensity, 0, "nothing before")
				T.near(WeatherLogic.at(e.Start + S.FadeIn + 1).Intensity, 1, 1e-9, "full after the fade in")
				T.eq(WeatherLogic.at(e.Start + e.Length + 1).Intensity, 0, "nothing after")
				T.eq(WeatherLogic.at(e.Start + e.Length / 2).Kind, e.Kind, "its kind in the middle")
				local last = 0
				for t = e.Start - 2, e.Start + e.Length + 2, 0.5 do
					local v = WeatherLogic.at(t).Intensity
					T.lt(math.abs(v - last), 0.06, "no jump")
					last = v
				end
			end
		end
		T.truthy(checked > 20, "events checked")
	end)

	T.test("weather: a rainbow follows a shower, nothing else", function()
		local rainbows = 0
		for slot = BASE, BASE + SLOTS - 1 do
			local e = WeatherLogic.event(slot)
			if e and e.Rainbow then
				rainbows += 1
				T.truthy((WeatherConfig.Kinds[e.Kind].Rainbow or 0) > 0, e.Kind .. " may have a rainbow")
				local r = WeatherConfig.Rainbow
				local peak = WeatherLogic.at(e.Start + e.Length - r.Lead + r.FadeIn + 2)
				T.near(peak.Rainbow, 1, 1e-9, "full rainbow")
				local after = WeatherLogic.at(e.Start + e.Length + 5)
				T.eq(after.Kind, "Clear", "the rain is gone")
				T.truthy(after.Rainbow > 0.5, "the rainbow is still there")
				T.eq(WeatherLogic.at(e.Start + e.Length / 2).Rainbow, 0, "no rainbow in the rain")
				T.eq(WeatherLogic.at(e.Start + e.Length - r.Lead + r.Seconds + 1).Rainbow, 0, "gone again")
			elseif e then
				T.eq(WeatherLogic.at(e.Start + e.Length + 5).Rainbow, 0, "no rainbow after " .. e.Kind)
			end
		end
		T.truthy(rainbows > 40, "rainbows happen")
	end)

	T.test("weather: WeatherForce shows a kind at once", function()
		T.eq(WeatherLogic.parseForce("rain"), "Rain", "case")
		T.eq(WeatherLogic.parseForce(" Storm "), "Storm", "spaces")
		T.eq(WeatherLogic.parseForce("HEATWAVE"), "Heatwave", "upper case")
		T.eq(WeatherLogic.parseForce("rainbow"), "Rainbow", "rainbow")
		T.eq(WeatherLogic.parseForce("clear"), "Clear", "clear")
		T.eq(WeatherLogic.parseForce("tornado"), nil, "unknown")
		T.eq(WeatherLogic.parseForce(""), nil, "empty")
		T.eq(WeatherLogic.parseForce(5), nil, "not a string")
		local t = BASE * S.Slot + 123
		local snow = WeatherLogic.at(t, "Snow")
		T.eq(snow.Kind, "Snow", "forced snow")
		T.eq(snow.Intensity, 1, "at full strength")
		T.truthy(snow.Forced and snow.Event ~= nil, "a forced event")
		local bow = WeatherLogic.at(t, "Rainbow")
		T.eq(bow.Kind, "Clear", "the rainbow alone")
		T.eq(bow.Rainbow, 1, "full rainbow")
		for slot = BASE, BASE + 30 do
			local e = WeatherLogic.event(slot)
			if e then
				local clear = WeatherLogic.at(e.Start + e.Length / 2, "Clear")
				T.eq(clear.Kind, "Clear", "forced clear in an event")
				T.eq(clear.Intensity, 0, "no weather")
			end
		end
		local off = table.clone(WeatherConfig)
		off.Kinds = withKinds(function(kinds)
			kinds.Hail.On = false
		end).Kinds
		T.eq(WeatherLogic.at(t, "Hail", off).Kind, "Hail", "a kind that is off can still be forced in Studio")
	end)

	T.test("weather: lightning strikes in windows, a flash and thunder after it", function()
		local L = WeatherConfig.Lightning
		local storm, rain
		for slot = BASE, BASE + 400 do
			local e = WeatherLogic.event(slot)
			if e and e.Kind == "Storm" and not storm then
				storm = e
			elseif e and e.Kind == "Rain" and not rain then
				rain = e
			end
		end
		T.truthy(storm and rain, "a storm and a rain found")
		T.eq(WeatherLogic.nextStrike(rain, 0), nil, "no lightning in plain rain")
		local at = 0
		local strikes = 0
		local s = WeatherLogic.nextStrike(storm, 0)
		while s and s.At < storm.Length do
			T.truthy(s.At > at, "later than the last")
			if strikes > 0 then
				T.truthy(s.At - at >= L.MinGap - 1e-9, "gap")
			else
				T.truthy(s.At >= L.First, "not at once")
			end
			T.truthy(s.Delay >= L.Delay[1] and s.Delay <= L.Delay[2], "thunder delay")
			local again = WeatherLogic.nextStrike(storm, at)
			T.eq(again and again.At, s.At, "the same strike again")
			at = s.At
			strikes += 1
			s = WeatherLogic.nextStrike(storm, at)
		end
		local expected = (storm.Length - L.First) / L.Window * L.Chance
		T.truthy(strikes >= expected * 0.4 and strikes <= expected * 1.8 + 1, `strikes {strikes} ~ {expected}`)
		local forced = WeatherLogic.at(BASE * S.Slot + 777, "Storm")
		T.truthy(WeatherLogic.nextStrike(forced.Event, forced.Elapsed), "a forced storm strikes too")
		T.near(WeatherLogic.flash(0), L.Peak, 1e-9, "the flash")
		T.truthy(WeatherLogic.flash(L.Flicker + 0.01) > WeatherLogic.flash(L.Flicker - 0.01), "the flicker")
		T.eq(WeatherLogic.flash(L.Length), 0, "gone")
		T.eq(WeatherLogic.flash(-0.1), 0, "not before")
		for t = 0, L.Length, 0.02 do
			T.truthy(WeatherLogic.flash(t) >= 0 and WeatherLogic.flash(t) <= L.Peak + L.Second, "in range")
		end
		T.near(WeatherLogic.thunderLevel(L.Delay[1]), 1, 1e-9, "close thunder is loud")
		T.truthy(WeatherLogic.thunderLevel(L.Delay[2]) >= 0.5, "far thunder still heard")
	end)

	T.test("weather: tints, rates and the caps", function()
		T.truthy(WeatherLogic.isNeutral(WeatherLogic.tint("Rain", 0, 0)), "no strength, no tint")
		T.truthy(WeatherLogic.isNeutral(WeatherLogic.tint("Clear", 1, 0)), "clear has no tint")
		local storm = WeatherLogic.tint("Storm", 1, 0)
		T.eq(storm.Brightness, WeatherConfig.Kinds.Storm.Tint.Brightness, "full storm tint")
		T.lt(storm.Brightness, WeatherLogic.tint("Rain", 1, 0).Brightness, "a storm is darker than rain")
		T.truthy(WeatherLogic.tint("Heatwave", 1, 0).Saturation > 0, "the heatwave is vivid")
		T.truthy(WeatherLogic.tint("Clear", 0, 1).Brightness > 0, "the sun is back with the rainbow")
		local half = WeatherLogic.tint("Snow", 0.5, 0)
		T.near(half.Contrast, WeatherConfig.Kinds.Snow.Tint.Contrast / 2, 1e-9, "half way")
		local rain = WeatherConfig.Kinds.Rain.Rain
		T.eq(WeatherLogic.rate(rain, 1, false, false), rain, "full rate")
		T.lt(WeatherLogic.rate(rain, 1, true, false), rain, "phones lower")
		T.lt(WeatherLogic.rate(rain, 1, false, true), rain, "Reduce motion lower")
		T.eq(WeatherLogic.rate(nil, 1, false, false), 0, "no emitter")
		T.eq(WeatherLogic.rate(rain, 0, false, false), 0, "no strength")
		T.lt(WeatherLogic.rate(WeatherConfig.Kinds.Storm.Rain, 1, true, false), 500, "a phone's storm stays under 500/s")
		T.eq(WeatherLogic.slant(0, 80), 0, "no wind, straight down")
		T.lt(
			WeatherLogic.slant(WeatherConfig.Kinds.Rain.Wind, 85),
			WeatherLogic.slant(WeatherConfig.Kinds.Storm.Wind, 85),
			"the storm leans more"
		)
		for i = 0, 100 do
			local v = WeatherLogic.sway(i * 0.13, 0.7, 0.06, 1.6)
			T.truthy(v >= 0 and v <= 0.06 * 1.13, "sway never upwind, capped")
			local p = WeatherLogic.scatter(i / 101, (i * 7 % 13) / 13, 30)
			T.le(p.Magnitude, 30 + 1e-9, "scatter in the disc")
			T.eq(p.Y, 0, "flat")
		end
	end)

	T.test("weather: only on the surface", function()
		T.truthy(WeatherLogic.isSurface(WorldLayout.SpawnPoint + Vector3.new(0, 3, 0)), "spawn")
		T.truthy(WeatherLogic.isSurface(Vector3.new(0, 3, 0)), "plaza")
		T.truthy(WeatherLogic.isSurface(WorldLayout.Plots[1].Center + Vector3.new(0, 3, 0)), "a plot")
		T.truthy(WeatherLogic.isSurface(Vector3.new(300, 2, 0)), "the sea")
		T.truthy(WeatherLogic.isSurface(Vector3.new(0, 220, 300)), "a sky island")
		local haven = WorldLayout.ZoneById.SkyHaven
		T.truthy(WeatherLogic.isSurface((haven.Min + haven.Max) / 2), "SKY HAVEN")
		for _, id in { "Quarry", "EmberCaves", "DeepHollow", "Grotto", "SunkenPalace", "StormglassRift", "HeartstoneCore" } do
			local zone = WorldLayout.ZoneById[id]
			T.truthy(zone, id)
			local inside = Vector3.new((zone.Min.X + zone.Max.X) / 2, zone.FloorY + 3, (zone.Min.Z + zone.Max.Z) / 2)
			T.falsy(WeatherLogic.isSurface(inside), id .. ": no weather down there")
		end
		T.falsy(WeatherLogic.isSurface(Vector3.new(0, -120, -600)), "the elevator shaft")
		local open = table.clone(WeatherConfig)
		open.Zones = table.clone(WeatherConfig.Zones)
		open.Zones.Quarry = true
		local q = WorldLayout.ZoneById.Quarry
		T.truthy(WeatherLogic.isSurface((q.Min + q.Max) / 2, open), "the quarry can be switched on")
	end)

	T.test("weather: the rainbow is a half circle opposite the sun", function()
		local bands = WeatherLogic.rainbowBands()
		T.eq(#bands, #WeatherConfig.Rainbow.Colors, "one band per colour")
		for i = 2, #bands do
			T.lt(bands[i].Radius, bands[i - 1].Radius, "outside in")
			T.near(bands[i - 1].Radius - bands[i].Radius, bands[i].Width / 1.15, bands[i].Width * 0.1, "bands touch")
		end
		local radius = bands[1].Radius
		local arc = WeatherLogic.rainbowArc(radius)
		T.eq(#arc.Points, 3, "foot, top, foot")
		for k = 1, 3 do
			-- (Vector3 is 32-bit floats)
			T.near(arc.Points[k].Magnitude, radius, radius * 1e-5, "on the circle")
			T.near(arc.Axes[k]:Dot(arc.Points[k]), 0, radius * 1e-5, "tangent")
		end
		-- the Beam's Bezier (P0, P0 + axis0 * c, P1 - axis1 * c, P1) stays on the circle
		for seg = 1, 2 do
			local p0, p3 = arc.Points[seg], arc.Points[seg + 1]
			local p1 = p0 + arc.Axes[seg] * arc.Curve
			local p2 = p3 - arc.Axes[seg + 1] * arc.Curve
			for i = 0, 10 do
				local t = i / 10
				local u = 1 - t
				local p = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
				T.near(p.Magnitude, radius, radius * 0.001, "Bezier on the arc")
				T.truthy(p.Y >= -radius * 1e-5, "above the centre")
			end
		end
		local camera = Vector3.new(0, 20, 30)
		local sun = LobbyLayout.SunDirection
		local frame = WeatherLogic.rainbowFrame(camera, sun)
		T.near((frame.Position - camera).Magnitude, WeatherConfig.Rainbow.Distance, 1e-3, "at its distance")
		T.truthy((frame.Position - camera).Unit:Dot(sun) < -0.99, "opposite the sun")
		T.truthy(frame.LookVector:Dot((camera - frame.Position).Unit) > 0.99, "facing the camera")
		local top = frame:PointToWorldSpace(arc.Points[2])
		local elevation = math.deg(math.asin((top - camera).Unit.Y))
		T.truthy(elevation > 15 and elevation < 45, `the top stands {elevation} degrees over the horizon`)
		T.near(WeatherLogic.rainbowTransparency(0, 1), 1, 1e-9, "hidden at alpha 0")
		T.near(WeatherLogic.rainbowTransparency(1, 1), WeatherConfig.Rainbow.Transparency, 1e-9, "the top at full alpha")
		T.truthy(WeatherLogic.rainbowTransparency(1, 0) > WeatherLogic.rainbowTransparency(1, 1), "the feet fade")
	end)

	T.test("weather: always a clear view (nothing falls near the lens)", function()
		local box = WeatherConfig.Box
		local P = WeatherConfig.Particles
		local checked = 0
		for _, kind in WeatherConfig.Order do
			local look = WeatherConfig.Kinds[kind]
			if (look.Rain or 0) > 0 or (look.Hail or 0) > 0 or (look.Snow or 0) > 0 then
				checked += 1
				local clear = look.Clear or box.Clear
				T.truthy(clear >= 6, kind .. " keeps at least 6 studs clear")
				local hole = WeatherLogic.hole(look)
				local strips = WeatherLogic.strips(hole)
				T.eq(#strips, 8, "two rings of four strips")
				local share = 0
				for _, strip in strips do
					share += strip.Share
					T.truthy(strip.SizeX >= 0 and strip.SizeZ >= 0, "no negative size")
					if strip.Share > 0 then
						-- the strip's nearest point to the camera's fall line (a square hole)
						local nx = math.max(0, math.abs(strip.X) - strip.SizeX / 2)
						local nz = math.max(0, math.abs(strip.Z) - strip.SizeZ / 2)
						T.truthy(math.max(nx, nz) >= hole - 1e-6, kind .. ": no strip in the hole")
						local fx = math.abs(strip.X) + strip.SizeX / 2
						local fz = math.abs(strip.Z) + strip.SizeZ / 2
						T.le(math.max(fx, fz), box.Field / 2 + 1e-6, "inside the field")
					end
				end
				T.near(share, 1, 1e-9, kind .. ": the strips share the whole rate")
				-- the worst sideways drift on the way down (the spread) still misses the clear view
				local slant = WeatherLogic.lookSlant(look)
				for _, key in { "Rain", "Hail", "Snow" } do
					local rate = (look :: any)[key]
					if rate and rate > 0 then
						local path = WeatherLogic.fieldHeight(look) / math.cos(slant)
						local drift = path * math.tan(math.rad(P[key].Spread or 0))
						T.truthy(hole - drift >= clear - 1e-6, `{kind} {key} cannot drift into the clear view`)
					end
				end
			end
		end
		T.eq(checked, 4, "rain, storm, hail and snow")
		T.truthy(WeatherConfig.Kinds.Snow.Clear >= 12, "snow keeps the widest clear view")
		T.truthy(box.NearSize < 1 and box.NearAlpha < 1, "smaller, fainter particles round the clear view")
		local camera = Vector3.new(0, 10, 0)
		T.falsy(WeatherLogic.padClear(Vector3.new(0, 0, 4), camera), "no splash or flake right under the lens")
		T.truthy(WeatherLogic.padClear(Vector3.new(0, 0, 20), camera), "further out is fine")
		T.truthy(WeatherConfig.Ground.Clear >= 10, "pads stay 10+ studs away")
		T.le(P.Settle.Size[2], 1.2, "settled flakes stay small")
	end)

	T.test("weather: lightning flashes stay rare (photosensitivity)", function()
		local L = WeatherConfig.Lightning
		T.truthy(L.MinFlashGap >= 1, "a second between two flashes at least")
		T.truthy(L.MinGap >= L.MinFlashGap, "strikes are further apart than that anyway")
		T.truthy(WeatherLogic.flashAllowed(nil, 5), "the first flash")
		T.falsy(WeatherLogic.flashAllowed(5, 5.5), "not half a second later")
		T.truthy(WeatherLogic.flashAllowed(5, 5 + L.MinFlashGap), "after the gap")
		-- the bright pulses (a flash and its flicker) of a list of strike times, as the controller
		-- shows them (flashAllowed), sampled every 5 ms: at most 3 start in any second
		local function pulses(strikes: { number }): { number }
			local shown = {}
			local last = nil
			for _, at in strikes do
				if WeatherLogic.flashAllowed(last, at) then
					table.insert(shown, at)
					last = at
				end
			end
			local starts = {}
			local before = 0
			local stop = (strikes[#strikes] or 0) + 2
			for t = 0, stop, 0.005 do
				local v = 0
				for _, at in shown do
					v = math.max(v, WeatherLogic.flash(t - at))
				end
				if v - before > 0.03 then
					table.insert(starts, t)
				end
				before = v
			end
			return starts
		end
		local function worstSecond(starts: { number }): number
			local worst = 0
			for i, a in starts do
				local n = 0
				for j = i, #starts do
					if starts[j] < a + 1 then
						n += 1
					end
				end
				worst = math.max(worst, n)
			end
			return worst
		end
		-- even strikes every 0.2 s (a bug) would flash at most 2-3 times a second
		local burst = {}
		for i = 1, 40 do
			table.insert(burst, 1 + i * 0.2)
		end
		T.le(worstSecond(pulses(burst)), 3, "a burst of strikes")
		-- a real storm: far fewer
		local storm
		for slot = BASE, BASE + 400 do
			local e = WeatherLogic.event(slot)
			if e and e.Kind == "Storm" then
				storm = e
				break
			end
		end
		T.truthy(storm, "a storm found")
		local strikes = {}
		local s = WeatherLogic.nextStrike(storm, 0)
		while s and s.At < storm.Length do
			table.insert(strikes, s.At)
			s = WeatherLogic.nextStrike(storm, s.At)
		end
		local starts = pulses(strikes)
		T.le(worstSecond(starts), 2, "a storm: a flash and its flicker at most in a second")
		T.lt(#starts / storm.Length, 0.25, "a storm flashes far less than once a second on average")
	end)

	T.test("weather: Reduce motion calms everything", function()
		local R = WeatherConfig.Reduced
		T.falsy(R.Flash, "no lightning flashes")
		T.falsy(R.Sway, "no tree sway")
		T.falsy(R.Heat, "no wobbling heat puffs")
		T.lt(R.Rate, 1, "fewer particles")
		T.truthy(WeatherConfig.Rainbow.FadeIn >= 2 and WeatherConfig.Rainbow.FadeOut >= 2, "the rainbow only fades slowly")
		T.truthy(S.FadeIn >= 5 and S.FadeOut >= 5, "weather comes and goes slowly")
	end)

	T.test("weather: rain, hail and snow come down round the player (their travel reaches the ground)", function()
		local box = WeatherConfig.Box
		T.truthy(box.Below >= 6, "what falls stays visible below the camera")
		local checked = 0
		for _, kind in WeatherConfig.Order do
			local look = WeatherConfig.Kinds[kind]
			local need = WeatherLogic.reach(look)
			T.near(need, (WeatherLogic.fieldHeight(look) + box.Below) / math.cos(WeatherLogic.lookSlant(look)), 1e-9, "reach")
			for _, key in { "Rain", "Hail", "Snow" } do
				local rate = (look :: any)[key]
				if rate and rate > 0 then
					checked += 1
					-- the slowest, shortest-lived particle, until it starts to fade (80 % of its life)
					local travel = WeatherLogic.travel(WeatherConfig.Particles[key], 0.8)
					T.truthy(travel >= need, `{kind} {key}: travels {travel} of {need} studs before it fades`)
				end
			end
		end
		T.eq(checked, 5, "rain, storm, hail (rain + hail) and snow")
		T.truthy(WeatherLogic.fieldHeight(WeatherConfig.Kinds.Snow) < box.Height, "the slow snow starts lower")
		T.near(WeatherLogic.travel({ Speed = { 10, 10 }, Lifetime = { 2, 2 } } :: any, 0.5), 10, 1e-9, "no drag: v t")
		T.lt(WeatherLogic.travel({ Speed = { 10, 10 }, Lifetime = { 2, 2 }, Drag = 1 } :: any, 0.5), 10, "drag slows it")
	end)

	T.test("weather: no weather in the Quarry -> Grotto tunnel", function()
		for _, p in { Vector3.new(76, -9, -182), Vector3.new(73, -6, -178), Vector3.new(86, -9, -186) } do
			T.falsy(WeatherLogic.isSurface(p), `tunnel {p}`)
		end
		T.truthy(WeatherLogic.isSurface(Vector3.new(0, 3, -112)), "the quarry rim road keeps its weather")
		T.truthy(WeatherLogic.isSurface(Vector3.new(76, 220, -182)), "the sky far above it too")
	end)

	-- the roof rule with real geometry: an upward ray against the parts' boxes (the nearest one it
	-- enters; a ray starting inside a part never hits it, and a part with CanCollide and CanQuery
	-- both off is never hit, like Workspace:Raycast)
	local function rayUp(origin: any, length: number, parts: { any }): (any, number)
		local up = Vector3.new(0, 1, 0)
		local best, bestT = nil, length
		for _, part in parts do
			if not part.CanCollide and not part.CanQuery then
				continue
			end
			local o = part.CFrame:PointToObjectSpace(origin)
			local d = part.CFrame:VectorToObjectSpace(up)
			local tmin, tmax = -math.huge, math.huge
			local ok = true
			for _, axis in { "X", "Y", "Z" } do
				local oa, da, h = o[axis], d[axis], part.Size[axis] / 2
				if math.abs(da) < 1e-9 then
					if math.abs(oa) > h then
						ok = false
						break
					end
				else
					local t1, t2 = (-h - oa) / da, (h - oa) / da
					if t1 > t2 then
						t1, t2 = t2, t1
					end
					tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
					if tmin > tmax then
						ok = false
						break
					end
				end
			end
			if ok and tmin > 1e-4 and tmin < bestT then
				best, bestT = part, tmin
			end
		end
		return best, bestT
	end
	-- WeatherController.inTree / roofAbove / roofed, against `parts`
	local function inTree(part: any): boolean
		local node = part.Parent
		while node do
			if node:IsA("Model") and WeatherLogic.isTreeName(node.Name) then
				return true
			end
			node = node.Parent
		end
		return false
	end
	local function roofAbove(origin: any, parts: { any }): boolean
		local R = WeatherConfig.Roof
		local from = origin
		for _ = 1, R.Hops do
			local left = R.Reach - (from.Y - origin.Y)
			if left <= 0 then
				return false
			end
			local part, t = rayUp(from, left, parts)
			if not part then
				return false
			end
			local y = from.Y + t
			if WeatherLogic.roofCounts(y - origin.Y, part.Transparency, part.CanCollide, inTree(part), part.Size) then
				return true
			end
			from = Vector3.new(from.X, y + 0.05, from.Z)
		end
		return false
	end
	local function covered(position: any, parts: { any }): boolean
		local center = roofAbove(position, parts)
		local sides = 0
		for _, offset in WeatherLogic.roofOffsets() do
			if roofAbove(position + offset, parts) then
				sides += 1
			end
		end
		return WeatherLogic.roofed(center, sides)
	end
	local function partsOf(root: any): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("weather: off under the DROPPERS roof, on in the open plaza next to it", function()
		local Droppers = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Droppers")
		local DropperShopBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperShopBuilder")
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local folder = roblox.Instance.new("Folder")
		Droppers.build(folder, Rng.new(1))
		local house = folder:FindFirstChild("DroppersHouse", true)
		T.truthy(house, "the house is built")
		local parts = partsOf(house)
		local frame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
		local room = DropperShopBuilder.Room
		local function at(x: number, y: number, z: number): any
			return (frame * roblox.CFrame.new(x, y, z)).Position
		end
		local zc = room.Front - room.D / 2
		-- inside: the middle, by the back wall, by a side wall, just inside the gateway, and on the
		-- front displays in both corners (the house is turned ~34 degrees to the world)
		for _, p in
			{
				at(0, room.Plinth + 3, zc),
				at(0, room.Plinth + 3, room.Front - room.D + 2),
				at(room.W / 2 - 3, room.Plinth + 3, zc),
				at(0, room.Plinth + 3, room.Front - 2),
				at(12, room.Plinth + 3.4, room.Front - 2.5),
				at(-12, room.Plinth + 3.4, room.Front - 2.5),
			}
		do
			T.truthy(covered(p, parts), `inside the shop at {p}: under the roof`)
		end
		-- outside: the open plaza in front, beside and behind the house
		for _, p in { at(0, 3, room.Front + 14), at(room.W / 2 + 9, 3, zc), at(-room.W / 2 - 9, 3, zc), at(0, 3, room.Front - room.D - 10) } do
			T.falsy(covered(p, parts), `the plaza at {p}: open sky`)
		end
	end)

	T.test("weather: lamps, trees, glass, blocks beside you and the islets far above are no roof", function()
		local function part(cf: any, size: any, collide: boolean, transparency: number?, parent: any?): any
			local x = roblox.Instance.new("Part")
			x.CFrame = cf
			x.Size = size
			x.CanCollide = collide
			x.Transparency = transparency or 0
			x.Parent = parent
			return x
		end
		local root = Vector3.new(0, 3, 0)
		local CF = roblox.CFrame.new
		T.falsy(covered(root, { part(CF(0, 10, 0), Vector3.new(2, 1, 2), true) }), "a lamp's head")
		T.falsy(covered(root, { part(CF(0, 12, 0), Vector3.new(30, 2, 2), true) }), "an arch's beam")
		for _, name in { "Tree", "JungleTree", "JungleTree3" } do
			local tree = roblox.Instance.new("Model")
			tree.Name = name
			T.truthy(WeatherLogic.isTreeName(name), name .. " is a tree")
			T.falsy(covered(root, { part(CF(0, 12, 0), Vector3.new(14, 6, 14), true, 0, tree) }), `a big {name} crown`)
		end
		for _, name in { "Street", "TreeHouse", "Treetop", "DroppersHouse" } do
			T.falsy(WeatherLogic.isTreeName(name), name .. " is no tree")
		end
		T.falsy(covered(root, { part(CF(0, 12, 0), Vector3.new(30, 1, 30), true, 0.95) }), "a glass roof you see through")
		T.falsy(covered(root, { part(CF(0, 12, 0), Vector3.new(30, 1, 3), false) }), "a thin non-colliding beam")
		T.falsy(
			covered(root, { part(CF(0, 14, 0), Vector3.new(14, 1, 14), false) }),
			"a non-colliding slab never counts (ghost roofs are Covered places)"
		)
		T.truthy(covered(root, { part(CF(0, 12, 0), Vector3.new(40, 1, 40), true) }), "a plain roof")
		T.falsy(covered(root, { part(CF(0, 3 + WeatherConfig.Roof.Reach + 6, 0), Vector3.new(40, 4, 40), true) }), "an islet far above")
		T.truthy(
			covered(root, { part(CF(0, 9, 0), Vector3.new(30, 1, 30), true, 0.95), part(CF(0, 15, 0), Vector3.new(30, 1, 30), true) }),
			"the roof above a glass ceiling"
		)
		-- a block (a rim rock, a pedestal, a wheel's rim) right behind you, wide enough for two side
		-- rays to start inside it and find its cap: the sky over you is open, so no roof
		local block = part(CF(0, 3, -4), Vector3.new(14, 6, 5), true)
		local cap = part(CF(0, 6.5, -4), Vector3.new(14, 1, 5), true)
		T.falsy(covered(root, { block, cap }), "a block beside you with open sky above")
		T.truthy(WeatherLogic.roofed(true, 1), "the middle ray and one more")
		T.falsy(WeatherLogic.roofed(false, 3), "never without the ray over the player")
		T.falsy(WeatherLogic.roofed(true, 0), "nor with the middle one alone (a lamp right above)")
	end)

	T.test("weather: no weather inside the EGGS temple or under THE GREAT FORGE's side roofs (ghost roofs)", function()
		local Capsules = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Capsules")
		local GreatForge = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GreatForge")
		local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local CF = roblox.CFrame.new
		local places = {}
		for _, place in WeatherConfig.Covered do
			places[place.Name] = place
		end

		-- the EGGS temple: its drum and dome are ghosts no ray sees
		local temple = roblox.Instance.new("Folder")
		Capsules.build(temple, Rng.new(1))
		local drum = temple:FindFirstChild("Drum", true)
		T.truthy(drum, "the EGGS temple's drum")
		T.falsy(drum.CanCollide or drum.CanQuery, "the drum is a ghost")
		local eggs = places.EggsTemple
		T.truthy(eggs and eggs.Round, "the temple is a round Covered place")
		local drumAt = drum.CFrame.Position -- (Lune parts have no Position property)
		local flat = Vector3.new(eggs.CFrame.Position.X - drumAt.X, 0, eggs.CFrame.Position.Z - drumAt.Z)
		T.lt(flat.Magnitude, 0.2, "centred under the drum")
		local width = math.max(drum.Size.X, drum.Size.Y, drum.Size.Z)
		T.near(eggs.Size.X, width, 0.2, "as wide as the drum")
		local underside = drumAt.Y - math.min(drum.Size.X, drum.Size.Y, drum.Size.Z) / 2
		local top = eggs.CFrame.Position.Y + eggs.Size.Y / 2
		T.truthy(top >= underside + 4, "over the drum's underside, with room for a jump")
		-- a jump from the Royal podium (top 3.0): the root rises to 3 + 3 + 7.5 (CharacterJumpHeight)
		T.truthy(top >= eggs.CFrame.Position.Y - eggs.Size.Y / 2 + 2 + 13.5 + 0.5, "a podium jump stays inside")
		local dais = Vector3.new(drumAt.X, 1.2 + 3, drumAt.Z)
		T.falsy(covered(dais, partsOf(temple)), "the rays see no roof over the dais (that is why the place is needed)")
		T.falsy(WeatherLogic.isSurface(dais), "no weather on the dais")
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local p = dais + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6)
			T.falsy(WeatherLogic.isSurface(p), `no weather under the drum at {p}`)
		end
		local front = (LobbyLayout.frame(LobbyLayout.get("CapsuleStall")) * CF(0, 3, -16)).Position
		T.truthy(WeatherLogic.isSurface(front), "the lawn in front of the temple keeps its weather")

		-- THE GREAT FORGE: the wide side roofs are ghosts too; the nave's own roof is real
		local forge = roblox.Instance.new("Folder")
		GreatForge.build(forge, Rng.new(1))
		local roofs = {}
		for _, d in partsOf(forge) do
			if d.Name == "Roof" and not d.CanCollide and not d.CanQuery then
				table.insert(roofs, d)
			end
		end
		T.eq(#roofs, 2, "two ghost side roofs")
		for _, roof in roofs do
			for _, u in { -0.4, 0, 0.4 } do
				for _, v in { -0.45, 0, 0.45 } do
					local top = (roof.CFrame * CF(u * roof.Size.X, 0, v * roof.Size.Z)).Position
					local p = Vector3.new(top.X, 3, top.Z)
					T.falsy(WeatherLogic.isSurface(p), `no weather under the side roof at {p}`)
				end
			end
		end
		local frame = LobbyLayout.frame(LobbyLayout.get("GreatForge"))
		for _, side in { -1, 1 } do
			local out = (frame * CF(side * 25, 3, 5)).Position
			T.truthy(WeatherLogic.isSurface(out), `beside the forge at {out}: open sky`)
		end
		T.truthy(WeatherLogic.isSurface((frame * CF(0, 3, 5)).Position), "the nave is left to the rays (its roof collides)")
	end)

	T.test("weather: the roof reading holds before the weather goes or comes back", function()
		local hold = WeatherConfig.Roof.Hold
		T.truthy(hold >= 0.4 and hold <= 1, "about half a second")
		local c = WeatherLogic.newCover()
		T.falsy(WeatherLogic.settleCover(c, false, 0), "open")
		T.falsy(WeatherLogic.settleCover(c, true, 1), "under a roof: not yet")
		T.falsy(WeatherLogic.settleCover(c, true, 1 + hold * 0.5), "still not")
		T.truthy(WeatherLogic.settleCover(c, true, 1 + hold), "held: indoors")
		-- a moment in the open (a gap in the roof) does not bring the weather back
		T.truthy(WeatherLogic.settleCover(c, false, 2), "a gap")
		T.truthy(WeatherLogic.settleCover(c, true, 2 + hold * 0.5), "covered again: still indoors")
		T.truthy(WeatherLogic.settleCover(c, false, 3), "out")
		T.truthy(WeatherLogic.settleCover(c, false, 3 + hold * 0.5), "not yet")
		T.falsy(WeatherLogic.settleCover(c, false, 3 + hold), "held: the weather is back")
		-- walking under a lamp: one covered reading never switches
		T.falsy(WeatherLogic.settleCover(c, true, 4), "under a lamp")
		T.falsy(WeatherLogic.settleCover(c, false, 4.25), "past it")
		T.falsy(WeatherLogic.settleCover(c, false, 6), "never blinked")
		T.eq(#WeatherLogic.roofOffsets(), WeatherConfig.Roof.Rays, "one start per side ray")
		T.truthy(WeatherConfig.Roof.Sides >= 1, "a ray round the player must agree with the one over it")
	end)

	T.test("weather: Covered places hold the roof reading (a jump in the EGGS temple, an aisle into the nave)", function()
		local hold = WeatherConfig.Roof.Hold
		-- a check every 0.25 s; returns true = the weather shows
		local c = WeatherLogic.newCover()
		T.truthy(WeatherLogic.roofGate(c, false, true, false, 0), "raining on the lawn")
		T.falsy(WeatherLogic.roofGate(c, true, true, true, 0.25), "into the temple: no weather")
		T.falsy(WeatherLogic.roofGate(c, true, true, true, 0.5), "on the dais")
		-- a jump: one check above the place, where the rays see only ghosts (no roof)
		T.falsy(WeatherLogic.roofGate(c, false, true, false, 0.75), "mid-jump: still no weather")
		T.falsy(WeatherLogic.roofGate(c, true, true, true, 1.0), "landed")
		-- THE GREAT FORGE: from a side aisle (a place) into the nave (the rays find its roof)
		T.falsy(WeatherLogic.roofGate(c, true, true, true, 2.0), "in the aisle")
		for t = 2.25, 4, 0.25 do
			T.falsy(WeatherLogic.roofGate(c, false, true, true, t), `in the nave at {t}: never back on`)
		end
		-- out into the open: the weather comes back after the hold, not before
		T.falsy(WeatherLogic.roofGate(c, false, true, false, 5), "out: not yet")
		T.falsy(WeatherLogic.roofGate(c, false, true, false, 5 + hold / 2), "not yet")
		T.truthy(WeatherLogic.roofGate(c, false, true, false, 5 + hold), "after the hold")
		-- weather begins while you stand inside: no blip
		local d = WeatherLogic.newCover()
		T.truthy(WeatherLogic.roofGate(d, false, false, false, 0), "clear")
		T.falsy(WeatherLogic.roofGate(d, false, true, true, 0.25), "rain begins under a roof: off at once")
		local e = WeatherLogic.newCover()
		T.falsy(WeatherLogic.roofGate(e, true, false, true, 0), "clear, in the temple")
		T.falsy(WeatherLogic.roofGate(e, true, true, true, 0.25), "rain begins in the temple")
		T.falsy(WeatherLogic.roofGate(e, false, true, false, 0.5), "a jump right away: still off")
	end)

	T.test("weather: small high parts are no roof (the golden dragon's fists over the statue ring)", function()
		local size = Vector3.new
		T.falsy(WeatherLogic.roofCounts(14, 0, true, false, size(3.7, 3.4, 3.6)), "a fist")
		T.falsy(WeatherLogic.roofCounts(3, 0, true, false, size(11, 3, 0.6)), "a sign board")
		T.falsy(WeatherLogic.roofCounts(4, 0, true, false, size(1.2, 1.3, 1.2)), "a king's crown")
		T.truthy(WeatherLogic.roofCounts(9, 0, true, false, size(30.6, 0.6, 15.6)), "the DROPPERS roof slab")
		T.truthy(WeatherLogic.roofCounts(9, 0, true, false, size(0.9, 12, 32)), "a turned slab")
		local FireCrystal = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.FireCrystal")
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local folder = roblox.Instance.new("Folder")
		FireCrystal.build(folder, Rng.new(1))
		T.truthy(folder:FindFirstChild("Fist1", true), "the dragon is built")
		local parts = partsOf(folder)
		for _, x in { -10, -9, -8, 8, 9, 10 } do
			for _, z in { -1, 0.5, 2 } do
				local p = Vector3.new(x, 1.83 + 3, z)
				T.falsy(covered(p, parts), `the statue ring at {p}: open sky`)
			end
		end
	end)
end
