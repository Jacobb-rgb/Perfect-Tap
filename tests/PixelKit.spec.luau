-- The pixel reels' kit (owner 2026-10-22) under Lune: the shop's pass cards have no dead
-- buttons, prices keep their size through refreshes, square cards stay square, a label has
-- one size constraint, round labels stay round, the LEVEL UP rays have one writer, and
-- PixelFxController's pure parts. The round look (owner's UI pack reel, 2026-10-27;
-- PopTheme.Look): its fonts and the switch, window colours and icons, dark HUD tiles,
-- section headings, the confetti burst.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")
	local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
	local PixelFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.PixelFxController")
	local Confetti = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Confetti")

	-- Runs `check` in `look`, then the default look again (also when it fails).
	local DEFAULT_LOOK = PopTheme.Look
	local function inLook(look: string, check: () -> ())
		PopTheme.setLook(look)
		local ok, err = pcall(check)
		PopTheme.setLook(DEFAULT_LOOK)
		if not ok then
			error(`{look} look: {err}`, 0)
		end
	end

	T.test("Pixel shop: every button in a pass card is the card or its wired Price tag", function()
		for _, look in { "Pixel", "Round" } do
			inLook(look, function()
				local refs = StoreView.build()
				local items = 0
				for _, card in refs.Cards do
					if card.Spec.Look == "Item" then
						items += 1
						for _, d in card.Button:GetDescendants() do
							if d:IsA("GuiButton") then
								T.truthy(d == card.Price, card.Spec.Id .. ": " .. d:GetFullName() .. " is the wired Price")
							end
						end
						-- (the pixel look's second tilted tag is a picture; the round look has one price)
						local mirror = card.Button:FindFirstChild("PriceMirror")
						if look == "Pixel" then
							T.truthy(mirror ~= nil and not mirror:IsA("GuiButton"), card.Spec.Id .. " mirror is a picture")
						else
							T.eq(mirror, nil, card.Spec.Id .. ": one price")
						end
					end
				end
				T.truthy(items >= 6, "the pass cards")
			end)
		end
	end)

	T.test("Pixel shop: a price keeps its size when the shop refreshes it", function()
		local refs = StoreView.build()
		for id, card in refs.Cards do
			local amount = card.PriceAmount
			local before = amount.Size.X.Offset
			StoreView.setCard(refs, id, card.Key, "Buy")
			StoreView.setCard(refs, id, card.Key, "Buy")
			T.eq(amount.Size.X.Offset, before, id .. " price width")
		end
	end)

	T.test("Round shop: one list, two Gamepass cards a row, three Buy Cash cards, a short row centred", function()
		inLook("Round", function()
			local refs = StoreView.build()
			T.falsy((refs.Group:FindFirstChild("Tabs") :: any).Visible, "no tab column")
			T.eq(StoreView.sections()[1].Id, "Passes", "Gamepass first")
			T.eq(StoreView.sectionTitle(StoreView.sections()[2]), "Buy Cash")
			local half = (StoreView.CardsWidth - StoreView.Gap) / 2
			for _, card in refs.Cards do
				if card.Spec.Look == "Item" and card.State ~= "Hidden" then
					T.near(card.Button.Size.X.Offset, math.floor(half), 1, card.Spec.Id .. ": two a row")
				end
			end
			local third = math.floor((StoreView.CardsWidth - 2 * StoreView.Gap) / 3)
			T.near(refs.Cards.CoinsSmall.Button.Size.X.Offset, third, 1, "three cash cards a row")
			-- a hidden pass leaves five: the last one alone in its row, centred
			StoreView.setCard(refs, "Podiums", refs.Cards.Podiums.Key, "Hidden")
			local star = refs.Cards.Starbreaker
			local x = star.Button.Position.X.Offset
			T.near(x + star.Button.Size.X.Offset / 2, StoreView.CardsWidth / 2, 2, "Starbreaker centred")
		end)
	end)

	T.test("Pixel shop: pass cards are never wider than three a row (a short row is centred)", function()
		PopTheme.setLook("Pixel")
		local refs = StoreView.build()
		PopTheme.setLook(DEFAULT_LOOK)
		local third = (StoreView.CardsWidth - 2 * StoreView.Gap) / 3
		for _, card in refs.Cards do
			if card.Spec.Look == "Item" and card.State ~= "Hidden" then
				T.le(card.Button.Size.X.Offset, math.ceil(third), card.Spec.Id .. " width")
			end
		end
		local star = refs.Cards.Starbreaker
		if star and star.State ~= "Hidden" then
			local x = star.Button.Position.X.Offset
			T.near(x + star.Button.Size.X.Offset / 2, StoreView.CardsWidth / 2, 2, "Starbreaker centred")
		end
		T.eq(StoreConfig.ById.Train.Tag, "FAST TRAIN", "the train tag says what it does")
		T.truthy(MonetizationConfig.Products.TrainExpress ~= nil)
	end)

	T.test("Pixel kit: Pop.limit keeps one size constraint; Pop.round stays round", function()
		local holder = roblox.Instance.new("Frame")
		local label = Pop.text(holder, "LEVEL", 22, {})
		Pop.limit(label, 22, 12)
		local count = 0
		for _, c in label:GetChildren() do
			if c:IsA("UITextSizeConstraint") then
				count += 1
			end
		end
		T.eq(count, 1, "one constraint")
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		T.truthy(limit.MinTextSize >= PopTheme.PixelMin, "pixel floor")
		local status = Pop.text(holder, "", 20, {})
		Pop.round(status)
		T.eq(status:GetAttribute("Round"), true)
		status.Text = "Saved"
		Pop.sentence(status, 20)
		T.falsy(Pop.isPixel(status.FontFace), "a short text keeps a round label round")
		local word = Pop.text(holder, "", 20, {})
		T.eq(word.TextTruncate, roblox.Enum.TextTruncate.AtEnd, "a pixel word ends in ... below the floor")
		T.eq(Pop.wordSize(word), 20, "the build size")
	end)

	T.test("Pixel kit: the LEVEL UP rays are turned by LevelController only", function()
		local view = LevelView.build()
		T.eq(view.Rays:GetAttribute("PixelFx"), nil, "no PixelFx spin")
	end)

	T.test("PixelFxController: spin angle, gleam gaps and the on-screen test", function()
		T.near(PixelFx.spinAt(0), 0, 1e-6)
		T.near(PixelFx.spinAt(1), PixelFx.SpinSpeed, 1e-6)
		T.truthy(PixelFx.spinAt(1e6) < 360)
		T.eq(PixelFx.nextGap(0), PixelFx.GleamGap[1])
		T.eq(PixelFx.nextGap(1), PixelFx.GleamGap[2])
		T.eq(PixelFx.nextGap(5), PixelFx.GleamGap[2], "clamped")
		local zero, box = Vector2.new(0, 0), Vector2.new(100, 100)
		T.truthy(PixelFx.overlaps(Vector2.new(50, 50), box, zero, box), "overlap")
		T.falsy(PixelFx.overlaps(Vector2.new(0, 300), box, zero, box), "scrolled out below")
		T.falsy(PixelFx.overlaps(Vector2.new(0, -150), box, zero, box), "scrolled out above")
	end)

	T.test("Round look: the default; words and sentences are Fredoka One, the switch flips to pixel and back", function()
		T.eq(DEFAULT_LOOK, "Round", "the round look ships")
		T.truthy(string.find(PopTheme.Pixel.Family, "Montserrat", 1, true) ~= nil, "the reel's Montserrat")
		local holder = roblox.Instance.new("Frame")
		inLook("Round", function()
			local word = Pop.text(holder, "SHOP", 30, {})
			T.truthy(Pop.isPixel(word.FontFace), "a short text is a word")
			T.eq(word.FontFace.Family, PopTheme.Font.Family, "the same family as the sentences (Black words, Bold sentences)")
			T.eq(word.TextSize, 30, "drawn at its size (PixelScale 1)")
			local sentence = Pop.text(holder, "Spray the dirt off raw ore by hand", 18, {})
			T.falsy(Pop.isPixel(sentence.FontFace), "a long text is a sentence")
			T.eq(Pop.section("PASSES"), "- Passes -", "Title Case, the reel's - Gamepass -")
			T.eq(Pop.section("- Passes -"), "- Passes -", "never twice")
			T.eq(Pop.caption("HALL OF FAME"), "Hall of Fame")
			T.eq(Pop.caption("2X MONEY"), "2x Money")
			T.eq(Pop.caption("Already Fine"), "Already Fine", "small letters: left alone")
			T.truthy(Pop.edgeFor(30) > 3, "the thick dark edge")
		end)
		inLook("Pixel", function()
			local word = Pop.text(holder, "SHOP", 30, {})
			T.truthy(string.find(word.FontFace.Family, "PressStart2P", 1, true) ~= nil, "pixel words")
			T.eq(PopTheme.PixelScale, 0.74)
			T.eq(Pop.section("PASSES"), "PASSES", "no dashes")
			T.eq(Pop.caption("MY GOLEMS"), "MY GOLEMS", "the pixel look keeps its capitals")
		end)
		T.eq(PopTheme.Look, DEFAULT_LOOK, "back to the default")
	end)

	T.test("Round look: a window wears its own colour, its icon and the faded copy; Window = '' opts out", function()
		inLook("Round", function()
			local gui = roblox.Instance.new("ScreenGui")
			gui.Name = "TerraForgeSettings"
			local window = Pop.window(gui, "SETTINGS", Vector2.new(600, 400), 70, "Green")
			T.eq(window.Header:GetAttribute("WindowPaint"), "Concrete", "the reel's dark grey Settings")
			T.eq(window.Title.Text, "Settings", "Title Case")
			T.truthy(window.Header:FindFirstChild("Watermark", true) ~= nil, "the faded icon")
			T.truthy(window.Icon ~= nil and window.Icon:GetAttribute("Icon") == "cog", "the icon left of the title")
			for _, look in PopTheme.Windows do
				T.truthy(PopTheme.Paints[look.Paint] ~= nil, look.Paint .. " is a paint")
			end
			-- a red confirm box inside a window keeps its colour
			local box = roblox.Instance.new("Frame")
			box:SetAttribute("Window", "")
			box.Parent = gui
			local red = Pop.window(box, "SURE?", Vector2.new(400, 200), 60, "Red")
			T.eq(red.Header:GetAttribute("WindowPaint"), nil, "the box keeps its red band")
			T.eq(red.Icon, nil)
		end)
		inLook("Pixel", function()
			local gui = roblox.Instance.new("ScreenGui")
			gui.Name = "TerraForgeSettings"
			local window = Pop.window(gui, "SETTINGS", Vector2.new(600, 400), 70, "Green")
			T.eq(window.Header:GetAttribute("WindowPaint"), nil, "the pixel look keeps the view's colour")
			T.eq(window.Icon, nil)
			T.eq(window.Header:FindFirstChild("Watermark", true), nil)
		end)
	end)

	T.test("Round look: HUD tiles are dark with their colour on the lip; the pixel tiles keep their rays", function()
		local spec = { Name = "Golems", Label = "GOLEMS", Icon = "golem", Paint = "Purple", Size = 100 }
		inLook("Round", function()
			local face = Pop.tile(roblox.Instance.new("Frame"), spec)
			T.eq(face:GetAttribute("DarkTile"), true)
			T.eq(face:FindFirstChild("Rays", true), nil, "no sunburst on a dark tile")
			local paint = face:FindFirstChild("Paint") :: any
			local keys = paint.Color.Keypoints
			T.eq(keys[#keys - 1].Value, PopTheme.Paints.Purple.Bottom, "the lip in the tile's colour")
		end)
		inLook("Pixel", function()
			local face = Pop.tile(roblox.Instance.new("Frame"), spec)
			T.eq(face:GetAttribute("DarkTile"), nil)
			T.truthy(face:FindFirstChild("Rays", true) ~= nil, "the sunburst")
		end)
	end)

	T.test("Round HUD: the reel's eight tiles, the Shop in the top row, offers mid-right clear of the rest", function()
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")
		inLook("Round", function()
			local ids = {}
			for _, entry in HudBubble.gameMenu() do
				table.insert(ids, entry.Id)
			end
			T.eq(table.concat(ids, ","), "Store,Rebirth,Golems,Backpack,Wheel,Quests,Build,More", "the reel's order")
			for _, spec in { { 1280, 720, false }, { 1920, 1080, true }, { 1024, 768, false } } do
				local screen = Vector2.new(spec[1], spec[2])
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, spec[1])
				local where = `{spec[1]} x {spec[2]}`
				T.truthy(refs.TopBar:FindFirstChild("ShopPill"), where .. ": the Shop leads the top row")
				local offers = refs.Gui:FindFirstChild("Offers") :: any
				T.truthy(offers, where .. ": the offers")
				local w, h = spec[1] / scale, (spec[2] - 36) / scale
				local left = w - 16 - offers.Size.X.Offset
				local top = h * 0.5 - offers.Size.Y.Offset / 2
				T.truthy(top > refs.TopBar.Size.Y.Offset and top + offers.Size.Y.Offset < h, where .. ": on screen, under the top row")
				local bubble = TutorialView.layout(scale, screen, false, spec[3], nil)
				local by = bubble.Position.Y - bubble.AnchorPoint.Y * bubble.Height
				local bx = bubble.Position.X - bubble.AnchorPoint.X * bubble.Width
				local apart = by >= top + offers.Size.Y.Offset or bx + bubble.Width <= left
				T.truthy(apart, where .. ": the offers clear of the tutorial bubble")
				for _, holder in offers:GetChildren() do
					if holder:IsA("Frame") then
						T.truthy(holder:FindFirstChild("Offer"):FindFirstChild("Price"), holder.Name .. ": its R$ tag")
					end
				end
			end
			-- the Spin tile's badge (spins ready) is the reel's FREE! sticker; other tiles keep a count
			local refs = HudBubble.buildGame(1)
			local spin = HudBubble.claimTile(refs.Menu, "Wheel")
			HudBubble.setTileBadge(spin, 2)
			T.eq(spin:FindFirstChild("Sticker").Text, "FREE!")
			T.eq(spin:FindFirstChild("Badge"), nil)
			HudBubble.setTileBadge(spin, 0)
			T.eq(spin:FindFirstChild("Sticker"), nil)
			local golems = HudBubble.claimTile(refs.Menu, "Golems")
			HudBubble.setTileBadge(golems, 3)
			T.truthy(golems:FindFirstChild("Badge"), "a count badge")
		end)
	end)

	T.test("Confetti: bits start across the top, fall a while and are the same for a seed", function()
		local a = Confetti.pieces(Confetti.Count, 42)
		local b = Confetti.pieces(Confetti.Count, 42)
		T.eq(#a, Confetti.Count)
		for i, piece in a do
			T.truthy(piece.X >= 0 and piece.X <= 1, "on the screen")
			T.truthy(piece.Time >= Confetti.Fall[1] and piece.Time <= Confetti.Fall[2], "falls a while")
			T.truthy(piece.Delay >= 0 and piece.Delay <= Confetti.Stagger, "staggered")
			T.eq(piece.X, b[i].X, "the same bits for a seed")
		end
		T.truthy(Confetti.ReducedCount < Confetti.Count, "reduce motion: fewer bits")
	end)
end
