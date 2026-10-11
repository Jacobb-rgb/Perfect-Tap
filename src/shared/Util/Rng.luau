--[[
	Deterministic random numbers (xorshift32). The same seed gives the same
	numbers on the server, the client and in the Lune tools, which is how the
	server can re-check a cleaning minigame it never saw.
]]

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

local TWO32 = 4294967296

-- Small string hash (stays below 2^53 so it is exact in Luau numbers).
function Rng.hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % TWO32
	end
	return h
end

function Rng.new(seed: number | string): Rng
	local s: number
	if type(seed) == "string" then
		s = Rng.hash(seed)
	else
		s = math.floor(math.abs(seed :: number)) % TWO32
	end
	if s == 0 then
		s = 0x9E3779B9
	end
	local self = setmetatable({ state = s }, Rng)
	-- warm up so close seeds diverge
	for _ = 1, 4 do
		self:nextU32()
	end
	return self
end

function Rng.nextU32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1)
function Rng.next(self: Rng): number
	return self:nextU32() / TWO32
end

-- Float in [min, max)
function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- Integer in [min, max]
function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:next() * (max - min + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- weights: { [key]: weight }; returns a key. Keys are sorted so the result is
-- deterministic regardless of table iteration order.
function Rng.weighted(self: Rng, weights: { [string]: number }): string
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	table.sort(keys)
	local roll = self:next() * total
	for _, key in keys do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

return Rng
