--[[
	LIMITED EDITION golems (owner 2026-10-20: "a limited mega cool edition of
	golems"): a themed set of 6 golems (GolemConfig.List, Edition = the
	set's id: Rare, Rare, Epic, Epic, Legendary, Mythic) wearing the set's
	gear (Builders/GolemGearLimited), sold only as the set's Robux capsule
	(CapsuleConfig, Limited = the set's id; MonetizationConfig products for
	1 / 3 / 10 / 50) in the Robux shop's FEATURED banner, for one window.

	- Editions change monthly; the owner decides each launch with us. Current
	  names the edition on sale and its real end (EndsAt, unix seconds UTC):
	  set both at each launch. No fake timers: the banner counts down to
	  EndsAt and the sale really stops there (docs/COMPLIANCE.md).
	- current(now) is the banner's data while the edition runs (nil after
	  EndsAt or for an unknown set). CapsuleService refuses to PROMPT a
	  limited capsule that isn't on sale (onSale; CapsuleConfig.Reasons
	  "Ended"); a receipt is ALWAYS granted (a purchase finished a moment
	  before the end, a Roblox retry days later), so the capsule, its
	  products and the golems stay in the configs forever, and the golems
	  woken are ordinary golems for good.
	- The odds are the capsule's (CapsuleConfig.odds, Triple Lucky included),
	  shown before every purchase; PaidRandom (PolicyService) like every paid
	  random item.
]]

local CapsuleConfig = require(script.Parent.CapsuleConfig)
local GolemConfig = require(script.Parent.GolemConfig)

export type Backdrop = {
	SkyTop: Color3, -- banner gradient top
	SkyHorizon: Color3, -- banner gradient bottom
	Ground: Color3, -- the stage the golems stand on
	Accent: Color3, -- the set's glow (title, rim lights)
	Title: { Color3 }, -- the title text gradient (top -> bottom)
	-- the banner's painted background (the set's scene rendered without its
	-- golems: tools/preview/limited_golems.sh -> NAHRAJ_DO_ROBLOXU), an image
	-- asset id the owner uploads; 0 = not uploaded (the drawn sky shows)
	Image: number?,
}

-- One set (forever: its golems and capsule stay after it ends).
export type Set = {
	Id: string,
	Title: string,
	Tagline: string,
	Backdrop: Backdrop,
	CapsuleId: string, -- its Robux capsule (CapsuleConfig, Limited = Id)
}

-- What the shop's banner reads while an edition runs (current).
export type Edition = {
	Id: string,
	Title: string,
	Tagline: string,
	Backdrop: Backdrop,
	Golems: { GolemConfig.Golem }, -- set order: Rare, Rare, Epic, Epic, Legendary, Mythic
	Odds: { [string]: number }, -- golem id -> chance (sum 1; the capsule's own, no Triple Lucky)
	CapsuleId: string,
	Products: { [number]: string }, -- count (1, 3, 10, 50) -> MonetizationConfig key
	EndsAt: number, -- unix seconds (UTC): the sale stops after this second
}

local LimitedGolems = {}

-- The rarities of a set, in order.
LimitedGolems.SetRarities = { "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

LimitedGolems.Sets = {
	Dragonforge = {
		Id = "Dragonforge",
		Title = "DRAGONFORGE",
		Tagline = "Golems forged in dragon fire!",
		Backdrop = {
			SkyTop = rgb(36, 10, 30),
			SkyHorizon = rgb(255, 96, 40),
			Ground = rgb(40, 30, 34),
			Accent = rgb(255, 128, 30),
			Title = { rgb(255, 236, 110), rgb(255, 90, 20) },
			Image = 0, -- banner_Dragonforge.png (owner uploads it)
		},
		CapsuleId = "Dragonforge",
	},
} :: { [string]: Set }

--[[
	The edition on sale: the OWNER SETS BOTH AT EACH LAUNCH (editions change
	monthly). EndsAt is a real date in unix seconds, UTC: 1796083199 =
	2026-11-30 23:59:59 UTC. To launch the next one: add its set (Sets, its
	golems with Edition in GolemConfig, its capsule and products), then point
	Current at it with its own EndsAt.
]]
LimitedGolems.Current = { Id = "Dragonforge", EndsAt = 1796083199 }

-- A set's golems in set order (GolemConfig.List order).
function LimitedGolems.golems(setId: string): { GolemConfig.Golem }
	local list = {}
	for _, golem in GolemConfig.List do
		if golem.Edition == setId then
			table.insert(list, golem)
		end
	end
	return list
end

-- The edition on sale at `now` (unix seconds, UTC), or nil (after EndsAt,
-- an unknown set, a broken Current).
function LimitedGolems.current(now: number): Edition?
	local current = LimitedGolems.Current
	local set = if type(current) == "table" then LimitedGolems.Sets[current.Id] else nil
	local capsule = if set then CapsuleConfig.ById[set.CapsuleId] else nil
	local endsAt = if type(current) == "table" then current.EndsAt else nil
	if
		not set
		or not capsule
		or not capsule.Products
		or type(endsAt) ~= "number"
		or type(now) ~= "number"
		or now ~= now
		or now > endsAt
	then
		return nil
	end
	return {
		Id = set.Id,
		Title = set.Title,
		Tagline = set.Tagline,
		Backdrop = set.Backdrop,
		Golems = LimitedGolems.golems(set.Id),
		Odds = table.clone(capsule.Odds),
		CapsuleId = capsule.Id,
		Products = table.clone(capsule.Products),
		EndsAt = endsAt,
	}
end

-- Is this a limited edition's capsule?
function LimitedGolems.isLimited(capsuleId: string): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	return capsule ~= nil and capsule.Limited ~= nil
end

-- May this capsule be offered (prompted) at `now`? Every other capsule:
-- true; a limited one only while its edition is the current one.
function LimitedGolems.onSale(capsuleId: string, now: number): boolean
	if not LimitedGolems.isLimited(capsuleId) then
		return true
	end
	local edition = LimitedGolems.current(now)
	return edition ~= nil and edition.CapsuleId == capsuleId
end

-- Sanity: every set has its capsule and its 6 golems by rarity, the capsule
-- rolls exactly them.
for id, set in LimitedGolems.Sets do
	assert(set.Id == id, "LimitedGolems: bad set " .. id)
	local capsule = CapsuleConfig.ById[set.CapsuleId]
	assert(capsule and capsule.Limited == id and capsule.Currency == "Robux", "LimitedGolems: bad capsule for " .. id)
	local golems = LimitedGolems.golems(id)
	assert(#golems == #LimitedGolems.SetRarities, "LimitedGolems: " .. id .. " needs 6 golems")
	for i, golem in golems do
		assert(golem.Rarity == LimitedGolems.SetRarities[i], `LimitedGolems: {golem.Id} should be {LimitedGolems.SetRarities[i]}`)
		assert(capsule.Odds[golem.Id], `LimitedGolems: {golem.Id} isn't in {capsule.Id}`)
	end
	for golemId in capsule.Odds do
		local golem = GolemConfig.ById[golemId]
		assert(golem and golem.Edition == id, `LimitedGolems: {capsule.Id} rolls {golemId}`)
	end
end

return LimitedGolems
