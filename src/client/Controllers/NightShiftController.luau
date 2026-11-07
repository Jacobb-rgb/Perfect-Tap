--[[
	NightShiftController: the "While you were away" window (Night Shift, UI/
	NightShiftView). OpenUI "Offline" fills and opens it, once the loading screen
	is gone. Collect, X, B or Backspace close it; a crate not opened waits for
	the next return (the server keeps it). Open Crate asks the server
	(NightCrate); a request the rate limit dropped gets no answer, so the
	button comes back after ResultTimeout.
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
local Motion = require(script.Parent.Parent.UI.Motion)
local NightShiftView = require(script.Parent.Parent.UI.NightShiftView)

local NightShiftController = {}

NightShiftController.ResultTimeout = 6

local CLOSE_ACTION = "TerraForgeNightShiftClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value

local view: NightShiftView.Refs? = nil
local opening = 0 -- counts the requests: a late timeout never undoes a newer one

local function close()
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

local function openCrate()
	local refs = view
	if not refs or not refs.Open.Active then
		return
	end
	Sfx.play("UIClick")
	NightShiftView.setOpening(refs, true)
	opening += 1
	local request = opening
	Net.send("NightCrate")
	task.delay(NightShiftController.ResultTimeout, function()
		if request == opening and view then
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
	built.Collect.Activated:Connect(function()
		Sfx.play("UIClick")
		close()
	end)
	built.Close.Activated:Connect(function()
		Sfx.play("UIClick")
		close()
	end)
	built.Open.Activated:Connect(openCrate)
	view = built
	return built
end

local function show(payload: { [string]: any })
	-- never under the loading screen (Util/Loading, at most MaxWait)
	if not Loading.isDone() then
		task.spawn(function()
			Loading.wait()
			show(payload)
		end)
		return
	end
	local refs = refsOf()
	opening += 1
	NightShiftView.setOpening(refs, false)
	NightShiftView.fill(refs, payload)
	refs.Gui.Enabled = true
	if Motion.enabled() then
		Motion.pop(refs.Panel, refs.Dim) -- (UI/Motion: none with Reduce motion)
	else
		Motion.classicPop(refs.Panel, nil, 0.6, 0.3)
	end
	Sfx.play("CoinBurst")
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = refs.Collect
	end
end

function NightShiftController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind == "Offline" and type(payload) == "table" then
			show(payload)
		end
	end)
	Net.listen("NightCrateResult", function(result)
		local refs = view
		if not refs then
			return
		end
		opening += 1
		NightShiftView.setOpening(refs, false)
		NightShiftView.setPrize(refs, result)
		if type(result) == "table" and result.Ok then
			Sfx.play("Discovery")
			if refs.Gui.Enabled and Motion.enabled() then
				Motion.pop(refs.CrateCard, nil)
			end
		end
		if UserInputService.GamepadEnabled and refs.Gui.Enabled then
			GuiService.SelectedObject = refs.Collect
		end
	end)
end

function NightShiftController.start() end

return NightShiftController
