--[[
	RebirthController: the STAR FORGE window (RebirthView), the rebirth
	moment and the gold star over every player's name.

	- Opens from the side menu's REBIRTH (open / toggle / isOpen / close,
	  the MenuPanels contract); closes with the X button, B (gamepad),
	  Backspace, respawning or another panel opening.
	- The window reads State.Rebirth (RebirthService.snapshot) and the
	  blaster level. REBIRTH! waits for a second press within
	  RebirthConfig.ConfirmSeconds ("SURE?"), then sends RebirthAction
	  "Rebirth"; a perk card's BUY sends "Buy". RebirthResult answers: a
	  refusal shows a line (or a toast), a perk pops its card, a rebirth
	  closes the window and plays the moment (a white flash, the banner
	  "REBIRTH n!" with the stars it paid and falling stars, the Reveal
	  sound); the server sends the character home after it.
	- BLASTERS (the STAR blasters, StarBlasterData): the ⭐ button sends
	  "Weapon" (buy with Forge Stars, it is equipped at once), EQUIP /
	  EQUIPPED send "Equip" (EQUIPPED goes back to the forged blaster), a
	  grey 🔒 REBIRTH n says when it opens; the R$ button prompts the
	  weapon's game pass (MarketplaceService:PromptGamePassPurchase, only
	  for a live id while the receipts gate is open, else "soon"; the
	  server grants it). The guns in the cards are built the first time
	  the page shows (RebirthView.fillPicture).
	- The side menu's REBIRTH badge (onUnseenChanged: 1 while a rebirth is
	  ready and the window wasn't opened since) and a one-time toast
	  "Rebirth ready!" when the blaster reaches MinBlaster.
	- Every player with the ForgeStars attribute (RebirthService) wears a
	  small "⭐ n" board over the head (BillboardGui in this PlayerGui,
	  adorned to the Head, up to StarDistance studs away).
]]

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared.Config.RebirthConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local BlasterData = require(Shared.Config.BlasterData)
local Net = require(Shared.Net)
local RebirthView = require(script.Parent.Parent.UI.RebirthView)
local MenuPanel = require(script.Parent.Parent.UI.MenuPanel)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local PromptController = require(script.Parent.PromptController)

local RebirthController = {}

local NAME = "RebirthController"
local CLOSE_ACTION = "TerraForgeRebirthClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local STARS_ATTRIBUTE = "ForgeStars" -- RebirthService.StarsAttribute

RebirthController.StarDistance = 80
RebirthController.Reasons = {
	Locked = `Reach blaster LV {RebirthConfig.MinBlaster} first.`,
	NotForged = "Forge your next blaster level at the Foundry first.", -- (the window says which: RebirthView.forgeText)
	Busy = "Not right now: finish your ride or the rebirth on its way.",
	Failed = "The rebirth didn't go through. Nothing changed, try again.",
	NoStars = "Not enough Forge Stars yet.",
	Max = "That perk is at its top level.",
	BadPerk = "That perk isn't in the shop.",
	NoData = "Your data is still loading.",
}
-- (the "Weapon" / "Equip" answers)
RebirthController.WeaponReasons = {
	Locked = "Rebirth more to open that blaster.",
	Owned = "That blaster is yours already.",
	NoStars = "Not enough Forge Stars yet.",
	BadWeapon = "That blaster isn't in the forge.",
	Checking = "Checking your Robux passes. Try again in a moment.",
	NoData = "Your data is still loading.",
}

local player = Players.LocalPlayer
local refs: RebirthView.Refs? = nil
local isOpen = false
local openedAt = 0
local confirmUntil = 0
local info: RebirthView.Info = { Count = 0, Stars = 0, Perks = {}, Level = 1, Ready = false, StarsNow = 0 }
local seenReady = false -- the window was opened while a rebirth was ready
local toldReady = false
local unseenListeners: { (number) -> () } = {}
local boards: { [Player]: BillboardGui } = {}

function RebirthController.isOpen(): boolean
	return isOpen
end

---------------------------------------------------------------- the badge

local function unseen(): number
	return if info.Ready and not seenReady then 1 else 0
end

