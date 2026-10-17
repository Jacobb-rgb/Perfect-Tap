--[[
	GridOverlay: the build-mode grid drawn on your plot (client only).

	26 thin lines (13 each way, one per cell edge) plus a few named plates
	(the ghost's footprint, its output cell, the cursor, the chute cells...),
	some with a floating text tag (tag(): the chutes' labels). Everything is
	created once and kept in one folder, Workspace.BuildClient, which is
	parented to nil while build mode is closed, so the overlay costs nothing
	the rest of the time. The build ghost lives in the same folder
	(GridOverlay.folder()), so it hides with the grid.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local GridOverlay = {}

local CELL = GameConfig.CellSize
local CELLS = GameConfig.PlotCells
local SIZE = CELLS * CELL

local LINE_COLOR = Color3.fromRGB(255, 236, 200)
local LINE_TRANSPARENCY = 0.55
local LINE_WIDTH = 0.08
local LINE_HEIGHT = 0.05
local LINE_Y = 0.04 -- just above the plot surface (plot-local y = 0)
local PLATE_Y = 0.08
local PLATE_THICKNESS = 0.06
local PLATE_INSET = 0.3 -- plates stop short of the cell edges so the lines stay visible
local PLATE_TRANSPARENCY = 0.5
local PLATE_COLOR = Color3.fromRGB(255, 255, 255)

local TAG_SIZE = Vector2.new(150, 34) -- plate labels, pixels
local TAG_UP = 2.6 -- studs above the plate (over a belt standing on it)

local folder: Folder? = nil
local lines: { BasePart } = {}
local lineOffsets: { CFrame } = {}
local plates: { [string]: BasePart } = {}
local tags: { [string]: TextLabel } = {}

local function newPart(name: string, size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Transparency = transparency
	return part
end

-- The folder for every build-mode visual (created on first use, not parented).
function GridOverlay.folder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "BuildClient"
	folder = created
	for i = 0, CELLS do
		local offset = -SIZE / 2 + i * CELL
		-- one line along X (at z = offset) and one along Z (at x = offset)
		local alongX = newPart("GridLine", Vector3.new(SIZE + LINE_WIDTH, LINE_HEIGHT, LINE_WIDTH), LINE_COLOR, LINE_TRANSPARENCY)
		alongX.Parent = created
		table.insert(lines, alongX)
		table.insert(lineOffsets, CFrame.new(0, LINE_Y, offset))
		local alongZ = newPart("GridLine", Vector3.new(LINE_WIDTH, LINE_HEIGHT, SIZE + LINE_WIDTH), LINE_COLOR, LINE_TRANSPARENCY)
		alongZ.Parent = created
		table.insert(lines, alongZ)
		table.insert(lineOffsets, CFrame.new(offset, LINE_Y, 0))
	end
	return created
end

-- Shows the grid on a plot (plotCFrame = WorldLayout.plotCFrame of it).
function GridOverlay.show(plotCFrame: CFrame)
	local f = GridOverlay.folder()
	for i, line in lines do
		line.CFrame = plotCFrame * lineOffsets[i]
	end
	f.Parent = Workspace
end

-- Hides the grid, every plate and anything else in the folder.
function GridOverlay.hide()
	for _, plate in plates do
		plate.Parent = nil
	end
	local f = folder
	if f then
		f.Parent = nil
	end
end

--[[
	Shows (or moves) a named plate: a flat glowing rectangle of w x d studs
	centred on `cf`, a point on the plot surface. Plates are pooled by name,
	so calling this every frame creates nothing new.
]]
function GridOverlay.plate(name: string, cf: CFrame, w: number, d: number, color: Color3?)
	local plate = plates[name]
	if not plate then
		plate = newPart("Plate_" .. name, Vector3.new(1, PLATE_THICKNESS, 1), PLATE_COLOR, PLATE_TRANSPARENCY)
		plates[name] = plate
	end
	local size = Vector3.new(math.max(w - PLATE_INSET, 0.2), PLATE_THICKNESS, math.max(d - PLATE_INSET, 0.2))
	if plate.Size ~= size then
		plate.Size = size
	end
	local placed = cf * CFrame.new(0, PLATE_Y, 0)
	if plate.CFrame ~= placed then
		plate.CFrame = placed
	end
	local wanted = color or PLATE_COLOR
	if plate.Color ~= wanted then
		plate.Color = wanted
	end
	plate.Parent = GridOverlay.folder()
end

--[[
	A short label floating over a named plate (shown with the plate, hidden
	with it; e.g. the chute cells' PEN / TRAIN / FOUNDRY). Drawn on top of
	everything, the same size on screen at every zoom. Call after plate().
]]
function GridOverlay.tag(name: string, text: string, color: Color3)
	local plate = plates[name]
	if not plate then
		return
	end
	local label = tags[name]
	if not label then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Tag"
		gui.Size = UDim2.fromOffset(TAG_SIZE.X, TAG_SIZE.Y)
		gui.StudsOffset = Vector3.new(0, TAG_UP, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 400
		gui.Parent = plate
		local newLabel = Instance.new("TextLabel")
		newLabel.Name = "Text"
		newLabel.BackgroundTransparency = 1
		newLabel.Size = UDim2.fromScale(1, 1)
		newLabel.TextScaled = true
		newLabel.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
		newLabel.TextStrokeColor3 = Color3.fromRGB(24, 16, 14)
		newLabel.TextStrokeTransparency = 0
		newLabel.Parent = gui
		tags[name] = newLabel
		label = newLabel
	end
	local current = label :: TextLabel
	if current.Text ~= text then
		current.Text = text
	end
	if current.TextColor3 ~= color then
		current.TextColor3 = color
	end
end

-- Hides one named plate (it stays pooled).
function GridOverlay.hidePlate(name: string)
	local plate = plates[name]
	if plate then
		plate.Parent = nil
	end
end

return GridOverlay
