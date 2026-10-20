--[[
	The blaster gallery of THE GREAT FORGE (V2_PLAN section 5: "blaster
	gallery: levels 1-10 + Coming soon"): every blaster level on show in the
	forge's glowing hall, so players see what they can forge.

	Each blaster is the real game model (BlasterBuilder, the gun you hold) in
	its level's ore look (BlasterData.vaultOre: the Blaster Vault's case
	ores), anchored and sized for display, on a wall plaque:
	  a dark board with a glowing rim in the ore's glow, two brass pegs, the
	  gun, and two small plates on the board's foot: "LV n" and the
	  blaster's name                                          6 parts + the gun
	Level 11 is a dark silhouette with a violet rim, a big glowing "?" and
	LV 11 / COMING SOON.

	The hall (GreatForge's local frame: front = -Z toward the plaza, local
	+X = the viewer's left seen from the plaza, hall floor y 10, side walls
	x +-7, the door opening is the hall's full width): a rack of two rows
	on each side wall, turned 12 degrees toward the door so the guns show
	from the porch and the stairs. The viewer's right wall (local -X):
	LV 1-3 below, LV 4-5 above (the forge's tool rack takes the third upper
	slot); the left wall: LV 6-8 below, LV 9, LV 10 and LV 11 above.

	Light for phones: no shadows from any gallery part, nothing collides or
	is raycast, one soft violet PointLight on LV 11 only. Pure: Instance
	creation only (the Lune preview builds it too).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BlasterData = require(Shared.Config.BlasterData)
local CaseBuilder = require(Shared.Builders.CaseBuilder)
local Stage = require(Shared.Builders.CrateOpeningStage)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local Style = require(script.Parent.Parent.Style)

local BlasterGallery = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

BlasterGallery.Board = rgb(96, 86, 100) -- the plaques' boards (mid-tone: the dark guns stand out on them)
BlasterGallery.Plate = rgb(22, 18, 24) -- the text plates
BlasterGallery.Brass = rgb(214, 160, 72)
BlasterGallery.Mystery = rgb(170, 90, 255) -- the LV 11 rim and "?"
BlasterGallery.Silhouette = rgb(20, 18, 26)
BlasterGallery.PlaqueSize = Vector2.new(3.6, 2.8) -- board width x height (studs)
BlasterGallery.Turn = math.rad(12) -- the racks turn this much toward the door
BlasterGallery.WallX = 6.35 -- plaque centers off the hall's middle (side walls at x +-7)
BlasterGallery.Floor = 10 -- the hall floor (GreatForge.PlinthTop)
BlasterGallery.Rows = { 1.9, 5.4 } -- plaque centers above the floor (the beams start 6.9 up)
BlasterGallery.Slots = { -6.3, -2.2, 1.9 } -- plaque centers along the hall (local z), front to back
-- the forge's tool rack hangs in the right wall's third upper slot (GreatForge.luau)
BlasterGallery.ToolRackSlot = { Side = -1, Row = 2, Slot = 3 }

local TINY = Style.tiny()

-- The ore look of a level on show (the Blaster Vault's case ores; level 1 = rusty).
function BlasterGallery.oreOf(level: number): string
	return BlasterData.vaultOre(level)
end

-- The two plate texts of a level.
function BlasterGallery.caption(level: number, oreId: string): (string, string)
	return "LV " .. level, string.upper(BlasterData.displayName(level, oreId))
end

---------------------------------------------------------------- parts

--[[
	The real blaster model for display: centered, anchored, scaled to fit
	`length` (barrel) x `height`, placed at `cf` (its barrel along cf's -Z).
	Every part is a non-colliding detail with no shadow.
]]
-- display detail: smaller solid bits than this (studs, after fitting) are left out (glowing ones stay)
BlasterGallery.MinDetail = 0.25

function BlasterGallery.gun(parent: Instance, cf: CFrame, level: number, oreId: string, length: number, height: number): Model
	local model = BlasterGallery.fit(parent, Stage.blasterModel(level, oreId), cf, length, height)
	-- display detail (the guns hang 6-10 studs from the eye): the invisible hand and effect
	-- holders and the tiniest solid bevels go; every glowing part (rim, cracks, stars, crystals) stays
	local drop: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local size = d.Size
			if
				d.Transparency >= 0.99 or (d.Material ~= Enum.Material.Neon and math.max(size.X, size.Y, size.Z) < BlasterGallery.MinDetail)
			then
				table.insert(drop, d)
			end
		end
	end
	for _, d in drop do
		d:Destroy()
	end
	model.Name = "Blaster" .. level
	model:SetAttribute("Level", level)
	model:SetAttribute("OreId", oreId)
	return model
end

--[[
	Centers `model` on its bounding box, scales it to fit `length` (along
	its -Z) x `height` and places it at `cf`, every part a non-colliding
	detail with no shadow. Returns the model (parented to `parent`).
]]
function BlasterGallery.fit(parent: Instance, model: Model, cf: CFrame, length: number, height: number): Model
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local p = d.CFrame.Position
			local half = d.Size.Magnitude / 2
			for i, v in { p.X, p.Y, p.Z } do
				lo[i] = math.min(lo[i], v - half * 0.5)
				hi[i] = math.max(hi[i], v + half * 0.5)
			end
		end
	end
	local center = Vector3.new((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
	local k = math.min(length / math.max(hi[3] - lo[3], 0.1), height / math.max(hi[2] - lo[2], 0.1))
	for _, d in parts do
		local rel = d.CFrame
		d.Size *= k
		d.CFrame = cf * CFrame.new((rel.Position - center) * k) * rel.Rotation
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Anchored = true
	end
	model.Parent = parent
	return model
end

-- A small text plate (one lit label filling its front face).
local function plate(parent: Instance, cf: CFrame, size: Vector3, text: string, color: Color3, font: Enum.Font, name: string): Part
	local p = Style.block(parent, cf, size, BlasterGallery.Plate, nil, TINY)
	p.Name = name
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.92, 0.8)
	t.Position = UDim2.fromScale(0.04, 0.1)
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeColor3 = rgb(12, 8, 14)
	t.TextStrokeTransparency = 0.3
	t.FontFace = Font.fromEnum(font)
	t.Parent = gui
	return p
end

-- The board, its glowing rim and the two plates of a plaque.
local function board(m: Model, cf: CFrame, rim: Color3, top: string, bottom: string, topColor: Color3)
	local size = BlasterGallery.PlaqueSize
	local w, h = size.X, size.Y
	local b = Style.block(m, cf, Vector3.new(w, h, 0.3), BlasterGallery.Board, nil, TINY)
	b.Name = "Board"
	Style.block(m, cf * CFrame.new(0, 0, 0.17), Vector3.new(w + 0.3, h + 0.3, 0.06), rim, NEON, TINY).Name = "Rim"
	local y = -h / 2 + 0.42
	-- (seen from the front, local +X is the viewer's left: the badge on the left)
	plate(m, cf * CFrame.new(w / 2 - 0.62, y, -0.17), Vector3.new(1.0, 0.56, 0.04), top, topColor, Style.SignFont, "LevelPlate")
	plate(m, cf * CFrame.new(-0.6, y, -0.17), Vector3.new(w - 1.5, 0.56, 0.04), bottom, rgb(255, 255, 255), Style.LabelFont, "NamePlate")
end

---------------------------------------------------------------- pieces

--[[
	A wall plaque (see the header). cf = the board's center, LookVector =
	out of the wall toward the viewer. barrelLeft = the barrel points to the
	viewer's left, else to the right.
]]
function BlasterGallery.plaque(parent: Instance, cf: CFrame, level: number, oreId: string?, barrelLeft: boolean?): Model
	local ore = oreId or BlasterGallery.oreOf(level)
	local _, _, glow = CaseBuilder.look(ore)
	local m = Style.model("Plaque" .. level, parent)
	local top, bottom = BlasterGallery.caption(level, ore)
	board(m, cf, glow:Lerp(Color3.new(0, 0, 0), 0.2), top, bottom, glow:Lerp(Color3.new(1, 1, 1), 0.35))
	local gunY = 0.35
	for _, x in { -0.75, 0.75 } do
		Style.block(m, cf * CFrame.new(x, gunY - 0.5, -0.3), Vector3.new(0.14, 0.14, 0.32), BlasterGallery.Brass, METAL, TINY).Name = "Peg"
	end
	-- the barrel (-Z) turned to local -X points to the viewer's right
	local turn = if barrelLeft then -math.pi / 2 else math.pi / 2
	local w, h = BlasterGallery.PlaqueSize.X, BlasterGallery.PlaqueSize.Y
	BlasterGallery.gun(
		m,
		cf * CFrame.new(0, gunY, -0.7) * CFrame.Angles(0, turn, 0) * CFrame.Angles(0.06, 0, 0),
		level,
		ore,
		w * 0.86,
		h * 0.52
	)
	m:SetAttribute("Level", level)
	return m
end

-- Level 11: a dark silhouette with a glowing "?" and COMING SOON (see the header).
function BlasterGallery.mystery(parent: Instance, cf: CFrame, barrelLeft: boolean?): Model
	local m = Style.model("ComingSoon", parent)
	local violet = BlasterGallery.Mystery
	board(m, cf, violet, "LV 11", "COMING SOON", violet:Lerp(Color3.new(1, 1, 1), 0.35))
	local turn = if barrelLeft then -math.pi / 2 else math.pi / 2
	local w, h = BlasterGallery.PlaqueSize.X, BlasterGallery.PlaqueSize.Y
	-- the dark silhouette of the top blaster (its outline only: BlasterBuilder.silhouette)
	local outline = BlasterBuilder.silhouette(BlasterData.MaxLevel, BlasterGallery.Silhouette)
	local gun = BlasterGallery.fit(
		m,
		outline,
		cf * CFrame.new(0, 0.35, -0.7) * CFrame.Angles(0, turn, 0) * CFrame.Angles(0.06, 0, 0),
		w * 0.86,
		h * 0.52
	)
	gun.Name = "Silhouette"
	-- the big glowing "?" on a faint glass plate in front of the silhouette (it holds the one light)
	local mark = plate(
		m,
		cf * CFrame.new(0, 0.35, -1.3),
		Vector3.new(1.3, 1.3, 0.04),
		"?",
		violet:Lerp(Color3.new(1, 1, 1), 0.4),
		Style.SignFont,
		"Question"
	)
	mark.Transparency = 0.9
	mark.Color = violet
	m:SetAttribute("Level", BlasterData.MaxLevel + 1)
	return m
end

---------------------------------------------------------------- the gallery

export type Spot = { Level: number, Cf: CFrame, Side: number, Row: number, Slot: number }

--[[
	Every plaque's frame in GreatForge's local frame (see the header).
	Level 11 = the "?". The tool rack's slot is left out.
]]
function BlasterGallery.spots(): { Spot }
	local list: { Spot } = {}
	local order = {
		[-1] = { { 1, 2, 3 }, { 4, 5, 0 } }, -- the viewer's right wall (0 = the tool rack)
		[1] = { { 6, 7, 8 }, { 9, 10, 11 } },
	}
	for _, side in { -1, 1 } do
		for row, levels in order[side] do
			for slot, level in levels do
				if level > 0 then
					local p = Vector3.new(
						side * BlasterGallery.WallX,
						BlasterGallery.Floor + BlasterGallery.Rows[row],
						BlasterGallery.Slots[slot]
					)
					-- face into the hall (toward -side * X), turned toward the door (-Z)
					local cf = CFrame.lookAt(p, p - Vector3.new(side, 0, 0)) * CFrame.Angles(0, -side * BlasterGallery.Turn, 0)
					table.insert(list, { Level = level, Cf = cf, Side = side, Row = row, Slot = slot })
				end
			end
		end
	end
	return list
end

-- Where the forge's tool rack hangs now (its board's center in GreatForge's local frame).
function BlasterGallery.toolRackSpot(): Vector3
	local s = BlasterGallery.ToolRackSlot
	return Vector3.new(s.Side * (7 - 0.12), BlasterGallery.Floor + BlasterGallery.Rows[s.Row], BlasterGallery.Slots[s.Slot] + 0.4)
end

--[[
	Builds the gallery into `parent`; `frame` = GreatForge's frame
	(LobbyLayout.frame of the piece). Returns the model.
]]
function BlasterGallery.build(parent: Instance, frame: CFrame): Model
	local m = Style.model("BlasterGallery", parent)
	for _, spot in BlasterGallery.spots() do
		local cf = frame * spot.Cf
		-- the barrels point into the hall, away from the door (no muzzles aimed at the visitors):
		-- facing the right wall (local -X) the back of the hall is on your left
		local barrelLeft = spot.Side < 0
		if spot.Level > BlasterData.MaxLevel then
			local piece = BlasterGallery.mystery(m, cf, barrelLeft)
			local mark = piece:FindFirstChild("Question")
			if mark and mark:IsA("BasePart") then
				Style.light(mark, BlasterGallery.Mystery, 8, 0.9)
			end
		else
			BlasterGallery.plaque(m, cf, spot.Level, nil, barrelLeft)
		end
	end
	return m
end

return BlasterGallery