local function fireUnseen()
	local count = unseen()
	for _, callback in unseenListeners do
		task.spawn(callback, count)
	end
end

-- cb(count) when the REBIRTH badge changes (SideMenuController).
function RebirthController.onUnseenChanged(callback: (number) -> ())
	table.insert(unseenListeners, callback)
	task.spawn(callback, unseen())
end

---------------------------------------------------------------- window

local function fit(view: RebirthView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = MenuPanel.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	RebirthView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function updateGlyphs(view: RebirthView.Refs)
	if MenuPanels.usingGamepad() then
		local a = MenuPanels.glyph(Enum.KeyCode.ButtonA)
		local b = MenuPanels.glyph(Enum.KeyCode.ButtonB)
		MenuPanel.setCloseGlyph(view.Frame, b)
		if a ~= "" and b ~= "" then
			MenuPanel.setHint(view.Frame, "", { { Image = a, Word = "choose" }, { Image = b, Word = "close" } })
		else
			MenuPanel.setHint(
				view.Frame,
				`{MenuPanels.padName(Enum.KeyCode.ButtonA)}: choose · {MenuPanels.padName(Enum.KeyCode.ButtonB)}: close`,
				nil
			)
		end
	else
		MenuPanel.setCloseGlyph(view.Frame, nil)
		MenuPanel.setHint(view.Frame, "Rebirth is optional: you choose when · Backspace: close", nil)
	end
end

local function refresh()
	local view = refs
	if view then
		if os.clock() > confirmUntil then
			view.Confirm = false
		end
		RebirthView.setInfo(view, info)
	end
end

local function send(args: { [string]: any })
	Net.send("RebirthAction", args)
end

local function onRebirthPressed()
	local view = refs
	if not view or not info.Ready then
		if view then
			local reason = if info.Level >= RebirthConfig.MinBlaster then "NotForged" else "Locked"
			RebirthView.setMessage(
				view,
				if reason == "NotForged" then RebirthView.forgeText(info.Level) else RebirthController.Reasons[reason]
			)
		end
		Sfx.play("UIClick")
		return
	end
	if view.Confirm and os.clock() <= confirmUntil then
		view.Confirm = false
		confirmUntil = 0
		RebirthView.setConfirm(view, false)
		send({ Action = "Rebirth" })
		return
	end
	confirmUntil = os.clock() + RebirthConfig.ConfirmSeconds
	RebirthView.setConfirm(view, true)
	Sfx.play("UIClick")
	task.delay(RebirthConfig.ConfirmSeconds + 0.05, refresh)
end

local function robuxOn(): boolean
	return ReplicatedStorage:GetAttribute(MonetizationConfig.ReceiptsAttribute) == true
end

-- A weapon card's big button: buy with stars, equip / unequip, or say when it opens.
local function onWeaponMain(id: string)
	local star = StarBlasterData.get(id)
	if not star then
		return
	end
	local shown = RebirthView.weaponCard(info, star)
	Sfx.play("UIClick")
	if shown.State == "Buy" then
		if info.Stars < star.Stars then
			HudController.toast(`The {star.Name} costs ⭐ {star.Stars}. You have ⭐ {info.Stars}.`, "Deny")
		else
			send({ Action = "Weapon", Id = id })
		end
	elseif shown.State == "Owned" then
		send({ Action = "Equip", Id = id })
	elseif shown.State == "Equipped" then
		send({ Action = "Equip", Id = "" })
	else
		HudController.toast(`The {star.Name} opens at rebirth {star.Unlock}.`, "Info")
	end
end

-- A weapon card's R$ button: the game pass prompt (the server grants it).
local function onWeaponRobux(id: string)
	local star = StarBlasterData.get(id)
	if not star then
		return
	end
	Sfx.play("UIClick")
	local entry = MonetizationConfig.get("Star" .. id)
	if entry and MonetizationConfig.isLive(entry.Id) and robuxOn() then
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		end)
	else
		HudController.toast(`Robux sales open soon. The {star.Name} is ⭐ {star.Stars} now!`, "Info")
	end
end

