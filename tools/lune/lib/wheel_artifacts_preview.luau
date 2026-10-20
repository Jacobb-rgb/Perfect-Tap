--[[
	Preview-only setup for the wheel + artifacts package (step 7).
	  lune run tools/lune/export_scene.luau wheel_artifacts
	The world with:
	  plot 5    the museum (MuseumBuilder, as ArtifactService builds it) with a
	            mid-game collection: the Crown complete, the others partly found;
	            the plot's podiums in the Crown's Royal Velvet skin
	            (ArtifactService.paintYard, as for its owner)
	  gallery   every relic (ArtifactBuilder) on a plinth row high above the sea
	            (x 0, y 240), one row per collection, with its name on a tag
	  quarry    the found moment: the rock shattered into rubble, the new
	            relic (the one the banner shows, Last Train Ticket) hovering
	            over it
	UI overlays (the real views, filled like the controllers do):
	  ui_wheel            PC: the Spin & Win screen (Pop look): BUY SPINS, the
	                      wheel, the jackpot card, SPIN (3) (free + 2 bought)
	  ui_wheel_odds       PC: ALL ODDS (Details), Fast Spin on
	  ui_wheel_buy        PC: the buy step of x5 (every segment's odds, the price)
	  ui_wheel_restricted PC: paid random items restricted: no BUY SPINS rows
	  ui_wheel_won        PC: the wheel stopped, the prize card and confetti
	                      (the line back to its countdown, SPIN (2))
	  ui_wheel_wait       PC: spun today, no bought spins: SPIN (0)
	  ui_wheel_info       PC: a capsule row's details card (every golem's odds)
	  ui_wheel_phone      667 x 375 pt phone: the compact wheel screen
	  ui_wheel_phone_small 568 x 320 pt phone, the free spin in 14:44
	  ui_wheel_buy_phone  568 x 320 pt phone: the buy step of x10
	  ui_wheel_info_phone 568 x 320 pt phone: the details card
	  ui_wheel_won_phone  568 x 320 pt phone: a golem won
	  ui_chip             the HUD with the FREE SPIN! chip (no BOOK button: the side menu has the book)
	  ui_chip_phone       the same on a phone
	  ui_chip_phone_small 568 x 320 pt phone: the icon-only bar, the chip after it
	  ui_book             PC: the collection book, Railway tab (silhouettes)
	  ui_book_done        PC: the Crown tab, complete, its title + skin IN USE
	  ui_book_phone       phone: the collection book
	  ui_book_phone_small 568 x 320 pt phone: the icon beside the name, the
	                      lore and where it turns up in view
	  ui_book_restore     PC: the Railway with one artifact missing: RESTORE
	                      for shards and the detail's restore line
	  ui_story            PC: the journal, chapter 1 page 2
	  ui_story_phone      phone: the journal (a locked chapter selected)
	  ui_banner           PC: the small NEW ARTIFACT! banner over the HUD (keyboard keys)
	  ui_banner_phone     568 x 320 pt phone: the banner (no key row: shorter)
	  ui_reveal_complete  the COLLECTION COMPLETE card (the only big card)
	  ui_reveal_phone     568 x 320 pt phone: that card
	Shots: tools/preview/wheel_artifacts_shots.json (scene "wheel_artifacts").
]]

local UiExport = require("./uiexport")

local Preview = {}

Preview.Plot = 5
Preview.GalleryAt = { 0, 240, 0 }
Preview.NewFind = "LastTicket" -- the find the banner and the found moment show

-- a mid-game player's finds
Preview.Found = {
	CrownCoin = 3,
	RoyalSeal = 2,
	QueensBrooch = 1,
	ThroneFinial = 1,
	EmberScepter = 1,
	EmberCrown = 1,
	GoldenSpike = 2,
	ConductorWhistle = 1,
	RailLantern = 1,
	RoyalTimetable = 1,
	GolemCog = 4,
	SparkVial = 1,
	StarMapFragment = 1,
	EmberRune = 1,
	HeartstoneFragment = 1,
}

