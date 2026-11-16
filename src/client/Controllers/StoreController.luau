--[[
	The Robux Shop window (owner 2026-10-20; shop v3 "WOW" 2026-11-11: six
	tabs, each its own colour world): opened by the side menu's STORE entry,
	the HUD's Shop button and OpenUI "Store". A tab (or LB / RB on a
	gamepad) shows its page.

	- A card's price button buys its product (StoreView.setCard picks which:
	  the blaster shows the price band of the player's next level, hidden at
	  the top); a one-price card's face buys too. By the product's Grant:
	    Capsule     CapsuleAction "Open" { Capsule, Count, Lucky } (the
	                capsule service remembers the odds the player saw)
	    Boost       BoostAction "BuyRobux" { Id }
	    WheelSpins  WheelAction "Buy" { Count } (WheelService: "Full" past the
	                spins it holds or with no golem room)
	    others      StoreAction "Buy" { Key } (StoreService)
	  Every buy is answered with PurchasePrompt { Product, Status }; the card
	  greys out until then (PROMPT_MEMORY seconds at most).
	- Paid random products (MonetizationConfig PaidRandom) show their exact
	  odds first (the odds panel: capsule odds, the wheel's segments, or the
	  ore luck per zone now and with the buy); they are hidden where the
	  player's policy restricts paid random items (PaidRandomRestricted).
	- Coin cards and the Starter Pack show the coins at the player's podium
	  income now; the Royal Egg and the limited edition show the odds a buy
	  rolls now (Triple Lucky included).
	- The pages are built lazily (StoreView.build): the open tab's at once,
	  each other the first time it opens; its buttons are wired then.
	- The motion (UI/ShopFx) is TweenService loops only, no per-frame Lua:
	  the window's own (rays, bolts, sparkles, the title's light band: none
	  of the ambient ones on a phone) and the open tab's (its page's shine,
	  gloss, rims, floats, idling golems and eggs, wiggles, pulses, rays and
	  particles, the tab's bob and its icon's wiggle) while the window is
	  open; a tab change stops the old tab's, a close stops all. A phone or
	  a tablet skips the ambient marks (view.Lean); a TV keeps them. As it
	  opens the header cascades in (StoreView.cascade). A purchase the shop
	  asked for that Roblox's prompt reports done: its card flashes, pops
	  and throws stars (StoreView.celebrate). Config/AnimConfig.PixelFx on
	  and Reduce motion off; else the shop stands still.
]]

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local StoreConfig = require(Shared.Config.StoreConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local LimitedGolems = require(Shared.Config.LimitedGolems)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local BlasterData = require(Shared.Config.BlasterData)
local WheelConfig = require(Shared.Config.WheelConfig)
local Net = require(Shared.Net)
local StoreView = require(script.Parent.Parent.UI.StoreView)
local ShopFx = require(script.Parent.Parent.UI.ShopFx)
local BoostView = require(script.Parent.Parent.UI.BoostView)
local RebirthView = require(script.Parent.Parent.UI.RebirthView)
local CapsuleView = require(script.Parent.Parent.UI.CapsuleView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local WheelView = require(script.Parent.Parent.UI.WheelView)
local CardOdds = require(script.Parent.Parent.UI.CardOdds)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Confetti = require(script.Parent.Parent.Effects.Confetti)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local PromptController = require(script.Parent.PromptController)

local StoreController = {}

local NAME = "StoreController"
local CLOSE_ACTION = "TerraForgeStoreClose"
local TABS_ACTION = "TerraForgeStoreTabs"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local PROMPT_MEMORY = 10 -- seconds a buy waits for its PurchasePrompt answer
local BLASTER_WAIT = 30 -- seconds the blaster card stays greyed after its prompt (until the level changes)
local ASK_MEMORY = 300 -- seconds a buy from the shop may sit in Roblox's purchase prompt (its card celebrates after)

local player = Players.LocalPlayer
local refs: StoreView.Refs? = nil
local isOpen = false
local pending: { [string]: number } = {} -- product key -> os.clock() of the buy
local asked: { [string]: number } = {} -- product key -> os.clock() of a buy from the shop (until Roblox's prompt ends)
local detailKey: string? = nil
local detailFrom: GuiObject? = nil -- the button that opened the odds panel (BACK selects it again)
local stateAt: number? = nil -- server time of the last State (CapsuleView.luckyNow)
-- a blaster level bought: its card stays greyed until the level changes (or BLASTER_WAIT)
local blasterWait: { Key: string, Level: number, Until: number }? = nil
local bannerFrame: Frame? = nil -- the limited banner whose buttons are wired
local windowLoops: ShopFx.Playing? = nil -- the window's own loops while it is open
local tabLoops: ShopFx.Playing? = nil -- the open tab's loops (its page and its bob)
local tabPlayed: { Tab: string, Marks: number }? = nil -- what tabLoops runs for

function StoreController.isOpen(): boolean
	return isOpen
end

local function restricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

local function state(): { [string]: any }
	return StateController.get() or {}
end

local function percent(chance: number): string
	return StoreView.percent(chance)
end

-- Does the player have the pass behind `key` (perks / the enchant)?
local function owns(product: MonetizationConfig.Product): boolean
	if product.Kind ~= "GamePass" then
		return false
	end
	if product.Perks then
		for _, perk in product.Perks do
			if player:GetAttribute("Perk_" .. perk) ~= true then
				return false
			end
		end
		return #product.Perks > 0
	end
	if product.Enchant then
		local enchants = state().Enchants
		return EnchantConfig.tierOf(enchants, product.Enchant) >= 1
	end
	if product.BoardId then
		local boards = state().Hoverboards
		local owned = if type(boards) == "table" then boards.Owned else nil
		return type(owned) == "table" and table.find(owned, product.BoardId) ~= nil
	end
	return false
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Does Triple Lucky count for a capsule opened now? (the capsule window's own rule)
local function tripleLuckyNow(): boolean
	return CapsuleView.luckyNow(StateController.get(), serverNow(), stateAt)
end

-- Seconds of Server Luck left (0 = off; ServerBoostService's attribute).
local function serverLuckLeft(): number
	local untilTime = ReplicatedStorage:GetAttribute("ServerLuckUntil")
	return if type(untilTime) == "number" then math.max(0, untilTime - serverNow()) else 0
end

-- Is the golem inventory full (a bought spin's egg prize couldn't be kept)? The wheel's own rule.
local function inventoryBlocks(): boolean
	local s = StateController.get()
	if not s or type(s.Golems) ~= "table" or CapsuleConfig.allRestricted(false) then
		return false
	end
	return GolemConfig.room(s.Golems) < 1
end

-- The STAR blasters' save fields as StarBlasterData reads them (from the State's Rebirth snapshot).
local function starData(): { [string]: any }
	local rebirth = state().Rebirth
	if type(rebirth) ~= "table" then
		return {}
	end
	return {
		Rebirths = rebirth.Count,
		Stars = rebirth.Stars,
		RebirthWeapons = rebirth.Weapons,
		StarBlaster = rebirth.Weapon,
	}
end

-- A STAR blaster card's state and note.
local function starCard(view: StoreView.Refs, id: string, spec: StoreConfig.CardSpec): string
	local star = StarBlasterData.get(spec.Star)
	if not star then
		return "Hidden"
	end
	local cardState = StarBlasterData.cardState(starData(), star.Id)
	if cardState == "Locked" then
		StoreView.setNote(view, id, `Opens at rebirth {star.Unlock}`)
		return "Locked"
	elseif cardState == "Waiting" then
		StoreView.setNote(view, id, `Yours! Opens at rebirth {star.Unlock}`)
		return "Owned"
	elseif cardState == "Equipped" then
		StoreView.setNote(view, id, "In your hands")
		return "Owned"
	elseif cardState == "Owned" then
		StoreView.setNote(view, id, "Equip it in the STAR FORGE")
		return "Owned"
	end
	StoreView.setNote(view, id, "Kept forever, every rebirth")
	return "Buy"
end

-- (defined below: the banner's buttons open the odds panel; a page built late is wired)
local onLimited: (count: number) -> ()
local wirePages: (view: StoreView.Refs) -> ()

--[[
	The limited edition banner at the top of FEATURED (LimitedGolems.current):
	shown while it runs and the player may buy paid random items; its buttons
	open the odds panel first (onLimited), its time left follows the server clock.
]]
local function refreshBanner(view: StoreView.Refs)
	local edition = if restricted() then nil else LimitedGolems.current(serverNow())
	local banner = StoreView.setEdition(view, edition :: any)
	if banner and banner.Frame ~= bannerFrame then
		bannerFrame = banner.Frame
		for count, button in banner.Buys do
			button.Activated:Connect(function()
				onLimited(count)
			end)
		end
	elseif not banner then
		bannerFrame = nil
	end
	if banner and edition then
		StoreView.setTimer(view, banner.Edition.EndsAt - serverNow())
		-- the tiles show what a buy rolls now (Triple Lucky included), like the odds panel
		local lucky = tripleLuckyNow()
		local odds: { [string]: number } = {}
		for _, line in CapsuleConfig.odds(edition.CapsuleId, lucky) do
			odds[line.Golem] = line.Chance
		end
		StoreView.setBannerOdds(view, odds, lucky)
	end
end

-- The Royal Egg banner (GOLEMS): its golems' chances now; hidden where paid random items are restricted.
local function refreshRoyal(view: StoreView.Refs)
	StoreView.setRoyalShown(view, not restricted())
	local lucky = tripleLuckyNow()
	local odds: { [string]: number } = {}
	for _, line in CapsuleConfig.odds("Royal", lucky) do
		odds[line.Golem] = line.Chance
	end
	StoreView.setRoyalOdds(view, odds, lucky)
end

-- The open tab's loops: its page's and its bob (the old tab's stop and settle first).
local function playTab(view: StoreView.Refs)
	ShopFx.stop(tabLoops)
	tabLoops = nil
	tabPlayed = { Tab = view.Current, Marks = view.Marks }
	local roots: { Instance } = { view.Pages[view.Current] }
	local tab = view.TabRefs[view.Current]
	if tab then
		table.insert(roots, tab.Lift)
	end
	tabLoops = ShopFx.play(ShopFx.loopsUnder(roots, view.Lean))
end

-- The motion follows the open tab (also when a tab hid and another opened by itself) and what
-- shows on it (a card came or went, the BEST VALUE moved): only while the window's motion runs.
local function followTab(view: StoreView.Refs)
	local played = tabPlayed
	if windowLoops and (not played or played.Tab ~= view.Current or played.Marks ~= view.Marks) then
		playTab(view)
	end
end

-- Which product each card shows and its state.
local function refresh()
	local view = refs
	if not view then
		return
	end
	local now = os.clock()
	local level = state().BlasterLevel
	-- (every card, its page built or not: StoreView keeps what it is told until the page is built)
	for _, spec in StoreConfig.Cards do
		local id = spec.Id
		local key = spec.Keys[1]
		local cardState = "Buy"
		if #spec.Keys > 1 then
			local fits = StoreConfig.blasterKey(spec, level)
			local wait = blasterWait
			if wait and (level ~= wait.Level or now > wait.Until) then
				blasterWait = nil -- the level came (or the purchase was never made)
				wait = nil
			end
			if wait then
				cardState = "Pending"
			end
			if fits then
				key = fits
				local current = if type(level) == "number" then math.floor(level) else 1
				StoreView.setBig(view, id, `LV {current} > LV {current + 1}`)
				-- LV 10 waits for one level bought with coins this run (a rebirth needs it)
				local rebirth = state().Rebirth
				local reached = if type(rebirth) == "table" and type(rebirth.Reached) == "number" then rebirth.Reached else 0
				local start = if type(rebirth) == "table" and type(rebirth.Start) == "number" then rebirth.Start else 1
				if RebirthConfig.topBlockedFor(current, reached) then
					cardState = "Locked"
					StoreView.setNote(view, id, "Buy LV 10 with coins at the Vault")
				elseif start >= BlasterData.MaxLevel - 1 then
					StoreView.setNote(view, id, "Rebirth start is max (LV 9)")
				else
					StoreView.setNote(view, id, spec.Note or "")
				end
			else
				cardState = "Hidden"
			end
		end
		local product = MonetizationConfig.Products[key]
		if product.Grant == "StarterPack" then
			-- one per player: only while the offer is open (State.StarterPack, StarterPackService)
			local offer = state().StarterPack
			if type(offer) ~= "table" or offer.Open ~= true then
				cardState = "Hidden"
			end
		end
		if spec.Look == "Star" then
			cardState = starCard(view, id, spec)
			if cardState == "Buy" and pending[key] and now - pending[key] < PROMPT_MEMORY then
				cardState = "Pending"
			end
		elseif cardState ~= "Hidden" then
			local anyPending = false
			for _, option in StoreConfig.keysOf(spec) do
				if pending[option] and now - pending[option] < PROMPT_MEMORY then
					anyPending = true
				end
			end
			if cardState == "Pending" or cardState == "Locked" then
				-- (the blaster: waiting for its level, or LV 10 before a forged level)
			elseif product.PaidRandom and restricted() then
				cardState = "Hidden"
			elseif owns(product) then
				cardState = "Owned"
			elseif anyPending then
				cardState = "Pending"
			end
		end
		StoreView.setCard(view, id, key, cardState)
	end
	-- Server Luck running: how long is left (a buy adds 15 minutes)
	local left = serverLuckLeft()
	StoreView.setNote(view, "ServerLuck", if left > 0 then `On now: {math.ceil(left / 60)} min left` else "")
	local income = player:GetAttribute("IncomePerSec")
	StoreView.setCoins(view, if type(income) == "number" then income else 0)
	refreshBanner(view)
	refreshRoyal(view)
	followTab(view)
end

---------------------------------------------------------------- odds (paid random)

-- Capsule odds lines ("Name  12.5%"), with Triple Lucky when it runs.
local function capsuleLines(capsuleId: string, lucky: boolean): { string }
	local lines: { string } = {}
	for _, line in CapsuleConfig.odds(capsuleId, lucky) do
		local golem = GolemConfig.ById[line.Golem]
		local name = if golem then golem.Name else line.Golem
		table.insert(lines, `{name}:  {percent(line.Chance)}`)
	end
	return lines
end

-- Ore luck per zone the player can mine: "Rare or better" now -> with `delta` (BoostView.luckLines).
local function luckLines(delta: { [string]: number }): { string }
	return BoostView.luckLines(state(), delta, os.time())
end

-- Every segment of the Spin & Win wheel with its chance and what it gives this player (the wheel's own list).
local function wheelLines(): { string }
	local info = WheelView.info(StateController.get(), restricted())
	local lines = { "Every spin stops on one of these:" }
	for _, row in WheelView.rows(info) do
		table.insert(lines, `{row.Label}:  {row.Chance}`)
		if row.Detail ~= "" then
			table.insert(lines, "   " .. row.Detail)
		end
		local golems = row.Lines
		if golems then
			for _, golem in golems do
				table.insert(lines, `      {golem.Name}  {golem.Chance}`)
			end
		end
	end
	return lines
end

local tableLines = CardOdds.tableLines

-- The coming-soon set the boost and enchant windows use (BoostView.soonNow).
local function soonNow(): { [string]: boolean }
	return BoostView.soonNow(
		ReplicatedStorage:GetAttribute(BoostView.SoonAttribute),
		ReplicatedStorage:GetAttribute(MonetizationConfig.ReceiptsAttribute)
	)
end

-- The odds panel's lines for a paid random product (or one that opens odds: the pass's Grotto).
local function oddsFor(product: MonetizationConfig.Product): { string }
	if product.Key == "BigPass" then
		return { "The pass opens the Glimmer Grotto:", MonetizationConfig.grottoOddsText() }
	end
	if product.Capsule then
		local lucky = tripleLuckyNow()
		local head = `{product.Name}: each golem is one of (odds{if lucky then " with Triple Lucky" else ""}):`
		local lines = { head }
		for _, line in capsuleLines(product.Capsule, lucky) do
			table.insert(lines, "   " .. line)
		end
		return lines
	end
	if product.Grant == "WheelSpins" then
		return wheelLines()
	end
	if product.Boost == "TripleLucky" then
		-- every capsule it changes (coin capsules too: coins can be bought with Robux)
		local lines: { string } = {}
		for _, capsuleId in BoostView.capsules(restricted()) do
			for _, line in tableLines(BoostView.tripleOdds(capsuleId)) do
				table.insert(lines, line)
			end
		end
		return lines
	end
	if product.Boost == "HexaLucky" then
		return luckLines({ OreLuckMult = BoostConfig.Kinds.HexaLucky.Mult })
	end
	if product.ServerBoost == "Luck" then
		local left = serverLuckLeft()
		if left > 0 then
			-- running already: a buy adds time, the odds stay
			local lines = { `Server Luck is on ({math.ceil(left / 60)} min left): this adds 15 minutes, the odds stay the same.` }
			for _, line in luckLines({}) do
				table.insert(lines, line)
			end
			return lines
		end
		return luckLines({ OreLuckMult = BoostView.ServerLuckMult })
	end
	if product.Enchant then
		return CardOdds.enchantLines(state(), product.Enchant, os.time(), soonNow())
	end
	return { product.Description }
end

---------------------------------------------------------------- buying

local function buy(key: string)
	local product = MonetizationConfig.get(key)
	if not product then
		return
	end
	pending[key] = os.clock()
	asked[key] = os.clock()
	if product.Grant == "BlasterLevel" then
		local level = state().BlasterLevel
		blasterWait = { Key = key, Level = if type(level) == "number" then level else 1, Until = os.clock() + BLASTER_WAIT }
	end
	if product.Grant == "Capsule" and product.Capsule then
		Net.send("CapsuleAction", "Open", { Capsule = product.Capsule, Count = product.Count, Lucky = tripleLuckyNow() })
	elseif product.Grant == "Boost" then
		Net.send("BoostAction", "BuyRobux", { Id = key })
	elseif product.Grant == "WheelSpins" then
		Net.send("WheelAction", "Buy", { Count = product.Spins })
	else
		Net.send("StoreAction", "Buy", { Key = key })
	end
	Sfx.play("UIClick")
	refresh()
	task.delay(PROMPT_MEMORY + 0.1, refresh)
end

-- Hides the odds panel; a gamepad selection goes back to the button that opened it
-- (or the page's first), never to the HUD behind the dim.
local function hideDetail()
	local view = refs
	detailKey = nil
	if not view then
		return
	end
	StoreView.showDetail(view, nil)
	if MenuPanels.usingGamepad() then
		GuiService.SelectedObject = detailFrom or StoreView.firstSelectable(view)
	end
end

-- Buying `key` from card `id` (its face or one of its price buttons): the odds first where they apply.
local function onBuy(id: string, key: string, from: GuiObject)
	local view = refs
	local card = if view then view.Cards[id] else nil
	if not isOpen or not view or not card or card.State ~= "Buy" then
		return
	end
	local product = MonetizationConfig.Products[key]
	if not product then
		return
	end
	if StoreView.needsOdds(card.Spec, key) then
		detailKey = key
		detailFrom = from
		StoreView.showDetail(view, {
			Title = if card.Spec.Options then product.Name else (card.Spec.Title or product.Name),
			Lines = oddsFor(product),
			Robux = product.Robux,
			Paint = card.Spec.Paint,
		})
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.DetailBuy else nil
		Sfx.play("UIClick")
		return
	end
	buy(key)
end

-- A limited banner button: its odds first (a paid random capsule), then BUY.
onLimited = function(count: number)
	local view = refs
	local edition = LimitedGolems.current(serverNow())
	if not isOpen or not view or not edition or restricted() then
		return
	end
	local key = edition.Products[count]
	local product = if key then MonetizationConfig.get(key) else nil
	if not product or (pending[key] and os.clock() - pending[key] < PROMPT_MEMORY) then
		return
	end
	local banner = view.Banner
	detailKey = key
	detailFrom = if banner then banner.Buys[count] else nil
	StoreView.showDetail(view, {
		Title = product.Name,
		Lines = oddsFor(product),
		Robux = product.Robux,
		Paint = "Red",
	})
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.DetailBuy else nil
	Sfx.play("UIClick")
end

local function onPurchasePrompt(payload: any)
	if type(payload) ~= "table" or type(payload.Product) ~= "string" then
		return
	end
	local key = payload.Product :: string
	if not pending[key] then
		return -- another window's buy
	end
	pending[key] = nil
	local wait = blasterWait
	if wait and wait.Key == key and payload.Status ~= "Prompted" then
		blasterWait = nil
	end
	local view = refs
	if view and payload.Status ~= "Prompted" then
		local text = MonetizationConfig.StatusText[payload.Status] or MonetizationConfig.StatusText.Unknown
		local product = MonetizationConfig.Products[key]
		if payload.Status == "Full" and product and product.Grant == "WheelSpins" then
			-- the wheel's two "Full"s: no golem room for a bought spin's prize, or the most spins held
			text = if inventoryBlocks() then WheelConfig.Reasons.InventoryFull else WheelConfig.Reasons.MaxSpins
		end
		if isOpen then
			StoreView.setStatus(view, text)
		end
	end
	refresh()
end

---------------------------------------------------------------- the window

-- Every loop stops; everything goes back to rest.
local function stopMotion()
	ShopFx.stop(windowLoops)
	ShopFx.stop(tabLoops)
	windowLoops, tabLoops, tabPlayed = nil, nil, nil
end

-- The window's loops and the open tab's (none while the shop is quiet: ShopFx.play).
local function startMotion(view: StoreView.Refs)
	stopMotion()
	windowLoops = ShopFx.play(ShopFx.loopsUnder(view.Fx, view.Lean))
	playTab(view)
end

--[[
	Roblox's purchase prompt for `product` ended: bought, and the shop asked
	for it (a buy from a card or the banner, ASK_MEMORY) while the window is
	open: its card flashes, pops and throws stars (the server still grants
	it). Either way the shop's ask is over.
]]
local function promptEnded(product: MonetizationConfig.Product?, purchased: boolean)
	local view = refs
	if not product then
		return
	end
	local at = asked[product.Key]
	asked[product.Key] = nil
	if purchased and view and isOpen and at and os.clock() - at <= ASK_MEMORY then
		StoreView.celebrate(view, product.Key)
	end
end

-- Shows tab `id`; the gamepad selection moves to its page (an odds panel open closes first).
local function showTab(view: StoreView.Refs, id: string, select: boolean?)
	if view.Detail.Visible and view.Current ~= id then
		detailKey = nil
		StoreView.showDetail(view, nil)
	end
	-- (open: the colours fade over, the page slides in, its cards pop in; ShopFx keeps it still when quiet)
	local changed, built = StoreView.selectTab(view, id, isOpen)
	if built then
		wirePages(view)
		refresh() -- (the new page's live lines: the banner's buttons, the coins at this income)
	end
	if not changed then
		return
	end
	followTab(view)
	if select and MenuPanels.usingGamepad() then
		GuiService.SelectedObject = StoreView.firstSelectable(view)
	end
end

-- LB / RB: the tab left or right of the open one.
local function onTabs(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local view = refs
	if inputState ~= Enum.UserInputState.Begin or not isOpen or not view or view.Detail.Visible then
		return Enum.ContextActionResult.Pass
	end
	local tabs = StoreView.visibleTabs(view)
	local at = table.find(tabs, view.Current) or 1
	local step = if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
	local nextId = tabs[(at - 1 + step) % #tabs + 1]
	if nextId then
		showTab(view, nextId, true)
		Sfx.play("UIClick")
	end
	return Enum.ContextActionResult.Sink
end

-- The screen's size in design units and whether it wants the phone / TV sizes.
local function screen(): (number, number, boolean)
	local camera = workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = TechShopView.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	return size.X / scale, (size.Y - inset.Y) / scale, compact
end

-- Connects the buttons of the pages built since the last call (once each) and fills the STAR guns
-- (one a frame, like the page's other models: StoreView.SpreadModels).
wirePages = function(view: StoreView.Refs)
	local guns: { { Id: string, View: Instance } } = {}
	for _, sectionId in StoreView.takeBuilt(view) do
		for _, spec in StoreConfig.Cards do
			local card = view.Cards[spec.Id]
			if spec.Section == sectionId and card then
				local id = spec.Id
				card.Button.Activated:Connect(function()
					if card.Button.Selectable then
						onBuy(id, card.Key, card.Button)
					end
				end)
				for _, face in card.Buys do
					face.Activated:Connect(function()
						local key = face:GetAttribute("Key")
						onBuy(id, if type(key) == "string" then key else card.Key, face)
					end)
				end
				-- the STAR blasters' live guns (the Star Forge's own builder)
				local star = spec.Star
				local picture = if star then card.Picture else nil
				local viewport = if picture then picture:FindFirstChild("View") else nil
				if star and viewport then
					table.insert(guns, { Id = star, View = viewport })
				end
			end
		end
	end
	if #guns > 0 then
		task.spawn(function()
			for _, gun in guns do
				if gun.View.Parent then
					pcall(RebirthView.fillPicture, gun :: any)
					task.wait()
				end
			end
		end)
	end
end

-- Connects the window's own buttons (once each: a rebuilt window is wired again) and its first page's.
local function wire(view: StoreView.Refs)
	view.Window.Close.Activated:Connect(function()
		StoreController.close()
		Sfx.play("UIClick")
	end)
	for sectionId, tab in view.Tabs do
		tab.Activated:Connect(function()
			showTab(view, sectionId, false)
			Sfx.play("UIClick")
		end)
	end
	view.DetailBack.Activated:Connect(function()
		hideDetail()
		Sfx.play("UIClick")
	end)
	view.DetailBuy.Activated:Connect(function()
		local key = detailKey
		hideDetail()
		if key and isOpen then
			buy(key)
		end
	end)
	TouchControls.follow(view.Gui)
	wirePages(view)
end

-- Builds the window for this screen's sizes (or again when they changed).
local function build(w: number, h: number, compact: boolean): StoreView.Refs
	local _, fit = StoreView.windowSize(w, h)
	local current = if refs then (refs :: StoreView.Refs).Current else nil
	local old = refs
	if old then
		old.Gui:Destroy()
	end
	bannerFrame = nil
	stopMotion()
	-- (lazy: the open tab's page now, the others on their first visit)
	local view = StoreView.build(StoreView.metricsFor(compact, fit), true)
	-- (a TV gets the compact sizes but keeps the particles, the gloss and the small pictures' idling)
	view.Lean = compact and not GuiService:IsTenFootInterface()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	refs = view
	if current then
		StoreView.selectTab(view, current)
	end
	wire(view)
	return view
end

local function fit(view: StoreView.Refs): StoreView.Refs
	local w, h, compact = screen()
	local current = view
	if StoreView.needsRebuild(view, w, h, compact) then
		current = build(w, h, compact)
		current.Gui.Enabled = isOpen
	end
	StoreView.layout(current, w, h, compact)
	return current
end

local function ensureView(): StoreView.Refs
	if refs then
		return refs :: StoreView.Refs
	end
	local w, h, compact = screen()
	return build(w, h, compact)
end

local tickGen = 0 -- the banner timer's generation (tickBanner)

function StoreController.close()
	if not isOpen then
		return
	end
	isOpen = false
	tickGen += 1 -- (the banner's timer ends)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TABS_ACTION)
	local view = refs
	if not view then
		stopMotion()
	else
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		StoreView.showDetail(view, nil)
		local gui = view.Gui
		-- (the loops run on through the shrink, then stop: their rest look never flashes up)
		local function hide()
			if not isOpen then
				gui.Enabled = false
				stopMotion()
			end
		end
		if Motion.enabled() then
			-- (UI/ShopFx: it shrinks a little as the dim fades, then goes; an open() before the end keeps it)
			ShopFx.close(view.Group, gui:FindFirstChild("Dim") :: GuiObject?, hide)
		else
			hide() -- (UI motion off: it just goes, as on main)
		end
	end
	PromptController.setSuppressed("Store", false)
end

local function onClose(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	local view = refs
	if view and view.Detail.Visible then
		hideDetail()
	else
		StoreController.close()
	end
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

-- The banner's quiet time left while the window is open (the edition ends: it goes). One timer at a
-- time: a quick close and reopen ends the old one (its generation is gone) instead of adding another.
local function tickBanner()
	tickGen += 1
	local gen = tickGen
	task.spawn(function()
		while isOpen and gen == tickGen do
			local view = refs
			if view and view.Banner then
				local left = view.Banner.Edition.EndsAt - serverNow()
				if left <= 0 then
					refreshBanner(view)
				else
					StoreView.setTimer(view, left)
				end
			end
			task.wait(5)
		end
	end)
end

function StoreController.open()
	if isOpen then
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = fit(ensureView())
	isOpen = true
	StoreView.setStatus(view, nil)
	refresh()
	view.Gui.Enabled = true
	tickBanner()
	PromptController.setSuppressed("Store", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TABS_ACTION, onTabs, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then StoreView.firstSelectable(view) else nil
	Sfx.play("UIClick")
	startMotion(view)
	local dim = view.Gui:FindFirstChild("Dim") :: GuiObject?
	ShopFx.rest(view.Group, dim, StoreView.DimTransparency)
	if not Motion.enabled() then
		-- (UI motion off, Config/AnimConfig: the window's own pop, as on main)
		Motion.classicPop(view.Window.Root, "OpenPop", 0.85, 0.18)
		return
	end
	-- UI/ShopFx: the window pops from 0.82 with a Back ease, the dim fades in, a burst of rays
	-- flashes out behind it, the header cascades in (Reduce motion: it just shows)
	ShopFx.open(view.Group, dim, StoreView.DimTransparency, view.Burst)
	StoreView.cascade(view)
end

-- Opens the Store at a card (the round look's HUD offers): its tab shows.
function StoreController.openAt(cardId: string)
	StoreController.open()
	local view = refs
	local section = StoreConfig.sectionOf(cardId)
	if not view or not section then
		return
	end
	if StoreView.tabShown(view, section) then
		showTab(view, section, false) -- (it builds the page the first time)
	end
	local card = view.Cards[cardId]
	if not card then
		return
	end
	-- (a gamepad: the selection on the offered card, so A buys what the player picked)
	if MenuPanels.usingGamepad() and card.Holder.Visible then
		if card.Button.Selectable then
			GuiService.SelectedObject = card.Button
		else
			-- (a card with options: its first price button)
			local keys = card.Spec.Options or card.Spec.Keys
			GuiService.SelectedObject = card.Buys[keys[1]]
		end
	end
end

--[[
	Does a HUD offer show (the round look, HudBubble.Offers)? Not when the
	player owns it, the Starter Pack's offer is over, or paid random items
	are restricted for this player.
]]
local function offerShows(cardId: string): boolean
	local spec = StoreConfig.ById[cardId]
	local product = if spec then MonetizationConfig.Products[spec.Keys[1]] else nil
	if not product then
		return false
	end
	if product.Grant == "StarterPack" then
		local offer = state().StarterPack
		if type(offer) ~= "table" or offer.Open ~= true then
			return false
		end
	end
	if product.PaidRandom and restricted() then
		return false
	end
	return not owns(product)
end

local function refreshOffers()
	local hud = HudController.refs()
	local column = if hud then hud.Gui:FindFirstChild("Offers") else nil
	if not column then
		return
	end
	for _, holder in column:GetChildren() do
		if holder:IsA("GuiObject") then
			holder.Visible = offerShows(holder.Name)
		end
	end
end

function StoreController.toggle()
	if isOpen then
		StoreController.close()
	else
		StoreController.open()
	end
end

function StoreController.init()
	-- (a page's 3D models are built one a frame after it shows: a tab's first visit never stalls)
	StoreView.SpreadModels = true
	Net.listen("PurchasePrompt", onPurchasePrompt)
	-- a capsule / boost buy refused before its prompt (the odds changed, a full inventory...)
	Net.listen("ActionResult", function(result: any)
		if type(result) ~= "table" or result.Ok ~= false then
			return
		end
		local kind = if result.Action == "Capsule" then "Capsule" elseif result.Action == "Boost" then "Boost" else nil
		if not kind then
			return
		end
		local cleared = false
		for key in pending do
			local product = MonetizationConfig.Products[key]
			if product and product.Grant == kind then
				pending[key] = nil
				cleared = true
			end
		end
		local view = refs
		if cleared and view and isOpen then
			local reasons = if kind == "Capsule" then CapsuleConfig.Reasons else BoostConfig.Reasons
			local text = if type(result.Reason) == "string"
					and reasons
					and reasons[result.Reason]
				then reasons[result.Reason]
				else "Not now."
			StoreView.setStatus(view, text)
			refresh()
		end
	end)
	Net.listen("OpenUI", function(kind)
		if kind == "Store" then
			StoreController.open()
		end
	end)
end

function StoreController.start()
	if StateController.get() then
		stateAt = serverNow()
	end
	-- Reduce motion turned on or off while the shop is open: its loops start over (stopMotion puts every
	-- one back at rest; ShopFx.play gives none while the shop is quiet)
	Motion.onReducedChanged(function()
		local view = refs
		if isOpen and view then
			startMotion(view)
		end
	end)
	-- a finished purchase (any Robux prompt in the game): a confetti burst over the screen
	-- (the owner's UI pack reel, 2026-10-27); the grant itself still comes from the server.
	-- One the shop asked for: its card flashes, pops and throws stars too (promptEnded).
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, purchased)
		if purchased then
			Confetti.burst(nil, Motion.reduced())
		end
		promptEnded(MonetizationConfig.byId(productId, "Product"), purchased)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, passId, purchased)
		if purchased then
			Confetti.burst(nil, Motion.reduced())
		end
		promptEnded(MonetizationConfig.byId(passId, "GamePass"), purchased)
	end)
	-- a blaster prompt closed without a purchase: its card is buyable again
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, purchased)
		local wait = blasterWait
		local product = if wait then MonetizationConfig.get(wait.Key) else nil
		if wait and product and product.Id == productId and not purchased then
			blasterWait = nil
			if isOpen then
				refresh()
			end
		end
	end)
	-- the HUD's green Shop pill (the game HUD, HudBubble.buildGame; the round look: the red
	-- Shop button in the top row)
	local hud = HudController.refs()
	local pill = if hud then hud.Gui:FindFirstChild("ShopPill", true) else nil
	if pill and pill:IsA("GuiButton") then
		pill.Activated:Connect(StoreController.toggle)
	end
	-- the round look's offers mid-right: the Store at that card; owned ones hide
	local offers = if hud then hud.Gui:FindFirstChild("Offers") else nil
	if offers then
		for _, holder in offers:GetChildren() do
			local button = holder:FindFirstChild("Offer")
			if button and button:IsA("GuiButton") then
				local cardId = holder.Name
				button.Activated:Connect(function()
					StoreController.openAt(cardId)
				end)
			end
		end
		refreshOffers()
		player.AttributeChanged:Connect(refreshOffers) -- (the passes' Perk_ attributes)
	end
	-- the Server Luck line over the pill while it runs: "Server Luck x2 · 14:59 · thanks Kuba"
	local luckLabel = if hud then hud.Gui:FindFirstChild("ServerLuck") else nil
	if luckLabel and luckLabel:IsA("TextLabel") then
		local label = luckLabel :: TextLabel
		task.spawn(function()
			while label.Parent do
				local left = serverLuckLeft()
				label.Visible = left > 0
				if left > 0 then
					local by = ReplicatedStorage:GetAttribute("ServerLuckBy")
					local clock = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
					local short = hud and hud.Gui:GetAttribute("ShortLuck") == true
					label.Text = `Server Luck x{BoostView.ServerLuckMult} · {clock}`
						.. (if not short and type(by) == "string" and by ~= "" then ` · thanks {by}` else "")
				end
				task.wait(if left > 0 then 0.5 else 2)
			end
		end)
	end
	StateController.onChanged(function()
		stateAt = serverNow()
		refreshOffers()
		if isOpen then
			refresh()
			-- the odds panel follows the State too (a boost started or ran out)
			local view = refs
			local key = detailKey
			if view and key and view.Detail.Visible then
				local product = MonetizationConfig.Products[key]
				view.DetailLines.Text = table.concat(oddsFor(product), "\n")
			end
		end
	end)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(refresh)
	player:GetAttributeChangedSignal("IncomePerSec"):Connect(function()
		if isOpen then
			refresh()
		end
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local view = refs
		if view and isOpen then
			local now = fit(view)
			if now ~= view then
				refresh()
				startMotion(now)
			end
		end
	end)
end

return StoreController
