--[[
	How firing a blaster feels (client effects only, Effects/BlasterFx): the
	beam's thickness, the muzzle flash, the sparks and rock chips at the hit,
	the hit sounds, the recoil, and the extra effects of the top levels. All
	tuning lives here.

	Tiers by blaster level:
	  1-3   a clean beam, a small muzzle flash, sparks in the beam's glow
	  4-6   thicker, brighter, more sparks
	  7-9   + an energy stream running along the beam, sparkles swirling off
	        the muzzle, more chips
	  10    + shock rings at the hit, the thickest beam
	A hit "pulse" (every Pulse seconds while the beam is on a rock you can
	mine) throws sparks and a hit crackle, kicks the gun and the camera a
	little; every ChipEvery-th pulse also throws rock chips (in the rock's
	crust colour: the ores inside stay secret until cleaned) and a thud.

	Phones: half the particles, no camera kick, a smaller gun kick. No extra
	lights anywhere (the beam keeps its one light at the hit point).
]]

local BlasterFeel = {}

export type Tier = {
	MinLevel: number,
	BeamWidth: number, -- the glow beam's width at the muzzle (studs)
	CoreWidth: number, -- the white core
	Light: number, -- brightness of the beam's light at the hit point
	Flash: number, -- muzzle flash particle size (studs)
	FlashRate: number, -- muzzle flash particles per second while firing
	Sparks: number, -- sparks per hit pulse
	Chips: number, -- rock chips per chip pulse
	Energy: boolean, -- an energy stream along the beam + sparkles off the muzzle
	Swirl: number, -- muzzle sparkles per second (Energy tiers)
	Rings: boolean, -- shock rings at the hit
}

BlasterFeel.Tiers = {
	{
		MinLevel = 1,
		BeamWidth = 0.55,
		CoreWidth = 0.18,
		Light = 1.8,
		Flash = 0.9,
		FlashRate = 16,
		Sparks = 3,
		Chips = 1,
		Energy = false,
		Swirl = 0,
		Rings = false,
	},
	{
		MinLevel = 4,
		BeamWidth = 0.7,
		CoreWidth = 0.22,
		Light = 2.1,
		Flash = 1.1,
		FlashRate = 20,
		Sparks = 4,
		Chips = 2,
		Energy = false,
		Swirl = 0,
		Rings = false,
	},
	{
		MinLevel = 7,
		BeamWidth = 0.85,
		CoreWidth = 0.26,
		Light = 2.4,
		Flash = 1.35,
		FlashRate = 24,
		Sparks = 5,
		Chips = 2,
		Energy = true,
		Swirl = 14,
		Rings = false,
	},
	{
		MinLevel = 10,
		BeamWidth = 1.0,
		CoreWidth = 0.3,
		Light = 2.8,
		Flash = 1.6,
		FlashRate = 28,
		Sparks = 6,
		Chips = 3,
		Energy = true,
		Swirl = 20,
		Rings = true,
	},
} :: { Tier }

BlasterFeel.Pulse = 0.11 -- seconds between hit pulses
BlasterFeel.ChipEvery = 3 -- chips (and the thud) on every 3rd pulse
BlasterFeel.TickEvery = 2 -- the hit crackle on every 2nd pulse

BlasterFeel.Recoil = {
	StartKick = math.rad(0.7), -- camera pitch kick when the trigger goes down (radians)
	PulseKick = math.rad(0.12), -- camera pitch kick on every hit pulse
	GunBack = 0.14, -- studs the gun jumps back on a pulse (at the start: x2)
	GunLift = math.rad(5), -- the muzzle climbs this much on a pulse (at the start: x2)
	Recover = 16, -- how fast the gun settles back (per second)
}

BlasterFeel.Phone = {
	Particles = 0.5, -- x every particle count and rate
	CameraKick = 0, -- x the camera kick
	GunKick = 0.6, -- x the gun kick
}

-- Hard caps, whatever the tuning says (mobile budget).
BlasterFeel.Limits = {
	SparksPerPulse = 8,
	ChipsPerPulse = 3,
	FlashRate = 40,
	SwirlRate = 30,
	Rings = 1, -- per chip pulse
}

-- The tier for a blaster level (levels below 1 are level 1).
function BlasterFeel.tier(level: any): Tier
	local n = if type(level) == "number" and level == level then level else 1
	local best = BlasterFeel.Tiers[1]
	for _, tier in BlasterFeel.Tiers do
		if n >= tier.MinLevel then
			best = tier
		end
	end
	return best
end

export type Feel = {
	Level: number,
	Tier: Tier,
	Sparks: number,
	Chips: number,
	FlashRate: number,
	Swirl: number,
	Rings: number,
	CameraKick: number, -- x the Recoil camera kicks
	GunKick: number, -- x the Recoil gun kicks
}

--[[
	Everything BlasterFx needs for one blaster on this device: the tier's
	counts scaled for phones and capped by Limits (a count never drops to 0
	where the tier has some).
]]
function BlasterFeel.resolve(level: any, phone: boolean): Feel
	local tier = BlasterFeel.tier(level)
	local p = if phone then BlasterFeel.Phone.Particles else 1
	local lim = BlasterFeel.Limits
	local function scaled(n: number, cap: number): number
		if n <= 0 then
			return 0
		end
		return math.clamp(math.floor(n * p + 0.5), 1, cap)
	end
	return {
		Level = if type(level) == "number" and level == level then math.max(1, math.floor(level)) else 1,
		Tier = tier,
		Sparks = scaled(tier.Sparks, lim.SparksPerPulse),
		Chips = scaled(tier.Chips, lim.ChipsPerPulse),
		FlashRate = scaled(tier.FlashRate, lim.FlashRate),
		Swirl = scaled(tier.Swirl, lim.SwirlRate),
		Rings = if tier.Rings then lim.Rings else 0,
		CameraKick = if phone then BlasterFeel.Phone.CameraKick else 1,
		GunKick = if phone then BlasterFeel.Phone.GunKick else 1,
	}
end

--[[
	The kick left after `elapsed` seconds from a kick of 1 (exponential
	settle at Recoil.Recover): the gun's and the camera's recoil both follow it.
]]
function BlasterFeel.settle(elapsed: number): number
	if elapsed <= 0 then
		return 1
	end
	return math.exp(-elapsed * BlasterFeel.Recoil.Recover)
end

return BlasterFeel
