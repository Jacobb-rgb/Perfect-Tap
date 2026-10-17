--[[
	HALL OF FAME: four leaderboards, design v2: Money per second, Total
	earned, Artifacts found, Hours played; in the concept v2 metal and neon
	language. Each board is a BasePart named Board1..Board4 (tag
	Leaderboard, attribute Board = 1..4) whose big Front face looks out of
	the hall's front; the leaderboard service puts a SurfaceGui on it at
	runtime. Until then each board shows a placeholder table: a Model
	"Placeholder" parented to the board holding one SurfaceGui (Adornee =
	the board) with a rank row per place ("1  -" ... "5  -"), no parts; the
	leaderboard service destroys Board.Placeholder when it shows real rows.

	Lobby fix round 3: a compact 2 x 2 display wall beside the forge porch,
	opposite the guild board (the four-board arc on the south-east rim hid
	the FOSSIL DIG and the ROCK SCANNER). Navy boards (26, 40, 90) glow
	softly in light bezels on a gunmetal wall, each under its own title
	strip (white letters on dark navy), on a plinth with the orange band;
	over them a HALL OF FAME sign box turned square to the viewer, letters
	about 1.6 studs tall; slim neon side posts.
	Local frame: Size.X wide, Size.Y tall, Size.Z deep, front = -Z (toward
	the plaza), seen from the front local +X is on the viewer's left
	(Board1 first, top row).
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
local BOARD_W, BOARD_H = 5.4, 5.0
local PLINTH = 1.0 -- plinth top
local ROW_GAP = 0.4
local TITLE_H = 0.9 -- the title strip over the top of each board
local ARC_R = 30 -- the boards turn a little toward a point this far in front
Hall.SignHeight = 2.4

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

function Hall.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("HallOfFame")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local W = piece.Size.X - 0.4
	local colX = BOARD_W / 2 + 0.45

	-- the plinth with the orange band and a neon top line
	Style.block(m, at(0, PLINTH / 2, 0.2), Vector3.new(W, PLINTH, 2.6), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, PLINTH * 0.45, -1.12), Vector3.new(W, 0.4, 0.1), Tech.Band)
	Tech.glow(m, at(0, PLINTH - 0.06, -1.14), Vector3.new(W, 0.12, 0.08), Tech.Neon)
	-- the gunmetal display wall behind the boards, warm timber on its back
	local wallTop = PLINTH + 2 * (BOARD_H + ROW_GAP) + 0.2
	Style.block(
		m,
		at(0, (PLINTH + wallTop) / 2, 0.9),
		Vector3.new(W, wallTop - PLINTH, 0.6),
		Style.vary(Tech.MetalDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, (PLINTH + wallTop) / 2, 1.26), Vector3.new(W - 0.6, wallTop - PLINTH - 0.6, 0.12), C.Wood)
	-- slim side posts with blue neon strips
	for _, side in { -1, 1 } do
		Style.block(
			m,
			at(side * (W / 2 - 0.3), (PLINTH + wallTop) / 2 + 0.3, 0.3),
			Vector3.new(0.6, wallTop - PLINTH + 0.6, 1.0),
			Tech.Metal,
			nil,
			Style.decor()
		)
		Tech.glow(
			m,
			at(side * (W / 2 - 0.3), (PLINTH + wallTop) / 2 + 0.3, -0.24),
			Vector3.new(0.22, wallTop - PLINTH - 0.4, 0.08),
			Tech.Tube
		)
	end

	local widest = 0
	for _, title in TITLES do
		widest = math.max(widest, textWidth(title))
	end
	for i = 1, 4 do
		local col = (i - 1) % 2
		local row = (i - 1) // 2 -- 0 = top row
		local x = if col == 0 then colX else -colX
		local cy = PLINTH + ROW_GAP / 2 + BOARD_H / 2 + (1 - row) * (BOARD_H + ROW_GAP)
		local yaw = math.asin(x / ARC_R)
		local frame = at(x, 0, 0) * CFrame.Angles(0, yaw, 0)
		-- a light bezel plate behind the board, a neon line on top
		Kit.bit(m, frame * CFrame.new(0, cy, 0.42), Vector3.new(BOARD_W + 0.5, BOARD_H + 0.4, 0.2), Tech.MetalLight)
		Tech.glow(m, frame * CFrame.new(0, cy + BOARD_H / 2 + 0.12, 0.2), Vector3.new(BOARD_W + 0.4, 0.16, 0.12), Tech.Tube)
		-- the board (flat Front face out of the hall's front)
		local board =
			Style.block(m, frame * CFrame.new(0, cy, 0.15), Vector3.new(BOARD_W, BOARD_H, 0.4), Hall.BoardColor, Kit.NEON, Style.solid())
		board.CastShadow = false
		board.Name = "Board" .. i
		board:SetAttribute("Board", i)
		Kit.tag(board, "Leaderboard")
		-- its title strip over the board's top
		local textW = (BOARD_W - 0.5) * textWidth(TITLES[i]) / widest
		Kit.bit(
			m,
			frame * CFrame.new(0, cy + BOARD_H / 2 - TITLE_H / 2 - 0.05, -0.08),
			Vector3.new(BOARD_W - 0.2, TITLE_H, 0.06),
			Tech.Board
		)
		Tech.label(m, frame * CFrame.new(0, cy + BOARD_H / 2 - TITLE_H / 2 - 0.05, -0.15), TITLES[i], textW, TITLE_H - 0.15, nil, 0.04)
		-- the placeholder table: five rank rows on one SurfaceGui, no parts
		local ph = Style.model("Placeholder", board)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlaceholderRows"
		gui.Face = Enum.NormalId.Front
		gui.Adornee = board
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.Parent = ph
		local medals = { C.Gold, C.IronLight, C.Copper }
		for r = 1, 5 do
			local label = Instance.new("TextLabel")
			label.Name = "Row" .. r
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(0.8, 0.12)
			label.Position = UDim2.fromScale(0.1, 0.24 + (r - 1) * 0.15)
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
	-- (round 3: letters about 1.6 studs tall)
	local signY = wallTop + 0.34 + 0.5 + Hall.SignHeight / 2
	Tech.sign(m, at(0, signY, 0.4), "HALL OF FAME", W - 1.0, Hall.SignHeight, { Back = true, Studs = false, Margin = 0.5 })
end

return Hall