local function ensureView(): RebirthView.Refs
	if refs then
		return refs :: RebirthView.Refs
	end
	local view = RebirthView.build()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Frame.Close.Activated:Connect(function()
		RebirthController.close()
		Sfx.play("UIClick")
	end)
	for _, id in RebirthView.TabIds do
		view.Tabs[id].Activated:Connect(function()
			RebirthView.setTab(view, id)
			if id == "Blasters" then
				for _, card in view.Weapons do
					RebirthView.fillPicture(card)
				end
			end
			Sfx.play("UIClick")
		end)
	end
	for _, card in view.Weapons do
		card.Main.Activated:Connect(function()
			onWeaponMain(card.Id)
		end)
		card.Robux.Activated:Connect(function()
			onWeaponRobux(card.Id)
		end)
	end
	view.Rebirth.Activated:Connect(onRebirthPressed)
	for _, card in view.Cards do
		card.Buy.Activated:Connect(function()
			send({ Action = "Buy", Perk = card.Id })
		end)
		local pick = card.Pick
		if pick then
			pick.Activated:Connect(function()
				send({ Action = "Glow", Color = RebirthConfig.nextGlow(info.Perks, info.Glow or "") })
				Sfx.play("UIClick")
			end)
		end
	end
	RebirthView.setTab(view, "Rebirth")
	refs = view
	refresh()
	return view
end

