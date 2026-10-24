--[[
	PowerLogic: pure power-network maths (docs/plans/MACHINES_GAME_PLAN.md
	"Power", MachineData.PowerRules). No Roblox services: PowerService (the
	server), PowerController (the client's cables) and the Lune tests all
	run it.

	Owner's rules: power goes through cables and poles; too little power
	slows machines down, it never stops them.

	- Poles (MachineData IsPole) link when the Chebyshev distance between
	  their cells is at most PoleLink. Linked poles form one network.
	- A generator (PowerOut > 0) or a machine (Power > 0) is on a network
	  when one of its footprint cells is within PoleReach (Chebyshev) of one
	  of the network's poles. It hangs on ONE pole, the nearest (fewest
	  cells, then the shortest straight line between the pole's cell and the
	  footprint centre, then the first pole in cell order), so a machine in
	  reach of two networks that are not linked joins the nearest pole's.
	- Per network: Supply = the sum of MachineData.powerOut(generator,
	  its type's Speed level), Demand = the sum of the machines' Power.
	- A machine runs at MachineData.powerSpeed(Supply, Demand) on a network
	  with Supply > 0 (Powered), otherwise at PowerRules.UnpoweredSpeed.
	  Machines without Power run at 1.
	- Cables: every pole lists the poles it links to (the shortest links
	  that join the network, a minimum spanning tree of the in-range pairs,
	  so a network is a tidy line of cables, not a web; it joins exactly the
	  same poles as every in-range pair would) and the generators and
	  machines it feeds (each hangs on one pole, so each gets one cable).

	Everything is deterministic: poles and machines are taken in cell order
	(Z, then X, then the input index) whatever order the entries come in. A
	network's id is the cell "x,z" of its first pole in that order, so it
	stays the same while poles elsewhere come and go.

	Attribute encoding (PowerService writes it, PowerController reads it):
	a list of cells is "x,z;x,z;..." (encodeCells / decodeCells), the cell
	of a machine is its entry's min corner (X, Z = the model's GridX / GridZ
	attributes).
]]

local MachineData = require(script.Parent.Parent.Config.MachineData)
local Grid = require(script.Parent.Grid)

local PowerLogic = {}

export type Entry = { Id: string, X: number, Z: number, R: number }
export type Kind = "Pole" | "Generator" | "Machine" | "Other"

-- One result per valid input entry (by input index).
export type MachineResult = {
	Kind: Kind,
	Speed: number, -- job speed multiplier, 0..1 (1 = full speed; always 1 for kinds other than "Machine")
	Powered: boolean, -- "Machine": on a network whose Supply > 0
	Network: string?, -- the network id (nil = in reach of no pole)
	Pole: number?, -- input index of the pole it hangs on (generators and machines)
	PowerOut: number, -- "Generator": power it makes at its Speed level (0 otherwise)
	Power: number, -- "Machine": power it needs (0 otherwise)
}

-- One result per pole (by input index).
export type PoleResult = {
	Network: string,
	Links: { number }, -- input indexes of the poles it has a cable to (cell order)
	Feeds: { number }, -- input indexes of the generators and machines it feeds (cell order)
}

export type Network = {
	Id: string,
	Supply: number,
	Demand: number,
	Speed: number, -- the speed of its machines
	Powered: boolean, -- Supply > 0
	Poles: { number }, -- input indexes, cell order (the first one names the network)
	Members: { number }, -- generators and machines on it, cell order
}

export type Result = {
	Machines: { [number]: MachineResult },
	Poles: { [number]: PoleResult },
	Networks: { Network }, -- in the order of their first poles
	ByNetwork: { [string]: Network },
}

export type Cell = { X: number, Z: number }

-- Most cells decodeCells reads from one string (more is junk).
PowerLogic.MaxCells = 160

type Item = {
	Index: number,
	Id: string,
	Info: MachineData.Machine,
	X: number,
	Z: number,
	W: number,
	D: number,
	Kind: Kind,
}

-- Two poles in link range (indexes in the sorted pole list) and the squared length between them.
type Pair = { A: number, B: number, Length: number }

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v > -1e6 and v < 1e6
end

-- What part a machine type plays in power.
function PowerLogic.kindOf(info: MachineData.Machine?): Kind
	if not info then
		return "Other"
	elseif info.IsPole then
		return "Pole"
	elseif (info.PowerOut or 0) > 0 then
		return "Generator"
	elseif (info.Power or 0) > 0 then
		return "Machine"
	end
	return "Other"
end

