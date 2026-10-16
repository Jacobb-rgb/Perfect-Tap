-- The progress sign over your own machines (client UI builder) on a real
-- machine model: where it hangs, and what update() shows.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Color3 = roblox.Color3
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")

	local function visiblePips(refs: any): (number, number)
		local filled = 0
		for _, pip in refs.Pips do
			if pip.BackgroundColor3 == Theme.Accent then
				filled += 1
			end
		end
		return #refs.Pips, filled
	end

	T.test("MachineBillboard: hangs on the Status attachment, hidden beyond 45 studs", function()
		for _, id in { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner", "Anvil" } do
			local model = MachineBuilder.build(id)
			local refs = MachineBillboard.attach(model)
			local status = model.PrimaryPart:FindFirstChild("Status")
			T.truthy(refs.Gui.Parent == status, id .. " parented to Status")
			T.truthy(refs.Gui.Adornee == status, id .. " adorned to Status")
			T.eq(refs.Gui.MaxDistance, 45, id .. " MaxDistance")
			T.eq(refs.Gui.AlwaysOnTop, false, id .. " not through walls")
			T.falsy(refs.Fill.Visible, id .. " empty bar")
			T.falsy(refs.Status.Visible, id .. " no status")
			MachineBillboard.detach(refs)
			T.eq(status:FindFirstChild("MachineBillboard"), nil, id .. " detached")
		end
	end)

	T.test("MachineBillboard: update shows progress, queue, FULL, ready items and status", function()
		local model = MachineBuilder.build("ClayFurnace")
		local refs = MachineBillboard.attach(model)
		local copper = Color3.fromRGB(222, 120, 60)
		MachineBillboard.update(refs, 0.5, 2, 4, 0, "", copper)
		T.eq(refs.Fill.Size.X.Offset, 75, "half the bar")
		T.truthy(refs.Fill.Visible, "bar visible")
		T.truthy(refs.Fill.BackgroundColor3 == copper, "ore colour")
		local pips, filled = visiblePips(refs)
		T.eq(pips, 4, "4 pips")
		T.eq(filled, 2, "2 filled")
		T.falsy(refs.Full.Visible, "not full")
		T.falsy(refs.Ready.Visible, "nothing ready")
		T.falsy(refs.Status.Visible, "no status")

		MachineBillboard.update(refs, 3, 4, 4, 3, "OutputBlocked", nil)
		T.eq(refs.Fill.Size.X.Offset, 150, "clamped to full")
		T.truthy(refs.Fill.BackgroundColor3 == Theme.Accent, "default colour")
		T.truthy(refs.Full.Visible, "FULL chip")
		T.truthy(refs.Ready.Visible, "ready count")
		T.eq(refs.Ready.Text, "3 ready", "ready text")
		T.truthy(refs.Status.Visible, "status shown")
		T.eq(refs.Status.Text, "Output blocked", "status text")

		MachineBillboard.update(refs, 0 / 0, 1, 2, 0, "TooManyItems", nil)
		T.eq(refs.Fill.Size.X.Offset, 0, "NaN progress is empty")
		T.falsy(refs.Fill.Visible, "bar hidden at 0")
		pips, filled = visiblePips(refs)
		T.eq(pips, 2, "pips follow QueueMax")
		T.eq(filled, 1, "1 filled")
		T.falsy(refs.Full.Visible, "FULL gone")
		T.falsy(refs.Ready.Visible, "ready gone")
		T.eq(refs.Status.Text, "Too many loose items", "loose items text")

		MachineBillboard.update(refs, 0.2, 0, 0, 0, "", nil)
		T.falsy(refs.Status.Visible, "status cleared")
		pips = visiblePips(refs)
		T.eq(pips, 0, "no queue, no pips")
		T.falsy(refs.Full.Visible, "no FULL without a queue")
		MachineBillboard.detach(refs)
	end)
end
