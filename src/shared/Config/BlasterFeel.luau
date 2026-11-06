--[[
	How firing a blaster feels (client effects only, Effects/BlasterShots and
	Effects/BlasterFx): the shots, the muzzle flash, the sparks and rock chips
	at the hit, the hit sounds, the recoil, and the extra effects of the top
	levels. All tuning lives here.

	The blaster fires separate energy shots, never a beam (owner 2026-11-06):
	slow while the barrels start to turn, faster and faster as they spin up,
	a very fast minigun at full spin (Shots, shotRate, shotStep). Each shot
	flies on its own with a short bright trail and makes a small impact.

	Tiers by blaster level:
	  1-3   a clean thin shot, a small muzzle flash, sparks in the shot's glow
	  4-6   thicker, brighter, more sparks
	  7-9   + sparkles swirling off the muzzle, more chips
	  10    + shock rings at the hit, the thickest shot
	A hit "pulse" (at most every Pulse seconds while shots land on a rock you
	can mine) throws a hit crackle; every ChipEvery-th pulse also throws rock
	chips (in the rock's crust colour: the ores inside stay secret until
	cleaned) and a thud. The gun and the camera kick as shots leave, at most
	every Pulse seconds.

	Phones: half the particles, half the muzzle flashes, no camera kick, a
	smaller gun kick. One light per gun, at its hit point: steady while shots land
	(never a strobe: at most 3 large flashes a second, glareStep). Reduce motion: no
	muzzle or impact flashes, only soft sparks and a dim steady light.
]]

local BlasterFeel = {}

export type Tier = {
	MinLevel: number,
	ShotWidth: number, -- a shot's glow trail at its head (studs); the head is about as wide
	ShotCore: number, -- the white core of the trail
	Light: number, -- brightness of the light at the hit point, when a shot lands
	Flash: number, -- muzzle flash particle size per shot (studs)
	Sparks: number, -- sets the sparks per shot (a third of this, at least 1)
	Chips: number, -- rock chips per chip pulse
	Swirl: number, -- muzzle sparkles per second (the top tiers)
	Rings: boolean, -- shock rings at the hit
}

BlasterFeel.Tiers = {
	{
		MinLevel = 1,
		ShotWidth = 0.32,
		ShotCore = 0.1,
		Light = 1.8,
		Flash = 0.7,
		Sparks = 3,
		Chips = 1,
		Swirl = 0,
		Rings = false,
	},
	{
		MinLevel = 4,
		ShotWidth = 0.38,
		ShotCore = 0.12,
		Light = 2.1,
		Flash = 0.85,
		Sparks = 4,
		Chips = 2,
		Swirl = 0,
		Rings = false,
	},
	{
		MinLevel = 7,
		ShotWidth = 0.44,
		ShotCore = 0.14,
		Light = 2.4,
		Flash = 1.0,
		Sparks = 5,
		Chips = 2,
		Swirl = 14,
		Rings = false,
	},
	{
		MinLevel = 10,
		ShotWidth = 0.5,
		ShotCore = 0.16,
		Light = 2.8,
		Flash = 1.2,
		Sparks = 6,
		Chips = 3,
		Swirl = 20,
		Rings = true,
	},
} :: { Tier }

BlasterFeel.Shots = {
	SlowRate = 4, -- shots a second when the barrels start to turn
	FastRate = 24, -- ... at full spin
	OtherRate = 12, -- the top rate of other players' guns (their shots only look, a busy mine stays light)
	ReducedRate = 8, -- the top rate with Reduce motion
	SpinUp = 2, -- seconds from SlowRate to FastRate (the barrels spin up with it: Effects/BarrelSpin)
	SpinDown = 0.9, -- seconds for the barrels to stop
	Barrels = 6, -- each shot leaves from the next barrel (a full spin = FastRate shots)
	Spiral = 0.32, -- how far off the barrels' axis a shot starts (studs)
	Speed = 80, -- studs a second
	Trail = 2, -- how long a shot's trail is (studs)
	Pool = 48, -- shots in the air at most, every gun together
	PhonePool = 24,
	Reserve = 12, -- ... other players' guns leave this many for yours (your longest stream)
	MaxPerFrame = 3, -- a slow frame fires at most this many
	SoundGap = 0.055, -- seconds between shot sounds at least
	Guns = 12, -- guns firing at most (you and the others nearby)
	LightLevel = 0.85, -- the hit light while shots land (x the tier's Light); it holds steady, no strobe
	ReducedLight = 0.3, -- ... with Reduce motion
	LightUp = 0.15, -- seconds to come up
	LightDown = 0.3, -- seconds to go out after the last shot
	LightHold = 0.3, -- it counts as "shots landing" this long after each (the slowest gap is 0.25 s)
}

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
	SparksPerShot = 2,
	ChipsPerPulse = 3,
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
	Sparks: number, -- per shot that lands
	Chips: number,
	FlashEvery: number, -- a muzzle flash on every n-th shot
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
		Sparks = scaled(tier.Sparks / 3, lim.SparksPerShot),
		Chips = scaled(tier.Chips, lim.ChipsPerPulse),
		FlashEvery = if phone then 2 else 1,
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

-- Shots a second at `spin` (0 = the barrels start to turn, 1 = full spin), up to `top` (default FastRate).
function BlasterFeel.shotRate(spin: number, top: number?): number
	local shots = BlasterFeel.Shots
	local rate = shots.SlowRate + (shots.FastRate - shots.SlowRate) * math.clamp(spin, 0, 1)
	return math.min(rate, top or shots.FastRate)
end

--[[
	One frame of a gun: (spin, due) -> (spin, due, shots to fire now). `due`
	counts toward the next shot; a gun that stops firing is due again at once,
	so the trigger going down always fires right away. Starts at spin 0, due 1.
]]
function BlasterFeel.shotStep(spin: number, due: number, dt: number, on: boolean, top: number?): (number, number, number)
	local shots = BlasterFeel.Shots
	if not on then
		return math.max(0, spin - dt / shots.SpinDown), 1, 0
	end
	local nextSpin = math.min(1, spin + dt / shots.SpinUp)
	local total = due + BlasterFeel.shotRate(nextSpin, top) * dt
	local count = math.floor(total)
	return nextSpin, total - count, math.min(count, shots.MaxPerFrame)
end

-- The hit light next frame: toward `level` while shots land (lit), out after the last one. Smooth, no pulse.
function BlasterFeel.glareStep(glare: number, dt: number, lit: boolean, level: number): number
	local shots = BlasterFeel.Shots
	if lit then
		if glare > level then
			return math.max(level, glare - dt / shots.LightDown)
		end
		return math.min(level, glare + dt / shots.LightUp)
	end
	return math.max(0, glare - dt / shots.LightDown)
end

-- The barrels' full speed (radians a second): one barrel goes by for every shot at FastRate.
function BlasterFeel.barrelSpeed(): number
	local shots = BlasterFeel.Shots
	return shots.FastRate / shots.Barrels * math.pi * 2
end

return BlasterFeel
