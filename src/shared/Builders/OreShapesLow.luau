--[[
	Ore looks for the Common, Uncommon and Rare ores of the owner's ore picture
	(docs/art/ores_reference.webp, 2026-10-18): one recipe per ore, keyed by
	the ore Id (OreData Shape = Id). ItemBuilder calls register() with its
	recipe table and the kit of helpers; a recipe gets the build context `c`:
	  c.Full   true = the podium / pen display copy (more detail, <= 14 parts),
	           false = the physical clean ore (<= 8 parts)
	  c.Order  rarity order (1 Common .. 6 Mythic), c.Rng (seeded), c.Pal (colours)
	and builds in unit space: bottom centre at the origin, about 2 studs big.
	Kit: P(x,y,z) position, A(rx,ry,rz) angles, V(x,y,z) size,
	block / wedge (c, cf, size, tone), ball (c, pos, d, tone),
	cyl (c, cf, height, d, tone) along cf.UpVector, point (c, cf, size, tone)
	a cube on its corner (crystal tip), beam (c, a, b, width, tone),
	hexPrism (c, cf, radius, height, {tones}), onBall (center, d, dir, inset?).
	Tones: "Main" "Light" "Dark" "Base" "Vein" "Tip" "Neon" "NeonDark" "Glass"
	or a Color3 (see ItemBuilder.resolve).
]]

local OreShapesLow = {}

OreShapesLow.Ores = {
	"Coal",
	"Copper",
	"Tin",
	"Iron",
	"Quartz",
	"Oakwood",
	"Honeycomb",
	"LeafOre",
	"Frostbite",
	"Emberite",
	"Cobalt",
	"Bogwood",
	"Amber",
	"Bronze",
	"Silver",
	"Gold",
	"Jade",
	"Sapphire",
	"DragonEgg",
}

function OreShapesLow.register(_shapes: { [string]: (any) -> () }, _kit: any)
	-- recipes go here: _shapes.<OreId> = function(c) ... end
end

return OreShapesLow
