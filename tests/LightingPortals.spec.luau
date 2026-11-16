-- Lighting portals (owner 2026-11-16, walking back out of the Ember Caves: "on the way back you still
-- see it"): near a cave's veil the light follows the side the camera is on (LightingController.
-- portalSide), and the veils carry the presets of the zones either side of them (Mine/Diorama), so
-- the quarry and the town behind the DEPTHS portal are never drawn in the caves' dark light.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local V3 = roblox.Vector3
	-- (the loader's CFrame: Lune 0.8.9's own lookAt faces away from its target)
	local CF = Loader.CFrame
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	-- (the controller reads Players.LocalPlayer when it loads: a stand-in while it does)
	local Players = Loader.game:GetService("Players")
	local hadLocal = rawget(Players, "LocalPlayer")
	rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1 })
	local loaded, LightingController = pcall(Loader.requirePath, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController")
	rawset(Players, "LocalPlayer", hadLocal)
	if not loaded then
		error(LightingController, 0)
	end
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Diorama = Loader.requirePath("ServerScriptService.Server.World.Mine.Diorama")

	local function portal(inside: any, outside: any): any
		local p = roblox.Instance.new("Part")
		p.Size = V3.new(20, 17, 0.3)
		-- (its LookVector, -Z, into the cave)
		p.CFrame = CF.lookAt(V3.new(0, 8, 0), V3.new(0, 8, -1))
		p:SetAttribute("Inside", inside)
		p:SetAttribute("Outside", outside)
		return p
	end

	T.test("lighting portals: the camera's side of a portal picks the light", function()
		T.eq(Diorama.PortalTag, LightingController.PortalTag, "the veils carry the controller's tag")
		local p = portal("EmberCaves", "Quarry")
		T.eq(LightingController.portalSide(p, V3.new(0, 8, -0.2)), "EmberCaves", "just inside")
		T.eq(LightingController.portalSide(p, V3.new(0, 8, 0.2)), "Quarry", "just outside")
		T.eq(LightingController.portalSide(p, V3.new(3, 2, -30)), "EmberCaves", "well inside, in front of it")
		T.eq(LightingController.portalSide(p, V3.new(-5, 14, 25)), "Quarry", "outside, over the tunnel")
		local reach = LightingController.PortalReach
		local margin = LightingController.PortalMargin
		T.eq(LightingController.portalSide(p, V3.new(0, 8, -(reach + 1))), nil, "deep in the cave: the zone decides")
		T.eq(LightingController.portalSide(p, V3.new(10 + margin + 1, 8, -3)), nil, "beside it: the zone decides")
		T.eq(LightingController.portalSide(p, V3.new(0, 8 + 8.5 + margin + 1, 3)), nil, "over it: the zone decides")
		T.eq(LightingController.portalSide(portal("NoSuchPreset", "Quarry"), V3.new(0, 8, -1)), nil, "an unknown preset is ignored")
		T.eq(LightingController.portalSide(portal(nil, "Quarry"), V3.new(0, 8, -1)), nil, "a portal without both presets is ignored")
	end)

	T.test("lighting portals: the Ember Caves' veil agrees with the zones either side of it", function()
		Fakes(Loader, true)
		local ok, err = pcall(function()
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine.Floor2Ember")
			local origin = MineFloors.Placement[2]
			local model = Floor.build(roblox.Instance.new("Folder"), origin, { Cutaway = false })
			local veils = {}
			for _, d in model:GetDescendants() do
				if d.Name == "Veil" then
					table.insert(veils, d)
				end
			end
			T.eq(#veils, 1, "one veil, in the way in from the quarry")
			local veil = veils[1]
			T.truthy(veil:HasTag(Diorama.PortalTag), "the veil is a lighting portal")
			T.eq(veil:GetAttribute("Inside"), "EmberCaves", "the caves' light inside")
			T.eq(veil:GetAttribute("Outside"), "Quarry", "the quarry's light outside")
			-- its LookVector points into the room (the DEPTHS tunnel is south of it, +Z)
			T.truthy(veil.CFrame.LookVector.Z < -0.99, "the veil faces into the caves")
			-- walking the DEPTHS way from the quarry into the caves at eye height: wherever the
			-- camera's side decides, it is the zone's own light there
			local checked = 0
			for z = -150, -330, -0.5 do
				for _, x in { -8, 0, 8 } do
					local p = V3.new(x, -6 + (z % 3) * 4, z)
					local side = LightingController.portalSide(veil, p)
					local zone = WorldLayout.zoneAt(p)
					if side and zone then
						checked += 1
						T.eq(side, zone.Lighting, `the portal's light at {x}, {z} is the zone's`)
					end
				end
			end
			T.truthy(checked > 100, `checked along the way ({checked})`)
			for _, name in { veil:GetAttribute("Inside"), veil:GetAttribute("Outside") } do
				T.truthy(LightingConfig.Presets[name] ~= nil, tostring(name) .. " is a preset")
			end
		end)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end)
end
