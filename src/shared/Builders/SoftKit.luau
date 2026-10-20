--[[
	Style A "Soft" for the world pieces built in code (owner 2026-10-20: the
	plot pieces in the machines' style, from the preview on art/plot-style-a):
	the plot walls and posts, the Ore Pen, the podiums and the train stop
	(PlotBuilder) and the Foundry building (FoundryBuilder). The same palette
	and roles as the machines (KitMachines.Palette, KitMachines.style: cream
	Body, slate Frame / Pipe, orange Trim, glowing Neon / Glow / Hot / Molten,
	Dark mouths, Glass), soft round shapes, signs in LuckiestGuy orange on
	slate. Flat details (tile seams, hazard stripes, panel insets) are
	SurfaceGui frames, so they cost no parts.

	Helpers take a CFrame frame (not world points like KitMachines' own
	helpers): `part` takes a role (a KitMachines.Palette key: the Kit
	attribute, colour, material, see-through and shine of the role) or a
	plain Color3 (SmoothPlastic); `cylUp` / `cylX` / `cylZ` are cylinders
	along the frame's up / X / Z axis, `rod` a cylinder between two world
	points. Pure: only Instance creation (the Lune tools build it too).
]]

local Geo = require(script.Parent.Geo)
local KitMachines = require(script.Parent.KitMachines)

local SoftKit = {}

export type Props = { [string]: any }
export type Role = string | Color3
export type Paint = { x: number, y: number, w: number, h: number, color: Color3, round: boolean?, stripes: number? }

local rgb = Color3.fromRGB
local P = KitMachines.Palette

SoftKit.Palette = P
SoftKit.Text = rgb(255, 170, 60) -- sign letters (orange, a little lighter than the strips)
SoftKit.Lamp = rgb(232, 102, 24) -- lamp balls: a deeper orange than the strips (no white / yellow bloom)

-- part property sets
SoftKit.SOLID = { CanTouch = false } :: Props -- players and items bump into it
SoftKit.FENCE = { CanTouch = false, CanQuery = false } :: Props -- collides, not raycast
SoftKit.TRIM = { CanTouch = false, CanQuery = false, CastShadow = false } :: Props -- collides, too small for a shadow
SoftKit.PROP = { CanTouch = false, CanQuery = false, CanCollide = false } :: Props
SoftKit.TINY = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false } :: Props

local CYLINDER = Enum.PartType.Cylinder

-- A part in a palette role or a plain Color3 (`shape`: Cylinder / Ball).
function SoftKit.part(parent: Instance, cf: CFrame, size: Vector3, role: Role, flags: Props, name: string?, shape: Enum.PartType?): Part
	local p: Part = Geo.make("Part", { CFrame = cf, Size = size }, parent)
	if typeof(role) == "Color3" then
		p.Color = role
		for key, value in flags do
			(p :: any)[key] = value
		end
		if name then
			p.Name = name
		end
	else
		KitMachines.style(p, role, flags, name)
	end
	if shape then
		p.Shape = shape
	end
	return p
end
local part = SoftKit.part

-- An upright cylinder centred at `cf`.
function SoftKit.cylUp(parent: Instance, cf: CFrame, height: number, d: number, role: Role, flags: Props, name: string?): Part
	return part(parent, cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(height, d, d), role, flags, name, CYLINDER)
end

-- A cylinder along the frame's Z axis.
function SoftKit.cylZ(parent: Instance, cf: CFrame, length: number, d: number, role: Role, flags: Props, name: string?): Part
	return part(parent, cf * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(length, d, d), role, flags, name, CYLINDER)
end

-- A cylinder along the frame's X axis.
function SoftKit.cylX(parent: Instance, cf: CFrame, length: number, d: number, role: Role, flags: Props, name: string?): Part
	return part(parent, cf, Vector3.new(length, d, d), role, flags, name, CYLINDER)
end

function SoftKit.ball(parent: Instance, pos: Vector3, d: number, role: Role, flags: Props, name: string?): Part
	return part(parent, CFrame.new(pos), Vector3.new(d, d, d), role, flags, name, Enum.PartType.Ball)
end

