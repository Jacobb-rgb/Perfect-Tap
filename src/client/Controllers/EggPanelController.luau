--[[
	EggPanelController: the eggs in the EGGS temple in the clean look and
	flow of the owner's two egg-game pictures (2026-10-28: "what we have now
	I almost don't like at all; I want it like this, it feels cleaner"). No
	window: walk up to an egg, see what is inside, press E.

	- The panel (UI/EggPanel, one BillboardGui in PlayerGui): over the egg
	  you are nearest to within EggPanel.ShowRange (EggPanel.nearest keeps
	  it a little longer, so it never flickers between two eggs); it pops in
	  (Reduce motion: a straight fade) and fades out when you walk away. The
	  other eggs stay clean. Hidden while a window (MenuPanels) is open.
	- Its content (refreshed every Refresh seconds and on every State push):
	  the price from CapsuleController.quote (the capsule window's own card:
	  coins at the player's price level, red while they can't pay it; the
	  Royal egg's Robux price, "Coming soon" while its product isn't live;
	  "Not available" where paid random items are restricted or the policy
	  isn't known yet), Auto (coin eggs) and a card per golem with the exact
	  chance the server rolls (Triple Lucky's while it runs: quote().Lucky,
	  CapsuleView.luckyNow). Golems the player has none of are black
	  silhouettes on coin eggs (EggPanel.known: the inventory is all the save
	  tracks, so a deleted kind goes dark again; Robux eggs show every golem).
	- "Buy Egg!" (a stock prompt per egg, PromptConfig "Main": E / gamepad Y
	  / a tap; its object text the price): ONE egg through
	  CapsuleController.buy, the window's own OPEN 1 request (the cooldown,
	  the local refusals as toasts, CapsuleAction "Open" with the odds the
	  panel shows, the server's rules, then the same opening). The Royal egg
	  goes the same way into the Robux purchase (PurchasePrompt) or says
	  "Coming soon!". Only the egg whose panel shows has its prompts on, so
	  its odds are always on screen before a buy.
	- Auto (coin eggs only, never a Robux egg: EggPanel.autoAllowed): the
	  panel's toggle (click / tap) or its stock prompt (PromptConfig
	  "Second": G / gamepad B / a tap; the toggle's badge shows the key).
	  On, it opens one egg, waits for the result and AutoDwell seconds of
	  its end screen, then the next (CapsuleConfig.ClientCooldown and the
	  server's CapsuleAction rate limit always hold: one open at a time).
	  It stops when you walk away (the panel moves or hides), when a refusal
	  comes (no coins, a full golem inventory, the server's own: buy's toast
	  says why), when you close an opening's end screen (OK / B) or a window
	  opens, and when you respawn. After the odds change it waits
	  LuckySettle seconds so the new odds are on the panel first.
	The capsule window (CapsuleView: every egg, x3 / x10, the golems' names)
	stays one button away: the golem inventory's EGGS.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyLayout = require(Shared.Config.LobbyLayout)
local PromptConfig = require(Shared.Config.PromptConfig)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local EggPanel = require(script.Parent.Parent.UI.EggPanel)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CapsuleController = require(script.Parent.CapsuleController)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local EggPanelController = {}

EggPanelController.Tick = 0.1 -- seconds between two looks at where the player stands
EggPanelController.Refresh = 0.5 -- seconds between two refreshes of the shown panel (coins, the boost's clock)
EggPanelController.AutoDwell = 1.2 -- seconds the end screen shows a golem before Auto opens the next
EggPanelController.LuckySettle = 1 -- Auto waits this long after the panel's odds changed
EggPanelController.FadeIn = 0.18
EggPanelController.FadeOut = 0.15
EggPanelController.PopFrom = 0.82 -- the pop-in's first scale (not with Reduce motion)

local STALL_TAG = "CapsuleStall"

type Spot = {
	Id: string,
	Point: Attachment, -- the prompts (in front of the egg, at its middle)
	Anchor: Attachment, -- the panel (over the egg's top)
	Buy: ProximityPrompt,
	Auto: ProximityPrompt?,
}
type Picture = { Model: Model?, Center: Vector3, Radius: number }

local player = Players.LocalPlayer
local spots: { [string]: Spot } = {}
local spotList: { EggPanel.Spot } = {} -- (EggPanel.nearest's input: id and centre)
local refs: EggPanel.Refs? = nil
local current: string? = nil -- the egg whose panel shows
local laidOut = "" -- the egg and device the panel was laid out for
local linesEgg: string? = nil -- the egg the cards show
local linesVersion = -1 -- the known golems they show (knownVersion)
local shownLucky = false -- the odds the panel shows (true: Triple Lucky's)
local luckySince = 0 -- os.clock() when those odds came on screen
local sellable = false -- the shown egg can be bought by this player here
local known: { [string]: boolean } = {}
local knownVersion = 0
local knownDirty = true -- a State push came: recount the golems the player has
local autoEgg: string? = nil
local pictures: { [string]: Picture } = {}
local fade: NumberValue? = nil
local fadeTween: Tween? = nil
local popTween: Tween? = nil
local front = Vector3.new(1, 0, 0)

local function isTouch(): boolean
	return MenuPanels.isTouch()
end

-- Is a window open (the panel hides and Auto stops)?
local function windowOpen(): boolean
	for _, name in MenuPanels.Names do
		if MenuPanels.isOpen(name) then
			return true
		end
	end
	return false
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or (humanoid and humanoid.Health <= 0) then
		return nil
	end
	return root.Position
end

---------------------------------------------------------------- the pictures

-- A golem's model for the cards, built once per kind and kept (framed once).
local function modelFor(kind: string): (Model?, Vector3, number)
	local cached = pictures[kind]
	if not cached then
		local ok, made = pcall(GolemBuilder.build, kind)
		local model: Model? = if ok then made else nil
		local center, radius = Vector3.zero, 1
		if model then
			center, radius = EggPanel.bounds(model)
		end
		cached = { Model = model, Center = center, Radius = radius }
		pictures[kind] = cached
	end
	return cached.Model, cached.Center, cached.Radius
end

---------------------------------------------------------------- the panel

local function ensurePanel(): EggPanel.Refs
	local existing = refs
	if existing then
		return existing
	end
	local r = EggPanel.build()
	r.Gui.Parent = player:WaitForChild("PlayerGui")
	local value = Instance.new("NumberValue")
	value.Name = "EggPanelFade"
	value.Value = 1
	value.Changed:Connect(function(alpha: number)
		local panel = refs
		if panel then
			EggPanel.setFade(panel, alpha)
		end
	end)
	fade = value
	EggPanel.setFade(r, 1)
	r.Toggle.Activated:Connect(function()
		local id = current
		if id then
			EggPanelController.toggleAuto(id)
		end
	end)
	refs = r
	return r
end

-- The key on Auto's badge: the keyboard letter, the gamepad's glyph, nothing on touch.
local function autoKey(): (string, string?)
	local keys = PromptConfig.keys("Second")
	if MenuPanels.usingGamepad() then
		local image = MenuPanels.glyph(keys.Gamepad)
		return if image ~= "" then "" else MenuPanels.padName(keys.Gamepad), if image ~= "" then image else nil
	elseif isTouch() then
		return "", nil
	end
	return keys.Keyboard.Name, nil
end

-- The prompts of every egg: on only for the egg whose panel shows and can be bought.
local function updatePrompts()
	local panelUp = current ~= nil and refs ~= nil and fade ~= nil
	for id, spot in spots do
		local on = panelUp and id == current and sellable
		spot.Buy.Enabled = on
		local auto = spot.Auto
		if auto then
			auto.Enabled = on and EggPanel.autoAllowed(id)
			auto.ObjectText = if autoEgg == id then "On" else "Off"
		end
	end
end

local function buyOf(card: any): any
	if type(card) ~= "table" or type(card.Buys) ~= "table" then
		return nil
	end
	for _, b in card.Buys do
		if b.Count == 1 then
			return b
		end
	end
	return nil
end

-- Fills the shown panel: the cards (when the egg, its odds or the golems
-- the player has changed), the price, Auto and the Triple Lucky tag.
local function refreshPanel()
	local r = refs
	local id = current
	if not r or not id then
		return
	end
	if knownDirty then
		knownDirty = false
		local now = EggPanel.known(StateController.get())
		local changed = false
		for kind in now do
			changed = changed or not known[kind]
		end
		for kind in known do
			changed = changed or not now[kind]
		end
		known = now
		if changed then
			knownVersion += 1
		end
	end
	local card = CapsuleController.quote(id)
	local lucky = card ~= nil and card.Lucky == true
	if id ~= linesEgg or lucky ~= shownLucky or linesVersion ~= knownVersion then
		if id ~= linesEgg or lucky ~= shownLucky then
			luckySince = os.clock() -- (other odds on screen: a new egg, or the boost began / ended)
		end
		linesEgg, linesVersion, shownLucky = id, knownVersion, lucky
		EggPanel.setLines(r, EggPanel.lines(id, lucky, known), modelFor)
	end
	local buy = buyOf(card)
	sellable = card ~= nil and card.Visible == true and buy ~= nil
	local spot = spots[id]
	if not card or not card.Visible or not buy then
		EggPanel.setPrice(r, "Off", "Not available", false)
	elseif card.Robux then
		local live = buy.Reason ~= "ComingSoon"
		EggPanel.setPrice(r, if live then "Robux" else "Off", if live then buy.PriceText else "Coming soon", true)
		if spot then
			spot.Buy.ObjectText = EggPanel.promptText(true, nil, buy.PriceText, live)
		end
	else
		EggPanel.setPrice(r, "Coins", EggPanel.priceText(buy.Price or 0), buy.Reason ~= "NoCoins")
		if spot then
			spot.Buy.ObjectText = EggPanel.promptText(false, buy.Price, buy.PriceText, true)
		end
	end
	local autoShown = sellable and EggPanel.autoAllowed(id)
	local text, image = autoKey()
	EggPanel.setAuto(r, autoShown, autoEgg == id, text, image)
	EggPanel.setLucky(r, lucky, autoShown)
	updatePrompts()
end

-- Lays the panel out for the egg and the device (again when either changed).
local function layOut(r: EggPanel.Refs, id: string)
	local touch = isTouch()
	local scale = HudController.uiScale()
	local key = `{id}|{touch}|{scale}`
	if key == laidOut then
		return
	end
	laidOut = key
	local count = #EggPanel.lines(id, false, known)
	EggPanel.apply(r, id, EggPanel.layout(count, touch), scale)
	linesEgg = nil
end

local function fadeTo(target: number, seconds: number)
	local value = fade
	if not value then
		return
	end
	if fadeTween then
		fadeTween:Cancel()
	end
	local tween = TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	fadeTween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		local r = refs
		if state == Enum.PlaybackState.Completed and target >= 1 and r and current == nil then
			r.Gui.Enabled = false
		end
	end)
	tween:Play()
end

local function show(id: string)
	local spot = spots[id]
	if not spot then
		return
	end
	local r = ensurePanel()
	local switching = r.Gui.Enabled and r.Gui.Adornee ~= spot.Anchor
	layOut(r, id)
	r.Gui.Adornee = spot.Anchor
	r.Gui.Enabled = true
	refreshPanel()
	local value = fade
	if value and switching then
		value.Value = 1 -- (another egg: its panel comes in fresh)
	end
	fadeTo(0, EggPanelController.FadeIn)
	local scale = r.Scale.Scale
	if popTween then
		popTween:Cancel()
		popTween = nil
	end
	local full = HudController.uiScale()
	if Motion.reduced() then
		r.Scale.Scale = full -- (Reduce motion: a straight fade, no bounce)
	else
		r.Scale.Scale = math.min(scale, full * EggPanelController.PopFrom)
		local tween = TweenService:Create(r.Scale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = full })
		popTween = tween
		tween:Play()
	end
	Sfx.play("UIClick")
end

local function hide()
	fadeTo(1, EggPanelController.FadeOut)
end

---------------------------------------------------------------- Auto

local function stopAuto()
	if not autoEgg then
		return
	end
	autoEgg = nil
	CapsuleController.setAuto(false)
	refreshPanel()
	updatePrompts()
end

-- Auto on / off for the shown egg (coin eggs only).
function EggPanelController.toggleAuto(id: string)
	if autoEgg == id then
		stopAuto()
		Sfx.play("UIClick")
		return
	end
	if id ~= current or not sellable or not EggPanel.autoAllowed(id) then
		return
	end
	autoEgg = id
	CapsuleController.setAuto(true)
	Sfx.play("UIClick")
	refreshPanel()
	updatePrompts()
end

-- One step of Auto: the next egg when the last one's end screen has shown long enough.
local function autoStep()
	local id = autoEgg
	if not id then
		return
	end
	if current ~= id or not sellable then
		stopAuto() -- (walked away, or it can't be bought here any more)
		return
	end
	local where, endFor = CapsuleController.openingState()
	if where == "Waiting" or where == "Playing" then
		return
	end
	if where == "End" and endFor < EggPanelController.AutoDwell then
		return
	end
	if os.clock() - luckySince < EggPanelController.LuckySettle then
		return -- (new odds: on the panel first)
	end
	local card = CapsuleController.quote(id)
	if card and card.Lucky ~= shownLucky then
		refreshPanel() -- (the boost began or ended: the new odds show, then Auto goes on)
		return
	end
	local sent, reason = CapsuleController.buy(id, shownLucky, true)
	if not sent and reason ~= "Busy" and reason ~= "Cooldown" then
		stopAuto() -- (buy's toast said why: no coins, a full golem inventory...)
	end
end

---------------------------------------------------------------- the eggs

local function addEgg(id: string, model: Model)
	if spots[id] then
		return
	end
	local center, top, promptAt = EggPanel.spotOf(model, front)
	local terrain = Workspace.Terrain
	local point = Instance.new("Attachment")
	point.Name = "EggPrompts" .. id
	point.Position = promptAt
	point.Parent = terrain
	local anchor = Instance.new("Attachment")
	anchor.Name = "EggPanel" .. id
	anchor.Position = Vector3.new(center.X, top + EggPanel.Lift, center.Z)
	anchor.Parent = terrain
	local buy = PromptConfig.make({
		Name = "EggBuyPrompt",
		ActionText = "Buy Egg!",
		ObjectText = "",
		Distance = EggPanel.PromptDistance,
		Enabled = false,
		Parent = point,
	})
	buy.Triggered:Connect(function()
		EggPanelController.buy(id)
	end)
	local auto: ProximityPrompt? = nil
	if EggPanel.autoAllowed(id) then
		local made = PromptConfig.make({
			Role = "Second",
			Name = "EggAutoPrompt",
			ActionText = "Auto",
			ObjectText = "Off",
			Distance = EggPanel.PromptDistance,
			Slot = 1,
			Enabled = false,
			Parent = point,
		})
		made.Triggered:Connect(function()
			EggPanelController.toggleAuto(id)
		end)
		auto = made
	end
	spots[id] = { Id = id, Point = point, Anchor = anchor, Buy = buy, Auto = auto }
	table.insert(spotList, { Id = id, Center = center })
end

-- "Buy Egg!": one egg with the odds on the panel (refused when they just changed).
function EggPanelController.buy(id: string)
	if id ~= current or not sellable then
		return
	end
	-- (the odds the panel shows: refused "OddsChanged" when the boost began or
	-- ended this moment; then the panel shows the new ones)
	local _sent, reason = CapsuleController.buy(id, shownLucky, false)
	if reason == "OddsChanged" then
		refreshPanel()
	end
end

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A stall streams in part by part (the eggs are atomic models): take each egg as it comes.
local function watchStall(stall: Instance)
	for id, model in EggPanel.eggsIn(stall) do
		addEgg(id, model)
	end
	if watched[stall] then
		return
	end
	watched[stall] = true
	stall.DescendantAdded:Connect(function(d: Instance)
		local id = EggPanel.eggId(d)
		if id and not spots[id] then
			-- (the egg's parts come with it: atomic; a frame later to be safe)
			task.defer(function()
				if d.Parent then
					addEgg(id, d :: Model)
				end
			end)
		end
	end)
end

---------------------------------------------------------------- the loop

local function tick()
	local position = rootPosition()
	local target: string? = nil
	if position and not windowOpen() then
		target = EggPanel.nearest(spotList, position, current)
	end
	if target ~= current then
		if autoEgg and target ~= autoEgg then
			stopAuto()
		end
		current = target
		if target then
			show(target)
		else
			sellable = false
			hide()
		end
		updatePrompts()
	end
	autoStep()
end

function EggPanelController.init()
	local ok, piece = pcall(LobbyLayout.get, "CapsuleStall")
	if ok and piece then
		front = LobbyLayout.frame(piece).LookVector -- (the temple's front: toward the plaza)
	end
	StateController.onChanged(function()
		knownDirty = true
		if current then
			refreshPanel()
		end
	end)
	CapsuleController.onStop(function(_reason: string)
		stopAuto() -- (the end screen was closed, or the server refused: its own message says why)
	end)
	player.CharacterRemoving:Connect(function()
		stopAuto()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local r = refs
		local id = current
		if r and id then
			layOut(r, id)
			refreshPanel()
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local r = refs
			local id = current
			if r and id then
				layOut(r, id)
				refreshPanel()
			end
		end)
	end
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
		if current then
			refreshPanel()
		end
	end)
end

function EggPanelController.start()
	for _, stall in CollectionService:GetTagged(STALL_TAG) do
		watchStall(stall)
	end
	CollectionService:GetInstanceAddedSignal(STALL_TAG):Connect(watchStall)
	local elapsed, sinceRefresh = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		sinceRefresh += dt
		if elapsed < EggPanelController.Tick then
			return
		end
		elapsed = 0
		tick()
		if current and sinceRefresh >= EggPanelController.Refresh then
			sinceRefresh = 0
			refreshPanel()
		end
	end)
end

return EggPanelController
