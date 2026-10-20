--[[
	Hides Roblox's touch controls (thumbstick, jump) while a window is open,
	so they never cover its buttons on phones. follow(gui): while gui is
	enabled and in the PlayerGui the controls stay hidden; they come back once
	no followed window is open. Used by the light UI's windows that don't hide
	them themselves (Sell, Tech Shop, Train, Iron Box, Ore Pen).
]]

local GuiService = game:GetService("GuiService")

local TouchControls = {}

local open: { [Instance]: boolean } = {}

local function update(gui: ScreenGui)
	local isOpen = gui.Enabled and gui.Parent ~= nil
	local was = open[gui] == true
	if isOpen == was then
		return
	end
	if isOpen then
		open[gui] = true
	else
		open[gui] = nil
	end
	pcall(function()
		GuiService.TouchControlsEnabled = next(open) == nil
	end)
end

function TouchControls.follow(gui: ScreenGui)
	pcall(function()
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			update(gui)
		end)
		gui.AncestryChanged:Connect(function()
			update(gui)
		end)
	end)
end

-- How many followed windows are open now (tests).
function TouchControls.openCount(): number
	local n = 0
	for _ in open do
		n += 1
	end
	return n
end

return TouchControls
