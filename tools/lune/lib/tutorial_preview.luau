--[[
	The first-time tutorial in the quarry (scene "tutorial" / "tutorial_hopper"
	for tools/lune/export_scene.luau, shots in tools/preview/tutorial_shots.json).
	The bubble is drawn with the game's own code (TutorialView.build / layout /
	apply / setStep, HudView, TeleportView); the steps' text comes from
	TutorialConfig.

	The 3D guide is a Beam and a BillboardGui in the game, which the preview
	renderer can't draw. Here it is stood in for with glowing parts on the
	same line: a strip from the character's feet to the target point
	(TutorialConfig.layoutPoint) and a chevron with the target's name over it.

	  tutorial         step 1: a player at the foot of the quarry ramp, the
	                   guide on the Mine Station
	  tutorial_hopper  step 3: on the station platform carrying ore, the guide
	                   on the hopper

	UI overlays (build/preview/<name>.json):
	  ui_tutorial_pc           PC 1600 x 900: step 1, bubble at the bottom right
	  ui_tutorial_tv           a 1080p TV (console, HUD scale 1.25): step 2 with
	                           the gamepad hint, in the title-safe area
	  ui_tutorial_phone        667 x 375 pt phone: step 3, top right, touch hint
	  ui_tutorial_phone_small  568 x 320 pt phone: step 5 (the longest text),
	                           kept above a right-side menu of two buttons
	  ui_tutorial_done         PC: the finish card (+250 coins)
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")
local Dummy = require("./dummy")

local Preview = {}

local Instance, Vector2, Vector3, Color3 = roblox.Instance, roblox.Vector2, roblox.Vector3, roblox.Color3
local UDim2 = roblox.UDim2

local GLOW = Color3.fromRGB(255, 176, 64) -- Theme.Accent
local GOLD = Color3.fromRGB(255, 206, 72) -- Theme.Coin

local function neon(parent: any, cf: any, size: any, color: any, transparency: number?): any
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = roblox.Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- The guide stand-in: a strip from `from` to `to`, a chevron and a name over `to`, facing `eye`.
function Preview.guide(parent: any, CF: any, from: any, to: any, name: string, eye: any, height: number)
	local folder = Instance.new("Folder")
	folder.Name = "TutorialGuide"
	folder.Parent = parent
	-- the beam: dashes (the sparkle texture moving along it), fading toward the target
	local length = (to - from).Magnitude
	local dash, gap = 1.6, 0.9
	local along = CF.lookAt(from, to)
	local d = 0
	while d + dash < length - 1 do
		local fade = d / length
		neon(
			folder,
			along * CF.new(0, 0, -(d + dash / 2)),
			Vector3.new(0.5, 0.18, dash),
			if fade < 0.5 then GLOW else GOLD,
			0.15 + fade * 0.4
		)
		d += dash + gap
	end
	-- the chevron (two bars meeting at the tip) and the name, turned to the camera
	local tip = to + Vector3.new(0, height - 0.6, 0)
	local flat = Vector3.new(eye.X, tip.Y, eye.Z)
	local face = CF.lookAt(tip, flat)
	for _, side in { -1, 1 } do
		local arm = face * CF.new(side * 0.75, 0.75, 0) * CF.Angles(0, 0, side * math.rad(45))
		neon(folder, arm * CF.new(0, 0, 0), Vector3.new(0.7, 2.4, 0.3), GLOW)
	end
	local sign = Instance.new("Part")
	sign.Anchored = true
	sign.Transparency = 0.98 -- (the exporter drops fully clear parts, and their text with them)
	sign.Size = Vector3.new(8, 1.4, 0.1)
	sign.CFrame = face * CF.new(0, 3.1, 0)
	sign.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Face = roblox.Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Text = name
	label.TextColor3 = GOLD
	label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
	label.Parent = gui
end

-- The world part of the scene: the dummy and the guide (`variant` = "station" | "hopper").
function Preview.scene(Loader: any, workspace: any, variant: string)
	local CF = Loader.CFrame
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
	local props = Instance.new("Folder")
	props.Name = "TutorialProps"
	props.Parent = workspace
	local station = TrainConfig.Station.Platform.Center
	if variant == "golems" then
		-- step 9 (the golem hint): on the plaza, the guide on the CapsuleStall
		local stall = nil
		for _, d in workspace:GetDescendants() do
			if d:IsA("Model") and d:HasTag("CapsuleStall") then
				stall = d:GetPivot().Position
				break
			end
		end
		local feet = Vector3.new(-14, 0.2, 18)
		local target = (stall or Vector3.new(-39, 0.85, 12.4)) + Vector3.new(0, 3, 0)
		Dummy.build(props, CF, CF.lookAt(feet, Vector3.new(target.X, feet.Y, target.Z)), "idle")
		Preview.guide(
			props,
			CF,
			feet + Vector3.new(0, 0.6, 0),
			target,
			TutorialConfig.TargetNames.Capsules,
			Vector3.new(-2, 7, 30),
			TutorialConfig.arrowHeight("Capsules")
		)
	elseif variant == "hopper" then
		local deck = station.Y + TrainConfig.Station.Platform.Size.Y
		local feet = Vector3.new(station.X - 8, deck, station.Z + 1.5)
		local target = TutorialConfig.layoutPoint("Hopper", nil)
		Dummy.build(props, CF, CF.lookAt(feet, Vector3.new(target.X, feet.Y, target.Z)), "carry")
		Preview.guide(
			props,
			CF,
			feet + Vector3.new(0, 0.6, 0),
			target,
			TutorialConfig.TargetNames.Hopper,
			Vector3.new(14, -3, -133),
			TutorialConfig.arrowHeight("Hopper")
		)
	else
		local feet = Vector3.new(5, -12, -141)
		local target = TutorialConfig.layoutPoint("Station", nil)
		Dummy.build(props, CF, CF.lookAt(feet, Vector3.new(target.X, feet.Y, target.Z)), "idle")
		Preview.guide(
			props,
			CF,
			feet + Vector3.new(0, 0.6, 0),
			target,
			TutorialConfig.TargetNames.Station,
			Vector3.new(-2, -6.5, -127),
			TutorialConfig.arrowHeight("Station")
		)
	end
end

-- The UI overlays.
function Preview.build(Loader: any): { [string]: any }
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")

	-- one screen: render px per design unit, the game's uiScale and the screen in pt (below the top bar)
	type Screen = { Px: number, Ui: number, Pt: any, Touch: boolean, TenFoot: boolean? }
	local PC: Screen = { Px = 1.25, Ui = 1.25, Pt = Vector2.new(1600, 900 - 36), Touch = false }
	local TV: Screen = { Px = 1.25 * 900 / 1080, Ui = 1.25, Pt = Vector2.new(1920, 1080 - 36), Touch = false, TenFoot = true }
	local PHONE: Screen = { Px = 0.62 * 900 / 375, Ui = 0.62, Pt = Vector2.new(667, 375 - 24), Touch = true }
	local SMALL: Screen = { Px = 0.62 * 900 / 320, Ui = 0.62, Pt = Vector2.new(568, 320 - 58), Touch = true }

	local function hud(screen: Screen): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = screen.Px
		refs.Coins.Text = Format.money(120)
		refs.Income.Text = Format.perSecond(0)
		refs.CarryLabel.Text = "CARRYING 0/2"
		for i = 1, 2 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		local bar = TeleportView.build(refs.TopBar, screen.Ui, screen.Pt.X)
		TeleportView.relayout(bar, refs.TopBar, screen.Ui, screen.Pt.X)
		return refs
	end

	-- the right-side menu: BUILD and the elevator icon (two buttons of 64, gap 10)
	local function menuTop(screen: Screen): number
		return screen.Pt.Y / screen.Ui / 2 - (64 * 2 + 10) / 2
	end

	local function bubble(screen: Screen, index: number, input: string): any
		local refs = TutorialView.build()
		refs.Gui.Scale.Scale = screen.Px
		TutorialView.apply(refs, TutorialView.layout(screen.Ui, screen.Pt, screen.Touch, screen.TenFoot, menuTop(screen)))
		local step = TutorialConfig.get(index)
		TutorialView.setStep(refs, index, step, if step.Hint then step.Hint[input] else nil)
		refs.Bubble.Visible = true
		return refs
	end

	-- the side menu as it ships (STORE hidden until step 8's store), and the
	-- golem hint's on-screen arrow at GOLEMS (or at MENU on the shut touch grid)
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local function golemHint(screen: Screen, input: string): { any }
		local menu = SideMenuView.build()
		menu.Gui.Scale.Scale = screen.Px
		SideMenuView.setHidden(menu, "Store", true)
		local designH = screen.Pt.Y / screen.Ui
		local touch = screen.Touch
		SideMenuView.apply(
			menu,
			SideMenuView.layout(
				screen.Ui,
				designH,
				{ Count = #SideMenuView.shown(menu), Touch = touch, DesignWidth = screen.Pt.X / screen.Ui }
			)
		)
		local tut = bubble(screen, 9, input)
		local holder = (
			if menu.Layout and menu.Layout.Toggle and not menu.Expanded then menu.Toggle.Parent else menu.Buttons.Golems.Parent
		) :: any
		local column = menu.Column.Position
		local right = math.max(holder.Position.X.Offset + holder.Size.X.Offset, menu.Column.Size.X.Offset)
		local x = column.X.Offset + right + TutorialView.PointerGap
		local y = column.Y.Offset + holder.Position.Y.Offset + holder.Size.Y.Offset / 2
		tut.Pointer.Position = UDim2.fromOffset(x, y)
		tut.Pointer.Visible = true
		return { hud(screen).Gui, menu.Gui, tut.Gui }
	end

	local exports: { [string]: any } = {}
	exports.ui_tutorial_golems_pc = UiExport.export(golemHint(PC, "Mouse"))
	exports.ui_tutorial_golems_phone = UiExport.export(golemHint(PHONE, "Touch"))
	exports.ui_tutorial_pc = UiExport.export({ hud(PC).Gui, bubble(PC, 1, "Mouse").Gui })
	exports.ui_tutorial_tv = UiExport.export({ hud(TV).Gui, bubble(TV, 2, "Gamepad").Gui })
	exports.ui_tutorial_phone = UiExport.export({ hud(PHONE).Gui, bubble(PHONE, 3, "Touch").Gui })
	exports.ui_tutorial_phone_small = UiExport.export({ hud(SMALL).Gui, bubble(SMALL, 5, "Touch").Gui })
	local done = TutorialView.build()
	done.Gui.Scale.Scale = PC.Px
	done.DoneText.Text = TutorialView.doneText(TutorialConfig.Reward)
	done.Done.Visible = true
	local doneHud = hud(PC)
	doneHud.Coins.Text = Format.money(370)
	exports.ui_tutorial_done = UiExport.export({ doneHud.Gui, done.Gui })
	return exports
end

return Preview
