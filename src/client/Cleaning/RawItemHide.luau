--[[
	Hides the dirty item in the Cleaning Station's vise while the close-up runs:
	the close-up builds its own clump (OreShellBuilder) in the same spot, and the
	real item would stay in front of it however much dirt is washed off.

	One look at CleanBegin isn't enough. An ore out of the backpack is spawned
	in the same server frame as CleanBegin, so with StreamingEnabled the model,
	and then each of its parts, reaches this client later. So the session scans
	again every Gap seconds (CleaningController's frame loop), and every scan
	also covers the parts that have arrived since on the items already found.
]]

local RawItemHide = {}

RawItemHide.Reach = 3 -- studs from the vise
RawItemHide.Gap = 0.1 -- seconds between two scans

export type State = {
	At: Vector3,
	Hidden: { [Model]: boolean },
	NextScan: number,
}

function RawItemHide.new(at: Vector3): State
	return { At = at, Hidden = {}, NextScan = 0 }
end

-- Is it time for the next scan? (so the caller lists the tagged items only then)
function RawItemHide.due(state: State, now: number): boolean
	if now < state.NextScan then
		return false
	end
	state.NextScan = now + RawItemHide.Gap
	return true
end

local function setHidden(model: Model, hidden: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- `items`: the instances tagged "Item". A model with none of its parts here yet waits for the next scan.
function RawItemHide.scan(state: State, items: { Instance })
	for _, item in items do
		if item:IsA("Model") and not state.Hidden[item] and item:GetAttribute("State") == "Machine" then
			local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
			if part and (part.CFrame.Position - state.At).Magnitude < RawItemHide.Reach then
				state.Hidden[item] = true
			end
		end
	end
	for model in state.Hidden do
		if model.Parent then
			setHidden(model, true)
		else
			state.Hidden[model] = nil -- consumed or streamed out
		end
	end
end

-- The session is over: everything it hid shows again.
function RawItemHide.restore(state: State)
	for model in state.Hidden do
		if model.Parent then
			setHidden(model, false)
		end
	end
	table.clear(state.Hidden)
end

return RawItemHide
