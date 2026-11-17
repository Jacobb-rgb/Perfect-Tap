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
	-- (kept: the step spec gives it a character)
	local me: any = { Name = "Me", UserId = 1 }
	rawset(Players, "LocalPlayer", me)
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

	-- a camera at `at` looking toward `toward`
	local function cam(at: any, toward: any): any
		return CF.lookAt(at, toward)
	end

	T.test("lighting portals: the camera's side of a portal picks the light", function()
		T.eq(Diorama.PortalTag, LightingController.PortalTag, "the veils carry the controller's tag")
		local p = portal("EmberCaves", "Quarry")
		local side = LightingController.portalSide
		-- (the portal: x -10..10, y -0.5..16.5 round its centre at y 8, its plane z 0, the cave at -z)
		T.eq(side(p, cam(V3.new(0, 8, -3), V3.new(0, 8, -20))), "EmberCaves", "just inside, looking in")
		T.eq(side(p, cam(V3.new(0, 8, 3), V3.new(0, 8, 20))), "Quarry", "just outside, looking out")
		T.eq(side(p, cam(V3.new(0, 8, -3), V3.new(0, 8, 20))), "EmberCaves", "inside looking at the veil: still inside")
		T.eq(side(p, cam(V3.new(3, 2, -30), V3.new(3, 2, -40))), "EmberCaves", "well inside, in front of it")
		T.eq(side(p, cam(V3.new(-5, 14, 25), V3.new(0, 0, 60))), "Quarry", "outside, over the tunnel")
		-- a camera pinned on the wall round the veil: its eye inside the wall, the way it looks decides
		T.eq(side(p, cam(V3.new(12, 4, -0.2), V3.new(12, 2, 30))), "Quarry", "pinned on the wall's outer face, looking out")
		T.eq(side(p, cam(V3.new(12, 4, 0.2), V3.new(12, 2, -30))), "EmberCaves", "pinned on its inner face, looking in")
		T.eq(side(p, cam(V3.new(12, 4, -0.2), V3.new(40, 4, -0.3))), "EmberCaves", "along the wall: the side it stands on")
		-- away from it: the zone decides, unless the camera is seen through it from the character's side
		local reach = LightingController.PortalReach
		local margin = LightingController.PortalMargin
		T.eq(side(p, cam(V3.new(0, 8, -(reach + 1)), V3.new(0, 8, -200))), nil, "deep in the cave: the zone decides")
		T.eq(side(p, cam(V3.new(10 + margin + 1, 8, -3), V3.new(40, 8, -3))), nil, "beside it: the zone decides")
		local high = V3.new(0, 8 + 8.5 + margin + 12, 34)
		T.eq(side(p, cam(high, V3.new(0, 8, -4)), V3.new(0, 4, 4)), nil, "over it, the character outside too: the zone decides")
		T.eq(side(p, cam(high, V3.new(0, 8, -4)), V3.new(0, 4, -4)), "Quarry", "zoomed out high over the quarry, the character inside")
		T.eq(
			side(p, cam(V3.new(0, 30, 34), V3.new(0, 30, -4)), V3.new(0, 30, -4)),
			nil,
			"seen over the portal (through the wall above): the zone decides"
		)
		-- a dividing plane at the middle of the wall round it (PlaneZ): a camera stopped on either
		-- face of that wall, looking straight down, lies on its own side
		local walled = portal("EmberCaves", "Quarry")
		walled:SetAttribute("PlaneZ", -0.22)
		T.eq(side(walled, cam(V3.new(12, 6, -0.11), V3.new(12.1, -30, -0.2))), "Quarry", "stopped on the wall's outer face, looking down")
		T.eq(side(walled, cam(V3.new(12, 6, -0.33), V3.new(12.1, -30, -0.4))), "EmberCaves", "stopped on its inner face, looking down")
		-- the character far off: a town camera hanging out over the quarry is not the portal's
		T.eq(side(p, cam(V3.new(0, 8, 40), V3.new(0, 8, 60)), V3.new(0, 8, reach + 37)), nil, "the focus out of reach: the zone decides")
		T.eq(side(p, cam(V3.new(0, 8, 40), V3.new(0, 8, 60)), V3.new(0, 8, 46)), "Quarry", "the focus near: the camera's side")
		T.eq(side(portal("NoSuchPreset", "Quarry"), cam(V3.new(0, 8, -3), V3.new(0, 8, -20))), nil, "an unknown preset is ignored")
		T.eq(side(portal(nil, "Quarry"), cam(V3.new(0, 8, -3), V3.new(0, 8, -20))), nil, "a portal without both presets is ignored")
	end)

	T.test("lighting portals: the light changes at once on the frame the camera passes through", function()
		local Lighting = Loader.game:GetService("Lighting")
		-- (the loader's Lighting is a plain stand-in: no post effects, and every key the presets set
		-- comes off again afterwards)
		local before: { [any]: boolean } = {}
		for key in next, Lighting do
			before[key] = true
		end
		rawset(Lighting, "FindFirstChildOfClass", function()
			return nil
		end)
		local Tags = Loader.game:GetService("CollectionService")
		local hadTagged = rawget(Tags, "GetTagged")
		rawset(Tags, "GetTagged", function()
			return {}
		end)
		local p = portal("EmberCaves", "Quarry")
		LightingController.untrackPortal()
		LightingController.trackPortal(p)
		local camera = roblox.Instance.new("Camera")
		local function at(position: any, toward: any)
			camera.CFrame = CF.lookAt(position, toward)
			camera.Focus = CF.new(position + (toward - position).Unit * 10)
		end
		-- (every Lighting value the preset sets is on, as it is)
		local function lit(name: string): boolean
			for key, value in LightingConfig.Presets[name].Lighting do
				if rawget(Lighting, key) ~= value then
					return false
				end
			end
			return true
		end
		local function light(name: string): any
			return LightingConfig.Presets[name].Lighting
		end
		T.truthy(
			light("EmberCaves").Brightness ~= light("Quarry").Brightness
				or light("EmberCaves").ExposureCompensation ~= light("Quarry").ExposureCompensation,
			"the two presets differ in their light"
		)
		local ok, err = pcall(function()
			-- inside, walking out: the camera behind the character
			at(V3.new(0, 8, -6), V3.new(0, 8, 20))
			LightingController.portalStep(camera)
			T.eq(LightingController.currentZone(), "EmberCaves", "inside: the caves' light")
			T.truthy(lit("EmberCaves"), "set at once, no tween")
			-- the camera passes through the veil
			at(V3.new(0, 8, 0.5), V3.new(0, 8, 20))
			T.eq(LightingController.portalStep(camera), "Quarry", "the frame it passes through")
			T.truthy(lit("Quarry"), "the quarry's light that same frame")
			T.eq(LightingController.portalStep(camera), nil, "nothing more to do on the next frame")
			-- a cut away to the town (a teleport, a film's end): the character's zone at once
			-- (a stand-in root: Lune's parts have no Position)
			local root = { Position = V3.new(0, 4, 40) }
			me.Character = {
				FindFirstChild = function(_, name: string)
					return if name == "HumanoidRootPart" then root else nil
				end,
			}
			local town = WorldLayout.zoneAt(root.Position)
			T.truthy(town ~= nil and town.Lighting ~= "Quarry", "the stand-in character stands in the town")
			at(V3.new(0, 30, 400), V3.new(0, 4, 40))
			T.eq(LightingController.portalStep(camera), town.Lighting, "the cut away: the town's light at once")
			T.truthy(lit(town.Lighting), "set at once")
			-- a scripted camera (a film) at the veil decides nothing
			at(V3.new(0, 8, -6), V3.new(0, 8, -20))
			camera.CameraType = roblox.Enum.CameraType.Scriptable
			T.eq(LightingController.portalStep(camera), nil, "a film's camera brings its own light")
			T.eq(LightingController.currentZone(), town.Lighting, "the zone stays the character's")
			camera.CameraType = roblox.Enum.CameraType.Custom
			-- an override (the cleaning close-up) stays on through a crossing
			local pop = LightingController.push("Workbench", 0)
			at(V3.new(0, 8, -6), V3.new(0, 8, -20))
			LightingController.portalStep(camera)
			T.eq(LightingController.currentZone(), "EmberCaves", "the zone follows the camera underneath")
			-- (Workbench sets no Lighting values: the town's stay on, the caves' never come)
			T.truthy(lit(town.Lighting) and not lit("EmberCaves"), "the override's light stays")
			pop()
			T.truthy(lit("EmberCaves"), "popped: the camera's side")
		end)
		me.Character = nil
		LightingController.untrackPortal()
		LightingController.portalStep(nil)
		for key in next, Lighting do
			if not before[key] then
				rawset(Lighting, key, nil)
			end
		end
		rawset(Tags, "GetTagged", hadTagged)
		if not ok then
			error(err, 0)
		end
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
			-- its sides part at the middle of the thin wall round it
			T.near(
				veil:GetAttribute("PlaneZ"),
				-(Diorama.ThinWall / 2 + 0.01 + Diorama.VeilThickness / 2),
				1e-6,
				"the dividing plane in the wall"
			)
			-- walking the DEPTHS way from the quarry into the caves at eye height: wherever the
			-- camera's side decides, it is the zone's own light there
			local checked = 0
			for z = -150, -330, -0.5 do
				for _, x in { -8, 0, 8 } do
					local p = V3.new(x, -6 + (z % 3) * 4, z)
					-- (looking the way it walks in; the band round the plane goes by the view)
					local side = LightingController.portalSide(veil, CF.lookAt(p, p + V3.new(0, 0, -1)))
					local zone = WorldLayout.zoneAt(p)
					-- (within the band round its plane the camera's view decides, not the zone)
					local band = math.abs(veil.CFrame:PointToObjectSpace(p).Z) <= LightingController.PortalBand
					if side and zone and not band then
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
