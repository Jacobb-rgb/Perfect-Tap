--[[
	The big iron billboard by the plaza (owner 2026-11-07: "velkej železnej
	billboard", it shows the events so nothing sits on the player's screen).
	Pure builder: riveted dark iron on two I-beams, a gantry over the east road
	(players walk under it), with two work lamps over it.
	The screen is one part, tag EventBoardScreen; the clients draw on it
	(Controllers/EventBoardController, UI/EventBoardView). About 50 parts.
	Front = -Z of LobbyLayout's frame, like every board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Geo = require(Shared.Builders.Geo)

local EventBoard = {}

EventBoard.Width = 28 -- the iron panel
EventBoard.Height = 15.5
EventBoard.Bottom = 13 -- its lower edge above the road
EventBoard.Screen = Vector2.new(24.5, 12.5)
EventBoard.PostAt = 9.5 -- the two beams, left and right of the middle (clear of the road)
EventBoard.FootSize = 4.2
EventBoard.MaxParts = 60

local IRON = Color3.fromRGB(58, 62, 70)
local IRON_DARK = Color3.fromRGB(36, 39, 45)
local RIVET = Color3.fromRGB(104, 110, 120)
local RUST = Color3.fromRGB(120, 72, 44)
local LAMP = Color3.fromRGB(255, 196, 120)
local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate

function EventBoard.build(parent: Instance): Model
	local frame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
	local model = Instance.new("Model")
	model.Name = "EventBoard"
	model:AddTag("NoStuds") -- iron plate, no studs
	model.Parent = parent
	local w, h, bottom = EventBoard.Width, EventBoard.Height, EventBoard.Bottom
	local top = bottom + h
	local mid = bottom + h / 2

	local function box(x: number, y: number, z: number, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return Geo.block(model, frame * CFrame.new(x, y, z), size, color, material or METAL)
	end

	-- two I-beams on concrete feet
	local beam = top + 1
	for _, x in { -EventBoard.PostAt, EventBoard.PostAt } do
		box(x, beam / 2, 0.6, Vector3.new(0.6, beam, 1.8), IRON_DARK)
		box(x - 0.9, beam / 2, 0.6, Vector3.new(0.5, beam, 2.4), IRON)
		box(x + 0.9, beam / 2, 0.6, Vector3.new(0.5, beam, 2.4), IRON)
		box(x, 0.6, 0.6, Vector3.new(EventBoard.FootSize, 1.2, EventBoard.FootSize), Color3.fromRGB(96, 98, 104), Enum.Material.Concrete)
		box(x, 1.45, 0.6, Vector3.new(3.4, 0.5, 3.4), RUST)
	end
	-- a girder under the panel, between the beams
	box(0, bottom - 0.5, 0.6, Vector3.new(EventBoard.PostAt * 2, 1, 1), IRON_DARK)
	-- the panel, its heavy frame, the corner plates
	box(0, mid, 0.2, Vector3.new(w, h, 0.8), IRON_DARK, PLATE)
	box(0, top - 0.6, -0.5, Vector3.new(w + 1.2, 1.8, 1), IRON)
	box(0, bottom + 0.6, -0.5, Vector3.new(w + 1.2, 1.8, 1), IRON)
	box(-w / 2 + 0.4, mid, -0.5, Vector3.new(1.8, h - 2.4, 1), IRON)
	box(w / 2 - 0.4, mid, -0.5, Vector3.new(1.8, h - 2.4, 1), IRON)
	for _, x in { -w / 2 + 1, w / 2 - 1 } do
		for _, y in { bottom + 1, top - 1 } do
			box(x, y, -1.05, Vector3.new(3.2, 3.2, 0.2), RUST, Enum.Material.SmoothPlastic)
		end
	end
	-- rivets along the frame
	local function rivet(x: number, y: number)
		Geo.ball(model, (frame * CFrame.new(x, y, -1.05)).Position, 0.7, RIVET, METAL)
	end
	for k = 1, 7 do
		local x = -w / 2 + 3.2 + (k - 1) * (w - 6.4) / 6
		rivet(x, top - 0.6)
		rivet(x, bottom + 0.6)
	end
	for k = 1, 3 do
		local y = bottom + 4 + (k - 1) * (h - 8) / 2
		rivet(-w / 2 + 0.4, y)
		rivet(w / 2 - 0.4, y)
	end
	-- two work lamps over it
	for _, x in { -w / 4, w / 4 } do
		box(x, top + 1.4, -1, Vector3.new(0.4, 0.4, 3), IRON_DARK)
		box(x, top + 1.1, -2.4, Vector3.new(3.4, 0.8, 1.2), IRON)
		box(x, top + 0.62, -2.4, Vector3.new(2.8, 0.16, 0.8), LAMP, Enum.Material.Neon).CastShadow = false
	end
	-- the screen
	local screen = box(
		0,
		mid,
		-0.72,
		Vector3.new(EventBoard.Screen.X, EventBoard.Screen.Y, 0.1),
		Color3.fromRGB(14, 16, 24),
		Enum.Material.SmoothPlastic
	)
	screen.Name = "Screen"
	screen:AddTag("EventBoardScreen")
	return model
end

return EventBoard
