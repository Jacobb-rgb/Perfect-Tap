--[[
	EggPanelController: the eggs in the EGGS temple in the clean look and
	flow of the owner's two egg-game pictures (2026-10-28: "what we have now
	I almost don't like at all; I want it like this, it feels cleaner"; round
	2: "yes, a big E; make it even cooler; add opening by 10"). No window:
	walk up to an egg, see what is inside, press E.

	- The panel (UI/EggPanel, one BillboardGui in PlayerGui): over the egg
	  you are nearest to within EggPanel.ShowRange (EggPanel.nearest keeps
	  it a little longer, so it never flickers between two eggs); it pops in,
	  its cards one after another, and fades out when you walk away. The
	  other eggs stay clean. Hidden while a window (MenuPanels) is open.
	- Its content (refreshed every Refresh seconds and on every State push):
	  the price from CapsuleController.quote (the capsule window's own card:
	  coins at the player's price level, red while they can't pay it, counting
	  to a new price; the Royal egg's Robux price, "Coming soon" while its
	  product isn't live; "Not available" where paid random items are
	  restricted or the policy isn't known yet), Auto (coin eggs), a card per
	  golem with the exact chance the server rolls (Triple Lucky's while it
	  runs: quote().Lucky, CapsuleView.luckyNow) and Open 1 / 3 / 10 with
	  their prices (the window's buys; grey when they can't be bought, a click
	  still says why). Golems the player has none of are black silhouettes on
	  coin eggs (EggPanel.known: the inventory is all the save tracks, so a
	  deleted kind goes dark again; Robux eggs show every golem); a card that
	  lights up because its golem just woke pops and the egg sparkles.
	- "Buy Egg!" (a prompt per egg, PromptConfig "Main": E / gamepad Y / a
	  tap) drawn as the big round E (UI/EggPrompt: Style Custom on these
	  prompts only, EggPanel.BigE, the one exception
	  tests/PromptKeys.spec.luau allows; the keys, the trigger and the
	  touch hold stay Roblox's own, the disc's tap calls InputHoldBegin).
	  It opens ONE egg through CapsuleController.buy, the window's own
	  request (the cooldown, the local refusals as toasts, CapsuleAction
	  "Open" with the odds the panel shows, the server's rules, then the
	  same opening). Open 3 and Open 10 are the panel's buttons (click /
	  tap; keyboard R and X, free at the temple: R and X are bound only in
	  build mode, on the plot; the gamepad has no free button, every one is
	  bound already: its Open 3 / 10 are the buttons through Roblox's own UI
	  navigation, or the golem inventory's EGGS window). The Royal egg goes
	  the same way into the Robux purchase (PurchasePrompt) or says "Coming
	  soon!". Only the egg whose panel shows has its prompts and keys on, so
	  its odds are always on screen before a buy (the Royal egg's before its
	  Robux prompt).
	- Auto (coin eggs only, never a Robux egg: EggPanel.autoAllowed), one
	  egg at a time: the panel's toggle (click / tap) or its prompt
	  (PromptConfig "Second": G / gamepad B, no drawing of its own: the
	  toggle's badge shows the key). On, it opens one egg, waits for the
	  result and AutoDwell seconds of its end screen, then the next
	  (CapsuleConfig.ClientCooldown and the server's CapsuleAction rate limit
	  always hold: one open at a time). It stops when you walk away (the
	  panel moves or hides), when a refusal comes (no coins, a full golem
	  inventory, the server's own: buy's toast says why), when you close an
	  opening's end screen (OK / B) or a window opens, and when you respawn.
	  After the odds change it waits LuckySettle seconds so the new odds are
	  on the panel first.
	- Cool (none of it with Reduce motion, Motion.reduced(): then things
	  only fade): the egg hops and wobbles once with a sparkle when its panel
	  comes up (DecorController.bounce, Vfx Glint), a soft ring of light on
	  its podium breathes, the cards pop in one after another, Epic+ golems
	  have a turning ray burst, Legendary+ cards a breathing glow and a
	  gently bobbing golem, the price chip flashes red twice when you can't
	  pay, and the big E breathes, shines and squashes when pressed. All of
	  it TweenService tweens made when the panel shows (nothing per frame),
	  cancelled when it hides; flashes stay under 3 a second.
	The capsule window (CapsuleView: every egg, x3 / x10, the golems' names)
	stays one button away: the golem inventory's EGGS.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local PromptConfig = require(Shared.Config.PromptConfig)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local EggPanel = require(script.Parent.Parent.UI.EggPanel)
local EggPrompt = require(script.Parent.Parent.UI.EggPrompt)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local CapsuleController = require(script.Parent.CapsuleController)
local DecorController = require(script.Parent.DecorController)
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
EggPanelController.CountSeconds = 0.45 -- the price chip counting to a new price

local STALL_TAG = "CapsuleStall"
local OPEN3_ACTION = "TerraForgeEggOpen3"
local OPEN10_ACTION = "TerraForgeEggOpen10"
local OPEN_KEYS: { [number]: Enum.KeyCode } = { [3] = Enum.KeyCode.R, [10] = Enum.KeyCode.X }

type Spot = {
	Id: string,
	Model: Model, -- the egg (it hops: DecorController.bounce)
	Center: Vector3,
	Top: number, -- its top (the panel's anchor over it)
	Bottom: number, -- its foot (the light ring)
	Half: number, -- its half width
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
local lines: { EggPanel.Line } = {} -- the cards shown
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
local loops: { Tween } = {} -- the panel's running loops (rays, glows, bobs, the ring)
local chipPrice: number? = nil -- the x1 price the chip counts from
local counter: NumberValue? = nil
local counterTween: Tween? = nil
local alertTween: Tween? = nil
local keysBound = false
local ring: Part? = nil -- the light ring on the active egg's podium
local front = Vector3.new(1, 0, 0)
-- the big E
local prompt: EggPrompt.Refs? = nil
local promptFor: ProximityPrompt? = nil
local promptFade: NumberValue? = nil
local promptLoops: { Tween } = {}

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

local function glowOf(id: string): Color3
	local capsule = CapsuleConfig.ById[id]
	return if capsule then capsule.Glow else Color3.fromRGB(255, 200, 90)
end

local function loop(
	target: Instance,
	seconds: number,
	goal: { [string]: any },
	reverses: boolean,
	style: Enum.EasingStyle?,
	delay: number?
): Tween
	local tween = TweenService:Create(
		target,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, reverses, delay or 0),
		goal
	)
	tween:Play()
	return tween
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

---------------------------------------------------------------- the panel's motion

-- Stops the panel's loops and puts everything at rest (glows off: they aren't in the fade list).
local function stopLoops()
	for _, tween in loops do
		tween:Cancel()
	end
	table.clear(loops)
	local r = refs
	if r then
		for _, card in r.Cards do
			card.Rays.Rotation = 0
			card.Picture.Position = UDim2.fromScale(0.5, 0.44)
			card.Glow.BackgroundTransparency = 1
		end
	end
	local light = ring
	if light then
		light.Transparency = 1
	end
end

-- The loops of the shown cards and the podium's ring (still with Reduce motion: the glows only shine).
local function startLoops()
	stopLoops()
	local r = refs
	if not r then
		return
	end
	local still = Motion.reduced()
	for _, card in r.Cards do
		if card.Frame.Visible and card.Glow.Visible then
			card.Glow.BackgroundTransparency = 0.55
			if not still then
				table.insert(loops, loop(card.Glow, EggPanel.GlowPeriod / 2, { BackgroundTransparency = 0.82 }, true))
				table.insert(loops, loop(card.Picture, 0.9, { Position = UDim2.fromScale(0.5, 0.39) }, true))
			end
		end
		if card.Frame.Visible and card.Rays.Visible and not still then
			table.insert(loops, loop(card.Rays, EggPanel.RaySpeed, { Rotation = 360 }, false, Enum.EasingStyle.Linear))
		end
	end
	local light = ring
	if light and current then
		light.Transparency = 0.45
		if not still then
			table.insert(loops, loop(light, 1.2, { Transparency = 0.72 }, true))
		end
	end
end

-- The cards pop in one after another (not with Reduce motion).
local function popCards()
	local r = refs
	if not r or Motion.reduced() then
		return
	end
	local n = 0
	for _, card in r.Cards do
		if card.Frame.Visible then
			card.PopScale.Scale = 0.3
			TweenService:Create(
				card.PopScale,
				TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.08 + n * EggPanel.CardStagger),
				{ Scale = 1 }
			):Play()
			n += 1
		end
	end
end

-- One card's golem just woke: it pops (and the egg sparkles).
local function popCard(index: number)
	local r = refs
	local id = current
	if not r or not id or Motion.reduced() then
		return
	end
	local card = r.Cards[index]
	if card then
		card.PopScale.Scale = 1.35
		TweenService:Create(card.PopScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local spot = spots[id]
	if spot then
		Vfx.burst("Glint", spot.Center + Vector3.new(0, 1.5, 0), 14, glowOf(id))
	end
end

-- The price chip flashes red twice (Reduce motion: it turns red once and fades).
local function flashAlert()
	local r = refs
	if not r then
		return
	end
	if alertTween then
		alertTween:Cancel()
	end
	local tween
	if Motion.reduced() then
		r.Alert.BackgroundTransparency = 0.45
		tween = TweenService:Create(r.Alert, TweenInfo.new(EggPanel.AlertSeconds), { BackgroundTransparency = 1 })
	else
		r.Alert.BackgroundTransparency = 1
		local half = EggPanel.AlertSeconds / (EggPanel.AlertFlashes * 2)
		tween = TweenService:Create(
			r.Alert,
			TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, EggPanel.AlertFlashes - 1, true),
			{ BackgroundTransparency = 0.3 }
		)
	end
	alertTween = tween
	tween:Play()
end

-- The chip counts from the price it showed to `price` (a new egg, a new price level).
local function countPrice(price: number)
	local r = refs
	local from = chipPrice
	chipPrice = price
	if not r or from == nil or from == price or Motion.reduced() then
		return
	end
	local value = counter
	if not value then
		local made = Instance.new("NumberValue")
		made.Changed:Connect(function(v: number)
			local panel = refs
			if panel and counterTween then
				panel.Price.Text = EggPanel.priceText(v)
			end
		end)
		counter = made
		value = made
	end
	local v = value :: NumberValue
	if counterTween then
		counterTween:Cancel()
	end
	v.Value = from
	local tween = TweenService:Create(v, TweenInfo.new(EggPanelController.CountSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = price,
	})
	counterTween = tween
	tween.Completed:Connect(function()
		if counterTween == tween then
			counterTween = nil
			local panel = refs
			if panel then
				panel.Price.Text = EggPanel.priceText(price)
			end
		end
	end)
	tween:Play()
end

-- The soft ring of light on the active egg's podium (one part, moved; not in the lobby's light budget: neon only).
local function placeRing(spot: Spot)
	local light = ring
	if not light then
		local made = Instance.new("Part")
		made.Name = "EggLightRing"
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Material = Enum.Material.Neon
		made.Shape = Enum.PartType.Cylinder
		made.Transparency = 1
		made.Parent = Vfx.folder()
		ring = made
		light = made
	end
	local part = light :: Part
	local d = math.clamp(spot.Half * 1.15, 2.6, 5)
	part.Size = Vector3.new(0.08, d, d)
	part.CFrame = CFrame.new(spot.Center.X, spot.Bottom + 0.06, spot.Center.Z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = glowOf(spot.Id)
end

---------------------------------------------------------------- the panel

local refreshPanel: () -> () -- (below: the opens and Auto call it)

-- One egg (or 3, or 10) with the odds on the panel: refused when they just changed.
function EggPanelController.open(id: string, count: number)
	if id ~= current or not sellable then
		return
	end
	local _sent, reason = CapsuleController.buy(id, count, shownLucky, false)
	if reason == "OddsChanged" then
		refreshPanel() -- (the boost began or ended this moment: the new odds show first)
	elseif reason == "NoCoins" then
		flashAlert()
	end
end

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
	for _, open in r.Opens do
		open.Button.Activated:Connect(function()
			local id = current
			if id then
				EggPanelController.open(id, open.Count)
			end
		end)
	end
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

-- The opens' key badges: E / R / X on a keyboard, the main prompt's glyph on Open 1 for a gamepad, none on touch.
local function openKeys(): ({ [number]: string }?, string?)
	if MenuPanels.usingGamepad() then
		local main = PromptConfig.keys("Main").Gamepad
		local image = MenuPanels.glyph(main)
		return if image ~= "" then nil else { [1] = MenuPanels.padName(main) }, if image ~= "" then image else nil
	elseif isTouch() then
		return nil, nil
	end
	return EggPanel.OpenKeys, nil
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

local function buyOf(card: any, count: number): any
	if type(card) ~= "table" or type(card.Buys) ~= "table" then
		return nil
	end
	for _, b in card.Buys do
		if b.Count == count then
			return b
		end
	end
	return nil
end

-- Sets the big E's words from the egg's quote (when it shows).
local function updatePromptText(id: string, card: any)
	local p = prompt
	if not p then
		return
	end
	local buy = buyOf(card, 1)
	if not buy then
		EggPrompt.setText(p, "Buy Egg!", "Not available", false)
	elseif card.Robux then
		local live = buy.Reason ~= "ComingSoon"
		EggPrompt.setText(p, "Buy Egg!", EggPanel.promptText(true, nil, buy.PriceText, live), live)
	else
		EggPrompt.setText(p, "Buy Egg!", EggPanel.promptText(false, buy.Price, buy.PriceText, true), buy.Reason ~= "NoCoins")
	end
	EggPrompt.setGlow(p, glowOf(id))
end

--[[
	Fills the shown panel: the cards (when the egg, its odds or the golems
	the player has changed; a card that lights up pops), the price, the
	opens, Auto and the Triple Lucky tag.
]]
function refreshPanel()
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
		local sameEgg = id == linesEgg
		if id ~= linesEgg or lucky ~= shownLucky then
			luckySince = os.clock() -- (other odds on screen: a new egg, or the boost began / ended)
		end
		local before = lines
		linesEgg, linesVersion, shownLucky = id, knownVersion, lucky
		lines = EggPanel.lines(id, lucky, known)
		EggPanel.setLines(r, lines, modelFor)
		if r.Gui.Enabled then
			startLoops()
			if sameEgg then
				for i, line in lines do
					local old = before[i]
					if old and old.Golem == line.Golem and old.Silhouette and not line.Silhouette then
						popCard(i) -- (its golem just woke: in colour now)
					end
				end
			end
		end
	end
	local buy = buyOf(card, 1)
	sellable = card ~= nil and card.Visible == true and buy ~= nil
	local spot = spots[id]
	if not card or not card.Visible or not buy then
		EggPanel.setPrice(r, "Off", "Not available", false)
		EggPanel.setOpens(r, {})
	else
		if card.Robux then
			local live = buy.Reason ~= "ComingSoon"
			EggPanel.setPrice(r, if live then "Robux" else "Off", if live then buy.PriceText else "Coming soon", true)
			if spot then
				spot.Buy.ObjectText = EggPanel.promptText(true, nil, buy.PriceText, live)
			end
		else
			EggPanel.setPrice(r, "Coins", EggPanel.priceText(buy.Price or 0), buy.Reason ~= "NoCoins")
			countPrice(buy.Price or 0)
			local count = counter
			if counterTween and count then
				r.Price.Text = EggPanel.priceText(count.Value) -- (still counting: the refresh doesn't jump it)
			end
			if spot then
				spot.Buy.ObjectText = EggPanel.promptText(false, buy.Price, buy.PriceText, true)
			end
		end
		local keys, glyph = openKeys()
		EggPanel.setOpens(r, EggPanel.opens(card.Buys, card.Robux), keys, glyph)
	end
	local autoShown = sellable and EggPanel.autoAllowed(id)
	local text, image = autoKey()
	EggPanel.setAuto(r, autoShown, autoEgg == id, text, image)
	EggPanel.setLucky(r, lucky, autoShown)
	if promptFor and spot and promptFor == spot.Buy then
		updatePromptText(id, card)
	end
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
	EggPanel.apply(r, id, EggPanel.layout(count, touch, EggPanel.autoAllowed(id)), scale)
	local spot = spots[id]
	if spot then
		-- (over the egg on PC, beside it on touch: EggPanel.place)
		EggPanel.place(r, spot.Top + EggPanel.Lift - spot.Center.Y, spot.Half)
	end
	linesEgg = nil
	local p = prompt
	if p then
		EggPrompt.setScale(p, scale)
	end
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

-- R / X: Open 3 / Open 10 while a panel shows (never while the prompts are suppressed: an overlay, build mode).
local function onOpenKey(action: string, state: Enum.UserInputState): Enum.ContextActionResult
	local id = current
	if state ~= Enum.UserInputState.Begin or not id or not sellable or not ProximityPromptService.Enabled then
		return Enum.ContextActionResult.Pass
	end
	EggPanelController.open(id, if action == OPEN10_ACTION then 10 else 3)
	return Enum.ContextActionResult.Sink
end

local function bindKeys(on: boolean)
	if on == keysBound then
		return
	end
	keysBound = on
	if on then
		ContextActionService:BindAction(OPEN3_ACTION, onOpenKey, false, OPEN_KEYS[3])
		ContextActionService:BindAction(OPEN10_ACTION, onOpenKey, false, OPEN_KEYS[10])
	else
		ContextActionService:UnbindAction(OPEN3_ACTION)
		ContextActionService:UnbindAction(OPEN10_ACTION)
	end
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
	chipPrice = nil -- (a new egg: its price shows at once)
	placeRing(spot)
	linesEgg = nil
	refreshPanel() -- (the cards anew: their loops start there)
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
		popCards()
		-- the egg is happy to see you: a hop, a wobble, a sparkle
		DecorController.bounce(spot.Model)
		Vfx.burst("Glint", spot.Center + Vector3.new(0, 1, 0), 16, glowOf(id))
	end
	bindKeys(true)
	Sfx.play("UIClick")
end

local function hide()
	fadeTo(1, EggPanelController.FadeOut)
	stopLoops()
	bindKeys(false)
end

---------------------------------------------------------------- the big E (UI/EggPrompt)

-- The egg prompts' look: their own big round E (EggPanel.BigE) or Roblox's stock one.
local function eggLook(made: ProximityPrompt)
	made.Style = if EggPanel.BigE then Enum.ProximityPromptStyle.Custom else Enum.ProximityPromptStyle.Default
	if EggPanel.BigE then
		made:SetAttribute("OwnLook", true) -- (the light UI's prompts, UIConfig.CustomPrompts, leave it alone)
	end
end

local function ensurePrompt(): EggPrompt.Refs
	local existing = prompt
	if existing then
		return existing
	end
	local p = EggPrompt.build()
	p.Gui.Parent = player:WaitForChild("PlayerGui")
	EggPrompt.setScale(p, HudController.uiScale())
	local value = Instance.new("NumberValue")
	value.Value = 1
	value.Changed:Connect(function(alpha: number)
		local shown = prompt
		if shown then
			EggPrompt.setFade(shown, alpha)
		end
	end)
	promptFade = value
	EggPrompt.setFade(p, 1)
	-- a tap (or a click) on the disc holds the prompt like Roblox's own touch button
	p.Disc.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		local target = promptFor
		if target and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			target:InputHoldBegin()
		end
	end)
	p.Disc.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		local target = promptFor
		if target and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			target:InputHoldEnd()
		end
	end)
	prompt = p
	return p
end

local function stopPromptLoops()
	for _, tween in promptLoops do
		tween:Cancel()
	end
	table.clear(promptLoops)
	local p = prompt
	if p then
		p.GlowScale.Scale = 1
		p.Shine.Offset = Vector2.new(-1, 0)
		p.Press.Scale = 1
	end
end

local function showPrompt(spot: Spot, inputType: Enum.ProximityPromptInputType)
	local p = ensurePrompt()
	promptFor = spot.Buy
	p.Gui.Adornee = spot.Point
	p.Gui.Enabled = true
	EggPrompt.setScale(p, HudController.uiScale())
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local main = PromptConfig.keys("Main").Gamepad
		local image = MenuPanels.glyph(main)
		EggPrompt.setKey(p, if image ~= "" then "" else MenuPanels.padName(main), if image ~= "" then image else nil)
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		EggPrompt.setKey(p, "Tap", nil)
	else
		EggPrompt.setKey(p, PromptConfig.keys("Main").Keyboard.Name, nil)
	end
	updatePromptText(spot.Id, CapsuleController.quote(spot.Id))
	local value = promptFade
	if value then
		TweenService:Create(value, TweenInfo.new(0.12), { Value = 0 }):Play()
	end
	stopPromptLoops()
	if not Motion.reduced() then
		-- the ring of light breathes, a light band sweeps across the disc now and then
		table.insert(promptLoops, loop(p.GlowScale, EggPanel.GlowPeriod / 2, { Scale = 1.14 }, true))
		table.insert(
			promptLoops,
			loop(
				p.Shine,
				EggPrompt.ShineTime,
				{ Offset = Vector2.new(1, 0) },
				false,
				Enum.EasingStyle.Linear,
				EggPrompt.ShineEvery - EggPrompt.ShineTime
			)
		)
	end
end

local function hidePrompt(target: ProximityPrompt)
	if promptFor ~= target then
		return
	end
	promptFor = nil
	stopPromptLoops()
	local p = prompt
	local value = promptFade
	if p and value then
		local tween = TweenService:Create(value, TweenInfo.new(0.1), { Value = 1 })
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			local shown = prompt
			if state == Enum.PlaybackState.Completed and promptFor == nil and shown then
				shown.Gui.Enabled = false
			end
		end)
		tween:Play()
	end
end

-- The disc squashes when it is pressed (not with Reduce motion).
local function squash()
	local p = prompt
	if not p or Motion.reduced() then
		return
	end
	p.Press.Scale = 0.84
	TweenService:Create(p.Press, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	local sent, reason = CapsuleController.buy(id, 1, shownLucky, true)
	if not sent and reason ~= "Busy" and reason ~= "Cooldown" then
		stopAuto() -- (buy's toast said why: no coins, a full golem inventory...)
	end
end

---------------------------------------------------------------- the eggs

local function addEgg(id: string, model: Model)
	if spots[id] then
		return
	end
	local center, top, promptAt, bottom, half = EggPanel.spotOf(model, front)
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
	})
	eggLook(buy)
	buy.Parent = point
	local spot: Spot = {
		Id = id,
		Model = model,
		Center = center,
		Top = top,
		Bottom = bottom,
		Half = half,
		Point = point,
		Anchor = anchor,
		Buy = buy,
		Auto = nil,
	}
	buy.Triggered:Connect(function()
		squash()
		EggPanelController.open(id, 1)
	end)
	buy.PromptButtonHoldBegan:Connect(squash)
	buy.PromptShown:Connect(function(inputType: Enum.ProximityPromptInputType)
		if buy.Style == Enum.ProximityPromptStyle.Default then
			return -- (Roblox draws its own)
		end
		showPrompt(spot, inputType)
	end)
	buy.PromptHidden:Connect(function()
		hidePrompt(buy)
	end)
	if EggPanel.autoAllowed(id) then
		-- (no drawing of its own: the panel's toggle shows Auto and its key)
		local made = PromptConfig.make({
			Role = "Second",
			Name = "EggAutoPrompt",
			ActionText = "Auto",
			ObjectText = "Off",
			Distance = EggPanel.PromptDistance,
			Slot = 1,
			Enabled = false,
		})
		eggLook(made)
		made.Parent = point
		made.Triggered:Connect(function()
			EggPanelController.toggleAuto(id)
		end)
		spot.Auto = made
	end
	spots[id] = spot
	table.insert(spotList, { Id = id, Center = center })
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
