-- The shopkeepers (owner 2026-10-24: one and the same miner, exactly his 3D model, behind
-- every shop counter, none at the EGGS temple) under Lune: ShopkeeperConfig's lines,
-- scales, show / hide distances and head-turn math; ShopkeeperBuilder builds every piece
-- of the model (smooth, no studs, the lost mirrored pieces back) on an R6-style rig whose
-- joints hold the pieces in place at rest; the lobby marks exactly one keeper spot per
-- shop, each behind its counter facing the customers, and the old blocky keepers are gone.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local ShopkeeperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ShopkeeperBuilder")
	local ShopkeeperModel = Loader.requirePath("ReplicatedStorage.Shared.Builders.ShopkeeperModel")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	local SHOPS = { "Gear", "Tech", "Sell", "Enchant", "Vault" }
	-- the counter tag each shop's spot hangs on
	local COUNTERS = {
		Gear = "ShopCounter",
		Tech = "UpgradeCounter",
		Sell = "SellCounter",
		Enchant = "EnchantCounter",
		Vault = "VaultCounter",
	}
	local RIG = {
		HumanoidRootPart = true,
		Torso = true,
		Head = true,
		["Left Arm"] = true,
		["Right Arm"] = true,
		["Left Leg"] = true,
		["Right Leg"] = true,
	}

	local function hasTag(inst: any, tag: string): boolean
		return table.find(inst:GetTags(), tag) ~= nil
	end

	T.test("Shopkeepers: every shop has hello and thanks lines that fit the bubble", function()
		for _, shop in { "Gear", "Tech", "Sell", "Enchant", "Vault", "Droppers", "Backpacks" } do
			local s = ShopkeeperConfig.Shops[shop]
			T.truthy(s, shop)
			for _, kind in { "Hello", "Thanks" } do
				T.truthy(#s[kind] >= 1, `{shop} {kind}`)
				for _, line in s[kind] do
					T.le(#line, 30, `{shop}: "{line}" fits the bubble`)
				end
			end
			local scale = ShopkeeperConfig.scale(shop)
			T.truthy(scale >= 1 and scale <= 1.6, `{shop} scale {scale}`)
		end
		T.eq(ShopkeeperConfig.Shops.Eggs, nil, "no keeper at the EGGS temple (owner)")
		local hello = ShopkeeperConfig.Shops.Gear.Hello
		T.eq(ShopkeeperConfig.line("Gear", "Hello", 1), hello[1], "first line")
		T.eq(ShopkeeperConfig.line("Gear", "Hello", #hello + 1), hello[1], "wraps round")
		T.eq(ShopkeeperConfig.line("Nowhere", "Thanks", 1), "Thanks!", "an unknown shop says thanks")
		T.eq(ShopkeeperConfig.scale("Nowhere"), ShopkeeperConfig.DefaultScale, "default scale")
	end)

	T.test("Shopkeepers: built near the player, gone far away, steady in between", function()
		local show, hide = ShopkeeperConfig.ShowDistance, ShopkeeperConfig.HideDistance
		T.truthy(hide > show, "a gap between showing and hiding")
		T.truthy(ShopkeeperConfig.wanted(show - 1, false), "near: built")
		T.falsy(ShopkeeperConfig.wanted(show + 1, false), "not yet in the gap")
		T.truthy(ShopkeeperConfig.wanted(show + 1, true), "stays in the gap")
		T.falsy(ShopkeeperConfig.wanted(hide + 1, true), "far: gone")
	end)

	T.test("Shopkeepers: the head turns toward the player, clamped, never backwards", function()
		local body = CFrame.new(0, 3, 0) -- faces -Z
		local head = Vector3.new(0, 5, 0)
		local yaw, pitch = ShopkeeperConfig.lookAngles(body, head, Vector3.new(0, 5, -10))
		T.near(yaw, 0, 1e-6, "straight ahead")
		T.near(pitch, 0, 1e-6, "level")
		yaw = ShopkeeperConfig.lookAngles(body, head, Vector3.new(3, 5, -10))
		T.truthy(yaw < 0, "a player on his right turns the head right (negative yaw)")
		local turned = body * CFrame.Angles(0, yaw, 0)
		local dir = (Vector3.new(3, 5, -10) - head).Unit
		T.near(turned.LookVector:Dot(dir), 1, 1e-6, "the turned head looks at him")
		yaw = ShopkeeperConfig.lookAngles(body, head, Vector3.new(-30, 5, -1))
		T.near(yaw, ShopkeeperConfig.LookYaw, 1e-6, "far left: clamped")
		yaw, pitch = ShopkeeperConfig.lookAngles(body, head, Vector3.new(2, 5, 6))
		T.eq(yaw, 0, "behind him: looks ahead")
		T.eq(pitch, 0, "behind him: level")
		_, pitch = ShopkeeperConfig.lookAngles(body, head, Vector3.new(0, 30, -2))
		T.near(pitch, ShopkeeperConfig.LookPitch, 1e-6, "far up: clamped")
		_, pitch = ShopkeeperConfig.lookAngles(body, head, Vector3.new(0, 4, -6))
		T.truthy(pitch < 0, "a shorter player: looks down")
	end)

	local function pieces(model: any): { [string]: any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not RIG[d.Name] then
				out[d.Name] = d
			end
		end
		return out
	end

	T.test("Shopkeepers: every piece of the owner's model, smooth, no studs", function()
		T.eq(#ShopkeeperModel.Pieces, 76, "all 75 meshes of the file (the 11 its scene lost too) and the hip block")
		local model = ShopkeeperBuilder.build(CFrame.new(), 1)
		T.truthy(hasTag(model, ShopkeeperBuilder.SkipTag), "tagged NoStuds: no Roblox studs on him")
		local count, neon = 0, 0
		for _, part in pieces(model) do
			count += 1
			if part.Material == roblox.Enum.Material.Neon then
				neon += 1
			else
				T.eq(part.Material, roblox.Enum.Material.SmoothPlastic, part.Name .. " smooth")
			end
			T.falsy(part.CanCollide, part.Name .. " no collision")
			T.falsy(part.CanQuery, part.Name .. " no queries (prompts and clicks pass)")
			T.falsy(part.CanTouch, part.Name .. " no touch")
			T.falsy(part.Anchored, part.Name .. " moves with the rig")
		end
		T.eq(count, 76, "76 pieces built")
		T.eq(neon, 4, "the head lamp, side lamp, chest light and lantern glow")
		-- the hip block closes the file's gap between the thighs and the torso
		local hips, torso, thigh = pieces(model).hips, pieces(model).torso, pieces(model).L_thigh
		T.truthy(hips.CFrame.Position.Y - hips.Size.Y / 2 <= thigh.CFrame.Position.Y + thigh.Size.Y / 2, "hips reach the thighs")
		T.truthy(hips.CFrame.Position.Y + hips.Size.Y / 2 >= torso.CFrame.Position.Y - torso.Size.Y / 2, "hips reach the torso")
		-- the mirrored pieces the file's scene had lost are back on both sides
		local p = pieces(model)
		for _, pair in { { "eye", "eye_1" }, { "ear", "ear_1" }, { "eyebrow", "eyebrow_1" }, { "belt_pouch", "belt_pouch_1" } } do
			local a, b = p[pair[1]], p[pair[2]]
			T.truthy(a and b, `{pair[1]} and {pair[2]}`)
			T.near(a.CFrame.Position.X, -b.CFrame.Position.X, 1e-3, `{pair[1]} mirrors {pair[2]}`)
		end
	end)

	T.test("Shopkeepers: feet on the spot, the model's height, facing the spot's way", function()
		local feet = CFrame.lookAt(Vector3.new(10, 2, 5), Vector3.new(20, 2, 5)) -- faces +X
		local scale = 1.2
		local model = ShopkeeperBuilder.build(feet, scale)
		local p = pieces(model)
		local low, high = math.huge, -math.huge
		for _, part in p do
			if part.Shape == roblox.Enum.PartType.Block then
				local y, h = part.CFrame.Position.Y, part.Size.Y / 2 -- (blocks stay upright)
				low = math.min(low, y - h)
				high = math.max(high, y + h)
			end
		end
		T.near(low, 2, 1e-3, "the soles on the floor")
		T.near(high - low, ShopkeeperModel.Height * scale, 1e-2, "as tall as the model at his scale")
		local ahead = p.eye.CFrame.Position - p.head.CFrame.Position
		T.truthy(ahead:Dot(feet.LookVector) > 0.3, "his eyes look the spot's way")
		T.truthy((p.pickaxe_handle.CFrame.Position - p.torso.CFrame.Position):Dot(feet.LookVector) < 0, "the pickaxe on his back")
	end)

	T.test("Shopkeepers: an R6 rig whose joints hold every piece in place at rest", function()
		local feet = CFrame.new(3, 1, -4) * CFrame.Angles(0, 0.7, 0)
		local model = ShopkeeperBuilder.build(feet, 1.1)
		T.eq(model.PrimaryPart and model.PrimaryPart.Name, "HumanoidRootPart", "the root")
		T.truthy(model.PrimaryPart.Anchored, "the root holds him")
		for name in RIG do
			T.truthy(model:FindFirstChild(name), name)
		end
		local joints = {
			RootJoint = { "HumanoidRootPart", "Torso" },
			Neck = { "Torso", "Head" },
			["Left Shoulder"] = { "Torso", "Left Arm" },
			["Right Shoulder"] = { "Torso", "Right Arm" },
			["Left Hip"] = { "Torso", "Left Leg" },
			["Right Hip"] = { "Torso", "Right Leg" },
		}
		local found = 0
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				local want = joints[d.Name]
				T.truthy(want, d.Name .. " is an R6 joint")
				T.eq(d.Part0.Name, want[1], d.Name .. " Part0")
				T.eq(d.Part1.Name, want[2], d.Name .. " Part1")
				local rest = d.Part0.CFrame * d.C0 * d.C1:Inverse()
				T.near((rest.Position - d.Part1.CFrame.Position).Magnitude, 0, 1e-4, d.Name .. " holds its part in place")
				T.near(rest.LookVector:Dot(d.Part1.CFrame.LookVector), 1, 1e-4, d.Name .. " no twist at rest")
				found += 1
			end
		end
		T.eq(found, 6, "six joints")
		-- every piece welded to the rig part it sits in
		for _, part in pieces(model) do
			local weld = part:FindFirstChildOfClass("WeldConstraint")
			T.truthy(weld and weld.Part1 == part and weld.Part0 == part.Parent, part.Name .. " welded to " .. part.Parent.Name)
		end
		local controller = model:FindFirstChildOfClass("AnimationController")
		T.truthy(controller and controller:FindFirstChildOfClass("Animator"), "an Animator for Roblox's R6 animations")
	end)

	local cachedMap = nil
	local function map(): any
		if not cachedMap then
			local game = Instance.new("DataModel")
			cachedMap = WorldBuilder.build(game:GetService("Workspace"))
		end
		return cachedMap
	end

	T.test("Shopkeepers: one keeper spot per shop, behind its counter, facing the customers", function()
		local spots = {}
		for _, d in map():GetDescendants() do
			if hasTag(d, ShopkeeperConfig.Tag) then
				T.truthy(d:IsA("Attachment"), d:GetFullName() .. " is an Attachment (no part)")
				local shop = d:GetAttribute("Shop")
				T.eq(spots[shop], nil, `one spot for {shop}`)
				T.truthy(ShopkeeperConfig.Shops[shop], `{shop} is a known shop`)
				spots[shop] = d
			end
		end
		T.eq(spots.Eggs, nil, "none at the EGGS temple (owner)")
		for _, shop in SHOPS do
			local spot = spots[shop]
			T.truthy(spot, `{shop} has a keeper spot`)
			local holder = spot.Parent
			T.truthy(holder:IsA("BasePart"), `{shop}: on a part (it streams with it)`)
			T.truthy(hasTag(holder, COUNTERS[shop]), `{shop}: on the {COUNTERS[shop]}`)
			local feet = holder.CFrame * spot.CFrame
			local look = feet.LookVector
			T.near(look.Y, 0, 1e-4, `{shop}: stands upright`)
			local toCounter = holder.CFrame.Position - feet.Position
			local flat = Vector3.new(toCounter.X, 0, toCounter.Z)
			T.truthy(flat.Magnitude < 4.5, `{shop}: right behind the counter ({flat.Magnitude})`)
			T.truthy(flat.Magnitude > 0.5 and flat.Unit:Dot(look) > 0.3, `{shop}: the counter is in front of him`)
			T.truthy(feet.Position.Y < holder.CFrame.Position.Y, `{shop}: his feet below the counter top`)
		end
		local eggs = nil
		for _, d in map():GetDescendants() do
			if d:IsA("Model") and hasTag(d, "CapsuleStall") then
				eggs = d
			end
		end
		T.truthy(eggs, "the EGGS temple")
		for _, d in eggs:GetDescendants() do
			T.falsy(hasTag(d, ShopkeeperConfig.Tag), "no keeper spot in the EGGS temple")
		end
	end)

	T.test("Shopkeepers: the old blocky keepers are gone", function()
		for _, d in map():GetDescendants() do
			if d:IsA("Model") then
				for _, name in { "Tobin", "Outfitter", "Forgemaster Ulda", "Enchanter" } do
					T.truthy(d.Name ~= name, `{name} left the map`)
				end
			end
		end
	end)
end
