--[[
	TeleportController: the quick-teleport buttons (TeleportView) in the HUD.

	  - BASE / LOBBY / VAULT at the top centre; the elevator's button is
	    ElevatorController's (left side menu), which calls request("Elevator")
	  - mouse click / touch tap on a button; gamepad: D-pad down jumps into the
	    bar (GuiService selection, left / right to move, A to go, B or D-pad
	    down again to leave); the D-pad glyph shows next to the bar while a
	    gamepad is in use
	  - a jump: the screen fades dark, Teleport goes to the server, the
	    TeleportResult (or ReplyTimeout) fades it back; refusals show as a
	    toast; then every button shows the cooldown
	  - refused on the client already while a minigame or build mode holds
	    the controls (PlayerControls) or during the cooldown
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeleportConfig = require(Shared.Config.TeleportConfig)
local Net = require(Shared.Net)
local TeleportView = require(script.Parent.Parent.UI.TeleportView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local CleaningController = require(script.Parent.CleaningController)

local TeleportController = {}

local player = Players.LocalPlayer
local refs: TeleportView.Refs? = nil
local fadeCover: Frame? = nil
local readyAt = 0 -- os.clock() when the next teleport is allowed
local waiting: string? = nil -- the destination of the request in flight
local waitToken = 0

local GAMEPAD_KEY = Enum.KeyCode.DPadDown

local function isGamepad(inputType: Enum.UserInputType): boolean
	return inputType.Name:sub(1, 7) == "Gamepad"
end

local function fade(to: number)
	local cover = fadeCover
	if cover then
		TweenService:Create(cover, TweenInfo.new(TeleportConfig.Fade), { BackgroundTransparency = to }):Play()
	end
end

local function cooldownLoop()
	local r = refs
	if not r then
		return
	end
	while true do
		local left = readyAt - os.clock()
		TeleportView.setCooldown(r, math.max(0, left))
		if left <= 0 then
			return
		end
		task.wait(0.1)
	end
end

local function startCooldown(seconds: number)
	readyAt = math.max(readyAt, os.clock() + seconds)
	task.spawn(cooldownLoop)
end

local function finish(token: number)
	if token ~= waitToken then
		return
	end
	waiting = nil
	fade(1)
end

-- Asks the server to move us to a destination.
function TeleportController.request(id: string)
	local spot = TeleportConfig.ById[id]
	if not spot or waiting then
		return
	end
	if os.clock() < readyAt then
		HudController.toast(TeleportConfig.Reasons.Cooldown, "Deny")
		return
	end
	if CleaningController.isActive() then
		HudController.toast(TeleportConfig.Reasons.Cleaning, "Deny")
		return
	end
	if PlayerControls.owner() ~= nil then
		HudController.toast("Finish what you're doing first.", "Deny")
		return
	end
	Sfx.play("UIClick")
	GuiService.SelectedObject = nil
	waiting = spot.Id
	waitToken += 1
	local token = waitToken
	fade(0)
	task.delay(TeleportConfig.Fade, function()
		if token == waitToken then
			Net.send("Teleport", spot.Id)
		end
	end)
	task.delay(TeleportConfig.Fade + TeleportConfig.ReplyTimeout, finish, token)
end

local function onResult(payload: any)
	if type(payload) ~= "table" or waiting == nil then
		return
	end
	if payload.Ok == true then
		startCooldown(TeleportConfig.Cooldown)
	else
		local reason = if type(payload.Reason) == "string" then payload.Reason else nil
		HudController.toast(reason and TeleportConfig.Reasons[reason] or TeleportConfig.Reasons.NotHere, "Deny")
		if reason == "Cooldown" then
			startCooldown(TeleportConfig.Cooldown - TeleportConfig.ServerCooldown + 0.5)
		end
	end
	-- a short beat on the dark screen so the new place has streamed in
	local token = waitToken
	task.delay(0.1, finish, token)
end

local function ownsSelection(): boolean
	local r = refs
	local selected = GuiService.SelectedObject
	if not r or not selected then
		return false
	end
	for _, button in r.Buttons do
		if selected == button then
			return true
		end
	end
	return false
end

local function onGamepadKey(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local r = refs
	if not r then
		return Enum.ContextActionResult.Pass
	end
	if ownsSelection() then
		GuiService.SelectedObject = nil
		return Enum.ContextActionResult.Sink
	end
	-- only when nothing else uses the selection or the controls
	if GuiService.SelectedObject ~= nil or PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return Enum.ContextActionResult.Pass
	end
	local base = r.Buttons.Base
	if base and base:IsDescendantOf(player) and (base.Parent :: Frame).Visible then
		GuiService.SelectedObject = base
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function updateHint()
	local r = refs
	if not r then
		return
	end
	local gamepad = isGamepad(UserInputService:GetLastInputType())
	if gamepad then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(GAMEPAD_KEY)
		end)
		r.Hint.Image = if ok and type(image) == "string" then image else ""
	end
	r.Hint.Visible = gamepad and r.Hint.Image ~= ""
end

function TeleportController.init()
	local hud = HudController.refs()
	local built = TeleportView.build(hud.TopBar, HudController.uiScale())
	refs = built
	for id, button in built.Buttons do
		button.Activated:Connect(function()
			TeleportController.request(id)
		end)
	end
	local gui, cover = TeleportView.buildFade()
	gui.Parent = player:WaitForChild("PlayerGui")
	fadeCover = cover
	Net.listen("TeleportResult", onResult)
end

function TeleportController.start()
	local r = refs
	if not r then
		return
	end
	local hud = HudController.refs()
	-- phone <-> big screen: the bar's buttons follow the HUD scale
	local scale = hud.Gui:FindFirstChild("Scale")
	if scale and scale:IsA("UIScale") then
		local function relayout()
			TeleportView.relayout(r, hud.TopBar, scale.Scale)
		end
		scale:GetPropertyChangedSignal("Scale"):Connect(relayout)
		relayout()
	end
	ContextActionService:BindAction("TerraForgeTeleportBar", onGamepadKey, false, GAMEPAD_KEY)
	UserInputService.LastInputTypeChanged:Connect(updateHint)
	updateHint()
end

return TeleportController
