--[[
	DropperShopController: the DROPPERS shop's showroom on this screen.

	The server builds the shop's solid shell only (Districts/Droppers.luau);
	every half second the houses tagged DropperShopBuilder.Tag that are
	within ShowDistance of the camera get their showroom built here
	(DropperShopBuilder.show: the real droppers, the DARK MATTER DROPPER on
	its podium, the Dropper Master, the floor, the walls, the chandeliers),
	and past HideDistance it goes again (phones: those parts only exist near
	the shop). A house that streams out and back in is a new instance and
	gets a new showroom.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperShopBuilder = require(Shared.Builders.DropperShopBuilder)

local DropperShopController = {}

local shown: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local from = camera.CFrame.Position
	for _, house in CollectionService:GetTagged(DropperShopBuilder.Tag) do
		local frame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
		if typeof(frame) == "CFrame" and house:IsDescendantOf(Workspace) then
			local distance = (frame.Position - from).Magnitude
			if distance <= DropperShopBuilder.ShowDistance and not shown[house] then
				DropperShopBuilder.show(house, frame)
				shown[house] = true
			elseif distance > DropperShopBuilder.HideDistance and shown[house] then
				DropperShopBuilder.clear(house)
				shown[house] = nil
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
