--[[
	Builds a Kenney kit model from its generated box list (Horizon/Kenney/*,
	made by tools/kenney/voxelize.mjs from the CC0 kits the owner sent:
	Watercraft, Hexagon, Fantasy Town, Survival). Plain Roblox parts, no
	meshes (Roblox can't load them from code).

	Blocks.build(parent, data, frame, size, opts) -> Model
	  frame  where the model's bottom center goes; the model's own -Z
	         (Kenney's front) follows frame's LookVector unless opts.Turn
	  size   studs the model's longest side spans
	  opts   Turn (radians about Y), Recolor ({ ["rrggbb"] = Color3 }),
	         Name
]]

local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)

local Blocks = {}

export type Data = {
	Voxel: number,
	Origin: { number },
	Min: { number },
	Max: { number },
	Colors: { string },
	Boxes: { number },
}

-- Studs per Kenney unit for a model whose longest side should span `size`.
function Blocks.scale(data: Data, size: number): number
	local ext = math.max(data.Max[1] - data.Min[1], data.Max[2] - data.Min[2], data.Max[3] - data.Min[3])
	return size / ext
end

-- Height of the model in studs at `size`.
function Blocks.height(data: Data, size: number): number
	return (data.Max[2] - data.Min[2]) * Blocks.scale(data, size)
end

-- The main panel drawn in `colors` (hex): the biggest such box grown by
-- every box of those colours in the same Z slab (one sail of a mast).
-- Center and size in the frame `Blocks.build` got (before Turn), or nil.
-- Used to put a skull on a galleon's main sail.
function Blocks.panel(data: Data, colors: { string }, size: number): (Vector3?, Vector3?)
	local k = Blocks.scale(data, size)
	local h = data.Voxel
	local pivot = Vector3.new((data.Min[1] + data.Max[1]) / 2, data.Min[2], (data.Min[3] + data.Max[3]) / 2)
	local origin = Vector3.new(data.Origin[1], data.Origin[2], data.Origin[3])
	local boxes = data.Boxes
	local function corners(i: number): (Vector3, Vector3)
		return Vector3.new(boxes[i], boxes[i + 1], boxes[i + 2]), Vector3.new(boxes[i + 3], boxes[i + 4], boxes[i + 5])
	end
	local best, bestI = 0, 0
	for i = 1, #boxes, 7 do
		if table.find(colors, data.Colors[boxes[i + 6]]) then
			local lo, hi = corners(i)
			local area = (hi.X - lo.X) * (hi.Y - lo.Y)
			if area > best then
				best, bestI = area, i
			end
		end
	end
	if bestI == 0 then
		return nil, nil
	end
	local lo, hi = corners(bestI)
	for i = 1, #boxes, 7 do
		if table.find(colors, data.Colors[boxes[i + 6]]) then
			local a, b = corners(i)
			if a.Z < hi.Z + 1 and b.Z > lo.Z - 1 then
				lo, hi = lo:Min(a), hi:Max(b)
			end
		end
	end
	return (origin + (lo + hi) / 2 * h - pivot) * k, (hi - lo) * h * k
end

function Blocks.build(parent: Instance, data: Data, frame: CFrame, size: number, opts: { [string]: any }?): Model
	local o: { [string]: any } = opts or {}
	local m = Style.model(o.Name or "KenneyModel", parent)
	local k: number = o.Scale or Blocks.scale(data, size)
	local h = data.Voxel
	local pivot = Vector3.new((data.Min[1] + data.Max[1]) / 2, data.Min[2], (data.Min[3] + data.Max[3]) / 2)
	local origin = Vector3.new(data.Origin[1], data.Origin[2], data.Origin[3])
	local base = frame * CFrame.Angles(0, o.Turn or 0, 0)
	local recolor: { [string]: Color3 } = o.Recolor or {}
	local colors: { Color3 } = {}
	for i, hex in data.Colors do
		colors[i] = recolor[hex] or Color3.fromHex(hex)
	end
	local boxes = data.Boxes
	for i = 1, #boxes, 7 do
		local lo = Vector3.new(boxes[i], boxes[i + 1], boxes[i + 2])
		local hi = Vector3.new(boxes[i + 3], boxes[i + 4], boxes[i + 5])
		local center = (origin + (lo + hi) / 2 * h - pivot) * k
		Style.block(m, base * CFrame.new(center), (hi - lo) * h * k, colors[boxes[i + 6]], nil, Kit.far())
	end
	return m
end

return Blocks
