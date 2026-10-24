--[[
	StudStyleService: switches the studded style (Shared/StudStyle,
	StudStyleConfig, docs/STUD_STYLE.md) for every client.

	- At start the Workspace attributes "StudStyle" (on / off) and
	  "StudStyleLook" ("Classic" / "Custom") come from StudStyleConfig, unless
	  the place already has them (a Studio test place). Every client follows
	  them (StudStyleController restyles what streams to it), so the look can be
	  switched live from the server's command bar:
	    workspace:SetAttribute("StudStyle", false)  -- every client puts the map back
	- While it is on, the custom stud MaterialVariants live in MaterialService
	  (when the stud pictures are uploaded: StudStyleConfig.customReady); off,
	  they are removed. The server never restyles the map's parts itself.
]]

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudStyle = require(Shared.StudStyle)
local StudStyleConfig = require(Shared.Config.StudStyleConfig)

local StudStyleService = {}

local function sync()
	if Workspace:GetAttribute("StudStyle") == true then
		StudStyle.ensureVariants(MaterialService)
	else
		StudStyle.removeVariants(MaterialService)
	end
end

function StudStyleService.init()
	if type(Workspace:GetAttribute("StudStyle")) ~= "boolean" then
		Workspace:SetAttribute("StudStyle", StudStyleConfig.Enabled)
	end
	local look = Workspace:GetAttribute("StudStyleLook")
	if look ~= "Classic" and look ~= "Custom" then
		Workspace:SetAttribute("StudStyleLook", StudStyleConfig.Look)
	end
	sync()
end

function StudStyleService.start()
	Workspace:GetAttributeChangedSignal("StudStyle"):Connect(sync)
end

return StudStyleService
