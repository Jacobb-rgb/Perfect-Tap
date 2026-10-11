--[[
	Number formatting for UI: 1234 -> "1,234", 1250000 -> "1.25M".
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

local SUFFIXES = {
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
	{ Value = 1e4, Suffix = "K" },
}

function Format.short(n: number): string
	local abs = math.abs(n)
	for _, pair in SUFFIXES do
		if abs >= pair.Value then
			local value = n / pair.Value
			local text = string.format(if math.abs(value) >= 100 then "%.0f" else "%.1f", value)
			text = text:gsub("%.0$", "")
			return text .. pair.Suffix
		end
	end
	return Format.commas(n)
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
