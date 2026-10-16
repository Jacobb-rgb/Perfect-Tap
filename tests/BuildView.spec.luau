-- BuildView (pure UI builder) under Lune: the tray cards, the slot chip,
-- reasons and which touch buttons each build mode shows.
return function(T, Loader)
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")

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

	T.test("BuildView: the HUD BUILD button", function()
		local refs = BuildView.build()
		local button = BuildView.menuButton(refs.Gui)
		T.eq(button.Text, "BUILD", "label")
		T.le(64, button.Parent.Size.Y.Offset, "tall enough")
	end)
end
