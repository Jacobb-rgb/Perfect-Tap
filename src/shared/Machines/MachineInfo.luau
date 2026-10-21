--[[
	MachineInfo: what a machine is and does, in the player's words (build
	mode's info card and tray chips), plus the maths of build mode's power
	preview. Pure: only MachineData, Grid and PowerLogic, so the Lune tests
	run it and the client can call it every time the ghost moves.

	  describe(id)         name, category, size, Takes (from Accepts), Gives
	                       (Output / OutputCount), Seconds (Time), PowerNeed /
	                       PowerMake and their line, where the results come
	                       out, the Description (nil for an unknown id)
	  powerChip(id)        the tray card's chip: "PWR 10" needs, "+40 PWR" makes
	  unplaced(inventory)  machines waiting in data.MachineInventory (the
	                       BUILD tile's badge)
	  powerPreview(...)    what PowerLogic will say about a ghost at a spot:
	                       powered or not (the reason line), the poles a new
	                       pole would link and the machines it would feed
	  area(...)            the cells within `radius` of a cell, on the plot
	                       (a pole's reach and link squares)
	  segment(...)         a straight line between two cell points (the
	                       preview cables)
]]

local MachineData = require(script.Parent.Parent.Config.MachineData)
local Grid = require(script.Parent.Grid)
local PowerLogic = require(script.Parent.PowerLogic)

local MachineInfo = {}

export type Info = {
	Id: string,
	Name: string,
	Category: string,
	Width: number, -- cells along X at rotation 0
	Depth: number,
	Size: string, -- "2x2 cells"
	Takes: string?, -- "Clean ore, Crushed ore" (nil: it takes nothing in)
	Gives: string?, -- "2 Crushed ore" (nil: nothing comes out)
	Seconds: number?, -- one job, before upgrades (nil: no job)
	Flow: string?, -- "Clean ore -> 2 Crushed ore · 3 s"
	PowerNeed: number, -- MachineData Power (0 = none)
	PowerMake: number, -- MachineData PowerOut at Speed level 0
	PowerText: string?, -- "Needs 10 power: a pole within 3 cells, else 60% speed"
	OutputText: string?, -- "Results come out the FRONT (amber square)"
	Description: string,
}

export type Entry = PowerLogic.Entry

export type PowerState = "Powered" | "Slow" | "NoSupply" | "NoPole" | "Feeds" | "Links" | "Alone" | "None"

export type Preview = {
	Kind: PowerLogic.Kind,
	State: PowerState,
	Speed: number, -- the job speed a machine would run at (1 for every other kind)
	Text: string?, -- the reason line (nil: nothing to say)
	Good: boolean, -- green (true) or yellow
	Pole: Entry?, -- a machine / generator: the pole it would hang on
	Links: { Entry }, -- a pole: the poles it would have a cable to
	Feeds: { Entry }, -- a pole: the machines and generators it would feed
}

-- Item kinds in processing order, and their names (one / many).
MachineInfo.KindOrder = { "Raw", "Clean", "Crushed", "Ingot", "Alloy", "Gear", "Relic" }
MachineInfo.Kinds = {
	Raw = { One = "Dirty ore", Many = "Dirty ore" },
	Clean = { One = "Clean ore", Many = "Clean ore" },
	Crushed = { One = "Crushed ore", Many = "Crushed ore" },
	Ingot = { One = "Ingot", Many = "Ingots" },
	Alloy = { One = "Alloy", Many = "Alloys" },
	Gear = { One = "Gear", Many = "Gear" },
	Relic = { One = "Dusty relic", Many = "Dusty relics" },
} :: { [string]: { One: string, Many: string } }

-- A machine that takes this many kinds or more "takes any item".
MachineInfo.AnyKinds = 4
MachineInfo.AnyText = "Any item"

-- What machines without an Output give (their behaviour does the work).
MachineInfo.GivesText = {
	CleaningStation = "Clean ore (you spray it)",
	IronBox = "Kept ore to your pen, the rest out the front",
	Splitter = "Left, then right",
	Sorter = "Your rarity and better right, the rest left",
	SellBox = "Coins",
	RestorationTable = "An artifact for your collection",
	RobotArm = "Into the machine in front",
} :: { [string]: string }

-- What machines without Accepts take.
MachineInfo.TakesText = {
	RobotArm = "Finished items from the machine behind",
} :: { [string]: string }

MachineInfo.FrontText = "Results come out the FRONT (amber square)"
MachineInfo.SidesText = "Results come out the LEFT and RIGHT sides"
MachineInfo.BeltText = "Items ride the way the arrows point"
MachineInfo.TrayText = "Clean ore lands on its tray"
MachineInfo.ArmText = "Put its FRONT against the machine to fill"
MachineInfo.NoPowerText = "No power needed"

-- "6", "2.5", "18.8" (seconds, power: one decimal, none when whole).
function MachineInfo.num(n: number): string
	if n == math.floor(n) then
		return tostring(math.floor(n))
	end
	local text = string.format("%.1f", n)
	return if string.sub(text, -2) == ".0" then string.sub(text, 1, -3) else text
end

local function percent(speed: number): number
	return math.floor(speed * 100 + 0.5)
end

local function takesOf(machine: MachineData.Machine): string?
	local fixed = MachineInfo.TakesText[machine.Id]
	if fixed then
		return fixed
	end
	local accepts = machine.Accepts
	if not accepts then
		return nil
	end
	local names: { string } = {}
	for _, kind in MachineInfo.KindOrder do
		local entry = MachineInfo.Kinds[kind]
		if accepts[kind] and entry then
			table.insert(names, entry.Many)
		end
	end
	if #names == 0 then
		return nil
	elseif #names >= MachineInfo.AnyKinds then
		return MachineInfo.AnyText
	end
	local text = table.concat(names, ", ")
	local inputs = machine.Inputs or 1
	return if inputs > 1 then `{inputs} {text}` else text
end

local function givesOf(machine: MachineData.Machine): string?
	local output = machine.Output
	local kind = if output then MachineInfo.Kinds[output] else nil
	if kind then
		local count = machine.OutputCount or 1
		return if count > 1 then `{count} {kind.Many}` else kind.One
	end
	return MachineInfo.GivesText[machine.Id]
end

local function powerTextOf(machine: MachineData.Machine): string?
	local rules = MachineData.PowerRules
	local kind = PowerLogic.kindOf(machine)
	if kind == "Machine" then
		return `Needs {machine.Power} power: a pole within {rules.PoleReach} cells, else {percent(rules.UnpoweredSpeed)}% speed`
	elseif kind == "Generator" then
		return `Makes {machine.PowerOut} power: a pole within {rules.PoleReach} cells carries it`
	elseif kind == "Pole" then
		return `Links poles within {rules.PoleLink} cells, powers machines within {rules.PoleReach}`
	elseif machine.Accepts or machine.Time then
		return MachineInfo.NoPowerText
	end
	return nil
end

local function outputTextOf(machine: MachineData.Machine): string?
	if Grid.outputLocal(machine.Id) then
		return MachineInfo.FrontText
	elseif machine.SideOutputs then
		return MachineInfo.SidesText
	elseif machine.IsConveyor then
		return MachineInfo.BeltText
	elseif machine.Id == "CleaningStation" then
		return MachineInfo.TrayText
	elseif machine.Behaviour == "RobotArm" then
		return MachineInfo.ArmText
	end
	return nil
end

-- Everything the info card says about a machine type (nil for an unknown id).
function MachineInfo.describe(id: any): Info?
	local machine = if type(id) == "string" then MachineData.ById[id] else nil
	if not machine then
		return nil
	end
	local takes, gives = takesOf(machine), givesOf(machine)
	local seconds = if machine.Time and machine.Time > 0 then machine.Time else nil
	local flow: string? = nil
	if takes and gives then
		flow = `{takes} -> {gives}`
		if seconds then
			flow = `{flow} · {MachineInfo.num(seconds)} s`
			if (machine.Batch or 1) > 1 then
				flow = `{flow} ({machine.Batch} at once)`
			end
		end
	end
	local w, d = machine.Size[1], machine.Size[2]
	return {
		Id = machine.Id,
		Name = machine.Name,
		Category = machine.Category,
		Width = w,
		Depth = d,
		Size = `{w}x{d} cells`,
		Takes = takes,
		Gives = gives,
		Seconds = seconds,
		Flow = flow,
		PowerNeed = machine.Power or 0,
		PowerMake = machine.PowerOut or 0,
		PowerText = powerTextOf(machine),
		OutputText = outputTextOf(machine),
		Description = machine.Description,
	}
end

-- The tray card's power chip in words (no emoji, owner 2026-10-21): "PWR 10"
-- (needs), "+40 PWR" (makes), "PWR" (a pole), nil (no part in power).
function MachineInfo.powerChip(id: any): string?
	local machine = if type(id) == "string" then MachineData.ById[id] else nil
	local kind = PowerLogic.kindOf(machine)
	if not machine or kind == "Other" then
		return nil
	elseif kind == "Machine" then
		return `PWR {machine.Power}`
	elseif kind == "Generator" then
		return `+{machine.PowerOut} PWR`
	end
	return "PWR"
end

-- How many machines wait to be placed (data.MachineInventory: known ids,
-- whole positive counts; anything broken counts 0).
function MachineInfo.unplaced(inventory: any): number
	if type(inventory) ~= "table" then
		return 0
	end
	local total = 0
	for id, count in inventory do
		if type(id) == "string" and MachineData.ById[id] and type(count) == "number" and count == count and count > 0 then
			total += math.floor(math.min(count, MachineData.MaxInventory))
		end
	end
	return total
end

-- The cells within `radius` (Chebyshev) of the cell (x, z), clamped to a
-- plot of `cells` x `cells`: x0, z0, x1, z1 (inclusive).
function MachineInfo.area(x: number, z: number, radius: number, cells: number): (number, number, number, number)
	return math.max(0, x - radius), math.max(0, z - radius), math.min(cells - 1, x + radius), math.min(cells - 1, z + radius)
end

-- A straight line between two points in cell units (a cell's centre is
-- x + 0.5): its middle, its length and the turn around Y that points a
-- part's local Z along it (CFrame.Angles(0, yaw, 0)).
function MachineInfo.segment(ax: number, az: number, bx: number, bz: number): (number, number, number, number)
	local dx, dz = bx - ax, bz - az
	return (ax + bx) / 2, (az + bz) / 2, math.sqrt(dx * dx + dz * dz), math.atan2(dx, dz)
end

local function plural(n: number, one: string, many: string): string
	return `{n} {if n == 1 then one else many}`
end

--[[
	What the power network will say about `ghost` ({ Id, X, Z, R }) placed
	next to `entries` (the plot's layout without the machine being moved).
	`machineUpgrades` is data.MachineUpgrades (generators make more per
	Speed level). Same rules as PowerService (PowerLogic.compute).
]]
function MachineInfo.powerPreview(entries: { Entry }, ghost: Entry, machineUpgrades: any?): Preview
	local machine = MachineData.ById[ghost.Id]
	local kind: PowerLogic.Kind = PowerLogic.kindOf(machine)
	local preview: Preview = { Kind = kind, State = "None", Speed = 1, Text = nil, Good = true, Pole = nil, Links = {}, Feeds = {} }
	if kind == "Other" then
		return preview
	end
	local list: { Entry } = table.clone(entries)
	table.insert(list, ghost)
	local me = #list
	local result = PowerLogic.compute(list, PowerLogic.speedLevels(machineUpgrades))
	local rules = MachineData.PowerRules
	local mine = result.Machines[me]
	if not mine then
		return preview
	end
	if kind == "Pole" then
		local pole = result.Poles[me]
		local machines, generators = 0, 0
		if pole then
			for _, index in pole.Links do
				table.insert(preview.Links, list[index])
			end
			for _, index in pole.Feeds do
				table.insert(preview.Feeds, list[index])
				local fed = result.Machines[index]
				if fed and fed.Kind == "Generator" then
					generators += 1
				else
					machines += 1
				end
			end
		end
		local network = if pole then result.ByNetwork[pole.Network] else nil
		local parts: { string } = {}
		if #preview.Links > 0 then
			table.insert(parts, "links " .. plural(#preview.Links, "pole", "poles"))
		end
		if generators > 0 then
			table.insert(parts, "takes " .. plural(generators, "generator", "generators"))
		end
		if machines > 0 then
			table.insert(parts, "powers " .. plural(machines, "machine", "machines"))
		end
		if #parts == 0 then
			preview.State = "Alone"
			preview.Good = false
			preview.Text = `Nothing in reach yet: poles link within {rules.PoleLink} cells`
		else
			preview.State = "Links"
			local text = table.concat(parts, " · ")
			text = string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
			if network and not network.Powered and machines > 0 then
				preview.Good = false
				text ..= " · no generator yet"
			end
			preview.Text = text
		end
		return preview
	end
	local poleIndex = mine.Pole
	preview.Pole = if poleIndex then list[poleIndex] else nil
	if kind == "Generator" then
		if mine.Network then
			preview.State = "Feeds"
			preview.Text = `Makes {MachineInfo.num(mine.PowerOut)} power for this network`
		else
			preview.State = "NoPole"
			preview.Good = false
			preview.Text = "No pole in reach: its power goes nowhere"
		end
		return preview
	end
	preview.Speed = mine.Speed
	if not mine.Network then
		preview.State = "NoPole"
		preview.Good = false
		preview.Text = `No pole in reach: runs at {percent(mine.Speed)}%`
	elseif not mine.Powered then
		preview.State = "NoSupply"
		preview.Good = false
		preview.Text = `No generator on that pole: runs at {percent(mine.Speed)}%`
	elseif mine.Speed < 1 then
		preview.State = "Slow"
		preview.Good = false
		preview.Text = `Powered, but not enough: runs at {percent(mine.Speed)}%`
	else
		preview.State = "Powered"
		preview.Text = "Powered"
	end
	return preview
end

return MachineInfo
