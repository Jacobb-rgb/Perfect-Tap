--[[
	The Robux Shop window (owner 2026-10-20; the bright egg-game look the same
	evening): opened by the side menu's STORE entry, the HUD's green Shop
	button and OpenUI "Store". A section tab scrolls the list to its section.

	- A card buys its product (StoreView.setCard picks which: the blaster
	  shows the price band of the player's next level, hidden at the top).
	  By the product's Grant:
	    Capsule  CapsuleAction "Open" { Capsule, Count, Lucky } (the
	             capsule service remembers the odds the player saw)
	    Boost    BoostAction "BuyRobux" { Id }
	    others   StoreAction "Buy" { Key } (StoreService)
	  Every buy is answered with PurchasePrompt { Product, Status }; the card
	  greys out until then (PROMPT_MEMORY seconds at most).
	- Paid random products (MonetizationConfig PaidRandom) show their exact
	  odds first (the odds panel: capsule odds, or the ore luck per zone
	  now and with the buy); they are hidden where the player's policy
	  restricts paid random items (the PaidRandomRestricted attribute).
	- Coin cards show the coins at the player's podium income now.
]]

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local StoreView = require(script.Parent.Parent.UI.StoreView)
local BoostView = require(script.Parent.Parent.UI.BoostView)
local RebirthView = require(script.Parent.Parent.UI.RebirthView)
local CapsuleView = require(script.Parent.Parent.UI.CapsuleView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local CardOdds = require(script.Parent.Parent.UI.CardOdds)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local PromptController = require(script.Parent.PromptController)

local StoreController = {}

local NAME = "StoreController"
local CLOSE_ACTION = "TerraForgeStoreClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local PROMPT_MEMORY = 10 -- seconds a buy waits for its PurchasePrompt answer
local BLASTER_WAIT = 30 -- seconds the blaster card stays greyed after its prompt (until the level changes)

local player = Players.LocalPlayer
local refs: StoreView.Refs? = nil
local isOpen = false
local pending: { [string]: number } = {} -- product key -> os.clock() of the buy
local detailKey: string? = nil
local detailFrom: GuiObject? = nil -- the card that opened the odds panel (BACK selects it again)
local stateAt: number? = nil -- server time of the last State (CapsuleView.luckyNow)
-- a blaster level bought: its card stays greyed until the level changes (or BLASTER_WAIT)
local blasterWait: { Key: string, Level: number, Until: number }? = nil
local bannerFrame: Frame? = nil -- the limited banner whose buttons are wired

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
	local text = string.format("%.2f", chance * 100)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
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

-- (defined below: the banner's buttons open the odds panel)
local onLimited: (count: number) -> ()

--[[
	The limited edition banner at the top of FEATURED (LimitedGolems.current):
	shown while it runs and the player may buy paid random items; its buttons
	open the odds panel first (onLimited), its countdown follows the server clock.
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

-- Which product each card shows and its state.
local function refresh()
	local view = refs
	if not view then
		return
	end
	local now = os.clock()
	local level = state().BlasterLevel
	for id, card in view.Cards do
		local spec = card.Spec
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
				StoreView.setBig(view, id, `LV {current + 1}`)
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
			if cardState == "Pending" or cardState == "Locked" then
				-- (the blaster: waiting for its level, or LV 10 before a forged level)
			elseif product.PaidRandom and restricted() then
				cardState = "Hidden"
			elseif owns(product) then
				cardState = "Owned"
			elseif pending[key] and now - pending[key] < PROMPT_MEMORY then
				cardState = "Pending"
			end
		end
		StoreView.setCard(view, id, key, cardState)
	end
	local income = player:GetAttribute("IncomePerSec")
	StoreView.setCoins(view, if type(income) == "number" then income else 0)
	refreshBanner(view)
end

---------------------------------------------------------------- odds (paid random)

-- Capsule odds lines ("Name  12.5%"), with Triple Lucky when it runs.
local function capsuleLines(capsuleId: string, lucky: boolean, compareLucky: boolean?): { string }
	local lines: { string } = {}
	local now = CapsuleConfig.odds(capsuleId, lucky)
	local after = if compareLucky then CapsuleConfig.odds(capsuleId, true) else nil
	for i, line in now do
		local golem = GolemConfig.ById[line.Golem]
		local name = if golem then golem.Name else line.Golem
		if after and after[i] then
			table.insert(lines, `{name}:  {percent(line.Chance)}  →  {percent(after[i].Chance)}`)
		else
			table.insert(lines, `{name}:  {percent(line.Chance)}`)
		end
	end
	return lines
end

-- Ore luck per zone the player can mine: "Rare or better" now -> with `delta`.
local function luckLines(delta: { [string]: number }): { string }
	local ctx = BoostView.context(state(), os.time())
	local preview = BoostConfig.preview(ctx, delta)
	local lines: { string } = { "Chance a chunk is Rare or better:" }
	for _, zone in preview.Zones do
		if not zone.NoEffect then
			local info = WorldLayout.ZoneById[zone.Zone]
			table.insert(lines, `{if info then info.Name else zone.Zone}:  {percent(zone.Before)}  →  {percent(zone.After)}`)
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
		return luckLines({ OreLuckMult = 2 })
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
	if product.Grant == "BlasterLevel" then
		local level = state().BlasterLevel
		blasterWait = { Key = key, Level = if type(level) == "number" then level else 1, Until = os.clock() + BLASTER_WAIT }
	end
	if product.Grant == "Capsule" and product.Capsule then
		Net.send("CapsuleAction", "Open", { Capsule = product.Capsule, Count = product.Count, Lucky = tripleLuckyNow() })
	elseif product.Grant == "Boost" then
		Net.send("BoostAction", "BuyRobux", { Id = key })
	else
		Net.send("StoreAction", "Buy", { Key = key })
	end
	Sfx.play("UIClick")
	refresh()
	task.delay(PROMPT_MEMORY + 0.1, refresh)
end

-- Hides the odds panel; a gamepad selection goes back to the card that opened it
-- (or the first card), never to the HUD behind the dim.
local function hideDetail()
	local view = refs
	detailKey = nil
	if not view then
		return
	end
	StoreView.showDetail(view, nil)
	if MenuPanels.usingGamepad() then
		local first = view.Cards[view.Order[1]]
		GuiService.SelectedObject = detailFrom or (if first then first.Button else nil)
	end
end

local function onCard(id: string)
	local view = refs
	local card = if view then view.Cards[id] else nil
	if not isOpen or not view or not card or not card.Button.Active then
		return
	end
	local product = MonetizationConfig.Products[card.Key]
	if product.PaidRandom or card.Spec.Odds then
		detailKey = card.Key
		detailFrom = card.Button
		StoreView.showDetail(view, {
			Title = card.Spec.Title or product.Name,
			Lines = oddsFor(product),
			Robux = product.Robux,
			Paint = card.Spec.Paint,
		})
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.DetailBuy else nil
		Sfx.play("UIClick")
		return
	end
	buy(card.Key)
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
		if isOpen then
			StoreView.setStatus(view, text)
		end
	end
	refresh()
end

---------------------------------------------------------------- the window

local function fit(view: StoreView.Refs)
	local camera = workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = TechShopView.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	StoreView.layout(view, size.X / scale, (size.Y - inset.Y) / scale, compact)
end

local function ensureView(): StoreView.Refs
	if refs then
		return refs :: StoreView.Refs
	end
	local view = StoreView.build()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Window.Close.Activated:Connect(function()
		StoreController.close()
		Sfx.play("UIClick")
	end)
	for id, card in view.Cards do
		card.Button.Activated:Connect(function()
			onCard(id)
		end)
		card.Price.Activated:Connect(function()
			onCard(id)
		end)
	end
	-- a section tab scrolls the list to its section
	for sectionId, tab in view.Tabs do
		tab.Activated:Connect(function()
			local target = Vector2.new(0, StoreView.sectionTop(view, sectionId))
			TweenService
				:Create(view.Scroller, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target })
				:Play()
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
	-- the STAR blasters' live guns (the Star Forge's own builder)
	for _, card in view.Cards do
		local star = card.Spec.Star
		local picture = if star then card.Button:FindFirstChild("Picture") else nil
		local viewport = if picture then picture:FindFirstChild("View") else nil
		if star and viewport then
			pcall(RebirthView.fillPicture, { Id = star, View = viewport } :: any)
		end
	end
	refs = view
	return view
end

function StoreController.close()
	if not isOpen then
		return
	end
	isOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		StoreView.showDetail(view, nil)
		-- (UI/Motion: it shrinks away first, an open() before the end cancels that;
		-- with UI motion off it just goes, as on main)
		local gui = view.Gui
		Motion.close(view.Group, function()
			if not isOpen then
				gui.Enabled = false
			end
		end, gui:FindFirstChild("Dim") :: GuiObject?)
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

-- The banner's quiet time left while the window is open (the edition ends: it goes).
local function tickBanner()
	task.spawn(function()
		while isOpen do
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
	local view = ensureView()
	isOpen = true
	fit(view)
	StoreView.setStatus(view, nil)
	refresh()
	view.Gui.Enabled = true
	tickBanner()
	PromptController.setSuppressed("Store", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local first = view.Cards[view.Order[1]]
	GuiService.SelectedObject = if MenuPanels.usingGamepad() and first then first.Button else nil
	Sfx.play("UIClick")
	if not Motion.enabled() then
		-- (UI motion off, Config/AnimConfig: the window's own pop, as on main)
		Motion.classicPop(view.Window.Root, "OpenPop", 0.85, 0.18)
		return
	end
	-- UI/Motion: the window and its tabs pop from the middle (the Group is centred),
	-- the dim fades in, the tab column slides in from the right
	Motion.pop(view.Group, view.Gui:FindFirstChild("Dim") :: GuiObject?)
	local tabs = view.Group:FindFirstChild("Tabs") :: GuiObject?
	if tabs then
		Motion.slide(tabs, "Right", 36)
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
	-- the HUD's green Shop pill (the game HUD, HudBubble.buildGame)
	local hud = HudController.refs()
	local pill = if hud then hud.Gui:FindFirstChild("ShopPill") else nil
	if pill and pill:IsA("GuiButton") then
		pill.Activated:Connect(StoreController.toggle)
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
			fit(view)
		end
	end)
end

return StoreController
