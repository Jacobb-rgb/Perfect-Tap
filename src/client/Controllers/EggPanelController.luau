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
	  still says why). Every card names its golem; golems the player has
	  none of are black silhouettes on coin eggs, their names under them
	  (EggPanel.known: the inventory is all the save tracks, so a deleted
	  kind goes dark again; Robux eggs show every golem); a card that lights
	  up because its golem just woke pops and the egg sparkles, never while
	  an egg hatches (the reveal comes first: EggPanel.holdCards). On touch
	  the panel floats beside the egg (float(), measured in the HUD's frames:
	  its opens' row out of the thumbstick's zone and off the touch buttons,
	  the HUD's buttons, the boost corner and the tutorial bubble, its cards
	  visible, inside the notch-safe frame; where the corner or the bubble
	  leave no room they step aside while it floats: BoostController.hold,
	  TutorialController.hold; the big E hides where the panel would cover
	  it). A TV gets bigger names and marks (EggPanel.layout's TenFoot).
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
	  build mode, on the plot; a gamepad's FocusKey, D-pad Up, selects the
	  panel's Open 1, the D-pad walks to Open 3 / 10 and Auto, A opens, B or
	  walking away lets go; nothing is selected when the panel shows, so the
	  stick keeps walking). The keys and their badges work within the
	  prompt's reach only (EggPanel.inReach), where E does, and only while
	  the panel is on the screen (a turned camera: no buy with the odds off
	  it, D-pad Up builds / goes home again). The Royal egg goes
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
	  opening's end screen (OK / B) or a window opens, when you respawn, and
	  when the odds change under it (Triple Lucky begins or runs out, maybe
	  under an end screen: it never buys on odds the player hasn't seen).
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
local GuiService = game:GetService("GuiService")
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
-- the gamepad's button that FOCUSES the panel (selects Open 1; the D-pad then walks to
-- Open 3, Open 10 and Auto; B or walking away lets go). Nothing is selected when the
-- panel shows: the left stick keeps walking. D-pad Up is build mode's (on the plot) and
-- "home" elsewhere; at an egg, within the prompt's reach, it is the panel's.
EggPanelController.FocusKey = Enum.KeyCode.DPadUp

local STALL_TAG = "CapsuleStall"
local OPEN3_ACTION = "TerraForgeEggOpen3"
local OPEN10_ACTION = "TerraForgeEggOpen10"
local FOCUS_ACTION = "TerraForgeEggFocus"
local RELEASE_ACTION = "TerraForgeEggRelease"
local OPEN_KEYS: { [number]: Enum.KeyCode } = { [3] = Enum.KeyCode.R, [10] = Enum.KeyCode.X }
local KEY_PRIORITY = Enum.ContextActionPriority.High.Value + 20 -- (over D-pad Up's build / home and B's own uses)
local FLOAT_STEP = "TerraForgeEggPanelFloat"

