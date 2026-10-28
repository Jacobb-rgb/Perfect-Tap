--[[
	WeatherSway: the trees near the camera lean with the wind (Wind and Storm
	weather, WeatherConfig.TreeSway). Client only and capped: at most
	TreeSway.Max trees (Phone.TreeSway on phones) within TreeSway.Radius,
	each turned about the bottom of its bounding box (so it bends from the
	ground up) by WeatherLogic.sway, all its parts in one
	Workspace:BulkMoveTo. Every tree goes back to its exact place when it
	drops out of the nearest set or the wind stops (stop()).

	Trees are the map's Models named "Tree" (Props, Lobby/Flora): found by a
	walk of the Workspace's folders and models when the wind starts, spread
	over frames (TreeSway.ScanBudget seconds a frame, the clock looked at
	every TreeSway.ScanEvery children: no hitch on phones), and found again
	at a windy spell once the last search is TreeSway.ScanAge old (trees
	stream in and out). No Workspace-wide signals stay connected. A tree with unanchored parts or
	more than TreeSway.MaxParts parts is skipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeatherConfig = require(Shared.Config.WeatherConfig)
local WeatherLogic = require(Shared.Weather.WeatherLogic)

local WeatherSway = {}

type Swaying = {
	Model: Model,
	Parts: { BasePart },
	Home: { CFrame }, -- the parts' own CFrames
	Moved: { CFrame }, -- reused every frame
	Base: Vector3, -- the bottom of the bounding box
	Phase: number,
}

local trees: { [Model]: true } = {}
local scanned = false
local scannedAt = 0
local scanning: thread? = nil
local swaying: { [Model]: Swaying } = {}
local nextPick = 0

local function isTree(instance: Instance): boolean
	return instance.Name == "Tree" and instance:IsA("Model")
end

-- The tree search: a walk down the Workspace's folders and models (trees never sit inside a
-- part), at most TreeSway.ScanBudget seconds a frame. The trees found so far sway at once.
local function scan()
	local sway = WeatherConfig.TreeSway
	if scanned and os.clock() - scannedAt < sway.ScanAge then
		return
	end
	scanned = true
	scannedAt = os.clock()
	-- the first search fills the list as it goes (trees sway at once); a later one fills a fresh
	-- list and swaps it in when it is done (the trees swaying now are never dropped meanwhile)
	local found: { [Model]: true } = if next(trees) == nil then trees else {}
	scanning = task.spawn(function()
		local stack: { Instance } = { Workspace }
		local slice = os.clock()
		while #stack > 0 do
			local node = table.remove(stack) :: Instance
			for i, child in node:GetChildren() do
				if isTree(child) then
					found[child :: Model] = true
				elseif child:IsA("Folder") or child:IsA("Model") then
					table.insert(stack, child)
				end
				-- (a folder can hold thousands of children: look at the clock inside it too)
				if i % sway.ScanEvery == 0 and os.clock() - slice >= sway.ScanBudget then
					task.wait()
					slice = os.clock()
				end
			end
			if os.clock() - slice >= sway.ScanBudget then
				task.wait()
				slice = os.clock()
			end
		end
		trees = found
		scanning = nil
	end)
end

-- (pcall: a part may have streamed out since it was captured)
local function restore(s: Swaying)
	pcall(Workspace.BulkMoveTo, Workspace, s.Parts, s.Home, Enum.BulkMoveMode.FireCFrameChanged)
end

local function capture(model: Model): Swaying?
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if not d.Anchored or #parts >= WeatherConfig.TreeSway.MaxParts then
				return nil
			end
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return nil
	end
	local home: { CFrame } = {}
	for i, part in parts do
		home[i] = part.CFrame
	end
	local cf, size = model:GetBoundingBox()
	return {
		Model = model,
		Parts = parts,
		Home = home,
		Moved = table.clone(home),
		Base = cf.Position - Vector3.new(0, size.Y / 2, 0),
		Phase = (cf.Position.X * 0.37 + cf.Position.Z * 0.61) % (math.pi * 2),
	}
end

-- Picks the nearest trees (at most `cap`), restoring the ones that drop out.
local function pick(position: Vector3, cap: number)
	local radius = WeatherConfig.TreeSway.Radius
	local near: { { Model: Model, Distance: number } } = {}
	for model in trees do
		if model.Parent then
			local pivot = model:GetPivot().Position
			local distance = (pivot - position).Magnitude
			if distance <= radius then
				table.insert(near, { Model = model, Distance = distance })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.Distance < b.Distance
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(cap, #near) do
		keep[near[i].Model] = true
	end
	for model, s in swaying do
		if not keep[model] then
			restore(s)
			swaying[model] = nil
		end
	end
	for model in keep do
		if not swaying[model] then
			local s = capture(model)
			if s then
				swaying[model] = s
			end
		end
	end
end

-- One frame of sway: `amount` radians at most, leaning toward `wind` (flat unit vector).
function WeatherSway.step(now: number, position: Vector3, amount: number, wind: Vector3, cap: number)
	scan()
	if now >= nextPick then
		nextPick = now + WeatherConfig.TreeSway.Rescan
		pick(position, cap)
	end
	local axis = Vector3.new(0, 1, 0):Cross(wind)
	if axis.Magnitude < 1e-3 then
		return
	end
	axis = axis.Unit
	local speed = WeatherConfig.TreeSway.Speed
	for model, s in swaying do
		local angle = WeatherLogic.sway(now, s.Phase, amount, speed)
		-- turning about (up x wind) by +angle leans the top downwind, about the base
		local turn = CFrame.new(s.Base) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-s.Base)
		for i, home in s.Home do
			s.Moved[i] = turn * home
		end
		local ok = pcall(Workspace.BulkMoveTo, Workspace, s.Parts, s.Moved, Enum.BulkMoveMode.FireCFrameChanged)
		if not ok then
			swaying[model] = nil
		end
	end
end

-- Every tree back to its place.
function WeatherSway.stop()
	for model, s in swaying do
		restore(s)
		swaying[model] = nil
	end
	nextPick = 0
	-- a search cut short starts again at the next windy spell; a finished one is kept for a while
	-- (passing under a roof stops the sway, so it must not search the whole map again each time)
	local running = scanning
	if running then
		task.cancel(running)
		scanning = nil
		scanned = false
	end
end

function WeatherSway.active(): boolean
	return next(swaying) ~= nil
end

return WeatherSway
