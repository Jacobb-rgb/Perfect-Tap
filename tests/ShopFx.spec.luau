-- The shop v3 "WOW" look (owner 2026-11-11) under Lune: ShopFx's pure timing (the 2 s loop:
-- rays turn, bolts flash, the shine sweeps, the open tab bobs, the Mythic rim runs), its
-- seeded bolts, the motion driver's steps and rest, the shop icon sheet against the concept's
-- icons.js, the 3D models built only for the page that shows, and a sane instance count.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local Instance = roblox.Instance
	local function ui(name: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local ShopFx = ui("ShopFx")
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")

	T.test("ShopFx: the 2 s loop's timing (rays, bolts, shine, bob, rim, sparkles)", function()
		T.near(ShopFx.rayAngle(0, 10), 10, 1e-9, "the rays start where they were built")
		T.near(ShopFx.rayAngle(1, 10), 10 + ShopFx.RaySpeed, 1e-9, "and turn RaySpeed a second")
		T.truthy(ShopFx.rayAngle(100, 0) >= 0 and ShopFx.rayAngle(100, 0) < 360, "a turn wraps")
		-- two quick flashes a second, then dark
		T.truthy(ShopFx.boltOn(0.05))
		T.falsy(ShopFx.boltOn(0.12))
		T.truthy(ShopFx.boltOn(0.18))
		T.falsy(ShopFx.boltOn(0.5))
		T.truthy(ShopFx.boltOn(1.05), "every second")
		T.truthy(ShopFx.boltOn(0.6, 0.43), "a phase moves its flash")
		-- the shine: off the button at the loop's start and end, across it in between
		T.truthy(ShopFx.shineOffset(0) < -0.6, "off the left")
		T.truthy(math.abs(ShopFx.shineOffset(0.75)) < 0.6, "on the button")
		T.truthy(ShopFx.shineOffset(1.99) > 0.6, "off the right")
		T.near(ShopFx.shineOffset(0.4), ShopFx.shineOffset(0.4 + ShopFx.Loop), 1e-9, "a 2 s loop")
		for t = 0, 4, 0.1 do
			T.truthy(math.abs(ShopFx.bob(t)) <= 3 + 1e-9, "the tab bobs 3 units at most")
			local s = ShopFx.sparkleScale(t, 2)
			T.truthy(s >= 0.45 - 1e-9 and s <= 1 + 1e-9, "a sparkle pulses 0.45 .. 1")
			local r = ShopFx.rimAngle(t)
			T.truthy(r >= 0 and r < 360, "the rim's turn wraps")
		end
		T.near(ShopFx.rimAngle(2) - ShopFx.rimAngle(0), 0, 1e-9, "the rim runs a full turn every 2 s")
	end)

	T.test("ShopFx: bolts are seeded (the same bolt every time) and end where they're aimed", function()
		local a, b = Vector2.new(0, 0), Vector2.new(300, 100)
		local p1 = ShopFx.boltPoints(a, b, 120, 4, ShopFx.random(7))
		local p2 = ShopFx.boltPoints(a, b, 120, 4, ShopFx.random(7))
		T.eq(#p1, 2 ^ 4 + 1, "2^depth segments")
		T.eq(p1[1], a)
		T.eq(p1[#p1], b)
		for i, p in p1 do
			T.near(p.X, p2[i].X, 1e-9)
			T.near(p.Y, p2[i].Y, 1e-9)
		end
		local rand = ShopFx.random(3)
		for _ = 1, 200 do
			local x = rand()
			T.truthy(x >= 0 and x < 1, "random in [0, 1)")
		end
		-- a bolt's frames: the main line's segments and its forks
		local parent = Instance.new("Frame")
		local bolt = ShopFx.bolt(parent, a, b, roblox.Color3.new(1, 1, 0), 4, 5, 2, 3, 0.3, 3, false)
		T.eq(bolt:GetAttribute("ShopFx"), "Bolt")
		T.eq(bolt:GetAttribute("Phase"), 0.3)
		local segs = 0
		for _, d in bolt:GetChildren() do
			if d.Name == "Seg" then
				segs += 1
			end
			T.truthy(d.Name ~= "Haze", "no haze when asked for none")
		end
		T.eq(segs, 2 ^ 3 + 2 * 2 ^ 2, "8 main segments and two forks of 4")
	end)

	T.test("ShopFx: the motion driver moves its marks and puts them at rest", function()
		local window = Instance.new("Frame")
		local page = Instance.new("Frame")
		local rays = ShopFx.rays(window, roblox.UDim2.fromScale(0.5, 0.5), 6, 100, 0.6, 2)
		local bolt = ShopFx.bolt(window, Vector2.new(0, 0), Vector2.new(100, 100), roblox.Color3.new(1, 1, 1), 3, 1, 0, 2, 0, 3, false)
		local price = ShopFx.priceButton(page, 99, Vector2.new(160, 50), "Green")
		local sweep = (price.Face :: any).Shine.Sweep
		local sparkle = ShopFx.sparkle(window, roblox.UDim2.fromOffset(10, 10), 20, roblox.Color3.new(1, 1, 1), 3, 1)
		local tab = Instance.new("Frame")
		local driver = ShopFx.start({ window }, page, tab, nil)
		driver.step(0.12)
		T.near(rays.Rotation, ShopFx.rayAngle(0.12, 0), 1e-6, "the rays turned")
		T.falsy(bolt.Visible, "the bolt is dark between its flashes")
		T.near(sweep.Offset.X, ShopFx.shineOffset(0.12), 1e-6, "the shine moved")
		T.eq(tab.Position.Y.Offset, math.floor(ShopFx.bob(0.12) + 0.5), "the open tab bobbed")
		T.near((sparkle :: any).Pulse.Scale, ShopFx.sparkleScale(0.12, 1), 1e-6, "the sparkle pulsed")
		driver.step(0.5)
		T.eq(tab.Position.Y.Offset, 3, "up to 3 units")
		-- another page: the old one's shine rests, the new one's moves
		local other = Instance.new("Frame")
		local second = ShopFx.priceButton(other, 49, Vector2.new(160, 50), "Gold")
		local secondSweep = (second.Face :: any).Shine.Sweep
		driver.focus(other, nil)
		T.near(sweep.Offset.X, ShopFx.shineOffset(0), 1e-6, "the old page's shine rests")
		T.near(tab.Position.Y.Offset, 0, 1e-6, "the old tab is back")
		driver.step(0.8)
		T.near(secondSweep.Offset.X, ShopFx.shineOffset(0.8), 1e-6, "the new page's shine moves")
		T.near(sweep.Offset.X, ShopFx.shineOffset(0), 1e-6, "the old one stays")
		driver.stop()
		T.truthy(bolt.Visible, "stopped: the bolts stay lit")
		T.near(secondSweep.Offset.X, ShopFx.shineOffset(0), 1e-6, "stopped: the shine is off the button")
		T.near((sparkle :: any).Pulse.Scale, 1, 1e-6)
		T.falsy(driver.running(), "no connection after stop")
	end)

	T.test("ShopFx: the shop icon sheet matches the concept's icons, one cell each, under 1024 px", function()
		local fs = require("@lune/fs")
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
		for _, name in { "basket", "lock", "clock", "bolt" } do
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
		local id = sheet.Id
		sheet.Id = 123
		IconAssets.applyShop(label, "egg")
		sheet.Id = id
		local cell = IconAssets.shopCell("egg") :: number
		T.eq(label.Image, "rbxassetid://123")
		T.eq(label.ImageRectOffset, Vector2.new((cell % sheet.Columns) * sheet.Cell, (cell // sheet.Columns) * sheet.Cell))
		T.eq(label.ImageRectSize, Vector2.new(sheet.Cell, sheet.Cell))
	end)

	T.test("ShopFx: the shop builds only the open tab's 3D models, and stays a sane size", function()
		local StoreView = ui("StoreView")
		local refs = StoreView.build()
		local function waiting(page: any): number
			local n = 0
			for _, d in page:GetDescendants() do
				if d:GetAttribute("Model") ~= nil then
					n += 1
				end
			end
			return n
		end
		T.eq(waiting(refs.Pages[refs.Current]), 0, "the open tab's models are built")
		T.truthy(waiting(refs.Pages.Golems) > 0, "the Golems tab's wait for it")
		StoreView.selectTab(refs, "Golems")
		T.eq(waiting(refs.Pages.Golems), 0, "shown: built")
		local parts = 0
		for _, d in refs.Pages.Golems:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		T.truthy(parts > 0, "the golems and eggs are live models")
		-- (shop v3 is about twice the old window; its effects never grow without a look at this)
		local fresh = StoreView.build()
		local count = #fresh.Gui:GetDescendants()
		T.truthy(count < 8000, `instances at the first open: {count}`)
	end)
end
