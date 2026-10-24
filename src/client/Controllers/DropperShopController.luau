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
					model = DropperShopBuilder.build(frame)
					built[house] = model
				end
				if model.Parent ~= house then
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
