--[[
	Golem capsules and golem pets preview (step 7, package Capsules+Golems).
	Shots in tools/preview/capsules_shots.json. Everything is drawn with the
	game's own code (GolemBuilder, CapsuleView, GolemView, HudView).

	  scene "golems"          every golem in rows by rarity on a studio floor,
	                          the three capsules whole and cracked open, a
	                          forgekeeper with three followers for scale
	  scene "capsules"        the world: a forgekeeper at the CAPSULES stall
	                          with three followers, another walking by with
	                          two hopping followers; UI overlays:
	    ui_capsules_shop        PC: the capsule panel, STONE tab
	    ui_capsules_lucky       PC: CRYSTAL tab with Triple Lucky on (boosted odds)
	    ui_capsules_phone       667 x 375 pt phone (compact layout)
	    ui_capsules_grid        PC: an x10 opening's result grid
	    ui_capsules_grid_phone  phone: the same
	    ui_golems               PC: the golem inventory, a golem selected
	    ui_golems_phone         phone: the inventory
	    ui_golems_delete        PC: delete mode, three golems picked
	    ui_golems_confirm       PC: the confirm box before deleting
	    ui_capsule_board        the stall's odds board as the game fills it (inset)
	  scene "capsule_reveal"  the world dimmed (a dark see-through plane in
	                          front of the camera stands in for the overlay's
	                          dim) with a Mythic golem where the opening's hero
	                          viewport is (the renderer draws no ViewportFrames)
	    ui_capsule_reveal       PC: the name plate, rays, OK / OPEN AGAIN
	    ui_capsule_reveal_phone phone: the same
	  scene "capsule_crack"   the same with the capsule shaking, cracks lit
	    ui_capsule_crack        PC: SKIP and the hint
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local Color3 = roblox.Color3
local Vector3 = roblox.Vector3
local UDim2 = roblox.UDim2

-- The render (tools/preview/render.mjs) and its UI scales.
Preview.Width = 1600
Preview.Height = 900
Preview.Fov = 50
Preview.Scale = 1.25 -- 900 px / 720 design units
Preview.Inset = 36 -- the PC top bar (render px)
Preview.PhoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone at the 0.62 floor
Preview.PhoneInset = 58

-- The hero camera of the reveal shots (scene "capsule_reveal" / "capsule_crack"),
-- far enough from the stall that the dim plane fits between the hero and the world.
Preview.HeroCamera = { Position = { -11.8, 8.7, 42.2 }, Target = { -40, 4.5, 14 } }
Preview.HeroGolem = "HeartstoneColossus"

-- A mid-game player (State snapshot shape).
Preview.Now = 1_800_000_000
function Preview.state(lucky: boolean?): { [string]: any }
	local owned = {}
	local kinds = {
		"RubyKnight",
		"GildedPorter",
		"CobaltDiver",
		"EmberImp",
		"SilverSquire",
		"QuartzSprite",
		"JadeGardener",
		"AmethystAcolyte",
		"PebbleGolem",
		"PebbleGolem",
		"CopperTinker",
		"CoalChomper",
		"TinTumbler",
		"CopperTinker",
	}
	for i, kind in kinds do
		table.insert(owned, { Id = i, Kind = kind, Locked = if i == 1 or i == 5 then true else nil })
	end
	return {
		Coins = if lucky then 2.4e6 else 48250,
		BlasterLevel = if lucky then 4 else 3,
		Golems = { Owned = owned, Equipped = { 1, 2, 3 }, NextId = #owned + 1 },
		Boosts = { TripleLuckyUntil = if lucky then Preview.Now + 754 else 0, HexaLuckyUntil = 0 },
		Bonuses = { GolemBond = 0 },
	}
end

local function label(Geo: any, parent: any, cf: any, width: number, height: number, text: string, color: any)
	local board = Geo.block(parent, cf, Vector3.new(width, height, 0.08), Color3.fromRGB(44, 36, 46))
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = roblox.Enum.NormalId.Back
	gui.Parent = board
	local textLabel = roblox.Instance.new("TextLabel")
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
	textLabel.Parent = gui
	return board
end

---------------------------------------------------------------- scene "golems"

-- The golem gallery.
function Preview.buildGallery(Loader: any, workspace: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Dummy = require("./dummy")

	local gallery = roblox.Instance.new("Model")
	gallery.Name = "GolemGallery"
	gallery.Parent = workspace
	Geo.block(gallery, CF.new(0, -0.5, 0), Vector3.new(160, 1, 120), Color3.fromRGB(62, 64, 78))

	-- rows by rarity (Common in front), golems face the camera (-Z)
	local rows: { [string]: { string } } = {}
	for _, golem in GolemConfig.List do
		rows[golem.Rarity] = rows[golem.Rarity] or {}
		table.insert(rows[golem.Rarity], golem.Id)
	end
	local SPACING = 4.2
	for r, info in Rarity.List do
		local ids = rows[info.Id] or {}
		local z = (r - 1) * 5.2
		local y = (r - 1) * 0.6 -- a step per row so the back rows show
		Geo.block(gallery, CF.new(0, y / 2, z + 0.4), Vector3.new(30, y + 0.02, 5.2), Color3.fromRGB(70, 72, 88))
		label(Geo, gallery, CF.new(-14.5, y + 0.3, z - 1.4) * CF.Angles(-1.05, 0, 0), 4.2, 0.7, string.upper(info.Name), info.Color)
		for i, id in ids do
			local x = (i - (#ids + 1) / 2) * SPACING
			GolemBuilder.build(id, CF.new(x, y, z)).Parent = gallery
		end
	end

	-- the capsules: whole, then cracked open with the halves flying apart
	for i, capsule in CapsuleConfig.List do
		local x = 22 + (i - 1) * 5.5
		GolemBuilder.capsule(capsule.Id, CF.new(x, 2.4, 0) * CF.Angles(0, 0.3, 0)).Parent = gallery
		local open = GolemBuilder.capsule(capsule.Id, CF.new(x, 2.4, 8) * CF.Angles(0, 0.3, 0))
		open.Parent = gallery
		local top = open:FindFirstChild("Top")
		top:PivotTo(top:GetPivot() * CF.new(0.6, 1.6, 0) * CF.Angles(0, 0, -0.6))
		for _, d in open:GetDescendants() do
			if d:IsA("BasePart") and d.Name:sub(1, 5) == "Crack" then
				d.Transparency = 0
			end
		end
	end

	-- a forgekeeper with three followers (scale check, follower size)
	local feet = CF.new(-24, 0, 4)
	Dummy.build(gallery, CF, feet, "idle")
	for i, kind in { "GildedPorter", "RubyKnight", "StarmetalSovereign" } do
		local slot = Preview.Slots[i]
		GolemBuilder.build(kind, feet * CF.new(slot.X, 0, slot.Z), { Size = Preview.FollowerSize }).Parent = gallery
	end
end

-- GolemController.Slots / FollowerSize (the controller needs the client to load).
Preview.Slots = { Vector3.new(-3.1, 0, 3.0), Vector3.new(3.1, 0, 3.0), Vector3.new(0, 0, 5.2) }
Preview.FollowerSize = 0.85

---------------------------------------------------------------- the world scenes

local function findStall(workspace: any): any
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.PrimaryPart and d.PrimaryPart.Name == "CapsuleMachine" then
			return d
		end
	end
	error("no CapsuleStall in the world")
end

-- The stall's front direction (its OddsBoard faces it) and the pedestal.
local function stallFrame(stall: any): (any, any)
	local board = stall:FindFirstChild("OddsBoard", true)
	local look = board.CFrame.LookVector
	local front = Vector3.new(look.X, 0, look.Z).Unit
	return front, stall.PrimaryPart.CFrame.Position
end

-- A ray from the render camera through a screen pixel.
local function pixelRay(Loader: any, cameraPos: any, target: any, px: number, py: number): any
	local CF = Loader.CFrame
	local cam = CF.lookAt(cameraPos, target)
	local tanY = math.tan(math.rad(Preview.Fov) / 2)
	local tanX = tanY * Preview.Width / Preview.Height
	local nx = px / Preview.Width * 2 - 1
	local ny = 1 - py / Preview.Height * 2
	return (cam.LookVector + cam.RightVector * (nx * tanX) + cam.UpVector * (ny * tanY)).Unit
end

-- The forgekeepers and their followers by the stall (scene "capsules").
function Preview.buildWorld(Loader: any, workspace: any)
	local CF = Loader.CFrame
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local Dummy = require("./dummy")
	local stall = findStall(workspace)
	local front, pedestal = stallFrame(stall)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "CapsulePreview"
	folder.Parent = workspace
	local ground = pedestal.Y - 0.25
	-- a forgekeeper in front of the big capsule (a little aside), looking at it
	local side = front:Cross(Vector3.new(0, 1, 0)).Unit
	local at = pedestal + front * 7 + side * 4.5
	local feet = CF.lookAt(Vector3.new(at.X, ground, at.Z), Vector3.new(pedestal.X, ground, pedestal.Z))
	Dummy.build(folder, CF, feet, "idle")
	for i, kind in { "StarmetalSovereign", "RubyKnight", "GildedPorter" } do
		local slot = Preview.Slots[i]
		-- standing followers look around (GolemController.LookAround): here back toward the plaza
		local golemFeet = feet * CF.new(slot.X, 0, slot.Z) * CF.Angles(0, ({ 2.2, -2.0, 2.6 })[i], 0)
		GolemBuilder.build(kind, golemFeet, { Size = Preview.FollowerSize }).Parent = folder
	end
	-- another forgekeeper walking by, two followers mid-hop
	local walker = pedestal + front * 14 - side * 7
	local walkFeet = CF.lookAt(Vector3.new(walker.X, ground, walker.Z), Vector3.new(walker.X, ground, walker.Z) + front)
	Dummy.build(folder, CF, walkFeet, "idle", {
		shirt = Color3.fromRGB(60, 130, 200),
		pants = Color3.fromRGB(50, 50, 64),
		skin = Color3.fromRGB(200, 150, 110),
		hair = Color3.fromRGB(30, 24, 20),
	})
	for i, kind in { "EmberImp", "CobaltDiver" } do
		local slot = Preview.Slots[i]
		local hop = if i == 1 then 0.45 else 0.15
		local golemFeet = walkFeet * CF.new(slot.X, hop, slot.Z) * CF.Angles(-0.12, 0, (if i == 1 then 0.07 else -0.06))
		GolemBuilder.build(kind, golemFeet, { Size = Preview.FollowerSize }).Parent = folder
	end
end

-- The reveal / crack scenes: a dim plane in front of the hero camera and a
-- golem (or the shaking capsule) where the hero viewport shows it.
function Preview.buildHero(Loader: any, workspace: any, crack: boolean)
	local CF = Loader.CFrame
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local cam = Preview.HeroCamera
	local cameraPos = Vector3.new(cam.Position[1], cam.Position[2], cam.Position[3])
	local target = Vector3.new(cam.Target[1], cam.Target[2], cam.Target[3])
	local folder = roblox.Instance.new("Folder")
	folder.Name = "CapsuleHero"
	folder.Parent = workspace
	local look = (target - cameraPos).Unit
	-- the overlay's dim (rgb 12, 8, 16 at 30 % see-through), as a plane behind the hero
	local dimAt = cameraPos + look * 18
	local dim = roblox.Instance.new("Part")
	dim.Anchored = true
	dim.CanCollide = false
	dim.CastShadow = false
	dim.Size = Vector3.new(80, 50, 0.1)
	dim.CFrame = CF.lookAt(dimAt, dimAt + look)
	dim.Color = Color3.fromRGB(12, 8, 16)
	dim.Material = roblox.Enum.Material.SmoothPlastic
	dim.Transparency = 0.3
	dim.Parent = folder
	-- the hero viewport's center on screen (CapsuleView.layoutOpening at this UI scale)
	local designH = (Preview.Height - Preview.Inset) / Preview.Scale
	local hero = math.clamp(math.floor(designH * 0.5), 220, 460)
	local heroY = math.max(hero / 2 + 40, designH * 0.36)
	local px, py = Preview.Width / 2, Preview.Inset + heroY * Preview.Scale
	local ray = pixelRay(Loader, cameraPos, target, px, py)
	if crack then
		-- the capsule at its biggest shake, the cracks lit in the rarest golem's color
		local capsule = GolemBuilder.capsule("Crystal")
		local legendary = Rarity.ById.Legendary.Color
		for _, d in capsule:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:sub(1, 5) == "Crack" or d.Name == "Band") then
				d.Transparency = 0
				d.Color = if d.Name == "Band" then legendary else legendary:Lerp(Color3.new(1, 1, 1), 0.3)
			end
		end
		local center = cameraPos + ray * 15.5
		local toward = Vector3.new(-look.X, 0, -look.Z).Unit
		-- its window (-Z) faces the camera; tipped by the shake
		capsule:PivotTo(CF.lookAt(center, center + toward) * CF.Angles(0, 0.4, 0.22))
		capsule.Parent = folder
		return
	end
	local golem = GolemBuilder.build(Preview.HeroGolem)
	local height = golem:GetAttribute("Height")
	-- the viewport camera frames the golem at 2.9 x its height + 1 with a 30 degree FOV:
	-- it fills 0.6 of the hero square, so stand it where it is that tall on screen
	local screenH = hero * Preview.Scale * height / (2 * (2.9 * height + 1) * math.tan(math.rad(15)))
	local distance = height * Preview.Height / (screenH * 2 * math.tan(math.rad(Preview.Fov) / 2))
	local center = cameraPos + ray * distance
	local flat = Vector3.new(-look.X, 0, -look.Z).Unit
	local feet = center - Vector3.new(0, height / 2, 0)
	-- facing the camera, turned a little (the viewport camera stands 0.32 rad aside)
	golem:PivotTo(CF.lookAt(feet, feet + flat) * CF.Angles(0, -0.32, 0) * CF.new(0, golem:GetAttribute("RootHeight"), 0))
	golem.Parent = folder
end

---------------------------------------------------------------- UI overlays

function Preview.buildUi(Loader: any, which: string): { [string]: any }
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local GolemView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemView")
	local UiExport = require("./uiexport")

	local scale, phone = Preview.Scale, Preview.PhoneScale
	local pcW, pcH = Preview.Width / scale, (Preview.Height - Preview.Inset) / scale
	local phW, phH = Preview.Width / phone, (Preview.Height - Preview.PhoneInset) / phone

	local function hud(uiScale: number, coins: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		BuildView.menuButton(refs.Menu)
		GolemView.menuButton(refs.Menu)
		refs.Coins.Text = Format.money(coins)
		refs.Income.Text = Format.perSecond(186)
		refs.Income.TextColor3 = Theme.Good
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		return refs
	end

	local function shop(uiScale: number, compact: boolean, w: number, h: number, lucky: boolean, tab: string): any
		local state = Preview.state(lucky)
		local refs = CapsuleView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		CapsuleView.layout(refs, compact, w, h)
		refs.Tab = tab
		CapsuleView.setCards(refs, CapsuleView.cards(state, state.Coins, false, Preview.Now))
		CapsuleView.setCoins(refs, state.Coins)
		CapsuleView.setHint(refs, `Click OPEN to wake golems{CapsuleView.Separator}Backspace: close`)
		return refs
	end

	local function opening(uiScale: number, compact: boolean, w: number, h: number, dim: boolean): any
		local o = CapsuleView.buildOpening(compact)
		o.Gui.Scale.Scale = uiScale
		o.Gui.Enabled = true
		CapsuleView.layoutOpening(o, compact, w, h)
		if not dim then
			o.Dim.BackgroundTransparency = 1 -- the scene's dim plane stands in for it
		end
		-- the renderer has no gradient transparency: a lighter uniform ray
		for _, ray in o.Rays:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundTransparency = 0.88
			end
		end
		return o
	end

	local function endButtons(o: any, again: string)
		o.Skip.Parent.Visible = false
		o.Ok.Parent.Visible = true
		o.Again.Parent.Visible = true
		o.Again.Text = again
		o.Hint.Text = ""
	end

	local function inventory(uiScale: number, compact: boolean, w: number, h: number, deleting: boolean, confirm: boolean?): any
		local state = Preview.state(false)
		local refs = GolemView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		GolemView.layout(refs, compact, w, h)
		local cards = GolemView.cards(state)
		local picked = if deleting then { [6] = true, [7] = true, [9] = true } else nil
		GolemView.setCards(refs, cards, if deleting then nil else 1, picked)
		GolemView.setEquipped(refs, GolemView.equipped(state), GolemView.totals(state))
		GolemView.setCount(refs, GolemView.countText(state), false)
		GolemView.setDetail(refs, cards[1])
		GolemView.setDeleteMode(refs, deleting, if deleting then 3 else 0)
		GolemView.setHint(refs, `Click a golem to see it{GolemView.Separator}Backspace: close`)
		if deleting then
			GolemView.setHint(refs, `Click the golems to delete{GolemView.Separator}Backspace: back`)
		end
		if confirm then
			GolemView.showConfirm(refs, GolemView.confirmText(cards, picked :: any))
		end
		return refs
	end

	local exports: { [string]: any } = {}
	if which == "capsules" then
		exports.ui_capsules_shop = UiExport.export({ hud(scale, 48250).Gui, shop(scale, false, pcW, pcH, false, "Stone").Gui })
		exports.ui_capsules_lucky = UiExport.export({ hud(scale, 2.4e6).Gui, shop(scale, false, pcW, pcH, true, "Crystal").Gui })
		exports.ui_capsules_phone = UiExport.export({ hud(phone, 48250).Gui, shop(phone, true, phW, phH, false, "Stone").Gui })

		-- an x10 Stone opening's grid (the rarest card framed white)
		local kinds = {
			"PebbleGolem",
			"CopperTinker",
			"QuartzSprite",
			"CoalChomper",
			"EmberImp",
			"TinTumbler",
			"PebbleGolem",
			"SilverSquire",
			"CopperTinker",
			"JadeGardener",
		}
		local function grid(uiScale: number, compact: boolean, w: number, h: number): any
			local o = opening(uiScale, compact, w, h, true)
			local best = CapsuleView.best(kinds)
			local bestIndex = table.find(kinds, best)
			CapsuleView.setGrid(o, kinds, { [3] = true, [5] = true, [10] = true }, bestIndex)
			for _, cell in o.Cells do
				cell.Frame.Visible = true
			end
			o.Grid.Visible = true
			o.Rays.Visible = false
			o.Counter.Text = "10 GOLEMS WOKE UP!"
			endButtons(o, `OPEN 10 AGAIN  {Format.money(22500)}`)
			return o
		end
		exports.ui_capsules_grid = UiExport.export({ grid(scale, false, pcW, pcH).Gui })
		exports.ui_capsules_grid_phone = UiExport.export({ grid(phone, true, phW, phH).Gui })

		exports.ui_golems = UiExport.export({ hud(scale, 48250).Gui, inventory(scale, false, pcW, pcH, false).Gui })
		exports.ui_golems_phone = UiExport.export({ hud(phone, 48250).Gui, inventory(phone, true, phW, phH, false).Gui })
		exports.ui_golems_delete = UiExport.export({ hud(scale, 48250).Gui, inventory(scale, false, pcW, pcH, true).Gui })
		exports.ui_golems_confirm = UiExport.export({ hud(scale, 48250).Gui, inventory(scale, false, pcW, pcH, true, true).Gui })

		-- the stall's odds board as the game fills it, at the board's 1.9 x 3.9 shape
		local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
		local gui = UIKit.screen("BoardInset", 50)
		gui.Scale.Scale = scale
		local frame = UIKit.new("Frame", {
			Name = "Board",
			Position = UDim2.fromOffset(pcW - 300, 60),
			Size = UDim2.fromOffset(19 * 14, 39 * 14),
			BackgroundColor3 = Color3.fromRGB(24, 28, 44),
			BorderSizePixel = 0,
		}, gui)
		UIKit.stroke(frame, 4, Color3.fromRGB(40, 150, 255))
		CapsuleView.fillBoard(frame, "Stone", false)
		exports.ui_capsule_board = UiExport.export({ gui })
	elseif which == "capsule_reveal" then
		local function reveal(uiScale: number, compact: boolean, w: number, h: number): any
			local o = opening(uiScale, compact, w, h, false)
			CapsuleView.setPlate(o, Preview.HeroGolem, true)
			CapsuleView.setRayColor(o, CapsuleView.rarityColor(Preview.HeroGolem))
			o.Note.Text = "TRIPLE LUCKY ODDS"
			endButtons(o, `OPEN 1 AGAIN  {Format.money(750000 * 2)}`)
			return o
		end
		exports.ui_capsule_reveal = UiExport.export({ reveal(scale, false, pcW, pcH).Gui })
		exports.ui_capsule_reveal_phone = UiExport.export({ reveal(phone, true, phW, phH).Gui })
	elseif which == "capsule_crack" then
		local o = opening(scale, false, pcW, pcH, false)
		o.Rays.Visible = false
		o.Hint.Text = `Click or Space to skip{CapsuleView.Separator}Backspace: skip all`
		exports.ui_capsule_crack = UiExport.export({ o.Gui })
	end
	local _ = GolemConfig
	return exports
end

-- export_scene entry: builds `scene` into workspace and returns its UI
-- overlays ("golems": the gallery alone; the others: the world first).
function Preview.build(Loader: any, workspace: any, scene: string): { [string]: any }
	if scene == "golems" then
		Preview.buildGallery(Loader, workspace)
		return {}
	end
	Loader.requirePath("ServerScriptService.Server.World.WorldBuilder").build(workspace)
	if scene == "capsules" then
		Preview.buildWorld(Loader, workspace)
	else
		Preview.buildHero(Loader, workspace, scene == "capsule_crack")
	end
	return Preview.buildUi(Loader, scene)
end

return Preview
