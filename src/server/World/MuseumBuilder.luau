--[[
	The artifact museum's builder moved to ReplicatedStorage.Shared.Builders
	(src/shared/Builders/MuseumBuilder.luau): the clients build the relics in
	the cases themselves, only near the camera. This keeps the old require
	path working for the server and the tools.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(ReplicatedStorage:WaitForChild("Shared").Builders.MuseumBuilder)
