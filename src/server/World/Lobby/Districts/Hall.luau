--[[
	HALL OF FAME: four leaderboards in a gentle arc facing the spawn, design
	v2: Money per second, Total earned, Artifacts found, Hours played; in
	the concept v2 metal and neon language. Each board is a
	BasePart named Board1..Board4 (tag Leaderboard, attribute Board = 1..4)
	whose big Front face looks at the spawn; the leaderboard service puts a
	SurfaceGui on it at runtime. Every board sits in a thick gunmetal
	display-wall bezel with a blue neon edge on a plinth with the orange
	band, under a small glowing title plate. A HALL OF FAME sign box with
	gold crowns on two round pillars, dark lantern pillars with glowing
	slots at the ends and a winners' podium in front.
	Local frame: 24 wide, 14 tall, 6 deep, front = -Z (toward the spawn),
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
local BOARD_Y = 2.4 -- bottom of the boards

function Hall.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("HallOfFame")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
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
		local board = Style.block(m, frame * CFrame.new(0, cy, 0.3), Vector3.new(BOARD_W, BOARD_H, 0.5), Tech.Board, nil, Style.solid())
		board.Name = "Board" .. i
		board:SetAttribute("Board", i)
		Kit.tag(board, "Leaderboard")
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
			Tech.glow(m, frame * CFrame.new(sx * (BOARD_W / 2 - 0.08), cy, 0.0), Vector3.new(0.14, BOARD_H - 0.2, 0.08), Tech.Neon)
		end
		Tech.glow(m, frame * CFrame.new(0, cy + BOARD_H / 2 - 0.08, 0.0), Vector3.new(BOARD_W, 0.14, 0.08), Tech.Neon)
		Kit.bit(m, frame * CFrame.new(0, cy, 0.66), Vector3.new(BOARD_W + 0.6, BOARD_H + 0.4, 0.14), Tech.MetalDark)
		Tech.glow(m, frame * CFrame.new(0, cy + BOARD_H / 2 - 0.4, 0.75), Vector3.new(BOARD_W + 0.4, 0.16, 0.06), Tech.Neon)
		Kit.bit(m, frame * CFrame.new(0, cy - 1.2, 0.75), Vector3.new(BOARD_W + 0.6, 0.6, 0.06), Tech.Band)
		-- glowing title plate above the board
		local top = cy + BOARD_H / 2 + bt
		Style.sign(m, frame * CFrame.new(0, top + 0.75, 0.15), TITLES[i], BOARD_W + 0.2, 1.1, {
			Kind = "Glow",
			Depth = 0.4,
			BoardColor = Tech.Board,
		})
		Kit.bit(m, frame * CFrame.new(0, top + 0.75, 0.45), Vector3.new(BOARD_W + 0.8, 1.5, 0.3), Tech.MetalDark)
	end

	-- the HALL OF FAME sign box on two round pillars, gold crowns at its ends
	for _, x in { -5.6, 5.6 } do
		Tech.roundPillar(m, at(x, 0, 1.9), 10.5, 0.9, { Neon = false })
	end
	local signY = 12.0
	Tech.sign(m, at(0, signY, 1.4), "HALL OF FAME", 11.4, 2.2)
	for _, x in { -7.4, 7.4 } do
		Tech.crown(m, at(x, signY - 0.75, 1.5), 1.6, Tech.GoldGlow, { Depth = 0.5, Neon = true })
	end
	-- a warm lamp strip under the sign (glow only: the boards face the sun)
	local lamp = Tech.glow(m, at(0, 10.1, 1.1), Vector3.new(3.0, 0.2, 0.5), C.Lamp)
	lamp.Name = "HallLamp"

	-- dark lantern pillars with glowing slots at the ends
	for _, x in { -11.2, 11.2 } do
		local z = -x * x / (2 * ARC_R)
		Tech.lanternPillar(m, at(x, 0, z), 8.4, 1.2)
	end

	-- winners' podium in front of the middle boards (gold, silver, copper)
	local podium = {
		{ X = 0, H = 1.5, Color = C.Gold },
		{ X = 2.0, H = 1.0, Color = C.IronLight },
		{ X = -2.0, H = 0.7, Color = C.Copper },
	}
	for _, p in podium do
		local x, h, color = p.X, p.H, p.Color
		Style.block(m, at(x, h / 2, -1.8), Vector3.new(2.0, h, 1.8), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
		Kit.bit(m, at(x, h + 0.05, -1.8), Vector3.new(2.05, 0.12, 1.85), color)
		Tech.glow(m, at(x, h - 0.2, -2.72), Vector3.new(1.8, 0.12, 0.06), color)
	end
end

return Hall
