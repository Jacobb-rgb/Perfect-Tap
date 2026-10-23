-- The pixel reels' kit (owner 2026-10-22) under Lune: the shop's pass cards have no dead
-- buttons, prices keep their size through refreshes, square cards stay square, a label has
-- one size constraint, round labels stay round, the LEVEL UP rays have one writer, and
-- PixelFxController's pure parts.
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

	T.test("Pixel shop: every button in a pass card is the card or its wired Price tag", function()
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
				local mirror = card.Button:FindFirstChild("PriceMirror")
				T.truthy(mirror ~= nil and not mirror:IsA("GuiButton"), card.Spec.Id .. " mirror is a picture")
			end
		end
		T.truthy(items >= 6, "the pass cards")
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

	T.test("Pixel shop: pass cards are never wider than three a row (a short row is centred)", function()
		local refs = StoreView.build()
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
end
