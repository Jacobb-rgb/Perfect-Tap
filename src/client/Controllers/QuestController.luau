--[[
	QuestController: the QUESTS window and the daily-streak popup
	(QuestView; the server is QuestService, docs/plans/DAILY_QUESTS_PLAN.md).

	  - open / close / toggle / isOpen: the side menu's QUESTS tile (MenuPanels:
	    one panel at a time; the popup counts as this panel too)
	  - onUnseenChanged(callback(count)): the tile's badge = finished quests not
	    claimed + today's streak day when it is not claimed yet
	  - a toast the moment a quest gets finished ("Quest done! ...")
	  - the streak popup on join: once per session, after the loading screen
	    (Util/Loading), only when today's day is not claimed, never over the
	    tutorial bubble, another panel, the cleaning minigame or build mode
	    (it waits up to QuestConfig.PopupWaitSeconds, else the badge stays)
	  - claims: QuestAction ("Claim" / "Streak"); QuestReward shows the prize
	    (a capsule's opening comes from CapsuleController: the popup closes
	    first); a refusal (ActionResult) shows its reason
	  - input: click / tap; gamepad: the window is a SelectionGroup, the first
	    thing to claim is selected, B closes (or leaves the odds panel)
	  - layouts: QuestView.layout with the HUD scale; phones / TVs compact
	    (every button >= 44 pt through the fit scale)
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared.Config.QuestConfig)
local BoostConfig = require(Shared.Config.BoostConfig)
local QuestLogic = require(Shared.Quests.QuestLogic)
local Net = require(Shared.Net)
local QuestView = require(script.Parent.Parent.UI.QuestView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Loading = require(script.Parent.Parent.Util.Loading)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local QuestController = {}

local NAME = "QuestController"
local CLOSE_ACTION = "TerraForgeQuestsClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10

local player = Players.LocalPlayer
local refs: QuestView.Refs? = nil
local popup: QuestView.PopupRefs? = nil
local windowOpen = false
local popupOpen = false
local view: { [string]: any }? = nil
local listeners: { (number) -> () } = {}
local lastCount = -1
local waiting = false -- a claim is on its way
local waitToken = 0
local popupShown = false
-- "<Day>|<Id>" / "<Week>|<Id>" -> finished (for the "Quest done!" toast)
local finished: { [string]: boolean } = {}
local seenOnce = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

function QuestController.isOpen(): boolean
	return windowOpen or popupOpen
end

-- The badge: things waiting to be claimed.
function QuestController.unseen(): number
	return QuestLogic.claimable(view)
end

function QuestController.onUnseenChanged(callback: (number) -> ())
	table.insert(listeners, callback)
	task.spawn(callback, QuestController.unseen())
end

local function notifyCount()
	local count = QuestController.unseen()
	if count == lastCount then
		return
	end
	lastCount = count
	for _, listener in listeners do
		task.spawn(listener, count)
	end
end

local function lucky(): boolean
	local state = StateController.get()
	local boosts = if state then state.Boosts else nil
	return BoostConfig.active(boosts, "TripleLucky", math.floor(now()))
end

---------------------------------------------------------------- layout

local function screenFit(): (number, number, boolean)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = TechShopView.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	return size.X / scale, (size.Y - inset.Y) / scale, compact
end

local function fit()
	local w, h, compact = screenFit()
	if refs then
		QuestView.layout(refs, w, h, compact)
	end
	if popup then
		QuestView.layoutPopup(popup, w, h, compact)
	end
end

local function popIn(root: GuiObject)
	local pop = root:FindFirstChild("OpenPop") :: UIScale?
	if not pop then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = root
		pop = made
	end
	local s = pop :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- drawing

-- The first thing a gamepad should land on: something to claim, else the close X.
local function firstSelectable(r: QuestView.Refs): GuiObject
	for _, cell in r.Days do
		if cell.Button.Selectable then
			return cell.Button
		end
	end
	for _, q in r.Quests do
		if q.Claim.Visible and q.Claim.Selectable then
			return q.Claim
		end
	end
	return r.Window.Close
end

local function redraw()
	local r = refs
	if r and windowOpen then
		QuestView.setView(r, view, math.floor(now()))
	end
	local p = popup
	if p and popupOpen then
		QuestView.setPopup(p, view)
	end
end

-- Countdowns tick while the window is open.
local function tickLoop()
	while windowOpen do
		local r = refs
		if r then
			QuestView.setView(r, view, math.floor(now()))
		end
		task.wait(1)
	end
end

---------------------------------------------------------------- claims

local function startWait()
	waiting = true
	waitToken += 1
	local token = waitToken
	task.delay(QuestConfig.ResultTimeout, function()
		if token == waitToken then
			waiting = false
		end
	end)
end

function QuestController.claim(kind: string, index: number)
	if waiting or not view then
		return
	end
	Sfx.play("UIClick")
	startWait()
	if kind == "Weekly" then
		Net.send("QuestAction", "Claim", { Kind = "Weekly", Week = view.Week })
	else
		Net.send("QuestAction", "Claim", { Kind = "Daily", Index = index, Day = view.Day })
	end
end

function QuestController.claimStreak()
	local streak = if view then view.Streak else nil
	if waiting or type(streak) ~= "table" or streak.CanClaim ~= true then
		if type(streak) == "table" and streak.CanClaim ~= true then
			HudController.toast(QuestConfig.Reasons.Tomorrow, "Info")
		end
		return
	end
	Sfx.play("UIClick")
	startWait()
	Net.send("QuestAction", "Streak")
end

local function rewardToast(reward: { [string]: any })
	local parts = {}
	local text = QuestView.rewardText({
		Coins = reward.Coins,
		Shards = reward.Shards,
		Boost = reward.Boost,
		BoostSeconds = reward.Seconds,
	})
	if text ~= "" then
		table.insert(parts, text)
	end
	if reward.Full then
		table.insert(parts, "(the capsule was paid as coins)")
	end
	local title = if reward.Kind == "Streak" then `Day {reward.Day or 1} reward!` else "Quest reward!"
	HudController.toast(title .. " " .. table.concat(parts, "  "), "Reward")
end

local function onReward(reward: any)
	if type(reward) ~= "table" then
		return
	end
	waiting = false
	waitToken += 1
	Sfx.play("CoinBurst")
	rewardToast(reward)
	local p = popup
	if reward.Kind == "Streak" and p and popupOpen then
		if reward.Golem then
			-- the capsule opening (CapsuleController) plays right away: out of its way
			QuestController.closePopup()
		else
			task.delay(1.4, function()
				if popupOpen then
					QuestController.closePopup()
				end
			end)
		end
	end
end

local function onActionResult(result: any)
	if type(result) ~= "table" or result.Action ~= "Quest" then
		return
	end
	if result.Ok == true then
		return
	end
	waiting = false
	waitToken += 1
	Sfx.play("UIDeny")
	local reason = if type(result.Reason) == "string" then QuestConfig.Reasons[result.Reason] else nil
	HudController.toast(reason or QuestConfig.Reasons.BadQuest, "Deny")
end

---------------------------------------------------------------- state

-- A "Quest done!" toast for quests that just got finished (not on the first state).
local function announce(v: { [string]: any })
	for _, key in { "Daily", "Weekly" } do
		local list = v[key]
		local number = if key == "Weekly" then v.Week else v.Day
		if type(list) == "table" then
			for _, q in list do
				if type(q) == "table" then
					local id = `{key}|{number}|{q.Id}`
					local done = type(q.Progress) == "number" and q.Progress >= (q.Goal or math.huge)
					if done and not finished[id] and seenOnce and not q.Claimed then
						HudController.toast(`Quest done: {q.Text}! Claim it in QUESTS.`, "Reward")
						Sfx.play("Discovery")
					end
					finished[id] = done
				end
			end
		end
	end
	seenOnce = true
end

local function onState(state: { [string]: any })
	local quests = state.Quests
	if type(quests) ~= "table" then
		return
	end
	view = quests
	announce(quests)
	notifyCount()
	redraw()
end

---------------------------------------------------------------- the window

local function bindClose()
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin or not QuestController.isOpen() then
			return Enum.ContextActionResult.Pass
		end
		local r, p = refs, popup
		if r and windowOpen and r.Odds.Visible then
			QuestView.showOdds(r, nil)
			GuiService.SelectedObject = if MenuPanels.usingGamepad() then r.OddsButton else nil
		elseif p and popupOpen and p.Odds.Visible then
			QuestView.showOdds(p, nil)
			GuiService.SelectedObject = if MenuPanels.usingGamepad() then p.Claim else nil
		else
			QuestController.close()
		end
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
end

local function ensureView(): QuestView.Refs
	if refs then
		return refs :: QuestView.Refs
	end
	local r = QuestView.build()
	r.Gui.Parent = player:WaitForChild("PlayerGui")
	r.Window.Close.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestController.close()
	end)
	for i, q in r.Quests do
		q.Claim.Activated:Connect(function()
			if q.Claim.Active then
				QuestController.claim(if i > QuestConfig.DailyCount then "Weekly" else "Daily", i)
			end
		end)
	end
	for _, cell in r.Days do
		cell.Button.Activated:Connect(function()
			if cell.Button.Active then
				QuestController.claimStreak()
			end
		end)
	end
	r.OddsButton.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestView.showOdds(r, QuestView.oddsLines(lucky()))
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then r.OddsBack else nil
	end)
	r.OddsBack.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestView.showOdds(r, nil)
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then r.OddsButton else nil
	end)
	refs = r
	return r
