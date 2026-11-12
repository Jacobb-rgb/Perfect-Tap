-- The shop v3 "WOW" look under Lune (owner 2026-11-11: "cool and smooth, not laggy"): the effects
-- picture's cells, what shows before and after its upload (no wedges), the TweenService loops
-- (one endless tween per mark, Roblox's curves, nothing when quiet, no per-frame Lua), the
-- one-shot motions (open, close, a tab's fade, slide and pop), the lazy pages, the egg piles, the
-- instance and tween budgets, and the shop icon sheet against the concept's icons.js.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Vector2 = roblox.Vector2
	local UDim2 = roblox.UDim2
	local Color3 = roblox.Color3
	local Instance = roblox.Instance
	local function ui(name: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local ShopFx = ui("ShopFx")
	local Motion = ui("Motion")
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")
	local WHITE = Color3.new(1, 1, 1)

	-- Runs `fn` with the effects picture uploaded (`id` > 0) or not, then puts it back.
	local function withEffects(id: number, fn: () -> ())
		local sheet = IconAssets.ShopFx
		local before, preview, previewing = sheet.Id, sheet.Preview, IconAssets.Previewing
		sheet.Id = id
		IconAssets.Previewing = false
		local ok, err = pcall(fn)
		sheet.Id, sheet.Preview, IconAssets.Previewing = before, preview, previewing
		if not ok then
			error(err, 0)
		end
	end

	-- Records every tween ShopFx makes while `fn` runs (nothing plays).
	type Made = {
		Instance: any,
		Time: number,
		Style: string,
		Direction: string,
		Goal: { [string]: any },
		Repeats: number,
		Reverses: boolean,
		Delay: number,
		Cancelled: boolean,
	}
	local function recording(fn: (made: { Made }) -> ())
		local made: { Made } = {}
		ShopFx.useTweens(function(instance, time, style, direction, goal, repeats, reverses, delay)
			local record: Made = {
				Instance = instance,
				Time = time,
				Style = style,
				Direction = direction,
				Goal = goal,
				Repeats = repeats,
				Reverses = reverses,
				Delay = delay,
				Cancelled = false,
			}
			table.insert(made, record)
			return {
				Play = function() end,
				Cancel = function()
					record.Cancelled = true
				end,
			}
		end)
		local ok, err = pcall(fn, made)
		ShopFx.useTweens(nil)
		if not ok then
			error(err, 0)
		end
	end

	local function count(root: any, predicate: (d: any) -> boolean): number
		local n = 0
		for _, d in root:GetDescendants() do
			if predicate(d) then
				n += 1
			end
		end
		return n
	end

	---------------------------------------------------------------- the effects picture

	T.test("ShopFx: the effects picture's cells fit 1024 px, never overlap, and its tool draws them", function()
		local sheet = IconAssets.ShopFx
		T.eq(sheet.File, "obchod_efekty.png")
		local cells: { { number } } = {}
		local names: { string } = {}
		for name, cell in sheet.Cells do
			T.eq(#cell, 4, name)
			T.truthy(cell[1] >= 0 and cell[2] >= 0 and cell[3] > 0 and cell[4] > 0, name .. " has a size")
			T.truthy(cell[1] + cell[3] <= 1024 and cell[2] + cell[4] <= 1024, name .. " is inside 1024 px")
			table.insert(cells, cell)
			table.insert(names, name)
		end
		for i = 1, #cells do
			for j = i + 1, #cells do
				local a, b = cells[i], cells[j]
				local apart = a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1] or a[2] + a[4] <= b[2] or b[2] + b[4] <= a[2]
				T.truthy(apart, names[i] .. " and " .. names[j] .. " don't overlap")
			end
		end
		for _, name in { "rays", "glow", "sparkle", "dots", "flame", "studs", "bolt1", "bolt2", "bolt3" } do
			T.truthy(sheet.Cells[name] ~= nil, name)
		end
		-- the tool reads the same cells and writes the file the NAVOD names
		local tool = fs.readFile(Loader.root .. "/tools/preview/shop_effects_sheet.mjs")
		T.truthy(tool:find("IconAssets.ShopFx", 1, true) and tool:find("obchod_efekty.png", 1, true), "shop_effects_sheet.mjs")
		-- not uploaded: nothing in the game; a preview draws it unless told not to; uploaded: its cell
		withEffects(0, function()
			T.falsy(IconAssets.shopFxShows("rays"), "the game before the upload")
			IconAssets.Previewing = true
			T.truthy(IconAssets.shopFxShows("rays"), "a preview")
			sheet.Preview = false
			T.falsy(IconAssets.shopFxShows("rays"), "a preview of Studio before the upload")
		end)
		-- uploaded (owner 2026-11-12): the game shows them
		withEffects(sheet.Id, function()
			T.truthy(sheet.Id > 0, "the owner's upload is set")
			T.truthy(IconAssets.shopFxShows("rays"), "the game after the owner's upload")
		end)
		withEffects(123, function()
			T.truthy(IconAssets.shopFxShows("bolt2"))
			T.falsy(IconAssets.shopFxShows("nope"), "an unknown name")
			local label = Instance.new("ImageLabel")
			IconAssets.applyShopFx(label, "bolt2")
			local cell = sheet.Cells.bolt2
			T.eq(label.Image, "rbxassetid://123")
			T.eq(label.ImageRectOffset, Vector2.new(cell[1], cell[2]))
			T.eq(label.ImageRectSize, Vector2.new(cell[3], cell[4]))
			T.eq(label:GetAttribute("Icon"), "shopfx_bolt2", "the previews' picture")
		end)
	end)

	T.test("ShopFx: one image per effect; before the upload plain gradients, no wedges (the icon sheet's bolt and sparkle)", function()
		withEffects(0, function()
			local parent = Instance.new("Frame")
			T.eq(ShopFx.rays(parent, UDim2.fromScale(0.5, 0.5), 300, 0.5, 2), nil, "no rays")
			T.eq(ShopFx.studs(parent, 300, 60, 17, 0.2, 3), nil, "no studs")
			local glow = ShopFx.glow(parent, UDim2.fromScale(0.5, 0.5), 80, WHITE, 2)
			T.eq(glow.ClassName, "Frame", "the glow: one soft disc")
			T.truthy(#glow:GetDescendants() <= 1, "(and its corner)")
			T.eq(ShopFx.bolt(parent, UDim2.fromOffset(10, 10), 200, 20, WHITE, 1, 2, 5, false), nil, "a card's bolt waits for the upload")
			local bolt = ShopFx.bolt(parent, UDim2.fromOffset(10, 10), 200, 20, WHITE, 1, 2, 5)
			T.truthy(bolt and bolt:GetAttribute("Icon") == "shop_bolt", "the window's bolts: the icon sheet's (uploaded)")
			local sparkle = ShopFx.sparkle(parent, UDim2.fromOffset(4, 4), 20, WHITE, 3, 1)
			T.eq(sparkle:GetAttribute("Icon"), "shop_sparkle")
			T.truthy(sparkle:FindFirstChild("Pulse"), "it twinkles by its UIScale")
			T.eq(
				count(parent, function(d)
					return d.Name == "Ray" or d.Name == "Seg" or d.Name == "Stud" or d.Name == "Dot"
				end),
				0,
				"no wedge, segment, stud or dot frames"
			)
		end)
		withEffects(1, function()
			local parent = Instance.new("Frame")
			local rays = ShopFx.rays(parent, UDim2.fromScale(0.5, 0.5), 300, 0.5, 2, WHITE, 30)
			T.truthy(rays and rays.ClassName == "ImageLabel", "the rays: one image")
			T.eq(rays:GetAttribute("ShopFx"), "Rays")
			T.eq(rays:GetAttribute("Period"), 30)
			local studs = ShopFx.studs(parent, 300, 60, 17, 0.2, 3) :: any
			T.eq(#studs:GetChildren(), math.ceil(300 / (17 * 12)) * math.ceil(60 / (17 * 12)), "a few patches of 12 x 12 studs")
			-- (owner's Studio 2026-11-12: the tilted X drew a whole patch past the window, Roblox doesn't
			-- clip under a turned frame) every patch is cut to the face: nothing past w x h, same stud size
			local cell = IconAssets.ShopFx.Cells.studs
			for _, case in { { 300, 60, 17 }, { 58, 58, 18 }, { 1050, 81, 28 }, { 140, 50, 17 } } do
				local w, h, stud = case[1], case[2], case[3]
				local holder = ShopFx.studs(Instance.new("Frame"), w, h, stud, 0.2, 3) :: any
				local patch = stud * 12
				for _, image in holder:GetChildren() do
					local x, y = image.Position.X.Offset, image.Position.Y.Offset
					local iw, ih = image.Size.X.Offset, image.Size.Y.Offset
					T.truthy(x + iw <= w + 1e-6 and y + ih <= h + 1e-6, `{w} x {h}: a patch ends inside ({x + iw}, {y + ih})`)
					local rect = if iw < patch or ih < patch then image.ImageRectSize else Vector2.new(cell[3], cell[4])
					T.near(rect.X / iw, cell[3] / patch, 1e-6, `{w} x {h}: the studs keep their size across`)
					T.near(rect.Y / ih, cell[4] / patch, 1e-6, `{w} x {h}: the studs keep their size down`)
					if iw < patch or ih < patch then
						T.eq(image:GetAttribute("Crop"), Vector2.new(iw / patch, ih / patch), "the previews' cut")
					end
				end
			end
			local bolt = ShopFx.bolt(parent, UDim2.fromOffset(10, 10), 200, 20, WHITE, 3, 2, 6, false) :: any
			T.eq(bolt:GetAttribute("Icon"), "shopfx_bolt3")
			T.eq(bolt.Size, UDim2.fromOffset(math.floor(200 * 0.375), 200))
			T.near(bolt.ImageTransparency, ShopFx.BoltRest, 1e-6, "softly lit at rest")
		end)
	end)

	---------------------------------------------------------------- the loops

	-- A small window with one of every mark (the effects picture uploaded).
	local function marked(): any
		local root = Instance.new("Frame")
		local rays = ShopFx.rays(root, UDim2.fromScale(0.5, 0.5), 300, 0.5, 2, WHITE, 30)
		rays.Rotation = 10
		local bolt = ShopFx.bolt(root, UDim2.fromOffset(10, 10), 200, 20, WHITE, 1, 2, 6)
		local price = ShopFx.priceButton(root, 99, Vector2.new(160, 50), "Green")
		local sparkle = ShopFx.sparkle(root, UDim2.fromOffset(4, 4), 20, WHITE, 3, 2)
		local card = Instance.new("TextButton")
		card.Parent = root
		ShopFx.mythicRim(card, 5)
		local best = Instance.new("Frame")
		best.Parent = root
		local pulse = Instance.new("UIScale")
		pulse.Name = "Pulse"
		pulse.Parent = best
		best:SetAttribute("ShopFx", "Pulse")
		local hero = Instance.new("Frame")
		hero.Position = UDim2.fromOffset(50, 40)
		hero.Parent = root
		hero:SetAttribute("ShopFx", "Float")
		local lift = Instance.new("Frame")
		lift.Position = UDim2.fromScale(0.5, 0.5)
		lift.Parent = root
		lift:SetAttribute("ShopFx", "Bob")
		-- a hidden card's rays, an ambient bolt (a phone shows neither)
		local hidden = Instance.new("Frame")
		hidden.Visible = false
		hidden.Parent = root
		ShopFx.rays(hidden, UDim2.fromScale(0.5, 0.5), 300, 0.5, 2)
		local ambient = ShopFx.bolt(root, UDim2.fromOffset(10, 10), 200, 20, WHITE, 2, 2, 5)
		ambient:SetAttribute("Ambient", true)
		return {
			Root = root,
			Rays = rays,
			Bolt = bolt,
			Sweep = (price.Face :: any).Shine.Sweep,
			Sparkle = sparkle,
			Rim = (card :: any).Border.Rainbow,
			Pulse = pulse,
			Hero = hero,
			Lift = lift,
		}
	end

	local function byKind(loops: { any }): { [string]: { any } }
		local out: { [string]: { any } } = {}
		for _, loop in loops do
			out[loop.Kind] = out[loop.Kind] or {}
			table.insert(out[loop.Kind], loop)
		end
		return out
	end

	T.test("ShopFx: one endless loop per mark on Roblox's curves (rays, shine, bolts, sparkles, rim, pulse, float, bob)", function()
		withEffects(1, function()
			local m = marked()
			local loops = ShopFx.loopsUnder({ m.Root })
			local kinds = byKind(loops)
			T.eq(#kinds.Rays, 1, "the hidden card's rays don't turn")
			T.eq(#kinds.Bolt, 2, "two bolts")
			T.eq(#byKind(ShopFx.loopsUnder({ m.Root }, true)).Bolt, 1, "a phone: no ambient bolt")
			for _, kind in { "Shine", "Sparkle", "Rim", "Pulse", "Float", "Bob" } do
				T.eq(#kinds[kind], 1, kind)
			end
			-- the rays: one slow turn a period, from where they were built
			local rays = kinds.Rays[1]
			T.eq(rays.Property, "Rotation")
			T.eq(rays.Style, "Linear")
			T.falsy(rays.Reverses)
			T.near(ShopFx.sample(rays, 0), 10, 1e-9)
			T.near(ShopFx.sample(rays, 7.5), 100, 1e-9, "a quarter turn in a quarter period")
			T.near(ShopFx.sample(rays, 30), 10, 1e-9, "round again")
			-- the shine: a sweep every ShineTime, off the button at the start
			local shine = kinds.Shine[1]
			T.eq(shine.Target, m.Sweep)
			T.near(ShopFx.sample(shine, 0).X, ShopFx.ShineFrom, 1e-6)
			T.near(ShopFx.sample(shine, ShopFx.ShineTime / 2).X, (ShopFx.ShineFrom + ShopFx.ShineTo) / 2, 1e-6)
			-- the next button's band starts further off at the same speed: the buttons shine one after another
			local more = Instance.new("Frame")
			ShopFx.priceButton(more, 49, Vector2.new(160, 50), "Gold")
			ShopFx.priceButton(more, 99, Vector2.new(160, 50), "Green")
			local two = byKind(ShopFx.loopsUnder({ more })).Shine
			T.eq(#two, 2)
			T.truthy(two[2].From.X < two[1].From.X, "the second starts further off")
			local speed1 = (two[1].To.X - two[1].From.X) / two[1].Time
			local speed2 = (two[2].To.X - two[2].From.X) / two[2].Time
			T.near(speed1, speed2, 1e-6, "at the same speed")
			T.eq(two[2].Rest, two[1].Rest, "both rest off the button")
			-- a bolt: dark most of the time (a transparency over 1), lit for a moment each period
			local bolt = kinds.Bolt[1]
			T.eq(bolt.Property, "ImageTransparency")
			T.truthy(bolt.Reverses)
			T.near(bolt.Time, 3, 1e-9, "half its 6 s period")
			T.truthy(ShopFx.sample(bolt, 0) > 1, "dark")
			T.near(ShopFx.sample(bolt, 3), ShopFx.BoltPeak, 1e-9, "lit at its peak")
			local lit = 0
			for i = 0, 599 do
				if ShopFx.sample(bolt, i * 0.01) < 1 then
					lit += 1
				end
			end
			T.truthy(lit > 0 and lit < 120, `a quick flash: lit {lit / 100} s of 6`)
			-- the sparkle twinkles, the pulse breathes, the hero floats, the tab bobs
			for t = 0, 3, 0.05 do
				local s = ShopFx.sample(kinds.Sparkle[1], t)
				T.truthy(s >= 0.35 - 1e-9 and s <= 1.1 + 1e-9, "a sparkle 0.35 .. 1.1")
				local p = ShopFx.sample(kinds.Pulse[1], t)
				T.truthy(p >= 1 - 1e-9 and p <= ShopFx.PulsePeak + 1e-9, "a gentle pulse")
				local f = ShopFx.sample(kinds.Float[1], t)
				T.truthy(f.Y.Offset <= 40 + 1e-9 and f.Y.Offset >= 40 - ShopFx.FloatRise - 1e-9, "the hero floats up to FloatRise")
				local b = ShopFx.sample(kinds.Bob[1], t)
				T.truthy(b.Y.Scale == 0.5 and b.Y.Offset >= -ShopFx.BobRise - 1e-9 and b.Y.Offset <= 1e-9, "the tab bobs BobRise")
			end
			T.eq(kinds.Sparkle[1].Target, m.Sparkle:FindFirstChild("Pulse"), "a sparkle's UIScale")
			T.eq(kinds.Rim[1].Target, m.Rim)
			T.near(ShopFx.sample(kinds.Rim[1], ShopFx.RimTime / 4), 90, 1e-9, "the rim runs round")
		end)
	end)

	T.test("ShopFx: play makes one endless tween per loop, stop cancels them and puts all at rest, quiet makes none", function()
		withEffects(1, function()
			local m = marked()
			local loops = ShopFx.loopsUnder({ m.Root })
			recording(function(made)
				local playing = ShopFx.play(loops)
				T.eq(#made, #loops, "one tween a loop")
				for _, record in made do
					T.eq(record.Repeats, -1, "endless")
				end
				T.near(m.Bolt.ImageTransparency, ShopFx.BoltDark, 1e-6, "a bolt starts dark")
				ShopFx.stop(playing)
				for _, record in made do
					T.truthy(record.Cancelled, "cancelled")
				end
				T.near(m.Bolt.ImageTransparency, ShopFx.BoltRest, 1e-6, "a bolt rests softly lit")
				T.near(m.Sweep.Offset.X, ShopFx.ShineFrom, 1e-6, "the shine off the button")
				T.near(m.Rays.Rotation, 10, 1e-6, "the rays where they were built")
				T.eq(m.Lift.Position, UDim2.fromScale(0.5, 0.5), "the tab back")
				T.eq((m.Sparkle :: any).Pulse.Scale, 1)
				-- Reduce motion / PixelFx off: the shop stands still
				table.clear(made)
				Motion.setReduced(true)
				local ok, err = pcall(function()
					T.truthy(ShopFx.quiet())
					local still = ShopFx.play(loops)
					T.eq(#made, 0, "no tween")
					T.eq(#still.Loops, 0)
					local group = Instance.new("Frame")
					local dim = Instance.new("Frame")
					ShopFx.open(group, dim, 0.45)
					T.eq(#made, 0, "the window just shows")
					T.eq((group :: any).OpenPop.Scale, 1)
					T.near(dim.BackgroundTransparency, 0.45, 1e-6)
					local closed = false
					ShopFx.close(group, dim, function()
						closed = true
					end)
					T.truthy(closed, "and just goes")
				end)
				Motion.setReduced(false)
				if not ok then
					error(err, 0)
				end
				local pixel = AnimConfig.PixelFx
				AnimConfig.PixelFx = false
				T.truthy(ShopFx.quiet(), "PixelFx off: quiet")
				AnimConfig.PixelFx = pixel
			end)
		end)
		-- no per-frame Lua anywhere in the shop: TweenService only
		for _, file in { "UI/ShopFx", "UI/StoreView", "Controllers/StoreController" } do
			local source = fs.readFile(Loader.root .. "/src/client/" .. file .. ".luau")
			for _, hook in { "Heartbeat", "RenderStepped", "Stepped", "BindToRenderStep" } do
				T.falsy(source:find(hook, 1, true), file .. " has no " .. hook)
			end
		end
	end)

	T.test("ShopFx: it opens with a Back pop, a dim fade and a burst; closes small and faded; a tab fades, slides and pops", function()
		local StoreView = ui("StoreView")
		withEffects(1, function()
			recording(function(made)
				local group = Instance.new("Frame")
				local dim = Instance.new("Frame")
				local burst = Instance.new("ImageLabel")
				burst.Visible = false
				ShopFx.open(group, dim, 0.45, burst)
				local pop = (group :: any).OpenPop
				T.near(pop.Scale, 0.82, 1e-6, "from 0.82")
				T.eq(made[1].Instance, pop)
				T.eq(made[1].Style, "Back")
				T.eq(made[1].Direction, "Out")
				T.eq(made[1].Goal.Scale, 1)
				T.eq(dim.BackgroundTransparency, 1, "the dim from clear")
				T.eq(made[2].Goal.BackgroundTransparency, 0.45)
				T.truthy(burst.Visible, "the burst flashes")
				T.eq(made[3].Goal.ImageTransparency, 1, "and fades")
				table.clear(made)
				ShopFx.close(group, dim, function() end)
				T.eq(made[1].Goal.Scale, 0.86, "it shrinks a little")
				T.truthy(made[1].Time <= 0.15, "quickly")
				T.eq(made[2].Goal.BackgroundTransparency, 1, "the dim fades")
				-- a tab: the old colours fade over the new, the page slides in, the cards pop in one by one
				local refs = StoreView.build()
				table.clear(made)
				StoreView.selectTab(refs, "Golems", true)
				local fades, slides, pops, delays = 0, 0, 0, {}
				for _, record in made do
					if record.Goal.BackgroundTransparency == 1 and record.Instance.Name:find("Over") then
						fades += 1
					elseif record.Instance == refs.Pages.Golems then
						slides += 1
					elseif record.Instance.Name == "Scale" and record.Style == "Back" then
						pops += 1
						table.insert(delays, record.Delay)
					end
				end
				T.eq(fades, 3, "the header, its band and the body fade over")
				T.eq(slides, 1, "the page slides in")
				T.truthy(pops >= 4, "the cards pop in")
				T.eq(delays[1], 0)
				T.truthy(delays[#delays] > delays[1], "one after another")
				-- the same tab again: nothing moves
				table.clear(made)
				StoreView.selectTab(refs, "Golems", true)
				T.eq(#made, 0)
			end)
		end)
	end)

	---------------------------------------------------------------- the pages

	T.test("ShopFx: the shop builds only the open tab; a tab's first visit builds it with what it was told", function()
		local StoreView = ui("StoreView")
		local refs = StoreView.build(nil, true)
		T.truthy(refs.Built.Featured, "the open tab")
		T.eq(#refs.Pages.Golems:GetChildren(), 0, "the others wait")
		T.eq(refs.Cards.Royal5, nil)
		T.eq(table.concat(StoreView.takeBuilt(refs), ","), "Featured", "the controller wires it")
		T.eq(#StoreView.takeBuilt(refs), 0, "once")
		-- told before it is built: kept
		StoreView.setCard(refs, "Royal5", "RoyalCapsule5", "Pending")
		StoreView.setCoins(refs, 1000)
		T.eq(refs.States.Royal5.State, "Pending")
		local changed, built = StoreView.selectTab(refs, "Golems")
		T.truthy(changed and built, "built on its first visit")
		T.eq(refs.Cards.Royal5.State, "Pending", "shows what it was told")
		T.truthy(refs.Cards.Royal5.Shade.Visible)
		T.eq(table.concat(StoreView.takeBuilt(refs), ","), "Golems")
		local _, again = StoreView.selectTab(refs, "Golems")
		T.falsy(again, "built once")
		StoreView.selectTab(refs, "Cash")
		T.eq((refs.Cards.CoinsMega.Amount :: any).Text, "$18M", "the coins at the income it was told")
		-- a tab with nothing to show hides from what it was told (built or not)
		local fresh = StoreView.build(nil, true)
		for _, id in { "Royal1", "Royal3", "Royal5", "Royal10" } do
			StoreView.setCard(fresh, id, StoreConfig.ById[id].Keys[1], "Hidden")
		end
		StoreView.setRoyalShown(fresh, false)
		T.falsy(StoreView.tabShown(fresh, "Golems"), "no eggs: the tab hides unbuilt")
		T.falsy(fresh.Built.Golems)
	end)

	T.test("ShopFx: first open well under half of the old 6,674 instances; few tweens and few 3D views a tab", function()
		local StoreView = ui("StoreView")
		withEffects(1, function()
			local refs = StoreView.build(nil, true)
			StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
			local first = #refs.Gui:GetDescendants()
			T.truthy(first < 6674 / 2, `instances at the first open: {first}`)
			local windowLoops = #ShopFx.loopsUnder(refs.Fx, false)
			T.truthy(windowLoops <= 16, `the window's tweens: {windowLoops}`)
			for _, section in StoreConfig.Sections do
				StoreView.selectTab(refs, section.Id)
				local loops = #ShopFx.loopsUnder({ refs.Pages[section.Id], refs.TabRefs[section.Id].Lift })
				T.truthy(loops <= 30, `{section.Id}: {loops} tweens`)
				local views = count(refs.Pages[section.Id], function(d)
					return d.ClassName == "ViewportFrame"
				end)
				T.truthy(views <= 12, `{section.Id}: {views} 3D views`)
			end
			local all = #refs.Gui:GetDescendants()
			T.truthy(all < 6674 * 0.8, `every tab visited: {all}`)
			-- a phone: none of the ambient ones
			local phone = StoreView.build(StoreView.metricsFor(true, 1), true)
			for _, loop in ShopFx.loopsUnder(phone.Fx, true) do
				T.falsy(loop.Target:GetAttribute("Ambient"), "no ambient " .. loop.Kind .. " on a phone")
			end
		end)
	end)

	T.test("ShopFx: an egg pack's three eggs are one 3D view; the open tab's models are built, the others wait", function()
		local StoreView = ui("StoreView")
		local refs = StoreView.build()
		local function waiting(page: any): number
			return count(page, function(d)
				return d:GetAttribute("Model") ~= nil
			end)
		end
		T.eq(waiting(refs.Pages[refs.Current]), 0, "the open tab's models are built")
		T.truthy(waiting(refs.Pages.Golems) > 0, "the Golems tab's wait for it")
		StoreView.selectTab(refs, "Golems")
		T.eq(waiting(refs.Pages.Golems), 0, "shown: built")
		for _, id in { "Royal3", "Royal5", "Royal10" } do
			local card = refs.Cards[id]
			local views = count(card.Holder, function(d)
				return d.ClassName == "ViewportFrame"
			end)
			T.eq(views, 1, id .. ": one view")
			local view = (card.Picture :: any).View
			T.eq(#view:GetChildren(), 2, id .. ": the pile and its camera")
			local pile = view:FindFirstChildOfClass("Model")
			T.eq(#pile:GetChildren(), 3, id .. ": three eggs")
			T.truthy(view:FindFirstChildOfClass("Camera") ~= nil, id .. " framed")
		end
		T.eq(
			count(refs.Cards.Royal1.Holder, function(d)
				return d.ClassName == "ViewportFrame"
			end),
			1,
			"x1: one egg"
		)
	end)

	---------------------------------------------------------------- the icon sheet

	T.test("ShopFx: the shop icon sheet matches the concept's icons, one cell each, under 1024 px", function()
		local source = fs.readFile(Loader.root .. "/docs/art/shop_v3_concept/icons.js")
		local block = string.match(source, "const I = {(.-)\n  };") or ""
		local names: { string } = {}
		for name in string.gmatch(block, "\n    ([%w_]+): %(%) =>") do
			table.insert(names, name)
		end
		T.truthy(#names >= 30, "icons.js lists its icons (" .. #names .. ")")
		local sheet = IconAssets.Shop
		T.eq(table.concat(sheet.Icons, ","), table.concat(names, ","), "the sheet's order is the concept's")
		local rows = math.ceil(#sheet.Icons / sheet.Columns)
		T.truthy(math.max(rows, sheet.Columns) * sheet.Cell <= 1024, "under Roblox's 1024 px")
		local seen: { [number]: boolean } = {}
		for _, name in sheet.Icons do
			local cell = IconAssets.shopCell(name) :: number
			T.falsy(seen[cell], name .. " has its own cell")
			seen[cell] = true
		end
		-- every sheet picture the shop asks for is in it
		for _, section in StoreConfig.Sections do
			T.truthy(IconAssets.shopCell(section.TabIcon) ~= nil, section.Id .. "'s tab picture")
		end
		for _, spec in StoreConfig.Cards do
			if spec.Sheet then
				T.truthy(IconAssets.shopCell(spec.Sheet) ~= nil, spec.Id .. "'s picture " .. spec.Sheet)
			end
			for _, icon in spec.LineIcons or {} do
				T.truthy(IconAssets.shopCell(icon) ~= nil, spec.Id .. "'s line picture " .. icon)
			end
		end
		for _, name in { "basket", "lock", "clock", "bolt", "sparkle" } do
			T.truthy(IconAssets.shopCell(name) ~= nil, name)
		end
		-- not uploaded (Id 0): nothing shows in the game; a preview shows them unless told not to
		local before, preview, id = IconAssets.Previewing, sheet.Preview, sheet.Id
		sheet.Id = 0
		IconAssets.Previewing = false
		T.falsy(IconAssets.shopShows("crown"), "the game before the upload")
		IconAssets.Previewing = true
		T.truthy(IconAssets.shopShows("crown"), "a preview")
		sheet.Preview = false
		T.falsy(IconAssets.shopShows("crown"), "a preview of Studio before the upload")
		-- uploaded (owner 2026-11-11): the game shows them
		sheet.Id = id
		IconAssets.Previewing = false
		T.truthy(id > 0 and IconAssets.shopShows("crown"), "the game after the owner's upload")
		IconAssets.Previewing, sheet.Preview = before, preview
		T.falsy(IconAssets.shopShows("nope"), "an unknown name")
		-- once uploaded: its cell of the image
		local label = Instance.new("ImageLabel")
		sheet.Id = 123
		IconAssets.applyShop(label, "egg")
		sheet.Id = id
		local cell = IconAssets.shopCell("egg") :: number
		T.eq(label.Image, "rbxassetid://123")
		T.eq(label.ImageRectOffset, Vector2.new((cell % sheet.Columns) * sheet.Cell, (cell // sheet.Columns) * sheet.Cell))
		T.eq(label.ImageRectSize, Vector2.new(sheet.Cell, sheet.Cell))
	end)

	---------------------------------------------------------------- the golem stickers

	-- Runs `fn` with the golem stickers' image uploaded (`id` > 0) or not, then puts it back.
	local function withStickers(id: number, fn: () -> ())
		local sheet = IconAssets.ShopGolems
		local before, preview, previewing = sheet.Id, sheet.Preview, IconAssets.Previewing
		sheet.Id = id
		IconAssets.Previewing = false
		local ok, err = pcall(fn)
		sheet.Id, sheet.Preview, IconAssets.Previewing = before, preview, previewing
		if not ok then
			error(err, 0)
		end
	end

	-- The golems and eggs the shop shows: the Royal Egg's, the cards' (the Starter Pack's golem, the
	-- Royal eggs) and the limited edition on sale's (its golems and its shard).
	local function shopGolems(): { string }
		local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
		local names = { "capsule_Royal" }
		for _, line in CapsuleConfig.odds("Royal", false) do
			table.insert(names, "golem_" .. line.Golem)
		end
		for _, spec in StoreConfig.Cards do
			local model = spec.Model
			if model and (string.sub(model, 1, 6) == "golem_" or string.sub(model, 1, 8) == "capsule_") then
				table.insert(names, model)
			end
		end
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		if edition then
			table.insert(names, "capsule_" .. edition.CapsuleId)
			for _, golem in edition.Golems do
				table.insert(names, "golem_" .. golem.Id)
			end
		end
		return names
	end

	-- (owner 2026-11-11, pick B: the game's own golems and eggs drawn like the shop's icons)
	T.test("ShopFx: golems.js draws every golem sticker, one cell each under 1024 px; every shop golem and egg has one", function()
		local source = fs.readFile(Loader.root .. "/docs/art/shop_v3_concept/golems.js")
		local drawn: { [string]: boolean } = {}
		local count = 0
		for name in string.gmatch(source, "\n  D%.([%w_]+) = %(%) =>") do
			drawn[name] = true
			count += 1
		end
		local sheet = IconAssets.ShopGolems
		T.eq(sheet.File, "obchod_golemove.png")
		T.eq(count, #sheet.Icons, "golems.js draws exactly the sheet's stickers")
		local rows = math.ceil(#sheet.Icons / sheet.Columns)
		T.truthy(sheet.Columns * sheet.Cell <= 1024 and rows * sheet.Cell <= 1024, "under Roblox's 1024 px")
		local seen: { [number]: boolean } = {}
		for i, name in sheet.Icons do
			T.truthy(drawn[name], name .. " is drawn in golems.js")
			local cell = IconAssets.shopGolemCell(name) :: number
			T.eq(cell, i - 1, name .. ": the sheet's order")
			T.falsy(seen[cell], name .. " has its own cell")
			seen[cell] = true
		end
		for _, name in shopGolems() do
			T.truthy(IconAssets.shopGolemCell(name) ~= nil, name .. " (in the shop) has a sticker")
		end
		-- the tool reads the same order and cells and writes the file the NAVOD names
		local tool = fs.readFile(Loader.root .. "/tools/preview/shop_golem_sheet.mjs")
		T.truthy(tool:find("IconAssets.ShopGolems", 1, true) and tool:find("obchod_golemove.png", 1, true), "shop_golem_sheet.mjs")
		-- not uploaded (Id 0): nothing in the game; a preview shows them unless told not to
		withStickers(0, function()
			T.falsy(IconAssets.shopGolemShows("golem_DragonKing"), "the game before the upload")
			IconAssets.Previewing = true
			T.truthy(IconAssets.shopGolemShows("golem_DragonKing"), "a preview")
			sheet.Preview = false
			T.falsy(IconAssets.shopGolemShows("golem_DragonKing"), "a preview of Studio before the upload")
		end)
		-- uploaded: its cell of the image; a golem without a sticker never shows one
		withStickers(123, function()
			T.truthy(IconAssets.shopGolemShows("capsule_Dragonforge"))
			T.falsy(IconAssets.shopGolemShows("golem_PebbleGolem"), "no sticker: never")
			local label = Instance.new("ImageLabel")
			IconAssets.applyShopGolem(label, "capsule_Dragonforge")
			local cell = IconAssets.shopGolemCell("capsule_Dragonforge") :: number
			T.eq(label.Image, "rbxassetid://123")
			T.eq(label.ImageRectOffset, Vector2.new((cell % sheet.Columns) * sheet.Cell, (cell // sheet.Columns) * sheet.Cell))
			T.eq(label.ImageRectSize, Vector2.new(sheet.Cell, sheet.Cell))
			T.eq(label:GetAttribute("Icon"), "sticker_capsule_Dragonforge", "the previews' picture")
		end)
	end)

	T.test("ShopFx: before the sticker upload the shop's golems and eggs stay live 3D; after it they are images, no 3D view", function()
		local StoreView = ui("StoreView")
		local function build(): any
			local refs = StoreView.build()
			StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
			StoreView.selectTab(refs, "Golems")
			StoreView.selectTab(refs, "Featured")
			return refs
		end
		local function stickers(root: any): { [string]: number }
			local out: { [string]: number } = {}
			for _, d in root:GetDescendants() do
				local icon = d:GetAttribute("Icon")
				if d:IsA("ImageLabel") and type(icon) == "string" and string.sub(icon, 1, 8) == "sticker_" then
					out[icon] = (out[icon] or 0) + 1
				end
			end
			return out
		end
		local function views(root: any): number
			return count(root, function(d)
				return d.ClassName == "ViewportFrame"
			end)
		end
		withStickers(0, function()
			local refs = build()
			T.eq(next(stickers(refs.Gui)), nil, "no sticker before the upload")
			T.truthy(views(refs.Pages.Golems) >= 10, "the Golems tab's live golems and eggs")
			local hero = refs.Banner.Frame:FindFirstChild("Hero")
			T.truthy(hero and hero:FindFirstChild("View"), "the hero is a live model")
		end)
		withStickers(123, function()
			local refs = build()
			local shown = stickers(refs.Gui)
			for _, name in shopGolems() do
				T.truthy((shown["sticker_" .. name] or 0) > 0, name .. " shows its sticker")
			end
			T.eq(views(refs.Pages.Golems), 0, "no 3D view left on the Golems tab")
			T.eq(stickers(refs.Pages.Golems).sticker_capsule_Royal, 1 + 1 + 3 * 3, "the banner's egg, x1, three in each pile")
			local featured = views(refs.Pages.Featured)
			T.truthy(featured <= 2, `the Featured tab: only the Starter Pack's coins and podium stay 3D ({featured})`)
			local hero = refs.Banner.Frame:FindFirstChild("Hero")
			T.truthy(hero and hero:IsA("ImageLabel") and hero:GetAttribute("Icon") == "sticker_golem_DragonKing", "the hero")
			T.eq(hero:GetAttribute("ShopFx"), "Float", "it still floats")
			T.eq(hero.Image, "rbxassetid://123")
			for _, id in { "Royal3", "Royal5", "Royal10" } do
				local pile = refs.Cards[id].Picture :: any
				T.eq(#pile:GetChildren(), 3, id .. ": three eggs")
				T.eq(pile:GetAttribute("Copies"), nil, id .. ": no 3D pile to build")
			end
			T.eq(
				count(refs.Gui, function(d)
					return d:GetAttribute("Model") ~= nil and string.match(tostring(d:GetAttribute("Model")), "^golem_") ~= nil
				end),
				0,
				"no golem model waits to be built"
			)
		end)
	end)
end
