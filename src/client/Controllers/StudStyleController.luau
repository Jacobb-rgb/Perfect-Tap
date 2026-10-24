--[[
	StudStyleController: the studded style on this client (Shared/StudStyle,
	StudStyleConfig, docs/STUD_STYLE.md). Only visuals, no network cost: the
	server's map is never changed, this client restyles the parts that stream
	to it (and every part added later: machines, plots, rebuilt pieces),
	StudStyleConfig.BatchSize per frame.

	Follows the Workspace attributes StudStyleService sets: "StudStyle"
	(on / off) and "StudStyleLook" ("Classic" / "Custom"). Switched off or to
	another look, every restyled part goes back exactly as it was first.
	When the server's custom stud materials arrive (MaterialService.TFStudStyle),
	the map is gone over again for the parts that were waiting for them.
]]

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudStyle = require(Shared.StudStyle)
local StudStyleConfig = require(Shared.Config.StudStyleConfig)

local StudStyleController = {}

local stop: (() -> ())? = nil
local activeLook: StudStyleConfig.Look? = nil

-- The wanted state: on / off and the look (the attributes, else the config).
function StudStyleController.wanted(): (boolean, StudStyleConfig.Look)
	local on = Workspace:GetAttribute("StudStyle")
	local look = Workspace:GetAttribute("StudStyleLook")
	local wantedLook = StudStyle.look(if look == "Classic" or look == "Custom" then look else StudStyleConfig.Look)
	return if type(on) == "boolean" then on else StudStyleConfig.Enabled, wantedLook
end

local function sync()
	local on, look = StudStyleController.wanted()
	local running = stop
	if running and (not on or look ~= activeLook) then
		running()
		stop = nil
		activeLook = nil
		StudStyle.restoreTree(Workspace)
	end
	if on and not stop then
		activeLook = look
		stop = StudStyle.watch(Workspace, look)
	end
end

-- The custom stud materials came: watch again from the start (parts that have
-- studs already are skipped, the ones that waited for the materials get them).
local function rewatch()
	local running = stop
	if running then
		running()
		stop = nil
		activeLook = nil
	end
	sync()
end

function StudStyleController.start()
	sync()
	Workspace:GetAttributeChangedSignal("StudStyle"):Connect(sync)
	Workspace:GetAttributeChangedSignal("StudStyleLook"):Connect(sync)
	MaterialService.ChildAdded:Connect(function(child: Instance)
		if child.Name == StudStyle.FolderName then
			rewatch()
		end
	end)
end

return StudStyleController
