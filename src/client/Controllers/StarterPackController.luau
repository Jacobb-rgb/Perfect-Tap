--[[
	The Starter Pack popup (StarterPackView): shown at most once per
	session, while the State says the offer is open (State.StarterPack =
	{ Open, Bought, Left }: StarterPackService), after PopupAfter seconds of
	play (MonetizationConfig.StarterOffer), only once purchases are really
	on (the receipts gate attribute and a live product id: never a popup
	that can only say "Coming soon"), once the tutorial is done (never over
	its first steps) and while no other menu is open. It says plainly
	"available during your first hour": no countdown, no pressure
	(docs/COMPLIANCE.md 2.6a).
	The price buys it (StoreAction "Buy": StoreService prompts; a refusal
	shows its PurchasePrompt text in the popup); Later and the X close it.
	The Store's FEATURED card sells it too (StoreController).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Net = require(Shared.Net)
local StarterPackView = require(script.Parent.Parent.UI.StarterPackView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local StarterPackController = {}

local KEY = StarterPackView.Key
local player = Players.LocalPlayer

local refs: StarterPackView.Refs? = nil
local shown = false -- this session's one popup
local isOpen = false
local leftAt = 0 -- os.clock() when the State's Left was read
local leftSeconds = 0

local function offer(): { [string]: any }?
	local state = StateController.get()
	local record = if type(state) == "table" then state.StarterPack else nil
	return if type(record) == "table" then record else nil
end

-- Seconds of the offer left now (counted down between State pushes).
local function leftNow(): number
	return math.max(0, leftSeconds - (os.clock() - leftAt))
end

function StarterPackController.close()
	local view = refs
	isOpen = false
	if view then
		view.Gui.Enabled = false
	end
	if GuiService.SelectedObject and view and GuiService.SelectedObject:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
end

local function ensureView(): StarterPackView.Refs
	if refs then
		return refs :: StarterPackView.Refs
	end
	local view = StarterPackView.build()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Window.Close.Activated:Connect(function()
		StarterPackController.close()
		Sfx.play("UIClick")
	end)
	view.Later.Activated:Connect(function()
		StarterPackController.close()
		Sfx.play("UIClick")
	end)
	view.Price.Activated:Connect(function()
		StarterPackView.setStatus(view, nil)
		Net.send("StoreAction", "Buy", { Key = KEY })
		Sfx.play("UIClick")
	end)
	refs = view
	return view
end

function StarterPackController.open()
	local view = ensureView()
	isOpen = true
	local fit = view.Gui:FindFirstChild("Scale") :: UIScale?
	if fit then
		fit.Scale = HudController.uiScale()
	end
	StarterPackView.setStatus(view, nil)
	view.Gui.Enabled = true
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.Price else nil
	Sfx.play("UIClick")
	task.spawn(function()
		while isOpen and view.Gui.Enabled do
			local record = offer()
			if leftNow() <= 0 or (record and record.Open ~= true) then
				StarterPackController.close()
				break
			end
			task.wait(1)
		end
	end)
end

-- Is the popup due now? (see the header)
local function due(record: { [string]: any }): boolean
	if shown or record.Open ~= true or record.Bought == true then
		return false
	end
	local played = MonetizationConfig.StarterOffer.Seconds - leftNow()
	if played < MonetizationConfig.StarterOffer.PopupAfter or leftNow() <= 60 then
		return false
	end
	local state = StateController.get()
	local tutorial = if type(state) == "table" then state.Tutorial else nil
	if type(tutorial) == "table" and tutorial.Done ~= true then
		return false
	end
	if ReplicatedStorage:GetAttribute(MonetizationConfig.ReceiptsAttribute) ~= true or not MonetizationConfig.keyLive(KEY) then
		return false
	end
	return not MenuPanels.otherOpen("StarterPackController")
end

local function onState()
	local record = offer()
	if not record then
		return
	end
	local left = tonumber(record.Left)
	if left and left == left then
		leftSeconds = left
		leftAt = os.clock()
	end
	if isOpen and record.Open ~= true then
		StarterPackController.close()
	end
end

function StarterPackController.init()
	Net.listen("PurchasePrompt", function(payload: any)
		local view = refs
		if not isOpen or not view or type(payload) ~= "table" or payload.Product ~= KEY then
			return
		end
		if payload.Status == "Prompted" then
			StarterPackController.close()
		else
			StarterPackView.setStatus(view, MonetizationConfig.StatusText[payload.Status] or MonetizationConfig.StatusText.Unknown)
		end
	end)
end

function StarterPackController.start()
	StateController.onChanged(onState)
	onState()
	-- the popup waits for its moment (checked every few seconds, never every frame)
	task.spawn(function()
		while not shown do
			task.wait(5)
			local record = offer()
			if record and record.Open ~= true then
				break -- bought, or the offer is over: it never opens again this session
			end
			if record and due(record) then
				shown = true
				StarterPackController.open()
			end
		end
	end)
end

return StarterPackController
