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
		T.eq(#WeatherConfig.Order, 7, "seven kinds")
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
			for _, key in { "Rain", "Hail", "Snow", "Leaves", "Mist", "Heat", "Splash", "Bounce", "Settle", "Clack" } do
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
				look.On = name == "Fog"
			end
		end)
		for i = 0, 50 do
			T.eq(WeatherLogic.pick(i / 50, only), "Fog", "only fog")
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
		local half = WeatherLogic.tint("Fog", 0.5, 0)
		T.near(half.Contrast, WeatherConfig.Kinds.Fog.Tint.Contrast / 2, 1e-9, "half way")
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
end
