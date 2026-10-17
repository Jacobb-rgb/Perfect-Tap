--[[
	MenuPanels: what the side menu's panels (CodexController,
	SettingsController, LeaderboardController) share on the client.

	  controller(name)   another controller module by name, required with
	                     pcall on first use (nil while it doesn't exist: the
	                     packages that add GolemController, BoostController,
	                     ArtifactController... may merge later)
	  call(name, fn, ...) calls controller(name)[fn](...) when it exists
	  closeOthers(self)  one panel in the middle of the screen at a time:
	                     closes every other known panel that is open
	  otherOpen(self)    true while another known panel is open (an open
	                     panel closes itself when one appears)
	  device helpers     usingGamepad / isTouch / padName / glyph
]]

local UserInputService = game:GetService("UserInputService")

local MenuPanels = {}

-- Panel controllers with isOpen() and close() (the ones that don't exist are skipped).
MenuPanels.Names = {
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"TechShopController",
	"BoostController",
	"GearController",
	"EnchantController",
	"CapsuleController",
	"GolemController",
	"WheelController",
	"ArtifactController",
	"StoreController",
	"CodexController",
	"SettingsController",
	"LeaderboardController",
}

local cache: { [string]: any } = {}

local function folder(): Instance?
	local client = script.Parent.Parent
	return client:FindFirstChild("Controllers")
end

-- The controller module `name`, or nil (missing, or it failed to load).
function MenuPanels.controller(name: string): any?
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	local controllers = folder()
	local module = controllers and controllers:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module :: any)
	if ok and type(result) == "table" then
		cache[name] = result
		return result
	end
	return nil
end

-- Calls controller(name)[fn](...) when both exist. Returns whether it ran without an error.
function MenuPanels.call(name: string, fn: string, ...: any): boolean
	local c = MenuPanels.controller(name)
	local f = c and c[fn]
	if type(f) ~= "function" then
		return false
	end
	local ok, err = pcall(f, ...)
	if not ok then
		warn(`[MenuPanels] {name}.{fn} failed: {err}`)
	end
	return ok
end

local function isOpen(c: any): boolean
	if type(c) ~= "table" or type(c.isOpen) ~= "function" then
		return false
	end
	local ok, open = pcall(c.isOpen)
	return ok and open == true
end

function MenuPanels.isOpen(name: string): boolean
	return isOpen(MenuPanels.controller(name))
end

function MenuPanels.otherOpen(self: string): boolean
	for _, name in MenuPanels.Names do
		if name ~= self and MenuPanels.isOpen(name) then
			return true
		end
	end
	return false
end

function MenuPanels.closeOthers(self: string)
	for _, name in MenuPanels.Names do
		if name ~= self and MenuPanels.isOpen(name) then
			MenuPanels.call(name, "close")
		end
	end
end

---------------------------------------------------------------- devices

function MenuPanels.usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

function MenuPanels.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- A gamepad button's name on this platform ("A" / "Cross"), for when it has no glyph image.
function MenuPanels.padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

-- The platform's glyph image for a gamepad button ("" when it has none).
function MenuPanels.glyph(key: Enum.KeyCode): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	return if ok and type(image) == "string" then image else ""
end

return MenuPanels
