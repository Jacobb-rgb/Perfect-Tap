--[[
	The Foundry on every base yard (step 3), in the machines' style A "Soft"
	(owner 2026-10-20, from the preview on art/plot-style-a; SoftKit with
	KitMachines' palette and roles: cream bodies, slate frames and lids,
	orange trims, glowing orange strips, soft round shapes, orange letters
	on slate). Pure builder: only Instance creation, so the Lune tests and
	the preview tools build it too.

	FoundryService builds it at server start and puts it in place of the
	PlotBuilder placeholder (Plot_<id>.Yard.Foundry); PlotBuilder itself is
	not changed. It stands in BaseLayout.Foundry (plot-local x 5..21,
	z 41..52, at most 16 studs high so the trains' ore arcs clear it), on a
	slate platform (painted seams, a glowing strip along its front, a
	striped hazard edge) whose front meets the gravel apron PlotBuilder lays:

	  back wall        a cream wall with painted soft insets and bolts under a
	                   slate lid with a glowing strip, the FOUNDRY sign on top,
	                   a warning beacon at each end (WarnLight: glowing balls on
	                   slate cups the client blinks while the owner forges,
	                   attribute Forging)
	  crucible furnace a round cream crucible (back left as you look at it) on
	                   a slate plinth with a glow ring, a slate lid, an arched
	                   glowing door (Glow, a Hot core, a grate bar), a round
	                   bowl hopper on top (the Intake box takes thrown ingots)
	                   and a fat slate chimney (ChimneyTop smokes); the slate
	                   feed pipe beside it rises out of the floor: the ingots
	                   from the FOUNDRY chute arrive through it
	  glass pipe       molten metal runs from the furnace through a glass pipe
	                   into a sloped casting channel (a dark slide, orange lips)
	  blaster mould    the channel pours into a blaster-shaped mould on a cream
	                   table
	  anvil            front right: AnvilPoint (top centre), CamPoint (the
	                   hammer close-up camera, looking at the anvil) and the
	                   Prompt attachment ("Open Foundry", "Put In")
	  blaster rack     a light shadow board on the back wall behind the anvil:
	                   the black Silhouette of the owner's next blaster level
	                   (setRack) and the RackSign plate ("NEXT: LV 3")
	Molten / Glow parts are Neon (the client pulses them). The PrimaryPart
	"Base" (the platform) holds the attachments: AnvilPoint, CamPoint,
	Prompt, HopperIn (where a thrown ingot disappears), HopperOut (where a
	refused one pops out), RackMount.

	receiver(): the FOUNDRY chute's receiver at BaseLayout.FoundryIntake: a
	slate hood over the end of the sink belt, leaning on the plot's back
	wall, with a glowing throat, an orange roof and cream cheeks, a striped
	lintel and a slate pipe with an orange collar that goes down into the
	ground. Mouth = where a taken item flies in; the PenFull billboard says
	"Ore Pen full" while an item has to wait. Nothing in it collides or
	blocks raycasts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local SoftKit = require(Shared.Builders.SoftKit)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local BaseLayout = require(Shared.Config.BaseLayout)
local BlasterData = require(Shared.Config.BlasterData)

local FoundryBuilder = {}

type Paint = SoftKit.Paint

local rgb = Color3.fromRGB
local P = SoftKit.Palette
local SOLID, PROP, TINY = SoftKit.SOLID, SoftKit.PROP, SoftKit.TINY
local part, cylUp, cylX, ball, rod = SoftKit.part, SoftKit.cylUp, SoftKit.cylX, SoftKit.ball, SoftKit.rod

-- the colours outside the machines' palette
local C = {
	Steel = rgb(200, 206, 220), -- the anvil's face and horn (light, so it reads from the yard at dusk)
	Board = rgb(240, 234, 222), -- the shadow board behind the silhouette
	Inset = rgb(222, 214, 200), -- the wall's soft panel insets
	Silhouette = rgb(30, 26, 32),
	Alert = rgb(255, 92, 70),
}

FoundryBuilder.Colors = C
FoundryBuilder.MaxParts = 110 -- the building with the silhouette (a mobile budget)
-- style A must not use more parts than the Kenney-look building did (69 without the silhouette)
FoundryBuilder.BuildingParts = 69
FoundryBuilder.ReceiverMaxParts = 10

-- Plot-local frame of the building: the platform's front edge centre.
-- x grows toward the plot's right wall, z toward the sea (as BaseLayout).
local ORIGIN = Vector3.new(BaseLayout.Foundry.Center.X, 0, 41)
local FLOOR = 0.3 -- platform top
local WIDTH, DEPTH = 16, 11

-- Building-frame positions (also used by FoundryService and the tests).
local ANVIL = Vector3.new(-3.8, 0, 3.0)
local ANVIL_TOP = 2.6
local FURNACE = Vector3.new(4.6, 0, 6.6)
local FURNACE_D = 4.6 -- the crucible's diameter
local FURNACE_TOP = 5.1
local HOPPER_Y = FURNACE_TOP + 0.8 -- bottom of the hopper (on the lid)
local MOULD = Vector3.new(0.4, 0, 3.0)
local RACK = Vector3.new(-4.4, 4.45, 10.3)
local CAMERA = Vector3.new(-2.1, 6.2, -2.9)

-- Plot-local points FoundryService needs without the model (range checks).
FoundryBuilder.AnvilLocal = ORIGIN + ANVIL + Vector3.new(0, ANVIL_TOP, 0)
FoundryBuilder.PromptLocal = ORIGIN + ANVIL + Vector3.new(0, 3.1, -0.8)
FoundryBuilder.Height = 14.2 -- the chimney's top (the trains' ore arcs need <= BaseLayout.Foundry.Size.Y)

local function attach(base: BasePart, name: string, world: CFrame): Attachment
	return SoftKit.attachment(base, name, base.CFrame:ToObjectSpace(world))
end

---------------------------------------------------------------- the building

local function platform(m: Model, F: CFrame): Part
	local base = part(m, F * CFrame.new(0, FLOOR - 0.25, DEPTH / 2), Vector3.new(WIDTH, 0.5, DEPTH), "Floor", SOLID, "Base")
	local seams: { Paint } = {}
	for i = 1, 3 do
		table.insert(seams, { x = i / 4 - 0.002, y = 0, w = 0.004, h = 1, color = P.Frame })
	end
	table.insert(seams, { x = 0, y = 0.5, w = 1, h = 0.006, color = P.Frame })
	SoftKit.paint(base, Enum.NormalId.Top, seams)
	-- the glowing strip along the front face and the hazard edge on top
	part(m, F * CFrame.new(0, FLOOR - 0.25, -0.03), Vector3.new(WIDTH - 0.8, 0.12, 0.06), "Neon", TINY, "FrontGlow")
	local edge = part(m, F * CFrame.new(0, FLOOR + 0.01, 0.3), Vector3.new(WIDTH, 0.04, 0.6), "Trim", TINY, "HazardEdge")
	SoftKit.paint(edge, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 24 } })
	return base
