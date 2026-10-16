--[[
	Lobby budget report: builds the world and prints parts and lights per
	lobby package, per legacy town piece and for everything else inside the
	lobby area, against the budgets in LobbyLayout.Budget.

	  lune run tools/lune/lobby_stats.luau

	(tests/Lobby.spec.luau enforces the same budgets; this tool shows where
	the parts go.)
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")
Loader.init(process.cwd)

local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

local game = roblox.Instance.new("DataModel")
local map = WorldBuilder.build(game:GetService("Workspace"))

type Row = { parts: number, lobbyParts: number, lights: number, lobbyLights: number }

local rows: { [string]: Row } = {}
local order: { string } = {}

local function row(key: string): Row
	local r = rows[key]
	if not r then
		r = { parts = 0, lobbyParts = 0, lights = 0, lobbyLights = 0 }
		rows[key] = r
		table.insert(order, key)
	end
	return r
end

-- Group: Emberfall.Lobby.<Package> -> "Lobby/<Package>", other Emberfall
-- children -> "Town/<name>", everything else -> "<top>/<child>".
local function groupOf(d: any): string
	local chain = {}
	local node = d
	while node and node ~= map do
		table.insert(chain, 1, node.Name)
		node = node.Parent
	end
	if chain[1] == "Emberfall" then
		if chain[2] == "Lobby" and chain[3] then
			return "Lobby/" .. chain[3]
		end
		return "Town/" .. (chain[2] or "?")
	end
	return chain[1] .. (if chain[2] and #chain > 2 then "/" .. chain[2] else "")
end

local total, lobbyParts, lobbyLights = 0, 0, 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		local r = row(groupOf(d))
		r.parts += 1
		total += 1
		if LobbyLayout.inArea(d.CFrame.Position) then
			r.lobbyParts += 1
			lobbyParts += 1
		end
	elseif (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Parent and d.Parent:IsA("BasePart") then
		local r = row(groupOf(d.Parent))
		r.lights += 1
		if LobbyLayout.inArea(d.Parent.CFrame.Position) then
			r.lobbyLights += 1
			lobbyLights += 1
		end
	end
end

table.sort(order, function(a, b)
	return rows[a].lobbyParts > rows[b].lobbyParts or (rows[a].lobbyParts == rows[b].lobbyParts and a < b)
end)

local budget = LobbyLayout.Budget
print(
	string.format(
		"%-28s %7s %7s %7s %7s   %s",
		"group",
		"parts",
		"inLobby",
		"lights",
		"inLobby",
		"budget: parts (in lobby) / lights (in lobby)"
	)
)
for _, key in order do
	local r = rows[key]
	local note = ""
	local pkg = string.match(key, "^Lobby/(.+)$")
	if pkg and budget.Packages[pkg] then
		local b = budget.Packages[pkg]
		local over = r.parts > b.Parts or r.lobbyParts > b.LobbyParts or r.lights > b.Lights or r.lobbyLights > b.LobbyLights
		note = string.format("%d (%d) / %d (%d)%s", b.Parts, b.LobbyParts, b.Lights, b.LobbyLights, if over then "  OVER BUDGET" else "")
	end
	print(string.format("%-28s %7d %7d %7d %7d   %s", key, r.parts, r.lobbyParts, r.lights, r.lobbyLights, note))
end
print(string.rep("-", 72))
print(
	string.format(
		"map parts %d / %d   lobby parts %d / %d   lobby lights %d / %d",
		total,
		budget.MapParts,
		lobbyParts,
		budget.LobbyParts,
		lobbyLights,
		budget.LobbyLights
	)
)

-- `lune run tools/lune/lobby_stats.luau pieces`: parts and lights per piece
-- (each child model of a lobby package, plus one plot and its yard) for the
-- per-piece budgets in the package specs.
if table.find(process.args, "pieces") then
	print("")
	print(string.format("%-36s %7s %7s", "piece", "parts", "lights"))
	local function count(m: any): (number, number)
		local p, l = 0, 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				p += 1
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				l += 1
			end
		end
		return p, l
	end
	local lobby = map.Emberfall:FindFirstChild("Lobby")
	for _, name in LobbyLayout.Packages do
		local pkg = lobby and lobby:FindFirstChild(name)
		if pkg then
			for _, child in pkg:GetChildren() do
				local p, l = count(child)
				print(string.format("%-36s %7d %7d", name .. "/" .. child.Name, p, l))
			end
		end
	end
	local plot = map.Plots:FindFirstChild("Plot_1")
	if plot then
		local p, l = count(plot)
		local yp = count(plot.Yard)
		print(string.format("%-36s %7d %7d   (yard %d)", "Plots/Plot_1", p, l, yp))
	end
end
