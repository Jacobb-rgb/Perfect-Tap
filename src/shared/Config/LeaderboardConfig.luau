--[[
	The 4 leaderboards in the Hall of Fame (step 7). Each lobby board is a
	BasePart named Board1..Board4 (tag Leaderboard, attribute Board = 1..4).

	  Board 1  MONEY / SEC    podium income per second (PodiumService.incomeOf)
	  Board 2  TOTAL EARNED   data.TotalEarned
	  Board 3  ARTIFACTS      data.Stats.ArtifactsFound (every find)
	  Board 4  HOURS PLAYED   data.Stats.PlaySeconds

	- One OrderedDataStore per board (Store, versioned: bump the _vN suffix to
	  start a board fresh). Every RefreshSeconds the server writes the online
	  players' values (SetAsync, only when the encoded value changed) and
	  reads the top TopCount (GetSortedAsync descending) for the board.
	- OrderedDataStore values must be whole numbers, and safely below 2^53 in
	  Luau, but money grows past Qi (1e18). So:
	    "Log" boards store floor(log10(1 + value) * LogScale): order-preserving
	          for every value >= 0, 1e300 still fits, and decode() gives the value
	          back within ~1e-11 of it (relative). The floor makes it a hair
	          low (25 -> 24.99999999994, 1e12 -> 999999999999), so decode
	          snaps a value that close onto a number with at most 6 significant
	          digits, or else onto a whole number (25, 1000, 1e12 and 3.2M
	          show as themselves; Format floors, so a hair low would show 24).
	    "Int" boards store floor(value / Scale), capped at MaxStored.
	  encode / decode / format below; the Lune tests check round-trips and order.
]]

local Format = require(script.Parent.Parent.Util.Format)

export type Encoding = "Log" | "Int"
export type Board = {
	Index: number, -- 1..4 (the lobby part's Board attribute)
	Id: string,
	Title: string,
	Store: string, -- OrderedDataStore name
	Encoding: Encoding,
	Scale: number?, -- Int boards: stored = floor(value / Scale)
	Source: string, -- where the value comes from (see the header)
}

local LeaderboardConfig = {}

LeaderboardConfig.RefreshSeconds = 60
LeaderboardConfig.TopCount = 10
LeaderboardConfig.Tag = "Leaderboard"
LeaderboardConfig.LogScale = 1e12
LeaderboardConfig.MaxStored = 2 ^ 53 - 1

LeaderboardConfig.Boards = {
	{
		Index = 1,
		Id = "MoneyPerSec",
		Title = "MONEY / SEC",
		Store = "TF_LB_MoneyPerSec_v1",
		Encoding = "Log",
		Source = "PodiumService.incomeOf",
	},
	{
		Index = 2,
		Id = "TotalEarned",
		Title = "TOTAL EARNED",
		Store = "TF_LB_TotalEarned_v1",
		Encoding = "Log",
		Source = "TotalEarned",
	},
	{
		Index = 3,
		Id = "Artifacts",
		Title = "ARTIFACTS",
		Store = "TF_LB_Artifacts_v1",
		Encoding = "Int",
		Scale = 1,
		Source = "Stats.ArtifactsFound",
	},
	{
		Index = 4,
		Id = "HoursPlayed",
		Title = "HOURS PLAYED",
		Store = "TF_LB_HoursPlayed_v1",
		Encoding = "Int",
		Scale = 60, -- stored in whole minutes; the value is seconds
		Source = "Stats.PlaySeconds",
	},
} :: { Board }

LeaderboardConfig.ById = {} :: { [string]: Board }
LeaderboardConfig.ByIndex = {} :: { [number]: Board }
for _, board in LeaderboardConfig.Boards do
	LeaderboardConfig.ById[board.Id] = board
	LeaderboardConfig.ByIndex[board.Index] = board
end

local function clean(value: any): number
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return 0
	end
	return math.min(value, 1e300)
end

-- The whole number to store for a board's value (>= 0, < 2^53).
function LeaderboardConfig.encode(boardId: string, value: any): number
	local board = LeaderboardConfig.ById[boardId]
	local v = clean(value)
	if not board or v == 0 then
		return 0
	end
	if board.Encoding == "Log" then
		-- values below ~2.3e-12 store 0, like 0 itself
		local stored = math.floor(math.log10(1 + v) * LeaderboardConfig.LogScale)
		return math.clamp(stored, 0, LeaderboardConfig.MaxStored)
	end
	local stored = math.floor(v / (board.Scale or 1))
	return math.clamp(stored, 0, LeaderboardConfig.MaxStored)
end

-- How close (relative) a decoded Log value must be to a whole number to snap onto it.
LeaderboardConfig.SnapTolerance = 1e-10 -- ~40x the encoding error

-- The value back from a stored number (Log: within ~1e-11 relative, snapped
-- onto a whole number that close; Int: the stored unit, e.g. whole minutes
-- as seconds).
function LeaderboardConfig.decode(boardId: string, stored: any): number
	local board = LeaderboardConfig.ById[boardId]
	if not board or type(stored) ~= "number" or stored ~= stored or stored <= 0 then
		return 0
	end
	if board.Encoding == "Log" then
		local v = 10 ^ (stored / LeaderboardConfig.LogScale) - 1
		local tolerance = LeaderboardConfig.SnapTolerance * math.max(1, v)
		if v > 0 then
			-- a number with at most 6 significant digits that close (1e12, 2.5e15)
			local digits = math.floor(math.log10(v)) - 5
			local nice
			if digits < 0 then
				local scale = 10 ^ -digits -- divide whole numbers: 700000 / 1e5 is exactly 7
				nice = math.floor(v * scale + 0.5) / scale
			else
				local step = 10 ^ digits
				nice = math.floor(v / step + 0.5) * step
			end
			if math.abs(v - nice) <= tolerance then
				return nice
			end
		end
		-- or a whole number that close (25, 1234567)
		local whole = math.floor(v + 0.5)
		if math.abs(v - whole) <= tolerance then
			return whole
		end
		return v
	end
	return math.floor(stored) * (board.Scale or 1)
end

-- Text for a decoded value on a board: "+$1.3K/s", "$4.5M", "1,234" or "12.5 h".
function LeaderboardConfig.format(boardId: string, value: number): string
	if boardId == "MoneyPerSec" then
		return Format.perSecond(value)
	elseif boardId == "TotalEarned" then
		return Format.money(value)
	elseif boardId == "HoursPlayed" then
		local hours = math.floor(value / 360) / 10
		if hours >= 1000 then
			return Format.big(math.floor(hours)) .. " h"
		end
		return string.format("%.1f h", hours)
	end
	return if value < 1e4 then Format.commas(value) else Format.big(value)
end

return LeaderboardConfig
