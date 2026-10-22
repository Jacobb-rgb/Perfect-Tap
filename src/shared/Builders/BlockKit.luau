--[[
	The "block tycoon" look (owner 2026-10-21, after Sandbox Tycoon): everything
	is chunky cubes on a grid, every cube has a darker rim and a lighter face
	(the textured-block look without textures), with a few bright "pixels" in
	the corners. Used by the hoppers, the 2X laser and the HOPPER WORKS house.

	  cube(parent, cf, size, face, rim, sides?)  a framed block (sides: "all" |
	                    "side" (no top frame) | "flat" (one part))
	  pixels(parent, cf, size, color, n)  n bright squares on a face (+Z side)
	  pixelArt(parent, cf, rows, unit, colors)  a picture of cubes, row by row
	                    ("..##." strings; one part per run of the same colour)
	  belt(parent, cf, length, width)  a conveyor piece along +X: rails, dark
	                    belt, yellow chevrons
	  text(parent, cf, size, text, ink, board, edge, font?)  a sign plate whose
	                    text faces +Z

	Pure: only creates Instances (the Lune previews run it too).
]]

local Geo = require(script.Parent.Geo)

local BlockKit = {}

local rgb = Color3.fromRGB
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

BlockKit.Rim = 0.16 -- how much of each face edge is rim (studs)
BlockKit.Lift = 0.03 -- how far a face sticks out of its rim

local function decor(cast: boolean?): { [string]: any }
	-- (decor never collides; the framed blocks' outer shells, cast = true, do)
	return { CanTouch = false, CanQuery = false, CastShadow = cast == true, CanCollide = cast == true }
end

-- A framed block: the rim colour all over, the face colour inset on every side.
function BlockKit.cube(parent: Instance, cf: CFrame, size: Vector3, face: Color3, rim: Color3, sides: string?): Part
	local mode = sides or "all"
	local outer = Geo.block(parent, cf, size, if mode == "flat" then face else rim, PLASTIC, decor(true))
	if mode == "flat" then
		return outer
	end
	local r, l = BlockKit.Rim * 2, BlockKit.Lift * 2
	local minSide = math.min(size.X, size.Y, size.Z)
	if minSide <= r * 1.5 then
		outer.Color = face
		return outer
	end
	-- faces toward ±Z and ±X (the rim shows around each)
	Geo.block(parent, cf, Vector3.new(size.X - r, size.Y - r, size.Z + l), face, PLASTIC, decor())
	Geo.block(parent, cf, Vector3.new(size.X + l, size.Y - r, size.Z - r), face, PLASTIC, decor())
	if mode == "all" then
		Geo.block(parent, cf, Vector3.new(size.X - r, size.Y + l, size.Z - r), face, PLASTIC, decor())
	end
	return outer
end

-- `n` bright square pixels near the corners of the +Z face of a block of `size` at `cf`.
function BlockKit.pixels(parent: Instance, cf: CFrame, size: Vector3, color: Color3, n: number, material: Enum.Material?)
	local p = math.clamp(math.min(size.X, size.Y) * 0.12, 0.18, 0.42)
	local inX, inY = size.X / 2 - BlockKit.Rim - p * 0.9, size.Y / 2 - BlockKit.Rim - p * 0.9
	local spots = {
		Vector2.new(-inX, inY),
		Vector2.new(inX, -inY),
		Vector2.new(inX - p, -inY),
		Vector2.new(-inX, inY - p),
		Vector2.new(inX, inY),
		Vector2.new(-inX, -inY),
	}
	for i = 1, math.min(n, #spots) do
		local s = spots[i]
		Geo.block(
			parent,
			cf * CFrame.new(s.X, s.Y, size.Z / 2 + BlockKit.Lift + 0.01),
			Vector3.new(p, p, 0.04),
			color,
			material or NEON,
			decor()
		)
	end
end

--[[
	A picture of cubes facing +Z, centred on `cf`. `rows` top to bottom, each
	character one cell; `colors` maps a character to a colour ("." = empty).
	One part per run of the same colour in a row.
]]
function BlockKit.pixelArt(
	parent: Instance,
	cf: CFrame,
	rows: { string },
	unit: number,
	colors: { [string]: Color3 },
	depth: number?,
	material: Enum.Material?
)
	local h, w = #rows, 0
	for _, row in rows do
		w = math.max(w, #row)
	end
	local d = depth or unit
	for y, row in rows do
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			local run = 1
			while x + run <= #row and string.sub(row, x + run, x + run) == ch do
				run += 1
			end
			local color = colors[ch]
			if color then
				local cx = (x - 1 + run / 2 - w / 2) * unit
				local cy = (h / 2 - (y - 0.5)) * unit
				Geo.block(parent, cf * CFrame.new(cx, cy, 0), Vector3.new(run * unit, unit, d), color, material or PLASTIC, decor())
			end
			x += run
		end
	end
end

-- A conveyor piece along +X from `cf` (its middle): two block rails, the dark
-- belt and yellow chevrons pointing +X.
BlockKit.BeltColor = rgb(40, 42, 50)
BlockKit.RailFace = rgb(150, 104, 62) -- wooden rails, like the planks
BlockKit.RailRim = rgb(104, 68, 40)
BlockKit.Chevron = rgb(255, 204, 40)
function BlockKit.belt(parent: Instance, cf: CFrame, length: number, width: number?)
	local w = width or 2.4
	Geo.block(parent, cf * CFrame.new(0, 0.3, 0), Vector3.new(length, 0.6, w), BlockKit.BeltColor, PLASTIC, decor(true))
	for _, side in { -1, 1 } do
		BlockKit.cube(
			parent,
			cf * CFrame.new(0, 0.5, side * (w / 2 + 0.3)),
			Vector3.new(length, 1.0, 0.6),
			BlockKit.RailFace,
			BlockKit.RailRim,
			"side"
		)
	end
	local step = 2.4
	local count = math.max(1, math.floor(length / step))
	for i = 1, count do
		local x = -length / 2 + (i - 0.5) * (length / count)
		-- a ">" of two flat bars
		for _, side in { -1, 1 } do
			Geo.block(
				parent,
				cf * CFrame.new(x - 0.22, 0.62, side * 0.3) * CFrame.Angles(0, side * 0.75, 0),
				Vector3.new(0.95, 0.05, 0.24),
				BlockKit.Chevron,
				PLASTIC,
				decor()
			)
		end
	end
end

-- Scales every part of `model` by `k` around `origin` (keeps their turns).
function BlockKit.scale(model: Instance, origin: CFrame, k: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local rel = origin:ToObjectSpace(part.CFrame)
			part.Size *= k
			part.CFrame = origin * CFrame.new(rel.Position * k) * (rel - rel.Position)
		end
	end
end

-- A sign plate whose text faces +Z (a glowing edge behind it).
function BlockKit.text(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	words: string,
	ink: Color3,
	board: Color3,
	edge: Color3?,
	font: Enum.Font?
): Part
	if edge then
		Geo.block(parent, cf * CFrame.new(0, 0, -0.03), size + Vector3.new(0.18, 0.18, -0.02), edge, PLASTIC, decor())
	end
	local plate = Geo.block(parent, cf, size, board, PLASTIC, decor())
	plate.Name = "Sign"
	-- (like SoftKit.label: a canvas by pixels per stud, a scaled transparent label)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.TextScaled = true
	label.Text = words
	label.TextColor3 = ink
	label.FontFace = Font.fromEnum(font or Enum.Font.FredokaOne)
	label.Parent = gui
	return plate
end

return BlockKit
