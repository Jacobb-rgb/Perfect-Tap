--[[
	HALL OF FAME: four leaderboards in a gentle arc facing the spawn, design
	v2: Money per second, Total earned, Artifacts found, Hours played; in
	the concept v2 metal and neon language. Each board is a
	BasePart named Board1..Board4 (tag Leaderboard, attribute Board = 1..4)
	whose big Front face looks at the spawn; the leaderboard service puts a
	SurfaceGui on it at runtime. Until then each board shows a placeholder
	table: a Model "Placeholder" parented to the board (five faint rank
	rows reading "-" between thin warm dividers, gold, silver and bronze
	medals on the top three); the leaderboard service destroys
	Board.Placeholder when it shows real rows. The boards glow a soft
	half-bright screen blue (no dead dark panels). Every board sits in a thick gunmetal
	display-wall bezel with a blue neon edge on a plinth with the orange
	band, under a title plate (white letters on dark navy inside a thin
	neon outline, so the words do not bloom away; every title has the same
	letter size). A HALL OF FAME sign box with
	gold crowns on two round pillars, dark lantern pillars with glowing
	slots at the ends and a winners' podium in front.
	Local frame: 24 wide, 16 tall, 6 deep, front = -Z (toward the spawn),
	seen from the spawn local +X is on the viewer's left (Board1 first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Hall = {}

local C = Kit.C

local TITLES = { "MONEY / SEC", "TOTAL EARNED", "ARTIFACTS", "HOURS PLAYED" }
local ARC_R = 30 -- radius of the arc (center toward the spawn)
local BOARD_W, BOARD_H = 5.0, 6.4
local BOARD_Y = 2.0 -- bottom of the boards
local PLATE_H = 2.1 -- title plates over the boards (tall enough to read from the plaza)
local MEDALS = { C.Gold, C.IronLight, C.Copper }
local ROW_COLOR = Color3.fromRGB(44, 70, 140) -- faint rank rows on the board
-- the board face: Tech.Screen at about half value, so the waiting boards read
-- as lit screens (not dead dark panels); thin warm row dividers
local BOARD_FACE = Color3.fromRGB(15, 46, 107)

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

	local widest = 0
	for _, title in TITLES do
		widest = math.max(widest, textWidth(title))
	end

	-- board i sits at x = 8.1, 2.7, -2.7, -8.1 (viewer's left to right)
	for i = 1, 4 do
		local x = 8.1 - (i - 1) * 5.4
		local z = -x * x / (2 * ARC_R)
		local yaw = math.asin(x / ARC_R)
		local frame = at(x, 0, z) * CFrame.Angles(0, yaw, 0)
		-- gunmetal plinth with the orange band and a neon top line
		Style.block(
			m,
			frame * CFrame.new(0, BOARD_Y / 2, 0.2),
			Vector3.new(BOARD_W + 0.6, BOARD_Y, 1.4),
			Style.vary(Tech.Metal, rng, 0.03),
			nil,
			Style.solid()
		)
		Kit.bit(m, frame * CFrame.new(0, BOARD_Y * 0.45, -0.52), Vector3.new(BOARD_W + 0.6, 0.55, 0.1), Tech.Band)
		Tech.glow(m, frame * CFrame.new(0, BOARD_Y - 0.1, -0.53), Vector3.new(BOARD_W + 0.6, 0.12, 0.08), Tech.Neon)
		-- the board (flat Front face toward the spawn)
		local cy = BOARD_Y + 0.1 + BOARD_H / 2
		local board =
			Style.block(m, frame * CFrame.new(0, cy, 0.3), Vector3.new(BOARD_W, BOARD_H, 0.5), BOARD_FACE, Kit.NEON, Style.solid())
		board.CastShadow = false
		board.Name = "Board" .. i
		board:SetAttribute("Board", i)
		Kit.tag(board, "Leaderboard")
		-- the placeholder table: five rank rows ("—" until the leaderboards
		-- fill in) between thin warm dividers, medals on the top three
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
		for row = 1, 5 do
			local ry = cy + 2.15 - (row - 1) * 1.1
			Kit.bit(ph, frame * CFrame.new(-0.45, ry - 0.2, 0.03), Vector3.new(3.4, 0.08, 0.06), ROW_COLOR)
			if row < 5 then
				Tech.glow(ph, frame * CFrame.new(0, ry - 0.55, 0.02), Vector3.new(BOARD_W - 0.5, 0.06, 0.05), Tech.CaseLight)
			end
			local medal = MEDALS[row]
			if medal then
				Tech.faceDisc(ph, frame * CFrame.new(1.75, ry, 0.0), 0.08, 0.62, medal)
			end
			local label = Instance.new("TextLabel")
			label.Name = "Row" .. row
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(0.7, 0.13)
			label.Position = UDim2.fromScale(0.06, 0.07 + (row - 1) * 0.172)
			label.Text = `{row}   —`
			label.TextScaled = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = C.GlowText
			label.TextStrokeColor3 = Tech.Board
			label.TextStrokeTransparency = 0
			label.FontFace = Font.fromEnum(Style.LabelFont)
			label.Parent = gui
		end
		-- display-wall bezel: thick frame, dark back plate, blue neon inner edge
		local bt = 0.6
		local bz = 0.2
		Kit.block(
			m,
			frame * CFrame.new(0, cy + BOARD_H / 2 + bt / 2, bz),
			Vector3.new(BOARD_W + 2 * bt, bt, 1.0),
			Tech.MetalLight,
			nil,
			Style.decor()
		)
		Kit.block(
			m,
			frame * CFrame.new(0, cy - BOARD_H / 2 - bt / 2 + 0.1, bz),
			Vector3.new(BOARD_W + 2 * bt, bt, 1.0),
			Tech.Metal,
			nil,
			Style.decor()
		)
		for _, sx in { -1, 1 } do
			Kit.block(
				m,
				frame * CFrame.new(sx * (BOARD_W / 2 + bt / 2), cy, bz),
				Vector3.new(bt, BOARD_H, 1.0),
				Tech.Metal,
				nil,
				Style.decor()
			)
			Tech.glow(m, frame * CFrame.new(sx * (BOARD_W / 2 - 0.12), cy, 0.0), Vector3.new(0.28, BOARD_H - 0.2, 0.12), Tech.Tube)
		end
		Tech.glow(m, frame * CFrame.new(0, cy + BOARD_H / 2 - 0.12, 0.0), Vector3.new(BOARD_W, 0.28, 0.12), Tech.Tube)
		Kit.bit(m, frame * CFrame.new(0, cy, 0.66), Vector3.new(BOARD_W + 0.6, BOARD_H + 0.4, 0.14), Tech.MetalDark)
		Tech.glow(m, frame * CFrame.new(0, cy + BOARD_H / 2 - 0.4, 0.75), Vector3.new(BOARD_W + 0.4, 0.16, 0.06), Tech.Neon)
		Kit.bit(m, frame * CFrame.new(0, cy - 1.2, 0.75), Vector3.new(BOARD_W + 0.6, 0.6, 0.06), Tech.Band)
		-- title plate above the board: white letters on dark navy inside a thin
		-- neon outline (a thick glowing frame would bloom over the words)
		local top = cy + BOARD_H / 2 + bt
		local py = top + 0.2 + PLATE_H / 2
		Kit.bit(m, frame * CFrame.new(0, py, 0.15), Vector3.new(BOARD_W + 0.2, PLATE_H, 0.4), Tech.Board)
		local textW = (BOARD_W - 0.4) * textWidth(TITLES[i]) / widest
		Tech.label(m, frame * CFrame.new(0, py, -0.08), TITLES[i], textW, PLATE_H - 0.3, nil, 0.04)
		Tech.outline(m, frame * CFrame.new(0, py, 0.15), BOARD_W / 2 + 0.02, PLATE_H / 2 - 0.08, 0.3, 0.1, -0.25, Tech.Neon)
		Kit.bit(m, frame * CFrame.new(0, py, 0.45), Vector3.new(BOARD_W + 0.8, PLATE_H + 0.4, 0.3), Tech.MetalDark)
	end

	-- the HALL OF FAME sign box on two round pillars, gold crowns at its ends
	for _, x in { -5.6, 5.6 } do
		Tech.roundPillar(m, at(x, 0, 1.9), 10.5, 0.9, { Neon = false })
	end
	local signY = 13.6
	Tech.sign(m, at(0, signY, 1.4), "HALL OF FAME", 11.4, 2.2, { Back = true })
	for _, x in { -7.5, 7.5 } do
		Tech.crown(m, at(x, signY - 0.8, 1.5), 1.8, Tech.GoldGlow, { Depth = 0.55, Neon = true })
	end

	-- dark lantern pillars with glowing slots at the ends
	for _, x in { -11.2, 11.2 } do
		local z = -x * x / (2 * ARC_R)
		Tech.lanternPillar(m, at(x, 0, z), 8.4, 1.2)
	end

	-- the winners' 1-2-3 podium in front of the middle boards: a dark
	-- gunmetal base and three stepped blocks (gold, silver, copper fronts)
	Style.block(m, at(0, 0.15, -1.8), Vector3.new(6.6, 0.3, 2.3), Tech.MetalDark, nil, Style.solid())
	local podium = {
		{ X = 0, H = 1.6, Color = C.Gold },
		{ X = 2.1, H = 1.1, Color = C.IronLight },
		{ X = -2.1, H = 0.75, Color = C.Copper },
	}
	for _, p in podium do
		local x, h, color = p.X, p.H, p.Color
		Style.block(m, at(x, 0.3 + h / 2, -1.8), Vector3.new(2.1, h, 1.9), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
		Kit.bit(m, at(x, 0.3 + h / 2, -2.78), Vector3.new(1.7, h - 0.2, 0.08), color)
		Tech.glow(m, at(x, 0.3 + h - 0.08, -2.78), Vector3.new(2.1, 0.12, 0.08), color)
	end
end

return Hall
