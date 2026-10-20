--[[
	The Robux STORE window (owner 2026-10-20): opened by the side menu's
	STORE entry, the HUD's green Shop button and OpenUI "Store".

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
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local StoreView = require(script.Parent.Parent.UI.StoreView)
local BoostView = require(script.Parent.Parent.UI.BoostView)
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

local player = Players.LocalPlayer
local refs: StoreView.Refs? = nil
local isOpen = false
local pending: { [string]: number } = {} -- product key -> os.clock() of the buy
local detailKey: string? = nil

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
	return false
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
			if fits then
				key = fits
				local current = if type(level) == "number" then math.floor(level) else 1
				StoreView.setBig(view, id, `LV {current + 1}`)
			else
				cardState = "Hidden"
			end
		end
		local product = MonetizationConfig.Products[key]
		if cardState ~= "Hidden" then
			if product.PaidRandom and restricted() then
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

local function tripleLuckyNow(): boolean
	local bonuses = state().Bonuses
	return type(bonuses) == "table" and type(bonuses.CapsuleLuckMult) == "number" and bonuses.CapsuleLuckMult > 1
end

-- The odds panel's lines for a paid random product.
local function oddsFor(product: MonetizationConfig.Product): { string }
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
		local lines = { "Royal Capsule odds now → with Triple Lucky:" }
		for _, line in capsuleLines("Royal", false, true) do
			table.insert(lines, "   " .. line)
		end
		return lines
	end
	if product.Boost == "HexaLucky" then
		return luckLines({ OreLuckMult = BoostConfig.Kinds.HexaLucky.Mult })
	end
	if product.ServerBoost == "Luck" then
		return luckLines({ OreLuckMult = 2 })
	end
	if product.Enchant then
		return luckLines(EnchantConfig.nextDelta(state().Enchants, state().BlasterLevel or 1, product.Enchant))
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

local function onCard(id: string)
	local view = refs
	local card = if view then view.Cards[id] else nil
	if not view or not card or not card.Button.Active then
		return
	end
	local product = MonetizationConfig.Products[card.Key]
	if product.PaidRandom then
		detailKey = card.Key
		StoreView.showDetail(view, {
			Title = card.Spec.Title or product.Name,
			Lines = oddsFor(product),
			Robux = product.Robux,
			Glow = card.Spec.Glow,
		})
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.DetailBuy else nil
		Sfx.play("UIClick")
		return
	end
	buy(card.Key)
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
	StoreView.layout(view, size.X / scale, (size.Y - inset.Y) / scale)
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
	end
	view.DetailBack.Activated:Connect(function()
		detailKey = nil
		StoreView.showDetail(view, nil)
		Sfx.play("UIClick")
	end)
	view.DetailBuy.Activated:Connect(function()
		local key = detailKey
		detailKey = nil
		StoreView.showDetail(view, nil)
		if key then
			buy(key)
		end
	end)
	TouchControls.follow(view.Gui)
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
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Store", false)
end

local function onClose(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	local view = refs
	if view and view.Detail.Visible then
		detailKey = nil
		StoreView.showDetail(view, nil)
	else
		StoreController.close()
	end
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
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
	PromptController.setSuppressed("Store", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local first = view.Cards[view.Order[1]]
	GuiService.SelectedObject = if MenuPanels.usingGamepad() and first then first.Button else nil
	Sfx.play("UIClick")
	local pop = view.Window.Root:FindFirstChild("OpenPop") :: UIScale?
	if not pop then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Window.Root
		pop = made
	end
	local s = pop :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	Net.listen("OpenUI", function(kind)
		if kind == "Store" then
			StoreController.open()
		end
	end)
end

function StoreController.start()
	-- the HUD's green Shop pill (the game HUD, HudBubble.buildGame)
	local hud = HudController.refs()
	local pill = if hud then hud.Gui:FindFirstChild("ShopPill") else nil
	if pill and pill:IsA("GuiButton") then
		pill.Activated:Connect(StoreController.toggle)
	end
	StateController.onChanged(function()
		if isOpen then
			refresh()
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
