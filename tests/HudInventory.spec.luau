--[[
	The owner's HUD of 2026-11-11 (round look, light UI):
	  stickers   the right side's offers and the boost corner show the shop's sticker icons
	             (IconAssets.Shop), the same the shop shows for the same products; the old
	             pictures stay the fallback while that sheet isn't there
	  one        no Inventory tile on the left ("so we don't have two inventories"): eight tiles,
	  inventory  a full block (his pick A: two a row and four rows on a PC and a TV, four a row
	             on touch); the bottom button is the Inventory and opens the window
	  GOLD       his hotbar pick (obrazky/hud_inventar_2026-11-11/06_*): a blue and a gold rim
	  hotbar     round a green striped face, the sticker backpack a touch above the middle and
	             clear of the count and the bar, the count in gold letters, the bar of the
	             load (red while full), the white Q; the BLASTER slot in gold; the motion
	             (bounce, drifting stripes) only by tweens and never with Reduce motion
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Vector2, Color3 = roblox.Vector2, roblox.Color3
	local function ui(name: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local HudBubble = ui("HudBubble")
	local HudView = ui("HudView")
	local BoostView = ui("BoostView")
	local Motion = ui("Motion")

	-- the round look with the light UI (put back afterwards)
	local function inRound(fn: () -> ())
		local look, light = PopTheme.Look, UIConfig.LightUI
		PopTheme.setLook("Round")
		UIConfig.LightUI = true
		local ok, err = pcall(fn)
		PopTheme.setLook(look)
		UIConfig.LightUI = light
		if not ok then
			error(err, 0)
		end
	end

	-- the shop's sheet not there (and no previews drawing it): the old pictures
	local function withoutSheet(fn: () -> ())
		local id, previewing = IconAssets.Shop.Id, IconAssets.Previewing
		IconAssets.Shop.Id = 0
		IconAssets.Previewing = false
		local ok, err = pcall(fn)
		IconAssets.Shop.Id, IconAssets.Previewing = id, previewing
		if not ok then
			error(err, 0)
		end
	end

	-- a sheet cell's offset, as IconAssets.applyShop cuts it
	local function cell(name: string): any
		local index = IconAssets.shopCell(name) :: number
		local sheet = IconAssets.Shop
		return Vector2.new((index % sheet.Columns) * sheet.Cell, (index // sheet.Columns) * sheet.Cell)
	end

	local function overlap(a: { number }, b: { number }): boolean
		return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
	end

	---------------------------------------------------------------- the stickers

	T.test("HudInventory: the offers and the boost chips name the shop's stickers for the same products", function()
		local want = { StarterPack = "gift", DoubleMoney = "cash", TripleLucky15 = "clover_gold" }
		T.eq(#HudBubble.Offers, 3, "three offers")
		for _, offer in HudBubble.Offers do
			T.eq(offer.Sheet, want[offer.Card], offer.Card .. "'s sticker")
			T.truthy(IconAssets.shopCell(offer.Sheet) ~= nil, offer.Card .. ": in the shop's sheet")
			-- (the shop shows the same picture on the same product's card; its Starter Pack card shows slots)
			local card = StoreConfig.ById[offer.Card]
			T.truthy(card, offer.Card .. ": a Store card")
			if card.Sheet then
				T.eq(offer.Sheet, card.Sheet, offer.Card .. ": the shop's own picture")
			end
		end
		T.eq(HudBubble.Offers[2].Badge, "x2", "2x Money wears the x2 badge, as on the shop's card")
		T.truthy(IconAssets.shopCell("x2") ~= nil, "the x2 sticker is in the sheet")
		-- the running boosts: the shop's Triple / Hexa Lucky pictures; Server Luck's is the plain clover
		T.eq(BoostView.Stickers.TripleLucky, StoreConfig.ById.TripleLucky15.Sheet, "Triple Lucky")
		T.eq(BoostView.Stickers.TripleLucky, "clover_gold")
		T.eq(BoostView.Stickers.HexaLucky, StoreConfig.ById.HexaLucky15.Sheet, "Hexa Lucky")
		T.eq(BoostView.Stickers.HexaLucky, "clover_rainbow")
		T.eq(StoreConfig.ById.ServerLuck.Sheet, "clover", "Server Luck: the clover")
		local Boost = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
		for _, kindId in Boost.KindIds do
			T.truthy(BoostView.Stickers[kindId], kindId .. ": a sticker for every boost kind")
		end
	end)

	T.test("HudInventory: the offers show the stickers once the sheet is up, the old pictures until then", function()
		inRound(function()
			T.truthy(IconAssets.Shop.Id > 0, "the owner's sheet is uploaded")
			local refs = HudBubble.buildGame(1, 1280, false, false, 720 - 58) :: any
			local offers = refs.Gui:FindFirstChild("Offers")
			T.truthy(offers, "the offers on a PC")
			for _, offer in HudBubble.Offers do
				local button = offers:FindFirstChild(offer.Card):FindFirstChild("Offer")
				T.eq(button.Image, "rbxassetid://" .. tostring(IconAssets.Shop.Id), offer.Card .. ": the shop's sheet")
				T.eq(button.ImageRectOffset, cell(offer.Sheet), offer.Card .. ": its cell")
				T.eq(button:GetAttribute("Icon"), "shop_" .. offer.Sheet, offer.Card .. ": the previews draw the same")
				T.falsy(button:FindFirstChild("Picture"), offer.Card .. ": no old 3D picture under it")
				local badge = button:FindFirstChild("Badge")
				if offer.Badge then
					T.truthy(badge, offer.Card .. ": its badge")
					T.eq(badge.ImageRectOffset, cell(offer.Badge), offer.Card .. ": the x2 cell")
					-- (the price is tilted over the top-right corner: the badge takes the top-left)
					T.truthy(badge.Position.X.Scale < 0.5 and badge.Position.Y.Scale < 0.5, offer.Card .. ": top-left")
				else
					T.falsy(badge, offer.Card .. ": no badge")
				end
				T.truthy(button:FindFirstChild("Price"), offer.Card .. ": the price stays")
			end
			refs.Gui:Destroy()
			withoutSheet(function()
				local old = HudBubble.buildGame(1, 1280, false, false, 720 - 58) :: any
				for _, offer in HudBubble.Offers do
					local button = old.Gui:FindFirstChild("Offers"):FindFirstChild(offer.Card):FindFirstChild("Offer")
					T.truthy(button:FindFirstChild("Picture"), offer.Card .. ": the old live picture without the sheet")
					T.falsy(button:FindFirstChild("Badge"), offer.Card .. ": no badge without the sheet")
				end
				old.Gui:Destroy()
			end)
		end)
	end)

	T.test("HudInventory: the boost corner tiles show the boosts' stickers, the drawn clover without the sheet", function()
		inRound(function()
			local chips = BoostView.buildChips()
			for kindId, sheet in BoostView.Stickers do
				local art = chips.Chips[kindId]:FindFirstChild("Pill"):FindFirstChild("Dot"):FindFirstChild("Art")
				T.truthy(art and art:IsA("ImageLabel"), kindId .. ": the sticker")
				T.eq(art.ImageRectOffset, cell(sheet), kindId .. ": its cell")
				T.eq(art:GetAttribute("Icon"), "shop_" .. sheet)
			end
			withoutSheet(function()
				local old = BoostView.buildChips()
				local art = old.Chips.TripleLucky:FindFirstChild("Pill"):FindFirstChild("Dot"):FindFirstChild("Art")
				T.truthy(art and art:IsA("Frame"), "the drawn clover without the sheet")
			end)
		end)
	end)

	---------------------------------------------------------------- one Inventory, the left block

	T.test("HudInventory: no Inventory tile on the left; eight tiles on every screen", function()
		for _, entry in HudBubble.RoundMenu do
			T.truthy(entry.Id ~= "Backpack" and entry.Label ~= "Inventory", "no Inventory tile: " .. entry.Id)
		end
		local ids = {}
		for _, entry in HudBubble.RoundMenu do
			table.insert(ids, entry.Id)
		end
		T.eq(table.concat(ids, ","), "Store,Rebirth,Golems,Ride,Build,Elevator,Trade,More", "the owner's eight, in order")
		for _, touch in { false, true } do
			local layout = HudBubble.layout(1, 1280, touch, false, 662)
			T.eq(HudBubble.roundCount(layout), 8, (if touch then "touch" else "a mouse") .. ": eight (Trade on touch too)")
		end
		-- nobody claims the old tile any more
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/BackpackController.luau")
		T.falsy(source:find('claimTile(menu, "Backpack")', 1, true), "BackpackController claims no tile")
	end)

	T.test("HudInventory: a full block wins (pure): fullRows, columnOrder, pickColumns", function()
		T.truthy(HudBubble.fullRows(8, 2) and HudBubble.fullRows(8, 4), "8: two and four a row fill every row")
		T.falsy(HudBubble.fullRows(8, 3) or HudBubble.fullRows(8, 5) or HudBubble.fullRows(8, 6), "8: three, five, six leave a hole")
		T.eq(table.concat(HudBubble.columnOrder(8, { 6, 5, 4 }), ","), "4,6,5", "touch: four a row first")
		T.eq(table.concat(HudBubble.columnOrder(8, { 2, 3, 4, 5 }), ","), "2,4,3,5", "a mouse: two, then four")
		T.eq(table.concat(HudBubble.columnOrder(7, { 6, 5, 4 }), ","), "6,5,4", "no full block: the old order")
		-- two a row wins while as big (or nearly), four a row when two are much smaller, else the biggest
		T.eq(HudBubble.pickColumns(8, { { 2, 78 }, { 3, 78 }, { 4, 78 } })[1], 2, "all at the cap: two a row")
		T.eq(HudBubble.pickColumns(8, { { 2, 79 }, { 3, 80 }, { 4, 80 } })[1], 2, "two a row a unit smaller: still two")
		T.eq(HudBubble.pickColumns(8, { { 3, 64 }, { 4, 80 }, { 5, 80 } })[1], 4, "two can't: four a row")
		T.eq(HudBubble.pickColumns(8, { { 2, 58 }, { 3, 80 }, { 4, 59 } })[1], 3, "no full block near the biggest: the biggest")
		T.eq(HudBubble.pickColumns(8, {}), nil, "no tries")
	end)

	-- (owner 2026-11-11, pick A: "no hole", two a row and four rows, the tiles big; touch: four a row)
	T.test("HudInventory: his pick A on every screen: two a row and four rows at 78, four a row on touch", function()
		inRound(function()
			-- { width, height, touch, TV, a row, the tile }
			for _, case in
				{
					{ 1402, 683, false, false, 2, 78 }, -- his Studio window
					{ 1402, 490, false, false, 2, 80 }, -- with the Output open (Compact: RoundMouseTile)
					{ 1280, 720, false, false, 2, 78 },
					{ 1366, 768, false, false, 2, 78 },
					{ 1920, 1080, false, false, 2, 78 },
					{ 1920, 1080, false, true, 2, 78 }, -- a TV
					{ 1402, 368, false, false, 4, 80 }, -- too short for four rows: a 4 x 2 block
					{ 844, 390, true, false, 4, 72 },
					{ 667, 375, true, false, 4, 72 },
					{ 568, 320, true, false, 4, 72 },
					{ 1024, 768, true, false, 4, 58 }, -- a tablet
				}
			do
				local touch, tv = case[3] == true, case[4] == true
				local where = `{case[1]} x {case[2]}{if touch then " (touch)" elseif tv then " (TV)" else ""}`
				local scale = HudBubble.scaleFor(Vector2.new(case[1], case[2]))
				local layout = HudBubble.layout(scale, case[1], touch, tv, case[2] - 58)
				T.eq(layout.Columns, case[5], where .. ": a row")
				T.eq(layout.Tile, case[6], where .. ": the tile")
				T.truthy(HudBubble.fullRows(HudBubble.roundCount(layout), layout.Columns), where .. ": a full block")
				if touch then
					T.truthy(layout.Tile * scale >= 44 - 0.5, where .. ": 44 pt")
				end
			end
		end)
	end)

	---------------------------------------------------------------- the GOLD hotbar

	-- a rect { left, top, right, bottom } of `object` in its parent `w` x `h` (offset sizes)
	local function rect(object: any, w: number, h: number): { number }
		local sx = object.Size.X.Scale * w + object.Size.X.Offset
		local sy = object.Size.Y.Scale * h + object.Size.Y.Offset
		local x = object.Position.X.Scale * w + object.Position.X.Offset - object.AnchorPoint.X * sx
		local y = object.Position.Y.Scale * h + object.Position.Y.Offset - object.AnchorPoint.Y * sy
		return { x, y, x + sx, y + sy }
	end

	T.test("HudInventory: the GOLD Inventory: rims, stripes, the backpack a touch above the middle, clear of the count", function()
		inRound(function()
			for _, compact in { false, true } do
				local scale = if compact then 0.62 else 1
				local refs = HudBubble.buildGame(scale, if compact then 844 else 1280, compact, false, if compact then 332 else 662) :: any
				local where = if compact then "phone" else "PC"
				local button, slot = refs.Backpack, refs.BlasterSlot
				local size = HudBubble.carryPackSize(compact)
				T.eq(size, if compact then HudBubble.InventorySizePhone else HudBubble.InventorySize, where .. ": the Inventory's size")
				local w, h = size.X, size.Y
				T.eq(button.Size.X.Offset, w, where .. ": the Inventory's width")
				T.eq(button.Size.Y.Offset, h, where .. ": its height")
				T.eq(slot.Size.Y.Offset, h, where .. ": the slot as tall")
				T.truthy(w / h >= 3, where .. ": a lying rectangle")
				T.truthy(h * scale >= 44, where .. ": 44 pt to tap")
				T.truthy(button.Selectable, where .. ": a gamepad selects it")
				T.eq(button:GetAttribute("Gold"), "Inventory", where .. ": the GOLD look")
				T.eq(slot:GetAttribute("Gold"), "Blaster", where .. ": the slot too")
				-- the pieces, outside in
				T.truthy(button:FindFirstChild("Border"), where .. ": the dark outline")
				T.truthy(button:FindFirstChild("Paint"), where .. ": the blue rim")
				local gold = button:FindFirstChild("Gold")
				local green = button:FindFirstChild("Green")
				T.truthy(gold and green, where .. ": the gold rim and the green face")
				T.truthy(green:FindFirstChild("Stripes") and green:FindFirstChild("Gloss"), where .. ": stripes and the gloss")
				T.truthy(green:FindFirstChild("Lattice"):FindFirstChild("Gleam"), where .. ": the shine that sweeps across")
				T.truthy(#green:FindFirstChild("Stripes"):GetChildren() >= 3, where .. ": enough stripe bands")
				T.truthy(
					refs.CarryPanel:FindFirstChild("BackpackGlow") and refs.CarryPanel:FindFirstChild("BackpackSlab"),
					where .. ": glow and slab"
				)
				T.truthy(
					refs.CarryPanel:FindFirstChild("BlasterGlow") and refs.CarryPanel:FindFirstChild("BlasterSlab"),
					where .. ": the slot's"
				)
				T.truthy(button:FindFirstChild("Star"), where .. ": the gold star")
				T.truthy(button:FindFirstChild("Sparkle"), where .. ": a sparkle")
				-- the sticker backpack: the shop's, its bag (56 % x 73 % of the square, a touch low in it)
				local pack = button:FindFirstChild("Pack")
				local icon = pack:FindFirstChild("Icon")
				T.eq(icon:GetAttribute("Icon"), "shop_backpack", where .. ": the newer backpack")
				T.eq(icon.ImageRectOffset, cell("backpack"), where .. ": its cell")
				local box = rect(pack, w, h)
				local side = box[3] - box[1]
				local bag = {
					box[1] + side * 56 / 256,
					box[2] + side * 36 / 256,
					box[1] + side * 200 / 256,
					box[2] + side * 224 / 256,
				}
				local k = h / 64
				local rims = (HudBubble.GoldSizes.Blue + HudBubble.GoldSizes.Gold) * k
				T.truthy(bag[2] >= rims - 1 and bag[2] <= rims + 3 * k, `{where}: the bag's top just inside the rims ({bag[2]})`)
				T.truthy((bag[2] + bag[4]) / 2 < h / 2, where .. ": its middle a touch above the button's")
				T.truthy(bag[4] - bag[2] >= 0.72 * h, where .. ": a bit bigger (the bag 3/4 of the height)")
				local count = button:FindFirstChild("Count")
				local bar = button:FindFirstChild("Bar")
				T.falsy(overlap(bag, rect(count, w, h)), where .. ": the bag clear of the count")
				T.falsy(overlap(bag, rect(bar, w, h)), where .. ": and of the bar")
				T.truthy(rect(count, w, h)[4] <= rect(bar, w, h)[2] - HudBubble.GoldSizes.BarEdge * k, where .. ": the count above the bar")
				-- the count's gold letters, readable (13 pt at least on a phone)
				local letters = count:FindFirstChild("Gold")
				T.truthy(letters and letters:IsA("UIGradient") and letters.Enabled, where .. ": gold letters")
				T.truthy(count.Size.Y.Offset * scale >= 18, where .. ": the count's box tall enough")
				local fit = count:FindFirstChildOfClass("UITextSizeConstraint")
				T.truthy(fit.MaxTextSize * scale >= 17, where .. ": big letters")
				-- the white Q keycap on the top-right corner
				local key = button:FindFirstChild("Key")
				T.eq(key.Position.X.Scale, 1, where .. ": Q top-right")
				T.eq(key.BackgroundColor3, Color3.new(1, 1, 1), where .. ": a white cap")
				refs.Gui:Destroy()
			end
		end)
	end)

	T.test("HudInventory: the bar shows the load, turns red with FULL, and goes back", function()
		T.eq(HudBubble.fillShare(3, 5), 0.6)
		T.eq(HudBubble.fillShare(9, 5), 1, "over the capacity: full")
		T.eq(HudBubble.fillShare(0 / 0, 5), 0, "junk reads 0")
		T.eq(HudBubble.fillShare(2, 0), 0, "no capacity")
		inRound(function()
			local refs = HudBubble.buildGame(1, 1280, false, false, 662) :: any
			local button = refs.Backpack
			local fill = button:FindFirstChild("Bar"):FindFirstChild("Fill")
			local paint = fill:FindFirstChild("Paint")
			local before = #button:GetDescendants()
			HudView.setBackpack(refs, 0, 5)
			T.falsy(fill.Visible, "empty: no fill")
			HudView.setBackpack(refs, 3, 5)
			T.truthy(fill.Visible and math.abs(fill.Size.X.Scale - 0.6) < 1e-6, "3 / 5: 60 %")
			T.eq(paint.Color.Keypoints[1].Value, HudBubble.Gold.Fill[1], "a gold fill")
			T.eq(button:FindFirstChild("CountShadow").Text, "3 / 5", "the count's dark copy follows")
			HudView.setBackpack(refs, 5, 5)
			T.truthy(button:FindFirstChild("Full").Visible, "FULL")
			T.eq(paint.Color.Keypoints[2].Value, HudBubble.Gold.FillFull[2], "a red fill")
			T.eq(refs.CarryLabel.TextColor3, HudBubble.FullColor, "a red count")
			T.falsy(refs.CarryLabel:FindFirstChild("Gold").Enabled, "no gold letters while full")
			T.falsy(button:FindFirstChild("Star").Visible, "the star steps aside for FULL")
			HudView.setBackpack(refs, 4, 5)
			T.falsy(button:FindFirstChild("Full").Visible, "not full again")
			T.eq(paint.Color.Keypoints[1].Value, HudBubble.Gold.Fill[1], "gold again")
			T.truthy(refs.CarryLabel:FindFirstChild("Gold").Enabled and button:FindFirstChild("Star").Visible, "gold letters, the star")
			T.eq(#button:GetDescendants(), before, "updated in place")
			refs.Gui:Destroy()
		end)
	end)

	T.test("HudInventory: the GOLD slot keeps its gold middle and light ring after the Blaster is put away", function()
		inRound(function()
			local refs = HudBubble.buildGame(1, 1280, false, false, 662) :: any
			local slot = refs.BlasterSlot
			local disc = slot:FindFirstChild("Disc")
			local light = slot:FindFirstChild("Rim"):FindFirstChild("Light")
			T.eq(disc.BackgroundColor3, HudBubble.GoldDisc, "the gold slot's light middle")
			T.truthy(slot:FindFirstChild("Stripes") and slot:FindFirstChild("Gloss"), "stripes and gloss on the slot too")
			local restWidth = light.Thickness
			HudView.setBlasterEquipped(refs, true)
			T.eq(disc.BackgroundColor3, HudBubble.EquippedColor, "in hand: gold")
			T.truthy(slot:FindFirstChild("Equipped").Visible, "the ring in hand")
			HudView.setBlasterEquipped(refs, false)
			T.eq(disc.BackgroundColor3, HudBubble.GoldDisc, "put away: its own middle again")
			T.eq(light.Color, Color3.new(1, 1, 1), "its white ring again")
			T.eq(light.Thickness, restWidth, "as wide as before")
			-- the key cap stays dark on the slot (the "1"), top-left
			T.eq(slot:FindFirstChild("Key").Position.X.Scale, 0, "the 1 top-left")
			refs.Gui:Destroy()
		end)
	end)

	T.test("HudInventory: the hotbar's motion is tweens only and stops with Reduce motion", function()
		-- Motion tells its hooks when Reduce motion turns on or off
		local heard = {}
		Motion.onReducedChanged(function(on: boolean)
			table.insert(heard, on)
		end)
		local was = Motion.reduced()
		Motion.setReduced(not was)
		Motion.setReduced(was)
		T.eq(#heard >= 2 and heard[#heard - 1], not was, "turned on: heard")
		T.eq(heard[#heard], was, "turned off: heard")
		-- HudController: the bounce and the drift (read as text: it needs the player when it loads)
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/HudController.luau")
		local bounce = source:match("\nlocal function bounceBackpack%(%)(.-)\nend\n")
		T.truthy(bounce and bounce:find("Motion.reduced()", 1, true), "no bounce with Reduce motion")
		T.truthy(bounce and bounce:find("TweenService:Create", 1, true), "the bounce is a tween")
		local drift = source:match("\nlocal function syncDrift%(%)(.-)\nend\n")
		T.truthy(drift and drift:find("not Motion.reduced()", 1, true), "the stripes stop with Reduce motion")
		T.truthy(drift and drift:find("-1)", 1, true), "an endless tween, no per-frame Lua")
		T.truthy(source:find("Motion.onReducedChanged(", 1, true), "and follow the setting")
		local refresh = source:match("\nlocal function refreshBackpack%(%)(.-)\nend\n")
		T.truthy(refresh and refresh:find("count > shownCount", 1, true), "a bounce when ore comes in")
		T.falsy(source:find("RenderStepped", 1, true) or source:find("Heartbeat", 1, true), "no per-frame loop in HudController")
		-- the drifting holder knows its step: one stripe along
		inRound(function()
			local refs = HudBubble.buildGame(1, 1280, false, false, 662) :: any
			local drift = refs.Backpack:FindFirstChild("Bar"):FindFirstChild("Fill"):FindFirstChild("Drift")
			local step = drift:GetAttribute("Step")
			T.near(step, HudBubble.GoldSizes.BarStripe * math.sqrt(2), 1e-6, "one stripe along the bar")
			T.truthy(drift.Size.X.Offset >= refs.Backpack:FindFirstChild("Bar").Size.X.Offset - 1, "as wide as the bar and a stripe")
			for _, name in { "Pack", "Count", "CountShadow" } do
				local part = refs.Backpack:FindFirstChild(name)
				T.truthy(part and part:FindFirstChild("Bounce"), name .. ": its bounce scale")
			end
			refs.Gui:Destroy()
		end)
	end)
end
