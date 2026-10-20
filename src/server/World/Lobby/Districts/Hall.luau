--[[
	HALL OF FAME: four leaderboards, design v2: Money per second, Total
	earned, Artifacts found, Hours played. Each board is a BasePart named
	Board1..Board4 (tag Leaderboard, attribute Board = 1..4) whose big Front
	face looks out of the hall's front; the leaderboard service puts a
	SurfaceGui on it at runtime. Until then each board shows a placeholder
	table: a Model "Placeholder" parented to the board holding one SurfaceGui
	(Adornee = the board) with a rank row per place ("1  -" ... "5  -"), no
	parts; the leaderboard service destroys Board.Placeholder when it shows
	real rows.

	The giant hall (owner 2026-10-20: "massive, and the best player's skin
	always hops on top", from his leaderboard plaza photo): the four boards
	stand side by side, tall, in a gunmetal wall on a plinth with the orange
	band; slim pillars between them carry glowing diamond gems in each
	board's colour (gold, cyan, purple, green); a big HALL OF FAME sign box
	runs over the boards and on top of it four round pedestals, one over
	each board: BaseParts Champion1..Champion4 (tag LeaderChampion,
	attribute Board = 1..4) where ChampionService stands the board's #1
	player's avatar (the client makes it hop).
	Local frame: Size.X wide, Size.Y tall, Size.Z deep, front = -Z (toward
	the plaza), seen from the front local +X is on the viewer's left
	(Board1 first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Hall = {}

local C = Kit.C
local rgb = Color3.fromRGB

local TITLES = { "MONEY / SEC", "TOTAL EARNED", "ARTIFACTS", "HOURS PLAYED" }
Hall.BoardColor = rgb(26, 40, 90) -- navy boards (round 3)
-- each board's colour: its frame line, the gems beside it and its pedestal ring
Hall.Colors = { rgb(255, 176, 30), rgb(40, 200, 255), rgb(170, 90, 255), rgb(70, 220, 90) }
local BOARD_W, BOARD_H = 4.8, 7.2
local PILLAR = 0.45 -- the pillars between the boards
local PLINTH = 1.2 -- plinth top
local TITLE_H = 1.0 -- the title strip over the top of each board
local ARC_R = 30 -- the boards turn a little toward a point this far in front
Hall.SignHeight = 2.4
Hall.PedestalHeight = 0.5

-- Rough glyph widths of the sign font (em): the title labels get widths in
-- proportion, so TextScaled gives every title the same letter size.
local function textWidth(text: string): number
	local w = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if ch == " " then
			w += 0.3
		elseif ch == "/" or ch == "I" then
			w += 0.4
		elseif ch == "M" or ch == "W" then
			w += 0.85
		else
			w += 0.62
		end
	end
	return w
end

-- Board i's centre x in the hall's local frame (Board1 on the viewer's left).
function Hall.boardX(i: number): number
	return (1.5 - (i - 1)) * (BOARD_W + PILLAR)
end

function Hall.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("HallOfFame")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local W = piece.Size.X - 0.4
	local boardY = PLINTH + 0.3 + BOARD_H / 2
	local wallTop = PLINTH + 0.3 + BOARD_H + 0.5

	-- the plinth with the orange band and a neon top line
	Style.block(m, at(0, PLINTH / 2, 0.2), Vector3.new(W, PLINTH, 3.0), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, PLINTH * 0.45, -1.32), Vector3.new(W, 0.45, 0.1), Tech.Band)
	Tech.glow(m, at(0, PLINTH - 0.06, -1.34), Vector3.new(W, 0.12, 0.08), Tech.Neon)
	-- the gunmetal display wall behind the boards, warm timber on its back
	Style.block(
		m,
		at(0, (PLINTH + wallTop) / 2, 0.9),
		Vector3.new(W, wallTop - PLINTH, 0.6),
		Style.vary(Tech.MetalDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, (PLINTH + wallTop) / 2, 1.26), Vector3.new(W - 0.6, wallTop - PLINTH - 0.6, 0.12), C.Wood)

	-- the pillars: one at each end and between the boards, two glowing diamond gems each
	for p = 0, 4 do
		local x = (2 - p) * (BOARD_W + PILLAR)
		local yaw = math.asin(math.clamp(x / ARC_R, -1, 1))
		local frame = at(x, 0, 0) * CFrame.Angles(0, yaw, 0)
		Style.block(
			m,
			frame * CFrame.new(0, (PLINTH + wallTop) / 2 + 0.2, 0.2),
			Vector3.new(PILLAR, wallTop - PLINTH + 0.4, 1.0),
			Tech.MetalLight,
			nil,
			Style.decor()
		)
		-- the gems take the colours of the boards beside the pillar
		local left = Hall.Colors[math.clamp(p, 1, 4)]
		local right = Hall.Colors[math.clamp(p + 1, 1, 4)]
		for g, color in { left, right } do
			local gem = Kit.bit(
				m,
				frame * CFrame.new(0, PLINTH + 1.6 + (g - 1) * (BOARD_H - 2.2), -0.36) * CFrame.Angles(0, 0, math.rad(45)),
				Vector3.new(0.52, 0.52, 0.3),
				color,
				Kit.NEON
			)
			gem.Name = "Gem"
		end
	end

	local widest = 0
	for _, title in TITLES do
		widest = math.max(widest, textWidth(title))
	end
	for i = 1, 4 do
		local x = Hall.boardX(i)
		local yaw = math.asin(x / ARC_R)
		local frame = at(x, 0, 0) * CFrame.Angles(0, yaw, 0)
		local color = Hall.Colors[i]
		-- a light bezel plate behind the board, a neon line in the board's colour on top and below
		Kit.bit(m, frame * CFrame.new(0, boardY, 0.42), Vector3.new(BOARD_W + 0.3, BOARD_H + 0.4, 0.2), Tech.MetalLight)
		Tech.glow(m, frame * CFrame.new(0, boardY + BOARD_H / 2 + 0.12, 0.2), Vector3.new(BOARD_W + 0.2, 0.18, 0.12), color)
		Tech.glow(m, frame * CFrame.new(0, boardY - BOARD_H / 2 - 0.12, 0.2), Vector3.new(BOARD_W + 0.2, 0.18, 0.12), color)
		-- the board (flat Front face out of the hall's front)
		local board =
			Style.block(m, frame * CFrame.new(0, boardY, 0.15), Vector3.new(BOARD_W, BOARD_H, 0.4), Hall.BoardColor, Kit.NEON, Style.solid())
		board.CastShadow = false
		board.Name = "Board" .. i
		board:SetAttribute("Board", i)
		Kit.tag(board, "Leaderboard")
		-- its title strip over the board's top
		local textW = (BOARD_W - 0.5) * textWidth(TITLES[i]) / widest
		Kit.bit(
			m,
			frame * CFrame.new(0, boardY + BOARD_H / 2 - TITLE_H / 2 - 0.05, -0.08),
			Vector3.new(BOARD_W - 0.2, TITLE_H, 0.06),
			Tech.Board
		)
		Tech.label(m, frame * CFrame.new(0, boardY + BOARD_H / 2 - TITLE_H / 2 - 0.05, -0.15), TITLES[i], textW, TITLE_H - 0.15, nil, 0.04)
		-- the placeholder table: five rank rows on one SurfaceGui, no parts
		local ph = Style.model("Placeholder", board)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlaceholderRows"
		gui.Face = Enum.NormalId.Front
		gui.Adornee = board
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 140
		gui.Parent = ph
		local medals = { C.Gold, C.IronLight, C.Copper }
		for r = 1, 5 do
			local label = Instance.new("TextLabel")
			label.Name = "Row" .. r
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(0.8, 0.1)
			label.Position = UDim2.fromScale(0.1, 0.22 + (r - 1) * 0.13)
			label.Text = `{r}   —`
			label.TextScaled = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = medals[r] or C.GlowText
			label.TextStrokeColor3 = Hall.BoardColor
			label.TextStrokeTransparency = 0
			label.FontFace = Font.fromEnum(Style.LabelFont)
			label.Parent = gui
		end
	end

	-- the HALL OF FAME sign box over the boards, square to the viewer
	local signY = wallTop + 0.3 + Hall.SignHeight / 2
	Tech.sign(m, at(0, signY, 0.4), "HALL OF FAME", W - 1.0, Hall.SignHeight, { Back = true, Studs = false, Margin = 0.5 })

	-- the champions' pedestals on the sign box, one over each board
	local signTop = signY + Hall.SignHeight / 2 + 0.25
	for i = 1, 4 do
		local x = Hall.boardX(i)
		local yaw = math.asin(x / ARC_R)
		local base = at(x, signTop + Hall.PedestalHeight / 2, 0.4) * CFrame.Angles(0, yaw, 0)
		local pedestal = Style.block(m, base, Vector3.new(2.6, Hall.PedestalHeight, 2.6), Tech.MetalLight, nil, Style.decor())
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.Size = Vector3.new(Hall.PedestalHeight, 2.6, 2.6)
		pedestal.CFrame = base * CFrame.Angles(0, 0, math.rad(90))
		pedestal.Name = "Champion" .. i
		pedestal:SetAttribute("Board", i)
		Kit.tag(pedestal, "LeaderChampion")
		-- a glowing ring round its top edge in the board's colour
		local ring = Kit.bit(m, base * CFrame.new(0, Hall.PedestalHeight / 2 - 0.04, 0), Vector3.new(0.1, 2.75, 2.75), Hall.Colors[i], Kit.NEON)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = base * CFrame.new(0, Hall.PedestalHeight / 2 - 0.04, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Name = "ChampionRing"
	end
end

return Hall
