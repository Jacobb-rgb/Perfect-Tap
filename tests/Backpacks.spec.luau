-- The backpacks (owner 2026-10-24): ten packs worst to best (BackpackData, capacity 5 ->
-- 1000, coins only), their models from parts within budget (BackpackBuilder), their
-- effects (BackpackFx), the shop window (BackpackShopView) and the BACKPACKS stall.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
	local BackpackBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackBuilder")
	local BackpackFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackFx")
	local PictureModels = Loader.requirePath("ReplicatedStorage.Shared.Builders.PictureModels")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local ShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BackpackShopView")

	-- the saved ids (data.Backpacks, the inventory's migration): never rename or reorder
	local IDS = {
		"RookiePack",
		"TrailPack",
		"LeatherRucksack",
		"MinersPack",
		"IronboundPack",
		"ExplorersPack",
		"AmethystPack",
		"RuneboundPack",
		"EmberforgePack",
		"StarforgePack",
	}

	local function partsOf(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("backpacks: ten packs worst to best, capacity 5 -> 1000, prices rise, coins only", function()
		T.eq(#BackpackData.List, #IDS, "pack count")
		local lastCapacity, lastPrice = 0, -1
		for i, pack in BackpackData.List do
			T.eq(pack.Id, IDS[i], `pack {i} id`)
			T.eq(pack.Order, i, pack.Id .. " order")
			T.eq(BackpackData.ById[pack.Id], pack, pack.Id .. " by id")
			T.eq(BackpackData.Ids[i], pack.Id, pack.Id .. " in Ids")
			T.truthy(Rarity.ById[pack.Rarity] ~= nil, pack.Id .. " rarity")
			T.truthy(#pack.Name > 0 and #pack.Description > 0, pack.Id .. " has a name and a description")
			T.truthy(pack.Capacity > lastCapacity, pack.Id .. " holds more than the pack before")
			T.truthy(pack.Price > lastPrice, pack.Id .. " costs more than the pack before")
			lastCapacity, lastPrice = pack.Capacity, pack.Price
			for _, key in { "Body", "Panel", "Flap", "Trim", "Leather", "Buckle", "Roll", "Gem", "Glow" } do
				T.eq(typeof(pack.Colors[key]), "Color3", `{pack.Id} colour {key}`)
			end
			T.truthy(pack.Size.X > 1 and pack.Size.Y > 1 and pack.Size.Z > 0.5, pack.Id .. " size")
		end
		T.eq(BackpackData.StarterId, "RookiePack", "the starter")
		T.eq(BackpackData.List[1].Price, 0, "the starter is free")
		T.eq(BackpackData.List[1].Capacity, 5, "the start capacity (owner)")
		T.eq(BackpackData.List[#BackpackData.List].Capacity, 1000, "the top capacity (owner)")
	end)

	T.test("backpacks: capacity() reads a pack, anything else is the starter's", function()
		T.eq(BackpackData.capacity("RuneboundPack"), 400, "a pack")
		T.eq(BackpackData.capacity("StarforgePack"), 1000, "the best")
		T.eq(BackpackData.capacity("Nope"), 5, "unknown id")
		T.eq(BackpackData.capacity(nil), 5, "missing")
		T.eq(BackpackData.capacity(42), 5, "junk")
	end)

	T.test("backpacks: every pack builds within budget, worn and on display", function()
		for _, pack in BackpackData.List do
			for _, display in { false, true } do
				local model = BackpackBuilder.build(pack.Id, display)
				local label = pack.Id .. (if display then " (display)" else "")
				T.eq(model.Name, pack.Id, label .. " name")
				T.eq(model:GetAttribute("BackpackId"), pack.Id, label .. " attribute")
				local root = model.PrimaryPart
				T.truthy(root ~= nil and root.Name == "Root", label .. " Root")
				T.truthy(root.Transparency == 1, label .. " Root is invisible")
				T.truthy(root:FindFirstChild("Gem") ~= nil and root:FindFirstChild("Top") ~= nil, label .. " attachments")
				local parts = partsOf(model)
				T.le(#parts, BackpackBuilder.MaxParts, label .. " part budget")
				T.eq(model:GetAttribute("Parts"), #parts, label .. " Parts attribute")
				local bottom, top = model:GetAttribute("BottomY"), model:GetAttribute("TopY")
				T.truthy(type(bottom) == "number" and type(top) == "number" and bottom < 0 and top > bottom, label .. " height range")
				local straps = 0
				for _, p in parts do
					T.truthy(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, `{label} {p.Name} is pure decoration`)
					if p.Name == "ShoulderStrap" then
						straps += 1
					end
				end
				T.eq(straps, if display then 0 else 4, label .. " shoulder straps only when worn")
			end
		end
	end)

	T.test("backpacks: rig() unanchors every part and welds it to Root", function()
		local model = BackpackBuilder.build("RuneboundPack")
		BackpackBuilder.rig(model)
		for _, p in partsOf(model) do
			T.falsy(p.Anchored, p.Name .. " unanchored")
			T.truthy(p.Massless, p.Name .. " massless")
			if p ~= model.PrimaryPart then
				local weld = p:FindFirstChildOfClass("WeldConstraint")
				T.truthy(weld ~= nil and weld.Part0 == model.PrimaryPart, p.Name .. " welded to Root")
			end
		end
	end)

	T.test("backpack effects: every effect has its box, lights start off, lite halves the rates", function()
		local withFx = 0
		for _, pack in BackpackData.List do
			local spec = BackpackFx.Specs[pack.Id]
			local model = BackpackBuilder.build(pack.Id)
			local emitters, light = BackpackFx.apply(model)
			if not spec then
				T.eq(#emitters, 0, pack.Id .. " no effects")
				T.eq(light, nil, pack.Id .. " no light")
				continue
			end
			withFx += 1
			T.eq(#emitters, #spec.Effects, pack.Id .. " an emitter per effect (every box is there)")
			for i, e in emitters do
				T.eq(e.Parent:GetAttribute("FxBox"), spec.Effects[i].Box, `{pack.Id} effect {i} in its box`)
				T.eq(e.Rate, spec.Effects[i].Rate, `{pack.Id} effect {i} rate`)
			end
			if spec.Light then
				T.truthy(light ~= nil and light.Enabled == false and light.Shadows == false, pack.Id .. " light off, no shadows")
				T.le(light.Range, 10, pack.Id .. " a small light")
			end
			local lite = BackpackFx.apply(BackpackBuilder.build(pack.Id), true)
			T.eq(lite[1].Rate, spec.Effects[1].Rate * 0.5, pack.Id .. " lite rate")
		end
		T.eq(BackpackFx.Specs.RookiePack, nil, "the starter packs stay plain")
		T.truthy(withFx >= 8, "the richer packs have effects")
	end)

	T.test("backpack pictures: PictureModels builds every pack for the shop cards", function()
		for _, pack in BackpackData.List do
			local model, from = PictureModels.build("backpack_" .. pack.Id)
			T.truthy(model ~= nil, pack.Id .. " picture model")
			T.truthy(from.Z > 0, pack.Id .. " seen from behind the wearer (+Z)")
		end
	end)

	T.test("BackpackShopView: card states, texts and the owned set", function()
		local B = BackpackData.ById
		local none = {}
		T.eq(ShopView.cardState(B.TrailPack, none, "RookiePack", 249), "BuyLocked", "not enough coins")
		T.eq(ShopView.cardState(B.TrailPack, none, "RookiePack", 250), "Buy", "exactly enough")
		T.eq(ShopView.cardState(B.TrailPack, none, "RookiePack", 0 / 0), "BuyLocked", "NaN coins")
		T.eq(ShopView.cardState(B.TrailPack, { TrailPack = true }, "RookiePack", 0), "Equip", "owned")
		T.eq(ShopView.cardState(B.TrailPack, { TrailPack = true }, "TrailPack", 0), "Equipped", "equipped")
		T.eq(ShopView.priceText(B.RookiePack), "FREE", "the starter")
		T.eq(ShopView.priceText(B.MinersPack), Format.money(B.MinersPack.Price), "coin price")
		T.eq(ShopView.capacityText(B.StarforgePack), "1,000 ORE", "capacity")
		T.eq(ShopView.buttonText("Buy"), "BUY")
		T.eq(ShopView.buttonText("BuyLocked"), "BUY")
		T.eq(ShopView.buttonText("Equip"), "EQUIP")
		T.eq(ShopView.buttonText("Equipped"), "EQUIPPED")
		local set = ShopView.ownedSet({ "TrailPack", "Nope", 5 })
		T.truthy(set.TrailPack, "known ids")
		T.eq(set.Nope, nil, "unknown ids dropped")
		T.eq(next(ShopView.ownedSet("junk")), nil, "junk = nothing")
		local fromSet = ShopView.ownedSet({ MinersPack = true, Nope = true, TrailPack = false })
		T.truthy(fromSet.MinersPack and not fromSet.Nope and not fromSet.TrailPack, "a set works too (true only)")
		T.eq(ShopView.statusText("LeatherRucksack", 12, 30), "Your backpack: Leather Rucksack · 12 / 30 ore", "status")
		T.eq(ShopView.statusText("Nope", nil, nil), "Your backpack: Rookie Pack · 0 / 5 ore", "status without a record")
		for _, pack in BackpackData.List do
			T.truthy(ShopView.RarityPaints[pack.Rarity] ~= nil, pack.Id .. " card paint")
		end
		for _, reason in { "TooFar", "NoCoins", "Owned", "NotOwned", "BadId", "Locked" } do
			T.truthy(type(ShopView.Reasons[reason]) == "string", reason .. " has a line")
		end
	end)

	local function insidePanel(refs: any, label: string)
		local w = refs.Root.Size.X.Offset
		for _, card in refs.Cards do
			local p, s = card.Frame.Position, card.Frame.Size
			local left = refs.CardPage.Position.X.Offset + p.X.Offset - s.X.Offset / 2
			T.truthy(left >= 0 and left + s.X.Offset <= w + 0.5, `{label}: {card.Pack.Id} inside the panel`)
			local buttonTop = s.Y.Offset - 10 - card.Look.Holder.Size.Y.Offset
			for _, part in { card.PriceRow, card.SizeChip, card.RarityChip, card.Name, card.ArtBack } do
				T.le(part.Position.Y.Offset + part.Size.Y.Offset, buttonTop + 0.5, `{label}: {card.Pack.Id} {part.Name} above the button`)
				T.truthy(
					part.Position.X.Offset >= 0 and part.Position.X.Offset + part.Size.X.Offset <= s.X.Offset + 0.5,
					`{label}: {card.Pack.Id} {part.Name} inside the card`
				)
			end
		end
	end

	T.test("BackpackShopView: builds closed, a card per pack, two rows of five on a PC, phones scroll", function()
		local refs = ShopView.build()
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.eq(refs.Title.Text, "BACKPACKS", "title")
		T.truthy(refs.Root.SelectionGroup, "gamepad stays inside")
		T.eq(#refs.Cards, #BackpackData.List, "a card per pack")
		for i, card in refs.Cards do
			T.eq(card.Pack, BackpackData.List[i], "card order = pack order")
			local picture = card.Picture
			T.truthy(picture ~= nil, card.Pack.Id .. " live 3D pack")
			T.eq(picture:GetAttribute("Icon"), "backpack_" .. card.Pack.Id, card.Pack.Id .. " picture name")
			T.falsy(card.Face.Selectable, card.Pack.Id .. " the card is not a gamepad stop")
		end
		ShopView.layout(refs, false, 1600 / 1.25, 900 / 1.25)
		T.eq(refs.Columns, 5, "five a row")
		T.falsy(refs.Scrolls, "two rows fit a PC")
		insidePanel(refs, "PC")
		-- laptops under Roblox's 58 px top bar (HudController.uiScale): two rows, the footer pill on screen
		for _, screen in { { 1280, 720 }, { 1366, 768 }, { 1600, 900 }, { 1920, 1080 } } do
			local w, h = screen[1], screen[2]
			local scale = math.clamp(math.min(h / 720, w / 1100), 0.62, 1.25)
			local maxHeight = (h - 58) / scale
			ShopView.layout(refs, false, w / scale, maxHeight)
			local label = `{w} x {h}`
			T.falsy(refs.Scrolls, label .. ": two rows without scrolling")
			local root = refs.Root
			local bottom = maxHeight / 2 + root.Position.Y.Offset + root.Size.Y.Offset / 2
			T.le(bottom + refs.Footer.Size.Y.Offset / 2, maxHeight - 4, label .. ": the footer pill stays on screen")
			T.truthy(maxHeight / 2 + root.Position.Y.Offset - root.Size.Y.Offset / 2 >= 4, label .. ": the top stays on screen")
		end
		ShopView.layout(refs, true, 667 / 0.62, (375 - 36) / 0.62)
		T.truthy(refs.Compact and refs.Scrolls, "a phone: compact, the cards scroll")
		T.truthy(refs.Cards[1].Look.Holder.Size.Y.Offset >= 64, "phone buttons are big")
		insidePanel(refs, "phone")
		-- the equipped card: gold edge, halo, not selectable; owned ones show OWNED
		ShopView.setCards(refs, { RookiePack = true, TrailPack = true }, "TrailPack", 5000)
		local trail, rookie, leather = refs.Cards[2], refs.Cards[1], refs.Cards[3]
		T.eq(trail.State, "Equipped", "equipped")
		T.truthy(trail.Glow.Visible and not trail.Button.Selectable, "equipped look")
		T.truthy(rookie.Owned.Visible and not rookie.PriceRow.Visible, "owned shows OWNED")
		T.eq(leather.State, "Buy", "affordable")
		T.eq(ShopView.firstButton(refs), rookie.Button, "the gamepad lands on the first card you can use")
		ShopView.pose(refs, 0)
		T.falsy(refs.Cards[1].Frame.Visible, "closed pose hides the cards")
		ShopView.pose(refs, ShopView.OpenTime)
		T.truthy(refs.Cards[#refs.Cards].Frame.Visible, "open pose shows every card")
	end)

	T.test("BACKPACKS shop: the counter hook, the keeper's feet and every pack on display once", function()
		local Backpacks = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Backpacks")
		local Decor = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackShopDecor")
		local parent = roblox.Instance.new("Model")
		Backpacks.build(parent, Rng.new(7))
		local stall = parent:FindFirstChild("BackpackStall")
		T.truthy(stall ~= nil, "the shop model")
		local frame = stall:GetAttribute(Decor.FrameAttribute)
		T.eq(typeof(frame), "CFrame", "the shop frame for the clients' decor")
		local counters, parts = 0, 0
		local shown: { [string]: number } = {}
		local boxes = {}
		for _, d in stall:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:HasTag("BackpackCounter") then
					counters += 1
					T.truthy(d:FindFirstChild("BackpackPromptPoint") ~= nil, "the prompt point on the counter")
					local feet = d:FindFirstChild(Backpacks.KeeperFeet)
					T.truthy(feet ~= nil and feet:IsA("Attachment"), "the shopkeeper's feet on the counter")
					local local_ = frame:ToObjectSpace(d.CFrame * feet.CFrame)
					T.near(local_.Position.Y, Decor.Layout.Floor + 1.0, 0.01, "the feet stand on the step")
					T.truthy(local_.Position.Z > Decor.Layout.CounterZ + 1, "behind the counter")
					T.near(local_.LookVector.Z, -1, 0.01, "facing the customers (the gateway)")
				end
				local id = d:GetAttribute("BackpackId")
				if id ~= nil then
					local pack = BackpackData.ById[id]
					T.truthy(pack ~= nil, "a display marker names a pack")
					shown[id] = (shown[id] or 0) + 1
					T.eq(#d:GetTags(), 0, "display markers carry no tag (Plaza Life keeps miners off tagged parts)")
					T.eq(d.Parent, stall, "the markers sit in the shop model (the clients find them through the counter)")
					-- the pack's box where the clients stand it (centred on the plate, on its top)
					local scale = d:GetAttribute("DisplayScale") or 1
					local size = pack.Size * scale
					local c = frame:ToObjectSpace(d.CFrame * CFrame.new(0, d.Size.Y / 2 + size.Y / 2, 0))
					local function abs(v: any): any
						return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
					end
					local half = abs(c.RightVector * size.X / 2) + abs(c.UpVector * size.Y / 2) + abs(c.LookVector * size.Z / 2)
					table.insert(boxes, { Id = id, Min = c.Position - half, Max = c.Position + half, Spin = d:GetAttribute("DisplaySpin") })
				end
			end
		end
		T.eq(counters, 1, "one counter")
		for _, pack in BackpackData.List do
			T.eq(shown[pack.Id], 1, pack.Id .. " is on display once")
		end
		T.le(parts, 110, "the shell stays lean (the packs and the decor are the clients')")
		-- the packs keep clear of each other and of the walls (a turning one sweeps a circle)
		local L = Decor.Layout
		for i, a in boxes do
			if not a.Spin then
				local inside = a.Min.X >= -L.Width / 2 + L.Wall0 - 0.05 and a.Max.X <= L.Width / 2 - L.Wall0 + 0.05
				T.truthy(inside or a.Min.Z < L.FrontZ, a.Id .. " stands inside the walls")
			end
			for j = i + 1, #boxes do
				local b = boxes[j]
				local apart = a.Max.X <= b.Min.X
					or b.Max.X <= a.Min.X
					or a.Max.Y <= b.Min.Y
					or b.Max.Y <= a.Min.Y
					or a.Max.Z <= b.Min.Z
					or b.Max.Z <= a.Min.Z
				T.truthy(apart, a.Id .. " and " .. b.Id .. " don't overlap")
			end
		end
	end)

	T.test("BACKPACKS shop: its client-built packs and decor stay out of the phones' budget spots", function()
		-- (PhoneBudget.spec counts round the spawn and the plaza, DropperShop.spec at the
		-- DROPPERS door: none of them may hold this shop's client parts as well)
		local Backpacks = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Backpacks")
		local Droppers = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Droppers")
		local DropperShopBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperShopBuilder")
		local Decor = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackShopDecor")
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local parent = roblox.Instance.new("Model")
		Backpacks.build(parent, Rng.new(7))
		local house = Droppers.build(parent, Rng.new(7))
		local door = (house:GetAttribute(DropperShopBuilder.FrameAttribute) * CFrame.new(0, 0, DropperShopBuilder.Room.Front)).Position
		local spots = { Spawn = WorldLayout.SpawnPoint, Plaza = WorldLayout.Plaza.Center, DroppersDoor = door }
		local stall = parent:FindFirstChild("BackpackStall")
		for name, spot in spots do
			for _, d in stall:GetChildren() do
				if d:GetAttribute("BackpackId") then
					local range = d:GetAttribute("DisplayRange")
					T.eq(type(range), "number", d.Name .. " has its build range")
					T.truthy(
						(d.CFrame.Position - spot).Magnitude > range,
						`{d.Name} {d:GetAttribute("BackpackId")} is not built at the {name}`
					)
				end
			end
			local frame = stall:GetAttribute(Decor.FrameAttribute)
			T.truthy((frame.Position - spot).Magnitude > Decor.ShowRange, `the decor is not built at the {name}`)
		end
	end)

	T.test("BACKPACKS shop decor: built by the clients, inside the footprint, lights and dust off", function()
		local Decor = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackShopDecor")
		local frame = CFrame.new(46, 0, 74) * CFrame.Angles(0, math.pi / 2, 0)
		local model = Decor.build(frame)
		local parts, lights, emitters = 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.falsy(d.CanCollide or d.CanQuery or d.CanTouch, d.Name .. " is decor (no collisions, no queries)")
				T.truthy(d.Anchored, d.Name .. " anchored")
				local p = frame:PointToObjectSpace(d.CFrame.Position)
				T.truthy(math.abs(p.X) <= 8 and p.Y >= 0 and p.Y <= 16 and math.abs(p.Z) <= 6, d.Name .. " inside the shop's footprint")
			elseif d:IsA("PointLight") then
				lights += 1
				T.falsy(d.Enabled, "the lanterns' lights start off")
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
				T.falsy(d.Enabled, "the gate dust starts off")
			end
		end
		T.truthy(parts > 40, "plenty of small things")
		T.le(parts, Decor.MaxParts, "within the decor budget")
		T.eq(lights, 2, "two lantern lights")
		T.eq(emitters, 1, "one dust emitter")
	end)
end
