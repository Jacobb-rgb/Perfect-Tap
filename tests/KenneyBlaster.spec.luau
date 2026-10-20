--[[
	The owner-approved Kenney-shape blasters (Builders/KenneyBlaster,
	KenneyShapes from tools/kenney/blaster_lite.py): the light shape data is
	well formed, every level in every ore stays inside the per-gun part
	budget (phones), the Ore Glow skins pick lava for hot ores and galaxy for
	the rest, guns are the same every time, the black silhouettes are cheap,
	and the shooting effects' hooks (the Muzzle) are where Effects/BlasterFx
	expects them.
]]
return function(T, Loader)
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local KenneyBlaster = Loader.requirePath("ReplicatedStorage.Shared.Builders.KenneyBlaster")
	local Shapes = Loader.requirePath("ReplicatedStorage.Shared.Builders.KenneyShapes")
	local CaseBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.CaseBuilder")

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	T.test("KenneyBlaster: the light shape data is well formed", function()
		-- one model per level, then one per STAR blaster (Config/StarBlasterData: 10 + Index)
		local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
		T.eq(#KenneyBlaster.Models, BlasterData.MaxLevel + #StarBlasterData.List, "one model per level and star blaster")
		local seen = {}
		for _, name in KenneyBlaster.Models do
			T.falsy(seen[name], name .. " used once")
			seen[name] = true
		end
		for _, name in KenneyBlaster.Models do
			local shape = Shapes[name]
			T.truthy(shape, name)
			local b = shape.bounds
			T.lt(b[1], b[2], name .. " z bounds")
			T.lt(b[3], b[4], name .. " y bounds")
			T.truthy(KenneyBlaster.Hands[name], name .. " hand point")
			for _, region in shape.regions do
				T.truthy(region.w > 0, name .. " region width")
				for _, p in region.prims do
					if p[1] == "b" then
						T.lt(p[2], p[3], name .. " box z")
						T.lt(p[4], p[5], name .. " box y")
					elseif p[1] == "t" then
						T.near(p[3], p[5], 1e-6, name .. " a wedge's Z leg is level")
						T.near(p[2], p[6], 1e-6, name .. " a wedge's Y leg is upright")
					else
						T.eq(#p, 7, name .. " a triangle")
					end
				end
			end
			T.truthy(#shape.silhouette > 0, name .. " silhouette")
		end
	end)

	T.test("KenneyBlaster: every level in every ore within the per-gun budget", function()
		local ores = { "", "NotAnOre" }
		for _, ore in OreData.List do
			table.insert(ores, ore.Id)
		end
		local biggest = 0
		for level = 1, BlasterData.MaxLevel do
			for _, ore in ores do
				local n = #parts(BlasterBuilder.build(level, ore))
				biggest = math.max(biggest, n)
				T.le(n, KenneyBlaster.MaxParts, `level {level} {ore}`)
			end
		end
		T.le(KenneyBlaster.MaxParts, 90, "the budget stays phone-friendly")
		T.truthy(biggest > 40, "the top levels keep their detail")
	end)

	T.test("KenneyBlaster: Ore Glow skins (lava for hot ores, galaxy for the rest)", function()
		for level = 1, BlasterData.MaxLevel do
			local ore = BlasterData.vaultOre(level)
			local look = BlasterBuilder.look(level, ore)
			local skin = KenneyBlaster.skin(level, if look.Rusty then "" else ore, look)
			T.eq(skin.Magma, look.Rusty or CaseBuilder.HotOres[ore] == true, `level {level} {ore} pattern`)
			T.eq(skin.Tier, if level >= 10 then 3 elseif level >= 7 then 2 elseif level >= 4 then 1 else 0, "tier")
			local tool = BlasterBuilder.build(level, ore)
			T.eq(tool:FindFirstChild("Crack") ~= nil, skin.Magma, `level {level} lava cracks`)
			T.eq(tool:FindFirstChild("Star") ~= nil, not skin.Magma, `level {level} stars`)
			local fx = tool:FindFirstChild("Effects")
			if fx then
				local emitter = fx:FindFirstChildOfClass("ParticleEmitter")
				T.truthy(emitter, "the effects emitter")
				T.eq(emitter.Name, if skin.Magma then "GunFlame" else "GunSpark", "flames or sparks")
				T.le(emitter.Rate, 8, "slow (phones)")
				T.eq(fx.Transparency, 1, "an invisible holder")
			end
		end
	end)

	T.test("KenneyBlaster: the same gun every time, the Muzzle where the shooting effects expect it", function()
		for _, level in { 1, 5, 10 } do
			local ore = BlasterData.vaultOre(level)
			local a, b = parts(BlasterBuilder.build(level, ore)), parts(BlasterBuilder.build(level, ore))
			T.eq(#a, #b, "same parts")
			for i = 1, #a do
				T.truthy((a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-6, "same place")
				T.eq(a[i].Name, b[i].Name, "same names")
			end
			local tool = BlasterBuilder.build(level, ore)
			local handle = tool:FindFirstChild("Handle")
			local muzzle = handle:FindFirstChild("Muzzle")
			T.truthy(muzzle and muzzle:IsA("Attachment"), "the Muzzle on the Handle (Effects/BlasterFx)")
			T.eq(#muzzle:GetChildren(), 0, "nothing on the Muzzle yet (BlasterFx adds its emitters there)")
			local glow = tool:FindFirstChild("MuzzleGlow")
			local tip = handle.CFrame:PointToWorldSpace(muzzle.Position)
			T.truthy((glow.CFrame.Position - tip).Magnitude < 0.2, "the glowing bore at the Muzzle")
			T.eq(typeof(tool:GetAttribute("Glow")), "Color3", "the beam color")
		end
	end)

	T.test("KenneyBlaster: cheap black silhouettes for the racks", function()
		for level = 2, BlasterData.MaxLevel do
			local model = BlasterBuilder.silhouette(level)
			local list = parts(model)
			T.truthy(#list >= 4, "level " .. level .. " has a shape")
			T.le(#list, 25, "level " .. level .. " silhouette budget")
			for _, p in list do
				T.truthy(p.Anchored and not p.CanCollide and not p.CastShadow, "decor")
			end
		end
	end)

	T.test("KenneyBlaster: the five STAR blasters wear their jewels within the part budget", function()
		local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
		for _, star in StarBlasterData.List do
			local level, ore, skin = BlasterBuilder.starSkin(star)
			T.eq(skin.Tier, 4, star.Id .. ": the jewellery tier")
			local count, names = 0, {}
			local anchors = KenneyBlaster.parts(level, ore, skin, function(name, cf, size)
				count += 1
				names[name] = (names[name] or 0) + 1
				return { CFrame = cf, Size = size } :: any
			end)
			T.truthy(count <= KenneyBlaster.MaxParts, `{star.Id}: {count} parts`)
			T.truthy(anchors.Muzzle.Z < -1, star.Id .. ": the muzzle is ahead of the hand")
			-- the jewellery: gems in gold bezels, a gold collar, a big cluster, the crown
			T.truthy((names.Gem or 0) >= 2, `{star.Id}: {names.Gem or 0} gems`)
			T.eq(names.Gem, names.GemBezel, star.Id .. ": every gem in a bezel")
			T.eq(names.Collar, 1, star.Id .. ": the gold collar")
			T.truthy((names.CrownCrystal or 0) >= 4, star.Id .. ": the crown")
			T.truthy((names.Crystal or 0) >= 5, `{star.Id}: {names.Crystal or 0} crystals`)
		end
		-- the levels never get jewels
		local plain = {}
		KenneyBlaster.parts(10, "Gold", KenneyBlaster.skin(10, "Gold", BlasterBuilder.look(10, "Gold")), function(name, cf, size)
			plain[name] = true
			return { CFrame = cf, Size = size } :: any
		end)
		T.falsy(plain.Gem or plain.Collar or plain.GoldTrim, "LV 10 wears no jewels")
	end)

	-- The held size of a tool's body (Body / Bevel parts; the hand at the origin, the barrel along -Z):
	-- width (X), height (Y) and how far it reaches behind the hand (+Z).
	local function heldSize(tool: any): (number, number, number)
		local lo = { math.huge, math.huge, math.huge }
		local hi = { -math.huge, -math.huge, -math.huge }
		for _, p in parts(tool) do
			if string.match(p.Name, "^Body") or string.match(p.Name, "^Bevel") then
				local h = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local c = p.CFrame * Loader.roblox.Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
							local v = { c.X, c.Y, c.Z }
							for i = 1, 3 do
								lo[i] = math.min(lo[i], v[i])
								hi[i] = math.max(hi[i], v[i])
							end
						end
					end
				end
			end
		end
		return hi[1] - lo[1], hi[2] - lo[2], hi[3]
	end

	T.test("KenneyBlaster: every gun fits the hand (levels and STAR blasters: width, height, behind the hand)", function()
		local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
		-- the biggest level bodies (LV 7 / LV 9) set the budget
		local WIDTH, HEIGHT, BEHIND = 1.3, 2.8, 1.95
		local function check(label: string, tool: any)
			local w, h, behind = heldSize(tool)
			T.truthy(w <= WIDTH, `{label}: {string.format("%.2f", w)} wide`)
			T.truthy(h <= HEIGHT, `{label}: {string.format("%.2f", h)} tall`)
			T.truthy(behind <= BEHIND, `{label}: {string.format("%.2f", behind)} behind the hand`)
		end
		for level = 1, BlasterData.MaxLevel do
			check("LV " .. level, BlasterBuilder.build(level, if level > 1 then "Gold" else ""))
		end
		for _, star in StarBlasterData.List do
			local tool = BlasterBuilder.buildStar(star, 10, "")
			check(star.Id, tool)
			-- still a real gun: at least LV 4's length ahead of the hand
			local muzzle = (tool:FindFirstChild("Handle") :: any):FindFirstChild("Muzzle")
			T.truthy(muzzle.Position.Z < -1.5, `{star.Id}: the barrel reaches {string.format("%.2f", -muzzle.Position.Z)} ahead`)
		end
	end)
end