end

local function backWall(m: Model, F: CFrame)
	local z = DEPTH - 0.3
	local wallH = 6.8
	local w = part(m, F * CFrame.new(0, FLOOR + wallH / 2, z), Vector3.new(WIDTH, wallH, 0.6), "Body", SOLID, "Wall")
	-- painted panels: a slate skirting, soft insets with bolts, the slate frame behind the rack
	local items: { Paint } = { { x = 0, y = 0.9, w = 1, h = 0.1, color = P.Frame } }
	for i = 0, 3 do
		local x = 0.025 + i * 0.245
		table.insert(items, { x = x, y = 0.08, w = 0.22, h = 0.74, color = C.Inset })
		table.insert(items, { x = x + 0.012, y = 0.11, w = 0.014, h = 0.03, color = P.Bolt, round = true })
		table.insert(items, { x = x + 0.194, y = 0.11, w = 0.014, h = 0.03, color = P.Bolt, round = true })
	end
	-- the rack's frame (the wall's front face runs from +X at x = 0 to -X at x = 1)
	local rackU = 0.5 - RACK.X / WIDTH
	table.insert(items, { x = rackU - 0.215, y = 1 - (RACK.Y - FLOOR + 2.0) / wallH, w = 0.43, h = 4.1 / wallH, color = P.Frame })
	SoftKit.paint(w, Enum.NormalId.Front, items)
	-- the train side: the same soft insets (no rack frame)
	local back: { Paint } = { { x = 0, y = 0.9, w = 1, h = 0.1, color = P.Frame } }
	for i = 0, 3 do
		table.insert(back, { x = 0.025 + i * 0.245, y = 0.08, w = 0.22, h = 0.74, color = C.Inset })
	end
	SoftKit.paint(w, Enum.NormalId.Back, back)
	-- a slate lid with a glowing strip, the FOUNDRY sign standing on it (both faces: the yard and the train side)
	part(m, F * CFrame.new(0, FLOOR + wallH + 0.15, z), Vector3.new(WIDTH + 0.4, 0.4, 1.0), "Frame", SOLID, "WallLid")
	part(m, F * CFrame.new(0, FLOOR + wallH + 0.15, z - 0.53), Vector3.new(WIDTH - 0.2, 0.12, 0.06), "Neon", TINY, "WallGlow")
	SoftKit.sign(m, F * CFrame.new(0, FLOOR + 7.95, z), Vector3.new(7.6, 1.6, 0.3), "FOUNDRY", true)
	-- warning beacons: glowing balls on slate cups (the client blinks WarnLight)
	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.6)
		cylUp(m, F * CFrame.new(x, FLOOR + 7.35, z), 0.4, 0.8, "Frame", TINY)
		ball(m, (F * CFrame.new(x, FLOOR + 7.8, z)).Position, 0.75, "Neon", TINY, "WarnLight")
	end
