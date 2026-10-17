--[[
	Lobby package "Vault": the Blaster Vault (the blaster shop) at the end of
	the south road, its two giant stone king statues and six jungle trees
	(owner-approved preview: tools/lune/lib/blaster_shop.luau, "Forge Vault").

	  BlasterVault     the vault (built at design size, scaled by Scale): the
	                   podium, stone walls, glass front, sign, roof, gables,
	                   hologram (Spin), the ten cases inside, the vault door,
	                   the counter (tag VaultCounter = the shop hook), the
	                   Blastsmith, wall decorations, a LightingZone (Preset
	                   VaultInterior) over the inside
	  VaultStatueWest  giant statues on pedestals, facing the plaza, the
	  VaultStatueEast  blaster arm on the outer side
	  VaultTrees       six jungle trees around the vault (placed relative to it)

	Frames come from the LobbyLayout pieces of the same names; before they
	exist, the agreed defaults below are used. Budget: <= 3500 parts, <= 6
	lights, <= 12 particle emitters (tests/LobbyVault.spec.luau).
	Pure builder: Instance creation only, deterministic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Style)
local Kit = require(script.Kit)
local Building = require(script.Building)
local Interior = require(script.Interior)
local Statue = require(script.Statue)
local Tree = require(script.Tree)

local Vault = {}

Vault.Replaces = {} :: { string }

Vault.Scale = 0.8 -- design studs -> lobby studs for the vault building
Vault.CenterOffset = 7 -- the footprint's center lies this far in front of the vault's origin (design studs)

-- A frame like LobbyLayout.frame: bottom center, LookVector = facing.
local function frameAt(center: Vector3, facing: Vector3): CFrame
	local look = Vector3.new(facing.X, 0, facing.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	return CFrame.fromMatrix(center, right, Vector3.new(0, 1, 0), -look)
end

-- Where the pieces go until LobbyLayout has them (the owner-approved spot at the end of the south road).
Vault.Defaults = {
	BlasterVault = frameAt(Vector3.new(0, 0, 112.4), Vector3.new(0, 0, -1)),
	VaultStatueWest = frameAt(Vector3.new(-43, 0, 92), Vector3.new(0.296, 0, -0.955)),
	VaultStatueEast = frameAt(Vector3.new(43, 0, 92), Vector3.new(-0.296, 0, -0.955)),
}

-- The jungle trees relative to the vault's origin (x to its right, z toward its front, world studs): x, z, trunk height, canopy radius.
Vault.Trees = {
	{ 29, -35, 48, 13 },
	{ -29, -37, 52, 14 },
	{ 45, -2, 40, 11 },
	{ 47, -22, 44, 12 },
	{ -45, 10, 40, 11 },
	{ -46, -18, 44, 12 },
}

-- The vault's origin frame (podium foot center, front = +Z = toward the plaza).
function Vault.origin(): CFrame
	local piece = Kit.frame("BlasterVault", Vault.Defaults.BlasterVault)
	return piece * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -Vault.CenterOffset * Vault.Scale)
end

local function embers(part: BasePart, kind: string, color: Color3, rate: number)
	Style.emitter(part, kind, color, rate)
end

-- The vault building.
function Vault.buildVault(parent: Instance): Model
	local m = Style.model("BlasterVault", parent)
	local ground = Vault.origin()
	local origin = ground * CFrame.new(0, Building.PODIUM_H, 0)
	Building.podium(m, ground)
	Building.walls(m, origin)
	local bowls = Building.front(m, origin)
	Building.sign(m, origin * CFrame.new(0, 17.9, 25.3))
	Building.facade(m, origin)
	Building.roof(m, origin)
	Building.backGable(m, origin)
	Building.frontGable(m, origin)
	local towers = Building.towers(m, origin)
	local holo, gems = Building.hologram(m, origin)
	Building.crystals(m, origin)
	local pools = Building.lavaFalls(m, origin)
	Building.forecourt(m, origin)
	Interior.floor(m, origin)
	Interior.cases(m, origin)
	Interior.door(m, origin * CFrame.new(0, 18.2, -21.6), 6.6)
	Interior.ceiling(m, origin)
	Interior.counter(m, origin)
	Interior.decor(m, origin)
	Interior.zone(m, origin)
	Kit.light(m, (origin * CFrame.new(0, 17, 31)).Position, Kit.C.Fire, 22, 1)
	Kit.scale(m, ground, Vault.Scale)
	-- particles (after scaling): embers over the fire bowls, the towers, the braziers, the lava pools
	for _, p in bowls do
		embers(p, "Embers", Kit.C.Fire, 4)
	end
	for _, p in towers do
		embers(p, "Embers", Kit.C.Fire, 8)
	end
	for _, p in pools do
		embers(p, "Embers", Kit.C.Lava, 5)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Brazier" then
			embers(d, "Embers", Kit.C.Fire, 4)
		end
	end
	-- the hologram floats and turns, its gems circle the other way (DecorController, tag Spin)
	holo:SetAttribute("SpinSpeed", 0.5)
	holo:SetAttribute("BobHeight", 0.8)
	holo:SetAttribute("BobSpeed", 1.1)
	holo:AddTag("Spin")
	Style.streaming(holo, "Atomic")
	gems:SetAttribute("SpinSpeed", -0.35)
	gems:SetAttribute("BobHeight", 0)
	gems:AddTag("Spin")
	Style.streaming(gems, "Atomic")
	return m
end

-- The two statues: facing along their pieces, the blaster arm on the side away from the vault.
function Vault.buildStatues(parent: Instance): { Model }
	local vaultPos = Vault.origin().Position
	local out = {}
	for _, name in { "VaultStatueWest", "VaultStatueEast" } do
		local piece = Kit.frame(name, Vault.Defaults[name])
		local ground = piece * CFrame.Angles(0, math.pi, 0) -- the statue's front (+Z) along Facing
		local outward = ground.Position - vaultPos
		local arm = if ground.RightVector:Dot(Vector3.new(outward.X, 0, outward.Z)) > 0 then 1 else -1
		table.insert(out, Statue.build(parent, ground, arm, name))
	end
	return out
end

function Vault.buildTrees(parent: Instance): Model
	local m = Style.model("VaultTrees", parent)
	local origin = Vault.origin()
	for i, t in Vault.Trees do
		Tree.build(m, (origin * CFrame.new(t[1], 0, t[2])).Position, t[3], t[4], "JungleTree" .. i)
	end
	return m
end

function Vault.build(parent: Model, _rng: Rng.Rng)
	Vault.buildVault(parent)
	Vault.buildStatues(parent)
	Vault.buildTrees(parent)
	Kit.finish(parent)
end

return Vault
