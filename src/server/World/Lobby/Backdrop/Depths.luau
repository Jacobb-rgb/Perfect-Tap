--[[
	DepthsPortal + DepthsRails (LOBBY_PLAN 6.2 items 3 and 5): the stone
	and iron portal that frames the real Ember Caves entrance (Land's tunnel
	mouth at z -236), with the DEPTHS sign, a keystone with a down arrow,
	a string of warm bulbs under the lintel, receding U-shaped iron frames
	with ember edges inside the tunnel, pillar lanterns, and rails with an
	ore cart running out onto the quarry floor.
	The walkway x -9..9, y -12..4 stays open (tests/LobbyBackdrop.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local Depths = {}

-- Kept open for walking into the caves (portal frame).
Depths.Opening = { Min = Vector3.new(-9, -12, -246), Max = Vector3.new(9, 4, -222) }
Depths.RailX = -2.5

local FLOOR = -12
local SOUTH = Vector3.new(0, 0, 1)

function Depths.buildPortal(parent: Instance, rng: Rng.Rng): Model
	local m = Kit.piece(parent, "DepthsPortal")
	-- pillars holding the tunnel roof, a glowing band near the top
	for _, side in { -1, 1 } do
		Style.pillar(m, CFrame.new(side * 14, FLOOR, -229.5), 22, rng, { Width = 4, Glow = C.Fire })
	end
	-- side buttresses (stepped stone) out to the edge of the frame
	for _, side in { -1, 1 } do
		Kit.column(
			m,
			side * 16.2,
			-238,
			side * 22,
			-231,
			FLOOR,
			18,
			rng,
			{ Color = C.StoneDark, Cap = "None", Front = Vector3.new(0, 0, 1), Accents = 2 }
		)
		Kit.box(
			m,
			Vector3.new(side * 16.8, 18, -237),
			Vector3.new(side * 21.4, 21, -231.6),
			Style.vary(C.Stone, rng, 0.05),
			nil,
			Style.solid()
		)
	end
	-- parapet above the tunnel roof: closes the gap into the cave and carries the sign
	Kit.column(m, -16.2, -238, 16.2, -231.6, 10, 26, rng, { Color = C.StoneDeep, Cap = "None", Front = Vector3.new(0, 0, 1), Accents = 3 })
	Kit.box(m, Vector3.new(-17, 26, -238.4), Vector3.new(17, 27.4, -231), Style.vary(C.StoneLight, rng, 0.04), nil, Style.solid())
	-- lintel (covers the tunnel roof's front edge), stepped haunches = the arch
	Kit.box(m, Vector3.new(-16.6, 6, -230), Vector3.new(16.6, 12, -226.6), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	for _, side in { -1, 1 } do
		Kit.box(
			m,
			Vector3.new(side * 10.4, 3.4, -229.8),
			Vector3.new(side * 12.1, 6, -227),
			Style.vary(C.Stone, rng, 0.04),
			nil,
			Style.solid()
		)
		Kit.box(
			m,
			Vector3.new(side * 9.3, 4.6, -229.8),
			Vector3.new(side * 10.5, 6, -227.2),
			Style.vary(C.StoneLight, rng, 0.04),
			nil,
			Style.tiny()
		)
	end
	-- keystone with the down arrow
	local key = Kit.box(m, Vector3.new(-2.3, 7.4, -226.9), Vector3.new(2.3, 13.6, -225.9), C.StoneLight, nil, Style.tiny())
	key.Name = "Keystone"
	-- down arrow (a V head under the shaft) in glowing gold
	local ax, ay, az = 0, 10.5, -225.5
	Kit.box(m, Vector3.new(ax - 0.4, ay - 0.6, az - 0.3), Vector3.new(ax + 0.4, ay + 2.4, az + 0.15), C.SignText, NEON, Style.tiny())
	for _, side in { -1, 1 } do
		Kit.beam(m, Vector3.new(ax + side * 1.6, ay + 0.3, az), Vector3.new(ax + side * 0.15, ay - 1.75, az), 0.75, C.SignText, NEON)
	end
	-- warm bulbs along the arch
	for i = -2, 2 do
		local x = i * 5
		if i ~= 0 then
			Kit.bulb(m, Vector3.new(x, 6.5, -226.4), 0.7)
		end
	end
	-- DEPTHS sign on the parapet
	Style.sign(m, Kit.facing(Vector3.new(0, 18.8, -231.25), SOUTH), "DEPTHS", 26, 7.4, { Kind = "Stone", Depth = 0.7 })
	-- receding U-shaped iron frames inside the tunnel, ember inner edges
	for _, z in { -238, -241, -244 } do
		for _, side in { -1, 1 } do
			Kit.box(m, Vector3.new(side * 9.8, FLOOR, z - 0.5), Vector3.new(side * 10.9, 5.6, z + 0.5), C.Iron, METAL, Style.decor())
			Kit.box(m, Vector3.new(side * 9.3, FLOOR + 0.6, z - 0.3), Vector3.new(side * 9.8, 4.1, z + 0.3), C.Fire, NEON, Style.tiny())
		end
		Kit.box(m, Vector3.new(-10.9, 4.6, z - 0.5), Vector3.new(10.9, 5.8, z + 0.5), C.Iron, METAL, Style.decor())
		Kit.box(m, Vector3.new(-9.8, 4.1, z - 0.3), Vector3.new(9.8, 4.6, z + 0.3), C.Fire, NEON, Style.tiny())
	end
	-- pillar lanterns either side, the portal's one light on a hidden bulb at the keystone
	for _, side in { -1, 1 } do
		Style.lantern(m, CFrame.new(side * 19.2, FLOOR, -227.6), { Kind = "Pillar", Height = 4.5 })
	end
	local glow = Kit.bulb(m, Vector3.new(0, 5.2, -228.2), 0.6, C.Fire)
	glow.Name = "PortalGlow"
	Style.light(glow, C.Fire, 22, 1.8)
	return m
end

function Depths.buildRails(parent: Instance, rng: Rng.Rng): Model
	local m = Kit.piece(parent, "DepthsRails")
	local x = Depths.RailX
	local z0, z1 = -238, -207.5
	Style.rails(m, Vector3.new(x, FLOOR, z0), Vector3.new(x, FLOOR, z1), { SleeperEvery = 2.4 })
	Style.mineCart(m, CFrame.lookAt(Vector3.new(x, FLOOR, -215.5), Vector3.new(x, FLOOR, -205)), rng, { Load = "Gold" })
	-- buffer stop
	for _, side in { -1, 1 } do
		Kit.box(
			m,
			Vector3.new(x + side * 1.2, FLOOR, z1 - 0.2),
			Vector3.new(x + side * 2, FLOOR + 2.6, z1 + 0.8),
			C.WoodDark,
			nil,
			Style.decor()
		)
	end
	Kit.box(m, Vector3.new(x - 2.4, FLOOR + 1.4, z1 + 0.8), Vector3.new(x + 2.4, FLOOR + 2.4, z1 + 1.3), C.Hazard, nil, Style.tiny())
	Kit.box(m, Vector3.new(x - 0.6, FLOOR + 1.5, z1 + 1.3), Vector3.new(x + 0.6, FLOOR + 2.3, z1 + 1.4), C.HazardDark, nil, Style.tiny())
	return m
end

return Depths
