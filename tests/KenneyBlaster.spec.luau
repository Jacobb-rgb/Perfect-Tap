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
		T.eq(#KenneyBlaster.Models, BlasterData.MaxLevel, "one model per level")
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
end
