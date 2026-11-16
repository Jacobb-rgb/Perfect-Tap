--[[
	ElevatorTravelController, the travel cinematic on the client, run on fakes
	(Lune has no Roblox services; the stage, the arrival effects and the overlay
	are the real ones): every way out gives the game back (the camera with the
	player's field of view, the controls, prompts, grab, the blaster, the HUD's
	guis, the touch controls, the character, the real cage, the lighting):
	the end, "Cancel", a respawn, no "Arrive", a second "Depart". The phases
	come in order (the floor window closes at "Enter"), the real cage is hidden
	under the cabin and comes back, and Reduce motion keeps the camera still in
	the preparation.
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox") :: any
	local Instance, Enum = roblox.Instance, roblox.Enum
	local CFrame = Loader.CFrame
	local Config = Loader.requirePath("ReplicatedStorage.Shared.Config.ElevatorTravelConfig")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local RENDER_STEP = "TerraForgeElevatorTravel"

	local function signal(): any
		local list = {}
		local s: any = {}
		s.Connect = function(_, fn)
			table.insert(list, fn)
			local connection: any = { Connected = true }
			connection.Disconnect = function()
				connection.Connected = false
				local index = table.find(list, fn)
				if index then
					table.remove(list, index)
				end
			end
			return connection
		end
		s.fire = function(...)
			for _, fn in table.clone(list) do
				fn(...)
			end
		end
		s.count = function(): number
			return #list
		end
		return s
	end

	local FROM_FLOOR, TO_FLOOR = 1, 4
	local function stopCf(floorIndex: number): any
		return CFrame.new(floorIndex * 300, -40 * floorIndex, 50) * CFrame.Angles(0, floorIndex * 0.8, 0)
	end

	-- A fresh controller on a fake clock. w records what it does; w.run(seconds) plays frames at 60 a second.
	local function controller(reduced: boolean): (any, any)
		local dm = Instance.new("DataModel")
		local workspace = dm:GetService("Workspace")
		local camera = Instance.new("Camera")
		camera.Parent = workspace
		workspace.CurrentCamera = camera
		camera.FieldOfView = 75
		camera.CameraType = Enum.CameraType.Custom
		camera.CFrame = CFrame.new(300, 20, 70)
		camera.Focus = CFrame.new(300, 12, 60)
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		-- two of the game's guis that the ride puts away (one is off already: it stays off)
		local function screenGui(name: string, enabled: boolean): any
			local made = Instance.new("ScreenGui")
			made.Name = name
			made.Enabled = enabled
			local scale = Instance.new("UIScale")
			scale.Name = "Scale"
			scale.Scale = 0.62
			scale.Parent = made
			made.Parent = playerGui
			return made
		end
		local hud = screenGui("TerraForgeHud", true)
		local shut = screenGui("TerraForgeShop", false)
		local banner = screenGui("TerraForgeArtifactBanner", true)
		-- the character
		local character = Instance.new("Model")
		character.Name = "Rider"
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = character
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = character
		local face = Instance.new("Decal")
		face.Parent = head
		character.Parent = workspace
		local function worn(folderName: string, name: string, to: any): any
			local folder = workspace:FindFirstChild(folderName)
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = folderName
				folder.Parent = workspace
			end
			local model = Instance.new("Model")
			model.Name = name
			local body = Instance.new("Part")
			body.Name = "Root"
			body.Parent = model
			local glow = Instance.new("PointLight")
			glow.Enabled = true
			glow.Parent = body
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Enabled = true
			sparkle.Parent = body
			local weld = Instance.new("Weld")
			weld.Part0 = to
			weld.Part1 = body
			weld.Parent = body
			model.Parent = folder
			return model
		end
		local pack = worn("ClientBackpacks", "RookiePack", head)
		local cape = worn("ClientCapes", "Rider_RoyalCape", root)
		local someone = Instance.new("Part")
		someone.Name = "SomeoneElsesTorso"
		someone.Parent = workspace
		local otherPack = worn("ClientBackpacks", "OtherPack", someone)
		-- the real stops (MineKit.elevator), tagged like the game's
		local stops = {}
		for _, floorIndex in { FROM_FLOOR, TO_FLOOR } do
			local floorModel = Instance.new("Model")
			floorModel.Parent = workspace
			stops[floorIndex] = MineKit.elevator(floorModel, stopCf(floorIndex), floorIndex)
		end
		-- (Lune reads LocalTransparencyModifier only once it was set; Roblox starts every part at 0)
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 0
			end
		end
		local removing = signal()
		local heartbeat = signal()
		local w: any = {
			now = 1000,
			steps = {},
			sfx = {},
			loops = {},
			phases = {},
			pushes = 0,
			pops = 0,
			suspends = 0,
			resumes = 0,
			controls = true,
			claimed = nil,
			busy = false,
			prompts = false,
			removing = removing,
			heartbeat = heartbeat,
			camera = camera,
			character = character,
			stops = stops,
			hud = hud,
			shut = shut,
			banner = banner,
			pack = pack,
			cape = cape,
			otherPack = otherPack,
			hideTarget = false, -- the target stop not streamed in yet
			playerGui = playerGui,
			shakes = 0,
			warns = {},
			bursts = 0,
		}
		local gui = { TouchControlsEnabled = true, SelectedObject = nil }
		local localPlayer: any = {
			Name = "Rider",
			Character = character,
			CharacterRemoving = removing,
		}
		localPlayer.WaitForChild = function()
			return playerGui
		end
		localPlayer.FindFirstChildOfClass = function(_, class: string)
			return if class == "PlayerGui" then playerGui else nil
		end
		local services: any = {
			CollectionService = {
				GetTagged = function(_, tag: string)
					if tag ~= "MineElevator" then
						return {}
					end
					local out = {}
					for index, model in stops do
						if model.Parent and not (index == TO_FLOOR and w.hideTarget) then
							table.insert(out, model)
						end
					end
					return out
				end,
			},
			GuiService = gui,
			Players = { LocalPlayer = localPlayer },
			ReplicatedStorage = Loader.game:GetService("ReplicatedStorage"),
			RunService = {
				BindToRenderStep = function(_, name, _priority, fn)
					w.steps[name] = fn
				end,
				UnbindFromRenderStep = function(_, name)
					w.steps[name] = nil
				end,
				Heartbeat = heartbeat,
			},
			Workspace = workspace,
		}
		local function keep(key: string): any
			return function(...)
				w[key] = select(select("#", ...), ...)
			end
		end
		local function tally(key: string): any
			return function()
				w[key] += 1
			end
		end
		local stubs: any = {
			Sfx = {
				play = function(name)
					w.sfx[name] = (w.sfx[name] or 0) + 1
				end,
				loop = function(name, on)
					w.loops[name] = on
				end,
				loopPitch = function() end,
			},
			Motion = {
				reduced = function()
					return reduced
				end,
			},
			PlayerControls = {
				claim = function(name)
					if w.claimed == nil or w.claimed == name then
						w.claimed = name
						return true
					end
					return false
				end,
				release = function(name)
					if w.claimed == name then
						w.claimed = nil
					end
				end,
				set = keep("controls"),
			},
			HudController = {
				uiScale = function()
					return 0.62
				end,
			},
			LightingController = {
				push = function(name)
					T.eq(name, "ElevatorRide", "the ride's lighting")
					w.pushes += 1
					return tally("pops")
				end,
			},
			PromptController = { setSuppressed = keep("prompts") },
			InteractController = { suspend = tally("suspends"), resume = tally("resumes") },
			MiningController = { setBusy = keep("busy") },
			-- the real arrival effects, but the particle bursts are only counted (Lune has no Emit)
			ElevatorArrivalFx = setmetatable({
				burst = function()
					w.bursts += 1
				end,
			}, { __index = Loader.requirePath("ReplicatedStorage.Shared.Builders.ElevatorArrivalFx") }),
		}
		local env: any = {
			game = {
				GetService = function(_, name)
					local service = services[name]
					assert(service, "no fake for " .. name)
					return service
				end,
			},
			script = Loader.find("StarterPlayer.StarterPlayerScripts.Client.Controllers.ElevatorTravelController"),
			os = {
				clock = function()
					return w.now
				end,
			},
			task = {
				spawn = function(fn, ...)
					fn(...)
				end,
				defer = function(fn, ...)
					fn(...)
				end,
				delay = function(_, fn)
					w.prebuild = fn
				end,
			},
			require = function(node)
				return stubs[rawget(node, "Name")] or Loader.require(node)
			end,
			Instance = Instance,
			Enum = Enum,
			CFrame = CFrame,
			Vector3 = roblox.Vector3,
			Color3 = roblox.Color3,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			typeof = function(value: any): string
				return typeof(value)
			end,
			warn = function(text: any)
				table.insert(w.warns, tostring(text))
			end,
		}
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/ElevatorTravelController.luau")
		local C = luau.load(luau.compile(source), { debugName = "ElevatorTravelController", environment = env })()
		C.init()
		C.onPhase(function(name: string, floor: number)
			table.insert(w.phases, name)
			T.eq(floor, TO_FLOOR, "the phase names the target floor")
		end)
		function w.depart(extra: any?)
			local payload: any = {
				Phase = "Depart",
				Floor = TO_FLOOR,
				From = FROM_FLOOR,
				Name = "Sunken Palace",
				Duration = 2,
				DoorsClose = 1.6,
				FromAt = stopCf(FROM_FLOOR),
				StopAt = stopCf(TO_FLOOR),
				Target = stopCf(TO_FLOOR) * CFrame.new(0, 3.6, -3.9),
			}
			if extra then
				for key, value in extra do
					payload[key] = value
				end
			end
			C.depart(payload)
		end
		function w.run(seconds: number)
			local stop = w.now + seconds
			while w.now < stop - 1e-9 do
				w.now += 1 / 60
				local before = camera.CFrame
				local step = w.steps[RENDER_STEP]
				if step then
					step()
				end
				if camera.CameraType == Enum.CameraType.Custom and step and camera.CFrame ~= before then
					w.shakes += 1
				end
				heartbeat.fire()
			end
		end
		-- the real cage parts the cabin covers (their LocalTransparencyModifier)
		function w.cageHidden(floorIndex: number): (number, number)
			local hidden, total = 0, 0
			for _, d in stops[floorIndex]:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "CageLamp" then
					total += 1
					if d.LocalTransparencyModifier > 0.99 then
						hidden += 1
					end
				end
			end
			return hidden, total
		end
		-- Nothing of the ride is left and the game is the player's again.
		function w.isBack(label: string, C2: any)
			local CC = C2 or C
			T.falsy(CC.isTraveling(), label .. ": over")
			T.eq(w.steps[RENDER_STEP], nil, label .. ": no frame step")
			T.eq(camera.CameraType, Enum.CameraType.Custom, label .. ": the camera")
			T.eq(camera.FieldOfView, 75, label .. ": the player's field of view")
			T.eq(w.pops, w.pushes, label .. ": the lighting")
			T.eq(w.resumes, w.suspends, label .. ": grab / throw")
			T.truthy(w.controls, label .. ": the controls")
			T.eq(w.claimed, nil, label .. ": the controls lock")
			T.falsy(w.busy, label .. ": the blaster")
			T.falsy(w.prompts, label .. ": the prompts")
			T.truthy(hud.Enabled, label .. ": the HUD (never switched off)")
			T.near(hud.Scale.Scale, 0.62, 1e-6, label .. ": the HUD at its own scale again")
			T.near(shut.Scale.Scale, 0.62, 1e-6, label .. ": every gui at its own scale again")
			for _, thing in { pack, cape } do
				for _, d in thing:GetDescendants() do
					if d:IsA("BasePart") then
						T.eq(d.LocalTransparencyModifier, 0, label .. ": " .. thing.Name .. " is seen again")
					elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") then
						T.truthy(d.Enabled, label .. ": " .. thing.Name .. "'s " .. d.ClassName .. " back on")
					end
				end
			end
			T.truthy(gui.TouchControlsEnabled, label .. ": the touch controls")
			T.eq(root.LocalTransparencyModifier, 0, label .. ": the character is seen")
			T.eq(face.LocalTransparencyModifier, 0, label .. ": its face")
			for _, floorIndex in { FROM_FLOOR, TO_FLOOR } do
				local hidden = w.cageHidden(floorIndex)
				T.eq(hidden, 0, label .. ": the real cage of floor " .. floorIndex)
				local lamp = stops[floorIndex]:FindFirstChild("CageLamp", true)
				T.truthy(lamp:FindFirstChildOfClass("PointLight").Enabled, label .. ": its lamp's light")
			end
			local set = CC._test.stage()
			T.truthy(set == nil or set.Folder.Parent == nil, label .. ": no set in the world")
			T.eq(w.loops.ElevatorHum, false, label .. ": the hum stops")
		end
		return C, w
	end

	T.test("travel controller: a whole ride plays its phases and gives everything back", function()
		local C, w = controller(false)
		w.depart()
		T.truthy(C.isTraveling(), "travelling")
		T.falsy(w.controls, "the character stands still from the first moment")
		T.truthy(w.prompts and w.busy, "no prompts, no blaster")
		T.eq(w.phases[1], "Prepare")
		T.eq(w.sfx.ElevatorStart, 1, "the clunk")
		local view = C._test.view()
		T.truthy(view.Gui.Enabled and view.Prepare.Visible, "PREPARING ELEVATOR...")
		T.eq(w.camera.CameraType, Enum.CameraType.Custom, "the game's camera in the preparation")
		w.run(0.5)
		T.truthy(w.shakes > 0, "a small shake in the preparation")
		T.eq(w.sfx.ElevatorWarn, 2, "the warning beeps twice")
		local lamp = w.stops[FROM_FLOOR]:FindFirstChild("CageLamp", true):FindFirstChildOfClass("PointLight")
		T.truthy(lamp.Brightness > 1.5, "the cage lamp turns up")
		w.run(0.4)
		T.eq(w.phases[2], "Enter", "the floor window closes")
		T.eq(w.camera.CameraType, Enum.CameraType.Scriptable, "the camera is in the cabin")
		T.near(lamp.Brightness, 1.4, 1e-6, "the lamp as it was")
		T.truthy(w.hud.Scale.Scale < 0.001, "the HUD is put away (by its scale)")
		T.eq(w.pushes, 1, "the ride's lighting")
		T.eq(w.character.Head.LocalTransparencyModifier, 1, "the character is hidden in the cabin")
		local hidden, total = w.cageHidden(FROM_FLOOR)
		T.truthy(total > 0 and hidden == total, "the real cage is under the cabin")
		w.run(0.8) -- 1.7 s: the doors are shut, the server moves the character
		T.eq(w.phases[3], "Ride")
		T.eq(w.sfx.DoorThud, 1, "the thud")
		T.truthy(w.loops.ElevatorHum, "the hum")
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Name = "Sunken Palace", Ok = true })
		local plan = Config.plan(FROM_FLOOR, TO_FLOOR)
		w.run(plan.StopAt - 1.7 + 0.05)
		T.eq(w.phases[4], "Arrive", "the stop")
		T.eq(w.sfx.ElevatorTick, plan.Floors, "a click per floor passed")
		T.eq(w.sfx.ElevatorBrake, 1, "the brakes")
		T.eq(w.sfx.ElevatorDing, 1, "the ding")
		T.eq(w.pops, 1, "the target floor's own lighting comes back")
		hidden = w.cageHidden(FROM_FLOOR)
		T.eq(hidden, 0, "the cage left is back")
		hidden, total = w.cageHidden(TO_FLOOR)
		T.truthy(total > 0 and hidden == total, "the target's cage is under the cabin now")
		T.truthy(view.Arrived.Visible, "ARRIVED!")
		w.run(plan.EndAt - plan.StopAt + 0.1)
		T.eq(w.sfx.ElevatorArrive, 1, "the arrival sting")
		T.eq(w.sfx[Config.Themes.SunkenPalace.Sound], 1, "the mine's own sound")
		T.eq(w.phases[5], "Done")
		T.eq(w.bursts, 1, "one burst of the mine's particles as the doors open")
		T.eq(#w.warns, 0, "no frame failed: " .. table.concat(w.warns, " | "))
		w.isBack("the end")
		T.falsy(view.Gui.Enabled, "the words are gone")
		-- the arrival's effects play on a moment, then go away
		local effects = C._test.fx()
		T.eq(effects.Folder.Parent, w.camera.Parent, "the effects play on")
		w.run(Config.ArrivalTime)
		T.eq(effects.Folder.Parent, nil, "and go away")
		T.eq(w.heartbeat.count(), 0, "nothing keeps running")
	end)

	T.test("travel controller: Cancel, a respawn, no Arrive or an error: the game comes back", function()
		local C, w = controller(false)
		w.depart()
		w.run(1.2)
		C.cancel({ Phase = "Cancel", Floor = TO_FLOOR })
		w.isBack("Cancel")
		T.eq(w.phases[#w.phases], "Cancel")
		w.run(0.5)
		T.falsy(C._test.view().Gui.Enabled, "the words go after the fade back")

		C, w = controller(false)
		w.depart()
		w.run(2.5)
		w.removing.fire()
		w.isBack("a respawn in the ride")

		C, w = controller(false)
		w.depart()
		w.run(0.3)
		w.removing.fire()
		w.isBack("a respawn in the preparation")

		C, w = controller(false)
		w.depart()
		local plan = Config.plan(FROM_FLOOR, TO_FLOOR)
		w.run(plan.BrakeAt + 0.5)
		T.truthy(C.isTraveling(), "the shaft keeps rushing while it waits for Arrive")
		T.eq(w.phases[4], nil, "no stop without Arrive")
		T.eq(w.sfx.ElevatorBrake, nil, "no brake screech while it still rushes")
		w.run(Config.Timing.FailSafe + 0.2)
		w.isBack("no Arrive (the fail-safe)")

		C, w = controller(false)
		w.depart()
		w.run(2)
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Ok = false })
		w.isBack("a failed move")

		-- an error inside a frame ends the ride and still gives everything back
		C, w = controller(false)
		w.depart()
		w.run(1)
		local set = C._test.stage()
		rawset(set, "Rings", nil) -- (the first shaft frame breaks)
		w.run(1)
		w.isBack("an error in a frame")
	end)

	T.test("travel controller: a second Depart gives the first ride back and plays the new one", function()
		local C, w = controller(false)
		w.depart()
		w.run(2)
		w.depart()
		T.truthy(C.isTraveling(), "the new ride plays")
		T.eq(w.phases[#w.phases], "Prepare", "from its start")
		T.eq(w.pushes - w.pops, 0, "the first ride's lighting is back")
		T.eq(w.claimed, "ElevatorTravel", "one lock")
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Ok = true })
		w.run(Config.plan(FROM_FLOOR, TO_FLOOR).EndAt + 0.1)
		w.isBack("the second ride")
	end)

	T.test("travel controller: Reduce motion keeps the camera still before the dip", function()
		local C, w = controller(true)
		w.depart()
		w.run(0.6)
		T.eq(w.shakes, 0, "no shake")
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Ok = true })
		w.run(Config.plan(FROM_FLOOR, TO_FLOOR).EndAt)
		w.isBack("reduced motion")
		-- junk payloads play nothing
		local C2, w2 = controller(false)
		C2.depart({ Phase = "Depart", Floor = "x" })
		C2.depart({ Phase = "Depart", Floor = 3 }) -- (no FromAt: an old server)
		C2.depart(nil)
		T.falsy(C2.isTraveling(), "nothing plays")
		T.truthy(w2.controls, "the controls stay")
		C2.arrive({ Phase = "Arrive" })
		C2.cancel({})
		T.falsy(C2.isTraveling(), "still nothing")
	end)

	T.test("travel controller: the worn pack and cape go with the body; guis keep their owners' choices", function()
		local C, w = controller(false)
		local plan = Config.plan(FROM_FLOOR, TO_FLOOR)
		local function packState(model: any): (number, boolean)
			local level, on = 0, false
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					level = d.LocalTransparencyModifier
				elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") then
					on = on or d.Enabled
				end
			end
			return level, on
		end
		w.depart()
		w.run(plan.DipMid + 0.1)
		for _, thing in { w.pack, w.cape } do
			local level, on = packState(thing)
			T.eq(level, 1, thing.Name .. " hidden with the body in the cabin")
			T.falsy(on, thing.Name .. ": its light and sparkles off")
		end
		local otherLevel, otherOn = packState(w.otherPack)
		T.eq(otherLevel, 0, "someone else's pack is left alone")
		T.truthy(otherOn, "and keeps its light")
		-- the guis go by their scale, never by Enabled
		T.truthy(w.hud.Enabled, "the HUD is never switched off ...")
		T.truthy(w.hud.Scale.Scale < 0.001, "... it is put away by its scale")
		T.truthy(w.shut.Scale.Scale < 0.001, "a closed gui is put away too (in case it opens meanwhile)")
		-- meanwhile the owners do their own things: the banner's timer closes it, the shop opens
		w.banner.Enabled = false
		w.shut.Enabled = true
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Ok = true })
		w.run(plan.DoorsOpenAt + 0.3 - (plan.DipMid + 0.1))
		local level = packState(w.pack)
		T.eq(level, 1, "no pack floating in the doorway while the doors open")
		T.truthy(w.shut.Scale.Scale < 0.001, "the gui opened in the ride stays out of the cinematic")
		w.run(plan.EndAt - (plan.DoorsOpenAt + 0.3) + 0.1)
		T.falsy(C.isTraveling(), "over")
		T.falsy(w.banner.Enabled, "the banner its owner closed stays closed")
		T.near(w.banner.Scale.Scale, 0.62, 1e-6, "(at its own scale for next time)")
		T.truthy(w.shut.Enabled, "the gui opened in the ride shows now")
		T.near(w.shut.Scale.Scale, 0.62, 1e-6, "at its own scale")
		local backLevel, backOn = packState(w.pack)
		T.eq(backLevel, 0, "the pack is back")
		T.truthy(backOn, "with its light")
	end)

	T.test("travel controller: a target stop that streams in late still goes under the cabin", function()
		local C, w = controller(false)
		local plan = Config.plan(FROM_FLOOR, TO_FLOOR)
		w.hideTarget = true
		w.depart()
		w.run(1.7)
		C.arrive({ Phase = "Arrive", Floor = TO_FLOOR, Ok = true })
		w.run(plan.StopAt - 1.7 + 0.05)
		T.eq(w.phases[4], "Arrive", "the stop (the cabin did not wait forever for the stop)")
		local hidden, total = w.cageHidden(TO_FLOOR)
		T.eq(hidden, 0, "not streamed in: nothing to hide yet " .. total)
		w.hideTarget = false -- (it streams in now)
		w.run(0.05)
		hidden, total = w.cageHidden(TO_FLOOR)
		T.truthy(total > 0 and hidden == total, "its cage goes under the cabin at once")
		w.run(plan.EndAt - plan.StopAt + 0.1)
		w.isBack("a late stop")
	end)

	T.test("travel controller: the set is built ahead of the first ride", function()
		local C, w = controller(false)
		T.eq(C._test.stage(), nil, "nothing built at init")
		C.start()
		T.truthy(w.prebuild, "start() plans the build for a little later")
		w.prebuild()
		local set = C._test.stage()
		T.truthy(set and C._test.fx(), "the set and the arrival effects are ready")
		T.eq(set.Folder.Parent, nil, "and out of the world until a ride")
		w.depart()
		T.eq(C._test.stage(), set, "the first ride uses them")
	end)
end
