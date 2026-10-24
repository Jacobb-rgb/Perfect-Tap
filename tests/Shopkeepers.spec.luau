-- The shopkeepers (owner 2026-10-24: his own avatar behind every shop counter) under
-- Lune: ShopkeeperConfig's lines, scales, owner pick and head-turn math; the
-- ShopkeeperService template (dressed as a harmless rig, retried, never for UserId 0;
-- avatars are fakes); the lobby marks exactly one keeper spot per shop, each behind its
-- counter facing the customers, and the old blocky keepers are gone.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local ShopkeeperService = Loader.requirePath("ServerScriptService.Server.Services.ShopkeeperService")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")

	local SHOPS = { "Gear", "Tech", "Sell", "Enchant", "Vault", "Eggs" }
	-- the counter tag each shop's spot hangs on (the EGGS temple has no counter: its podium)
	local COUNTERS = {
		Gear = "ShopCounter",
		Tech = "UpgradeCounter",
		Sell = "SellCounter",
		Enchant = "EnchantCounter",
		Vault = "VaultCounter",
	}

	T.test("Shopkeepers: every shop has hello and thanks lines that fit the bubble", function()
		for _, shop in { "Gear", "Tech", "Sell", "Enchant", "Vault", "Eggs", "Droppers", "Backpacks" } do
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
		local hello = ShopkeeperConfig.Shops.Gear.Hello
		T.eq(ShopkeeperConfig.line("Gear", "Hello", 1), hello[1], "first line")
		T.eq(ShopkeeperConfig.line("Gear", "Hello", #hello + 1), hello[1], "wraps round")
		T.eq(ShopkeeperConfig.line("Nowhere", "Thanks", 1), "Thanks!", "an unknown shop says thanks")
		T.eq(ShopkeeperConfig.scale("Nowhere"), ShopkeeperConfig.DefaultScale, "default scale")
	end)

	T.test("Shopkeepers: the configured UserId wins, then a user creator, else nobody yet", function()
		T.eq(ShopkeeperConfig.ownerId(42, true, 7), 42, "configured")
		T.eq(ShopkeeperConfig.ownerId(0, true, 7), 7, "the user who owns the game")
		T.eq(ShopkeeperConfig.ownerId(0, false, 7), 0, "a group game: not the group id")
		T.eq(ShopkeeperConfig.ownerId(0, true, 0), 0, "an unpublished place")
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

	local function fakeAvatar(): any
		local model = Instance.new("Model")
		model.Name = "Player"
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = false
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Anchored = true
		head.CanCollide = true
		head.Parent = model
		local hat = Instance.new("Accessory")
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.CanQuery = true
		handle.Parent = hat
		hat.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = roblox.Enum.HumanoidRigType.R15
		humanoid.Parent = model
		local animate = Instance.new("LocalScript")
		animate.Name = "Animate"
		animate.Parent = model
		return model
	end

	T.test("Shopkeepers: the template is a harmless rig the client can animate", function()
		local model = fakeAvatar()
		ShopkeeperService.dress(model, 99)
		T.eq(model.Name, ShopkeeperConfig.TemplateName, "name")
		T.eq(model:GetAttribute("UserId"), 99, "whose avatar")
		T.eq(model.PrimaryPart, model.HumanoidRootPart, "pivot = the root")
		T.truthy(model.HumanoidRootPart.Anchored, "the root holds him in place")
		T.falsy(model.Head.Anchored, "the body parts move with the animations")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				T.falsy(d.CanCollide, d.Name .. " no collision")
				T.falsy(d.CanTouch, d.Name .. " no touch")
				T.falsy(d.CanQuery, d.Name .. " no queries (prompts and clicks pass)")
				T.falsy(d.CastShadow, d.Name .. " no shadow")
			end
		end
		T.eq(model:FindFirstChild("Animate"), nil, "scripts stripped")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		T.eq(humanoid.DisplayDistanceType, roblox.Enum.HumanoidDisplayDistanceType.None, "no name over his head")
		T.eq(model:GetAttribute("Rig"), "R15", "rig type for the animations")
		local classic = fakeAvatar()
		classic:FindFirstChildOfClass("Humanoid").RigType = roblox.Enum.HumanoidRigType.R6
		ShopkeeperService.dress(classic, 1)
		T.eq(classic:GetAttribute("Rig"), "R6", "a classic R6 avatar")
	end)

	T.test("Shopkeepers: the template is retried with a doubling wait, never for UserId 0", function()
		local home = Instance.new("Folder")
		local calls, waits = 0, {}
		ShopkeeperService._setMaker(function(userId: number)
			calls += 1
			return if calls >= 3 then fakeAvatar() else nil
		end, function(seconds: number)
			table.insert(waits, seconds)
		end)
		T.falsy(ShopkeeperService.build(0, home), "nobody")
		T.eq(calls, 0, "no download for UserId 0")
		T.truthy(ShopkeeperService.build(5, home), "third try")
		T.eq(calls, 3, "three downloads")
		T.eq(#waits, 2, "two waits")
		T.eq(waits[2], waits[1] * 2, "doubled")
		local template = home:FindFirstChild(ShopkeeperConfig.TemplateName)
		T.truthy(template, "the template is home")
		T.eq(template:GetAttribute("UserId"), 5, "his avatar")
		-- a rebuild replaces it
		calls = 10
		T.truthy(ShopkeeperService.build(6, home), "again")
		local count = 0
		for _, child in home:GetChildren() do
			if child.Name == ShopkeeperConfig.TemplateName then
				count += 1
			end
		end
		T.eq(count, 1, "one template")
		-- all tries fail: no template, false
		local empty = Instance.new("Folder")
		calls = -100
		T.falsy(ShopkeeperService.build(7, empty), "no avatar")
		T.eq(empty:FindFirstChild(ShopkeeperConfig.TemplateName), nil, "nothing left behind")
	end)

	local cachedMap = nil
	local function map(): any
		if not cachedMap then
			local game = Instance.new("DataModel")
			cachedMap = WorldBuilder.build(game:GetService("Workspace"))
		end
		return cachedMap
	end

	local function hasTag(inst: any, tag: string): boolean
		return table.find(inst:GetTags(), tag) ~= nil
	end

	T.test("Shopkeepers: one keeper spot per shop, behind its counter, facing the customers", function()
		local spots = {}
		for _, d in map():GetDescendants() do
			if hasTag(d, ShopkeeperConfig.Tag) then
				T.truthy(d:IsA("Attachment"), d:GetFullName() .. " is an Attachment (no part)")
				local shop = d:GetAttribute("Shop")
				T.eq(spots[shop], nil, `one spot for {shop}`)
				spots[shop] = d
			end
		end
		for _, shop in SHOPS do
			local spot = spots[shop]
			T.truthy(spot, `{shop} has a keeper spot`)
			T.truthy(ShopkeeperConfig.Shops[shop], `{shop} is a known shop`)
			local holder = spot.Parent
			T.truthy(holder:IsA("BasePart"), `{shop}: on a part (it streams with it)`)
			local feet = holder.CFrame * spot.CFrame
			local look = feet.LookVector
			T.near(look.Y, 0, 1e-4, `{shop}: stands upright`)
			local tag = COUNTERS[shop]
			if tag then
				T.truthy(hasTag(holder, tag), `{shop}: on the {tag}`)
				local toCounter = holder.CFrame.Position - feet.Position
				local flat = Vector3.new(toCounter.X, 0, toCounter.Z)
				T.truthy(flat.Magnitude < 4.5, `{shop}: right behind the counter ({flat.Magnitude})`)
				T.truthy(flat.Magnitude > 0.5 and flat.Unit:Dot(look) > 0.3, `{shop}: the counter is in front of him`)
				T.truthy(feet.Position.Y < holder.CFrame.Position.Y, `{shop}: his feet below the counter top`)
			else
				-- the EGGS temple: on its dais beside the ROYAL podium, facing the stall's front
				T.eq(holder.Name, "CapsuleMachine", "on the ROYAL podium")
				local facing = LobbyLayout.get("CapsuleStall").Facing
				T.truthy(look:Dot(Vector3.new(facing.X, 0, facing.Z).Unit) > 0.99, "faces the stall's front")
				local size = holder.Size
				local podiumH = math.min(size.X, size.Y, size.Z)
				T.near(feet.Position.Y, holder.CFrame.Position.Y - podiumH / 2, 0.05, "feet on the dais (the podium's foot)")
				local side = feet.Position - holder.CFrame.Position
				T.truthy(Vector3.new(side.X, 0, side.Z).Magnitude > 2.4, "beside the podium, not inside it")
			end
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
