--[[
	The artifact museum on every base yard (step 7), at BaseLayout.Museum
	(plot-local x -23..-1, z 47..55: behind the Ore Pen, beside the end of
	the yard's middle lane, its back to the train stop). It is open toward
	the yard: from the grid gate and the lane the lit cases show over the
	pen's low fence, and the walkway between the pen and the cases starts
	right at the end of the lane. Pure builder:
	only Instance creation, so the Lune tests and the preview tools build it
	too. ArtifactService builds one per plot into Plot_<id>.Yard at server
	start (PlotBuilder itself is not changed) and fills it with the owner's
	finds.

	  floor     a low stone platform (one step up) with a darker border
	  back wall a brick wall with a stone cap on the train stop side and a
	            pale plaster panel behind the cases (it keeps the gallery
	            bright under the roof); the lean-to slate roof rests on it
	            and on three stone columns, with a gold fascia and a warm
	            neon strip (gallery lights, no Light objects: plots keep
	            their one light) under its open front edge (the pen side)
	  sign      "MUSEUM" on top of the roof, readable from both sides (the
	            yard gate and the lane over the pen, and the train stop)
	  cases     one glass case per ArtifactConfig collection, left to right
	            (as the visitors see them) in collection order: a gunmetal pedestal like the podiums,
	            a neon strip in the collection's color, a plaque with the
	            collection's name and "3 / 6", a raised back shelf (the one
	            plinth part shared by the back row), the glass, a cap and a
	            soft neon panel under the cap that lights the case (no Light
	            object). The relics are built without their light
	            (ArtifactBuilder noLight, also the Mythic's).
	            The spots: the collection's artifacts in ArtifactConfig
	            order, the first half in the front row, the rest on the shelf.
	Visitors stand on the platform in front of the cases (the open -Z side
	toward the pen: a walkway reached from the end of the yard's lane) and
	look toward the train stop; every relic and plaque faces them and the
	yard. The "Prompt" attachment on the floor carries the "Collection
	Book" prompt (ArtifactService).

	show(museum, plotCF, artifacts) puts exactly the found artifacts
	(ArtifactConfig.countOf > 0) on their spots and updates the plaques;
	empty spots show nothing (budget: ArtifactConfig header). Structure
	<= MaxStructureParts parts, plus at most ArtifactConfig.MaxParts per relic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local ArtifactBuilder = require(Shared.Builders.ArtifactBuilder)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local BaseLayout = require(Shared.Config.BaseLayout)

local MuseumBuilder = {}

MuseumBuilder.Name = "Museum"
MuseumBuilder.ArtifactScale = 0.74
MuseumBuilder.MaxStructureParts = 48
MuseumBuilder.PromptName = "Prompt"
MuseumBuilder.FloorTop = 0.3

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass

local STONE = rgb(180, 170, 158) -- the walls' cap stone (PlotBuilder WALL_CAP)
local STONE_DARK = rgb(132, 124, 116)
local BRICK = rgb(132, 64, 54) -- PlotBuilder BRICK
local PILLAR = rgb(160, 150, 140)
local PILLAR_CAP = rgb(112, 106, 100)
local SLATE = rgb(70, 76, 98)
local GOLD = rgb(226, 176, 72)
local WARM = rgb(190, 110, 46) -- deep amber: no white bloom under the roof
local SHELL = rgb(44, 48, 64) -- the podiums' gunmetal
local SHELF = rgb(70, 76, 98)
local SIGN_BOARD = rgb(58, 60, 72)
local PLASTER = rgb(226, 212, 186) -- the pale panel behind the cases
local CASE_LIGHT = rgb(255, 214, 160) -- the soft panel under each case's cap
local SIGN_TEXT = rgb(255, 206, 72)

local SOLID = { CanTouch = false }
local GHOST = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }

local RECT = BaseLayout.Museum
local X0 = RECT.Center.X - RECT.Size.X / 2
local X1 = RECT.Center.X + RECT.Size.X / 2
local OPEN_Z = RECT.Center.Z - RECT.Size.Z / 2 -- the visitors' side: the pen and the yard
local WALL_Z = RECT.Center.Z + RECT.Size.Z / 2 -- the back wall: the train stop side
local FLOOR = MuseumBuilder.FloorTop

local SIDE_PAD = 0.9 -- floor edge to the first / last case
local CASE_GAP = 0.7
local CASE_DEPTH = 2.3
local CASE_Z = WALL_Z - 1.4 - CASE_DEPTH / 2
local PEDESTAL = 1.6 -- pedestal height above the floor
local GLASS_H = 2.4
local SHELF_H = 0.45
local ROOF_Y = 5.6
local ROOF_FRONT = CASE_Z - CASE_DEPTH / 2 - 1.2 -- the roof's open edge (pen side)

export type CaseInfo = { Center: Vector3, Width: number, Collection: string }

-- Plot-local centre of each case (pedestal top centre) and its width, in
-- collection order from the visitors' left to right (they face +Z, so their
-- left is +X).
function MuseumBuilder.cases(): { CaseInfo }
	local list = ArtifactConfig.Collections
	local n = math.max(1, #list)
	local usable = (X1 - X0) - 2 * SIDE_PAD
	local width = (usable - (n - 1) * CASE_GAP) / n
	local out: { CaseInfo } = {}
	for i, collection in list do
		local x = X1 - SIDE_PAD - (i - 1) * (width + CASE_GAP) - width / 2
		table.insert(out, { Center = Vector3.new(x, FLOOR + PEDESTAL, CASE_Z), Width = width, Collection = collection.Id })
	end
	return out
end

-- Plot-local spot of the `slot`-th artifact (1-based) of a case with `count`
-- spots: the first half in the front row, the rest on the raised shelf, each
-- row in order from the visitors' left (+X) to right.
function MuseumBuilder.spotLocal(case: CaseInfo, slot: number, count: number): Vector3
	local perRow = math.max(1, math.ceil(count / 2))
	local front = slot <= perRow
	local index = if front then slot else slot - perRow
	local rowCount = if front then perRow else count - perRow
	local step = case.Width / (perRow + 0.2)
	local x = case.Center.X - (index - (rowCount + 1) / 2) * step
	local z = case.Center.Z + (if front then -0.22 else 0.22) * CASE_DEPTH
	local y = case.Center.Y + (if front then 0 else SHELF_H)
	return Vector3.new(x, y, z)
end

-- World CFrame of an artifact's spot: the relic's front (ArtifactBuilder: -Z)
-- faces the visitors and the yard (-Z of the plot).
function MuseumBuilder.spot(plotCF: CFrame, artifactId: string): CFrame?
	local art = ArtifactConfig.ById[artifactId]
	if not art then
		return nil
	end
	local list = ArtifactConfig.ByCollection[art.Collection]
	local slot = list and table.find(list, art)
	if not list or not slot then
		return nil
	end
	for _, case in MuseumBuilder.cases() do
		if case.Collection == art.Collection then
			return plotCF * CFrame.new(MuseumBuilder.spotLocal(case, slot, #list))
		end
	end
	return nil
end

-- A board with big text on its front (and its back when `twoSided`).
local function textPart(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	text: string,
	textColor: Color3,
	twoSided: boolean
): Part
	local part = Geo.block(parent, cf, size, color, nil, GHOST)
	local faces: { Enum.NormalId } = if twoSided then { Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Front }
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Face" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.05, 0.1)
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = textColor
		label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = rgb(20, 14, 12)
		stroke.Parent = label
	end
	return part
end

-- The plaque text of a case: the collection's name and how many are found.
function MuseumBuilder.plaqueText(collectionId: string, artifacts: any): string
	local collection = ArtifactConfig.CollectionById[collectionId]
	local list: { ArtifactConfig.Artifact } = ArtifactConfig.ByCollection[collectionId] or {}
	local found = 0
	for _, art in list do
		if ArtifactConfig.countOf(artifacts, art.Id) > 0 then
			found += 1
		end
	end
	local name = if collection then string.upper(collection.Name) else collectionId
	return `{name}\n{found} / {#list}`
end

local function buildCase(parent: Instance, plotCF: CFrame, case: CaseInfo, index: number)
	local collection = ArtifactConfig.CollectionById[case.Collection]
	local m = Instance.new("Model")
	m.Name = "Case" .. index
	m:SetAttribute("Collection", case.Collection)
	m.Parent = parent
	local c = case.Center
	local w = case.Width
	local function at(x: number, y: number, z: number): CFrame
		return plotCF * CFrame.new(x, y, z)
	end
	local pedestal = Geo.block(m, at(c.X, FLOOR + PEDESTAL / 2, c.Z), Vector3.new(w, PEDESTAL, CASE_DEPTH), SHELL, nil, SOLID)
	pedestal.Name = "Pedestal"
	m.PrimaryPart = pedestal
	local frontZ = c.Z - CASE_DEPTH / 2
	-- the collection's color at 60 %: a saturated glow, no white bloom
	local glow = collection.Color:Lerp(Color3.new(0, 0, 0), 0.4)
	local strip = Geo.block(m, at(c.X, FLOOR + PEDESTAL - 0.16, frontZ - 0.03), Vector3.new(w, 0.1, 0.05), glow, NEON, GHOST)
	strip.Name = "Strip"
	-- the plaque faces the visitors (its Front is -Z, toward the pen)
	local plaque = textPart(
		m,
		at(c.X, FLOOR + PEDESTAL * 0.5, frontZ - 0.04),
		Vector3.new(w * 0.78, 0.7, 0.06),
		SIGN_BOARD,
		MuseumBuilder.plaqueText(case.Collection, nil),
		SIGN_TEXT,
		false
	)
	plaque.Name = "Plaque"
	local shelf = Geo.block(
		m,
		at(c.X, c.Y + SHELF_H / 2, c.Z + CASE_DEPTH * 0.25),
		Vector3.new(w - 0.3, SHELF_H, CASE_DEPTH * 0.45),
		SHELF,
		nil,
		GHOST
	)
	shelf.Name = "Shelf"
	local glass =
		Geo.block(m, at(c.X, c.Y + GLASS_H / 2, c.Z), Vector3.new(w - 0.1, GLASS_H, CASE_DEPTH - 0.1), rgb(200, 230, 255), GLASS, {
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
			Transparency = 0.8,
		})
	glass.Name = "Glass"
	local cap = Geo.block(m, at(c.X, c.Y + GLASS_H + 0.1, c.Z), Vector3.new(w + 0.1, 0.2, CASE_DEPTH + 0.1), SHELL, nil, GHOST)
	cap.Name = "Cap"
	-- the case's light: a soft warm panel just under the cap (half see-through: no white bloom)
	local light = Geo.block(m, at(c.X, c.Y + GLASS_H - 0.06, c.Z), Vector3.new(w - 0.5, 0.05, CASE_DEPTH - 0.6), CASE_LIGHT, NEON, GHOST)
	light.Transparency = 0.35
	light.Name = "CaseLight"
end

-- Builds the museum for a plot (plot frame from WorldLayout.plotCFrame). Not parented.
function MuseumBuilder.build(plotCF: CFrame): Model
	local m = Instance.new("Model")
	m.Name = MuseumBuilder.Name
	local function at(x: number, y: number, z: number): CFrame
		return plotCF * CFrame.new(x, y, z)
	end
	local cx = RECT.Center.X
	local width = X1 - X0
	-- floor: a darker border slab under a stone platform, one low step up
	local floor = Geo.block(
		m,
		at(cx, FLOOR / 2, (OPEN_Z + WALL_Z) / 2 - 0.05),
		Vector3.new(width - 0.6, FLOOR, WALL_Z - OPEN_Z - 0.5),
		STONE,
		Enum.Material.Slate,
		SOLID
	)
	floor.Name = "Floor"
	m.PrimaryPart = floor
	Geo.block(
		m,
		at(cx, FLOOR / 2 - 0.05, (OPEN_Z + WALL_Z) / 2),
		Vector3.new(width - 0.2, FLOOR - 0.1, WALL_Z - OPEN_Z - 0.2),
		STONE_DARK,
		nil,
		GHOST
	).Name =
		"Border"
	-- the back wall on the train stop side, up to the roof
	local wallZ = WALL_Z - 0.65
	local wallH = ROOF_Y - 0.2 - FLOOR
	Geo.block(m, at(cx, FLOOR + wallH / 2, wallZ), Vector3.new(width - 0.6, wallH, 0.7), BRICK, Enum.Material.Brick, SOLID).Name = "Wall"
	Geo.block(m, at(cx, FLOOR + 0.5, wallZ), Vector3.new(width - 0.5, 1.0, 1.0), PILLAR, nil, GHOST).Name = "Plinth"
	-- the pale plaster panel on the wall's gallery side, above the plinth
	local plasterBottom = FLOOR + 1.0
	local plasterTop = ROOF_Y - 0.85
	Geo.block(
		m,
		at(cx, (plasterBottom + plasterTop) / 2, wallZ - 0.37),
		Vector3.new(width - 1.4, plasterTop - plasterBottom, 0.06),
		PLASTER,
		Enum.Material.Plaster,
		GHOST
	).Name =
		"Backdrop"
	Geo.block(m, at(cx, ROOF_Y - 0.55, wallZ), Vector3.new(width - 0.5, 0.5, 0.95), PILLAR_CAP, nil, GHOST).Name = "WallCap"
	-- three stone columns carry the roof's front edge
	local columnZ = ROOF_FRONT + 0.6
	for _, x in { X0 + 0.75, cx, X1 - 0.75 } do
		Geo.block(m, at(x, FLOOR + (ROOF_Y - FLOOR) / 2, columnZ), Vector3.new(0.6, ROOF_Y - FLOOR, 0.6), PILLAR, nil, SOLID).Name =
			"Column"
		Geo.block(m, at(x, ROOF_Y - 0.35, columnZ), Vector3.new(0.9, 0.3, 0.9), PILLAR_CAP, nil, GHOST).Name = "ColumnCap"
	end
	-- the slate roof (resting on the back wall, rising to the open front), its gold fascia and the gallery lights
	local roofDepth = (WALL_Z + 0.2) - ROOF_FRONT
	local roofZ = (ROOF_FRONT + WALL_Z + 0.2) / 2
	local roof = Geo.block(
		m,
		at(cx, ROOF_Y + 0.2, roofZ) * CFrame.Angles(math.rad(6), 0, 0),
		Vector3.new(width + 0.4, 0.35, roofDepth + 0.4),
		SLATE,
		Enum.Material.Slate,
		{ CanTouch = false, CanQuery = false }
	)
	roof.Name = "Roof"
	Geo.block(m, at(cx, ROOF_Y - 0.05, ROOF_FRONT - 0.15), Vector3.new(width + 0.4, 0.45, 0.2), GOLD, Enum.Material.Metal, GHOST).Name =
		"Fascia"
	Geo.block(m, at(cx, ROOF_Y - 0.31, ROOF_FRONT), Vector3.new(width - 0.4, 0.06, 0.08), WARM, NEON, GHOST).Name = "Lights"
	-- the sign on the roof, readable from both sides (Front faces the yard: -Z)
	local sign = textPart(
		m,
		at(cx, ROOF_Y + 1.35, roofZ - 0.6),
		Vector3.new(7.4, 1.6, 0.25),
		SIGN_BOARD,
		"MUSEUM",
		SIGN_TEXT,
		true
	)
	sign.Name = "Sign"
	-- the cases
	for i, case in MuseumBuilder.cases() do
		buildCase(m, plotCF, case, i)
	end
	-- the "Collection Book" prompt spot, in front of the middle of the cases
	local point = Instance.new("Attachment")
	point.Name = MuseumBuilder.PromptName
	point.CFrame = floor.CFrame:ToObjectSpace(at(cx, FLOOR + 3, ROOF_FRONT - 1.2))
	point.Parent = floor
	local pieces = Instance.new("Folder")
	pieces.Name = "Pieces"
	pieces.Parent = m
	return m
end

-- The relics on show: artifactId -> model.
local function shownPieces(museum: Model): { [string]: Model }
	local out: { [string]: Model } = {}
	local pieces = museum:FindFirstChild("Pieces")
	if pieces then
		for _, child in pieces:GetChildren() do
			local id = child:GetAttribute("ArtifactId")
			if child:IsA("Model") and type(id) == "string" then
				out[id] = child
			end
		end
	end
	return out
end

-- Shows exactly the artifacts found in a data.Artifacts record (nil = none:
-- the plot has no owner) and updates the plaques. Returns how many are shown.
function MuseumBuilder.show(museum: Model, plotCF: CFrame, artifacts: any): number
	local pieces = museum:FindFirstChild("Pieces")
	if not pieces then
		local folder = Instance.new("Folder")
		folder.Name = "Pieces"
		folder.Parent = museum
		pieces = folder
	end
	local shown = shownPieces(museum)
	local count = 0
	for _, art in ArtifactConfig.List do
		local found = ArtifactConfig.countOf(artifacts, art.Id) > 0
		local piece = shown[art.Id]
		if found then
			count += 1
			if not piece then
				local spot = MuseumBuilder.spot(plotCF, art.Id)
				-- no light on any relic here (a plot keeps its one light)
				local model = spot and ArtifactBuilder.build(art.Id, spot, MuseumBuilder.ArtifactScale, true)
				if model then
					model.Parent = pieces
				end
			end
		elseif piece then
			piece:Destroy()
		end
	end
	for _, child in museum:GetChildren() do
		local collectionId = child:GetAttribute("Collection")
		local plaque = child:FindFirstChild("Plaque")
		if child:IsA("Model") and type(collectionId) == "string" and plaque then
			local gui = plaque:FindFirstChild("FaceFront")
			local label = gui and gui:FindFirstChild("Text")
			if label and label:IsA("TextLabel") then
				label.Text = MuseumBuilder.plaqueText(collectionId, artifacts)
			end
		end
	end
	return count
end

return MuseumBuilder