-- A cylinder from world point a to b.
function SoftKit.rod(parent: Instance, a: Vector3, b: Vector3, d: number, role: Role, flags: Props, name: string?): Part
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return part(parent, cf, Vector3.new((b - a).Magnitude, d, d), role, flags, name, CYLINDER)
end

function SoftKit.wedge(parent: Instance, cf: CFrame, size: Vector3, role: Role, flags: Props, name: string?): WedgePart
	local w: WedgePart = Geo.make("WedgePart", { CFrame = cf, Size = size }, parent)
	if typeof(role) == "Color3" then
		w.Color = role
		for key, value in flags do
			(w :: any)[key] = value
		end
		if name then
			w.Name = name
		end
	else
		KitMachines.style(w, role, flags, name)
	end
	return w
end

-- Makes a part glow (a Color3 part in Neon).
function SoftKit.glow(p: Part): Part
	p.Material = Enum.Material.Neon
	return p
end

function SoftKit.attachment(parent: BasePart, name: string, localCF: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = localCF
	a.Parent = parent
	return a
end

-- Text on one face of a part (LuckiestGuy, like the machine signs): a SurfaceGui "Gui" with the TextLabel "Text".
function SoftKit.label(board: BasePart, face: Enum.NormalId, text: string, color: Color3, light: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = light or 0.3
	gui.Parent = board
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.04, 0.1)
	l.Size = UDim2.fromScale(0.92, 0.8)
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	l.Parent = gui
	return gui
end

-- A slate sign board "Sign" with orange letters (on both faces when `back`).
function SoftKit.sign(parent: Instance, cf: CFrame, size: Vector3, text: string, back: boolean?, flags: Props?): Part
	local board = part(parent, cf, size, "Frame", flags or SoftKit.PROP, "Sign")
	SoftKit.label(board, Enum.NormalId.Front, text, SoftKit.Text)
	if back then
		SoftKit.label(board, Enum.NormalId.Back, text, SoftKit.Text)
	end
	return board
end

-- Painted details on one face (SurfaceGui frames, scale coordinates from the top left; `stripes` = hazard stripes).
function SoftKit.paint(target: BasePart, face: Enum.NormalId, items: { Paint }, maxDistance: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Paint"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = maxDistance or 140
	gui.Parent = target
	for _, it in items do
		local stripes = it.stripes
		if stripes then
			SoftKit.stripes(gui, it.x, it.y, it.w, it.h, stripes)
			continue
		end
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = it.color
		frame.Position = UDim2.fromScale(it.x, it.y)
		frame.Size = UDim2.fromScale(it.w, it.h)
		if it.round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
		end
		frame.Parent = gui
	end
	return gui
end

-- Most stripes one gradient carries: a ColorSequence takes at most 20
-- keypoints (two per stripe), from time 0 to exactly 1.
SoftKit.StripesPerGradient = 10

--[[
	`count` hazard stripes (orange Trim / Dark, left to right) across the
	rect x, y, w, h of a SurfaceGui: frames of at most StripesPerGradient
	stripes side by side, each with its own UIGradient of hard steps.
]]
function SoftKit.stripes(gui: SurfaceGui, x: number, y: number, w: number, h: number, count: number)
	local n = math.max(1, math.floor(count))
	local chunks = math.ceil(n / SoftKit.StripesPerGradient)
	local from = 0
	for c = 1, chunks do
		local to = math.floor(n * c / chunks + 0.5)
		local k = to - from
		local frame = Instance.new("Frame")
		frame.Name = "Stripes"
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.Position = UDim2.fromScale(x + w * from / n, y)
		frame.Size = UDim2.fromScale(w * k / n, h)
		local keys = {}
		for j = 0, k - 1 do
			local color = if (from + j) % 2 == 0 then P.Trim else P.Dark
			local t0, t1 = j / k, (j + 1) / k
			table.insert(keys, ColorSequenceKeypoint.new(t0, color))
			table.insert(keys, ColorSequenceKeypoint.new(if j == k - 1 then 1 else t1 - 0.001, color))
		end
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keys)
		gradient.Parent = frame
		frame.Parent = gui
		from = to
	end
end

return SoftKit