function Preview.build(Loader: any, workspace: any): { [string]: any }
	local newFindId = Preview.NewFind
	local roblox = Loader.roblox
	local C3 = roblox.Color3
	local V3 = roblox.Vector3
	local CF = Loader.CFrame
	local Instance = roblox.Instance
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local ArtifactBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ArtifactBuilder")
	local MuseumBuilder = Loader.requirePath("ServerScriptService.Server.World.MuseumBuilder")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")

	local artifacts = { Found = Preview.Found, Chapters = {} }

	-- the museum on plot 5's yard
	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[Preview.Plot])
	local plot = workspace:FindFirstChild("Plot_" .. Preview.Plot, true)
	local yard = plot and plot:FindFirstChild("Yard")
	local museum = MuseumBuilder.build(plotCF)
	museum.Parent = yard or workspace
	local shown = MuseumBuilder.show(museum, plotCF, artifacts)
	-- the owner's podium skin (the Crown is complete: Royal Velvet)
	local equipped = ArtifactConfig.equipped(artifacts)
	if yard and equipped then
		local painted = ArtifactService.paintYard(yard, ArtifactConfig.CollectionById[equipped].Reward.PodiumSkin)
		print(string.format("podium skin %s: %d parts", equipped, painted))
	end
	local structure = 0
	for _, d in museum:GetDescendants() do
		if d:IsA("BasePart") then
			structure += 1
		end
	end
	print(string.format("museum: %d parts with %d relics", structure, shown))

	-- the gallery: every relic on a plinth, one row per collection
	local gallery = Instance.new("Model")
	gallery.Name = "ArtifactGallery"
	gallery.Parent = workspace
	local g = Preview.GalleryAt
	local origin = CF.new(g[1], g[2], g[3])
	Geo.block(gallery, origin * CF.new(0, -0.5, 0), V3.new(30, 1, 22), C3.fromRGB(46, 40, 44))
	for row, collection in ArtifactConfig.Collections do
		local z = (row - 2.5) * 4.6
		for col, art in ArtifactConfig.ByCollection[collection.Id] do
			local x = (col - 3.5) * 4
			local base = origin * CF.new(x, 0, z)
			Geo.block(gallery, base * CF.new(0, 0.3, 0), V3.new(2.6, 0.6, 2.6), C3.fromRGB(70, 76, 98))
			local model = ArtifactBuilder.build(art.Id, base * CF.new(0, 0.6, 0) * CF.Angles(0, math.pi, 0), 1.25)
			if model then
				model.Parent = gallery
			end
		end
		Geo.block(gallery, origin * CF.new(-13.2, 0.4, z), V3.new(1.2, 0.8, 3.2), collection.Color, roblox.Enum.Material.Neon)
	end

	-- the found moment in the quarry: the rock shattered into rubble, the
	-- new relic (the banner's Last Train Ticket) hovering over it
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	for _, spawn in WorldBuilder.generateNodeSpawns() do
		if spawn.Zone == "Quarry" then
			local center = spawn.Position
			local rock = OreNodeBuilder.buildRock("Quarry", { "Copper", "Gold" }, CF.new(center), 11)
			rock.Parent = workspace
			local rng = Rng.new("shatter")
			local i = 0
			for _, part in rock:GetChildren() do
				if part:IsA("BasePart") then
					if part.Name == "Crack" or part.Name == "Moss" then
						part:Destroy()
					else
						-- a rubble piece: smaller, thrown out from the middle, lying on the ground
						i += 1
						local angle = i * 2.39996 + rng:range(-0.3, 0.3)
						local reach = rng:range(1.4, 3.4)
						local size = part.Size * 0.5
						part.Size = size
						part.CFrame = CF.new(center + V3.new(math.cos(angle) * reach, size.Y / 2 - 0.1, math.sin(angle) * reach))
							* CF.Angles(rng:range(-0.5, 0.5), rng:range(0, 6.28), rng:range(-0.5, 0.5))
					end
				end
			end
			-- the relic up out of the rubble, turned toward the camera, with the
			-- client's sparkle burst (Vfx "Glint") as a few tiny glowing bits
			local lift = center + V3.new(0, 3.6, 0)
			local relic = ArtifactBuilder.build(newFindId, CF.new(lift) * CF.Angles(0, -2.2, 0.12), 1.6)
			if relic then
				relic.Parent = workspace
			end
			for k = 1, 9 do
				local a = k * 2.39996
				local r = 1.2 + (k % 3) * 0.45
				Geo.block(
					workspace,
					CF.new(lift + V3.new(math.cos(a) * r, 0.4 + (k % 4) * 0.45, math.sin(a) * r)) * CF.Angles(a, a * 0.7, 0.4),
					V3.new(0.18, 0.18, 0.18),
					C3.fromRGB(255, 214, 130),
					roblox.Enum.Material.Neon
				)
			end
			print("found moment at", center)
			break
		end
	end

	return Preview.ui(Loader)
end

-- The HUD as HudController fills it (coins, income, empty carry slots),
-- drawn at `renderScale` (the 1600 x 900 render); the teleport bar is laid
-- out for the real uiScale and the screen width in pt it stands for (phones:
-- 0.62, the icon-only bar under 600 pt).
local function hud(Loader: any, renderScale: number, uiScale: number): any
	local roblox = Loader.roblox
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local refs = HudView.build()
	refs.Gui.Scale.Scale = renderScale
	refs.Coins.Text = Format.money(Preview.Coins)
	refs.Income.Text = Format.perSecond(Preview.Income)
	refs.Income.TextColor3 = roblox.Color3.fromRGB(110, 214, 92)
	refs.CarryLabel.Text = "CARRYING 0/3"
	for i = 1, 3 do
		HudView.slot(refs.CarrySlots, nil, i)
	end
	refs.Toasts:ClearAllChildren()
	TeleportView.build(refs.TopBar, uiScale, 1600 / renderScale * uiScale)
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	BuildView.menuButton(refs.Menu)
	-- (no BOOK button: with the side menu in the game its ARTIFACTS button is the book's one entry)
	return refs
end

Preview.Coins = 184500
Preview.Income = 640
Preview.BoughtSpins = 2 -- spins bought with Robux (the wheel shows SPIN (3) with the free one)
Preview.Wallet = { BlasterLevel = 4, Shards = 120 } -- RESTORE in the book

-- The wheel screen's info for a mid-game player (WheelController.info).
function Preview.wheelInfo(): any
	return {
		NoCapsules = false,
		Income = Preview.Income,
		Ore = { BlasterLevel = 4, BestIncome = 900, Vip = false },
		TripleLucky = false,
	}
end

function Preview.ui(Loader: any): { [string]: any }
	local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local exports: { [string]: any } = {}
	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone scaled up to the render
	local smallScale = 0.62 * 900 / 320 -- a 568 x 320 pt phone
	local phoneInset = math.floor(58 * 900 / 375)
	local smallInset = math.floor(58 * 900 / 320)
	-- the HUD for a render scale: phones run at the 0.62 uiScale floor
	local function hudAt(renderScale: number): any
		return hud(Loader, renderScale, if renderScale == scale then scale else 0.62)
	end

	local function wheel(uiScale: number, compact: boolean, maxW: number, maxH: number): any
		local refs = WheelView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		WheelView.setRows(refs, WheelView.rows(Preview.wheelInfo()))
		WheelView.layout(refs, maxW, maxH)
		-- the free spin ready and 2 bought spins: SPIN (3)
		WheelView.setReady(refs, true, 0, false, Preview.BoughtSpins)
		WheelView.setFast(refs, false)
		WheelView.setHint(refs, if compact then "Tap a row for details" else "Click a row for details  ·  Backspace: back")
		return refs
	end

	-- PC: ready
	local h1 = hudAt(scale)
	local w1 = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	exports.ui_wheel = UiExport.export({ h1.Gui, w1.Gui })

	-- PC: ALL ODDS (Details), Fast Spin on
	local h1b = hudAt(scale)
	local w1b = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	WheelView.setFast(w1b, true)
	WheelView.showOdds(w1b)
	WheelView.highlight(w1b, "OrePrize")
	exports.ui_wheel_odds = UiExport.export({ h1b.Gui, w1b.Gui })

	-- PC: the buy step of x5 (every segment's odds and what it pays, then the price)
	local h1d = hudAt(scale)
	local w1d = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	WheelView.showBuy(w1d, 5)
	WheelView.setHint(w1d, "The odds of every spin")
	exports.ui_wheel_buy = UiExport.export({ h1d.Gui, w1d.Gui })

	-- PC: where paid random items are restricted (no BUY SPINS rows; the free spin only)
	local h1c = hudAt(scale)
	local w1c = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	WheelView.setBuy(w1c, true)
	WheelView.setReady(w1c, true, 0, false, 0)
	exports.ui_wheel_restricted = UiExport.export({ h1c.Gui, w1c.Gui })

	-- PC: stopped on the Ore Prize, the prize card
	local h2 = hudAt(scale)
	local w2 = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	local index = WheelConfig.ById.OrePrize.Index
	w2.Disc.Rotation = WheelView.spinTarget(0, index, 8, 5, 0.15)
	-- after the free spin: the 2 bought spins are left, the line counts down to tomorrow's
	WheelView.setReady(w2, false, WheelConfig.CooldownSeconds - 6, false, Preview.BoughtSpins)
	WheelView.highlight(w2, "OrePrize")
	local prize, detail = WheelView.prizeText({ Kind = "Ore", DirtyOre = true })
	WheelView.showResult(w2, prize, detail, WheelView.faceColor(WheelConfig.ById.OrePrize.Index))
	WheelView.confetti(w2, 7)
	exports.ui_wheel_won = UiExport.export({ h2.Gui, w2.Gui })

	-- PC: spun today, no bought spins: SPIN (0) and the countdown
	local h3 = hudAt(scale)
	local w3 = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	WheelView.setReady(w3, false, 13 * 3600 + 42 * 60 + 10, false, 0)
	w3.Disc.Rotation = WheelView.restAngle(WheelConfig.ById.Shards.Index, 8)
	exports.ui_wheel_wait = UiExport.export({ h3.Gui, w3.Gui })

	-- PC: a capsule row's details card
	local h3b = hudAt(scale)
	local w3b = wheel(scale, false, 1600 / scale, (900 - 36) / scale)
	WheelView.showOdds(w3b)
	WheelView.showInfo(w3b, "StoneCapsule")
	WheelView.highlight(w3b, nil)
	exports.ui_wheel_info = UiExport.export({ h3b.Gui, w3b.Gui })

	-- phones
	local h4 = hudAt(phoneScale)
	local w4 = wheel(phoneScale, true, 1600 / phoneScale, (900 - phoneInset) / phoneScale)
	exports.ui_wheel_phone = UiExport.export({ h4.Gui, w4.Gui })
	local h5 = hudAt(smallScale)
	local w5 = wheel(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale)
	WheelView.setReady(w5, false, 14 * 60 + 44, false, 0)
	exports.ui_wheel_phone_small = UiExport.export({ h5.Gui, w5.Gui })
	local h5c = hudAt(smallScale)
	local w5c = wheel(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale)
	WheelView.showBuy(w5c, 10)
	WheelView.setHint(w5c, "The odds of every spin")
	exports.ui_wheel_buy_phone = UiExport.export({ h5c.Gui, w5c.Gui })
	local h5b = hudAt(smallScale)
	local w5b = wheel(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale)
	WheelView.showOdds(w5b)
	WheelView.showInfo(w5b, "CrystalCapsule")
	exports.ui_wheel_info_phone = UiExport.export({ h5b.Gui, w5b.Gui })
	-- the prize card on a small phone
	local h5d = hudAt(smallScale)
	local w5d = wheel(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale)
	w5d.Disc.Rotation = WheelView.spinTarget(0, WheelConfig.ById.CrystalCapsule.Index, 8, 5, -0.1)
	local prize2, detail2 = WheelView.prizeText({ Kind = "Capsule", Capsule = "Crystal", Golem = { Id = 3, Kind = "SapphireSage" } })
	WheelView.showResult(w5d, prize2, detail2, WheelView.faceColor(WheelConfig.ById.CrystalCapsule.Index))
	WheelView.confetti(w5d, 11)
	exports.ui_wheel_won_phone = UiExport.export({ h5d.Gui, w5d.Gui })

	-- the HUD chip
	local h6 = hudAt(scale)
	local chip = WheelView.buildChip(scale, 1600)
	chip.Gui.Scale.Scale = scale
	chip.Gui.Enabled = true
	exports.ui_chip = UiExport.export({ h6.Gui, chip.Gui })
	local h7 = hudAt(phoneScale)
	local chip2 = WheelView.buildChip(0.62, 667)
	chip2.Gui.Scale.Scale = phoneScale
	chip2.Gui.Enabled = true
	exports.ui_chip_phone = UiExport.export({ h7.Gui, chip2.Gui })
	-- a 568 x 320 phone: the icon-only bar, the chip right after it
	local h7b = hudAt(smallScale)
	local chip3 = WheelView.buildChip(0.62, 568)
	chip3.Gui.Scale.Scale = smallScale
	chip3.Gui.Enabled = true
	exports.ui_chip_phone_small = UiExport.export({ h7b.Gui, chip3.Gui })

	-- the collection book, the journal and the found card
	local CollectionView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CollectionView")
	local StoryView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoryView")
	local artifacts = { Found = Preview.Found, Chapters = {} }
	-- the newest find (the State push hasn't brought it yet)
	local newFind = { Artifact = Preview.NewFind, Count = 1, New = true, Collection = "RoyalRailway", Completed = false }

	local function bookView(
		uiScale: number,
		compact: boolean,
		maxW: number,
		maxH: number,
		collection: string,
		selected: string?,
		record: any?
	): any
		local refs = CollectionView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		refs.Collection = collection
		refs.Selected = selected
		CollectionView.layout(refs, maxW, maxH)
		CollectionView.fill(refs, record or artifacts, Preview.Wallet)
		refs.Hint.Text = if compact
			then "Tap a collection, then an artifact"
			else "Click a collection, then an artifact  ·  Backspace: close"
		return refs
	end
	local h8 = hudAt(scale)
	local b1 = bookView(scale, false, 1600 / scale, (900 - 36) / scale, "RoyalRailway", "RailLantern")
	exports.ui_book = UiExport.export({ h8.Gui, b1.Gui })
	local h9 = hudAt(scale)
	local b2 = bookView(scale, false, 1600 / scale, (900 - 36) / scale, "CrownOfKaldrum", "EmberCrown")
	exports.ui_book_done = UiExport.export({ h9.Gui, b2.Gui })
	local h10 = hudAt(phoneScale)
	local b3 = bookView(phoneScale, true, 1600 / phoneScale, (900 - phoneInset) / phoneScale, "HeartstoneLore", "HeartstoneFragment")
	exports.ui_book_phone = UiExport.export({ h10.Gui, b3.Gui })
	local h10b = hudAt(smallScale)
	local b4 = bookView(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, "Golemworks", "SparkVial")
	exports.ui_book_phone_small = UiExport.export({ h10b.Gui, b4.Gui })
	-- the Railway with the banner's find in: only the Locomotive Crest is missing
	local railway = { Found = table.clone(Preview.Found), Chapters = {} }
	railway.Found[Preview.NewFind] = 1
	local h10c = hudAt(scale)
	local b5 = bookView(scale, false, 1600 / scale, (900 - 36) / scale, "RoyalRailway", "LocomotiveCrest", railway)
	exports.ui_book_restore = UiExport.export({ h10c.Gui, b5.Gui })

	local function journalView(uiScale: number, compact: boolean, maxW: number, maxH: number, key: string, page: number): any
		local refs = StoryView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		StoryView.layout(refs, maxW, maxH)
		local entries = StoryView.entries(artifacts)
		refs.Key = key
		StoryView.setEntries(refs, entries, nil)
		StoryView.showPage(refs, StoryView.entry(entries, key) or entries[1], page)
		refs.Hint.Text = if compact then "Tap a chapter, then NEXT" else "Arrow keys: page  ·  Backspace: close"
		return refs
	end
	local h11 = hudAt(scale)
	local j1 = journalView(scale, false, 1600 / scale, (900 - 36) / scale, "CrownOfKaldrum", 2)
	exports.ui_story = UiExport.export({ h11.Gui, j1.Gui })
	local h12 = hudAt(phoneScale)
	local j2 = journalView(phoneScale, true, 1600 / phoneScale, (900 - phoneInset) / phoneScale, "Golemworks", 1)
	exports.ui_story_phone = UiExport.export({ h12.Gui, j2.Gui })

	-- the NEW ARTIFACT! banner (not modal) over the HUD
	local h13 = hudAt(scale)
	local banner = CollectionView.buildBanner(false)
	banner.Gui.Scale.Scale = scale
	-- (as the controller does it: the key row first, it sets the height)
	CollectionView.setBannerKeys(banner, "", "J: book", "", "Backspace: close")
	CollectionView.showBanner(banner, newFind, artifacts)
	exports.ui_banner = UiExport.export({ h13.Gui, banner.Gui })
	local h13b = hudAt(smallScale)
	local banner2 = CollectionView.buildBanner(true)
	banner2.Gui.Scale.Scale = smallScale
	CollectionView.setBannerKeys(banner2, "", "", "", "")
	CollectionView.showBanner(banner2, newFind, artifacts)
	exports.ui_banner_phone = UiExport.export({ h13b.Gui, banner2.Gui })

	-- the COLLECTION COMPLETE card (the State push with the find not there yet: 6 / 6 all the same)
	local stale = { Found = table.clone(Preview.Found), Chapters = {} }
	stale.Found.EmberCrown = nil
	local h14 = hudAt(scale)
	local card2 = CollectionView.buildReveal(false)
	card2.Gui.Scale.Scale = scale
	CollectionView.showReveal(
		card2,
		{ Artifact = "EmberCrown", Count = 1, New = true, Collection = "CrownOfKaldrum", Completed = true },
		stale
	)
	CollectionView.fitReveal(card2, 1600 / scale, (900 - 36) / scale)
	exports.ui_reveal_complete = UiExport.export({ h14.Gui, card2.Gui })
	local h15 = hudAt(smallScale)
	local card3 = CollectionView.buildReveal(true)
	card3.Gui.Scale.Scale = smallScale
	CollectionView.showReveal(
		card3,
		{ Artifact = "EmberCrown", Count = 1, New = true, Collection = "CrownOfKaldrum", Completed = true },
		stale
	)
	CollectionView.fitReveal(card3, 1600 / smallScale, (900 - smallInset) / smallScale)
	exports.ui_reveal_phone = UiExport.export({ h15.Gui, card3.Gui })

	return exports
end

return Preview
