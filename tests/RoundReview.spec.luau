--[[
	The round look's review (2026-10-28, round_look_review_findings): touch
	tablets get no offers and keep a short tile grid at the top (out of the
	thumbstick's start zone, clear of the top row), the boost corner keeps
	off the offers, the PC TRAIN chip sits under the tiles (owner
	2026-10-28: the tall block, the chip as wide as it) clear of the
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
			for _, size in { { 1024, 768, 58 }, { 1133, 744, 58 }, { 1280, 800, 58 } } do
				local screen = Vector2.new(size[1], size[2])
				local scale = HudBubble.scaleFor(screen)
				local where = `{size[1]} x {size[2]}`
				local refs = HudBubble.buildGame(scale, size[1], true, false, size[2] - size[3]) :: any
				T.eq(refs.Gui:FindFirstChild("Offers"), nil, where .. ": no offers on a touch tablet")
				local width, height = size[1] / scale, (size[2] - size[3]) / scale
				local menu = refs.Menu
				local bottom = menu.Position.Y.Offset + menu.Size.Y.Offset
				T.truthy(bottom <= height / 3, `{where}: the tiles above the thumbstick's zone ({bottom} <= {height / 3})`)
				local right = menu.Position.X.Offset + menu.Size.X.Offset
				T.truthy(right < width / 2 - refs.TopBar.Size.X.Offset / 2, where .. ": the tiles left of the top row")
				local grid = menu:FindFirstChildOfClass("UIGridLayout") :: any
				T.truthy(grid.CellSize.X.Offset * scale >= 44, where .. ": the tiles a thumb wide")
				-- the TRAIN chip under them (touch: TrainController's compact chip), also above the zone
				local chipTop = refs.Gui:GetAttribute("ChipTop")
				local chip = TrainView.chipSize(true)
				T.eq(chip.Y, HudBubble.TouchChipHeight, "the HUD knows the touch chip's height")
				local chipBottom = chipTop + chip.Y
				T.truthy(chipBottom <= height / 3, `{where}: the TRAIN chip above the zone ({chipBottom} <= {height / 3})`)
				-- the toasts start under the chip (its gui draws over the HUD's)
				T.truthy(refs.Toasts.Position.Y.Offset >= chipBottom, where .. ": the toasts under the TRAIN chip")
				-- the MORE flyout opens under the top row's buttons, over the toasts
				HudBubble.addMore(refs.Menu, "Codex", { Label = "CODEX", IconName = "Codex", Order = 1 })
				HudBubble.toggleMore(refs.Menu, true)
				local flyout = refs.Gui:FindFirstChild("MoreFlyout") :: any
				local bar = refs.TopBar
				T.truthy(flyout.Position.Y.Offset >= bar.Position.Y.Offset + bar.Size.Y.Offset, where .. ": the flyout under the top row")
				T.truthy(flyout.ZIndex > refs.Toasts.ZIndex, where .. ": the flyout over the toasts")
				-- (owner 2026-10-28: the chip under the tiles, as wide as them)
				T.eq(refs.Gui:GetAttribute("ChipLeft"), menu.Position.X.Offset, where .. ": the chip under the tiles' left edge")
				TrainView.useHud(refs.Gui)
				T.eq(TrainView.chipSize(true).X, menu.Size.X.Offset, where .. ": the chip as wide as the tiles")
				TrainView.useHud(nil)
				-- the BLASTER slot + backpack pair out of the thumbstick's zone on a tablet too
				local pairLeft = width / 2 + refs.CarryPanel.Position.X.Offset
				T.truthy(pairLeft >= HudBubble.ThumbZone * width - 1e-6, `{where}: the bottom pair from {pairLeft} of {width}`)
				refs.Gui:Destroy()
			end
			-- a PC keeps the offers and the tall block of tiles, two a row (owner 2026-10-28)
			local pc = HudBubble.buildGame(1, 1280, false, false, 720 - 58) :: any
			T.truthy(pc.Gui:FindFirstChild("Offers"), "PC: the offers")
			T.eq(pc.Menu:GetAttribute("Columns"), 2, "PC: two a row")
			local big = HudBubble.buildGame(1.25, 1920, false, false, 1080 - 58) :: any
			T.eq(big.Menu:GetAttribute("Columns"), 2, "1920 x 1080: two a row")
			T.truthy(big.Menu.Position.Y.Offset > HudBubble.MenuTop, "1920 x 1080: lower, like the reel's, where there is room")
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

	T.test("RoundReview: the PC TRAIN chip under the tiles as wide as them, clear of the Server Luck line and the floaters", function()
		inRound(function()
			for _, size in { { 1280, 720, 58 }, { 1366, 768, 58 }, { 1280, 800, 36 }, { 1920, 1080, 58 } } do
				local scale = HudBubble.scaleFor(Vector2.new(size[1], size[2]))
				local width, height = size[1] / scale, (size[2] - size[3]) / scale
				local refs = HudBubble.buildGame(scale, size[1], false, false, size[2] - size[3]) :: any
				local where = `{size[1]} x {size[2]}`
				local chipLeft, chipTop = refs.Gui:GetAttribute("ChipLeft"), refs.Gui:GetAttribute("ChipTop")
				T.eq(chipLeft, refs.Menu.Position.X.Offset, where .. ": under the tiles' left edge")
				T.eq(refs.Gui:GetAttribute("ChipStack"), true, where .. ": the stacked chip")
				TrainView.useHud(refs.Gui)
				local chip = TrainView.chipSize(false)
				TrainView.useHud(nil)
				T.eq(chip.X, refs.Menu.Size.X.Offset, where .. ": as wide as the tiles")
				T.eq(chip.Y, HudBubble.StackChipHeight, where .. ": the HUD knows the stacked chip's height")
				T.eq(refs.Menu:GetAttribute("Columns"), 2, where .. ": two a row")
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

	T.test("RoundReview: the limited banner's buy buttons stay 44 pt and never cover the golems' odds", function()
		inRound(function()
			local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
			if not edition then
				return
			end
			-- { label, design width, design height, compact, the HUD scale }
			local screens = {
				{ "568 x 320", 568 / 0.62, (320 - 58) / 0.62, true, 0.62 },
				{ "667 x 375", 667 / 0.62, (375 - 58) / 0.62, true, 0.62 },
				{ "844 x 390", 844 / 0.62, (390 - 58) / 0.62, true, 0.62 },
				{ "1024 x 768 touch", 1024 / 0.931, (768 - 58) / 0.931, true, 0.931 },
				{ "TV 1920 x 1080", 1920 / 1.25, (1080 - 58) / 1.25, true, 1.25 },
				{ "PC 1280 x 720", 1280, 684, false, 1 },
			}
			local k = StoreView.CardsWidth / StoreView.BannerWidth
			for _, screen in screens do
				local refs = StoreView.build()
				StoreView.setEdition(refs, edition)
				StoreView.layout(refs, screen[2], screen[3], screen[4])
				local banner = refs.Banner :: any
				local where = screen[1]
				local height = banner.Frame.Size.Y.Offset
				local boxes = {}
				for count, button in banner.Buys do
					local w, h = button.Size.X.Offset, button.Size.Y.Offset
					local x, y = button.Position.X.Offset - w / 2, button.Position.Y.Offset - h / 2
					table.insert(boxes, { x, y, x + w, y + h })
					T.truthy(y + h <= height, `{where}: x{count} inside the banner`)
					if screen[4] and screen[5] <= 0.75 then
						T.truthy(h * k * refs.Fit * screen[5] >= 44 - 1e-6, `{where}: x{count} {h * k * refs.Fit * screen[5]} pt tall`)
						T.truthy(w * k * refs.Fit * screen[5] >= 44, `{where}: x{count} wide enough`)
					end
				end
				-- every golem's chance % (the tile's bottom-right label) clear of every button
				for id, label in banner.Chances do
					local tile = label.Parent :: any
					local tx, ty = tile.Position.X.Offset, tile.Position.Y.Offset
					local size = tile.Size.Y.Offset
					local rect = { tx, ty + size - label.Size.Y.Offset, tx + tile.Size.X.Offset, ty + size }
					for _, box in boxes do
						T.falsy(overlap(rect, box), `{where}: {id}'s chance shows`)
					end
				end
				-- the list leaves the banner its whole (shrunk) height
				local section = banner.Frame.Parent :: any
				T.truthy(section.Size.Y.Offset >= banner.Frame.Position.Y.Offset + height * k - 1, `{where}: the section holds the banner`)
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

	-- (review 2026-10-29) the grid is fitted to the screen's height: a full-screen PC layout refits when
	-- the window shrinks (HudController: HudBubble.placeMenu on every size change), so the TRAIN chip
	-- never lands on the money, its Server Luck line or the floaters
	T.test("RoundReview: the tiles and the TRAIN chip refit when the window shrinks", function()
		inRound(function()
			local big = HudBubble.scaleFor(Vector2.new(1920, 1080))
			local refs = HudBubble.buildGame(big, 1920, false, false, 1080 - 58) :: any
			local small = HudBubble.scaleFor(Vector2.new(1280, 720))
			local layout = HudBubble.layout(small, 1280, false, false, 720 - 58)
			HudBubble.placeMenu(refs.Gui, refs.Menu, layout)
			TrainView.useHud(refs.Gui)
			local chip = TrainView.chipSize(false)
			TrainView.useHud(nil)
			local height = (720 - 58) / small
			local chipBottom = refs.Gui:GetAttribute("ChipTop") + chip.Y
			T.truthy(chipBottom <= HudBubble.roundFloor(layout, height), `the chip above the floaters ({chipBottom})`)
			local grid = refs.Menu:FindFirstChildOfClass("UIGridLayout") :: any
			T.eq(grid.CellSize.X.Offset, layout.Tile, "the tiles took the new size")
			T.eq(refs.Menu.Size.Y.Offset, HudBubble.menuMetrics(layout, #HudBubble.gameMenu()).Height, "the block took the new height")
			T.eq(refs.Gui:GetAttribute("ChipWidth"), refs.Menu.Size.X.Offset, "the chip as wide as the block again")
			refs.Gui:Destroy()
		end)
	end)

	-- (review 2026-10-29) a TV's stacked chip keeps its words 18 px at 1080p: the line on two rows, not smaller
	T.test("RoundReview: a TV's stacked TRAIN chip keeps its line big (two rows)", function()
		inRound(function()
			local scale = HudBubble.scaleFor(Vector2.new(1920, 1080))
			local refs = HudBubble.buildGame(scale, 1920, false, true, 1080 - 58) :: any
			T.eq(refs.Gui:GetAttribute("ChipStack"), true, "stacked on a TV")
			TrainView.useHud(refs.Gui)
			T.eq(TrainView.chipSize(false).Y, HudBubble.StackChipHeightTv, "the HUD knows the TV chip's height")
			local train = TrainView.build(false)
			TrainView.layout(train, false, 1920 / scale, (1080 - 58) / scale)
			TrainView.useHud(nil)
			local line = train.ChipLine :: any
			local fit = line:FindFirstChildOfClass("UITextSizeConstraint") :: any
			T.truthy(fit and fit.MinTextSize * scale >= 18, "the line never under 18 px")
			T.truthy(line.TextWrapped and line.Size.Y.Offset >= 2 * fit.MinTextSize, "two rows for a long line")
			-- (review 2026-10-29) and the name: "TRAIN" / "120/180" on two rows across the chip, never under 18 px
			local title = train.ChipTitle :: any
			local titleFit = title:FindFirstChildOfClass("UITextSizeConstraint") :: any
			T.truthy(titleFit and titleFit.MinTextSize * scale >= 18, "the name never under 18 px")
			T.truthy(title.TextWrapped and title.Size.Y.Offset >= 2 * titleFit.MinTextSize, "two rows for the name")
			T.truthy(title.Size.X.Offset >= 7 * titleFit.MinTextSize, "room for 120/180 at that size")
			-- (review 2026-10-29) the rows never overlap: the name, the bar, the line, SEND
			local bar = train.ChipBar :: any
			local send = (train.ChipSend :: any).Parent
			T.truthy(bar.Position.Y.Offset >= title.Position.Y.Offset + title.Size.Y.Offset, "the bar under the name")
			T.truthy(line.Position.Y.Offset >= bar.Position.Y.Offset + bar.Size.Y.Offset, "the line under the bar")
			T.truthy(send.Position.Y.Offset >= line.Position.Y.Offset + line.Size.Y.Offset, "SEND under the line")
			T.truthy(send.Position.Y.Offset + send.Size.Y.Offset <= HudBubble.StackChipHeightTv, "SEND inside the chip")
			train.Gui:Destroy()
			train.Chip:Destroy()
			refs.Gui:Destroy()
		end)
	end)

	-- (review 2026-10-29) the smallest touch phones: the TRAIN chip (beside or squeezed under the
	-- tiles) keeps off FIRE, Grab and Jump (BoostView.TouchButtons, measured like BoostController)
	-- and off the boost corner that moves left of the touch tutorial's bubble
	T.test("RoundReview: on the smallest touch phones the TRAIN chip keeps off the touch buttons and the boost corner", function()
		inRound(function()
			local TutorialView = ui("TutorialView")
			for _, size in
				{
					{ 533, 300 },
					{ 568, 320 },
					{ 600, 320 },
					{ 600, 340 },
					{ 620, 350 },
					{ 640, 320 },
					{ 640, 360 },
					{ 654, 334 },
					{ 699, 343 },
				}
			do
				for _, inset in { 36, 58 } do
					local where = `{size[1]} x {size[2]} (inset {inset})`
					local scale = HudBubble.scaleFor(Vector2.new(size[1], size[2]))
					local gui = Vector2.new(size[1], size[2] - inset)
					local w, h = gui.X / scale, gui.Y / scale
					local refs = HudBubble.buildGame(scale, size[1], true, false, gui.Y) :: any
					TrainView.useHud(refs.Gui)
					local chip = TrainView.chipSize(true)
					TrainView.useHud(nil)
					local x0, y0 = refs.Gui:GetAttribute("ChipLeft"), refs.Gui:GetAttribute("ChipTop")
					local chipRect = { x0, y0, x0 + chip.X, y0 + chip.Y }
					local small = math.min(size[1], size[2]) <= 500
					local buttons = {}
					for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
						local r = { w - b.Left / scale, h - b.Top / scale, w - b.Right / scale, h - b.Bottom / scale }
						buttons[b.Name] = r
						-- (from 568 x 320 up, the smallest phone Roblox runs on: under it the tiles, the
						-- chip and FIRE can't all fit in the top half)
						if size[1] >= 568 then
							T.falsy(overlap(chipRect, r), `{where}: the chip clear of {b.Name}`)
						end
					end
					-- (review 2026-10-29) where it reaches the floaters' band over the money or the toasts'
					-- column, it draws under the HUD: those stay readable over it
					local column = BoostView.ToastColumn
					local toasts = { w / 2 - column.Width / 2, column.Top, w / 2 + column.Width / 2, column.Top + column.Height }
					local layout = HudBubble.layout(scale, size[1], true, false, gui.Y)
					if chipRect[4] > HudBubble.roundFloor(layout, h) or overlap(chipRect, toasts) then
						TrainView.useHud(refs.Gui)
						local train = TrainView.build(true)
						TrainView.layout(train, true, w, h)
						TrainView.useHud(nil)
						T.truthy(train.Chip.DisplayOrder < refs.Gui.DisplayOrder, `{where}: the chip under the HUD's toasts and floaters`)
						train.Gui:Destroy()
						train.Chip:Destroy()
					end
					-- the money under it
					local moneyTop = h + refs.CoinsPanel.Position.Y.Offset - refs.CoinsPanel.Size.Y.Offset
					T.truthy(chipRect[4] <= moneyTop, `{where}: the chip above the money`)
					-- the boost corner while the touch tutorial's bubble shows
					local bubble = TutorialView.layout(scale, gui, true)
					local bubbleRect =
						{ Left = bubble.Position.X - bubble.Width, Top = bubble.Position.Y, Bottom = bubble.Position.Y + bubble.Height }
					-- the bubble's SKIP and GOT IT (TutorialView.apply: the row at its bottom right)
					local bLeft, bTop = bubble.Position.X - bubble.Width, bubble.Position.Y
					local rowY = bTop + TutorialView.Head + bubble.BodyHeight + TutorialView.Gap + 5
					local skipLeft = bLeft + bubble.Width - 12 - TutorialView.SkipWidth
					local ackLeft = skipLeft - 8 - TutorialView.AckWidth
					local bubbleButtons = {
						Skip = { skipLeft, rowY, skipLeft + TutorialView.SkipWidth, rowY + bubble.RowHeight },
						Ack = { ackLeft, rowY, ackLeft + TutorialView.AckWidth, rowY + bubble.RowHeight },
					}
					for _, count in { 1, 2 } do
						local right, bottom, stacked, spot = BoostView.cornerSpot({
							Screen = Vector2.new(size[1], size[2]),
							Gui = gui,
							Scale = scale,
							Touch = true,
							Count = count,
							Bubble = bubbleRect,
							Chip = { Left = chipRect[1], Top = chipRect[2], Right = chipRect[3], Bottom = chipRect[4] },
						})
						local tile, gap = BoostView.cornerHeight(), BoostView.CornerGap
						local rowW = if stacked then BoostView.CornerWidth else count * BoostView.CornerWidth + (count - 1) * gap
						local rowH = if stacked then count * tile + (count - 1) * gap else tile
						local corner = { w - right - rowW, h - bottom - rowH, w - right, h - bottom }
						T.falsy(overlap(chipRect, corner), `{where}: the chip clear of the boost corner ({count})`)
						for name, r in buttons do
							T.falsy(overlap(corner, r), `{where}: the boost corner ({count}) clear of {name}`)
						end
						T.truthy(corner[2] >= 0, `{where}: the boost corner ({count}) on the screen`)
						-- (review 2026-10-29) the bubble's buttons stay tappable: the corner never covers them,
						-- or it waits while the bubble shows (BoostController hides an "OverBubble" corner)
						if spot ~= "OverBubble" then
							for name, r in bubbleButtons do
								T.falsy(overlap(corner, r), `{where}: the boost corner ({count}) clear of the bubble's {name}`)
							end
						end
					end
					refs.Gui:Destroy()
				end
			end
			-- (HudBubble mirrors these: the corner column's room and the bubble's gap)
			T.eq(HudBubble.BoostColumnRoom, 2 * BoostView.CornerGap + BoostView.CornerWidth, "the corner column's room")
			T.eq(HudBubble.TutorialBarGap, TutorialView.BarGap, "the tutorial bubble's gap")
			T.eq(BoostView.TouchButtons, HudBubble.TouchButtons, "one table of touch buttons")
			local controller = require("@lune/fs").readFile(Loader.root .. "/src/client/Controllers/BoostController.luau")
			T.truthy(controller:find('covering = spot == "OverBubble"', 1, true), "the corner waits while it would cover the bubble")
		end)
	end)
end
