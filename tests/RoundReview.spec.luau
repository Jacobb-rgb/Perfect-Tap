--[[
	The round look's review (2026-10-28, round_look_review_findings): touch
	tablets get no offers and keep a short tile grid at the top (out of the
	thumbstick's start zone, clear of the top row), the boost corner keeps
	off the offers, the PC TRAIN chip sits beside the tiles clear of the
	Server Luck line and the floaters, a TV keeps the HUD out of its safe
	band, the Daily Reward popup fits phones, the limited banner's buy
	buttons stay 44 pt, the Spin tile says FREE! only for the free spin, the
	Inventory's search is a thumb tall and never leaves the gamepad on a
	hidden cell, and the Codex drops a filter it can't show.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local function ui(name: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local HudBubble = ui("HudBubble")
	local BoostView = ui("BoostView")
	local TrainView = ui("TrainView")
	local QuestView = ui("QuestView")
	local StoreView = ui("StoreView")
	local BackpackView = ui("BackpackView")
	local CodexView = ui("CodexView")
	local BackpackState = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.BackpackState")

	-- the round look with the light UI (the tests restore both)
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

	local function overlap(a: { number }, b: { number }): boolean
		return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
	end

	T.test("RoundReview: touch tablets get no offers and a short tile grid out of the thumbstick's zone", function()
		inRound(function()
			-- { width, height, the top inset (px) }: 1024 x 768, an iPad mini, a 1280 x 800 tablet
			for _, size in { { 1024, 768, 36 }, { 1133, 744, 36 }, { 1280, 800, 36 } } do
				local screen = Vector2.new(size[1], size[2])
				local scale = HudBubble.scaleFor(screen)
				local where = `{size[1]} x {size[2]}`
				local refs = HudBubble.buildGame(scale, size[1], true, false) :: any
				T.eq(refs.Gui:FindFirstChild("Offers"), nil, where .. ": no offers on a touch tablet")
				local width, height = size[1] / scale, (size[2] - size[3]) / scale
				local menu = refs.Menu
				local bottom = menu.Position.Y.Offset + menu.Size.Y.Offset
				T.truthy(bottom <= height / 3, `{where}: the tiles above the thumbstick's zone ({bottom} <= {height / 3})`)
				local right = menu.Position.X.Offset + menu.Size.X.Offset
				T.truthy(right < width / 2 - refs.TopBar.Size.X.Offset / 2, where .. ": the tiles left of the top row")
				local grid = menu:FindFirstChildOfClass("UIGridLayout") :: any
				T.truthy(grid.CellSize.X.Offset * scale >= 44, where .. ": the tiles a thumb wide")
				-- the TRAIN chip under them, also above the zone
				local chipTop = refs.Gui:GetAttribute("ChipTop")
				T.truthy(chipTop + TrainView.chipSize(false).Y <= height / 3 + 1, where .. ": the TRAIN chip above the zone")
				T.eq(refs.Gui:GetAttribute("ChipLeft"), nil, where .. ": the chip at its usual left")
				-- the BLASTER slot + backpack pair out of the thumbstick's zone on a tablet too
				local pairLeft = width / 2 + refs.CarryPanel.Position.X.Offset
				T.truthy(pairLeft >= HudBubble.ThumbZone * width - 1e-6, `{where}: the bottom pair from {pairLeft} of {width}`)
				refs.Gui:Destroy()
			end
			-- a PC keeps the reel's lowered tiles and the offers
			local pc = HudBubble.buildGame(1, 1280, false, false) :: any
			T.truthy(pc.Gui:FindFirstChild("Offers"), "PC: the offers")
			T.eq(pc.Menu.Position.Y.Offset, HudBubble.RoundMenuTop, "PC: the reel's lowered tiles")
		end)
	end)

	T.test("RoundReview: the boost corner keeps off the offers (the mouse tutorial card lifts it)", function()
		inRound(function()
			for _, size in { { 1280, 720, 36 }, { 1920, 1080, 58 } } do
				local screen = Vector2.new(size[1], size[2])
				local scale = HudBubble.scaleFor(screen)
				local gui = Vector2.new(size[1], size[2] - size[3])
				local width, height = gui.X / scale, gui.Y / scale
				local refs = HudBubble.buildGame(scale, size[1], false, false) :: any
				local offers = refs.Gui:FindFirstChild("Offers") :: any
				local ow, oh = offers.Size.X.Offset, offers.Size.Y.Offset
				local left = width + offers.Position.X.Offset - ow
				local top = height / 2 - oh / 2
				local avoid = { Left = left, Top = top, Bottom = top + oh }
				for _, count in { 1, 2 } do
					-- the mouse tutorial card at the bottom right: the row stands on it
					for _, card in { 0, 190, 260 } do
						local right, bottom, stacked = BoostView.cornerSpot({
							Screen = screen,
							Gui = gui,
							Scale = scale,
							Touch = false,
							Count = count,
							TutorialTop = if card > 0 then card else nil,
							Avoid = avoid,
						})
						local tile = BoostView.cornerHeight()
						local rowW = if stacked
							then BoostView.CornerWidth
							else count * BoostView.CornerWidth + (count - 1) * BoostView.CornerGap
						local rowH = if stacked then count * tile + (count - 1) * BoostView.CornerGap else tile
						local row = { width - right - rowW, height - bottom - rowH, width - right, height - bottom }
						local column = { avoid.Left, avoid.Top, width, avoid.Bottom }
						T.falsy(overlap(row, column), `{size[1]} x {size[2]}, {count} boost(s), card {card}: off the offers`)
						T.truthy(row[1] >= 0 and row[2] >= 0, "on screen")
					end
				end
				refs.Gui:Destroy()
			end
		end)
	end)

	T.test("RoundReview: the PC TRAIN chip beside the tiles, clear of the Server Luck line and the floaters", function()
		inRound(function()
			for _, size in { { 1280, 720, 58 }, { 1366, 768, 58 }, { 1280, 800, 36 }, { 1920, 1080, 58 } } do
				local scale = HudBubble.scaleFor(Vector2.new(size[1], size[2]))
				local width, height = size[1] / scale, (size[2] - size[3]) / scale
				local refs = HudBubble.buildGame(scale, size[1], false, false) :: any
				local where = `{size[1]} x {size[2]}`
				local chipLeft, chipTop = refs.Gui:GetAttribute("ChipLeft"), refs.Gui:GetAttribute("ChipTop")
				T.truthy(type(chipLeft) == "number", where .. ": beside the tiles")
				local chip = TrainView.chipSize(false)
				local chipRect = { chipLeft, chipTop, chipLeft + chip.X, chipTop + chip.Y }
				local function rectOf(object: any): { number }
					local x = width * object.Position.X.Scale + object.Position.X.Offset - object.AnchorPoint.X * object.Size.X.Offset
					local y = height * object.Position.Y.Scale + object.Position.Y.Offset - object.AnchorPoint.Y * object.Size.Y.Offset
					return { x, y, x + object.Size.X.Offset, y + object.Size.Y.Offset }
				end
				for _, name in { "ServerLuck", "Floaters", "Toasts", "Coins", "Offers" } do
					local object = refs.Gui:FindFirstChild(name)
					if object then
						T.falsy(overlap(chipRect, rectOf(object)), `{where}: the chip clear of {name}`)
					end
				end
				T.falsy(overlap(chipRect, rectOf(refs.Menu)), where .. ": clear of the tiles")
				T.truthy(
					chipRect[3] < width / 2 - refs.CarryPanel.Size.X.Offset / 2 or chipRect[4] < height - 100,
					where .. ": clear of the bottom pair"
				)
				refs.Gui:Destroy()
			end
		end)
	end)

	T.test("RoundReview: a TV keeps the offers, the money and the tiles out of its 5 % band", function()
		inRound(function()
			local scale = HudBubble.scaleFor(Vector2.new(1920, 1080))
			local width, height = 1920 / scale, (1080 - 58) / scale
			local refs = HudBubble.buildGame(scale, 1920, false, true) :: any
			local band = HudBubble.TenFootSafe
			local offers = refs.Gui:FindFirstChild("Offers") :: any
			local offersRight = width * offers.Position.X.Scale + offers.Position.X.Offset
			-- (the tilted R$ tags reach ~30 units past the pictures' column)
			T.truthy(offersRight <= width * (1 - band) - 6 + 1e-6, `the offers in from the right ({offersRight} of {width})`)
			T.truthy(refs.Menu.Position.X.Offset >= width * band, "the tiles in from the left")
			local coins = refs.CoinsPanel
			T.truthy(coins.Position.X.Offset >= width * band, "the money in from the left")
			local coinsBottom = height * coins.Position.Y.Scale + coins.Position.Y.Offset
			T.truthy(coinsBottom <= height * (1 - band) + 1e-6, "the money up from the bottom")
		end)
	end)

	T.test("RoundReview: the Daily Reward popup fits phones (CLAIM and ODDS inside, over the footnote)", function()
		inRound(function()
			for _, size in { { 844, 390 }, { 667, 375 }, { 568, 320 } } do
				local scale = 0.62
				local w, h = size[1] / scale, (size[2] - 58) / scale
				local refs = QuestView.buildPopup()
				QuestView.layoutPopup(refs, w, h, true)
				local where = `{size[1]} x {size[2]}`
				local bodyH = refs.Window.Root.Size.Y.Offset - QuestView.Header - 3
				local footTop = bodyH - 8 - refs.Note.Size.Y.Offset
				for _, button in { refs.Claim, refs.OddsButton } do
					local bottom = button.Position.Y.Offset + button.Size.Y.Offset
					T.truthy(bottom <= footTop + 1e-6, `{where}: {button.Name} ends at {bottom}, over the footnote at {footTop}`)
				end
				T.truthy(refs.Claim.Size.Y.Offset * scale * refs.Fit >= 44 - 1e-6, where .. ": CLAIM 44 pt")
			end
		end)
	end)

	T.test("RoundReview: the limited banner's buy buttons stay 44 pt on phones through the list's shrink", function()
		inRound(function()
			local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
			if not edition then
				return
			end
			local refs = StoreView.build()
			StoreView.setEdition(refs, edition)
			local scale = 0.62
			StoreView.layout(refs, 667 / scale, (375 - 58) / scale, true)
			local k = StoreView.CardsWidth / StoreView.BannerWidth
			local banner = refs.Banner :: any
			for count, button in banner.Buys do
				local pt = button.Size.Y.Offset * k * refs.Fit * scale
				T.truthy(pt >= 44 - 1e-6, `x{count}: {pt} pt tall`)
				T.truthy(button.Size.X.Offset * k * refs.Fit * scale >= 44, `x{count}: wide enough`)
				local y = button.Position.Y.Offset - button.Size.Y.Offset / 2
				T.truthy(y >= 0, `x{count}: inside the banner`)
			end
		end)
	end)

	T.test("RoundReview: the Spin tile says FREE! only for the free spin, else the bought spins' count", function()
		inRound(function()
			local refs = HudBubble.buildGame(1, 1280, false, false) :: any
			local face = HudBubble.claimTile(refs.Menu, "Wheel")
			HudBubble.setTileBadge(face, 2, false)
			T.eq(face:FindFirstChild("Sticker"), nil, "no FREE! with bought spins only")
			T.truthy(face:FindFirstChild("Badge"), "their count")
			HudBubble.setTileBadge(face, 3, true)
			T.truthy(face:FindFirstChild("Sticker"), "FREE! with the free spin ready")
			T.eq(face:FindFirstChild("Badge"), nil, "the sticker alone")
			HudBubble.setTileBadge(face, 0, false)
			T.eq(face:FindFirstChild("Sticker"), nil)
			T.eq(face:FindFirstChild("Badge"), nil)
		end)
	end)

	T.test("RoundReview: the Inventory search is a thumb tall on phones and never hides the gamepad's cell", function()
		inRound(function()
			local refs = BackpackView.build()
			local search = refs.Search :: any
			T.truthy(search, "the search box")
			local scale = 0.62
			BackpackView.layout(refs, 667 / scale, (375 - 58) / scale, true)
			local _, fit = BackpackView.windowSize(667 / scale, (375 - 58) / scale, true)
			T.truthy(search.Size.Y.Offset * scale * fit >= 44 - 1e-6, `the search box {search.Size.Y.Offset * scale * fit} pt tall`)
			local function key(kind: string, ore: string, grade: string?): string
				return ItemData.storageKey({ K = kind, O = ore, G = grade })
			end
			local items = { [key("Raw", "Copper")] = 2, [key("Clean", "Diamond", "Rough")] = 1 }
			BackpackView.setBackpack(refs, BackpackState.read({ Backpacks = { Count = 3, Capacity = 10, Items = items } }))
			BackpackView.setSearch(refs, "diamond")
			local first = BackpackView.firstRow(refs)
			T.truthy(first and first.Frame.Visible, "the first row the search shows")
			T.falsy(refs.Empty.Visible, "a match: no empty line")
			BackpackView.setSearch(refs, "zzz")
			T.eq(BackpackView.firstRow(refs), nil, "nothing shows: no row to select")
			T.truthy(refs.Empty.Visible and refs.Empty.Text == BackpackView.NoMatchText, "the no-match line")
			BackpackView.setSearch(refs, "")
			T.truthy(BackpackView.firstRow(refs), "every stack again")
		end)
	end)

	T.test("RoundReview: the Codex drops a rarity filter on a layout with no filter tabs", function()
		inRound(function()
			local refs = CodexView.build(false)
			CodexView.layout(refs, false, 1280, 684)
			if next(refs.Filters) == nil then
				return
			end
			CodexView.setFilter(refs, "Epic")
			CodexView.layout(refs, true, 667 / 0.62, (375 - 58) / 0.62)
			T.eq(refs.Filter, nil, "compact: no tabs, no filter")
			for _, card in refs.CardList do
				T.truthy(card.Button.Visible, card.OreId .. " shows")
			end
		end)
	end)

	T.test("RoundReview: the gamepad's picks: an offer's card, the top row's Shop", function()
		local fs = require("@lune/fs")
		local function source(rel: string): string
			return fs.readFile(Loader.root .. "/src/client/" .. rel .. ".luau")
		end
		local store = source("Controllers/StoreController")
		T.truthy(store:find("GuiService.SelectedObject = card.Button", 1, true), "an offer selects its card")
		local teleport = source("Controllers/TeleportController")
		T.truthy(teleport:find('selected.Name == "ShopPill"', 1, true), "the bar owns its Shop button")
	end)
end
