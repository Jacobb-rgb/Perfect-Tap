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
		local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
		T.eq(refs.Title.Text, Pop.caption("BACKPACKS"), "title (Title Case in the round look)")
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

	T.test("BACKPACKS shop: its client-built packs and decor stay out of the phones' budget spots, even after a visit", function()
		-- (PhoneBudget.spec counts round the spawn and the plaza, DropperShop.spec at the
		-- DROPPERS door: none of them may hold this shop's client parts as well; a pack
		-- stays built until the player's HumanoidRootPart, ~3 studs over the ground, is
		-- its range + Decor.Hysteresis away; MARGIN: a player a few steps closer)
		local ROOT, MARGIN = Vector3.new(0, 3, 0), 3
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
		local markers = table.clone(stall:GetChildren())
		for _, d in parent:FindFirstChild("BackpackGolem"):GetChildren() do
			table.insert(markers, d)
		end
		for name, spot in spots do
			for _, d in markers do
				if d:GetAttribute("BackpackId") then
					local range = d:GetAttribute("DisplayRange")
					T.eq(type(range), "number", d.Name .. " has its build range")
					T.truthy(
						(d.CFrame.Position - (spot + ROOT)).Magnitude > range + Decor.Hysteresis + MARGIN,
						`{d.Name} {d:GetAttribute("BackpackId")} is not built (nor kept) at the {name}`
					)
				end
			end
			local frame = stall:GetAttribute(Decor.FrameAttribute)
			T.truthy(
				(frame.Position - (spot + ROOT)).Magnitude > Decor.ShowRange + Decor.Hysteresis + MARGIN,
				`the decor is not built (nor kept) at the {name}`
			)
		end
	end)

	--[[
		The phone budget at the shop (integrator 2026-10-24, review 2026-10-28):
		at its gateway and at its counter (the customer side, where a player
		stands to shop), every part within Workspace.StreamingTargetRadius,
		every Persistent model's parts beyond it and the yard museums (as
		PhoneBudget.spec counts), plus what a phone builds there: the shop's
		display packs within their DisplayRange (the DisplayLite ones lite:
		phones show those without their small details, inside the shop too),
		its decor, the DROPPERS showroom within DropperShopBuilder.ShowDistance
		and every shopkeeper golem within ShopkeeperConfig.HideDistance (one
		built on the way stays until then), stay under StreamParts.
	]]
	T.test(
		"BACKPACKS shop: what a phone holds at its gateway and its counter (streamed + its packs and decor + the DROPPERS showroom + the shopkeepers) stays under StreamParts",
		function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
			local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
			local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
			local MuseumBuilder = Loader.requirePath("ServerScriptService.Server.World.MuseumBuilder")
			local DropperShopBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperShopBuilder")
			local Decor = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackShopDecor")
			local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
			local GolemKeeper = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemKeeper")
			local project = serde.decode("json", fs.readFile("default.project.json"))
			local radius = project.tree.Workspace["$properties"].StreamingTargetRadius
			local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
			local shop = map:FindFirstChild("BackpackStall", true)
			local frame = shop:GetAttribute(Decor.FrameAttribute)
			local L = Decor.Layout
			local spots = {
				Gateway = (frame * CFrame.new(0, 0, L.PorchZ)).Position,
				Counter = (frame * CFrame.new(0, 0, L.CounterZ - 1.6)).Position,
			}
			local function persistent(model: any): boolean
				local ok, mode = pcall(function()
					return model.ModelStreamingMode.Name
				end)
				return ok and mode == "Persistent"
			end
			local museums = 0
			for _, plot in WorldLayout.Plots do
				museums += #partsOf(MuseumBuilder.build(WorldLayout.plotCFrame(plot)))
			end
			local markers = table.clone(shop:GetChildren())
			for _, d in map:FindFirstChild("BackpackGolem", true):GetChildren() do
				table.insert(markers, d)
			end
			local house = map:FindFirstChild("DroppersHouse", true)
			local houseFrame = house:GetAttribute(DropperShopBuilder.FrameAttribute)
			local showroomParts = #partsOf(DropperShopBuilder.build(houseFrame))
			local decorParts = #partsOf(Decor.build(frame))
			-- the shopkeeper spots (tagged Attachments on the counters) and their golems' parts
			local keepers: { { At: Vector3, Parts: number } } = {}
			for _, d in map:GetDescendants() do
				if d:IsA("Attachment") and d:HasTag(ShopkeeperConfig.Tag) and d.Parent and d.Parent:IsA("BasePart") then
					local feet = d.Parent.CFrame * d.CFrame
					local kind, size = ShopkeeperConfig.golem(d:GetAttribute("Shop"))
					table.insert(keepers, { At = feet.Position, Parts = #GolemKeeper.build(kind, feet, size).Parts })
				end
			end
			for name, spot in spots do
				local near, always = 0, 0
				local function walk(instance: any, persists: boolean)
					for _, child in instance:GetChildren() do
						if child:IsA("BasePart") then
							if (child.CFrame.Position - spot).Magnitude <= radius then
								near += 1
							elseif persists then
								always += 1
							end
						end
						walk(child, persists or (child:IsA("Model") and persistent(child)))
					end
				end
				walk(map, false)
				local packs = 0
				for _, d in markers do
					local id = d:GetAttribute("BackpackId")
					if id and (d.CFrame.Position - spot).Magnitude <= d:GetAttribute("DisplayRange") then
						local model = BackpackBuilder.build(id, true)
						packs += if d:GetAttribute("DisplayLite") then BackpackBuilder.lite(model) else #partsOf(model)
					end
				end
				local decor = if (frame.Position - spot).Magnitude <= Decor.ShowRange then decorParts else 0
				local showroom = if (houseFrame.Position - spot).Magnitude <= DropperShopBuilder.ShowDistance then showroomParts else 0
				local golems = 0
				for _, k in keepers do
					if (k.At - spot).Magnitude <= ShopkeeperConfig.HideDistance then
						golems += k.Parts
					end
				end
				local total = near + always + museums + packs + decor + showroom + golems
				T.le(
					total,
					LobbyLayout.Budget.StreamParts,
					`{name}: {near} within {radius} + {always} always-streamed + {museums} museum + {packs} packs + {decor} decor + {showroom} DROPPERS showroom + {golems} shopkeepers = {total}`
				)
			end
		end
	)

	T.test("BACKPACKS capacities: BackpackData.carried is the server's Bonuses.carryCapacity for every pack", function()
		local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
		-- (Deep Pockets is +10% a level; the reviewer's cases: DP III with Amethyst and Runebound, DP I with Rookie)
		for _, flat in { 0, 3 } do
			for _, pct in { 0, 0.1, 0.2, 0.3 } do
				for _, pack in BackpackData.List do
					local server = Bonuses.carryCapacity({ CarryCapacity = pack.Capacity + flat, CarryPct = pct } :: any, nil)
					local client = BackpackData.carried(pack.Capacity, { Flat = flat, Pct = pct, Double = false })
					T.eq(client, server, `{pack.Id} flat {flat} pct {pct}`)
					T.eq(
						BackpackData.carried(pack.Capacity, { Flat = flat, Pct = pct, Double = true }),
						server * 2,
						`{pack.Id} with Strong Back`
					)
				end
			end
		end
		T.eq(BackpackData.carried(400, nil), 400, "no bonus: the pack's own")
		T.eq(BackpackData.carried(275, { Flat = 0, Pct = 0.3, Double = false }), 358, "Amethyst with Deep Pockets III")
		T.eq(BackpackData.carried(400, { Flat = 0, Pct = 0.3, Double = true }), 1040, "Runebound with DP III and Strong Back")
		T.eq(ShopView.capacityText(BackpackData.ById.StarforgePack, { Flat = 0, Pct = 0.1, Double = false }), "1,100 ORE", "the card chip")
	end)

	T.test("BACKPACKS packs: no studs on worn or shown packs (their ClientBackpacks folder is skipped)", function()
		-- (StudStyle: the owner's 10-24 rule, only ground, roads, buildings, stalls and machines get studs)
		local StudStyle = Loader.requirePath("ReplicatedStorage.Shared.StudStyle")
		local game = roblox.Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local function packIn(folderName: string): (any, any)
			local folder = roblox.Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = workspace
			local pack = BackpackBuilder.build("RookiePack")
			for _, part in partsOf(pack) do
				part.MaterialVariant = "" -- (Lune has no default for it; Roblox's is "")
			end
			pack.Parent = folder
			return folder, pack
		end
		StudStyle.clearCache()
		-- (the check is real: the same pack in another folder would get studs)
		local _, loose = packIn("SomeFolder")
		local studded = 0
		for _, part in partsOf(loose) do
			if StudStyle.skipReason(part) == nil then
				studded += 1
			end
		end
		T.truthy(studded > 0, "a pack outside ClientBackpacks would get studs")
		local folder, worn = packIn("ClientBackpacks")
		for _, part in partsOf(worn) do
			T.truthy(StudStyle.skipReason(part) ~= nil, part.Name .. " stays smooth")
		end
		T.eq(StudStyle.applyTree(folder), 0, "nothing in ClientBackpacks gets studs")
	end)

	T.test("BACKPACKS packs: the lite look drops the small details, keeps the Root and the effect boxes", function()
		for _, pack in BackpackData.List do
			local full = #partsOf(BackpackBuilder.build(pack.Id, true))
			local model = BackpackBuilder.build(pack.Id, true)
			local left = BackpackBuilder.lite(model)
			T.eq(left, #partsOf(model), pack.Id .. " counts what is left")
			T.truthy(left < full and left >= full * 0.25, pack.Id .. " lite keeps the big shapes")
			T.truthy(model.PrimaryPart and model.PrimaryPart.Parent == model, pack.Id .. " keeps its Root")
			T.truthy(model:GetAttribute("Lite"), pack.Id .. " is marked lite")
			local boxes = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FxBox") then
					boxes += 1
				end
			end
			local before = 0
			for _, d in BackpackBuilder.build(pack.Id, true):GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FxBox") then
					before += 1
				end
			end
			T.eq(boxes, before, pack.Id .. " keeps its effect boxes")
		end
	end)

	T.test("BACKPACKS golem: by the porch with the Runebound pack's plate on its back", function()
		local Backpacks = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Backpacks")
		local parent = roblox.Instance.new("Model")
		Backpacks.build(parent, Rng.new(7))
		local g = parent:FindFirstChild("BackpackGolem")
		T.truthy(g ~= nil and g.PrimaryPart ~= nil, "the golem model")
		local plate = g:FindFirstChild("GolemPack")
		T.truthy(plate ~= nil, "the pack's plate")
		T.eq(plate:GetAttribute("BackpackId"), Backpacks.Golem.Pack, "its pack")
		T.eq(plate.Transparency, 1, "the plate is invisible")
		T.falsy(plate.CanCollide, "no collision")
		T.truthy(plate:GetAttribute("DisplayLite"), "phones see the lite pack")
		T.eq(#plate:GetTags(), 0, "no tag (Plaza Life)")
		-- the pack's outer face away from the golem (the plate faces its back)
		local body = g.PrimaryPart
		local away = (plate.CFrame.Position - body.CFrame.Position) * Vector3.new(1, 0, 1)
		T.truthy(plate.CFrame.LookVector:Dot(away.Unit) > 0.9, "the plate faces out of the golem's back")
		T.le(#partsOf(g), 20, "a lean golem")
	end)

	T.test("BACKPACKS shop decor: built by the clients, inside the footprint, lights and dust off", function()
		local Decor = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackShopDecor")
		local frame = CFrame.new(46, 0, 73) * CFrame.Angles(0, math.pi / 2, 0)
		local model = Decor.build(frame)
		local parts, lights, emitters = 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.falsy(d.CanCollide or d.CanQuery or d.CanTouch, d.Name .. " is decor (no collisions, no queries)")
				T.truthy(d.Anchored, d.Name .. " anchored")
				local p = frame:PointToObjectSpace(d.CFrame.Position)
				T.truthy(math.abs(p.X) <= 9 and p.Y >= 0 and p.Y <= 16 and math.abs(p.Z) <= 6, d.Name .. " inside the shop's footprint")
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
