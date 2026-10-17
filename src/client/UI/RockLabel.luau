--[[
	RockLabel: the name and HP over a mine rock (owner, 2026-10-17: "like
	The Forge", so players see at a glance what they mine and how long it takes).

	   Greystone              20 HP     name in the rock's color (MineFloors.labelColor)
	  [===============-------]          HP bar
	Locked rocks show "Lv 5" in red instead of the HP.

	Hangs above the rock (StudsOffset = rock height + 1.4), hides beyond 45
	studs and behind walls. Pure builder: it only creates and changes
	Instances (no services, no events), so the Lune tests and previews run it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Config"):WaitForChild("UITheme"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.UIKit)

local RockLabel = {}

export type Refs = {
	Gui: BillboardGui,
	Name: TextLabel,
	Hp: TextLabel,
	Bar: Frame,
	Fill: Frame,
	Shown: { Hp: number, Max: number, Locked: number },
}

RockLabel.MaxDistance = 45
local WIDTH = 200
local BAR_HEIGHT = 9

-- Builds the label for a rock `height` studs tall (call RockLabel.set for live HP).
function RockLabel.build(name: string, color: Color3, maxHp: number, height: number): Refs
	local gui = UIKit.new("BillboardGui", {
		Name = "RockLabel",
		Size = UDim2.fromOffset(WIDTH, 40),
		StudsOffset = Vector3.new(0, height + 1.4, 0),
		MaxDistance = RockLabel.MaxDistance,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		ClipsDescendants = false,
	}) :: BillboardGui
	local nameLabel = UIKit.label(gui, name, 20, {
		Name = "RockName",
		Size = UDim2.new(0.64, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local hpLabel = UIKit.label(gui, "", 17, {
		Name = "Hp",
		Size = UDim2.new(0.36, 0, 0, 24),
		Position = UDim2.fromScale(0.64, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, gui) :: Frame
	UIKit.corner(bar, 5)
	UIKit.stroke(bar, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
	}, bar) :: Frame
	UIKit.corner(fill, 5)
	local refs: Refs = {
		Gui = gui,
		Name = nameLabel,
		Hp = hpLabel,
		Bar = bar,
		Fill = fill,
		Shown = { Hp = -1, Max = -1, Locked = -1 },
	}
	RockLabel.set(refs, maxHp, maxHp, nil)
	return refs
end

-- Shows `hp` of `maxHp`, or "Lv N" in red when the player's blaster is too weak.
function RockLabel.set(refs: Refs, hp: number, maxHp: number, lockedLevel: number?)
	local max = math.max(1, maxHp)
	local now = math.clamp(math.ceil(hp), 0, max)
	local locked = lockedLevel or 0
	local shown = refs.Shown
	if shown.Hp == now and shown.Max == max and shown.Locked == locked then
		return
	end
	shown.Hp, shown.Max, shown.Locked = now, max, locked
	if locked > 0 then
		refs.Hp.Text = "Lv " .. locked
		refs.Hp.TextColor3 = Theme.Bad
		refs.Fill.Size = UDim2.fromScale(1, 1)
		refs.Fill.BackgroundColor3 = Theme.BadDark
	else
		refs.Hp.Text = Format.short(now) .. " HP"
		refs.Hp.TextColor3 = Theme.Text
		refs.Fill.Size = UDim2.fromScale(now / max, 1)
		refs.Fill.BackgroundColor3 = Theme.Bad
	end
end

return RockLabel
