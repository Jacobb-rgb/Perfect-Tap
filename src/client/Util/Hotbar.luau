--[[
	Hotbar: Roblox's own hotbar (the CoreGui Backpack) and the Blaster in
	hand.

	The light UI (UIConfig.lightUI()) draws its own BLASTER slot left of the
	backpack button (HudBubble.blasterSlot, owner 2026-10-28) and turns
	Roblox's hotbar off for good (hideCore, BlasterSlotController). The
	close-ups (PlacementController, CleaningController, VaultController)
	still hide it while they own the screen and give back what they saved
	with restoreCore, which on the light UI never turns it on again. The dark
	HUD keeps Roblox's hotbar.

	toggle is the slot's (and the 1 key's) decision: equip the Blaster from
	the backpack, or put it away; never while `busy` (a close-up or the
	cleaning minigame). Pure apart from the calls it makes on what it is
	given (specs drive it with a fake character and backpack).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)

local Hotbar = {}

Hotbar.ToolName = BlasterBuilder.ToolName
Hotbar.HideTries = 40 -- hideCore: tries before it gives up (the CoreGui can refuse early on)
Hotbar.HideWait = 0.25 -- seconds between two tries
Hotbar.Core = StarterGui -- (specs swap in a stand-in with Set / GetCoreGuiEnabled)

-- Should Roblox's own hotbar show (outside the close-ups)? Only on the dark HUD.
function Hotbar.coreWanted(): boolean
	return not UIConfig.lightUI()
end

-- What a close-up gives back for the flag it saved: never on with the light UI.
function Hotbar.restoreValue(saved: boolean): boolean
	return saved == true and Hotbar.coreWanted()
end

-- A close-up gives Roblox's hotbar back (`saved` = what it read on entry; nil: nothing read).
function Hotbar.restoreCore(saved: boolean?)
	if saved == nil then
		return
	end
	local core = Hotbar.Core
	pcall(core.SetCoreGuiEnabled, core, Enum.CoreGuiType.Backpack, Hotbar.restoreValue(saved))
end

--[[
	Turns Roblox's hotbar off, retrying (pcall'd, `tries` times, `HideWait`
	apart) until the CoreGui says it is off. True when it is. Yields.
]]
function Hotbar.hideCore(tries: number?): boolean
	local count = math.max(1, tries or Hotbar.HideTries)
	for i = 1, count do
		local core = Hotbar.Core
		pcall(core.SetCoreGuiEnabled, core, Enum.CoreGuiType.Backpack, false)
		local ok, on = pcall(core.GetCoreGuiEnabled, core, Enum.CoreGuiType.Backpack)
		if ok and on == false then
			return true
		end
		if i < count then
			task.wait(Hotbar.HideWait)
		end
	end
	return false
end

-- The Blaster tool in `container` (a character or a Backpack), else nil.
function Hotbar.tool(container: Instance?): Tool?
	local tool = container and container:FindFirstChild(Hotbar.ToolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- Is the Blaster in the character's hand?
function Hotbar.equipped(character: Instance?): boolean
	return Hotbar.tool(character) ~= nil
end

export type Outcome = "Equipped" | "Unequipped" | "Busy" | "NoTool" | "NoCharacter"

--[[
	The slot's toggle: the Blaster in hand goes away (Humanoid:UnequipTools),
	else the Blaster from `backpack` goes into the hand (Humanoid:EquipTool).
	Refused while `busy`; nothing without a living humanoid or a Blaster.
	Returns what happened.
]]
function Hotbar.toggle(character: Instance?, backpack: Instance?, busy: boolean): Outcome
	if busy then
		return "Busy"
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return "NoCharacter"
	end
	if Hotbar.equipped(character) then
		humanoid:UnequipTools()
		return "Unequipped"
	end
	local tool = Hotbar.tool(backpack)
	if not tool then
		return "NoTool"
	end
	humanoid:EquipTool(tool)
	return "Equipped"
end

return Hotbar
