--[[
	The EGG GOLEMS' costumes (GolemConfig Family; owner 2026-10-30: "make
	the golems like in this picture, those are cleaner": the Sky and
	Dragonforge limited golems; 10-31: "crisp two-tone armour, a strong
	signature each"). Every golem of an egg wears its egg's armour set
	(plates in its own colour over a darker under-suit, the egg's metal for
	the trim, the egg's emblem on the breastplate), so each egg's golems read
	as one set, plus its own signature silhouette; a rarer one wears more
	(back pieces, floating bits) and glows more:

	  Stone    polished stone plates, bronze trim, a bronze cog, miner and tinker
	           gear, a warm ember glow
	  Crystal  gem-coloured plates, silver trim, a silver frame holding a crystal,
	           crystals growing from the shoulders, a cool glow
	  Royal    ore-metal plates trimmed with gold, a gold crest, helms, crowns,
	           halos, wings of light (divine; no capes: a cape is the Dragon
	           King's alone)

	Each family lives in its own module (EggGear/<Family>.luau) and builds
	its costumes from the shared clean pieces (EggGear/Clean.luau). A costume
	follows the limited sets' contract (GolemGearLimited): it adds parts to
	c.Model in unscaled golem units from the feet (c.At / c.V / tools.P),
	may re-dress the body's own parts at no part cost, adds optional parts
	only while c.Room() allows (GolemConfig.EggMaxParts by rarity) and
	returns roughly the top of what it added (GolemBuilder measures the real
	Height). GolemBuilder rounds the helm (else the head) and any
	part a costume marks with the attribute "Round" (a hood's head). Legendary
	and Mythic costumes may add one slow ember emitter (tools.embers), a
	Mythic one light (tools.light; a follower drops it). Each golem keeps its
	GolemConfig Accessory name (the 2D portraits key on it).

	  costumes(kit, tools)   golem id -> its costume
]]

local Types = require(script.Parent.LimitedGearTypes)
local Clean = require(script.Clean)
local Stone = require(script.Stone)
local Crystal = require(script.Crystal)
local Royal = require(script.Royal)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools

local EggGear = {}

EggGear.Families = { "Stone", "Crystal", "Royal" }

-- Every egg golem's costume by golem id.
function EggGear.costumes(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	local gear = Clean.new(kit, tools)
	local all: { [string]: (Ctx) -> number } = {}
	for _, family in { Stone.costumes(kit, tools, gear), Crystal.costumes(kit, tools, gear), Royal.costumes(kit, tools, gear) } do
		for id, add in family do
			all[id] = add
		end
	end
	return all
end

return EggGear
