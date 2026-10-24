--[[
	The shopkeeper golem previews (tools/lune/export_scene.luau, shots in
	tools/preview/shopkeeper_shots.json):
	  "shopkeepers"       the world with each shop's golem (GolemKeeper, the
	                      same build as ShopkeeperController's) on its spot,
	                      with its soft light; prints each spot (shop, feet,
	                      facing). Arg 2: an emote (Wave, Cheer, Dance...)
	                      at its peak, posed with GolemKeeper.frames.
	  "shopkeeper_solo"   the shops' golems in a row on a plain floor, same arg
	  "shopkeeper_golems" candidate golems in a row with their names (args: kinds)
]]

local Preview = {}

-- The golem `kind` at `size` on `feet`, posed at `emote`'s peak (nil: at rest).
local function golem(Loader: any, kind: string, feet: any, size: number, emote: string?): any
	local GolemKeeper = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemKeeper")
	local GolemEmotes = Loader.requirePath("ReplicatedStorage.Shared.Moves.GolemEmotes")
	local rig = GolemKeeper.build(kind, feet, size)
	if emote then
		-- (the peak: a third of the way in, past the fade-in)
		local t = (GolemEmotes.Duration[emote] or 1) * 0.35
		local frames = GolemKeeper.frames(rig, feet, GolemEmotes.pose(emote, t, 0), 0)
		for i, part in rig.Parts do
			part.CFrame = frames[i]
		end
	end
	return rig
end

-- The controller's soft light (it lights only the nearest golem in the game).
local function faceLight(Loader: any, parent: any, feet: any, height: number)
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local roblox = require("@lune/roblox") :: any
	local glow = ShopkeeperConfig.FaceLight
	local holder = roblox.Instance.new("Part")
	holder.Name = "PreviewLight"
	holder.Anchored = true
	holder.Transparency = 1
	holder.Size = roblox.Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = feet * roblox.CFrame.new(0, height * glow.Up, -glow.Ahead)
	local point = roblox.Instance.new("PointLight")
	point.Range = glow.Range
	point.Brightness = glow.Brightness
	point.Color = glow.Color
	point.Parent = holder
	holder.Parent = parent
end

function Preview.build(Loader: any, map: any, emote: string?)
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local spots = {}
	for _, d in map:GetDescendants() do
		if d:IsA("Attachment") and table.find(d:GetTags(), ShopkeeperConfig.Tag) then
			table.insert(spots, d)
		end
	end
	-- (collected first: the golems go into the same models)
	for _, d in spots do
		local feet = d.Parent.CFrame * d.CFrame
		local p, f = feet.Position, feet.LookVector
		local shop = d:GetAttribute("Shop")
		print(string.format("spot %-8s feet (%.1f, %.1f, %.1f) facing (%.2f, %.2f)", shop, p.X, p.Y, p.Z, f.X, f.Z))
		local kind, size = ShopkeeperConfig.golem(shop)
		local rig = golem(Loader, kind, feet, size, emote)
		rig.Model.Parent = d.Parent.Parent
		faceLight(Loader, d.Parent.Parent, feet, rig.Height)
	end
end

function Preview.buildSolo(Loader: any, workspace: any, emote: string?)
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local roblox = require("@lune/roblox") :: any
	local floor = roblox.Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = roblox.Vector3.new(80, 1, 30)
	floor.CFrame = roblox.CFrame.new(0, -0.5, 0)
	floor.Color = roblox.Color3.fromRGB(70, 74, 92)
	floor.Material = roblox.Enum.Material.SmoothPlastic
	floor.Parent = workspace
	local shops = { "Gear", "Tech", "Sell", "Enchant", "Vault" }
	for i, shop in shops do
		local kind, size = ShopkeeperConfig.golem(shop)
		local feet = roblox.CFrame.new((i - 3) * 10, 0, 0)
		local rig = golem(Loader, kind, feet, size, emote)
		rig.Model.Parent = workspace
	end
end

-- Candidate golems in a row (scene "shopkeeper_golems"), each with its name on a plate.
function Preview.buildGolemLineup(Loader: any, workspace: any, kinds: { string })
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local roblox = require("@lune/roblox") :: any
	local floor = roblox.Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = roblox.Vector3.new(120, 1, 30)
	floor.CFrame = roblox.CFrame.new(0, -0.5, 0)
	floor.Color = roblox.Color3.fromRGB(70, 74, 92)
	floor.Parent = workspace
	local gap = 7
	for i, kind in kinds do
		local x = (i - (#kinds + 1) / 2) * gap
		local g = GolemBuilder.build(kind, roblox.CFrame.new(x, 0, 0), { Size = 2 })
		g.Parent = workspace
		local plate = roblox.Instance.new("Part")
		plate.Name = "Plate"
		plate.Anchored = true
		plate.Size = roblox.Vector3.new(6, 1, 0.2)
		plate.CFrame = roblox.CFrame.new(x, 0.5, -3)
		plate.Color = roblox.Color3.fromRGB(30, 32, 44)
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Front
		gui.LightInfluence = 0
		local label = roblox.Instance.new("TextLabel")
		label.Text = kind
		label.TextColor3 = roblox.Color3.fromRGB(255, 230, 160)
		label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		label.Parent = gui
		gui.Parent = plate
		plate.Parent = workspace
	end
end

return Preview
