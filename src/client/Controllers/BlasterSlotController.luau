--[[
	BlasterSlotController: the light HUD's BLASTER slot (owner 2026-10-28:
	"a custom slot for the blaster left of the backpack, the pair in the
	middle"; UI/HudBubble.blasterSlot and carryGroup). Light UI only: the
	dark HUD keeps Roblox's own hotbar and this controller does nothing there.

	  Roblox's hotbar  off for good (Util/Hotbar.hideCore, retried until the
	                   CoreGui takes it); the close-ups give back only "off"
	                   (Hotbar.restoreCore)
	  the slot         a click, a tap or a gamepad's A on it (the UI selection
	                   reaches it) equips the Blaster from the backpack, or
	                   puts it away (Hotbar.toggle)
	  1                the same on a keyboard (Roblox's hotbar keys went with
	                   it): ContextActionService, no touch button, bound only
	                   while the slot shows
	  gamepad          no button of its own: R2 near a rock already equips
	                   (MiningController.tryEquip) and L1 / R1 are taken (the
	                   panels, build mode, the backpack)
	  key hint         "1" on the slot's top-left corner with a keyboard,
	                   nothing on touch or a gamepad
	  equipped         the slot's gold ring while the Blaster is in the
	                   character's hand (its ChildAdded / ChildRemoved, and
	                   every new character)
	Refused while a close-up holds the controls (PlayerControls.owner():
	build mode, the anvil, the vault) or the cleaning minigame runs
	(CleaningController.isActive), like MiningController.canUse. The slot
	hides with the bottom group: the "Carry" holder (build mode hides it)
	and the HUD (the close-ups turn it off).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local HudView = require(script.Parent.Parent.UI.HudView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Hotbar = require(script.Parent.Parent.Util.Hotbar)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local CleaningController = require(script.Parent.CleaningController)

local BlasterSlotController = {}

BlasterSlotController.Key = Enum.KeyCode.One
BlasterSlotController.KeyText = "1"

local KEY_ACTION = "TerraForgeBlasterSlot"

local player = Players.LocalPlayer
local bound = false
local characterConnections: { RBXScriptConnection } = {}

-- A close-up or the cleaning minigame owns the player: no equipping there.
local function busy(): boolean
	return PlayerControls.owner() ~= nil or CleaningController.isActive()
end

-- Equips the Blaster from the backpack, or puts it away (refused while busy).
function BlasterSlotController.toggle(): Hotbar.Outcome
	local outcome: Hotbar.Outcome = Hotbar.toggle(player.Character, player:FindFirstChildOfClass("Backpack"), busy())
	if outcome == "Equipped" or outcome == "Unequipped" then
		Sfx.play("UIClick")
	end
	return outcome
end

local function onKey(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or busy() then
		return Enum.ContextActionResult.Pass
	end
	BlasterSlotController.toggle()
	return Enum.ContextActionResult.Sink
end

-- Is the slot on screen (the HUD on, the bottom group shown)?
local function slotShows(hud: HudView.Refs): boolean
	local slot = hud.BlasterSlot
	return slot ~= nil and slot.Visible and hud.CarryPanel.Visible and hud.Gui.Enabled
end

-- 1 works only while the slot shows.
local function refreshBinding(hud: HudView.Refs)
	local shows = slotShows(hud)
	if shows and not bound then
		ContextActionService:BindAction(KEY_ACTION, onKey, false, BlasterSlotController.Key)
	elseif bound and not shows then
		ContextActionService:UnbindAction(KEY_ACTION)
	end
	bound = shows
end

-- "1" on a keyboard; nothing on touch or a gamepad (no button bound there).
local function refreshKeyHint(hud: HudView.Refs)
	local keyboard = not MenuPanels.usingGamepad() and not MenuPanels.isTouch()
	HudView.setBlasterKey(hud, if keyboard then BlasterSlotController.KeyText else nil)
end

local function refreshEquipped(hud: HudView.Refs)
	HudView.setBlasterEquipped(hud, Hotbar.equipped(player.Character))
end

-- Follows a character's tools for the slot's equipped look.
local function watchCharacter(hud: HudView.Refs, character: Model?)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if character then
		local function changed(child: Instance)
			if child:IsA("Tool") then
				refreshEquipped(hud)
			end
		end
		table.insert(characterConnections, character.ChildAdded:Connect(changed))
		table.insert(characterConnections, character.ChildRemoved:Connect(changed))
	end
	refreshEquipped(hud)
end

function BlasterSlotController.init()
	if not UIConfig.lightUI() then
		return
	end
	-- the light UI's own slot replaces Roblox's hotbar
	task.spawn(function()
		if not Hotbar.hideCore() then
			warn("[BlasterSlotController] Roblox's hotbar did not turn off")
		end
	end)
end

function BlasterSlotController.start()
	if not UIConfig.lightUI() then
		return
	end
	local hud = HudController.refs()
	local slot = hud and hud.BlasterSlot
	if not hud or not slot then
		return
	end
	slot.Activated:Connect(function()
		BlasterSlotController.toggle()
	end)
	for _, signal in
		{
			hud.Gui:GetPropertyChangedSignal("Enabled"),
			hud.CarryPanel:GetPropertyChangedSignal("Visible"),
			slot:GetPropertyChangedSignal("Visible"),
		}
	do
		signal:Connect(function()
			refreshBinding(hud)
		end)
	end
	refreshBinding(hud)
	refreshKeyHint(hud)
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshKeyHint(hud)
	end)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(hud, character)
	end)
	watchCharacter(hud, player.Character)
end

return BlasterSlotController
