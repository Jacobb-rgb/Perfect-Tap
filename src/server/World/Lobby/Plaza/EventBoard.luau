--[[
	The big billboard of the events (owner 2026-11-07: "velkej železnej
	billboard", it shows the events so nothing sits on the player's screen;
	2026-11-10 20:06Z: "jeden takovej velkej bilboard kterej bude zapichlej v
	tech horach ... strasne tlustou valcovou nohu a nahore bude ten velkej
	osvetlenej reflektory"): planted on the east shoulder of the forge
	mountain, one very thick round leg, a big iron board on top facing the
	town, three spotlights on arms over it shining down on its face.
	2026-11-11 06:11Z: 30 studs higher ("Ano, o 30 výš": the east islet no
	longer hides the finder's line from plots 7-8), the airship up over it
	("Ano, výš"), and the leg stays 12 thick but "trochu do výšky a pak to
	zahni do předu": it rises behind the board, then bends forward over
	its top like a neck, and the board hangs under the bend on two rods.

	From the spawn and the town it stands right of the Great Forge, above
	the mountain, clear of the golden dragon's sign in front and of the
	planets (LobbySky specs); the airship flies over it (Sky/Airship). It is
	far (about 380 studs from the
	spawn), so the model streams Persistent and its screen draws out to
	EventBoardView.MaxDistance.

	Pure builder. The screen is one part, tag EventBoardScreen; the clients
	draw on it (Controllers/EventBoardController, UI/EventBoardView).
	Front = -Z of LobbyLayout's frame, like every board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Geo = require(Shared.Builders.Geo)
local Style = require(script.Parent.Parent.Style)

local EventBoard = {}

EventBoard.Width = 130 -- the iron board
EventBoard.Height = 64
EventBoard.Bottom = 162 -- its lower edge, over the mountain's shoulder and the sky islets in front (owner 11-11: +30)
EventBoard.Screen = Vector2.new(120, 54)
EventBoard.Leg = 12 -- the round leg's diameter (owner 11-11: keep 12)
-- the neck: the leg rises behind the board, then bends forward a quarter circle of this
-- radius and ends over the board's middle, Over studs above its top; the board hangs under it
EventBoard.Bend = 22
EventBoard.Over = 14
EventBoard.Mid = 1.2 -- the board's plate, its middle plane (z)
EventBoard.LegZ = EventBoard.Mid + EventBoard.Bend -- where the upright part stands behind the board
EventBoard.Hangers = 42 -- the two hanger rods, this far left and right of the middle
EventBoard.Lamps = 3
EventBoard.MaxParts = 60

local IRON = Color3.fromRGB(58, 62, 70)
local IRON_DARK = Color3.fromRGB(36, 39, 45)
local RIVET = Color3.fromRGB(104, 110, 120)
local RUST = Color3.fromRGB(120, 72, 44)
local LAMP = Color3.fromRGB(255, 236, 196)
local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate
local SMOOTH = Enum.Material.SmoothPlastic

function EventBoard.build(parent: Instance): Model
	local frame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
	local model = Instance.new("Model")
	model.Name = "EventBoard"
	model:AddTag("NoStuds") -- iron plate, no studs
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
	-- an upright cylinder (Geo stands it up) centred at (x, y, z)
	local function column(x: number, y: number, z: number, height: number, diameter: number, color: Color3): BasePart
		return Geo.cylinder(model, at(x, y, z), height, diameter, color, METAL)
	end

	-- a round rod from a to b (a Cylinder part's length runs along its X)
	local function rod(a: Vector3, b: Vector3, diameter: number, color: Color3, name: string): BasePart
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
		local part =
			Geo.block(model, cf, Vector3.new((b - a).Magnitude, diameter, diameter), color, METAL, { Shape = Enum.PartType.Cylinder })
		part.Name = name
		return part
	end

	-- the leg (owner 11-11): upright from deep in the mountain behind the board, its collars and
	-- foot, then the neck bending forward a quarter circle over the board's top
	local legZ, bend, leg = EventBoard.LegZ, EventBoard.Bend, EventBoard.Leg
	local neckY = top + EventBoard.Over -- the neck's end, over the board's middle
	local upright = neckY - bend
	column(0, upright / 2, legZ, upright, leg, IRON_DARK).Name = "Leg"
	for y = 20, upright - 20, 40 do
		column(0, y, legZ, 2.2, leg + 2, IRON)
	end
	column(0, 2, legZ, 4, leg + 10, Color3.fromRGB(96, 98, 104)).Name = "Foot"
	local steps = 6
	local last = at(0, upright, legZ)
	for k = 1, steps do
		local angle = k / steps * math.pi / 2
		local point = at(0, upright + bend * math.sin(angle), EventBoard.Mid + bend * math.cos(angle))
		rod(last, point, leg, IRON_DARK, "Neck")
		if k < steps then
			Geo.ball(model, point, leg, IRON_DARK, METAL).Name = "NeckJoint"
		end
		last = point
	end
	-- its end cap, the cross bar under it and the two rods the board hangs on
	rod(at(0, neckY, EventBoard.Mid + 0.8), at(0, neckY, EventBoard.Mid - 0.8), leg + 2, IRON, "NeckCap")
	local barY = neckY - leg / 2 - 1.5
	rod(at(-EventBoard.Hangers - 4, barY, EventBoard.Mid), at(EventBoard.Hangers + 4, barY, EventBoard.Mid), 3, IRON, "HangerBar")
	for _, side in { -1, 1 } do
		rod(
			at(side * EventBoard.Hangers, barY, EventBoard.Mid),
			at(side * EventBoard.Hangers, top - 1, EventBoard.Mid),
			1.8,
			IRON,
			"Hanger"
		)
	end
	-- the cross beam behind the board and a stay back to the leg
	box(0, mid, 3.8, Vector3.new(w - 8, 4, 3), IRON_DARK)
	rod(at(0, mid, 5.3), at(0, mid, legZ - leg / 2 + 0.5), 2.4, IRON, "Stay")
	-- the board, its heavy frame, the corner plates
	box(0, mid, 1.2, Vector3.new(w, h, 2), IRON_DARK, PLATE)
	box(0, top - 1.5, -0.6, Vector3.new(w + 3, 4, 2), IRON)
	box(0, bottom + 1.5, -0.6, Vector3.new(w + 3, 4, 2), IRON)
	box(-w / 2 + 1, mid, -0.6, Vector3.new(4, h - 6, 2), IRON)
	box(w / 2 - 1, mid, -0.6, Vector3.new(4, h - 6, 2), IRON)
	for _, x in { -w / 2 + 2.5, w / 2 - 2.5 } do
		for _, y in { bottom + 2.5, top - 2.5 } do
			box(x, y, -1.7, Vector3.new(7, 7, 0.4), RUST, SMOOTH)
		end
	end
	for k = 1, 6 do
		local x = -w / 2 + 10 + (k - 1) * (w - 20) / 5
		for _, y in { top - 1.5, bottom + 1.5 } do
			Geo.ball(model, at(x, y, -1.7), 1.6, RIVET, METAL)
		end
	end
	-- the screen
	local screen = box(0, mid, -1.7, Vector3.new(EventBoard.Screen.X, EventBoard.Screen.Y, 0.2), Color3.fromRGB(14, 16, 24), SMOOTH)
	screen.Name = "Screen"
	screen:AddTag("EventBoardScreen")
	-- three spotlights on arms over the top edge, shining down on the board's face
	for k = 1, EventBoard.Lamps do
		local x = -w / 2 + k * w / (EventBoard.Lamps + 1)
		box(x, top + 1.2, -4, Vector3.new(1.4, 1.4, 9), IRON_DARK)
		local lampAt = at(x, top + 1.6, -9)
		local aim = at(x, mid - 6, -1.7)
		local head = Geo.block(model, CFrame.lookAt(lampAt, aim), Vector3.new(4, 3, 3), IRON, METAL)
		head.Name = "Lamp"
		local face =
			Geo.block(model, CFrame.lookAt(lampAt, aim) * CFrame.new(0, 0, -1.55), Vector3.new(3.2, 2.2, 0.2), LAMP, Enum.Material.Neon)
		face.Name = "LampFace"
		face.CastShadow = false
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 70
		light.Range = 60
		light.Brightness = 3
		light.Color = LAMP
		light.Shadows = false
		light.Parent = head
	end
	-- far from the town: always streamed in (Planets, Clouds do the same)
	Style.streaming(model, "Persistent")
	return model
end

return EventBoard
