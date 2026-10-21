--[[
	The 5 leaderboards in the Hall of Fame (step 7; LEVEL owner 2026-10-21).
	Each lobby board is a BasePart named Board1..Board5 (tag Leaderboard,
	attribute Board = 1..5).

	  Board 1  MONEY / SEC    podium income per second (PodiumService.incomeOf)
	  Board 2  TOTAL EARNED   data.TotalEarned
	  Board 3  ARTIFACTS      data.Stats.ArtifactsFound (every find)
	  Board 4  HOURS PLAYED   data.Stats.PlaySeconds
	  Board 5  LEVEL          data.Level.Level (LevelService; never reset)

	- One OrderedDataStore per board (Store, versioned: bump the _vN suffix to
	  start a board fresh). LeaderboardService writes each player's values at
	  most every 120 s (LeaderboardService.WriteSeconds) and once more when
	  they leave, only the boards whose encoded value changed: the growing
	  boards (TotalEarned, Artifacts, HoursPlayed) with UpdateAsync keeping
	  the bigger number, MoneyPerSec with SetAsync (at least once per
	  session). Every RefreshSeconds it reads the top TopCount of each board
	  (GetSortedAsync descending). Studio never writes (it only reads).
	- Hidden: UserIds that never show on a board and are never written
	  (cheaters, banned users); LeaderboardService.removeUser(userId) deletes
	  a user's entries from all five stores (the command bar; RTBF too) and
	  hides them at runtime on every server (no deploy needed).
	- Where they show: the lobby boards (Hall, 5.4 x 5 studs, five rank rows)
	  show the top BoardRows (5) so the rows stay readable on phones from the
	  plaza; the side menu's Leaderboards panel shows the top TopCount (10).
	  Both end with YOUR line: your live value and your rank: "#4" when you
	  are in the rows that were read, "~#4" when your live value would place
	  you there before your next write lands (LeaderboardView.estimateRank),
	  else "#11+" (OrderedDataStores don't give a rank below the page read).
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
	Index: number, -- 1..5 (the lobby part's Board attribute)
	Id: string,
	Title: string,
	Store: string, -- OrderedDataStore name
	Encoding: Encoding,
	Scale: number?, -- Int boards: stored = floor(value / Scale)
	Source: string, -- where the value comes from (see the header)
}

local LeaderboardConfig = {}

LeaderboardConfig.RefreshSeconds = 60
LeaderboardConfig.TopCount = 10 -- read per board, shown in the side menu panel
LeaderboardConfig.BoardRows = 5 -- rows on each lobby board (readable on phones)
LeaderboardConfig.Tag = "Leaderboard"
LeaderboardConfig.LogScale = 1e12
LeaderboardConfig.MaxStored = 2 ^ 53 - 1
-- UserIds kept off every board (never shown, never written): cheaters and
-- banned users. LeaderboardService.removeUser deletes their entries and
-- hides them at runtime on every server (this table is the in-code list).
LeaderboardConfig.Hidden = {} :: { [number]: boolean }

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
	{
		Index = 5,
		Id = "Level",
		Title = "LEVEL",
		Store = "TF_LB_Level_v1",
		Encoding = "Int",
		Scale = 1,
		Source = "Level.Level",
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
	elseif boardId == "Level" then
		return "LV " .. Format.commas(math.floor(value))
	end
	return if value < 1e4 then Format.commas(value) else Format.big(value)
end

return LeaderboardConfig
