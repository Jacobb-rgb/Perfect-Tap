--[[
	The light UI's ProximityPrompt look (pure builder; LightWorldController
	shows it for prompts only while UIConfig.CustomPrompts is on, and that
	ships off: the game uses the stock Roblox prompt since 2026-10-20).

	  [ (E) ]  OPEN SHOP          a white pill, navy outline, lip
	           Tobin's Ore Stall  the key in a gold circle (or the gamepad's
	  ========                    glyph, or TAP on touch), the action and the
	                              object; a green bar fills while you hold

	The whole pill is a button, so a tap starts / ends the hold on touch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local LightPrompt = {}

LightPrompt.Height = 64
LightPrompt.MinWidth = 180
LightPrompt.KeySize = 46

export type Refs = {
	Gui: BillboardGui,
	Button: TextButton,
	Key: TextLabel,
	Glyph: ImageLabel,
	Action: TextLabel,
	Object: TextLabel,
	Fill: Frame,
}

-- The pill's width for an action / object text (design pixels).
function LightPrompt.width(action: string, object: string): number
	local text = math.max(Bubble.textWidth(action, 22), Bubble.textWidth(object, 15))
	return math.max(LightPrompt.MinWidth, LightPrompt.KeySize + 30 + text)
end

function LightPrompt.build(action: string, object: string, key: string): Refs
	local w = LightPrompt.width(action, object)
	local h = LightPrompt.Height
	local gui = UIKit.new("BillboardGui", {
		Name = "TerraForgePrompt",
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(w + 12, h + 16),
		Active = true,
	})
	local holder, face = Bubble.body(gui, Bubble.role("Plain"), Vector2.new(w, h), { Name = "Pill", Corner = h // 2, Clickable = true })
	holder.Position = UDim2.fromOffset(6, 4)
	local button = face :: TextButton
	-- the key: a gold circle with the key's letter, or the platform glyph
	local circle = UIKit.new("Frame", {
		Name = "KeyCircle",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(LightPrompt.KeySize, LightPrompt.KeySize),
		ZIndex = 4,
	}, face)
	Bubble.corner(circle, LightPrompt.KeySize)
	Bubble.stroke(circle, 3)
	Bubble.gradient(circle, Color3.fromRGB(255, 232, 120), Theme.Gold)
	local keyLabel = Bubble.text(circle, key, if #key > 2 then 15 else 24, {
		Name = "Key",
		FontFace = Theme.TitleFont,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 6,
	}, circle)
	local x = LightPrompt.KeySize + 18
	local actionLabel = Bubble.ink(face, string.upper(action), 22, {
		Name = "Action",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(x, if object ~= "" then 6 else 0),
		Size = UDim2.new(1, -x - 12, 0, if object ~= "" then 30 else h),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local objectLabel = Bubble.ink(face, object, 15, {
		Name = "Object",
		Position = UDim2.fromOffset(x, 34),
		Size = UDim2.new(1, -x - 12, 0, 20),
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = object ~= "",
		ZIndex = 4,
	})
	-- the hold bar along the bottom edge
	local track = UIKit.new("Frame", {
		Name = "Hold",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -h, 0, 6),
		ZIndex = 4,
	}, face)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
	}, track)
	Bubble.corner(fill, 3)
	return { Gui = gui, Button = button, Key = keyLabel, Glyph = glyph, Action = actionLabel, Object = objectLabel, Fill = fill }
end

-- The key shown: a keyboard letter, a gamepad glyph image, or "TAP".
function LightPrompt.setKey(refs: Refs, text: string, image: string?)
	refs.Key.Text = text
	refs.Key.TextSize = if #text > 2 then 15 else 24
	local hasImage = image ~= nil and image ~= ""
	refs.Glyph.Image = image or ""
	refs.Glyph.Visible = hasImage
	refs.Key.Visible = not hasImage
end

-- How far the hold is (0..1).
function LightPrompt.setHold(refs: Refs, fraction: number)
	refs.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

return LightPrompt