function RebirthController.close()
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
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Rebirth", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	RebirthController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function RebirthController.open()
	if isOpen then
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = ensureView()
	isOpen = true
	openedAt = os.clock()
	updateGlyphs(view)
	fit(view)
	RebirthView.setMessage(view, nil)
	refresh()
	view.Gui.Enabled = true
	PromptController.setSuppressed("Rebirth", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.Tabs.Rebirth else nil
	if info.Ready and not seenReady then
		seenReady = true
		fireUnseen()
	end
	Sfx.play("UIClick")
	local panel = view.Frame.Panel
	local scale = panel:FindFirstChild("OpenPop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = panel
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function RebirthController.toggle()
	if isOpen then
		RebirthController.close()
	else
		RebirthController.open()
	end
end

---------------------------------------------------------------- the moment

local function moment(count: number, stars: number)
	local view = RebirthView.buildMoment(count, stars, math.floor(os.clock() * 1000))
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(view.Flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = view.Banner
	TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- the stars fall from above the screen to below it
	local rng = Random.new()
	for _, star in view.Stars do
		local x = star.Position.X.Scale
		star.Position = UDim2.fromScale(x, -0.05)
		TweenService:Create(
			star,
			TweenInfo.new(rng:NextNumber(1.4, 2.4), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(rng:NextNumber(0.1, 0.9), 1.1), Rotation = rng:NextNumber(-180, 180) }
		):Play()
	end
	Sfx.play("Reveal")
	task.delay(2.6, function()
		for _, object in { view.Banner, view.Paid } do
			TweenService:Create(object, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		task.delay(0.6, function()
			view.Gui:Destroy()
		end)
	end)
end

local function onResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local view = refs
	if result.Action == "Rebirth" then
		if result.Ok then
			RebirthController.close()
			moment(tonumber(result.Rebirths) or 1, tonumber(result.Stars) or 0)
		elseif view then
			local text = if result.Reason == "NotForged"
				then RebirthView.forgeText(info.Level)
				else RebirthController.Reasons[result.Reason]
			RebirthView.setMessage(view, text or "Not now.")
		end
	elseif result.Action == "Glow" then
		if not result.Ok then
			HudController.toast("Unlock that colour in the STAR SHOP first.", "Deny")
		end
	elseif result.Action == "Weapon" or result.Action == "Equip" then
		local star = StarBlasterData.get(result.Id)
		if not result.Ok then
			HudController.toast(RebirthController.WeaponReasons[result.Reason] or "Not now.", "Deny")
		elseif result.Action == "Weapon" and star then
			Sfx.play("Discovery")
			HudController.toast(`The {star.Name} is yours and equipped!`, "Reward")
		elseif star then
			HudController.toast(`{star.Name} equipped: x{star.Mult} damage!`, "Reward")
		else
			HudController.toast("Back to your forged blaster.", "Info")
		end
	elseif result.Action == "Buy" then
		if result.Ok then
			Sfx.play("Discovery")
			local perk = RebirthConfig.ById[result.Perk]
			if perk then
				HudController.toast(`{perk.Name} is now level {result.Level}!`, "Reward")
			end
		else
			HudController.toast(RebirthController.Reasons[result.Reason] or "Not now.", "Deny")
		end
	end
end

---------------------------------------------------------------- state

local function onState(state: { [string]: any })
	local r = state.Rebirth
	if type(r) ~= "table" then
		return
	end
	local wasReady = info.Ready
	info = {
		Count = tonumber(r.Count) or 0,
		Stars = tonumber(r.Stars) or 0,
		Perks = if type(r.Perks) == "table" then r.Perks else {},
		Level = BlasterData.get(state.BlasterLevel).Level,
		Ready = r.Ready == true,
		StarsNow = tonumber(r.StarsNow) or 0,
		Reached = tonumber(r.Reached),
		Start = tonumber(r.Start),
		Glow = if type(r.Glow) == "string" then r.Glow else "",
		Weapons = if type(r.Weapons) == "table" then r.Weapons else {},
		Weapon = if type(r.Weapon) == "string" then r.Weapon else "",
		RobuxOn = robuxOn(),
	}
	if info.Ready and not wasReady then
		seenReady = isOpen
		if not toldReady then
			toldReady = true
			HudController.toast("Rebirth ready! Open REBIRTH in the menu to see what you get.", "Reward")
		end
	elseif not info.Ready then
		seenReady = false
		toldReady = false
	end
	fireUnseen()
	refresh()
end

---------------------------------------------------------------- the star over the name

local function hideBoard(other: Player)
	local board = boards[other]
	if board then
		board:Destroy()
		boards[other] = nil
	end
end

local function showBoard(other: Player)
	local stars = other:GetAttribute(STARS_ATTRIBUTE)
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	if type(stars) ~= "number" or stars < 1 or not head then
		hideBoard(other)
		return
	end
	local board = boards[other]
	if not board then
		local made = Instance.new("BillboardGui")
		made.Name = "ForgeStars_" .. other.UserId
		made.Size = UDim2.fromOffset(110, 30)
		made.StudsOffset = Vector3.new(0, 3.6, 0)
		made.AlwaysOnTop = false
		made.MaxDistance = RebirthController.StarDistance
		made.LightInfluence = 0
		local label = UIKit.label(made, "", 22, {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = RebirthView.Colors.Star,
			TextWrapped = false,
		})
		UIKit.textStroke(label, 2)
		made.Parent = player:WaitForChild("PlayerGui")
		boards[other] = made
		board = made
	end
	local shown = board :: BillboardGui
	shown.Adornee = head
	local label = shown:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = `⭐ {math.floor(stars)}`
	end
end

local function watchPlayer(other: Player)
	other:GetAttributeChangedSignal(STARS_ATTRIBUTE):Connect(function()
		showBoard(other)
	end)
	other.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		showBoard(other)
	end)
	if other.Character then
		showBoard(other)
	end
end

---------------------------------------------------------------- lifecycle

function RebirthController.init()
	StateController.onChanged(onState)
	Net.listen("RebirthResult", onResult)
	-- the "Star Forge" prompt at the plaza's fire crystal
	Net.listen("OpenUI", function(kind)
		if kind == "Rebirth" then
			RebirthController.open()
		end
	end)
	player.CharacterRemoving:Connect(function()
		RebirthController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			updateGlyphs(view)
			fit(view)
		end
	end)
end

function RebirthController.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerRemoving:Connect(hideBoard)
	-- Robux sales switching on (the receipts gate) light the R$ buttons
	ReplicatedStorage:GetAttributeChangedSignal(MonetizationConfig.ReceiptsAttribute):Connect(function()
		info.RobuxOn = robuxOn()
		refresh()
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and isOpen then
				fit(view)
			end
		end)
	end
	-- another panel opening closes this one
	task.spawn(function()
		while true do
			task.wait(0.25)
			if isOpen and os.clock() - openedAt > 0.3 and MenuPanels.otherOpen(NAME) then
				RebirthController.close()
			end
		end
	end)
end

return RebirthController