end

-- An arched door on the frame `face` (bottom centre at y0, facing -Z): orange frame, glow, hot core, a grate bar.
local function door(m: Model, face: CFrame, y0: number, w: number, straight: number)
	local function arch(width: number, z: number, depth: number, role: string, flags: SoftKit.Props, name: string?)
		part(m, face * CFrame.new(0, y0 + straight / 2, z), Vector3.new(width, straight, depth), role, flags, name)
		SoftKit.cylZ(m, face * CFrame.new(0, y0 + straight, z), depth, width, role, flags, name)
	end
	-- the frame stands 0.35 proud of the face (it sinks into the round body at its sides)
	arch(w + 0.7, 0.1, 0.9, "Trim", SOLID)
	arch(w, -0.38, 0.06, "Glow", TINY, "Glow")
	part(m, face * CFrame.new(0, y0 + 0.75, -0.42), Vector3.new(w * 0.5, 1.3, 0.04), "Hot", TINY, "GlowCore")
	part(m, face * CFrame.new(0, y0 + 0.5, -0.46), Vector3.new(w * 0.95, 0.16, 0.1), "Dark", TINY)
end

local function furnace(m: Model, F: CFrame)
	local at = F * CFrame.new(FURNACE.X, 0, FURNACE.Z)
	-- slate plinth with a glow ring, the cream crucible, a slate lid
	local plinthH = 0.6
	cylUp(m, at * CFrame.new(0, FLOOR + plinthH / 2, 0), plinthH, FURNACE_D + 0.6, "Frame", SOLID)
	cylUp(m, at * CFrame.new(0, FLOOR + plinthH / 2, 0), 0.14, FURNACE_D + 0.66, "Neon", TINY)
	local bodyBottom = FLOOR + plinthH
	cylUp(m, at * CFrame.new(0, (bodyBottom + FURNACE_TOP) / 2, 0), FURNACE_TOP - bodyBottom, FURNACE_D, "Body", SOLID, "Crucible")
	cylUp(m, at * CFrame.new(0, FURNACE_TOP + 0.2, 0), 0.45, FURNACE_D + 0.3, "Frame", SOLID, "Lid")
	-- the arched door on the front
	door(m, at * CFrame.new(0, 0, -FURNACE_D / 2), bodyBottom + 0.05, 2.0, 1.5)
	-- the bowl hopper on the lid (KitMachines bowl): slate neck, cream bowl, glow ring, orange rim, dark mouth
	local hd = 3.4
	local y = FURNACE_TOP + 0.42
	local neck = 0.5
	cylUp(m, at * CFrame.new(0, y + neck / 2, 0), neck, hd * 0.56, "Frame", SOLID)
	y += neck
	local bowlH = hd * 0.34
	cylUp(m, at * CFrame.new(0, y + bowlH / 2, 0), bowlH, hd, "Body", SOLID, "Hopper")
	cylUp(m, at * CFrame.new(0, y + bowlH * 0.3, 0), 0.12, hd + 0.14, "Neon", TINY)
	cylUp(m, at * CFrame.new(0, y + bowlH + 0.05, 0), 0.26, hd + 0.28, "Trim", SOLID)
	cylUp(m, at * CFrame.new(0, y + bowlH + 0.19, 0), 0.04, hd * 0.8, "Dark", TINY, "HopperFloor")
	-- the fat chimney behind it (KitMachines chimney): slate stack, orange band, slate cap with a glow ring, smoke
	local stack = F * CFrame.new(FURNACE.X + 1.8, 0, FURNACE.Z + 2.4)
	local stackBottom, capY = FURNACE_TOP - 0.4, FoundryBuilder.Height - 0.55
	cylUp(m, stack * CFrame.new(0, (stackBottom + capY) / 2, 0), capY - stackBottom, 1.5, "Pipe", SOLID)
	cylUp(m, stack * CFrame.new(0, stackBottom + (capY - stackBottom) * 0.55, 0), 0.32, 1.62, "Trim", TINY)
	cylUp(m, stack * CFrame.new(0, capY + 0.22, 0), 0.45, 2.05, "Frame", SOLID)
	cylUp(m, stack * CFrame.new(0, capY + 0.22, 0), 0.14, 2.12, "Neon", TINY)
	local mouth = cylUp(m, stack * CFrame.new(0, capY + 0.46, 0), 0.04, 1.3, "Dark", TINY, "ChimneyTop")
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(P.Smoke)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Speed = NumberRange.new(2.5, 4)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Rate = 2
	smoke.LightInfluence = 1
	smoke.Parent = mouth
	-- the feed pipe from the FOUNDRY chute: an orange sleeve, a slate pipe up, an orange joint, into the side
	local px, pz = FURNACE.X + FURNACE_D / 2 + 0.75, FURNACE.Z - 0.9
	local bendY = FURNACE_TOP - 0.9
	cylUp(m, F * CFrame.new(px, FLOOR + 0.15, pz), 0.3, 1.0, "Trim", TINY)
	cylUp(m, F * CFrame.new(px, (FLOOR + bendY) / 2, pz), bendY - FLOOR, 0.7, "Pipe", PROP, "FeedPipe")
	local bend = (F * CFrame.new(px, bendY, pz)).Position
	local inlet = (F * CFrame.new(FURNACE.X + FURNACE_D / 2 - 0.4, bendY, pz)).Position
	ball(m, bend, 0.86, "Trim", TINY, "PipeJoint")
	rod(m, bend, inlet, 0.7, "Pipe", PROP)