type Spot = {
	Id: string,
	Model: Model, -- the egg (it hops: DecorController.bounce)
	Center: Vector3,
	Top: number, -- its top (the panel's anchor over it)
	Bottom: number, -- its foot (the light ring)
	Half: number, -- its half width
	Point: Attachment, -- the prompts (in front of the egg, at its middle)
	PromptAt: Vector3, -- (its world position)
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
local reach = false -- the player is within the "Buy Egg!" prompt's reach (the keys work, their badges show)
local releaseBound = false -- B lets go of the panel's selection (bound while it holds it)
local lastAlert = -math.huge -- when the price chip last flashed red (EggPanel.alertOk)
local floating = false -- touch: the panel floats on the screen (float(), every frame)
local floatOffset = Vector2.zero
local promptCovered = false -- touch: the floating panel would cover the big E (it hides; Open 1 buys the same)
local measureFull: ScreenGui? = nil -- (float(): the whole viewport's frame)
local measureSafe: ScreenGui? = nil -- (the notch-safe frame)
local heldCorner = false -- the boost corner steps aside for the floating panel
local heldBubble = false -- the tutorial bubble too
local docked: { Key: string, Egg: Vector2, Time: number, At: Vector2, Fit: EggPanel.Fit }? = nil
local autoLucky = false -- the odds Auto started on (it stops when the shown odds aren't these any more)
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

-- A card's picture at rest (EggPanel.apply sets its height: "Rest"), `lift` units up.
local function pictureAt(card: EggPanel.Card, lift: number): UDim2
	local rest = card.Picture:GetAttribute("Rest")
	local y = if type(rest) == "number" then rest else 30
	return UDim2.fromOffset(card.Picture.Position.X.Offset, y - lift)
end

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
			card.Picture.Position = pictureAt(card, 0)
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
				table.insert(loops, loop(card.Picture, 0.9, { Position = pictureAt(card, 3) }, true))
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

-- The price chip flashes red twice (Reduce motion: it turns red once and fades); never
-- again before it is done (mashing a key keeps it at 2.5 flashes a second: EggPanel.alertOk).
local function flashAlert()
	local r = refs
	local now = os.clock()
	if not r or not EggPanel.alertOk(lastAlert, now) then
		return
	end
	lastAlert = now
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

-- Does the panel hold the gamepad's selection (focused: the D-pad walks its buttons)?
local function focused(): boolean
	local r = refs
	local selected = GuiService.SelectedObject
	return r ~= nil and selected ~= nil and selected:IsDescendantOf(r.Gui)
end

-- The key on Auto's badge: the keyboard letter, the gamepad's glyph, nothing on touch
-- or out of the prompt's reach (the key does nothing there).
local function autoKey(): (string, string?)
	local keys = PromptConfig.keys("Second")
	if not reach or focused() then
		return "", nil -- (focused: B lets go of the panel there, A presses the selected button)
	elseif MenuPanels.usingGamepad() then
		local image = MenuPanels.glyph(keys.Gamepad)
		return if image ~= "" then "" else MenuPanels.padName(keys.Gamepad), if image ~= "" then image else nil
	elseif isTouch() then
		return "", nil
	end
	return keys.Keyboard.Name, nil
end

--[[
	The opens' key badges: E / R / X on a keyboard; for a gamepad the main
	prompt's button on Open 1 and the focus button on Open 3 and Open 10
	(press it, then the D-pad); none on touch, none out of the prompt's
	reach (the keys do nothing there).
]]
local function openKeys(): ({ [number]: string }?, { [number]: string }?)
	if not reach then
		return nil, nil
	elseif MenuPanels.usingGamepad() then
		local keys: { [number]: string } = {}
		local glyphs: { [number]: string } = {}
		local main = PromptConfig.keys("Main").Gamepad
		for count, key in { [1] = main, [3] = EggPanelController.FocusKey, [10] = EggPanelController.FocusKey } do
			local image = MenuPanels.glyph(key)
			if image ~= "" then
				glyphs[count] = image
			else
				keys[count] = MenuPanels.padName(key)
			end
		end
		return keys, glyphs
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
			-- (off while the panel holds the selection: B lets go of it there, never toggles Auto)
			auto.Enabled = on and EggPanel.autoAllowed(id) and not focused()
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
	local opening = CapsuleController.openingState()
	-- (the golems the player has wait while an egg hatches: a card lighting up there would tell the new golem before the reveal)
	if knownDirty and not EggPanel.holdCards(opening) then
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
	if autoEgg == id and lucky ~= autoLucky then
		-- the odds changed under Auto (Triple Lucky began or ran out, maybe under an end
		-- screen): Auto stops, the new odds show, the player starts it again on them; the
		-- opening's overlay says why while it is up (a toast would sit under its dim)
		autoEgg = nil
		local text = if lucky then "Triple Lucky is on: Auto stopped" else "Triple Lucky ended: Auto stopped"
		if opening == "Idle" then
			CapsuleController.setAuto(false)
			HudController.toast(text, "Info")
		else
			CapsuleController.setAuto(false, text)
		end
	end
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
		local keys, glyphs = openKeys()
		EggPanel.setOpens(r, EggPanel.opens(card.Buys, card.Robux), keys, glyphs)
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

-- The guis the floating panel measures the screen with: the whole viewport (its Absolute*
-- frame is the viewport's) and the notch-safe frame (CoreUISafeInsets, the HUD's).
local function measureGuis(): (ScreenGui, ScreenGui)
	local full, safe = measureFull, measureSafe
	if full and safe then
		return full, safe
	end
	local playerGui = player:WaitForChild("PlayerGui")
	local madeFull = Instance.new("ScreenGui")
	madeFull.Name = "TerraForgeEggMeasure"
	madeFull.IgnoreGuiInset = true
	madeFull.ScreenInsets = Enum.ScreenInsets.None
	madeFull.ResetOnSpawn = false
	madeFull.Parent = playerGui
	local madeSafe = Instance.new("ScreenGui")
	madeSafe.Name = "TerraForgeEggSafe"
	madeSafe.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	madeSafe.ResetOnSpawn = false
	madeSafe.Parent = playerGui
	measureFull, measureSafe = madeFull, madeSafe
	return madeFull, madeSafe
end

-- A gui object's box on the screen, in the viewport's px (`origin`: the full-screen gui's AbsolutePosition).
local function boxOf(object: GuiObject, origin: Vector2): EggPanel.Box
	local at = object.AbsolutePosition - origin
	return { Min = at, Max = at + object.AbsoluteSize }
end

-- The visible boost corner's tiles (BoostView.cornerSpot puts them), one box; nil: none or held.
local function cornerBox(playerGui: Instance, origin: Vector2): EggPanel.Box?
	local gui = playerGui:FindFirstChild("TerraForgeBoostChips")
	local row = if gui then gui:FindFirstChild("Row") else nil
	if not gui or not gui:IsA("ScreenGui") or not gui.Enabled or not row or not row:IsA("GuiObject") or not row.Visible then
		return nil
	end
	local box: EggPanel.Box? = nil
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child.AbsoluteSize.X > 0 then
			local b = boxOf(child, origin)
			local u = box
			box = if u then { Min = u.Min:Min(b.Min), Max = u.Max:Max(b.Max) } else b
		end
	end
	return box
end

-- The visible tutorial bubble (the touch one, top right); nil: none or held.
local function bubbleBox(playerGui: Instance, origin: Vector2): EggPanel.Box?
	local gui = playerGui:FindFirstChild("TerraForgeTutorial")
	local bubble = if gui then gui:FindFirstChild("Bubble") else nil
	if gui and gui:IsA("ScreenGui") and gui.Enabled and bubble and bubble:IsA("GuiObject") and bubble.Visible then
		return if bubble.AbsoluteSize.X > 0 then boxOf(bubble, origin) else nil
	end
	return nil
end

--[[
	The touch screen as the floating panel sees it (EggPanel.screen), in
	the viewport's px, measured in the frames the HUD draws in: the safe
	frame (the notch), Roblox's top bar row, the HUD's teleport bar, the
	boost corner and the tutorial bubble (each while it shows).
]]
function EggPanelController.screenInput(camera: Camera): EggPanel.ScreenInput
	local full, safeGui = measureGuis()
	local origin = full.AbsolutePosition
	local view = if full.AbsoluteSize.X > 0 then full.AbsoluteSize else camera.ViewportSize
	local safe: EggPanel.Box? = nil
	if safeGui.AbsoluteSize.X > 0 then
		local at = safeGui.AbsolutePosition - origin
		safe = { Min = at, Max = at + safeGui.AbsoluteSize }
	end
	-- the HUD's buttons: the teleport bar, the left tiles, the TRAIN chip (ScreenGuis: over the panel)
	local blocks: { EggPanel.Box } = {}
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = HudController.refs()
	local train = playerGui:FindFirstChild("TerraForgeTrain")
	local chip = if train and train:IsA("ScreenGui") and train.Enabled then train:FindFirstChild("TrainChip", true) else nil
	local hudShown = hud ~= nil and hud.Gui.Enabled
	for _, object in
		{ if hudShown then hud.Gui:FindFirstChild("TopBar") else nil, if hudShown then hud.Gui:FindFirstChild("Menu") else nil, chip }
	do
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 0 then
			table.insert(blocks, boxOf(object, origin))
		end
	end
	return {
		View = view,
		Safe = safe,
		TopInset = GuiService:GetGuiInset().Y,
		Hud = blocks,
		Corner = cornerBox(playerGui, origin),
		Bubble = bubbleBox(playerGui, origin),
	}
end

-- The boost corner steps aside (hides) while the floating panel needs its place, or comes back.
-- (BoostController and TutorialController are required when first needed: they load the
-- mining and the tutorial; the Lune specs swap these two for recorders.)
function EggPanelController.holdCorner(on: boolean)
	require(script.Parent.BoostController).hold("EggPanel", on)
end

-- The tutorial bubble likewise (the player is at the egg its step points to).
function EggPanelController.holdBubble(on: boolean)
	require(script.Parent.TutorialController).hold("EggPanel", on)
end

local function holdOthers(corner: boolean, bubble: boolean)
	if corner ~= heldCorner then
		heldCorner = corner
		EggPanelController.holdCorner(corner)
	end
	if bubble ~= heldBubble then
		heldBubble = bubble
		EggPanelController.holdBubble(bubble)
	end
end

--[[
	Touch: the panel floats on the screen beside the egg (EggPanel.floatAt:
	right of it and of the big E, its opens' row out of the thumbstick's
	zone and off the touch buttons, the top bar, the boost corner and the
	tutorial bubble, its cards visible), moved by its SizeOffset. Where the
	corner or the bubble would still cover its row or a card, they step
	aside (held: hidden) while it floats. The big E hides where the panel
	would cover it (the panel's Open 1 buys the same). Every frame while it
	floats, after the camera moved; the wanted place is a cheap check, the
	search for a docked place runs when the screen or the egg changed.
]]
local function float()
	local r = refs
	local id = current
	local spot = if id then spots[id] else nil
	local camera = Workspace.CurrentCamera
	local l = if r then r.Layout else nil
	if not r or not spot or not camera or not l or not l.Beside then
		return
	end
	local mid = camera:WorldToViewportPoint(spot.Center)
	if mid.Z <= 0 then
		return -- (behind the camera: not drawn)
	end
	local egg = Vector2.new(mid.X, mid.Y)
	local side = camera:WorldToViewportPoint(spot.Center + camera.CFrame.RightVector * spot.Half)
	local reachPx = math.abs(side.X - mid.X)
	local promptSize = Vector2.new(EggPrompt.Width, EggPrompt.Height) * HudController.uiScale()
	local point = camera:WorldToViewportPoint(spot.PromptAt)
	local promptAt = Vector2.new(point.X, point.Y) - promptSize / 2
	if promptFor == spot.Buy and point.Z > 0 then
		reachPx = math.max(reachPx, point.X + promptSize.X / 2 - mid.X)
	end
	local scale = r.Scale.Scale
	local size = Vector2.new(r.Gui.Size.X.Offset, r.Gui.Size.Y.Offset)
	local row, odds = EggPanel.rowBox(l, scale), EggPanel.oddsBox(l, scale)
	local input = EggPanelController.screenInput(camera)
	local s = EggPanel.screen(input)
	local want = EggPanel.wantAt(s, size, row, egg, reachPx)
	local fit = EggPanel.fitAt(s, want, size, row, odds)
	local at = want
	if fit.Hard > 0 or fit.Odds > 0 or fit.Panel > 0 then
		-- (a docked place: searched again when the screen changed, the egg moved far or a while passed)
		local key = `{size.X}x{size.Y}|{#s.Avoid}|{s.View.X}x{s.View.Y}`
		for _, b in s.Avoid do
			key ..= `|{math.floor(b.Min.X)},{math.floor(b.Min.Y)},{math.floor(b.Max.X)},{math.floor(b.Max.Y)}`
		end
		local now = os.clock()
		local last = docked
		if last and last.Key == key and (last.Egg - egg).Magnitude < 48 and now - last.Time < 1 then
			at, fit = last.At, last.Fit
		else
			at, fit = EggPanel.dockAt(s, size, row, odds, want)
			docked = { Key = key, Egg = egg, Time = now, At = at, Fit = fit }
			-- the corner and the bubble step aside where the panel can't keep its row and its
			-- cards clear of them (held until it stops floating)
			if (fit.Hard > 0 or fit.Odds > 0) and (input.Corner or input.Bubble) then
				local corner, bubble = EggPanel.asides(input, size, row, odds, egg, reachPx)
				holdOthers(heldCorner or corner, heldBubble or bubble)
			end
		end
	end
	local offset = EggPanel.floatOffset(egg, at, size)
	if (offset - floatOffset).Magnitude > 1e-4 then
		floatOffset = offset
		r.Gui.SizeOffset = offset
	end
	local cover = point.Z > 0 and EggPanel.overlap({ Min = at, Max = at + size }, { Min = promptAt, Max = promptAt + promptSize }) > 0
	if cover ~= promptCovered then
		promptCovered = cover
		local p = prompt
		if p and promptFor then
			p.Gui.Enabled = not cover
		end
	end
end
EggPanelController._float = float -- (the Lune specs run it on a fake camera)

local function setFloating(on: boolean)
	if on == floating then
		return
	end
	floating = on
	docked = nil
	if on then
		floatOffset = Vector2.new(0, 0.5)
		RunService:BindToRenderStep(FLOAT_STEP, Enum.RenderPriority.Camera.Value + 1, float)
	else
		RunService:UnbindFromRenderStep(FLOAT_STEP)
		holdOthers(false, false)
		if promptCovered then
			promptCovered = false
			local p = prompt
			if p and promptFor then
				p.Gui.Enabled = true
			end
		end
	end
end

-- Is the egg's panel on the screen (its middle in front of the camera, inside the view)? The keys need it:
-- with the egg behind the camera R / X / D-pad Up would buy with the odds off the screen (and E does nothing).
local function onScreen(spot: Spot?): boolean
	if not spot then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return true
	end
	local point = camera:WorldToViewportPoint(spot.Center)
	local view = camera.ViewportSize
	return point.Z > 0 and point.X >= 0 and point.Y >= 0 and point.X <= view.X and point.Y <= view.Y
end

-- Lays the panel out for the egg and the device (again when either changed).
local function layOut(r: EggPanel.Refs, id: string)
	local touch = isTouch()
	local scale = HudController.uiScale()
	local tenFoot = GuiService:IsTenFootInterface()
	local count = #EggPanel.lines(id, false, known)
	local auto = EggPanel.autoAllowed(id)
	-- (a phone too small for the usual panel right of the thumbstick's zone: the narrow layout, 568 x 320)
	local camera = Workspace.CurrentCamera
	local narrow = false
	if touch and camera then
		narrow = EggPanel.pickNarrow(EggPanel.screen(EggPanelController.screenInput(camera)), scale, count, auto)
	end
	local key = `{id}|{touch}|{scale}|{tenFoot}|{narrow}`
	if key == laidOut then
		return
	end
	laidOut = key
	EggPanel.apply(r, id, EggPanel.layout(count, touch, auto, { TenFoot = tenFoot, Narrow = narrow }), scale)
	local spot = spots[id]
	if spot then
		-- (over the egg on PC; on touch at its middle, floating beside it: float())
		EggPanel.place(r, spot.Top + EggPanel.Lift - spot.Center.Y)
	end
	local l = r.Layout
	setFloating(current ~= nil and l ~= nil and l.Beside)
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

-- R / X: Open 3 / Open 10 within the prompt's reach (where E opens one; never while the prompts are suppressed: an overlay, build mode).
local function onOpenKey(action: string, state: Enum.UserInputState): Enum.ContextActionResult
	local id = current
	if state ~= Enum.UserInputState.Begin or not id or not sellable or not reach or not ProximityPromptService.Enabled then
		return Enum.ContextActionResult.Pass
	end
	if not onScreen(spots[id]) then
		return Enum.ContextActionResult.Pass
	end
	EggPanelController.open(id, if action == OPEN10_ACTION then 10 else 3)
	return Enum.ContextActionResult.Sink
end

-- B while the panel holds the selection: it lets go (the stick walks again).
local function onRelease(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not focused() then
		return Enum.ContextActionResult.Pass -- (another window holds it now: its B)
	end
	EggPanelController.release()
	return Enum.ContextActionResult.Sink
end

local function bindRelease(on: boolean)
	if on == releaseBound then
		return
	end
	releaseBound = on
	if on then
		ContextActionService:BindActionAtPriority(RELEASE_ACTION, onRelease, false, KEY_PRIORITY, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(RELEASE_ACTION)
	end
end

--[[
	The gamepad's focus button (FocusKey) within the prompt's reach: the
	panel takes the selection (Open 1; the D-pad walks to Open 3, Open 10
	and Auto, A opens). Anywhere else, or while something holds the
	selection already, it does what it does elsewhere.
]]
local function onFocus(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass
	end
	if not EggPanelController.focus() then
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

-- The panel takes the gamepad's selection (its Open 1). Returns whether it did.
function EggPanelController.focus(): boolean
	local r = refs
	local id = current
	if not r or not id or not sellable or not reach or not ProximityPromptService.Enabled or not onScreen(spots[id]) then
		return false -- (D-pad Up then does what it does elsewhere: build, home)
	end
	local first = r.Opens[1].Button
	if not first.Visible then
		return false
	end
	GuiService.SelectedObject = first
	bindRelease(true)
	refreshPanel() -- (Auto's badge and prompt rest: B lets go here)
	updatePrompts()
	return true
end

-- The panel lets go of the gamepad's selection (B, walking away, the panel hiding).
function EggPanelController.release()
	if focused() then
		GuiService.SelectedObject = nil
	end
	bindRelease(false)
	refreshPanel()
	updatePrompts()
end

local function bindKeys(on: boolean)
	if on == keysBound then
		return
	end
	keysBound = on
	if on then
		ContextActionService:BindAction(OPEN3_ACTION, onOpenKey, false, OPEN_KEYS[3])
		ContextActionService:BindAction(OPEN10_ACTION, onOpenKey, false, OPEN_KEYS[10])
		ContextActionService:BindActionAtPriority(FOCUS_ACTION, onFocus, false, KEY_PRIORITY, EggPanelController.FocusKey)
	else
		ContextActionService:UnbindAction(OPEN3_ACTION)
		ContextActionService:UnbindAction(OPEN10_ACTION)
		ContextActionService:UnbindAction(FOCUS_ACTION)
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
	local l = r.Layout
	setFloating(l ~= nil and l.Beside)
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
	-- (nothing is selected: the left stick keeps walking; the focus button selects)
	bindKeys(true)
	Sfx.play("UIClick")
end

local function hide()
	fadeTo(1, EggPanelController.FadeOut)
	stopLoops()
	EggPanelController.release()
	bindKeys(false)
	setFloating(false)
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
	p.Gui.Enabled = not promptCovered -- (touch: hidden where the floating panel covers it: float())
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
	refreshPanel() -- (the odds as they are now on the panel: Auto runs on these and stops when they change)
	if id ~= current or not sellable then
		return
	end
	autoEgg = id
	autoLucky = shownLucky
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
		refreshPanel() -- (the boost began or ended: the new odds show and Auto stops there)
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
		PromptAt = promptAt,
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
	-- within the "Buy Egg!" prompt's reach the keys work and their badges show (EggPanel.inReach)
	local spot = if current then spots[current] else nil
	local near = position ~= nil and spot ~= nil and EggPanel.inReach(position, spot.PromptAt) and onScreen(spot)
	if near ~= reach then
		reach = near
		if current then
			refreshPanel()
		end
	end
	if releaseBound and not focused() then
		bindRelease(false) -- (something else took the selection: an opening, a window)
		updatePrompts()
	end
	autoStep()
end

-- The Lune specs drive the controller through these (tests/EggPanel.spec.luau, on fakes for Roblox's services).
EggPanelController._test = {
	tick = tick,
	watch = watchStall,
	state = function(): { [string]: any }
		return {
			Current = current,
			Auto = autoEgg,
			Sellable = sellable,
			Reach = reach,
			Refs = refs,
			Lines = lines,
			Lucky = shownLucky,
			Spots = spots,
		}
	end,
}

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
