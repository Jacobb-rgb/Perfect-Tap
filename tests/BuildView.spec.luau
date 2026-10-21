-- BuildView (pure UI builder) under Lune: the tray cards, the slot chip,
-- reasons and which touch buttons each build mode shows; the machine info
-- card, the controls row (keycaps per device and mode), the tray's live
-- pictures and power chips, SHOP, the BUILD tile's key and badge.
local roblox = require("@lune/roblox") :: any
local Enum = roblox.Enum

return function(T, Loader)
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local MachineInfo = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineInfo")
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")

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

	local function has(text: string?, part: string): boolean
		return text ~= nil and string.find(text, part, 1, true) ~= nil
	end

	local function models(parent: any): number
		local n = 0
		for _, child in parent:GetChildren() do
			if child:IsA("Model") then
				n += 1
			end
		end
		return n
	end

	local function visible(button: any): boolean
		return button.Parent.Visible == true
	end

	T.test("BuildView: builds a card for every machine, hidden until owned", function()
		local refs = BuildView.build()
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.falsy(refs.Gui.Enabled, "starts closed")
		for _, machine in MachineData.List do
			local card = refs.Cards[machine.Id]
			T.truthy(card, "card " .. machine.Id)
			T.eq(card.Button.LayoutOrder, machine.Order, "MachineData order")
			T.falsy(card.Button.Visible, "hidden at first")
		end
	end)

	T.test("BuildView: setInventory shows owned machines with counts and the selection", function()
		local refs = BuildView.build()
		local picked = nil
		local onPick = function(id)
			picked = id
		end
		BuildView.setInventory(refs, { ClayFurnace = 2, Conveyor = 0, Anvil = 1, FutureMachine = 3 }, "Anvil", onPick)
		T.truthy(refs.Cards.ClayFurnace.Button.Visible, "furnace shown")
		T.eq(refs.Cards.ClayFurnace.Count.Text, "x2", "count")
		T.falsy(refs.Cards.Conveyor.Button.Visible, "zero count hidden")
		T.falsy(refs.Cards.Crusher.Button.Visible, "not owned hidden")
		T.eq(refs.Cards.Anvil.Stroke.Color, Theme.Accent, "selected card outlined")
		T.eq(refs.Cards.ClayFurnace.Stroke.Color, Theme.Outline, "others plain")
		T.falsy(refs.Empty.Visible, "not empty")
		T.truthy(refs.OnPick == onPick, "callback kept")
		refs.OnPick("Anvil")
		T.eq(picked, "Anvil", "callback works")
		BuildView.setInventory(refs, {}, nil, onPick)
		T.truthy(refs.Empty.Visible, "empty tray says so")
		for _, card in refs.Cards do
			T.falsy(card.Button.Visible, "all hidden")
		end
	end)

	T.test("BuildView: the slot chip and the reason line", function()
		local refs = BuildView.build()
		BuildView.setCounts(refs, 3, 10, 0, 40)
		T.eq(refs.Chip.Text, "MACHINES 3/10 - BELTS 0/40", "chip text")
		T.eq(refs.Chip.TextColor3, Theme.Text, "not full")
		BuildView.setCounts(refs, 10, 10, 0, 40)
		T.eq(refs.Chip.TextColor3, Theme.Accent, "full slots stand out")
		BuildView.setReason(refs, "Something is already there", "Bad")
		T.truthy(refs.Reason.Visible, "reason shown")
		T.eq(refs.Reason.TextColor3, Theme.Bad, "red")
		BuildView.setReason(refs, "Output blocked", "Warn")
		T.eq(refs.Reason.TextColor3, BuildView.ReasonColors.Warn, "yellow")
		BuildView.setReason(refs, nil)
		T.falsy(refs.Reason.Visible, "hidden")
		BuildView.setHint(refs, "R: rotate")
		T.truthy(refs.Hint.Visible, "hint shown")
		BuildView.setHint(refs, nil)
		T.falsy(refs.Hint.Visible, "hint hidden")
	end)

	T.test("BuildView: touch buttons per mode, big enough for thumbs", function()
		local refs = BuildView.build()
		local expected = {
			Idle = {},
			Placing = { Cancel = true, Rotate = true, Place = true },
			Selected = { Cancel = true, Move = true, PackUp = true },
			Moving = { Cancel = true, Rotate = true, PackUp = true, Place = true },
		}
		for mode, wanted in expected do
			BuildView.setMode(refs, mode, true)
			for _, name in { "Cancel", "Rotate", "Move", "PackUp", "Place" } do
				T.eq(visible(refs[name]), wanted[name] == true, `{mode} {name}`)
			end
			T.eq(refs.Actions.Visible, next(wanted) ~= nil, mode .. " action bar")
			-- no touch: no buttons, the tray is centred
			BuildView.setMode(refs, mode, false)
			T.falsy(refs.Actions.Visible, mode .. " hidden without touch")
			T.eq(refs.Tray.AnchorPoint.X, 0.5, "centred tray")
		end
		BuildView.setMode(refs, "Moving", true)
		T.eq(refs.Tray.AnchorPoint.X, 0, "tray moves left of the buttons")
		for _, name in { "Cancel", "Rotate", "Move", "PackUp", "Place", "Done" } do
			T.le(64, refs[name].Parent.Size.Y.Offset, name .. " at least 64 tall")
		end
		T.truthy(refs.Done.Parent.Visible, "Done always shown")
	end)

	T.test("BuildView: the Deck / Ground toggle shows on touch while the plot has platforms", function()
		local refs = BuildView.build()
		for _, mode in { "Idle", "Placing", "Selected", "Moving" } do
			BuildView.setMode(refs, mode, true, true)
			T.truthy(visible(refs.Layer), mode .. " toggle shown")
			T.truthy(refs.Actions.Visible, mode .. " action bar")
			BuildView.setMode(refs, mode, true, false)
			T.falsy(visible(refs.Layer), mode .. " no platforms: hidden")
			BuildView.setMode(refs, mode, false, true)
			T.falsy(visible(refs.Layer), mode .. " no touch: hidden (V / D-pad Up)")
		end
		T.le(64, refs.Layer.Parent.Size.Y.Offset, "thumb sized")
		BuildView.setLayer(refs, false)
		T.eq(refs.Layer.Text, BuildView.LayerText.Deck)
		BuildView.setLayer(refs, true)
		T.eq(refs.Layer.Text, BuildView.LayerText.Ground)
	end)

	T.test("BuildView: the HUD BUILD button", function()
		local refs = BuildView.build()
		local button = BuildView.menuButton(refs.Gui)
		T.eq(button.Text, "BUILD", "label")
		T.le(64, button.Parent.Size.Y.Offset, "tall enough")
	end)

	T.test("BuildView: the machine info card with its live picture (light and dark)", function()
		for _, light in { false, true } do
			withLight(light, function()
				local label = if light then "light" else "dark"
				local refs = BuildView.build()
				local card = refs.Info
				T.falsy(card.Frame.Visible, label .. ": hidden at first")
				BuildView.setInfo(refs, MachineInfo.describe("BrickFurnace"))
				T.truthy(card.Frame.Visible, label .. ": shown")
				T.eq(card.Name.Text, "Brick Furnace", label .. ": name")
				T.eq(card.Category.Text, "PROCESSING", label .. ": category")
				T.eq(card.Footprint.Text, "2x2 cells", label .. ": size")
				T.eq(card.Flow.Text, "Clean ore, Crushed ore -> Ingot · 4 s", label .. ": TAKES -> GIVES · n s")
				T.truthy(card.Power.Visible and has(card.Power.Text, "Needs 10 power"), label .. ": the power line")
				T.eq(card.Output.Text, MachineInfo.FrontText, label .. ": results out of the FRONT")
				T.eq(card.Description.Text, MachineData.ById.BrickFurnace.Description, label .. ": description")
				T.falsy(card.Note.Visible, label .. ": no note")
				T.eq(models(card.View), 1, label .. ": one live model")
				T.truthy(card.View:FindFirstChildOfClass("Camera"), label .. ": its camera")
				local model = card.Models.BrickFurnace
				T.falsy(model:GetAttribute("MachineId"), label .. ": not a real machine")
				for _, d in model:GetDescendants() do
					T.eq(#d:GetTags(), 0, label .. ": no tags (client effects ignore it)")
					if d:IsA("BasePart") then
						T.truthy(d.Anchored, label .. ": anchored")
					end
				end
				BuildView.setInfo(refs, MachineInfo.describe("BrickFurnace"), "Now: no power, runs at 60%")
				T.truthy(card.Note.Visible and has(card.Note.Text, "60%"), label .. ": the state now")
				BuildView.setInfo(refs, MachineInfo.describe("Conveyor"))
				T.eq(models(card.View), 1, label .. ": one picture at a time")
				T.falsy(card.Flow.Visible, label .. ": a belt has no job")
				T.falsy(card.Note.Visible, label .. ": the note goes")
				BuildView.setInfo(refs, MachineInfo.describe("BrickFurnace"))
				T.truthy(card.Models.BrickFurnace == model, label .. ": built once, reused")
				T.truthy(model.Parent == card.View, label .. ": back in the picture")
				BuildView.setInfo(refs, nil)
				T.falsy(card.Frame.Visible, label .. ": nil hides it")
			end)
		end
	end)

	T.test("BuildView: the controls row has keycaps for every device and mode", function()
		for _, kind in { "Mouse", "Gamepad", "Touch" } do
			for _, mode in { "Idle", "Placing", "Selected", "Moving" } do
				local keys = BuildView.keys(kind, mode)
				T.le(2, #keys, `{kind} {mode}: a row`)
				for _, k in keys do
					T.le(1, #k.Caps, `{kind} {mode}: a cap`)
					T.truthy(k.Text ~= "", `{kind} {mode}: what it does`)
					if kind == "Gamepad" then
						T.eq(#(k.Pads or {}), #k.Caps, `{kind} {mode} {k.Text}: a glyph per cap`)
					end
				end
			end
		end
		local function find(keys: any, cap: string): any
			for _, k in keys do
				if table.find(k.Caps, cap) then
					return k
				end
			end
			return nil
		end
		local placing = BuildView.keys("Mouse", "Placing")
		T.eq(find(placing, "LMB").Text, "Place", "[LMB] Place")
		T.eq(find(placing, "R").Text, "Rotate", "[R] Rotate")
		T.eq(find(placing, "RMB").Text, "Cancel", "[RMB] Cancel")
		T.eq(find(placing, "B").Text, "Done", "[B] Done")
		local selected = BuildView.keys("Mouse", "Selected")
		T.eq(find(selected, "M").Text, "Move", "[M] Move")
		T.truthy(find(selected, "LMB") == find(selected, "M"), "a click on the selected machine moves it too")
		T.eq(find(selected, "X").Text, "Pack up", "[X] Pack up")
		T.truthy(find(BuildView.keys("Touch", "Selected"), "MOVE"), "touch: the Selected hint")
		T.truthy(has(BuildView.keys("Mouse", "Placing", { Belt = true })[1].Text, "drag"), "belts: drag a line")
		local decks = BuildView.keys("Mouse", "Placing", { Decks = true })
		T.eq(decks[#decks].Caps[1], "V", "platforms: [V] Deck / ground")
		T.falsy(find(BuildView.keys("Mouse", "Idle", { Decks = true }), "V"), "not in Idle")
		local padDecks = BuildView.keys("Gamepad", "Moving", { Decks = true })
		T.eq(padDecks[#padDecks].Pads[1], Enum.KeyCode.DPadUp, "gamepad: D-pad Up")
		T.eq(#BuildView.keys("Keyboard", "Idle"), 0, "unknown device")
		local copy = BuildView.keys("Mouse", "Idle")
		table.insert(copy, copy[1])
		T.eq(#BuildView.keys("Mouse", "Idle"), #copy - 1, "a fresh list each time")
	end)

	T.test("BuildView: setKeys draws keycap chips (gamepad glyphs, fallback caps)", function()
		for _, light in { false, true } do
			withLight(light, function()
				local refs = BuildView.build()
				local keys = BuildView.keys("Mouse", "Moving")
				BuildView.setKeys(refs, keys)
				T.truthy(refs.Keys.Visible, "shown")
				local chips = BuildView.keyChips(refs)
				T.eq(#chips, #keys, "a chip per key")
				T.eq((chips[1]:FindFirstChild("Cap") :: any).Text, "LMB", "keycap")
				T.eq((chips[1]:FindFirstChild("Text") :: any).Text, "Put here", "what it does")
				T.le(16, (chips[1]:FindFirstChild("Text") :: any).TextSize, "readable")
				T.le(32, chips[1].Size.Y.Offset, "a phone-sized chip")
				BuildView.setKeys(refs, keys)
				T.truthy(BuildView.keyChips(refs)[1] == chips[1], "the same row rebuilds nothing")

				local pad = BuildView.keys("Gamepad", "Placing")
				BuildView.setKeys(refs, pad, function(key)
					return if key == Enum.KeyCode.ButtonX then "" else "rbxasset://glyph/" .. key.Name
				end)
				chips = BuildView.keyChips(refs)
				T.eq(#chips, #pad, "a chip per key")
				T.eq((chips[1]:FindFirstChild("Glyph") :: any).Image, "rbxasset://glyph/ButtonA", "the platform's own A")
				T.falsy(chips[1]:FindFirstChild("Cap"), "no text cap with a glyph")
				T.eq((chips[2]:FindFirstChild("Cap") :: any).Text, "X", "no glyph: the cap's name")
				BuildView.setKeys(refs, {})
				T.falsy(refs.Keys.Visible, "an empty row hides")
			end)
		end
	end)

	T.test("BuildView: tray cards show the live machine, its category and power chip", function()
		withLight(true, function()
			local refs = BuildView.build()
			local brick = refs.Cards.BrickFurnace
			T.truthy(brick.Picture, "a live picture (the icon sheets have no ids)")
			T.falsy(brick.Button:FindFirstChild("Fallback", true), "no emoji")
			T.eq(models(brick.Picture), 0, "built only when the card shows")
			T.eq((brick.Button:FindFirstChild("Category", true) :: any).Text, "PROCESSING", "category band")
			T.eq(brick.Power.Text, "⚡10", "power chip")
			T.eq(refs.Cards.WindTurbine.Power.Text, "+40⚡", "a generator's chip")
			T.falsy(refs.Cards.Crusher.Power, "no chip without power")
			local hovered = {}
			local onHover = function(id, on)
				hovered[id] = on
			end
			BuildView.setInventory(refs, { BrickFurnace = 1 }, nil, function() end, onHover)
			T.eq(models(brick.Picture), 1, "the machine in its card")
			T.truthy(brick.Picture:FindFirstChildOfClass("Camera"), "framed")
			T.eq(models(refs.Cards.Crusher.Picture), 0, "hidden cards build nothing")
			BuildView.setInventory(refs, { BrickFurnace = 2 }, "BrickFurnace", function() end, onHover)
			T.eq(models(brick.Picture), 1, "once per card")
			T.truthy(refs.OnHover == onHover, "hover callback kept")
			refs.OnHover("BrickFurnace", true)
			T.truthy(hovered.BrickFurnace, "hover reaches the controller")
		end)
		local dark = BuildView.build()
		T.eq(dark.Cards.BrickFurnace.Power.Text, "⚡10", "dark cards: power chip")
		T.falsy(dark.Cards.Crusher.Power, "dark cards: none without power")
	end)

	T.test("BuildView: an empty tray points to SHOP, and SHOP is always there", function()
		for _, light in { false, true } do
			withLight(light, function()
				local label = if light then "light" else "dark"
				local refs = BuildView.build()
				BuildView.setInventory(refs, {}, nil, function() end)
				T.truthy(refs.Empty.Visible, label .. ": empty")
				T.truthy(has(refs.Empty.Text, "SHOP"), label .. ": says where to buy")
				T.truthy(refs.EmptyShop.Parent.Visible, label .. ": with a SHOP button")
				BuildView.setInventory(refs, { Crusher = 1 }, nil, function() end)
				T.falsy(refs.EmptyShop.Parent.Visible, label .. ": not with machines")
				T.truthy(refs.Shop.Parent.Visible, label .. ": SHOP in the build HUD")
				for _, button in { refs.Shop, refs.EmptyShop } do
					-- the same sizes as the other buttons of each look (the dark ones 64 design units)
					if light then
						T.le(44, button.Parent.Size.Y.Offset * 0.62, label .. ": >= 44 pt on a phone")
					else
						T.le(64, button.Parent.Size.Y.Offset, label .. ": thumb sized")
					end
				end
			end)
		end
	end)

	T.test("BuildView: the BUILD tile shows its key and how many machines wait", function()
		for _, light in { false, true } do
			withLight(light, function()
				local label = if light then "light" else "dark"
				local menu = if light then HudView.build().Menu else BuildView.build().Gui
				local button = BuildView.menuButton(menu)
				local cap = button:FindFirstChild("KeyCap")
				T.truthy(cap, label .. ": a keycap")
				T.falsy(cap.Visible, label .. ": hidden until the controller knows the device")
				BuildView.setMenuKey(button, "B")
				T.truthy(cap.Visible, label .. ": shown")
				T.eq((cap:FindFirstChild("Text") :: any).Text, "B", label .. ": B")
				BuildView.setMenuKey(button, nil, "rbxasset://glyph/DPadUp")
				T.truthy((cap:FindFirstChild("Glyph") :: any).Visible, label .. ": a gamepad glyph")
				T.eq((cap:FindFirstChild("Glyph") :: any).Image, "rbxasset://glyph/DPadUp", label .. ": its image")
				BuildView.setMenuKey(button, nil, nil)
				T.falsy(cap.Visible, label .. ": touch: none")

				local count = MachineInfo.unplaced({ Crusher = 2, Conveyor = 5, CleaningStation = 0 })
				BuildView.setMenuBadge(button, count)
				local badge = button:FindFirstChild("Badge")
				T.truthy(badge, label .. ": a badge")
				T.eq((badge:FindFirstChildOfClass("TextLabel") :: any).Text, "7", label .. ": every unplaced machine")
				BuildView.setMenuBadge(button, 150)
				T.eq((button:FindFirstChild("Badge"):FindFirstChildOfClass("TextLabel") :: any).Text, "99+", label .. ": capped")
				BuildView.setMenuBadge(button, 0)
				T.falsy(button:FindFirstChild("Badge"), label .. ": none to place: no badge")
			end)
		end
	end)
end
