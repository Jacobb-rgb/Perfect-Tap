--[[
	EmoteProps: the Gem Juggle's three gems (client-only looks).

	  juggle(u, i, rightPalm, leftPalm) -> Vector3   where gem i (1..3) is u
	        seconds into the juggling loop: a three-gem cascade, a throw
	        every Throw seconds from the right and the left hand in turn
	        (the emote's toss keys), each gem Flight seconds in the air on an
	        arc of Height studs, then in the catching hand until its next throw
	  newPool(make, maxOwners) a pool of gem sets: acquire(owner) gives that
	        character its GemCount parts (made once, reused; nil when
	        maxOwners characters already juggle), release(owner) parks them
	        (Parent = nil) for the next juggler. At most GemCount parts per
	        juggling character, never more than GemCount * maxOwners parts.
	  makeGem(i)  one small Neon gem in an ore's glow (anchored, no collision,
	        no queries, no shadow)
]]

local OreData = require(script.Parent.Parent.Config.OreData)

local EmoteProps = {}

EmoteProps.GemCount = 3
EmoteProps.Throw = 0.3
EmoteProps.Flight = 0.6
EmoteProps.Height = 3.2
EmoteProps.Size = 0.42
EmoteProps.MaxJugglers = 6 -- characters juggling with gems at once (the rest juggle empty-handed)
EmoteProps.GemOres = { "Heartstone", "Jade", "Sapphire" } -- the ore palette: their glow colours

local FALLBACK = { Color3.fromRGB(255, 77, 109), Color3.fromRGB(77, 255, 176), Color3.fromRGB(90, 168, 255) }

function EmoteProps.gemColor(i: number): Color3
	local ore = OreData.ById[EmoteProps.GemOres[i] or ""]
	return if ore then ore.Glow else FALLBACK[i] or FALLBACK[1]
end

function EmoteProps.juggle(u: number, i: number, rightPalm: Vector3, leftPalm: Vector3): Vector3
	local count = EmoteProps.GemCount
	local throw = EmoteProps.Throw
	local cycle = count * throw
	local s = u - (i - 1) * throw
	if s < 0 then
		-- waiting in the hand that throws it first
		return if (i - 1) % 2 == 0 then rightPalm else leftPalm
	end
	local k = math.floor(s / cycle)
	local phase = s - k * cycle
	local fromRight = ((i - 1) + count * k) % 2 == 0
	local a = if fromRight then rightPalm else leftPalm
	local b = if fromRight then leftPalm else rightPalm
	if phase < EmoteProps.Flight then
		local x = phase / EmoteProps.Flight
		return a:Lerp(b, x) + Vector3.new(0, EmoteProps.Height * 4 * x * (1 - x), 0)
	end
	return b
end

function EmoteProps.makeGem(i: number): BasePart
	local gem = Instance.new("Part")
	gem.Name = "JuggleGem" .. i
	gem.Size = Vector3.one * EmoteProps.Size
	gem.Material = Enum.Material.Neon
	gem.Color = EmoteProps.gemColor(i)
	gem.Anchored = true
	gem.CanCollide = false
	gem.CanQuery = false
	gem.CanTouch = false
	gem.CastShadow = false
	gem.Massless = true
	return gem
end

export type Pool = {
	acquire: (owner: any) -> { BasePart }?,
	release: (owner: any) -> (),
	active: () -> number, -- characters holding gems now
	parts: () -> number, -- parts ever made
}

function EmoteProps.newPool(make: (i: number) -> BasePart, maxOwners: number?): Pool
	local limit = maxOwners or EmoteProps.MaxJugglers
	local spare: { { BasePart } } = {}
	local held: { [any]: { BasePart } } = {}
	local heldCount = 0
	local made = 0
	local pool = {}
	function pool.acquire(owner: any): { BasePart }?
		local current = held[owner]
		if current then
			return current
		end
		if heldCount >= limit then
			return nil
		end
		local set: { BasePart }
		local reused = table.remove(spare)
		if reused then
			set = reused
		else
			set = {}
			for i = 1, EmoteProps.GemCount do
				table.insert(set, make(i))
				made += 1
			end
		end
		held[owner] = set
		heldCount += 1
		return set
	end
	function pool.release(owner: any)
		local set = held[owner]
		if not set then
			return
		end
		held[owner] = nil
		heldCount -= 1
		for _, part in set do
			part.Parent = nil
		end
		table.insert(spare, set)
	end
	function pool.active(): number
		return heldCount
	end
	function pool.parts(): number
		return made
	end
	return pool :: any
end

return EmoteProps