-- Speed levels by machine id from data.MachineUpgrades ({ [id] = { Speed = n } }).
-- Anything broken counts as level 0 (MachineData.powerOut clamps the rest).
function PowerLogic.speedLevels(machineUpgrades: any): { [string]: number }
	local levels: { [string]: number } = {}
	if type(machineUpgrades) ~= "table" then
		return levels
	end
	for id, upgrade in machineUpgrades do
		if type(id) == "string" and type(upgrade) == "table" then
			local speed = upgrade.Speed
			if type(speed) == "number" and speed == speed then
				levels[id] = speed
			end
		end
	end
	return levels
end

-- Cells (Chebyshev) from the cell (px, pz) to the nearest cell of the
-- footprint x..x+w-1, z..z+d-1 (0 when the cell is inside it).
function PowerLogic.reach(px: number, pz: number, x: number, z: number, w: number, d: number): number
	local dx = math.max(x - px, 0, px - (x + w - 1))
	local dz = math.max(z - pz, 0, pz - (z + d - 1))
	return math.max(dx, dz)
end

-- Chebyshev distance between two cells.
function PowerLogic.cells(ax: number, az: number, bx: number, bz: number): number
	return math.max(math.abs(ax - bx), math.abs(az - bz))
end

-- "x,z": a cell's key (network ids, attribute lists).
function PowerLogic.cellKey(x: number, z: number): string
	return `{x},{z}`
end

-- Rounds to 2 decimals (attributes).
function PowerLogic.round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

