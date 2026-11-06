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
	    ui_capsules_small       568 x 320 pt phone (the odds list drops RARITY)
	    ui_capsules_royal       PC: ROYAL tab as it will look once two of its
	                            products are live (preview-only ids) and step 8
	                            takes receipts: OPEN 10 still "Coming soon"
	    ui_capsules_grid        PC: an x10 opening, its golems out (UI/HatchStage,
	                            the stage drawn live: PreviewLive)
	    ui_capsules_grid_phone  phone: the same
	    ui_golems               PC: the golem inventory, a golem selected
	    ui_golems_phone         phone: the inventory
	    ui_golems_small         568 x 320 pt phone: the inventory
	    ui_golems_delete        PC: delete mode, three golems picked (one bought
	                            with Robux and unlocked by the player)
	    ui_golems_confirm       PC: the confirm box before deleting (it says
	                            one was bought with Robux)
	    ui_capsule_board        the stall's odds board as the game fills it: an
	                            ENLARGED 2D overlay of the 1.9 x 3.9 stud board
	                            (labelled so on the picture)
	  scene "capsule_reveal"  the world (the opening shows it: nothing dims it)
	    ui_capsule_reveal       PC: a Mythic out of a Crystal egg, its name and
	                            1 in N (the opening's stage drawn live)
	    ui_capsule_reveal_phone phone: the same
	  scene "capsule_crack"   the same world
	    ui_capsule_crack        PC: the egg's cracks at their last step
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local Color3 = roblox.Color3
local Vector3 = roblox.Vector3
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

-- The render (tools/preview/render.mjs) and its UI scales.
Preview.Width = 1600
Preview.Height = 900
Preview.Fov = 50
Preview.Scale = 1.25 -- 900 px / 720 design units
Preview.Inset = 36 -- the PC top bar (render px)
Preview.PhoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone at the 0.62 floor
Preview.SmallScale = 0.62 * 900 / 320 -- a 568 x 320 pt phone
Preview.PhoneInset = 58

-- The reveal shots' golem (scene "capsule_reveal": out of a Crystal egg)
Preview.HeroGolem = "HeartstoneColossus"

-- A mid-game player (State snapshot shape).
Preview.Now = 1_800_000_000
function Preview.state(lucky: boolean?): { [string]: any }
	local owned = {}
	local kinds = {
		"RoseKnight",
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
		-- 1 and 5 locked; 4 (an Ember Imp) came from a Royal capsule, the player unlocked it
		table.insert(owned, { Id = i, Kind = kind, Locked = if i == 1 or i == 5 then true else nil, Paid = if i == 4 then true else nil })
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
	for r, info in CapsuleConfig.rarities() do -- (the golems' six: a "Secret" Rarity is for ores)
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
	for i, kind in { "GildedPorter", "RoseKnight", "CelestialSovereign" } do
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
	for i, kind in { "CelestialSovereign", "RoseKnight", "GildedPorter" } do
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
	local small = Preview.SmallScale
	local smW, smH = Preview.Width / small, (Preview.Height - Preview.PhoneInset) / small

	-- the HUD (its GOLEMS button only shows in a game without the side menu:
	-- the side menu's GOLEMS is the one entry, see sideMenu below)
	local function hud(uiScale: number, coins: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		BuildView.menuButton(refs.Menu)
		refs.Coins.Text = Format.money(coins)
		refs.Income.Text = Format.perSecond(186)
		refs.Income.TextColor3 = Theme.Good
		HudView.setBackpack(refs, 0, 5)
		return refs
	end

	-- the side menu (GOLEMS and SHOP first; phones: the MENU button, shut)
	local function sideMenu(uiScale: number): any
		local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
		local refs = SideMenuView.build()
		refs.Gui.Scale.Scale = uiScale
		local onPhone = uiScale == phone
		local layout = SideMenuView.layout(if onPhone then 0.62 else 1, if onPhone then phH else pcH, {
			Touch = onPhone,
			DesignWidth = if onPhone then phW else pcW,
		})
		SideMenuView.apply(refs, layout)
		SideMenuView.setSoon(refs, "Store", true)
		return refs
	end

	local function shop(uiScale: number, compact: boolean, w: number, h: number, lucky: boolean, tab: string, receipts: boolean?): any
		local state = Preview.state(lucky)
		local refs = CapsuleView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		CapsuleView.layout(refs, compact, w, h)
		refs.Tab = tab
		CapsuleView.setCards(refs, CapsuleView.cards(state, state.Coins, false, Preview.Now, nil, receipts))
		CapsuleView.setCoins(refs, state.Coins)
		CapsuleView.setHint(refs, `Click OPEN to wake golems{CapsuleView.Separator}Backspace: close`)
		return refs
	end

	-- The opening (CapsuleView.buildOpening) posed by the game's own HatchStage `at` seconds into an
	-- opening of `kinds` from `egg`; its full-screen stage drawn live by the preview (PreviewLive).
	local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
	local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local function opening(uiScale: number, compact: boolean, egg: string, kinds: { string }, at: (any) -> number): any
		local o = CapsuleView.buildOpening(compact)
		o.Gui.Scale.Scale = uiScale
		o.Controls.Scale.Scale = uiScale
		local inset = if compact then Preview.PhoneInset else Preview.Inset
		CapsuleView.layoutOpening(
			o,
			compact,
			Preview.Width / uiScale,
			Preview.Height / uiScale,
			{ Touch = compact, Inset = inset / uiScale }
		)
		o.Gui.Enabled = true
		o.Controls.Enabled = true
		CapsuleView.setAuto(o, true, false, if compact then "" else "G", nil)
		o.Stage:SetAttribute("PreviewLive", true)
		local eggs = {}
		for _ = 1, #kinds do
			local model = GolemBuilder.capsule(egg)
			HatchFx.addCracks(model, if compact and #kinds > 3 then 2 else 3)
			model:SetAttribute("Pooled", true)
			table.insert(eggs, HatchFx.record(model))
		end
		local run = HatchStage.new({
			Refs = o,
			Capsule = egg,
			Lucky = false,
			Kinds = kinds,
			Eggs = eggs,
			Fast = false,
			Reduced = false,
			Phone = compact,
			Target = Vector2.new(0.5, 0.86),
			Golem = function(kind: string): (any, number, number)
				local model = GolemBuilder.build(kind)
				return model, model:GetAttribute("Height") or 3, model:GetAttribute("RootHeight") or 1
			end,
			Claim = function(): boolean
				return true
			end,
		})
		local stop = at(run.Timeline)
		local t = 0
		while t < stop do
			t = math.min(stop, t + 1 / 30)
			HatchStage.pose(run, t)
		end
		return o
	end
	local function revealed(tl: any): number
		return tl.Reveal + tl.Times.GolemPop + 0.35
	end

	local function inventory(uiScale: number, compact: boolean, w: number, h: number, deleting: boolean, confirm: boolean?): any
		local state = Preview.state(false)
		local refs = GolemView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		GolemView.layout(refs, compact, w, h)
		local cards = GolemView.cards(state)
		local picked = if deleting then { [4] = true, [6] = true, [9] = true } else nil
		GolemView.setCards(refs, cards, if deleting then nil else 1, picked)
		GolemView.setEquipped(refs, GolemView.equipped(state), GolemView.totals(state))
		GolemView.setCount(refs, GolemView.countText(state), false)
		GolemView.setDetail(refs, cards[1])
		GolemView.setDeleteMode(refs, deleting, if deleting then 3 else 0)
		GolemView.setHint(refs, `Click a golem to see it{GolemView.Separator}P / Backspace: close`)
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
		exports.ui_capsules_shop =
			UiExport.export({ hud(scale, 48250).Gui, sideMenu(scale).Gui, shop(scale, false, pcW, pcH, false, "Stone").Gui })
		exports.ui_capsules_lucky = UiExport.export({ hud(scale, 2.4e6).Gui, shop(scale, false, pcW, pcH, true, "Crystal").Gui })
		exports.ui_capsules_phone = UiExport.export({ hud(phone, 48250).Gui, shop(phone, true, phW, phH, false, "Stone").Gui })
		exports.ui_capsules_small = UiExport.export({ hud(small, 48250).Gui, shop(small, true, smW, smH, false, "Stone").Gui })
		-- preview-only ids: x1 and x3 live, x10 still a placeholder
		local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
		local p1, p3 = MonetizationConfig.Products.RoyalCapsule1, MonetizationConfig.Products.RoyalCapsule3
		local old1, old3 = p1.Id, p3.Id
		p1.Id, p3.Id = 1, 3
		exports.ui_capsules_royal = UiExport.export({ hud(scale, 48250).Gui, shop(scale, false, pcW, pcH, false, "Royal", true).Gui })
		p1.Id, p3.Id = old1, old3

		-- an x10 Stone opening, its golems out
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
		local function grid(uiScale: number, compact: boolean): any
			return opening(uiScale, compact, "Stone", kinds, revealed)
		end
		local pcGrid = grid(scale, false)
		exports.ui_capsules_grid = UiExport.export({ pcGrid.Gui, pcGrid.Controls })
		local phoneGrid = grid(phone, true)
		exports.ui_capsules_grid_phone = UiExport.export({ phoneGrid.Gui, phoneGrid.Controls })

		exports.ui_golems = UiExport.export({ hud(scale, 48250).Gui, sideMenu(scale).Gui, inventory(scale, false, pcW, pcH, false).Gui })
		exports.ui_golems_phone =
			UiExport.export({ hud(phone, 48250).Gui, sideMenu(phone).Gui, inventory(phone, true, phW, phH, false).Gui })
		exports.ui_golems_small = UiExport.export({ hud(small, 48250).Gui, inventory(small, true, smW, smH, false).Gui })
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
		UIKit.label(gui, "ENLARGED VIEW of the\n1.9 x 3.9 stud odds board", 17, {
			Name = "OverlayNote",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(pcW - 300 + 19 * 7, 56),
			Size = UDim2.fromOffset(19 * 14, 44),
			TextColor3 = Color3.fromRGB(255, 230, 150),
		})
		exports.ui_capsule_board = UiExport.export({ gui })
	elseif which == "capsule_reveal" then
		local function reveal(uiScale: number, compact: boolean): any
			return opening(uiScale, compact, "Crystal", { Preview.HeroGolem }, revealed)
		end
		local pc = reveal(scale, false)
		exports.ui_capsule_reveal = UiExport.export({ pc.Gui, pc.Controls })
		local ph = reveal(phone, true)
		exports.ui_capsule_reveal_phone = UiExport.export({ ph.Gui, ph.Controls })
	elseif which == "capsule_crack" then
		local o = opening(scale, false, "Crystal", { Preview.HeroGolem }, function(tl: any): number
			return tl.Steps[3] + 0.1
		end)
		exports.ui_capsule_crack = UiExport.export({ o.Gui, o.Controls })
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
	end
	-- (capsule_reveal / capsule_crack: the world as it is; the opening draws its own stage)
	return Preview.buildUi(Loader, scene)
end

return Preview
