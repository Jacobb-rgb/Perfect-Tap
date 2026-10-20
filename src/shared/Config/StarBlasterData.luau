--[[
	STAR blasters (the owner's picks 2026-10-20): five weapons above the ten
	blaster levels that open only after rebirths ("Star Forge"). Each one is
	bought ONCE, for Robux (a game pass) or for Forge Stars (the Star Forge's
	BLASTERS tab), and is KEPT through every later rebirth (losing something
	you paid for isn't fair): RebirthConfig.reset never touches them.

	Each one is a Kenney Blaster Kit shape the levels don't use (the kit's
	f, h, l, o, q: KenneyBlaster.Models 11-15), in its own celestial skin,
	with the level 10 detail (crystals, a crown round the barrel, sparks or
	flames).

	  Unlock   the rebirth count that opens it (Rebirths >= Unlock): before
	           that it can't be bought with stars or equipped; a pass bought
	           on the game page waits ("Opens at rebirth N")
	  Mult     POWER A: it hits Mult x the damage of the blaster level you
	           have forged (BlasterData.damage(level, ore)); the floors, the
	           range and the rebirth stars still follow the forged level, so
	           a rebirth run is never skipped. The beam takes its Glow
	  Robux    the one-time Game Pass price (MonetizationConfig StarComet..
	           StarSingularity, Grant "RebirthWeapon": RebirthService)
	  Stars    the Forge Stars price (the other way, no Robux needed)

	The save (DataTemplate): RebirthWeapons = { [id] = true } every one you
	own, RebirthWeaponPasses = { [id] = true } the ones a game pass gave (a
	refund takes back only those), StarBlaster = the equipped id ("" = your
	forged blaster). equipped() is the one check every server path uses.
]]

export type StarBlaster = {
	Id: string,
	Name: string,
	Index: number, -- 1..5: KenneyBlaster.Models[10 + Index]
	Unlock: number, -- rebirths needed
	Mult: number, -- damage x the forged level's (POWER A)
	Body: Color3,
	Glow: Color3,
	Gem: Color3, -- the cut gems in gold bezels and half the crown (KenneyBlaster Tier 4)
	Magma: boolean, -- lava cracks and flames (else stars and sparks)
	Robux: number, -- the Game Pass price (MonetizationConfig: keep them equal)
	Stars: number, -- the Forge Stars price
	Text: string,
}

local rgb = Color3.fromRGB

local StarBlasterData = {}

StarBlasterData.List = {
	{
		Id = "Comet",
		Name = "Comet Launcher",
		Index = 1,
		Unlock = 1,
		Mult = 1.2,
		Body = rgb(44, 82, 160),
		Glow = rgb(150, 226, 255),
		Gem = rgb(60, 130, 255), -- a sapphire
		Magma = false,
		Robux = 75,
		Stars = 20,
		Text = "An icy comet in a launcher",
	},
	{
		Id = "Nebula",
		Name = "Nebula Twin",
		Index = 2,
		Unlock = 2,
		Mult = 1.35,
		Body = rgb(98, 40, 150),
		Glow = rgb(255, 120, 225),
		Gem = rgb(50, 205, 255), -- an aquamarine
		Magma = false,
		Robux = 125,
		Stars = 30,
		Text = "Twin barrels full of pink star dust",
	},
	{
		Id = "Pulsar",
		Name = "Pulsar Rifle",
		Index = 3,
		Unlock = 3,
		Mult = 1.5,
		Body = rgb(20, 84, 104),
		Glow = rgb(80, 255, 220),
		Gem = rgb(255, 180, 30), -- a topaz
		Magma = false,
		Robux = 199,
		Stars = 45,
		Text = "A long rifle that pulses like a dead star",
	},
	{
		Id = "Supernova",
		Name = "Supernova Gatling",
		Index = 4,
		Unlock = 5,
		Mult = 1.65,
		Body = rgb(40, 22, 18),
		Glow = rgb(255, 170, 60),
		Gem = rgb(255, 35, 55), -- a ruby
		Magma = true,
		Robux = 299,
		Stars = 65,
		Text = "Four barrels of an exploding star",
	},
	{
		Id = "Singularity",
		Name = "Singularity Rail",
		Index = 5,
		Unlock = 8,
		Mult = 1.8,
		Body = rgb(38, 26, 70),
		Glow = rgb(176, 110, 255),
		Gem = rgb(255, 70, 190), -- a pink rhodolite
		Magma = false,
		Robux = 449,
		Stars = 90,
		Text = "A black hole between two rails",
	},
} :: { StarBlaster }

StarBlasterData.ById = {} :: { [string]: StarBlaster }
for _, star in StarBlasterData.List do
	StarBlasterData.ById[star.Id] = star
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function mapOf(data: any, key: string): { [string]: any }
	local t = if type(data) == "table" then data[key] else nil
	return if type(t) == "table" then t else {}
end

-- The weapon behind an id (nil for anything else).
function StarBlasterData.get(id: any): StarBlaster?
	return if type(id) == "string" then StarBlasterData.ById[id] else nil
end

-- A save's rebirth count (whole, >= 0; RebirthConfig.countOf).
local function rebirthsOf(data: any): number
	local v = if type(data) == "table" then data.Rebirths else nil
	return if finite(v) and v > 0 then math.floor(v) else 0
end

-- A save's unspent Forge Stars (RebirthConfig.starsOf).
local function starsOf(data: any): number
	local v = if type(data) == "table" then data.Stars else nil
	return if finite(v) and v > 0 then math.floor(v) else 0
end

-- Has the save done the rebirths that open weapon `id`?
function StarBlasterData.unlocked(data: any, id: any): boolean
	local star = StarBlasterData.get(id)
	return star ~= nil and rebirthsOf(data) >= star.Unlock
end

-- Does the save own weapon `id` (stars or a game pass)?
function StarBlasterData.owns(data: any, id: any): boolean
	local star = StarBlasterData.get(id)
	return star ~= nil and mapOf(data, "RebirthWeapons")[star.Id] == true
end

-- The weapon the player fights with: the equipped one when it is owned and
-- open, else nil (the forged blaster).
function StarBlasterData.equipped(data: any): StarBlaster?
	local id = if type(data) == "table" then data.StarBlaster else nil
	if StarBlasterData.owns(data, id) and StarBlasterData.unlocked(data, id) then
		return StarBlasterData.get(id)
	end
	return nil
end

-- The damage multiplier of the weapon in hand (1 = the forged blaster).
function StarBlasterData.mult(data: any): number
	local star = StarBlasterData.equipped(data)
	return if star then star.Mult else 1
end

-- What buying weapon `id` with Forge Stars costs, or why not:
-- "BadWeapon" | "Owned" | "Locked" (too few rebirths) | "NoStars".
function StarBlasterData.quote(data: any, id: any): (number?, string?)
	local star = StarBlasterData.get(id)
	if not star then
		return nil, "BadWeapon"
	end
	if StarBlasterData.owns(data, star.Id) then
		return nil, "Owned"
	end
	if not StarBlasterData.unlocked(data, star.Id) then
		return nil, "Locked"
	end
	if starsOf(data) < star.Stars then
		return star.Stars, "NoStars"
	end
	return star.Stars, nil
end

-- Buys weapon `id` with Forge Stars (after quote said yes) and equips it.
function StarBlasterData.buy(data: { [string]: any }, id: string)
	local star = StarBlasterData.ById[id]
	data.Stars = starsOf(data) - star.Stars
	local owned = data.RebirthWeapons
	if type(owned) ~= "table" then
		owned = {}
		data.RebirthWeapons = owned
	end
	owned[star.Id] = true
	data.StarBlaster = star.Id
end

-- What a weapon's card shows: "Locked" (too few rebirths), "Waiting" (owned,
-- a pass bought before it opened), "Buy", "Owned" (equip it) or "Equipped".
function StarBlasterData.cardState(data: any, id: string): string
	local owns = StarBlasterData.owns(data, id)
	if not StarBlasterData.unlocked(data, id) then
		return if owns then "Waiting" else "Locked"
	end
	if not owns then
		return "Buy"
	end
	return if type(data) == "table" and data.StarBlaster == id then "Equipped" else "Owned"
end

return StarBlasterData