end

local function ensurePopup(): QuestView.PopupRefs
	if popup then
		return popup :: QuestView.PopupRefs
	end
	local p = QuestView.buildPopup()
	p.Gui.Parent = player:WaitForChild("PlayerGui")
	p.Window.Close.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestController.closePopup()
	end)
	p.Claim.Activated:Connect(function()
		if p.Claim.Active then
			QuestController.claimStreak()
		end
	end)
	for _, cell in p.Days do
		cell.Button.Activated:Connect(function()
			if cell.Button.Active then
				QuestController.claimStreak()
			end
		end)
	end
	p.OddsButton.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestView.showOdds(p, QuestView.oddsLines(lucky()))
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then p.OddsBack else nil
	end)
	p.OddsBack.Activated:Connect(function()
		Sfx.play("UIClick")
		QuestView.showOdds(p, nil)
		GuiService.SelectedObject = if MenuPanels.usingGamepad() then p.Claim else nil
	end)
	popup = p
	return p
end

local function unbindIfShut()
	if not windowOpen and not popupOpen then
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
end

function QuestController.closePopup()
	if not popupOpen then
		return
	end
	popupOpen = false
	local p = popup
	if p then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(p.Gui) then
			GuiService.SelectedObject = nil
		end
		QuestView.showOdds(p, nil)
		p.Gui.Enabled = false
	end
	unbindIfShut()
