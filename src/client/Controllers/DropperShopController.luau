--[[
	DropperShopController: the DROPPERS shop's showroom on this screen.

	The server builds the shop's solid shell only (Districts/Droppers.luau).
	Every half second, for each house tagged DropperShopBuilder.Tag:
	  - within ShowDistance of the camera its showroom is in the scene
	    (DropperShopBuilder.build, once; then only parented to the house)
	  - past HideDistance it leaves the scene but is kept (unparented)
	  - past DropDistance (the mine floors, the far plots) it is thrown away
	A house that streams out and back in is a new instance: the old one's
	showroom goes, the new one gets its own.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperShopBuilder = require(Shared.Builders.DropperShopBuilder)

local DropperShopController = {}

-- house -> its showroom (built once; parented to the house while near)
local built: { [Instance]: Model } = {}

--[[
	(2026-11-15 perf pass) A new showroom (~500 parts) goes into the scene a slice a frame, not all
	in one frame (that frame hitched when you walked up to the shop): its pieces wait in a holder
	and SliceSize of them move into it each frame. A showroom dropped meanwhile takes its
	waiting pieces with it.
]]
DropperShopController.SliceSize = 40 -- parts (top-level pieces) a frame: the ~500-part room in ~13 frames
local function addInSlices(model: Model, house: Instance)
	local pieces = model:GetChildren()
	if #pieces <= DropperShopController.SliceSize then
		model.Parent = house
		return
	end
	local holder = Instance.new("Folder")
	for _, piece in pieces do
		piece.Parent = holder
	end
	model.Parent = house
	task.spawn(function()
		for i, piece in pieces do
			if built[house] ~= model then
				break
			end
			piece.Parent = model
			if i % DropperShopController.SliceSize == 0 then
				task.wait()
			end
		end
		holder:Destroy()
	end)
end

local function drop(house: Instance)
	local model = built[house]
	if model then
		model:Destroy()
		built[house] = nil
	end
end

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local from = camera.CFrame.Position
	for house in built do
		if not house:IsDescendantOf(Workspace) then
			drop(house)
		end
	end
	for _, house in CollectionService:GetTagged(DropperShopBuilder.Tag) do
		local frame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
		if typeof(frame) == "CFrame" and house:IsDescendantOf(Workspace) then
			local distance = (frame.Position - from).Magnitude
			local model = built[house]
			if distance <= DropperShopBuilder.ShowDistance then
				if not model then
					local made = DropperShopBuilder.build(frame)
					built[house] = made
					addInSlices(made, house)
					model = made
				end
				if model and model.Parent ~= house then
					model.Parent = house
				end
			elseif model and distance > DropperShopBuilder.DropDistance then
				drop(house)
			elseif model and distance > DropperShopBuilder.HideDistance and model.Parent ~= nil then
				model.Parent = nil
			end
		end
	end
end

function DropperShopController.start()
	while true do
		local ok, err = pcall(function()
			update()
		end)
		if not ok then
			warn("[DropperShopController] " .. tostring(err))
		end
		task.wait(0.5)
	end
end

return DropperShopController
