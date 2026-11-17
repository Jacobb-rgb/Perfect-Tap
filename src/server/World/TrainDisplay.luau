--[[
	TrainDisplay: the ore train as a still decoration (owner 2026-11-17: "The
	train should basically become just a static decorative object sitting on a
	platform. It should have no functionality at all."). The railway, its
	tunnels, the Mine Station, the yards' train stops and every train system
	are gone; where the Mine Station stood on the quarry floor, east of the
	ramp's foot, one plain flagstone platform carries the red locomotive and
	two loaded ore wagons (TrainBuilder), coupled, standing still, facing the
	ramp the players come down.

	No rails, no prompts, no scripts, no sounds: it is a prop. The platform
	collides like the floor; the train's own parts are TrainBuilder's (no
	collisions), so one invisible box per vehicle keeps players out of it.
	Everything is anchored. Pure and deterministic (Instance creation only),
	so Lune tests, the bake and previews build it; the world keeps rocks and
	big decorations off it (WorldLayout.KeepOut).

	  TrainDisplay.build(map)  builds Map.TrainDisplay (replacing an old one)
	  TrainDisplay.Platform    { Center (its ground middle), Size }
	  TrainDisplay.MaxParts    the whole display's budget (tests/TrainDisplay.spec.luau)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared.Builders.Geo)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local WorldLayout = require(Shared.Config.WorldLayout)

local TrainDisplay = {}

local rgb = Color3.fromRGB

-- On the quarry floor where the Mine Station stood (its platform and the stop beside it): a little
-- longer than the train (the locomotive and two wagons: 38 studs coupler to coupler), which stands
-- in its middle.
TrainDisplay.Platform = {
	Center = Vector3.new(26, WorldLayout.Quarry.Min.Y, -153),
	Size = Vector3.new(44, 0.8, 10),
}
-- the locomotive's colour (the shop's old Express Train picture) and the wagons' loads
TrainDisplay.Color = rgb(226, 72, 60)
TrainDisplay.Loads = {
	{ rgb(250, 196, 60), rgb(255, 222, 120), rgb(220, 150, 40) }, -- gold
	{ rgb(150, 110, 230), rgb(196, 160, 255), rgb(120, 200, 230) }, -- amethyst and quartz
}
TrainDisplay.MaxParts = 140

local DECK = rgb(178, 152, 126) -- flagstone (the old Mine Station's)
local DECK_DARK = rgb(146, 122, 102)
local SOLID = { CanTouch = false }
local BLOCKER = { CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }

-- Where an attachment is in the world (Lune does not keep WorldPosition up to date).
local function attachmentAt(model: Model, name: string): Vector3?
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			local part = d.Parent :: BasePart
			return (part.CFrame * d.CFrame).Position
		end
	end
	return nil
end

-- An invisible box round a vehicle (its parts don't collide): players walk round the train.
-- (its own box in the vehicle's frame, from every part's corners)
local function blocker(parent: Instance, vehicle: Model)
	local pivot = vehicle:GetPivot()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in vehicle:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = pivot:PointToObjectSpace((d.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
		end
	end
	if lo.X > hi.X then
		return
	end
	local part = Geo.block(parent, pivot * CFrame.new((lo + hi) / 2), hi - lo, DECK, nil, BLOCKER)
	part.Name = "Blocker"
end

function TrainDisplay.build(map: Instance): Model
	local old = map:FindFirstChild("TrainDisplay")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "TrainDisplay"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- the platform: a flagstone deck with a darker skirt and a low step on the ramp's side (no lines on
	-- the deck: two would read as rails)
	local cfg = TrainDisplay.Platform
	local top = cfg.Center.Y + cfg.Size.Y
	local deck = Geo.block(m, CFrame.new(cfg.Center + Vector3.new(0, cfg.Size.Y / 2, 0)), cfg.Size, DECK, nil, SOLID)
	deck.Name = "Platform"
	m.PrimaryPart = deck
	local skirt = Geo.block(
		m,
		CFrame.new(cfg.Center + Vector3.new(0, cfg.Size.Y / 2 - 0.1, 0)),
		cfg.Size + Vector3.new(0.6, -0.2, 0.6),
		DECK_DARK,
		nil,
		SOLID
	)
	skirt.Name = "Skirt"
	local step = Geo.block(
		m,
		CFrame.new(cfg.Center + Vector3.new(0, cfg.Size.Y / 4, cfg.Size.Z / 2 + 0.9)),
		Vector3.new(cfg.Size.X - 4, cfg.Size.Y / 2, 1.2),
		DECK_DARK,
		nil,
		SOLID
	)
	step.Name = "Step"
	-- the train: the locomotive in front (facing -X, the ramp's side), its wagons coupled behind,
	-- the whole train in the platform's middle
	local loco = TrainBuilder.locomotive(TrainDisplay.Color)
	loco.Name = "Locomotive"
	-- (the train stays smooth as it always was, the platform gets the map's studs: StudStyleConfig.SkipTag)
	loco:SetAttribute("NoStuds", true)
	loco.Parent = m
	local wagons: { Model } = {}
	local total = (loco:GetAttribute("Length") :: number?) or 10
	for i, loads in TrainDisplay.Loads do
		local wagon = TrainBuilder.wagon(TrainDisplay.Color, loads)
		wagon.Name = "Wagon" .. i
		wagon:SetAttribute("NoStuds", true)
		wagon.Parent = m
		total += (wagon:GetAttribute("Length") :: number?) or 10
		table.insert(wagons, wagon)
	end
	local front = Vector3.new(cfg.Center.X - total / 2, top, cfg.Center.Z)
	local facing = CFrame.lookAt(front, front + Vector3.new(-1, 0, 0))
	-- (the Root is the bottom middle: the wheels on the deck)
	local length = (loco:GetAttribute("Length") :: number?) or 10
	loco:PivotTo(facing * CFrame.new(0, 0, length / 2))
	blocker(m, loco)
	local previous: Model = loco
	for _, wagon in wagons do
		-- turned like the locomotive, then moved so its front coupler meets the back one before it
		wagon:PivotTo(facing.Rotation + wagon:GetPivot().Position)
		local back = attachmentAt(previous, "CouplerBack")
		local coupler = attachmentAt(wagon, "CouplerFront")
		if back and coupler then
			wagon:PivotTo(wagon:GetPivot() + (back - coupler))
		end
		blocker(m, wagon)
		previous = wagon
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = map
	return m
end

return TrainDisplay
