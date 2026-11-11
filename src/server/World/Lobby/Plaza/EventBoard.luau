--[[
	The big billboard of the events (owner 2026-11-07: "velkej železnej
	billboard", it shows the events so nothing sits on the player's screen;
	2026-11-10 20:06Z: "jeden takovej velkej bilboard kterej bude zapichlej v
	tech horach ... strasne tlustou valcovou nohu a nahore bude ten velkej
	osvetlenej reflektory"): planted on the east shoulder of the forge
	mountain, one very thick round leg, a big iron board on top facing the
	town, three spotlights on arms over it shining down on its face.
	2026-11-11: higher ("Ano, o 30 výš": the east islet no longer hides the
	finder's line from plots 7-8), the airship up over it ("Ano, výš"), the
	leg stays 12 thick and rises straight, then at the board's lower edge it
	kinks 30 degrees forward and the whole board leans with it, its face
	down toward the town (owner's pick "A, nakloněná tabule" in the evening;
	the quarter-circle neck of the morning was not what he meant).

	From the spawn and the town it stands right of the Great Forge, above
	the mountain, clear of the golden dragon's sign in front and of the
	planets (LobbySky specs); the airship flies over it (Sky/Airship). It is
	far (about 390 studs from the spawn, seen about 27 degrees up, so the
	30 degree lean turns its face almost straight at the town), so the model
	streams Persistent and its screen draws out to EventBoardView.MaxDistance.

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
-- its lower edge before the lean, over the mountain's shoulder and the sky islets in front
-- (owner 11-11: up; the lean lowers the edge about 3.5 studs, still clear from plots 7-8)
EventBoard.Bottom = 178
EventBoard.Screen = Vector2.new(120, 54)
EventBoard.Leg = 12 -- the round leg's diameter (owner 11-11: keep 12)
EventBoard.LegZ = 2.2 + EventBoard.Leg / 2 + 1 -- behind the board: its front face stays clear of the leg
EventBoard.Kink = 4 -- the leg kinks this far above the board's lower edge, in the board's back
EventBoard.Tilt = math.rad(30) -- the lean: the leg's top part and the whole board, forward
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
	local legFrame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
	local model = Instance.new("Model")
	model.Name = "EventBoard"
	model:AddTag("NoStuds") -- iron plate, no studs
	model.Parent = parent
	local w, h, bottom = EventBoard.Width, EventBoard.Height, EventBoard.Bottom
	local top = bottom + h
	local mid = bottom + h / 2
	local legZ, leg = EventBoard.LegZ, EventBoard.Leg
	local kinkY = bottom + EventBoard.Kink
	-- the board's frame: the upright one turned forward round the kink (the top toward -Z)
	local pivot = CFrame.new(0, kinkY, legZ)
	local frame = legFrame * pivot * CFrame.Angles(-EventBoard.Tilt, 0, 0) * pivot:Inverse()

	local function at(x: number, y: number, z: number): Vector3
		return (frame * CFrame.new(x, y, z)).Position
	end
	local function box(x: number, y: number, z: number, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return Geo.block(model, frame * CFrame.new(x, y, z), size, color, material or METAL)
	end
	-- an upright cylinder (Geo stands it up) centred at (x, y, z) of the leg's frame
	local function column(x: number, y: number, z: number, height: number, diameter: number, color: Color3): BasePart
		return Geo.cylinder(model, (legFrame * CFrame.new(x, y, z)).Position, height, diameter, color, METAL)
	end
	-- a round rod from a to b (a Cylinder part's length runs along its X)
	local function rod(a: Vector3, b: Vector3, diameter: number, color: Color3, name: string): BasePart
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
		local part =
			Geo.block(model, cf, Vector3.new((b - a).Magnitude, diameter, diameter), color, METAL, { Shape = Enum.PartType.Cylinder })
		part.Name = name
		return part
	end

	-- the leg (owner 11-11): upright from deep in the mountain to the kink, its collars and
	-- foot, then the leaning top up the board's back with its cap
	column(0, kinkY / 2, legZ, kinkY, leg, IRON_DARK).Name = "Leg"
	for y = 20, kinkY - 20, 40 do
		column(0, y, legZ, 2.2, leg + 2, IRON)
	end
	column(0, 2, legZ, 4, leg + 10, Color3.fromRGB(96, 98, 104)).Name = "Foot"
	Geo.ball(model, at(0, kinkY, legZ), leg + 1, IRON_DARK, METAL).Name = "Kink"
	rod(at(0, kinkY, legZ), at(0, top + 3, legZ), leg, IRON_DARK, "Neck")
	rod(at(0, top + 2.2, legZ), at(0, top + 3.8, legZ), leg + 2, IRON, "NeckCap")
	-- the cross beams behind the board, on the leaning top
	box(0, mid, 3.8, Vector3.new(w - 8, 4, 3), IRON_DARK)
	box(0, top - 10, 3.8, Vector3.new(w - 8, 4, 3), IRON_DARK)
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
