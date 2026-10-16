--[[
	QuarryFallsWest / QuarryFallsEast: two waterfalls down the massif face
	into pools hugging the quarry's north wall (LOBBY_PLAN 6.2 item 6).
	West: from the tier-1 notch (fed by the west cascade of the massif).
	East: from the ForgeWorks sluice (fed by the summit cascade).
	The pools are non-collide water over the solid quarry floor and stay
	clear of the quarry's node spawns (tests/LobbyBackdrop.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Massif = require(script.Parent.Massif)

local C = Style.C

local Falls = {}

Falls.WestLipY = Massif.WestNotch.Top + 1.0
Falls.EastLipY = 31.2
Falls.SheetZ = -232.6

local function pool(m: Model, x: number, width: number, rng: Rng.Rng)
	local floorY = WorldLayout.Quarry.Min.Y
	local z0, z1 = -234, -227.5
	Style.water(m, CFrame.new(x, floorY + 0.25, (z0 + z1) / 2), Vector3.new(width, 0.5, z1 - z0))
	-- stone rim on the sides and the front
	for _, side in { -1, 1 } do
		Kit.box(
			m,
			Vector3.new(x + side * (width / 2), floorY, z0),
			Vector3.new(x + side * (width / 2 + 1.6), floorY + 1.2, z1 + 0.5),
			Style.vary(C.Stone, rng, 0.06),
			nil,
			Style.solid()
		)
	end
	local stones = math.max(2, math.floor(width / 3.2))
	for i = 0, stones - 1 do
		local cx = x - width / 2 + (i + 0.5) * width / stones
		local s = rng:range(1.6, 2.4)
		Style.block(
			m,
			CFrame.new(cx, floorY + s * 0.3, z1 + 0.6),
			Vector3.new(width / stones + 0.3, s * 0.6, 1.6),
			Style.vary(if i % 2 == 0 then C.Stone else C.StoneDark, rng, 0.06),
			nil,
			Style.solid()
		)
	end
end

function Falls.build(parent: Instance, rng: Rng.Rng)
	-- west: a stone lip out of the tier-1 notch
	do
		local m, piece = Kit.piece(parent, "QuarryFallsWest")
		local x = piece.Center.X
		local lipY = Falls.WestLipY
		Kit.box(
			m,
			Vector3.new(x - 4.8, lipY - 3.4, Massif.FrontZ - 1.5),
			Vector3.new(x + 4.8, lipY - 0.3, Falls.SheetZ + 0.4),
			Style.vary(C.StoneDark, rng, 0.05),
			nil,
			Style.solid()
		)
		Kit.box(
			m,
			Vector3.new(x - 5, lipY - 1.2, Falls.SheetZ - 0.3),
			Vector3.new(x + 5, lipY - 0.2, Falls.SheetZ + 1.2),
			Style.vary(C.Stone, rng, 0.05),
			nil,
			Style.tiny()
		)
		Style.water(
			m,
			CFrame.new(x, lipY - 0.1, (Massif.FrontZ - 1.5 + Falls.SheetZ) / 2),
			Vector3.new(7.6, 0.4, Falls.SheetZ - Massif.FrontZ + 1.5)
		)
		local top = CFrame.lookAt(Vector3.new(x, lipY, Falls.SheetZ), Vector3.new(x, lipY, Falls.SheetZ + 1))
		Style.waterfall(m, top, lipY - WorldLayout.Quarry.Min.Y, 8, rng)
		pool(m, x, 11, rng)
	end
	-- east: out of the ForgeWorks sluice
	do
		local m, piece = Kit.piece(parent, "QuarryFallsEast")
		local x = piece.Center.X
		local lipY = Falls.EastLipY
		Kit.box(
			m,
			Vector3.new(x - 3.8, lipY - 2.4, -238.6),
			Vector3.new(x + 3.8, lipY - 0.3, Falls.SheetZ + 0.4),
			Style.vary(C.StoneDark, rng, 0.05),
			nil,
			Style.solid()
		)
		Kit.box(
			m,
			Vector3.new(x - 4, lipY - 1.2, Falls.SheetZ - 0.3),
			Vector3.new(x + 4, lipY - 0.2, Falls.SheetZ + 1.2),
			C.IronLight,
			Enum.Material.Metal,
			Style.tiny()
		)
		Style.water(m, CFrame.new(x, lipY - 0.1, (-238.6 + Falls.SheetZ) / 2), Vector3.new(6.2, 0.4, Falls.SheetZ + 238.6))
		local top = CFrame.lookAt(Vector3.new(x, lipY, Falls.SheetZ), Vector3.new(x, lipY, Falls.SheetZ + 1))
		Style.waterfall(m, top, lipY - WorldLayout.Quarry.Min.Y, 7, rng)
		pool(m, x, 10, rng)
	end
end

return Falls
