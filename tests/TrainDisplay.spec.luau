-- The train as a still decoration (owner 2026-11-17: "The train should basically become just a
-- static decorative object sitting on a platform. It should have no functionality at all."):
-- World/TrainDisplay's platform with the locomotive and two wagons on it, nothing to use, and a
-- world without the railway, its stops or any train prompt.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local TrainDisplay = Loader.requirePath("ServerScriptService.Server.World.TrainDisplay")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")

	local function parts(root: any): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	-- Nothing usable in a model: no prompt, script, sound or train tag anywhere in it.
	local function inert(root: any, label: string)
		for _, d in root:GetDescendants() do
			T.falsy(d:IsA("ProximityPrompt"), `{label}: no prompt ({d:GetFullName()})`)
			T.falsy(d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript"), `{label}: no script ({d:GetFullName()})`)
			T.falsy(d:IsA("Sound"), `{label}: no sound ({d:GetFullName()})`)
			for _, tag in { "TrainHopper", "TrainStation", "TrainPrompt", "MineLift" } do
				T.falsy(d:HasTag(tag), `{label}: no {tag} ({d:GetFullName()})`)
			end
		end
	end

	T.test("TrainDisplay: the locomotive and two wagons stand still on a plain platform in the quarry", function()
		local folder = roblox.Instance.new("Folder")
		local model = TrainDisplay.build(folder)
		T.eq(model.Name, "TrainDisplay")
		T.eq(model.Parent, folder)
		local cfg = TrainDisplay.Platform
		local deck = model.PrimaryPart
		T.truthy(deck and deck.Name == "Platform", "the platform is the PrimaryPart")
		T.truthy((deck.CFrame.Position - (cfg.Center + roblox.Vector3.new(0, cfg.Size.Y / 2, 0))).Magnitude < 1e-3, "at its place")
		T.truthy((deck.Size - cfg.Size).Magnitude < 1e-3, "its size")
		-- in the quarry, on its floor
		local q = WorldLayout.Quarry
		T.truthy(cfg.Center.X > q.Min.X and cfg.Center.X < q.Max.X and cfg.Center.Z > q.Min.Z and cfg.Center.Z < q.Max.Z, "in the quarry")
		T.eq(cfg.Center.Y, q.Min.Y, "on the quarry floor")
		-- the locomotive and two wagons, every wheel down on the deck, inside its box
		local top = cfg.Center.Y + cfg.Size.Y
		local minX, maxX = cfg.Center.X - cfg.Size.X / 2, cfg.Center.X + cfg.Size.X / 2
		local minZ, maxZ = cfg.Center.Z - cfg.Size.Z / 2, cfg.Center.Z + cfg.Size.Z / 2
		local vehicles = { "Locomotive", "Wagon1", "Wagon2" }
		for _, name in vehicles do
			local vehicle = model:FindFirstChild(name)
			T.truthy(vehicle and vehicle:IsA("Model"), name)
			local wheels = 0
			for _, d in vehicle:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Wheel" then
					wheels += 1
					local radius = d:GetAttribute("Radius") :: number
					local bottom = d.CFrame.Position.Y - radius
					T.truthy(math.abs(bottom - top) < 0.15, `{name}: a wheel on the deck ({bottom} vs {top})`)
				end
				if d:IsA("BasePart") and d.Transparency < 1 then
					local p = d.CFrame.Position
					T.truthy(
						p.X > minX - 0.5 and p.X < maxX + 0.5 and p.Z > minZ - 0.5 and p.Z < maxZ + 0.5,
						`{name}: {d.Name} over the deck`
					)
				end
			end
			T.truthy(wheels >= 4, name .. ": its wheels")
		end
		-- the wagons coupled behind the locomotive (along X, never inside each other)
		local function x(name: string): number
			return model:FindFirstChild(name):GetPivot().Position.X
		end
		T.truthy(x("Wagon1") > x("Locomotive") and x("Wagon2") > x("Wagon1"), "one after the other")
		-- one invisible box per vehicle keeps players out of the train (its own parts don't collide)
		local blockers = 0
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and d.Name == "Blocker" then
				blockers += 1
				T.truthy(d.CanCollide, "a blocker collides")
				T.eq(d.Transparency, 1, "and is invisible")
			end
		end
		T.eq(blockers, #vehicles, "a blocker per vehicle")
		-- still: everything anchored, nothing to use, within its budget
		local list = parts(model)
		for _, p in list do
			T.truthy(p.Anchored, p:GetFullName() .. " anchored")
		end
		T.le(#list, TrainDisplay.MaxParts, "within its budget")
		inert(model, "the display")
		-- built again: replaced, not doubled
		TrainDisplay.build(folder)
		local count = 0
		for _, child in folder:GetChildren() do
			if child.Name == "TrainDisplay" then
				count += 1
			end
		end
		T.eq(count, 1, "one display")
	end)

	T.test("TrainDisplay: the world has no railway, no train stop and no train prompt", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		T.le(74, WorldBuilder.Version, "map v74 or later: no railway")
		T.eq(map:FindFirstChild("Railway"), nil, "no railway")
		T.truthy(map:FindFirstChild("TrainDisplay"), "the still train")
		for _, d in map:GetDescendants() do
			local name = d.Name
			T.falsy(
				name == "TrainStop" or name == "QuarryLine" or name == "MineStation" or name == "Track",
				`no {name} ({d:GetFullName()})`
			)
			if d:IsA("ProximityPrompt") then
				T.falsy(string.find(string.lower(name .. " " .. d.ActionText), "train", 1, true), `no train prompt ({d:GetFullName()})`)
			end
			T.falsy(d:GetAttribute("RailwayPlaceholder"), `no track placeholder ({d:GetFullName()})`)
		end
		inert(map:FindFirstChild("TrainDisplay"), "the world's display")
		-- off the quarry ramp (its wedge: x -8..8, its toe at z -148): no part of the display in its box
		local land = map:FindFirstChild("Land")
		local quarry = if land then land:FindFirstChild("Quarry") else nil
		local ramp = if quarry then quarry:FindFirstChild("Ramp") else nil
		T.truthy(ramp and ramp:IsA("BasePart"), "the quarry ramp")
		local rp, rh = ramp.CFrame.Position, ramp.Size / 2
		for _, d in map:FindFirstChild("TrainDisplay"):GetDescendants() do
			if d:IsA("BasePart") then
				-- the part's world box (its rotation applied to its half size)
				local p = d.CFrame.Position
				local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = d.CFrame:GetComponents()
				local s = d.Size / 2
				local hx = math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z
				local hz = math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
				T.falsy(
					math.abs(p.X - rp.X) < rh.X + hx - 1e-3 and math.abs(p.Z - rp.Z) < rh.Z + hz - 1e-3,
					`{d.Name} clear of the quarry ramp`
				)
			end
		end
		-- the yards: no train stop, the back fence closed (its middle post where the opening was)
		local plots = map:FindFirstChild("Plots")
		T.truthy(plots, "plots")
		local yards = 0
		for _, d in plots:GetDescendants() do
			if d.Name == "Yard" and d:IsA("Model") then
				yards += 1
				T.eq(d:FindFirstChild("TrainStop"), nil, "no train stop")
				local fence = d:FindFirstChild("Fence")
				T.truthy(fence, "the yard's back fence")
			end
		end
		T.eq(yards, #WorldLayout.Plots, "a yard per plot")
		-- no TRAIN chute on the build grid
		T.eq(BaseLayout.Chutes.Train, nil)
		T.eq(#BaseLayout.ChuteNames, 1)
		T.eq(BaseLayout.ChuteNames[1], "Pen")
	end)
end