-- "x,z;x,z" for a list of cells ("" for none).
function PowerLogic.encodeCells(cells: { Cell }): string
	local parts = table.create(#cells)
	for i, cell in cells do
		parts[i] = PowerLogic.cellKey(cell.X, cell.Z)
	end
	return table.concat(parts, ";")
end

-- The cells of an encodeCells string; junk pairs are skipped, at most MaxCells.
function PowerLogic.decodeCells(text: any): { Cell }
	local list: { Cell } = {}
	if type(text) ~= "string" then
		return list
	end
	for x, z in string.gmatch(text, "(%-?%d+),(%-?%d+)") do
		if #list >= PowerLogic.MaxCells then
			break
		end
		local nx, nz = tonumber(x), tonumber(z)
		if nx and nz and isInt(nx) and isInt(nz) then
			table.insert(list, { X = nx, Z = nz })
		end
	end
	return list
end

local function byCell(a: Item, b: Item): boolean
	if a.Z ~= b.Z then
		return a.Z < b.Z
	elseif a.X ~= b.X then
		return a.X < b.X
	end
	return a.Index < b.Index
end

-- Squared straight-line distance from a pole's cell centre to a footprint centre (in cells).
local function lineSq(pole: Item, item: Item): number
	local dx = (pole.X + 0.5) - (item.X + item.W / 2)
	local dz = (pole.Z + 0.5) - (item.Z + item.D / 2)
	return dx * dx + dz * dz
end

--[[
	Works out the power networks of one plot. `entries` are placed machines
	({ Id, X, Z, R }, e.g. data.PlacedMachines); entries with an unknown Id
	or broken numbers get no result. `speedLevels` maps a machine id to its
	type's Speed level (PowerLogic.speedLevels(data.MachineUpgrades)).
	`machineUpgrades` (data.MachineUpgrades) gives a machine with tiers (the
	Furnace) the power of the player's tier (MachineData.info).
]]
function PowerLogic.compute(entries: { Entry }, speedLevels: { [string]: number }?, machineUpgrades: any?): Result
	local rules = MachineData.PowerRules
	local levels = speedLevels or {}
	local result: Result = { Machines = {}, Poles = {}, Networks = {}, ByNetwork = {} }

	local poles: { Item } = {}
	local users: { Item } = {} -- generators and machines
	for index, entry in entries do
		local listed = if type(entry) == "table" and type(entry.Id) == "string" then MachineData.ById[entry.Id] else nil
		local info = if listed then MachineData.info(listed.Id, MachineData.tierOf(machineUpgrades, listed.Id)) else nil
		if not info or not (isInt(entry.X) and isInt(entry.Z) and isInt(entry.R)) then
			continue
		end
		local w, d = Grid.footprint(entry.Id, entry.R)
		local kind: Kind = PowerLogic.kindOf(info)
		local item: Item = { Index = index, Id = entry.Id, Info = info, X = entry.X, Z = entry.Z, W = w, D = d, Kind = kind }
		result.Machines[index] = {
			Kind = kind,
			Speed = if kind == "Machine" then rules.UnpoweredSpeed else 1,
			Powered = false,
			Network = nil,
			Pole = nil,
			PowerOut = if kind == "Generator" then MachineData.powerOut(info, levels[entry.Id]) else 0,
			Power = if kind == "Machine" then info.Power or 0 else 0,
		}
		if kind == "Pole" then
			table.insert(poles, item)
		elseif kind == "Generator" or kind == "Machine" then
			table.insert(users, item)
		end
	end
	table.sort(poles, byCell)
	table.sort(users, byCell)

	-- pole links: Kruskal over the in-range pairs (shortest first)
	local parent: { number } = {}
	for i in poles do
		parent[i] = i
	end
	local function find(i: number): number
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local candidates: { Pair } = {}
	for a = 1, #poles do
		for b = a + 1, #poles do
			local pa, pb = poles[a], poles[b]
			if PowerLogic.cells(pa.X, pa.Z, pb.X, pb.Z) <= rules.PoleLink then
				local dx, dz = pa.X - pb.X, pa.Z - pb.Z
				table.insert(candidates, { A = a, B = b, Length = dx * dx + dz * dz })
			end
		end
	end
	table.sort(candidates, function(p: Pair, q: Pair): boolean
		if p.Length ~= q.Length then
			return p.Length < q.Length
		elseif p.A ~= q.A then
			return p.A < q.A
		end
		return p.B < q.B
	end)
	local links: { { number } } = {}
	for i in poles do
		links[i] = {}
	end
	for _, pair in candidates do
		local ra, rb = find(pair.A), find(pair.B)
		if ra ~= rb then
			-- the root stays the lower pole, so the first pole names the network
			if ra < rb then
				parent[rb] = ra
			else
				parent[ra] = rb
			end
			table.insert(links[pair.A], pair.B)
			table.insert(links[pair.B], pair.A)
		end
	end

	-- networks in the order of their first poles
	local networkOf: { [number]: Network } = {}
	for i, pole in poles do
		local root = find(i)
		local network = networkOf[root]
		if network == nil then
			local fresh: Network = {
				Id = PowerLogic.cellKey(poles[root].X, poles[root].Z),
				Supply = 0,
				Demand = 0,
				Speed = rules.UnpoweredSpeed,
				Powered = false,
				Poles = {},
				Members = {},
			}
			networkOf[root] = fresh
			table.insert(result.Networks, fresh)
			result.ByNetwork[fresh.Id] = fresh
			network = fresh
		end
		table.insert((network :: Network).Poles, pole.Index)
	end

	-- every generator and machine hangs on its nearest pole in reach
	local feeds: { { number } } = {}
	for i in poles do
		feeds[i] = {}
	end
	for _, item in users do
		local best: number? = nil
		local bestCells, bestLine = math.huge, math.huge
		for i, pole in poles do
			local cells = PowerLogic.reach(pole.X, pole.Z, item.X, item.Z, item.W, item.D)
			if cells <= rules.PoleReach then
				local line = lineSq(pole, item)
				if cells < bestCells or (cells == bestCells and line < bestLine) then
					best, bestCells, bestLine = i, cells, line
				end
			end
		end
		if best then
			local network = networkOf[find(best)]
			local res = result.Machines[item.Index]
			res.Network = network.Id
			res.Pole = poles[best].Index
			table.insert(feeds[best], item.Index)
			table.insert(network.Members, item.Index)
			if item.Kind == "Generator" then
				network.Supply += res.PowerOut
			else
				network.Demand += res.Power
			end
		end
	end

	-- speeds
	for _, network in result.Networks do
		network.Powered = network.Supply > 0
		network.Speed = if network.Powered then MachineData.powerSpeed(network.Supply, network.Demand) else rules.UnpoweredSpeed
	end
	for _, item in users do
		local res = result.Machines[item.Index]
		local id = res.Network
		local network = if id then result.ByNetwork[id] else nil
		if item.Kind == "Machine" and network and network.Powered then
			res.Powered = true
			res.Speed = network.Speed
		end
	end

	-- pole results (indexes in cell order: poles and users are sorted)
	for i, pole in poles do
		local linked: { number } = {}
		table.sort(links[i])
		for _, j in links[i] do
			table.insert(linked, poles[j].Index)
		end
		result.Poles[pole.Index] = {
			Network = networkOf[find(i)].Id,
			Links = linked,
			Feeds = feeds[i],
		}
	end
	return result
end

return PowerLogic
