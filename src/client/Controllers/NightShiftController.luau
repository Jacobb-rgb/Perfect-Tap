--[[
	NightShiftController: the "While you were away" window (Night Shift, UI/
	NightShiftView). OpenUI "Offline" fills and opens it, once the loading screen
	is gone. Collect, X, B or Backspace close it, not while Open Crate waits for
	the server (UI/NightShiftFlow); a crate not opened waits for the next return.
	Open Crate asks the server (NightCrate); a request the rate limit dropped gets
	no answer, so the button comes back after ResultTimeout. A late prize opens the
	window again. A panel like the others (MenuPanels: isOpen, close): popups wait
	while it is up, and it waits for a free screen (screenFree: no other panel, no
	tutorial card, no cleaning close-up, build mode or other control lock, no egg
	opening), so the login streak popup stays. It must stay before every other OpenUI listener in the ORDER
	(init.client): a remote's queued events go to its first connection only.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Loading = require(script.Parent.Parent.Util.Loading)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local Motion = require(script.Parent.Parent.UI.Motion)
local NightShiftFlow = require(script.Parent.Parent.UI.NightShiftFlow)
local NightShiftView = require(script.Parent.Parent.UI.NightShiftView)

local NightShiftController = {}

NightShiftController.ResultTimeout = 6
NightShiftController.PanelWait = 0.5 -- seconds between looks while another panel is up

local CLOSE_ACTION = "TerraForgeNightShiftClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 20

local view: NightShiftView.Refs? = nil
local flow = NightShiftFlow.new()

function NightShiftController.isOpen(): boolean
	local refs = view
	return refs ~= nil and refs.Gui.Enabled
end

function NightShiftController.close()
	local refs = view
	if not refs or not refs.Gui.Enabled then
		return
	end
	refs.Gui.Enabled = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(refs.Gui) then
		GuiService.SelectedObject = nil
	end
end

-- Does something hold the player's controls (build mode, a close-up)? (Util/PlayerControls, read on use)
function NightShiftController.controlsHeld(): boolean
	local ok, controls = pcall(require, script.Parent.Parent.Util.PlayerControls)
	return ok and type(controls) == "table" and controls.owner() ~= nil
end

-- Nothing else holds the screen (QuestController's rule, and an egg opening).
function NightShiftController.screenFree(): boolean
	for _, pair in { { "TutorialController", "isShown" }, { "CleaningController", "isActive" }, { "CapsuleController", "showing" } } do
		local name, method = pair[1], pair[2]
		local controller = MenuPanels.controller(name)
		if controller and type(controller[method]) == "function" then
			local ok, busy = pcall(controller[method])
			if ok and busy then
				return false
			end
		end
	end
	return not NightShiftController.controlsHeld() and not MenuPanels.otherOpen("NightShiftController")
end

-- The window's own ways out: not while the crate's answer is on its way.
local function leave()
	if NightShiftFlow.mayClose(flow) then
		Sfx.play("UIClick")
		NightShiftController.close()
	end
end

local function openCrate()
	local refs = view
	if not refs or not NightShiftFlow.mayPress(flow) then
		return
	end
	Sfx.play("UIClick")
	NightShiftView.setOpening(refs, true)
	local token = NightShiftFlow.press(flow)
	Net.send("NightCrate")
	task.delay(NightShiftController.ResultTimeout, function()
		if NightShiftFlow.timeout(flow, token) and view then
			NightShiftView.setOpening(view, false)
		end
	end)
end

local function refsOf(): NightShiftView.Refs
	local refs = view
	if refs then
		return refs
	end
	local built = NightShiftView.build()
	built.Gui:SetAttribute("TerraForge", true)
	local scale = built.Gui:FindFirstChild("Scale")
	if scale and scale:IsA("UIScale") then
		scale.Scale = require(script.Parent.HudController).uiScale()
	end
	built.Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	built.Collect.Activated:Connect(leave)
	built.Close.Activated:Connect(leave)
	built.Open.Activated:Connect(openCrate)
	view = built
	return built
end

-- The window up, with its keys.
local function raise(refs: NightShiftView.Refs)
	refs.Gui.Enabled = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			leave()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = refs.Collect
	end
end

local function show(payload: { [string]: any })
	-- never under the loading screen (Util/Loading, at most MaxWait), nor over anything else
	if not Loading.isDone() or not NightShiftController.screenFree() then
		task.spawn(function()
			Loading.wait()
			while not NightShiftController.screenFree() do
				task.wait(NightShiftController.PanelWait)
			end
			show(payload)
		end)
		return
	end
	local refs = refsOf()
	NightShiftFlow.show(flow)
	NightShiftView.setOpening(refs, false)
	NightShiftView.fill(refs, payload)
	raise(refs)
	if Motion.enabled() then
		Motion.pop(refs.Panel, refs.Dim) -- (UI/Motion: none with Reduce motion)
	else
		Motion.classicPop(refs.Panel, nil, 0.6, 0.3)
	end
	Sfx.play("CoinBurst")
end

local function answered(result: any)
	local refs = view
	if not refs then
		return
	end
	local what = NightShiftFlow.answer(flow, result)
	if what == "Ignore" then
		return
	end
	NightShiftView.setOpening(refs, false)
	NightShiftView.setPrize(refs, result)
	if what == "Prize" then
		if not refs.Gui.Enabled then
			raise(refs)
		end
		Sfx.play("Discovery")
		if Motion.enabled() then
			Motion.pop(refs.CrateCard, nil)
		end
	end
	if UserInputService.GamepadEnabled and refs.Gui.Enabled then
		GuiService.SelectedObject = refs.Collect
	end
end

function NightShiftController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind == "Offline" and type(payload) == "table" then
			show(payload)
		end
	end)
	Net.listen("NightCrateResult", answered)
end

function NightShiftController.start() end

return NightShiftController
