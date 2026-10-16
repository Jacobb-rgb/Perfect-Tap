--[[
	Number formatting for UI.
	- commas: 1234 -> "1,234"
	- big: 999 -> "999", 1234 -> "1.23K", 45600000 -> "45.6M", up to Dc (1e33),
	  then scientific ("1.2e36"). Three significant digits, trailing zeros cut.
	- money: "$1.23K"; perSecond: "+$1.3K/s"
	- short: kept for older callers (same as big from 10,000 up)
]]

local Format = {}

function Format.commas(n: number): string
	local negative = n < 0
	local text = tostring(math.floor(math.abs(n)))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return (if negative then "-" else "") .. result
end

-- Suffix for each power of 1000 (index 1 = thousand).
Format.Suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(text: string): string
	if text:find("%.") then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text
end

-- Three significant digits: 1.23 / 12.3 / 123
local function sig3(value: number): string
	local abs = math.abs(value)
	local text
	if abs >= 100 then
		text = string.format("%.0f", value)
	elseif abs >= 10 then
		text = string.format("%.1f", value)
	else
		text = string.format("%.2f", value)
	end
	return trim(text)
end

function Format.big(n: number): string
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	if n == math.huge or n == -math.huge then
		return if n > 0 then "∞" else "-∞"
	end
	local abs = math.abs(n)
	if abs < 1000 then
		-- whole numbers, or one decimal for small fractional amounts (0.5/s)
		if abs < 10 and math.floor(abs) ~= abs then
			return trim(string.format("%.1f", n))
		end
		local whole = if n >= 0 then math.floor(n) else math.ceil(n)
		return tostring(whole)
	end
	local power = math.floor(math.log10(abs) / 3)
	if power > #Format.Suffixes then
		local mantissa, exponent = string.format("%.2e", n):match("^(.-)e([%+%-]%d+)$")
		return trim(mantissa or "0") .. "e" .. tostring(tonumber(exponent) or 0)
	end
	local value = n / 1000 ^ power
	-- rounding can push 999.95 up to 1000: move to the next suffix
	if math.abs(value) >= 999.5 and power < #Format.Suffixes then
		power += 1
		value = n / 1000 ^ power
	end
	return sig3(value) .. Format.Suffixes[power]
end

function Format.money(n: number): string
	if type(n) == "number" and n < 0 then
		return "-$" .. Format.big(-n)
	end
	return "$" .. Format.big(n)
end

function Format.perSecond(n: number): string
	return "+" .. Format.money(n) .. "/s"
end

-- Older callers: commas below 10,000, then like big.
function Format.short(n: number): string
	if math.abs(n) < 1e4 then
		return Format.commas(n)
	end
	return Format.big(n)
end

function Format.seconds(s: number): string
	s = math.max(0, math.floor(s))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%d:%02d", m, sec)
end

return Format
