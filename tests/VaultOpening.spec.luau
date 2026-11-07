--[[
	VaultController's crate opening, run on fakes (Lune has no Roblox services;
	the stage and the overlay are the real ones): every way out gives the game
	back and names the blaster, the one flash goes through the game's flash gap,
	Reduce motion shows no flash, no blur and no particle bursts.
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox") :: any
	local Instance, Enum = roblox.Instance, roblox.Enum
	local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
	local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")
	local RENDER_STEP, SKIP = "TerraForgeCrateOpening", "TerraForgeCrateSkip"

	local function signal(): any
		local list = {}
		return {
			Connect = function(_, fn)
				table.insert(list, fn)
				return { Connected = true, Disconnect = function() end }
			end,
			fire = function()
				for _, fn in list do
					fn()
				end
			end,
		}
	end

	-- A fresh controller on a fake clock. w records what it does; w.run(seconds) plays frames at 60 a second.
	local function controller(reduced: boolean): (any, any)
		RevealKit.resetFlash()
		local dm = Instance.new("DataModel")
		local workspace = dm:GetService("Workspace")
		local camera = Instance.new("Camera")
		camera.Parent = workspace
		workspace.CurrentCamera = camera
		camera.ViewportSize = roblox.Vector2.new(844, 390)
		camera.FieldOfView = 70
		camera.CameraType = Enum.CameraType.Custom
		local lighting, playerGui = Instance.new("Folder"), Instance.new("Folder")
		local hud = { Gui = { Enabled = true } }
		local w: any = {
			now = 1000,
			delayed = {},
			steps = {},
			actions = {},
			toasts = {},
			sfx = {},
			bursts = {},
			pushes = 0,
			pops = 0,
			suspends = 0,
			resumes = 0,
			controls = true,
			busy = false,
			prompts = false,
			flash = 0,
			blur = 0,
			removing = signal(),
			net = {},
		}
		local gui = { TouchControlsEnabled = true, SelectedObject = nil }
		local function always(value: any): any
			return function()
				return value
			end
		end
		local function keep(key: string): any -- (methods: their last argument)
			return function(...)
				w[key] = select(select("#", ...), ...)
			end
		end
		local function tally(key: string): any
			return function()
				w[key] += 1
			end
		end
		local services: any = {
			ContextActionService = {
				BindActionAtPriority = function(_, name, fn)
					w.actions[name] = fn
				end,
				UnbindAction = function(_, name)
					w.actions[name] = nil
				end,
			},
			GuiService = gui,
			Players = { LocalPlayer = { CharacterRemoving = w.removing, WaitForChild = always(playerGui) } },
			ReplicatedStorage = Loader.game:GetService("ReplicatedStorage"),
			RunService = {
				BindToRenderStep = function(_, name, _priority, fn)
					w.steps[name] = fn
				end,
				UnbindFromRenderStep = function(_, name)
					w.steps[name] = nil
				end,
			},
			StarterGui = { GetCoreGuiEnabled = always(true), SetCoreGuiEnabled = function() end },
			Lighting = lighting,
			TweenService = {},
			UserInputService = {
				TouchEnabled = false,
				MouseEnabled = true,
				LastInputTypeChanged = signal(),
				GetLastInputType = always({ Name = "MouseButton1" }),
			},
			Workspace = workspace,
		}
		local stubs: any = {
			Sfx = {
				play = function(name)
					w.sfx[name] = (w.sfx[name] or 0) + 1
				end,
				loop = function() end,
				loopPitch = function() end,
			},
			Vfx = {
				burst = function(kind)
					table.insert(w.bursts, kind)
				end,
			},
			MenuPanels = { closeAll = function() end, Names = {} },
			PlayerControls = { claim = always(true), release = function() end, set = keep("controls") },
			Hotbar = { restoreCore = function() end },
			HudController = {
				uiScale = always(0.62),
				refs = always(hud),
				toast = function(text)
					table.insert(w.toasts, text)
				end,
			},
			LightingController = {
				push = function()
					w.pushes += 1
					return tally("pops")
				end,
			},
			PromptController = { setSuppressed = keep("prompts") },
			StateController = { onChanged = function() end },
			InteractController = { suspend = tally("suspends"), resume = tally("resumes") },
			MiningController = { setBusy = keep("busy") },
			Net = {
				listen = function(name, fn)
					w.net[name] = fn
				end,
			},
			Motion = { reduced = always(reduced) },
		}
		local env: any = {
			game = {
				GetService = function(_, name)
					return services[name]
				end,
			},
			script = Loader.find("StarterPlayer.StarterPlayerScripts.Client.Controllers.VaultController"),
			os = {
				clock = function()
					return w.now
				end,
			},
			task = {
				delay = function(seconds, fn)
					table.insert(w.delayed, { at = w.now + seconds, fn = fn })
				end,
			},
			require = function(node)
				return stubs[rawget(node, "Name")] or Loader.require(node)
			end,
			Instance = Instance,
			Enum = Enum,
			CFrame = Loader.CFrame,
			Vector3 = roblox.Vector3,
			Color3 = roblox.Color3,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
		}
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/VaultController.luau")
		local C = luau.load(luau.compile(source), { debugName = "VaultController", environment = env })()
		C.init()
		function w.overlay(name: string): any
			local screen = playerGui:FindFirstChild("TerraForgeCrateOpening")
			return screen and screen:FindFirstChild(name, true)
		end
		function w.run(seconds: number)
			local stop = w.now + seconds
			while w.now < stop do
				w.now += 1 / 60
				for i = #w.delayed, 1, -1 do
					local d = w.delayed[i]
					if d.at <= w.now then
						table.remove(w.delayed, i)
						d.fn()
					end
				end
				local step = w.steps[RENDER_STEP]
				if step then
					step()
					local flash = w.overlay("Flash")
					if flash.Visible then
						w.flash = math.max(w.flash, 1 - flash.BackgroundTransparency)
					end
					w.blur = math.max(w.blur, lighting:FindFirstChild("CrateOpeningBlur").Size)
				end
			end
		end
		function w.stage(): any
			return workspace:FindFirstChild("CrateOpening"):FindFirstChild("CrateOpening")
		end
		function w.press()
			w.actions[SKIP]("Skip", Enum.UserInputState.Begin)
		end
		-- Nothing of the opening is left and the game is the player's again.
		function w.isBack(label: string)
			T.falsy(C.isPlaying(), label .. ": over")
			T.eq(w.steps[RENDER_STEP], nil, label .. ": no frame step")
			T.eq(w.actions[SKIP], nil, label .. ": no skip button")
			T.eq(workspace:FindFirstChild("CrateOpening"), nil, label .. ": no stage")
			T.eq(#lighting:GetChildren(), 0, label .. ": no blur")
			T.eq(#playerGui:GetChildren(), 0, label .. ": no overlay")
			T.eq(camera.CameraType, Enum.CameraType.Custom, label .. ": the camera")
			T.eq(camera.FieldOfView, 70, label .. ": its zoom")
			T.eq(w.pops, w.pushes, label .. ": the lighting")
			T.eq(w.resumes, w.suspends, label .. ": grab / throw")
			T.truthy(w.controls and hud.Gui.Enabled and gui.TouchControlsEnabled, label .. ": controls, HUD, touch")
			T.falsy(w.busy or w.prompts, label .. ": mining, prompts")
		end
		return C, w
	end

	T.test("CrateOpening controller: every way out gives the game back", function()
		local C, w = controller(false)
		T.truthy(C.play(7, "Amethyst"), "plays")
		T.falsy(w.controls, "the stage owns the player")
		w.run(Stage.T_HOLD + 0.5)
		w.press() -- AWESOME!
		w.run(Stage.Duration - Stage.T_HOLD + 0.6)
		w.isBack("AWESOME!")
		T.eq(#w.toasts, 1, "one toast")
		T.truthy(string.find(w.toasts[1], "Amethyst", 1, true), "it names the blaster: " .. w.toasts[1])

		C, w = controller(false)
		C.play(5, "Gold")
		w.run(Stage.T_HOLD)
		w.now += 20 -- (nobody presses anything: it goes on by itself)
		w.run(Stage.Duration - Stage.T_HOLD + 0.6)
		w.isBack("nobody presses anything")
		T.eq(#w.toasts, 1, "one toast")

		C, w = controller(false)
		C.play(9, "RoyalAurum")
		w.run(1)
		w.press() -- on to the burst
		w.run(1.7)
		T.lt(0, w.sfx.CaseBurst or 0, "a skip still plays the burst")
		w.press() -- in the hero moment: on to the words
		w.press() -- AWESOME!
		w.run(Stage.Duration - Stage.T_HOLD + 0.6)
		w.isBack("skipped through")

		C, w = controller(false)
		C.play(10, "Heartstone")
		w.run(Stage.T_BURST + 0.05)
		w.removing.fire()
		w.isBack("reset at the burst")
		w.run(1)
		w.isBack("a moment later")
	end)

	T.test("CrateOpening controller: the item paid for is the one on the stage and in the words", function()
		local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
		local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
		local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
		local function paid(level: number, sent: any, ore: string)
			local label = string.format("level %d, %s: ", level, tostring(sent))
			local C, w = controller(true) -- (Reduce motion: the gun's colours stay exact)
			w.net.VaultResult({ Ok = true, Level = level, Ore = sent })
			T.truthy(C.isPlaying(), label .. "it plays")
			w.run(Stage.T_HOLD + 0.1)
			T.eq(w.overlay("BlasterName").Text, string.upper(BlasterData.displayName(level, ore)), label .. "name")
			T.eq(w.overlay("Stats").Text, "LV " .. level, label .. "level")
			T.eq(w.overlay("Damage").Text, Format.big(BlasterData.damage(level, ore)), label .. "damage")
			local stage = w.stage()
			T.eq(stage:FindFirstChild("Seam", true).Color, BlasterBuilder.colors(level, ore).Color, label .. "the crate's colour")
			-- the blaster on the stage, piece by piece
			local want, got = Stage.blasterModel(level, ore):GetDescendants(), stage:FindFirstChild("Blaster"):GetDescendants()
			T.eq(#got, #want, label .. "its pieces")
			for i, d in want do
				if d:IsA("BasePart") then
					T.eq(got[i].Name, d.Name, label .. "piece " .. i)
					T.eq(got[i].Color, d.Color, label .. d.Name .. " " .. i)
				end
			end
			w.press()
			w.run(Stage.Duration - Stage.T_HOLD + 0.6)
			T.truthy(string.find(w.toasts[1], BlasterData.displayName(level, ore), 1, true), label .. "the toast: " .. w.toasts[1])
		end
		paid(7, "Amethyst", "Amethyst") -- what the server sends
		paid(5, "Sapphire", "Sapphire") -- another ore than its case's
		paid(3, "", "") -- no ore
		paid(4, "NotAnOre", BlasterData.vaultOre(4)) -- a bad name: its case's ore
		paid(6, nil, BlasterData.vaultOre(6))
	end)

	T.test("CrateOpening controller: the burst has its one flash, through the game's flash gap", function()
		local C, w = controller(false)
		C.play(10, "Heartstone")
		w.run(Stage.T_BURST + 0.05)
		T.lt(0.8, w.flash, "the flash")
		T.falsy(RevealKit.takeFlash(w.now), "it took the slot")
		T.eq(#w.bursts, 3, "the burst's particles")
		w.run(Stage.T_RISE_END - Stage.T_BURST)
		T.eq(#w.bursts, 5, "and the reveal's")
		T.lt(0, w.blur, "the blur")

		-- another reveal flashed just before: none now
		C, w = controller(false)
		C.play(10, "Heartstone")
		w.run(Stage.T_BURST - 0.1)
		T.truthy(RevealKit.takeFlash(w.now), "another reveal's flash")
		w.run(0.4)
		T.eq(w.flash, 0, "no second one so soon")
		RevealKit.resetFlash()
	end)

	T.test("CrateOpening controller: Reduce motion: no flash, no blur, no particle bursts", function()
		for _, level in { 2, 10 } do
			local C, w = controller(true)
			C.play(level, "Gold")
			w.run(Stage.T_BURST + 0.05)
			T.truthy(RevealKit.takeFlash(w.now), "no flash slot taken")
			w.run(Stage.T_HOLD - Stage.T_BURST)
			T.eq(w.flash, 0, "no flash")
			T.eq(w.blur, 0, "no blur")
			T.eq(#w.bursts, 0, "no particle bursts")
			T.lt(0, w.sfx.CaseBurst or 0, "the sound stays")
			T.truthy(w.overlay("Flash"), "the overlay is up")
			w.press()
			w.run(Stage.Duration - Stage.T_HOLD + 0.6)
			w.isBack("Reduce motion")
			RevealKit.resetFlash()
		end
	end)
end
