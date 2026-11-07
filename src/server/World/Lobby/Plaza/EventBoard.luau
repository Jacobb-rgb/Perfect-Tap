--[[
	The big iron billboard by the plaza (owner 2026-11-07: "velkej železnej
	billboard", it shows the events so nothing sits on the player's screen),
	hanging from a hot-air balloon (owner 2026-11-07 23:23Z: "ten bilboard bude
	viset z letaciho balonu"): high over the east road, where the gantry stood,
	so from the plots it hangs above the golden dragon and its sign instead of
	in front of them, and the gas giant stays clear (LobbySky specs). Tethered:
	two ropes from its lower corners to concrete anchors where the gantry's feet
	stood. Pure builder: the riveted iron panel, two cables up to a wicker
	basket with a burner, a striped envelope (a ball, an equator band, a
	stepped cone down to the mouth, a vent on top).
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
EventBoard.Bottom = 46 -- its lower edge, high over the road (the dragon's sign shows under it from the plots)
EventBoard.Screen = Vector2.new(24.5, 12.5)
EventBoard.PostAt = 9 -- the two tether anchors, left and right of the middle (clear of the road)
EventBoard.FootSize = 3.6
EventBoard.Envelope = 22 -- the balloon's diameter
EventBoard.MaxParts = 60

local IRON = Color3.fromRGB(58, 62, 70)
local IRON_DARK = Color3.fromRGB(36, 39, 45)
local RIVET = Color3.fromRGB(104, 110, 120)
local RUST = Color3.fromRGB(120, 72, 44)
local ROPE = Color3.fromRGB(70, 58, 46)
local WICKER = Color3.fromRGB(176, 128, 72)
local RED = Color3.fromRGB(226, 64, 58)
local CREAM = Color3.fromRGB(246, 232, 200)
local GOLD = Color3.fromRGB(255, 196, 60)
local FLAME = Color3.fromRGB(255, 150, 50)
local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate
local SMOOTH = Enum.Material.SmoothPlastic

function EventBoard.build(parent: Instance): Model
	local frame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
	local model = Instance.new("Model")
	model.Name = "EventBoard"
	model:AddTag("NoStuds") -- iron plate and cloth, no studs
	model.Parent = parent
	local w, h, bottom = EventBoard.Width, EventBoard.Height, EventBoard.Bottom
	local top = bottom + h
	local mid = bottom + h / 2

	local function at(x: number, y: number, z: number): Vector3
		return (frame * CFrame.new(x, y, z)).Position
	end
	local function box(x: number, y: number, z: number, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return Geo.block(model, frame * CFrame.new(x, y, z), size, color, material or METAL)
	end
	-- a horizontal disc (a cylinder standing up) centred at (x, y, z)
	local function disc(
		x: number,
		y: number,
		z: number,
		height: number,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	): BasePart
		return Geo.cylinder(model, at(x, y, z), height, diameter, color, material) -- (Geo stands it up)
	end
	-- a rope / cable from a to b (world points)
	local function rope(a: Vector3, b: Vector3, thick: number, color: Color3): BasePart
		local dir = b - a
		local x = dir.Unit
		local ref = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
		local z = x:Cross(ref).Unit
		local y = z:Cross(x)
		local part = Geo.cylinder(model, (a + b) / 2, dir.Magnitude, thick, color, SMOOTH)
		part.CFrame = CFrame.fromMatrix((a + b) / 2, x, y, z)
		part.CanCollide = false
		part.CastShadow = false
		return part
	end

	-- the panel, its heavy frame, the corner plates
	box(0, mid, 0.2, Vector3.new(w, h, 0.8), IRON_DARK, PLATE)
	box(0, top - 0.6, -0.5, Vector3.new(w + 1.2, 1.8, 1), IRON)
	box(0, bottom + 0.6, -0.5, Vector3.new(w + 1.2, 1.8, 1), IRON)
	box(-w / 2 + 0.4, mid, -0.5, Vector3.new(1.8, h - 2.4, 1), IRON)
	box(w / 2 - 0.4, mid, -0.5, Vector3.new(1.8, h - 2.4, 1), IRON)
	for _, x in { -w / 2 + 1, w / 2 - 1 } do
		for _, y in { bottom + 1, top - 1 } do
			box(x, y, -1.05, Vector3.new(3.2, 3.2, 0.2), RUST, SMOOTH)
		end
	end
	-- rivets along the top and the bottom of the frame
	for k = 1, 5 do
		local x = -w / 2 + 4 + (k - 1) * (w - 8) / 4
		for _, y in { top - 0.6, bottom + 0.6 } do
			Geo.ball(model, at(x, y, -1.05), 0.7, RIVET, METAL)
		end
	end
	-- the screen
	local screen = box(0, mid, -0.72, Vector3.new(EventBoard.Screen.X, EventBoard.Screen.Y, 0.1), Color3.fromRGB(14, 16, 24), SMOOTH)
	screen.Name = "Screen"
	screen:AddTag("EventBoardScreen")

	-- the basket over it, two cables down to the panel's top corners
	local basketBottom = top + 7
	local basketTop = basketBottom + 3.6
	box(0, basketBottom + 1.8, 0.2, Vector3.new(5, 3.6, 5), WICKER, Enum.Material.WoodPlanks)
	box(0, basketTop - 0.2, 0.2, Vector3.new(5.6, 0.6, 5.6), ROPE, Enum.Material.Wood)
	for _, x in { -w / 2 + 2, w / 2 - 2 } do
		rope(at(x, top + 0.9, 0.2), at(if x < 0 then -2 else 2, basketBottom, 0.2), 0.35, IRON_DARK)
	end
	-- the burner and its flame
	disc(0, basketTop + 1.2, 0.2, 1.4, 1.8, IRON, METAL)
	Geo.ball(model, at(0, basketTop + 2.6, 0.2), 1.6, FLAME, Enum.Material.Neon).CastShadow = false
	-- the envelope: a stepped cone up from the mouth, the ball, an equator band, the vent
	local mouth = basketTop + 3.4
	disc(0, mouth, 0.2, 1, 4.4, IRON_DARK, SMOOTH)
	local cone: { { D: number, C: Color3 } } = { { D = 7, C = RED }, { D = 11, C = CREAM }, { D = 15, C = RED }, { D = 18.5, C = CREAM } }
	for k, step in cone do
		disc(0, mouth + 0.5 + (k - 0.5) * 2.4, 0.2, 2.4, step.D, step.C, SMOOTH)
	end
	local d = EventBoard.Envelope
	local center = mouth + 0.5 + #cone * 2.4 + d / 2 - 2
	Geo.ball(model, at(0, center, 0.2), d, RED, SMOOTH)
	disc(0, center, 0.2, 2.2, d + 0.3, GOLD, SMOOTH)
	disc(0, center + d / 2 - 0.3, 0.2, 1, 6, CREAM, SMOOTH)
	-- four cords from the basket's corners to the mouth
	for _, c in { { -2.3, -2.1 }, { 2.3, -2.1 }, { -2.3, 2.5 }, { 2.3, 2.5 } } do
		rope(at(c[1], basketTop, c[2]), at(c[1] * 0.7, mouth, c[2] * 0.7 + 0.06), 0.2, ROPE)
	end

	-- tethered: two ropes from the panel's lower corners to concrete anchors beside the road
	for _, side in { -1, 1 } do
		local x = side * EventBoard.PostAt
		box(x, 0.25, 0.6, Vector3.new(EventBoard.FootSize, 0.5, EventBoard.FootSize), Color3.fromRGB(96, 98, 104), Enum.Material.Concrete)
		box(x, 0.75, 0.6, Vector3.new(1.4, 0.5, 1.4), RUST)
		rope(at(x, 1, 0.6), at(side * (w / 2 - 1.5), bottom + 0.4, 0.2), 0.3, ROPE)
	end
	return model
end

return EventBoard
