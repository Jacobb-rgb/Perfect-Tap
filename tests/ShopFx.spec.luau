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
			T.truthy(windowLoops <= 17, `the window's tweens: {windowLoops}`)
			for _, section in StoreConfig.Sections do
				StoreView.selectTab(refs, section.Id)
				local loops = #ShopFx.loopsUnder({ refs.Pages[section.Id], refs.TabRefs[section.Id].Lift })
				T.truthy(loops <= 56, `{section.Id}: {loops} tweens (the budgets per tab: the motion v2 spec)`)
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

	-- Runs `fn` with every sticker image uploaded (`id` > 0) or none, then puts them back.
	local function withStickers(id: number, fn: () -> ())
		local before: { { Id: number, Preview: boolean } } = {}
		for i, sheet in IconAssets.StickerSheets do
			before[i] = { Id = sheet.Id, Preview = sheet.Preview }
			sheet.Id = id
		end
		local previewing = IconAssets.Previewing
		IconAssets.Previewing = false
		local ok, err = pcall(fn)
		for i, sheet in IconAssets.StickerSheets do
			sheet.Id, sheet.Preview = before[i].Id, before[i].Preview
		end
		IconAssets.Previewing = previewing
		if not ok then
			error(err, 0)
		end
	end

	-- (the live 3D models: as before the sticker images were uploaded, or if one fails to load)
	T.test("ShopFx: an egg pack's three eggs are one 3D view; the open tab's models are built, the others wait", function()
		withStickers(0, function()
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

	---------------------------------------------------------------- the drawn stickers (golems, eggs, pass items)

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

	-- (owner 2026-11-11 pick B, drawn like the shop's icons; 2026-11-12 "it has to look like it is in
	-- the game": every sticker is drawn from the model the shop's 3D picture shows; then "the
	-- hoverboard etc. doesn't have the drawn style yet": the PASSES tab's podium, train, hoverboard)
	T.test(
		"ShopFx: stickers are drawn from the game's models, one cell each under 1024 px; every shop golem and pass item has one",
		function()
			local PictureModels = Loader.requirePath("ReplicatedStorage.Shared.Builders.PictureModels")
			T.eq(IconAssets.ShopGolems.File, "obchod_golemove.png")
			T.eq(IconAssets.ShopItems.File, "obchod_predmety.png")
			T.truthy(IconAssets.ShopGolems.Id > 0, "the golem stickers are uploaded (owner 2026-11-12)")
			T.truthy(IconAssets.ShopItems.Id > 0, "the PASSES items' stickers are uploaded (owner 2026-11-16)")
			local files: { [string]: boolean } = {}
			for _, sheet in IconAssets.StickerSheets do
				T.falsy(files[sheet.File], sheet.File .. ": one image each")
				files[sheet.File] = true
				local rows = math.ceil(#sheet.Icons / sheet.Columns)
				T.truthy(sheet.Columns * sheet.Cell <= 1024 and rows * sheet.Cell <= 1024, sheet.File .. " under Roblox's 1024 px")
				local seen: { [number]: boolean } = {}
				for i, name in sheet.Icons do
					-- the model its 3D picture builds (the renderer draws exactly this one, from this side)
					local model, from = PictureModels.build(name)
					T.truthy(model ~= nil, name .. " is a game model (PictureModels)")
					local parts = 0
					for _, d in (model :: any):GetDescendants() do
						if d:IsA("BasePart") and d.Transparency < 0.99 then
							parts += 1
						end
					end
					T.truthy(parts >= 5, name .. ": the model's parts")
					T.truthy(from.Z < 0, name .. ": seen from its front (-Z)")
					T.eq(IconAssets.shopStickerSheet(name), sheet, name .. ": its image")
					local cell = IconAssets.shopStickerCell(name) :: number
					T.eq(cell, i - 1, name .. ": the image's order")
					T.falsy(seen[cell], name .. " has its own cell")
					seen[cell] = true
				end
			end
			for _, name in shopGolems() do
				T.truthy(IconAssets.shopStickerCell(name) ~= nil, name .. " (in the shop) has a sticker")
			end
			-- every picture of the PASSES tab is drawn once the images are in (an icon or a sticker)
			for _, spec in StoreConfig.Cards do
				if spec.Section == "Passes" then
					local drawn = spec.Sheet ~= nil or (spec.Model ~= nil and IconAssets.shopStickerCell(spec.Model :: string) ~= nil)
					T.truthy(drawn, spec.Id .. " (PASSES) is drawn")
				end
			end
			-- the tools: the export walks every image's names through PictureModels.build; the renderer
			-- runs it, reads the same order and cells and writes each image the NAVOD names
			local export = fs.readFile(Loader.root .. "/tools/lune/export_golem_stickers.luau")
			local exports = export:find("IconAssets.StickerSheets", 1, true) and export:find("PictureModels.build", 1, true)
			T.truthy(exports, "export_golem_stickers.luau")
			local tool = fs.readFile(Loader.root .. "/tools/preview/shop_golem_sheet.mjs")
			T.truthy(tool:find("golem_stickers.json", 1, true) and tool:find("sheet.file", 1, true), "shop_golem_sheet.mjs")
			T.truthy(tool:find("sheet.id === 0", 1, true), "an uploaded image is not written again")
			local draws = tool:find("export_golem_stickers.luau", 1, true) and tool:find("golem_toon/toon.html", 1, true)
			T.truthy(draws, "it draws the exported models")
			T.truthy(fs.isFile(Loader.root .. "/tools/preview/golem_toon/toon.js"), "the toon renderer")
			T.falsy(fs.isFile(Loader.root .. "/docs/art/shop_v3_concept/golems.js"), "no hand-drawn stickers left")
			-- not uploaded (Id 0): nothing in the game; a preview shows them unless told not to
			withStickers(0, function()
				for _, name in { "golem_DragonKing", "board_TerraForgeCustom" } do
					T.falsy(IconAssets.shopStickerShows(name), name .. ": the game before the upload")
					IconAssets.Previewing = true
					T.truthy(IconAssets.shopStickerShows(name), name .. ": a preview")
					local sheet = IconAssets.shopStickerSheet(name) :: any
					sheet.Preview = false
					T.falsy(IconAssets.shopStickerShows(name), name .. ": a preview of Studio before the upload")
					IconAssets.Previewing = false
				end
			end)
			-- uploaded: its cell of its image; a golem without a sticker never shows one
			withStickers(123, function()
				T.truthy(IconAssets.shopStickerShows("capsule_Dragonforge"))
				T.truthy(IconAssets.shopStickerShows("train"))
				T.falsy(IconAssets.shopStickerShows("golem_PebbleGolem"), "no sticker: never")
				for _, name in { "capsule_Dragonforge", "board_TerraForgeCustom" } do
					local sheet = IconAssets.shopStickerSheet(name) :: any
					local label = Instance.new("ImageLabel")
					IconAssets.applyShopSticker(label, name)
					local cell = IconAssets.shopStickerCell(name) :: number
					T.eq(label.Image, "rbxassetid://123")
					T.eq(label.ImageRectOffset, Vector2.new((cell % sheet.Columns) * sheet.Cell, (cell // sheet.Columns) * sheet.Cell))
					T.eq(label.ImageRectSize, Vector2.new(sheet.Cell, sheet.Cell))
					T.eq(label:GetAttribute("Icon"), "sticker_" .. name, "the previews' picture")
				end
			end)
		end
	)

	T.test("ShopFx: before the sticker upload the shop's golems and eggs stay live 3D; after it they are images, no 3D view", function()
		local StoreView = ui("StoreView")
		local function build(): any
			local refs = StoreView.build()
			StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
			StoreView.selectTab(refs, "Golems")
			StoreView.selectTab(refs, "Passes")
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
			T.eq(views(refs.Pages.Featured), 0, "the Featured tab: no 3D view (the Starter Pack's coins: an icon, its podium: a sticker)")
			T.eq(views(refs.Pages.Passes), 0, "the PASSES tab: no 3D view (the podium, the train, the hoverboard: stickers)")
			for _, id in { "Podiums", "Train", "CustomBoard" } do
				local picture = refs.Cards[id].Picture :: any
				T.truthy(picture:IsA("ImageLabel") and string.sub(picture:GetAttribute("Icon"), 1, 8) == "sticker_", id .. ": its sticker")
				T.eq(picture:GetAttribute("ShopFx"), "Idle", id .. ": it lives a little")
			end
			T.eq((refs.Cards.CustomBoard.Picture :: any):GetAttribute("Rise"), StoreView.HoverRise, "the hoverboard hovers higher")
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

	---------------------------------------------------------------- the motion v2 (owner 2026-11-12: "add more things")

	-- One of every new mark under a frame (the effects picture uploaded).
	local function markedV2(): any
		local root = Instance.new("Frame")
		local function picture(name: string, at: any): any
			local p = Instance.new("ImageLabel")
			p.Name = name
			p.Position = at
			p.Rotation = 0
			p.Parent = root
			return p
		end
		local idle1 = picture("Idle1", UDim2.fromOffset(100, 80))
		idle1:SetAttribute("ShopFx", "Idle")
		local idle2 = picture("Idle2", UDim2.fromOffset(200, 80))
		idle2:SetAttribute("ShopFx", "Idle")
		local hero = picture("Hero", UDim2.fromOffset(300, 90))
		hero:SetAttribute("ShopFx", "Float")
		hero:SetAttribute("Swing", 2.5)
		local egg = picture("Egg", UDim2.fromOffset(400, 90))
		egg.Rotation = -12
		egg:SetAttribute("ShopFx", "Float")
		egg:SetAttribute("Wobble", ShopFx.WobbleSwing)
		local glow = ShopFx.glow(root, UDim2.fromOffset(400, 90), 60, WHITE, 2, 0.9)
		glow:SetAttribute("ShopFx", "Glow")
		local sticker = ShopFx.sticker(root, "BEST VALUE!", "Gold", UDim2.fromOffset(50, 10), 14, -4)
		local cards = {}
		for i = 1, 4 do
			local holder = Instance.new("Frame")
			holder.Name = "Card" .. i
			holder.Parent = root
			table.insert(cards, ShopFx.sheen(holder, 18, 11))
		end
		local title = ShopFx.title(root, "SHOP", 56, { WHITE, WHITE, WHITE })
		local glint = ShopFx.glint(title)
		local mote = ShopFx.particle(root, "glow", UDim2.fromOffset(500, 300), 14, Vector2.new(10, -200), 3, WHITE, 0.1, 7)
		return {
			Root = root,
			Idle1 = idle1,
			Idle2 = idle2,
			Hero = hero,
			Egg = egg,
			Glow = glow,
			Sticker = sticker,
			Cards = cards,
			Glint = glint,
			Mote = mote,
		}
	end

	T.test("ShopFx v2: every new mark samples Roblox's curves (idle, rock, wobble, glow, wiggle, sheen, glint, rise)", function()
		withEffects(1, function()
			local m = markedV2()
			local kinds = byKind(ShopFx.loopsUnder({ m.Root }))
			-- idle: ONE tween moves the bob and the sway; the second one is slower and starts at the top
			T.eq(#kinds.Idle, 2, "two idle pictures")
			local a, b = kinds.Idle[1], kinds.Idle[2]
			T.eq(a.Property, "Position")
			T.truthy(a.Reverses and a.Style == "Sine")
			T.eq(#a.Also, 1, "its sway rides the same tween")
			T.eq(a.Also[1].Property, "Rotation")
			T.truthy(b.Time > a.Time, "never in step: the next one a little slower")
			T.eq(ShopFx.sample(a, 0), UDim2.fromOffset(100, 80), "the first from its place")
			T.eq(ShopFx.sample(b, 0), UDim2.fromOffset(200, 80 - ShopFx.IdleRise), "the second from the top")
			for t = 0, 6, 0.05 do
				local p = ShopFx.sample(a, t)
				T.truthy(p.Y.Offset <= 80 + 1e-9 and p.Y.Offset >= 80 - ShopFx.IdleRise - 1e-9, "a soft bob")
				local r = ShopFx.sample(a, t, "Rotation")
				T.truthy(math.abs(r) <= ShopFx.IdleSwing + 1e-9, `a small sway ({r})`)
			end
			T.near(ShopFx.sample(a, 0, "Rotation"), -ShopFx.IdleSwing, 1e-9)
			T.near(ShopFx.sample(a, a.Time, "Rotation"), ShopFx.IdleSwing, 1e-9, "it rocks as it bobs")
			T.eq(ShopFx.sample(a, 0, "Nope"), nil, "no such track")
			-- the dragon king floats and rocks (one tween); the egg floats, and wobbles now and then (two)
			local floats = kinds.Float
			T.eq(#floats, 2)
			local heroFloat = if floats[1].Target == m.Hero then floats[1] else floats[2]
			T.eq(heroFloat.Also[1].Property, "Rotation", "the hero rocks as it floats")
			T.near(ShopFx.sample(heroFloat, heroFloat.Time, "Rotation"), 2.5, 1e-9)
			T.eq(#kinds.Wobble, 1, "the egg's wobble")
			local wobble = kinds.Wobble[1]
			T.eq(wobble.Target, m.Egg)
			T.eq(wobble.Style, "Elastic")
			T.truthy(wobble.Reverses)
			T.near(ShopFx.sample(wobble, 0), -12, 1e-9, "from its tilt")
			T.near(ShopFx.sample(wobble, wobble.Time), -12 + ShopFx.WobbleSwing, 1e-9, "its peak")
			local still = 0
			local steps = 400
			for i = 0, steps - 1 do
				if math.abs(ShopFx.sample(wobble, i * 2 * wobble.Time / steps) + 12) < 0.5 then
					still += 1
				end
			end
			T.truthy(still / steps > 0.45 and still / steps < 0.8, `now and then: still {still / steps} of the time`)
			-- the glow breathes fainter and back
			local glow = kinds.Glow[1]
			T.eq(glow.Property, "ImageTransparency")
			T.near(ShopFx.sample(glow, 0), glow.Rest, 1e-9)
			T.near(ShopFx.sample(glow, glow.Time), math.min(1, glow.Rest + ShopFx.GlowFade), 1e-9)
			-- the sticker wiggles about its tilt
			local wiggle = kinds.Wiggle[1]
			T.eq(wiggle.Target, m.Sticker)
			T.eq(wiggle.Rest, -4)
			for t = 0, 3, 0.05 do
				T.truthy(math.abs(ShopFx.sample(wiggle, t) + 4) <= ShopFx.WiggleSwing + 1e-9, "a gentle wiggle")
			end
			-- the cards' gloss: the same round for all, each one later, always in that order (no drift)
			local sheens = kinds.Sheen
			T.eq(#sheens, 4)
			local function showing(loop: any, t: number): boolean
				local x = ShopFx.sample(loop, t).X
				return x > ShopFx.SweepFrom and x < ShopFx.SweepTo
			end
			local first: { number } = {}
			for i, loop in sheens do
				T.eq(loop.Time, ShopFx.SheenEvery, "one round for all")
				T.falsy(loop.Reverses)
				T.truthy(loop.From.X <= ShopFx.SweepFrom + 1e-5 and loop.To.X >= ShopFx.SweepTo - 1e-5, "the jump back is off the card")
				T.near(loop.Rest.X, ShopFx.SweepFrom, 1e-5, "at rest off the card (a Vector2: 32-bit)")
				for k = 0, 599 do
					if showing(loop, k * 0.01) then
						first[i] = k * 0.01
						break
					end
				end
				T.truthy(first[i] ~= nil, `card {i}'s band shows`)
				-- (every round the same: the band shows at the same moment of each)
				T.eq(showing(loop, first[i] + 0.02), showing(loop, first[i] + 0.02 + 3 * ShopFx.SheenEvery))
			end
			for i = 2, #sheens do
				T.near(first[i] - first[i - 1], ShopFx.SheenGap, 0.02, "one after another")
			end
			for k = 0, 599 do
				local at = 0
				for _, loop in sheens do
					if showing(loop, k * 0.01) then
						at += 1
					end
				end
				T.truthy(at < #sheens, "never all at once")
			end
			T.near(first[1], ShopFx.SheenLead, 0.02, "the first after the cards' pop-in")
			-- the title's light band: across in GlintCross every GlintEvery
			local glint = kinds.Glint[1]
			T.eq(glint.Target, m.Glint:FindFirstChild("Glint"))
			T.eq(glint.Time, ShopFx.GlintEvery)
			local lit = 0
			for k = 0, 449 do
				if showing(glint, k * 0.01) then
					lit += 1
				end
			end
			T.near(lit * 0.01, ShopFx.GlintCross, 0.03, "a quick sweep")
			-- a particle: a linear drift, clear at both ends (the jump back unseen), brightest half way
			local rise = kinds.Rise
			T.eq(#rise, 2, "its drift and its fade")
			local drift = if rise[1].Property == "Position" then rise[1] else rise[2]
			local fade = if rise[1].Property == "Position" then rise[2] else rise[1]
			T.eq(drift.Style, "Linear")
			T.falsy(drift.Reverses)
			T.eq(drift.Time, 3)
			T.eq(ShopFx.sample(drift, 1.5), UDim2.fromOffset(505, 200), "half way")
			T.near(fade.Time * 2, drift.Time, 1e-9, "the fade keeps step with the drift")
			for _, t in { 0, 3, 6, 2.97, 3.03, 5.97 } do
				T.truthy(ShopFx.sample(fade, t) > 0.99, `clear at the drift's ends ({t} s: {ShopFx.sample(fade, t)})`)
			end
			T.near(ShopFx.sample(fade, 1.5), 0.1, 1e-9, "brightest half way")
			-- a phone: no ambient ones (the particle, the cards' gloss)
			local lean = byKind(ShopFx.loopsUnder({ m.Root }, true))
			T.eq(lean.Rise, nil, "a phone: no particle")
			T.eq(lean.Sheen, nil, "a phone: no card gloss")
			T.eq(#lean.Idle, 2, "(the idles here are not ambient)")
		end)
	end)

	T.test("ShopFx v2: quiet keeps it all static at rest; stop puts the riding tracks back too", function()
		withEffects(1, function()
			local m = markedV2()
			local loops = ShopFx.loopsUnder({ m.Root })
			-- the built look is the rest look: nothing waits half way
			for _, loop in loops do
				local now = (loop.Target :: any)[loop.Property]
				T.truthy(
					now == loop.Rest or (type(now) == "number" and math.abs(now - loop.Rest) < 1e-6),
					`{loop.Kind} {loop.Property} built at rest`
				)
				for _, more in loop.Also or {} do
					T.eq((loop.Target :: any)[more.Property], more.Rest, loop.Kind .. " " .. more.Property .. " at rest")
				end
			end
			T.eq(m.Mote.ImageTransparency, 1, "a particle at rest: unseen")
			recording(function(made)
				local playing = ShopFx.play(loops)
				T.eq(#made, #loops, "one tween a loop")
				for _, record in made do
					if record.Instance == m.Idle1 then
						T.truthy(record.Goal.Position ~= nil and record.Goal.Rotation ~= nil, "the idle's one tween moves both")
					end
				end
				ShopFx.stop(playing)
				T.eq(m.Idle1.Position, UDim2.fromOffset(100, 80))
				T.eq(m.Idle1.Rotation, 0, "its sway back too")
				T.eq(m.Hero.Rotation, 0)
				T.eq(m.Egg.Rotation, -12)
				T.eq(m.Mote.ImageTransparency, 1)
				-- Reduce motion: no tween anywhere, the one-shots put everything at rest at once
				table.clear(made)
				Motion.setReduced(true)
				local ok, err = pcall(function()
					T.truthy(ShopFx.quiet())
					T.eq(#ShopFx.play(loops).Loops, 0)
					local holder = Instance.new("Frame")
					holder.AnchorPoint = Vector2.new(0.5, 0.5)
					holder.Size = UDim2.fromOffset(200, 250)
					local light = Instance.new("UIStroke")
					light.Transparency = 0.62
					light.Parent = holder
					ShopFx.hover(holder, true, false, { Lift = ShopFx.Lift, Light = light })
					T.eq(holder.AnchorPoint, Vector2.new(0.5, 0.5), "no lift")
					T.near(light.Transparency, 0.62, 1e-6, "no light")
					local title = Instance.new("TextLabel")
					title.Position = UDim2.fromOffset(84, 40)
					local tab = Instance.new("Frame")
					local x = Instance.new("Frame")
					x.Rotation = 4
					ShopFx.cascade({ Drops = { title }, Pops = { tab }, Spin = x })
					T.eq(title.Position, UDim2.fromOffset(84, 40))
					T.eq((tab :: any).Scale.Scale, 1)
					T.eq(x.Rotation, 4)
					ShopFx.popIcon(tab)
					T.eq((tab :: any).Pop.Scale, 1)
					T.eq(#ShopFx.celebrate(holder, 18, Instance.new("Frame"), UDim2.fromOffset(0, 0), "star"), 0, "no celebration")
					T.eq(#made, 0, "no tween at all")
				end)
				Motion.setReduced(false)
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	T.test("ShopFx v2: the header cascades in (under 0.3 s), the picked tab's icon pops, a hovered card rises and brightens", function()
		local StoreView = ui("StoreView")
		withEffects(1, function()
			recording(function(made)
				local refs = StoreView.build(nil, true)
				table.clear(made)
				StoreView.cascade(refs)
				local title = refs.Window.Title
				local drops, pops, spins = 0, {}, 0
				for _, record in made do
					T.truthy(record.Time + record.Delay <= 0.3 + 1e-9, "over by 0.3 s: " .. record.Instance.Name)
					T.eq(record.Style, "Back")
					if record.Goal.Position then
						drops += 1
						T.eq(record.Goal.Position, record.Instance:GetAttribute("BasePosition"), "it drops into its place")
					elseif record.Goal.Rotation then
						spins += 1
						T.eq(record.Goal.Rotation, 4, "the X spins back to its tilt")
					elseif record.Instance.Name == "Scale" then
						table.insert(pops, record.Delay)
					end
				end
				T.eq(drops, 3, "the title, its dark copy and its light band")
				T.eq(title.Position, (title :: any):GetAttribute("BasePosition") + UDim2.fromOffset(0, -ShopFx.CascadeDrop), "from above")
				T.eq(spins, 1, "the X spins in")
				T.eq(#pops, 1 + 6 + 1, "the basket, the six tabs, the X's scale")
				for i = 2, 7 do
					T.truthy(pops[i] > pops[i - 1], "the tabs one after another")
				end
				-- the picked tab's picture pops; the open tab's wiggles
				table.clear(made)
				StoreView.selectTab(refs, "Golems", true)
				local icon = refs.TabRefs.Golems.Icon
				local popped = false
				for _, record in made do
					if record.Instance.Name == "Pop" and record.Instance.Parent == icon then
						popped = record.Style == "Back" and record.Goal.Scale == 1
					end
				end
				T.truthy(popped, "the Golems icon pops")
				T.near((icon :: any).Pop.Scale, ShopFx.IconPopFrom, 1e-6)
				local wiggles = 0
				for _, loop in ShopFx.loopsUnder({ refs.TabRefs.Golems.Lift }) do
					if loop.Kind == "Wiggle" and loop.Target == icon then
						wiggles += 1
					end
				end
				T.eq(wiggles, 1, "the open tab's icon wiggles")
				-- a card under the mouse (or the gamepad's selection): 1.04, it rises, its light edge and glow brighten
				local card = refs.Cards.Royal5
				local holder = card.Holder
				local face = holder:FindFirstChild("Face") :: any
				local look = { Lift = ShopFx.Lift, Light = face.Rim.Light, Glow = face:FindFirstChild("Glow") }
				table.clear(made)
				ShopFx.hover(holder, true, false, look)
				local goals: { [string]: any } = {}
				for _, record in made do
					for property, value in record.Goal do
						goals[record.Instance.Name .. "." .. property] = value
					end
				end
				T.eq(goals["Scale.Scale"], ShopFx.Hover)
				local h = holder.Size.Y.Offset
				T.near(goals[holder.Name .. ".AnchorPoint"].Y, 0.5 + ShopFx.Lift / h, 1e-6, "it rises")
				T.eq(goals["Light.Transparency"], ShopFx.LightOn, "its light edge")
				T.truthy(goals["Glow.ImageTransparency"] < look.Glow.ImageTransparency, "its glow")
				-- away: all back; a touch (held, never hovered) only presses
				table.clear(made)
				ShopFx.hover(holder, false, false, look)
				for _, record in made do
					if record.Goal.AnchorPoint then
						T.eq(record.Goal.AnchorPoint, Vector2.new(0.5, 0.5), "down again")
					end
				end
				table.clear(made)
				ShopFx.hover(holder, false, true, look)
				for _, record in made do
					if record.Goal.Scale then
						T.eq(record.Goal.Scale, ShopFx.Press, "a touch presses")
					elseif record.Goal.AnchorPoint then
						T.eq(record.Goal.AnchorPoint, Vector2.new(0.5, 0.5), "a touch never lifts")
					end
				end
			end)
		end)
	end)

	T.test("ShopFx v2: a purchase from the shop flashes and pops its card and throws at most 12 stars, then clears them", function()
		local StoreView = ui("StoreView")
		withEffects(1, function()
			recording(function(made)
				local refs = StoreView.build(nil, true)
				StoreView.selectTab(refs, "Golems")
				local timers: { () -> () } = {}
				ShopFx.useDelays(function(_, fn)
					table.insert(timers, fn)
				end)
				table.clear(made)
				local ok, err = pcall(function()
					T.truthy(StoreView.celebrate(refs, "RoyalCapsule10"), "the x10 pack celebrates")
					local holder = refs.Cards.Royal10.Holder
					local scale = holder:FindFirstChild("Scale") :: any
					T.near(scale.Scale, ShopFx.CelebratePop, 1e-6, "it pops from 1.12")
					local pop, flash, prizes, fades = false, false, 0, 0
					for _, record in made do
						if record.Instance == scale and record.Goal.Scale == 1 then
							pop = true
						elseif record.Instance.Name == "Flash" and record.Goal.BackgroundTransparency == 1 then
							flash = true
						elseif record.Instance.Name == "Prize" then
							if record.Goal.ImageTransparency == 1 then
								fades += 1
							else
								prizes += 1
							end
						end
					end
					T.truthy(pop and flash, "a pop back to 1 and a flash")
					T.truthy(prizes > 0 and prizes <= 12, `stars fly out ({prizes})`)
					T.eq(fades, prizes, "and fade")
					local inFront = 0
					for _, d in refs.Front:GetChildren() do
						if d.Name == "Prize" then
							inFront += 1
							T.eq(d:GetAttribute("Icon"), "shop_star", "stars (coins for a coin pack)")
						end
					end
					T.eq(inFront, prizes, "over the window")
					T.eq(#timers, 1, "one clean-up")
					timers[1]()
					for _, d in refs.Front:GetChildren() do
						T.truthy(d.Name ~= "Prize", "the stars are gone")
					end
					T.eq(holder:FindFirstChild("Flash"), nil, "and the flash")
					-- a product not on the open page: nothing
					T.falsy(StoreView.celebrate(refs, "CoinsMega"), "the Cash tab isn't open")
				end)
				ShopFx.useDelays(nil)
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	-- (the budgets: PC at most about twice the motion it had, a phone a little more; the first open light)
	T.test("ShopFx v2: loop budgets per tab (PC <= 2x before, phone modest), first open <= 1,700, <= 8 particles a page", function()
		local StoreView = ui("StoreView")
		-- the window's and the open tab's loops before the motion v2 (2026-11-12, 9cb7536a)
		local before = {
			PC = { Featured = 35, Golems = 34, Blasters = 32, Passes = 28, Boosts = 37, Cash = 29 },
			Phone = { Featured = 25, Golems = 24, Blasters = 22, Passes = 18, Boosts = 27, Cash = 19 },
		}
		withEffects(IconAssets.ShopFx.Id, function()
			for _, lean in { false, true } do
				local refs = StoreView.build(if lean then StoreView.metricsFor(true, 1) else nil, true)
				StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
				if not lean then
					local first = #refs.Gui:GetDescendants()
					T.truthy(first <= 1700, `first open: {first} instances`)
				end
				local window = #ShopFx.loopsUnder(refs.Fx, lean)
				for _, section in StoreConfig.Sections do
					StoreView.selectTab(refs, section.Id)
					local page = refs.Pages[section.Id]
					local tab = #ShopFx.loopsUnder({ page, refs.TabRefs[section.Id].Lift }, lean)
					local was = (if lean then before.Phone else before.PC)[section.Id]
					local now = window + tab
					if lean then
						T.truthy(now <= was + 10, `phone {section.Id}: {now} loops (was {was})`)
					else
						T.truthy(now <= 2 * was, `PC {section.Id}: {now} loops (was {was})`)
						T.truthy(now > was, `PC {section.Id}: more life than before ({now} > {was})`)
					end
					T.truthy(count(page, function(d)
						return d.Name == "Mote"
					end) <= StoreView.MaxMotes, section.Id .. ": a few particles")
				end
			end
		end)
		-- the particles: Featured's embers, the Royal Egg's sparkles, the blaster's sparks, the coins; unseen at rest
		withEffects(1, function()
			local refs = StoreView.build()
			StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
			for _, section in { "Featured", "Golems", "Blasters", "Cash" } do
				local motes = 0
				for _, d in refs.Pages[section]:GetDescendants() do
					if d.Name == "Mote" then
						motes += 1
						T.eq(d:GetAttribute("ShopFx"), "Rise")
						T.truthy(d:GetAttribute("Ambient"), "a phone skips it")
						T.eq(d.ImageTransparency, 1, "unseen at rest")
					end
				end
				T.truthy(motes >= 4 and motes <= StoreView.MaxMotes, `{section}: {motes} particles`)
			end
		end)
	end)

	T.test("ShopFx v2: every golem and egg picture idles; the rare tiles shine, the Epic glows, MYTHIC runs a rainbow", function()
		local StoreView = ui("StoreView")
		withEffects(1, function()
			local refs = StoreView.build()
			StoreView.setEdition(refs, LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400) :: any)
			-- (the stickers or the live 3D models: the same pictures carry the marks)
			for _, d in refs.Gui:GetDescendants() do
				local icon = d:GetAttribute("Icon")
				local golem = type(icon) == "string"
					and (string.find(icon, "golem_", 1, true) ~= nil or string.find(icon, "capsule_", 1, true) ~= nil)
				if golem and d:IsA("ImageLabel") and not d:IsDescendantOf(refs.Window.Root:FindFirstChild("Tabs")) then
					local holder = d.Parent
					local mark = d:GetAttribute("ShopFx") or (holder and holder:GetAttribute("ShopFx"))
					T.truthy(mark == "Idle" or mark == "Float", "it lives: " .. d:GetFullName())
				end
			end
			local royal = refs.Royal :: any
			local egg = royal.Frame:FindFirstChild("Egg")
			T.eq(egg:GetAttribute("Wobble"), ShopFx.WobbleSwing, "the Royal Egg wobbles now and then")
			local shard = refs.Banner.Frame:FindFirstChild("Shard")
			T.truthy(shard:GetAttribute("Wobble"), "so does the Dragonforge shard")
			local glows = 0
			for _, d in royal.Frame:GetDescendants() do
				if d:GetAttribute("ShopFx") == "Glow" then
					glows += 1
				end
			end
			T.eq(glows, 2, "the egg's glow and the Epic's")
			local function tile(id: string): any
				return royal.Frame:FindFirstChild("Golem" .. id)
			end
			local turning = {}
			for _, d in royal.Frame:GetDescendants() do
				if
					d.Name == "Rays"
					and d:GetAttribute("ShopFx") == "Rays"
					and d.Parent
					and d.Parent.Parent
					and d.Parent.Parent ~= royal.Frame
				then
					turning[d.Parent.Parent.Name] = true
				end
			end
			T.truthy(turning.GolemStormTitan and turning.GolemCelestialSovereign, "the Legendary's and the Mythic's rays turn")
			T.falsy(turning.GolemSilverSquire or turning.GolemRoseKnight or turning.GolemMoonstoneOracle, "the others' stay still")
			for _, id in { "StormTitan", "CelestialSovereign" } do
				local sparkles = 0
				for _, d in tile(id):GetChildren() do
					if d.Name == "Sparkle" and d:GetAttribute("ShopFx") == "Sparkle" then
						sparkles += 1
					end
				end
				T.eq(sparkles, 2, id .. ": two sparkles")
			end
			local word = tile("CelestialSovereign"):FindFirstChild("Rarity")
			local rainbow = word:FindFirstChild("Rainbow")
			T.truthy(rainbow and rainbow:GetAttribute("ShopFx") == "Rim", "MYTHIC in a running rainbow")
			-- the counts x3 / x5 / x10 and the stickers wiggle; x1 stays
			for _, id in { "Royal3", "Royal5", "Royal10" } do
				T.eq(refs.Cards[id].Holder:FindFirstChild("Count"):GetAttribute("ShopFx"), "Wiggle", id)
			end
			T.eq(refs.Cards.Royal1.Holder:FindFirstChild("Count"):GetAttribute("ShopFx"), nil, "x1")
			T.eq(refs.Cards.Royal10.Sticker:GetAttribute("ShopFx"), "Wiggle", "BEST VALUE!")
			-- every card wears a gloss band (off the card at rest)
			for _, card in refs.Cards do
				local sheen = card.Holder:FindFirstChild("Sheen") :: any
				T.truthy(sheen and sheen.Sweep:GetAttribute("ShopFx") == "Sheen", card.Spec.Id .. "'s gloss")
				T.near(sheen.Sweep.Offset.X, ShopFx.SweepFrom, 1e-5)
			end
		end)
	end)
end
