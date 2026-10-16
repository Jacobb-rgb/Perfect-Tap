--[[
	HALL OF FAME: four leaderboards in a gentle arc facing the spawn
	(design v2: Money per second, Total earned, Artifacts found, Hours
	played). Each board is a BasePart named Board1..Board4 (tag Leaderboard,
	attribute Board = 1..4) whose big Front face looks at the spawn; the
	leaderboard service puts a SurfaceGui on it at runtime. A title plank
	above each board, a HALL OF FAME header on two posts, lantern columns
	at the ends and a small winners' podium in front.
	Local frame: 24 wide, 14 tall, 6 deep, front = -Z (toward the spawn),
	seen from the spawn local +X is on the viewer's left (Board1 first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

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
		-- stone plinth
		Style.block(
			m,
			frame * CFrame.new(0, BOARD_Y / 2, 0.2),
			Vector3.new(BOARD_W + 0.2, BOARD_Y, 1.2),
			Style.vary(C.StoneDark, rng, 0.04),
			nil,
			Style.solid()
		)
		Kit.bit(m, frame * CFrame.new(0, BOARD_Y + 0.05, 0.2), Vector3.new(BOARD_W + 0.4, 0.2, 1.4), C.StoneLight)
		-- the board (flat Front face toward the spawn)
		local board = Style.block(
			m,
			frame * CFrame.new(0, BOARD_Y + 0.1 + BOARD_H / 2, 0.3),
			Vector3.new(BOARD_W, BOARD_H, 0.5),
			C.GlowBoard,
			nil,
			Style.solid()
		)
		board.Name = "Board" .. i
		board:SetAttribute("Board", i)
		Kit.tag(board, "Leaderboard")
		-- plank backing so the boards look finished from behind (hero view)
		Kit.bit(m, frame * CFrame.new(0, BOARD_Y + 0.1 + BOARD_H / 2, 0.62), Vector3.new(BOARD_W + 0.3, BOARD_H + 0.3, 0.14), C.Plank)
		Kit.bit(m, frame * CFrame.new(0, BOARD_Y + 0.1 + BOARD_H / 2, 0.71), Vector3.new(0.5, BOARD_H, 0.06), C.WoodDark)
		-- wooden frame
		local top = BOARD_Y + 0.1 + BOARD_H
		local fz = 0.3 - 0.3
		Kit.bit(m, frame * CFrame.new(0, top + 0.15, fz), Vector3.new(BOARD_W + 0.5, 0.35, 0.35), C.SignFrame)
		Kit.bit(m, frame * CFrame.new(0, BOARD_Y + 0.2, fz), Vector3.new(BOARD_W + 0.5, 0.3, 0.35), C.SignFrame)
		for _, sx in { -1, 1 } do
			Kit.bit(m, frame * CFrame.new(sx * (BOARD_W / 2 + 0.1), top - BOARD_H / 2, fz), Vector3.new(0.3, BOARD_H, 0.35), C.SignFrame)
		end
		-- title plank
		Style.sign(m, frame * CFrame.new(0, top + 0.95, 0.2), TITLES[i], BOARD_W + 0.2, 1.15, { Kind = "Wood", Depth = 0.4, Frame = false })
	end

	-- header on two posts
	for _, x in { -5.4, 5.4 } do
		Style.block(m, at(x, 6.6, 1.0), Vector3.new(0.7, 13.2, 0.7), C.WoodDark)
	end
	local headerZ = 0.45
	Style.sign(m, at(0, 12.0, headerZ - 0.5), "HALL OF FAME", 11.6, 2.4, { Kind = "Wood" })
	Style.block(m, at(0, 12.0, headerZ), Vector3.new(12.4, 3.0, 0.4), C.WoodDark)
	-- gold crowns at the header ends
	for _, x in { -6.9, 6.9 } do
		local base = at(x, 11.4, headerZ - 0.3)
		Kit.bit(m, base * CFrame.new(0, 0.25, 0), Vector3.new(1.4, 0.5, 0.4), C.Gold)
		for _, px in { -0.5, 0, 0.5 } do
			Kit.bit(m, base * CFrame.new(px, 0.75, 0), Vector3.new(0.32, if px == 0 then 0.8 else 0.55, 0.36), C.Gold)
		end
		Kit.glow(m, base * CFrame.new(0, 0.25, -0.22), Vector3.new(0.3, 0.3, 0.06), C.AwningRed)
	end
	-- one warm lamp under the header lights all four boards
	local lamp = Kit.glow(m, at(0, 10.6, -0.3), Vector3.new(0.6, 0.4, 0.4), C.Lamp)
	Style.light(lamp, C.Lamp, 18, 1.3)

	-- lantern columns at the ends
	for _, x in { -11.3, 11.3 } do
		local z = -x * x / (2 * ARC_R)
		Style.block(m, at(x, 0.35, z), Vector3.new(1.4, 0.7, 1.4), C.StoneDark)
		Style.block(m, at(x, 4.9, z), Vector3.new(1.1, 8.4, 1.1), Style.vary(C.Stone, rng, 0.04))
		Kit.glow(m, at(x, 9.6, z), Vector3.new(0.9, 1.0, 0.9), C.Lamp)
		Kit.bit(m, at(x, 10.25, z), Vector3.new(1.35, 0.3, 1.35), C.Iron)
	end

	-- winners' podium in front of the middle boards (gold, silver, copper)
	local podium = {
		{ X = 0, H = 1.5, Color = C.Gold },
		{ X = 2.0, H = 1.0, Color = C.IronLight },
		{ X = -2.0, H = 0.7, Color = C.Copper },
	}
	for _, p in podium do
		local x, h, color = p.X, p.H, p.Color
		Style.block(m, at(x, h / 2, -1.8), Vector3.new(2.0, h, 1.8), Style.vary(C.Stone, rng, 0.03), nil, Style.solid())
		Kit.bit(m, at(x, h + 0.05, -1.8), Vector3.new(2.05, 0.12, 1.85), color)
	end
end

return Hall