end

-- Glass pipe from the furnace, the casting channel and the blaster mould.
local function casting(m: Model, F: CFrame)
	local pipeY = FLOOR + 3.3
	local fromX = FURNACE.X - FURNACE_D / 2 + 0.2
	local turnX = MOULD.X + 0.2
	local z = FURNACE.Z
	local a = (F * CFrame.new(fromX, pipeY, z)).Position
	local b = (F * CFrame.new(turnX, pipeY, z)).Position
	rod(m, a, b, 0.9, "Glass", PROP, "GlassPipe")
	rod(m, a, b, 0.42, "Molten", TINY, "Molten")
	cylX(m, F * CFrame.new(fromX - 0.2, pipeY, z), 0.3, 1.2, "Trim", TINY)
	ball(m, b, 0.98, "Frame", TINY, "PipeJoint")
	-- down into the channel
	local spoutY = FLOOR + 2.25
	local c = (F * CFrame.new(turnX, spoutY, z)).Position
	rod(m, b, c, 0.8, "Glass", PROP, "GlassPipe")
	rod(m, b, c, 0.36, "Molten", TINY, "Molten")
	-- the sloped casting channel (KitMachines chute: a dark slide with orange lips) with molten metal, on a leg
	local mouldTop = FLOOR + 1.45
	local from = (F * CFrame.new(turnX, spoutY - 0.25, z + 0.2)).Position
	local to = (F * CFrame.new(MOULD.X + 0.2, mouldTop + 0.18, MOULD.Z + 0.9)).Position
	local frame = CFrame.lookAt((from + to) / 2, to)
	local length = (to - from).Magnitude
	part(m, frame * CFrame.new(0, -0.12, 0), Vector3.new(0.9, 0.12, length), "Dark", PROP, "Channel")
	for _, side in { -1, 1 } do
		part(m, frame * CFrame.new(side * 0.42, 0.04, 0), Vector3.new(0.14, 0.32, length), "Trim", TINY)
	end
	part(m, frame * CFrame.new(0, -0.04, 0), Vector3.new(0.6, 0.05, length), "Molten", TINY, "Molten")
	cylUp(m, F * CFrame.new(turnX, (FLOOR + spoutY - 0.4) / 2, z + 0.2), spoutY - 0.4 - FLOOR, 0.36, "Frame", TINY)
	-- the mould table: a cream body, a glowing strip, the slate mould with the blaster cavity
	local tableCF = F * CFrame.new(MOULD.X, 0, MOULD.Z)
	local tableTop = mouldTop - 0.2
	part(m, tableCF * CFrame.new(0, (FLOOR + tableTop) / 2, 0), Vector3.new(3.6, tableTop - FLOOR, 2.4), "Body", SOLID, "MouldTable")
	part(m, tableCF * CFrame.new(0, FLOOR + 0.35, -1.23), Vector3.new(3.2, 0.12, 0.06), "Neon", TINY)
	part(m, tableCF * CFrame.new(0, mouldTop - 0.1, 0), Vector3.new(3.4, 0.2, 2.2), "Frame", SOLID, "Mould")
	-- the cavity: a blaster lying on its side, seen from above (muzzle block,
	-- barrel, body with a sight, rear block, the grip slanting toward the yard)
	local y = mouldTop + 0.005
	local cavity = {
		{ -1.36, 0.26, 0.24, 0.5, 0 }, -- muzzle
		{ -0.85, 0.26, 0.85, 0.28, 0 }, -- barrel
		{ 0.3, 0.2, 1.5, 0.62, 0 }, -- body
		{ 0.15, 0.58, 0.5, 0.16, 0 }, -- sight
		{ 1.2, 0.2, 0.32, 0.46, 0 }, -- rear block
		{ 0.6, -0.5, 0.42, 0.82, -0.3 }, -- grip
		{ 0.1, -0.26, 0.12, 0.26, 0.3 }, -- trigger
	}
	for _, piece in cavity do
		part(
			m,
			tableCF * CFrame.new(piece[1], y, piece[2]) * CFrame.Angles(0, piece[5], 0),
			Vector3.new(piece[3], 0.03, piece[4]),
			"Molten",
			TINY,
			"Molten"
		)
	end