end

function QuestController.close()
	QuestController.closePopup()
	if not windowOpen then
		return
	end
	windowOpen = false
	local r = refs
	if r then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(r.Gui) then
			GuiService.SelectedObject = nil
		end
		QuestView.showOdds(r, nil)
		r.Gui.Enabled = false
	end
	unbindIfShut()
end

function QuestController.open()
	if windowOpen then
		return
	end
	QuestController.closePopup()
	MenuPanels.closeOthers(NAME)
	local r = ensureView()
	windowOpen = true
	fit()
	QuestView.setStatus(r, nil)
	QuestView.showOdds(r, nil)
	QuestView.setView(r, view, math.floor(now()))
	r.Scroller.CanvasPosition = Vector2.new(0, 0)
	r.Gui.Enabled = true
	bindClose()
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then firstSelectable(r) else nil
	Sfx.play("UIClick")
	popIn(r.Window.Root)
	task.spawn(tickLoop)
end

function QuestController.toggle()
	if windowOpen then
		QuestController.close()
	else
		QuestController.open()
	end
end

-- The streak popup (the join one; also callable by other code).
function QuestController.openPopup()
	if popupOpen or windowOpen then
		return
	end
	MenuPanels.closeOthers(NAME)
	local p = ensurePopup()
	popupOpen = true
	fit()
	QuestView.showOdds(p, nil)
	QuestView.setPopup(p, view)
	p.Gui.Enabled = true
	bindClose()
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then p.Claim else nil
	Sfx.play("Reveal")
	popIn(p.Window.Root)
end

---------------------------------------------------------------- the join popup

-- Is the screen free for the popup (no tutorial bubble, panel, minigame, build mode)?
local function screenFree(): boolean
	local tutorial = MenuPanels.controller("TutorialController")
	if tutorial and type(tutorial.isShown) == "function" then
		local ok, shown = pcall(tutorial.isShown)
		if ok and shown then
			return false
		end
	end
	local cleaning = MenuPanels.controller("CleaningController")
	if cleaning and type(cleaning.isActive) == "function" then
		local ok, active = pcall(cleaning.isActive)
		if ok and active then
			return false
		end
	end
	if PlayerControls.owner() ~= nil or MenuPanels.otherOpen(NAME) then
		return false
	end
	local hud = HudController.refs()
	return hud == nil or (hud.Gui.Enabled and hud.Menu.Visible)
end

local function joinPopup()
	Loading.wait()
	local started = os.clock()
	while os.clock() - started < QuestConfig.PopupWaitSeconds do
		local streak = if view then view.Streak else nil
		if type(streak) == "table" then
			if streak.CanClaim ~= true then
				return -- claimed today already: no popup
			end
			-- a short beat after the loading screen so the world is there first
			if os.clock() - started >= 2 and screenFree() then
				if not popupShown then
					popupShown = true
					QuestController.openPopup()
				end
				return
			end
		end
		task.wait(0.5)
	end
end

---------------------------------------------------------------- lifecycle

function QuestController.init()
	Net.listen("QuestReward", onReward)
	Net.listen("ActionResult", onActionResult)
end

function QuestController.start()
	StateController.onChanged(onState)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if QuestController.isOpen() then
				fit()
			end
		end)
	end
	-- (the HUD scale follows the screen too)
	local hud = HudController.refs()
	local scale = hud and hud.Gui:FindFirstChild("Scale")
	if scale and scale:IsA("UIScale") then
		scale:GetPropertyChangedSignal("Scale"):Connect(function()
			if QuestController.isOpen() then
				fit()
			end
		end)
	end
	task.spawn(joinPopup)
end

return QuestController
