-- BuildBubble (light build mode UI, pure builder) under Lune: a card per owned
-- machine with its count, touch buttons only on touch, phone sizes.
return function(T, Loader)
	local BuildBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildBubble")
	local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")

	local function data(touch: boolean)
		return {
			Machines = {
				{ Id = "Crusher", Name = "Crusher", Group = "Special", Count = 1 },
				{ Id = "Conveyor", Name = "Conveyor", Group = "Transport", Count = 24 },
			},
			Selected = "Crusher",
			Group = "All",
			Slots = "MACHINES 1/10",
			Reason = "Needs power",
			Hint = "R rotate",
			Touch = touch,
		}
	end

	T.test("BuildBubble: cards with counts, the selected one outlined", function()
		local refs = BuildBubble.build(1.25, data(false))
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.eq(refs.Cards.Conveyor:FindFirstChild("Chance", true):FindFirstChild("Text").Text, "x24", "count chip")
		T.eq(refs.Cards.Crusher:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Gold, "selected")
		T.truthy(refs.Reason and refs.Hint, "reason + key hint on PC")
		T.falsy(refs.Place, "no touch buttons with a mouse")
	end)

	T.test("BuildBubble: touch buttons on phones, >= 44 pt", function()
		local refs = BuildBubble.build(0.62, data(true))
		for _, key in { "Place", "Rotate", "Move", "PackUp", "Cancel" } do
			T.truthy((refs :: any)[key], "touch " .. key)
		end
		T.falsy(refs.Hint, "no key hint on touch")
		local layout = BuildBubble.layout(0.62)
		T.truthy(layout.Touch.Y * 0.62 >= 44, "touch buttons")
		T.truthy(layout.Group.Y * 0.62 >= 44, "group pills")
		T.truthy(layout.Card.Y * 0.62 >= 44, "cards")
	end)
end