end

local function anvil(m: Model, F: CFrame)
	local at = F * CFrame.new(ANVIL.X, 0, ANVIL.Z)
	-- a slate stand with an orange band, the dark waist, the big light steel
	-- face and horn (they read from the yard next to the mould table)
	local face, faceH = Vector3.new(2.6, 0.6, 1.2), 0.6
	part(m, at * CFrame.new(0, FLOOR + 0.45, 0), Vector3.new(1.9, 0.9, 1.5), "Frame", SOLID, "AnvilBase")
	part(m, at * CFrame.new(0, FLOOR + 0.2, 0), Vector3.new(2.0, 0.24, 1.6), "Trim", TINY)
	local waistBottom, waistTop = FLOOR + 0.9, ANVIL_TOP - faceH
	part(m, at * CFrame.new(0, (waistBottom + waistTop) / 2, 0), Vector3.new(0.95, waistTop - waistBottom, 0.85), "Dark", SOLID)
	part(m, at * CFrame.new(0, ANVIL_TOP - faceH / 2, 0), face, C.Steel, SOLID, "Anvil")
	-- the horn: a wedge with its flat side on top, tapering to the left (-X)
	SoftKit.wedge(
		m,
		at * CFrame.new(-face.X / 2 - 0.55, ANVIL_TOP - faceH / 2, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(face.Z, faceH, 1.1),
		C.Steel,
		SOLID
	)
end

local function rack(m: Model, F: CFrame)
	local board = part(m, F * CFrame.new(RACK.X, RACK.Y, RACK.Z), Vector3.new(6.2, 3.4, 0.2), C.Board, PROP, "RackBoard")
	-- a big "?" for the level after the top one (shown by setRack)
	local gui = SoftKit.label(board, Enum.NormalId.Front, "?", C.Silhouette, 0.4)
	gui.Name = "Mystery"
	gui.Enabled = false
	local mark = gui:FindFirstChildOfClass("TextLabel")
	if mark then
		mark.Name = "Mark"
		mark.Position = UDim2.fromScale(0.3, 0.05)
		mark.Size = UDim2.fromScale(0.4, 0.9)
	end
	cylX(m, F * CFrame.new(RACK.X, RACK.Y + 1.85, RACK.Z - 0.05), 6.6, 0.36, "Trim", TINY)
	local plate = part(m, F * CFrame.new(RACK.X, RACK.Y - 1.95, RACK.Z - 0.08), Vector3.new(6.6, 0.6, 0.4), "Frame", TINY, "RackSign")
	SoftKit.label(plate, Enum.NormalId.Front, "NEXT: LV 2", SoftKit.Text)
end

local function mount(base: BasePart, F: CFrame)
	attach(base, "AnvilPoint", F * CFrame.new(ANVIL.X, ANVIL_TOP, ANVIL.Z))
	local camPos = (F * CFrame.new(CAMERA)).Position
	local look = (F * CFrame.new(ANVIL.X, ANVIL_TOP + 0.35, ANVIL.Z + 0.6)).Position
	attach(base, "CamPoint", CFrame.lookAt(camPos, look))
	attach(base, "Prompt", F * CFrame.new(ANVIL.X, 3.1, ANVIL.Z - 0.8))
	attach(base, "HopperIn", F * CFrame.new(FURNACE.X, HOPPER_Y + 1.7, FURNACE.Z))
	attach(base, "HopperOut", F * CFrame.new(FURNACE.X, HOPPER_Y + 2.6, FURNACE.Z - 2.6))
	attach(base, "RackMount", F * CFrame.new(RACK.X, RACK.Y + 0.1, RACK.Z - 0.12)) -- the board's front face
end

-- The Foundry building of a plot (plotCF = WorldLayout.plotCFrame). Its
-- silhouette shows `nextLevel` (default 2).
function FoundryBuilder.build(plotCF: CFrame, nextLevel: number?): Model
	local m = Instance.new("Model")
	m.Name = "Foundry"
	local F = plotCF * CFrame.new(ORIGIN)
	local base = platform(m, F)
	m.PrimaryPart = base
	backWall(m, F)
	furnace(m, F)
	casting(m, F)
	anvil(m, F)
	rack(m, F)
	mount(base, F)
	-- the hopper's intake box (an invisible IntakeService zone part)
	local intake = Geo.block(
		m,
		F * CFrame.new(FURNACE.X, HOPPER_Y + 2.25, FURNACE.Z),
		Vector3.new(3.8, 2.9, 3.8),
		P.Dark,
		nil,
		{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
	)
	intake.Name = "Intake"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	FoundryBuilder.setRack(m, nextLevel or 2)
	return m
end

--[[
	Shows blaster level `level` as a black silhouette on the shadow board (a
	level past BlasterData.MaxLevel: the "?" and COMING SOON). Rebuilds only
	the "Silhouette" model; the parts keep their BlasterBuilder.silhouette
	shapes, scaled to fit the board.
]]
function FoundryBuilder.setRack(building: Model, level: number)
	local old = building:FindFirstChild("Silhouette")
	if old then
		old:Destroy()
	end
	local base = building.PrimaryPart
	local mountPoint = base and base:FindFirstChild("RackMount")
	local board = building:FindFirstChild("RackBoard")
	local plate = building:FindFirstChild("RackSign")
	local label = plate and plate:FindFirstChild("Text", true)
	local mystery = board and board:FindFirstChild("Mystery")
	local comingSoon = level > BlasterData.MaxLevel
	if label and label:IsA("TextLabel") then
		label.Text = if comingSoon then "COMING SOON" else `NEXT: LV {level}`
	end
	if mystery and mystery:IsA("SurfaceGui") then
		mystery.Enabled = comingSoon
	end
	building:SetAttribute("RackLevel", level)
	if comingSoon or not base or not mountPoint or not mountPoint:IsA("Attachment") then
		return
	end
	local tool = BlasterBuilder.silhouette(math.max(2, level))
	local parts: { BasePart } = {}
	local minP = Vector3.new(math.huge, math.huge, math.huge)
	local maxP = -minP
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local half = d.Size / 2
			local cf = d.CFrame
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			local ext = Vector3.new(
				math.abs(r00) * half.X + math.abs(r01) * half.Y + math.abs(r02) * half.Z,
				math.abs(r10) * half.X + math.abs(r11) * half.Y + math.abs(r12) * half.Z,
				math.abs(r20) * half.X + math.abs(r21) * half.Y + math.abs(r22) * half.Z
			)
			local lo, hi = cf.Position - ext, cf.Position + ext
			minP = Vector3.new(math.min(minP.X, lo.X), math.min(minP.Y, lo.Y), math.min(minP.Z, lo.Z))
			maxP = Vector3.new(math.max(maxP.X, hi.X), math.max(maxP.Y, hi.Y), math.max(maxP.Z, hi.Z))
		end
	end
	local extent = maxP - minP
	local scale = math.min(1.5, 4.8 / math.max(extent.Z, 0.1), 2.5 / math.max(extent.Y, 0.1))
	local center = (minP + maxP) / 2
	-- barrel (-Z in the design frame) toward -X, the gun's side toward the yard
	-- (its side rests against the board: the gun's width is the depth here)
	local frame = base.CFrame * mountPoint.CFrame * CFrame.new(0, 0, -extent.X * scale / 2 - 0.02) * CFrame.Angles(0, math.pi / 2, 0)
	local silhouette = Instance.new("Model")
	silhouette.Name = "Silhouette"
	for _, piece in parts do
		for _, child in piece:GetChildren() do
			child:Destroy()
		end
		local rel = piece.CFrame
		piece.Size *= scale
		piece.CFrame = frame * CFrame.new((rel.Position - center) * scale) * rel.Rotation
		piece.Anchored = true
		piece.Massless = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Color = C.Silhouette
		piece.Material = Enum.Material.SmoothPlastic
		piece.Transparency = 0
		piece.Parent = silhouette
	end
	tool:Destroy()
	silhouette.Parent = building
end

---------------------------------------------------------------- the chute receiver

-- The FOUNDRY chute's receiver (plot-local BaseLayout.FoundryIntake), in style A.
function FoundryBuilder.receiver(plotCF: CFrame): Model
	local zone = BaseLayout.FoundryIntake.Zone
	local m = Instance.new("Model")
	m.Name = "FoundryReceiver"
	local cx = zone.Center.X
	local front = zone.Center.Z - zone.Size.Z / 2 + 0.08
	local wall = zone.Center.Z + 0.4 -- the hood's back plate leans on the plot wall
	local w = zone.Size.X - 0.1
	local hood = part(m, plotCF * CFrame.new(cx, 1.55, wall - 0.15), Vector3.new(w, 3.1, 0.3), "Frame", TINY, "Hood")
	m.PrimaryPart = hood
	part(m, plotCF * CFrame.new(cx, 1.5, wall - 0.32), Vector3.new(w - 1.1, 1.2, 0.05), "Glow", TINY, "Glow")
	-- the roof leans from the wall down over the belt's end
	local roofBack = (plotCF * CFrame.new(cx, 3.22, wall)).Position
	local roofFront = (plotCF * CFrame.new(cx, 2.5, front)).Position
	part(
		m,
		CFrame.lookAt((roofFront + roofBack) / 2, roofBack),
		Vector3.new(zone.Size.X, 0.18, (roofBack - roofFront).Magnitude),
		"Trim",
		TINY,
		"Roof"
	)
	for _, side in { -1, 1 } do
		part(
			m,
			plotCF * CFrame.new(cx + side * (zone.Size.X / 2 - 0.13), 1.85, (front + wall - 0.3) / 2),
			Vector3.new(0.25, 1.5, wall - 0.3 - front),
			"Body",
			TINY
		)
	end
	local lintel = part(m, plotCF * CFrame.new(cx, 2.25, front + 0.09), Vector3.new(zone.Size.X, 0.3, 0.18), "Trim", TINY, "Lintel")
	SoftKit.paint(lintel, Enum.NormalId.Front, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 8 } })
	-- the pipe the belt's end drops into, going down into the ground
	local pipe = plotCF * CFrame.new(cx, 0, wall - 0.3)
	cylUp(m, pipe * CFrame.new(0, 0.1, 0), 1.4, 1.35, "Pipe", TINY, "Pipe")
	cylUp(m, pipe * CFrame.new(0, 0.12, 0), 0.22, 1.58, "Trim", TINY)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.CFrame = hood.CFrame:ToObjectSpace(plotCF * CFrame.new(BaseLayout.FoundryIntake.Mouth))
	mouth.Parent = hood
	-- "Ore Pen full" over the hood while an item has to wait (FoundryService)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PenFull"
	billboard.Size = UDim2.fromScale(6, 1.3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, -0.6)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = hood
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundColor3 = rgb(40, 20, 18)
	label.BackgroundTransparency = 0.15
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "Ore Pen full"
	label.TextScaled = true
	label.TextColor3 = C.Alert
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = label
	return m
end

return FoundryBuilder
