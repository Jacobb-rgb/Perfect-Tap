--[[
	The backpack on the client (owner 2026-10-24: everything you pick up
	goes into the backpack; docs/plans/OWNER_PLAYTEST_1024.md "4 + 5"):

	  BackpackState   State.Backpacks + the CarryCount / CarryCapacity
	                  attributes: stacks parsed (relics too, junk skipped),
	                  sorted, the attribute leading the snapshot, the
	                  capacity fallbacks, the prompt rules' predicates
	  prompt rules    Load Train / Put In (anything but a relic), Put On
	                  Podium (a cleaned ore), the machines' Put In (anything)
	  BackpackView    named frames, the merged Dirty Ore row that keeps its
	                  secret, relic rows, rows reused in place, FULL, empty;
	                  fits PC, phones, a tablet and a TV with a thumb-sized X
	  the HUD         one backpack button right of the blaster's hotbar slot
	                  in both looks: "n / cap", FULL, the key hint, clear of
	                  the slot, the money and the phone's jump button
	  controls        InteractController only picks up (no drop, no throw);
	                  Q / R1 open the window, B / Backspace close it; the
	                  window is a MenuPanels panel; nothing on the client
	                  sends CarryDrop / CarryThrow or reads CarriedBy
	  cleaning        the result card says where the clean ore went (Into)
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local function client(path: string): any
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client." .. path)
	end
	local BackpackState = client("Util.BackpackState")
	local BackpackView = client("UI.BackpackView")
	local HudView = client("UI.HudView")
	local HudBubble = client("UI.HudBubble")
	local CleaningView = client("UI.CleaningView")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")

	-- runs fn with BackpackView.DirtyByOre set, always switching it back
	local function withDirtyByOre(on: boolean, fn: () -> ())
		local before = BackpackView.DirtyByOre
		BackpackView.DirtyByOre = on
		local ok, err = pcall(fn)
		BackpackView.DirtyByOre = before
		if not ok then
			error(err, 0)
		end
	end

	local function key(kind: string, ore: string, grade: string?): string
		return ItemData.storageKey({ K = kind, O = ore, G = grade })
	end
	local COMMON = "Copper"
	local EPIC = "Diamond"
	local RELIC = ArtifactConfig.List[1].Id
	local RELIC_KEY = `Relic|{RELIC}||`
	T.eq(OreData.ById[EPIC].Rarity, "Epic", "the spec's Epic ore")

	-- a backpack holding everything once (10 readable items)
	local function items(): { [string]: number }
		return {
			[key("Raw", COMMON)] = 3,
			[key("Raw", EPIC)] = 2,
			[key("Clean", COMMON, "Rough")] = 1,
			[key("Clean", EPIC, "Pristine")] = 2,
			[key("Clean", EPIC, "Flawless")] = 1,
			[RELIC_KEY] = 1,
			["Clean|NoSuchOre||"] = 4, -- a newer build's ore: skipped
			["junk"] = 1,
			[key("Clean", COMMON, "Clean")] = 0, -- an empty stack
		}
	end
	local function state(over: { [string]: any }?): { [string]: any }
		local section = { Equipped = "TrailPack", Owned = { "RookiePack", "TrailPack" }, Count = 10, Capacity = 15, Items = items() }
		for k, v in over or {} do
			section[k] = v
		end
		return { Backpacks = section }
	end

	---------------------------------------------------------------- BackpackState

	T.test("Backpack client: BackpackState reads stacks, counts and capacities", function()
		local b = BackpackState.read(state())
		T.eq(b.Equipped, "TrailPack")
		T.eq(b.Name, BackpackData.ById.TrailPack.Name)
		T.eq(b.Count, 10, "the snapshot's count")
		T.eq(b.Capacity, 15)
		T.falsy(b.Full)
		T.eq(#b.Stacks, 6, "junk, unknown ores and empty stacks are skipped")
		-- dirty ore first (by key: never by the rarity it hides), the relic, then the rarest, best clean ore
		T.eq(b.Stacks[1].Desc.K, "Raw")
		T.eq(b.Stacks[2].Desc.K, "Raw")
		T.truthy(b.Stacks[1].Key < b.Stacks[2].Key, "dirty ore by key only")
		T.eq(b.Stacks[3].Desc.K, "Relic", "relics parse (ItemData.parseStoredKey)")
		T.eq(b.Stacks[3].Desc.O, RELIC)
		T.eq(b.Stacks[4].Key, key("Clean", EPIC, "Flawless"), "the rarest ore, the best grade first")
		T.eq(b.Stacks[5].Key, key("Clean", EPIC, "Pristine"))
		T.eq(b.Stacks[6].Key, key("Clean", COMMON, "Rough"))
		-- the attributes lead the snapshot
		local empty = BackpackState.read(state(), 0, 30)
		T.eq(empty.Count, 0, "CarryCount 0: empty even while the snapshot still lists items")
		T.eq(#empty.Stacks, 0)
		T.eq(empty.Capacity, 30, "CarryCapacity wins")
		T.truthy(BackpackState.read(state(), 15).Full, "full at the capacity")
		T.truthy(BackpackState.read(state(), 20).Full, "and over it (a smaller pack worn)")
		-- no Count in the snapshot: the readable stacks' sum
		T.eq(BackpackState.read(state({ Count = "x" })).Count, 10)
		-- nothing known: the starter pack, empty
		for _, junk in { nil, 5, {}, { Backpacks = "x" } } do
			local fresh = BackpackState.read(junk)
			T.eq(fresh.Equipped, BackpackData.StarterId)
			T.eq(fresh.Count, 0)
			T.eq(fresh.Capacity, BackpackData.capacity(BackpackData.StarterId), "the starter pack's capacity")
		end
		-- a newer build's pack id is kept; its capacity comes from the snapshot
		local future = BackpackState.read(state({ Equipped = "FuturePack", Capacity = 2000 }))
		T.eq(future.Equipped, "FuturePack")
		T.eq(future.Name, "Backpack")
		T.eq(future.Capacity, 2000)
		T.eq(
			BackpackState.read(state({ Equipped = "FuturePack", Capacity = 0 })).Capacity,
			BackpackData.capacity(nil),
			"else the starter's"
		)
	end)

	T.test("Backpack client: the prompt rules read the backpack", function()
		local TrainController = client("Controllers.TrainController")
		-- (the Pen and Podium controllers load the world's effects: their rules are read from the source)
		local penSource = fs.readFile(Loader.root .. "/src/client/Controllers/PenController.luau")
		local podiumSource = fs.readFile(Loader.root .. "/src/client/Controllers/PodiumController.luau")
		T.truthy(
			penSource:find("return BackpackState.has(BackpackState.notRelic, backpack)", 1, true),
			"PenController.canPutIn: anything but a relic"
		)
		T.truthy(penSource:find("PenController.canPutIn(BackpackState.get())", 1, true), "the Put In prompt asks it")
		T.truthy(penSource:find("BackpackState.onChanged(refreshPrompts)", 1, true), "refreshed on CarryCount and State pushes")
		T.truthy(
			podiumSource:find("return BackpackState.has(BackpackState.podiumOre, backpack)", 1, true),
			"PodiumController.canPutOn: a cleaned ore"
		)
		T.truthy(
			podiumSource:find("GetAttributeChangedSignal(BackpackState.CountAttribute)", 1, true),
			"refreshed on CarryCount (and State pushes)"
		)
		local PenController = {
			canPutIn = function(b: any): boolean
				return BackpackState.has(BackpackState.notRelic, b)
			end,
		}
		local PodiumController = {
			canPutOn = function(b: any): boolean
				return BackpackState.has(BackpackState.podiumOre, b)
			end,
		}
		local full = BackpackState.read(state())
		local relicOnly = BackpackState.read({ Backpacks = { Count = 1, Capacity = 5, Items = { [RELIC_KEY] = 1 } } })
		local dirtyOnly = BackpackState.read({ Backpacks = { Count = 2, Capacity = 5, Items = { [key("Raw", COMMON)] = 2 } } })
		local stale = BackpackState.read(state(), 0) -- CarryCount 0, an older snapshot
		local loading = BackpackState.read({ Backpacks = { Count = 0, Items = {} } }, 1) -- CarryCount first, items not here yet
		-- Load Train / Put In: anything but a relic
		T.truthy(TrainController.canLoad(full), "Load Train: ore inside")
		T.truthy(TrainController.canLoad(dirtyOnly))
		T.falsy(TrainController.canLoad(relicOnly), "a relic is never shipped")
		T.falsy(TrainController.canLoad(stale), "an empty backpack")
		T.falsy(TrainController.canLoad(loading), "until the State push brings the items")
		T.truthy(PenController.canPutIn(full), "Put In: ore inside")
		T.falsy(PenController.canPutIn(relicOnly), "a relic is never stored")
		T.falsy(PenController.canPutIn(stale))
		-- Put On Podium: a cleaned ore
		T.truthy(PodiumController.canPutOn(full), "cleaned ore inside")
		T.falsy(PodiumController.canPutOn(dirtyOnly), "dirty ore never goes on a podium")
		T.falsy(PodiumController.canPutOn(relicOnly))
		-- the Cleaning Station's vise: dirty ore or a relic
		T.truthy(BackpackState.has(BackpackState.cleanable, dirtyOnly))
		T.truthy(BackpackState.has(BackpackState.cleanable, relicOnly))
		T.falsy(
			BackpackState.has(
				BackpackState.cleanable,
				BackpackState.read({ Backpacks = { Count = 1, Items = { [key("Clean", EPIC, "Rough")] = 1 } } })
			)
		)
		T.falsy(BackpackState.has(nil, stale), "nothing in an empty backpack")
		-- the Load prompt follows the rule's answer; other prompts are left alone
		local load = Instance.new("ProximityPrompt")
		load:AddTag(TrainController.PromptTag)
		load:SetAttribute("Action", "Load")
		T.truthy(TrainController.applyLoadPrompt(load, false), "a Load prompt")
		T.falsy(load.Enabled, "nothing to load")
		TrainController.applyLoadPrompt(load, true)
		T.truthy(load.Enabled, "ore to load")
		for _, junk in { nil, 3, "true" } do
			TrainController.applyLoadPrompt(load, junk)
			T.falsy(load.Enabled, "junk is nothing to load")
		end
		local send = Instance.new("ProximityPrompt")
		send:AddTag(TrainController.PromptTag)
		send:SetAttribute("Action", "Send")
		T.falsy(TrainController.applyLoadPrompt(send, false), "Send is no Load prompt")
		T.truthy(send.Enabled, "and keeps showing")
		-- the machines' Put In: only while the backpack holds a kind that machine takes
		local PromptController = client("Controllers.PromptController")
		local ME = 7
		local function pack(items: any): any
			local n = 0
			for _, c in items do
				n += c
			end
			return BackpackState.read({ Backpacks = { Items = items } }, n, 30)
		end
		local raw = pack({ ["Raw|Coal||"] = 3 })
		local crushed = pack({ ["Crushed|Iron|Rough|"] = 2 })
		local clean = pack({ ["Clean|Gold|Pristine|"] = 1, ["Raw|Coal||"] = 1 })
		T.falsy(PromptController.loadShown(ME, "ClayFurnace", ME, raw), "a Furnace takes no dirty ore")
		T.truthy(PromptController.loadShown(ME, "ClayFurnace", ME, crushed), "it takes crushed ore")
		T.falsy(PromptController.loadShown(ME, "Crusher", ME, raw), "a Crusher takes no dirty ore")
		T.truthy(PromptController.loadShown(ME, "Crusher", ME, clean), "it takes clean ore")
		T.falsy(PromptController.loadShown(ME + 1, "Crusher", ME, clean), "never on someone else's machine")
		T.falsy(PromptController.loadShown(ME, "Crusher", ME, pack({})), "an empty backpack")
		T.truthy(PromptController.loadShown(ME, "FutureMachine", ME, raw), "a machine this build doesn't know: anything")
		local prompts = fs.readFile(Loader.root .. "/src/client/Controllers/PromptController.luau")
		T.truthy(prompts:find("BackpackState.onChanged(refreshAll)", 1, true), "refreshed on CarryCount and State pushes")
	end)

	---------------------------------------------------------------- BackpackView

	T.test("BackpackView: named frames, the merged Dirty Ore, relics, FULL and empty", function()
		withDirtyByOre(false, function()
			local refs = BackpackView.build()
			T.falsy(refs.Gui.Enabled, "built hidden")
			T.truthy(refs.Gui:GetAttribute("TerraForge"), "HudController scales it")
			for name, frame in
				{
					Window = refs.Window.Root,
					Title = refs.Title,
					Close = refs.Close,
					Body = refs.Window.Body,
					Info = refs.Info,
					PackName = refs.PackName,
					Bar = refs.Bar,
					CountLabel = refs.CountLabel,
					List = refs.List,
					Empty = refs.Empty,
					Footer = refs.Footer,
					ShopLine = refs.ShopLine,
					Hint = refs.Hint,
				}
			do
				T.eq(frame.Name, name, "a clear name for the style chat: " .. name)
			end
			T.eq(refs.Title.Text, if PopTheme.round() then BackpackView.RoundTitle else "BACKPACK", "the reel's Inventory (round look)")
			T.truthy(refs.ShopLine.Text:find("BACKPACKS shop", 1, true), "where bigger packs are sold")
			T.truthy(refs.Group.SelectionGroup, "the gamepad selection stays inside")

			local backpack = BackpackState.read(state())
			local made = BackpackView.setBackpack(refs, backpack)
			local rows = BackpackView.rows(refs)
			T.eq(#made, 5, "one row per stack, every dirty ore in one")
			T.eq(#rows, 5)
			T.eq(refs.PackName.Text, string.upper(BackpackData.ById.TrailPack.Name))
			T.eq(refs.CountLabel.Text, "10 / 15")
			T.near(refs.Bar:FindFirstChild("Fill").Size.X.Scale, 10 / 15, 1e-6, "the fill bar")
			T.eq(refs.Bar:FindFirstChild("Label").Text, "", "no FULL")
			-- Dirty Ore keeps its secret: one row, no ore name, no rarity, a fixed picture
			local dirty = rows[1]
			T.eq(dirty.Id, "Dirty")
			T.eq(dirty.ItemName.Text, ItemData.DirtyName)
			T.eq(dirty.Count.Text, "x5", "both dirty stacks")
			T.eq(dirty.Grade.Text, if PopTheme.round() then "Dirty" else "UNKNOWN")
			T.eq(dirty.Mystery.Visible, not PopTheme.round(), "a ? on the picture (the pixel look's rows)")
			T.eq(dirty.Entry.Rarity, nil, "no rarity paint")
			T.eq(
				dirty.Entry.Desc.O,
				BackpackView.entries({ { Key = key("Raw", EPIC), Desc = { K = "Raw", O = EPIC }, Count = 1 } })[1].Desc.O,
				"the same picture whatever it hides"
			)
			T.truthy(dirty.Frame.Selectable, "rows are selectable (a gamepad walks the list)")
			-- the relic
			T.eq(rows[2].ItemName.Text, ItemData.RelicName)
			T.eq(rows[2].Grade.Text, if PopTheme.round() then "Relic" else "RELIC")
			T.eq(rows[2].Entry.Rarity, nil, "no rarity hint before it is cleaned")
			-- cleaned ore: "Flawless Diamond", its grade chip, the count
			T.eq(rows[3].ItemName.Text, ItemData.displayName("Clean", EPIC, "Flawless"))
			T.eq(rows[3].Grade.Text, if PopTheme.round() then "Epic" else "FLAWLESS", "the rarity word (round) or the grade chip")
			T.eq(rows[3].Entry.Rarity, "Epic")
			T.eq(rows[4].Count.Text, "x2")
			T.falsy(rows[3].Mystery.Visible)
			for _, row in rows do
				T.truthy(row.Icon:FindFirstChild("Picture"), row.Id .. ": the live picture")
				T.eq(row.Frame.Parent, refs.List, "in the list")
			end
			T.falsy(refs.Empty.Visible)
			-- live: rows reused by id, gone ones removed, FULL
			local before = refs.Rows.Dirty.Frame
			local next = state({ Count = 15 })
			next.Backpacks.Items[key("Clean", COMMON, "Rough")] = nil
			local again = BackpackView.setBackpack(refs, BackpackState.read(next))
			T.eq(#again, 0, "no new rows")
			T.eq(refs.Rows.Dirty.Frame, before, "the same frame")
			T.eq(refs.Rows[key("Clean", COMMON, "Rough")], nil, "a stack that went is gone")
			T.eq(#BackpackView.rows(refs), 4)
			T.eq(refs.Bar:FindFirstChild("Label").Text, "FULL", "FULL on the bar")
			T.eq(refs.CountLabel.TextColor3, BackpackView.FullColor, "the count turns red")
			T.truthy(refs.Gui:GetAttribute("Full"))
			-- empty
			BackpackView.setBackpack(refs, BackpackState.read(state(), 0))
			T.eq(#BackpackView.rows(refs), 0, "no rows")
			T.truthy(refs.Empty.Visible, "the empty line")
			T.eq(BackpackView.firstRow(refs), nil)
			T.eq(refs.CountLabel.Text, "0 / 15")
		end)
	end)

	T.test("BackpackView: dirty ore keeps its secret by default; the DirtyByOre switch stacks it per ore", function()
		T.eq(BackpackView.DirtyByOre, false, "the default (owner 2026-10-28): one shared Dirty Ore stack")
		local merged = BackpackView.entries(BackpackState.read(state()).Stacks)
		T.eq(merged[1].Id, "Dirty", "one shared stack first")
		T.eq(merged[1].Name, ItemData.DirtyName, "no ore name")
		T.eq(merged[1].Piece, nil, "no piece of the ore")
		T.eq(merged[1].Rarity, nil, "no rarity")
		withDirtyByOre(true, function()
			local entries = BackpackView.entries(BackpackState.read(state()).Stacks)
			local dirty: { any } = {}
			for _, entry in entries do
				if entry.Dirty then
					table.insert(dirty, entry)
				end
			end
			T.eq(#dirty, 2, "one stack per ore")
			for i, entry in dirty do
				T.eq(entries[i], entry, "the dirty stacks lead")
				local ore = OreData.ById[entry.Piece]
				T.truthy(ore ~= nil, "the piece is that ore")
				T.eq(entry.Name, "Dirty " .. ore.Name)
				T.eq(entry.Id, key("Raw", entry.Piece), "the stack's own storage key: nothing new reaches the client")
				T.eq(entry.Desc.K, "Raw", "the crust chunk")
			end
			local counts: { [string]: number } = {}
			for _, entry in dirty do
				counts[entry.Piece] = entry.Count
			end
			T.eq(counts[COMMON], 3)
			T.eq(counts[EPIC], 2)
			local refs = BackpackView.build()
			BackpackView.setBackpack(refs, BackpackState.read(state()))
			local row = refs.Rows[key("Raw", EPIC)]
			T.truthy(row ~= nil, "a cell per dirty ore")
			T.truthy(row.Icon:FindFirstChild("Piece") ~= nil, "a piece of the real ore pokes out")
			T.falsy(row.Mystery.Visible, "no ? over it")
			T.eq(row.Count.Text, "x2")
			-- the search box filters by name
			if refs.Search then
				BackpackView.setSearch(refs, "diamond")
				for id, r in refs.Rows do
					T.eq(r.Frame.Visible, string.find(string.lower(r.Entry.Name), "diamond", 1, true) ~= nil, id .. " filtered")
				end
				BackpackView.setSearch(refs, "")
			end
		end)
	end)

	-- HudController.uiScale for a screen
	local function uiScale(size: any): number
		return math.clamp(math.min(size.Y / 720, size.X / 1100), 0.62, 1.25)
	end
	local SCREENS = {
		{ Name = "PC 1280x720", Size = Vector2.new(1280, 720), Touch = false },
		{ Name = "PC 1920x1080", Size = Vector2.new(1920, 1080), Touch = false },
		{ Name = "TV 1920x1080", Size = Vector2.new(1920, 1080), Touch = false, TenFoot = true },
		{ Name = "phone 667x375", Size = Vector2.new(667, 375), Touch = true },
		{ Name = "phone 568x320", Size = Vector2.new(568, 320), Touch = true },
		{ Name = "phone 844x390", Size = Vector2.new(844, 390), Touch = true },
		{ Name = "tablet 1024x768", Size = Vector2.new(1024, 768), Touch = true },
	}

	local function box(gui: any, parent: { number }): { number }
		local w = gui.Size.X.Scale * parent[3] + gui.Size.X.Offset
		local h = gui.Size.Y.Scale * parent[4] + gui.Size.Y.Offset
		local x = parent[1] + gui.Position.X.Scale * parent[3] + gui.Position.X.Offset - gui.AnchorPoint.X * w
		local y = parent[2] + gui.Position.Y.Scale * parent[4] + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
		return { x, y, w, h }
	end
	local function inside(a: { number }, b: { number }): boolean
		return a[1] >= b[1] - 0.01 and a[2] >= b[2] - 0.01 and a[1] + a[3] <= b[1] + b[3] + 0.01 and a[2] + a[4] <= b[2] + b[4] + 0.01
	end

	T.test("BackpackView: fits PC, phones, a tablet and a TV; a thumb-sized X", function()
		local refs = BackpackView.build()
		local many: { [string]: number } = {}
		for i, ore in OreData.List do
			if i <= 30 then
				many[key("Clean", ore.Id, "Pristine")] = i
			end
		end
		local backpack = BackpackState.read({ Backpacks = { Count = 400, Capacity = 400, Equipped = "RuneboundPack", Items = many } })
		BackpackView.setBackpack(refs, backpack)
		for _, screen in SCREENS do
			local scale = uiScale(screen.Size)
			local w, h = screen.Size.X / scale, (screen.Size.Y - 36) / scale
			local compact = BackpackView.compactFor(screen.Touch, screen.TenFoot == true, scale, screen.Size.Y)
			BackpackView.layout(refs, w, h, compact)
			local fit = BackpackView.fitScale(refs)
			local size = refs.Window.Root.Size
			local where = screen.Name
			T.truthy(size.X.Offset * fit <= w - 15 and size.Y.Offset * fit <= h - 15, where .. ": the window fits the screen")
			T.eq(refs.Compact, screen.Touch or screen.TenFoot == true, where .. ": compact on touch and TVs")
			-- the X: at least MinTouch points on a touch screen, after the fit shrink
			local close = refs.Close.Size.X.Offset * fit * scale
			if screen.Touch then
				T.truthy(close >= BackpackView.MinTouch, `{where}: the X is {close} pt`)
			end
			-- info, list and footer stacked inside the body
			local body = { 0, 0, size.X.Offset - 8, size.Y.Offset - refs.Window.Body.Position.Y.Offset - 4 }
			local info = box(refs.Info, body)
			local list = box(refs.List, body)
			local footer = box(refs.Footer, body)
			for name, part in { Info = info, List = list, Footer = footer } do
				T.truthy(inside(part, body), `{where}: {name} inside the body`)
			end
			T.truthy(info[2] + info[4] <= list[2], where .. ": the info row above the list")
			T.truthy(list[2] + list[4] <= footer[2] + 0.01, where .. ": the list above the footer")
			-- the info row: name, bar and count side by side
			local inner = { 0, 0, info[3], info[4] }
			local name, bar, count = box(refs.PackName, inner), box(refs.Bar, inner), box(refs.CountLabel, inner)
			T.truthy(name[1] + name[3] <= bar[1] and bar[1] + bar[3] <= count[1] + 0.01, where .. ": name, bar, count")
			-- the round look's cells: everything inside, the rarity over the picture over the
			-- name; a row of cells inside the list; a thumb wide and tall on a touch screen
			if PopTheme.round() then
				for _, row in BackpackView.rows(refs) do
					local cw, ch = row.Frame.Size.X.Offset, row.Frame.Size.Y.Offset
					local r = { 0, 0, cw, ch }
					local icon, itemName, grade, n = box(row.Icon, r), box(row.ItemName, r), box(row.Grade, r), box(row.Count, r)
					for label, part in { Icon = icon, ItemName = itemName, Grade = grade, Count = n } do
						T.truthy(inside(part, r), `{where} {row.Id}: {label} inside the cell`)
					end
					T.truthy(grade[2] + grade[4] <= icon[2] + 0.01, where .. ": the rarity over the picture")
					T.truthy(icon[2] + icon[4] <= itemName[2] + 0.01, where .. ": the picture over the name")
					T.truthy(
						BackpackView.Columns * cw + (BackpackView.Columns - 1) * BackpackView.CellGap <= list[3],
						where .. ": a row of cells fits"
					)
					if compact then
						T.truthy(
							math.min(cw, ch) * fit * BackpackView.PhoneScale >= BackpackView.MinTouch - 0.5,
							where .. ": cells a thumb big"
						)
					end
				end
				continue
			end
			-- every row: the picture, the name and the grade left of the count
			for _, row in BackpackView.rows(refs) do
				local r = { 0, 0, list[3] - 10, row.Frame.Size.Y.Offset }
				local icon, itemName, grade, n = box(row.Icon, r), box(row.ItemName, r), box(row.Grade, r), box(row.Count, r)
				for label, part in { Icon = icon, ItemName = itemName, Grade = grade, Count = n } do
					T.truthy(inside(part, r), `{where} {row.Id}: {label} inside the row`)
				end
				T.truthy(icon[1] + icon[3] <= itemName[1], where .. ": the picture left of the name")
				T.truthy(itemName[1] + itemName[3] <= n[1] + 0.01, where .. ": the name left of the count")
				if compact then
					T.truthy(
						row.Frame.Size.Y.Offset * fit * BackpackView.PhoneScale >= BackpackView.MinTouch - 0.5,
						where .. ": rows a thumb tall"
					)
				end
			end
		end
	end)

	---------------------------------------------------------------- the HUD

	-- runs fn with the light UI on or off, always switching it back
	local function withLight(on: boolean, fn: () -> ())
		local before = UIConfig.LightUI
		UIConfig.LightUI = on
		local ok, err = pcall(fn)
		UIConfig.LightUI = before
		if not ok then
			error(err, 0)
		end
	end

	T.test("Backpack HUD: one button right of the blaster slot says n / cap and FULL, in both looks", function()
		for _, light in { true, false } do
			withLight(light, function()
				local refs = HudView.build() :: any
				local look = if light then "light" else "dark"
				T.truthy(refs.Backpack and refs.Backpack:IsA("TextButton"), look .. ": the backpack button")
				T.truthy(refs.Backpack.Selectable, look .. ": a gamepad can select it")
				T.eq(refs.Backpack.Parent, refs.CarryPanel, look .. ": in the Carry holder (build mode hides it)")
				-- the blaster's slot: the light HUD's own BLASTER slot in the same holder, left of the
				-- button (owner 2026-10-28); the dark HUD keeps Roblox's hotbar slot
				if light then
					T.eq(refs.BlasterSlot and refs.BlasterSlot.Parent, refs.CarryPanel, "light: the BLASTER slot hides with it")
					T.eq(refs.Backpack.AnchorPoint.X, 1, "light: the button at the group's right end")
				else
					T.eq(refs.BlasterSlot, nil, "dark: Roblox's own hotbar slot")
				end
				T.eq(refs.CarryLabel.Parent, refs.Backpack, look .. ": its count")
				for _, gone in { "CarrySlots", "ThrowBar", "ThrowFill" } do
					T.eq(refs[gone], nil, look .. ": no " .. gone)
				end
				T.truthy(refs.Backpack:FindFirstChild("Pack"), look .. ": the pack's picture")
				HudView.setBackpack(refs, 3, 5)
				T.eq(refs.CarryLabel.Text, "3 / 5")
				T.falsy(refs.Backpack:FindFirstChild("Full").Visible, look .. ": not full")
				T.falsy(refs.Backpack:GetAttribute("Full"))
				local count = #refs.Backpack:GetDescendants()
				HudView.setBackpack(refs, 5, 5)
				T.truthy(refs.Backpack:FindFirstChild("Full").Visible, look .. ": FULL")
				T.eq(refs.CarryLabel.TextColor3, HudBubble.FullColor, look .. ": a red count")
				HudView.setBackpack(refs, 7, 5)
				T.truthy(refs.Backpack:GetAttribute("Full"), "over the capacity is full too")
				HudView.setBackpack(refs, 1000, 1000)
				T.eq(refs.CarryLabel.Text, "1000 / 1000", "the biggest pack")
				T.eq(#refs.Backpack:GetDescendants(), count, look .. ": updated in place")
				-- the key hint: a key, a glyph, or nothing (touch)
				local keyLabel, glyph = refs.Backpack:FindFirstChild("Key"), refs.Backpack:FindFirstChild("Glyph")
				HudView.setBackpackKey(refs, "Q", nil)
				T.truthy(keyLabel.Visible and keyLabel.Text == "Q" and not glyph.Visible, look .. ": Q")
				HudView.setBackpackKey(refs, "RB", "rbxasset://textures/ui/Controls/RB.png")
				T.truthy(glyph.Visible and not keyLabel.Visible, look .. ": the gamepad's glyph")
				HudView.setBackpackKey(refs, nil, nil)
				T.falsy(glyph.Visible or keyLabel.Visible, look .. ": nothing on touch")
			end)
		end
		-- the dark HUD: right of Roblox's own hotbar slot (60 px, 100 on a TV, drawn in real pixels) at every scale
		for _, scale in { 0.62, 0.8, 1, 1.25 } do
			T.truthy(HudBubble.backpackX(scale) * scale >= HudBubble.BlasterSlot / 2 + 5, `clear of the blaster's slot at {scale}`)
			T.truthy(HudBubble.backpackX(scale, true) * scale >= 50 + 5, `and of a TV's bigger slot at {scale}`)
			T.truthy(HudBubble.backpackX(scale) * scale <= HudBubble.BlasterSlot / 2 + 30, `next to it at {scale}`)
		end
		local refs = HudView.build()
		HudView.placeBackpack(refs, 0.62, false)
		T.eq(refs.CarryPanel.Position.X.Offset, HudBubble.backpackX(0.62), "placed for the new scale")
		-- the light HUD's group stays centred at any scale (design units, no Roblox slot to clear)
		withLight(true, function()
			local light = HudView.build()
			for _, scale in { 0.62, 1, 1.25 } do
				HudView.placeBackpack(light, scale, scale > 1)
				local holder = light.CarryPanel
				T.eq(2 * holder.Position.X.Offset + holder.Size.X.Offset, 0, `light: centred at {scale}`)
			end
		end)
		T.eq(HudView.backpackText(12, 30), "12 / 30")
		T.eq(HudView.backpackText(0 / 0, -1), "0 / 0", "junk reads 0")
	end)

	T.test("Backpack HUD: on phones the button is a thumb tall and clear of the money and the jump button", function()
		withLight(true, function()
			for _, screen in
				{ Vector2.new(568, 320), Vector2.new(667, 375), Vector2.new(844, 390), Vector2.new(932, 430), Vector2.new(1280, 720) }
			do
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, screen.X)
				-- (the light HUD's holder is the whole group: the BLASTER slot and the button)
				local holder = refs.CarryPanel
				local width = screen.X / scale
				local where = `{screen.X} x {screen.Y}`
				local left = width / 2 + holder.Position.X.Offset
				local right = left + holder.Size.X.Offset
				if scale <= HudBubble.CompactScale then
					T.truthy(holder.Size.Y.Offset * scale >= 44, where .. ": >= 44 pt tall")
					T.truthy(refs.Backpack.Size.Y.Offset * scale >= 44, where .. ": the button >= 44 pt tall")
					local slot = refs.BlasterSlot :: any
					T.truthy(slot.Size.X.Offset * scale >= 44 and slot.Size.Y.Offset * scale >= 44, where .. ": the slot >= 44 pt")
					-- Roblox's jump button: 70 px on small screens, 25 px from the right edge
					T.truthy(right * scale < screen.X - 95, `{where}: clear of the jump button ({right * scale})`)
				end
				local moneyRight = refs.CoinsPanel.Position.X.Offset + refs.CoinsPanel.Size.X.Offset
				T.truthy(moneyRight < left, where .. ": clear of the money")
				T.truthy(right <= width, where .. ": on screen")
			end
		end)
	end)

	T.test("Backpack HUD: the PC and TV tutorial bubble never covers the backpack button", function()
		local TutorialView = client("UI.TutorialView")
		withLight(true, function()
			for _, spec in
				{
					{ Vector2.new(1100, 720), false },
					{ Vector2.new(1024, 768), false },
					{ Vector2.new(1280, 720), false },
					{ Vector2.new(1600, 900), false },
					{ Vector2.new(1920, 1080), true },
				}
			do
				local screen, tenFoot = spec[1], spec[2]
				local scale = HudBubble.scaleFor(screen)
				local w, h = screen.X / scale, screen.Y / scale
				local refs = HudBubble.buildGame(scale, screen.X)
				HudBubble.placeBackpack(refs.CarryPanel, scale, tenFoot)
				local holder = refs.CarryPanel
				local packLeft = w / 2 + holder.Position.X.Offset
				local packTop = h - HudBubble.BackpackBottom - holder.Size.Y.Offset
				local layout = TutorialView.layout(scale, screen, false, tenFoot, nil)
				local left = layout.Position.X - layout.AnchorPoint.X * layout.Width
				local top = layout.Position.Y - layout.AnchorPoint.Y * layout.Height
				local apart = left >= packLeft + holder.Size.X.Offset or top + layout.Height <= packTop
				T.truthy(apart, `the bubble clear of the button at {screen.X} x {screen.Y}`)
				T.truthy(top >= 0, "and still on screen")
			end
		end)
	end)

	---------------------------------------------------------------- controls

	T.test("Backpack controls: pick up only, Q / R1 open the window, B / Backspace close it", function()
		local interact = fs.readFile(Loader.root .. "/src/client/Controllers/InteractController.luau")
		T.truthy(interact:find('Net.send("CarryPickup", target)', 1, true), "F / X / Grab put the target into the backpack")
		for _, gone in { "CarryDrop", "CarryThrow", "TerraForgeThrow", "KeyCode.Q", "ButtonR1", "ThrowBar" } do
			T.falsy(interact:find(gone, 1, true), "InteractController: no " .. gone)
		end
		T.truthy(interact:find("BackpackState.isFull()", 1, true), "a full backpack offers nothing to pick up")
		T.eq(Net.Events.CarryDrop, nil, "the server's contract: no drops")
		T.eq(Net.Events.CarryThrow, nil, "and no throws")
		T.truthy(Net.Events.CarryPickup, "pickups stay")
		-- nothing on the client sends a drop or a throw, or looks for an item in the hands
		local function walk(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk(Loader.root .. "/src/client", files)
		for _, path in files do
			local text = fs.readFile(path)
			for _, gone in { "CarryDrop", "CarryThrow", "CarriedBy" } do
				T.falsy(text:find(gone, 1, true), path .. " mentions " .. gone)
			end
		end
		-- the window: a MenuPanels panel in the client's ORDER, Q / R1 to open, B / Backspace to close
		-- (BackpackController reads Players.LocalPlayer when it loads: its source is checked)
		local MenuPanels = client("Util.MenuPanels")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/BackpackController.luau")
		T.truthy(source:find("BackpackController.Key = Enum.KeyCode.Q\n", 1, true), "Q (I would zoom Roblox's camera)")
		T.truthy(source:find("BackpackController.PadKey = Enum.KeyCode.ButtonR1\n", 1, true), "R1 (free since the throw went)")
		T.truthy(table.find(MenuPanels.Names, "BackpackController"), "one panel at a time")
		local init = fs.readFile(Loader.root .. "/src/client/init.client.luau")
		T.truthy(init:find('"BackpackController"', 1, true), "in the client's ORDER")
		T.truthy(
			source:find("BindAction(KEY_ACTION, onKey, false, BackpackController.Key, BackpackController.PadKey)", 1, true),
			"Q and R1, no touch button"
		)
		T.truthy(source:find("Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace", 1, true), "B / Backspace close it")
		T.truthy(
			source:find("if not isOpen and inCloseUp() then\n\t\treturn Enum.ContextActionResult.Pass", 1, true),
			"the keys pass in a close-up"
		)
		T.truthy(source:find("hud.Backpack.Activated:Connect", 1, true), "the HUD button opens it (click, tap, a gamepad's A)")
		-- Q is nobody else's on the client
		for _, path in files do
			if not path:find("BackpackController", 1, true) then
				T.falsy(fs.readFile(path):find("KeyCode%.Q[^%w]"), path .. " uses KeyCode.Q")
			end
		end
		T.truthy(source:find('return `{closeName or "B"}: close`', 1, true), "the gamepad's hint: B close")
		T.truthy(source:find('return `{keyName or "Q"} or Backspace: close`', 1, true), "the keyboard's: Q or Backspace")
	end)

	---------------------------------------------------------------- cleaning

	T.test("Backpack client: the cleaning card says where the clean ore went", function()
		T.eq(CleaningView.intoText("Backpack"), "In your backpack")
		T.truthy(CleaningView.intoText("Pen"):find("Ore Pen", 1, true), "a full backpack: the pen")
		T.eq(CleaningView.intoText("Sold"), "", "never sold any more (the server keeps it on the tray)")
		T.truthy(CleaningView.intoText("Tray"):find("tray", 1, true), "the station's tray")
		for _, junk in { nil, "Hands", 3 } do
			T.eq(CleaningView.intoText(junk), "", "nothing for anything else")
		end
		for _, touch in { false, true } do
			local view = CleaningView.build({ Touch = touch })
			CleaningView.setInto(view, "Pen")
			T.eq(view.CardInto.Text, CleaningView.intoText("Pen"))
			local card = { 0, 0, view.Card.Size.X.Offset, view.Card.Size.Y.Offset }
			local into = box(view.CardInto, card)
			local detail = box(view.CardDetail, card)
			local collect = box(view.Collect.Parent, card)
			T.truthy(detail[2] + detail[4] <= into[2], "under the detail line")
			-- (the button's face sits 5 units above its holder: UIKit.button's lip)
			T.truthy(into[2] + into[4] <= collect[2] - 5, "above the Collect button")
			T.truthy(inside(into, card), "inside the card")
		end
	end)
end
