--[[
	Tiny UI kit: pure builder functions (only Instance creation), so the same
	code also runs in the Lune preview tools. Chunky forge style from UITheme.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UITheme"))

local UIKit = {}

export type Props = { [string]: any }

function UIKit.new(className: string, props: Props?, parent: Instance?): any
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) }, parent)
end

function UIKit.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or Theme.Stroke,
		Color = color or Theme.Outline,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UIKit.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

function UIKit.padding(parent: Instance, all: number): UIPadding
	local d = UDim.new(0, all)
	return UIKit.new("UIPadding", { PaddingTop = d, PaddingBottom = d, PaddingLeft = d, PaddingRight = d }, parent)
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	}, parent)
end

-- ScreenGui with a UIScale named "Scale" (controllers set it from screen size).
function UIKit.screen(name: string, displayOrder: number?): ScreenGui
	local gui = UIKit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
	})
	UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, gui)
	return gui
end

function UIKit.panel(parent: Instance, props: Props?): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, parent)
	if props then
		for key, value in props do
			(frame :: any)[key] = value
		end
	end
	UIKit.corner(frame)
	UIKit.stroke(frame)
	UIKit.gradient(frame, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	return frame
end

function UIKit.label(parent: Instance, text: string, textSize: number, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = textSize,
		TextColor3 = Theme.Text,
		FontFace = Theme.Font,
		TextWrapped = true,
	}, parent)
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	UIKit.textStroke(label)
	return label
end

--[[
	Chunky button with a darker "lip" underneath (3D look).
	Returns the clickable TextButton (its Parent is the lip holder frame).
]]
function UIKit.button(parent: Instance, text: string, color: Color3, darkColor: Color3, props: Props?): TextButton
	local holder = UIKit.new("Frame", {
		Name = (props and props.Name or text) .. "Holder",
		BackgroundColor3 = darkColor,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 52),
	}, parent)
	UIKit.corner(holder, 12)
	UIKit.stroke(holder)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -5),
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = Theme.Text,
		TextSize = 22,
		FontFace = Theme.Font,
	}, holder)
	UIKit.corner(button, 12)
	UIKit.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	UIKit.textStroke(button)
	if props then
		for key, value in props do
			if key == "Size" or key == "Position" or key == "AnchorPoint" or key == "LayoutOrder" or key == "Visible" then
				(holder :: any)[key] = value
			elseif key ~= "Name" then
				(button :: any)[key] = value
			end
		end
	end
	return button
end

-- Small rounded chip in a rarity color with text.
function UIKit.chip(parent: Instance, text: string, color: Color3, props: Props?): TextLabel
	local chip = UIKit.new("TextLabel", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = text,
		TextSize = 14,
		TextColor3 = Theme.Text,
		FontFace = Theme.Font,
		Size = UDim2.fromOffset(90, 22),
	}, parent)
	UIKit.corner(chip, 11)
	UIKit.stroke(chip, 2)
	UIKit.textStroke(chip, 1.5)
	if props then
		for key, value in props do
			(chip :: any)[key] = value
		end
	end
	return chip
end

function UIKit.list(parent: Instance, direction: Enum.FillDirection, padding: number, props: Props?): UIListLayout
	local layout = UIKit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
	if props then
		for key, value in props do
			(layout :: any)[key] = value
		end
	end
	return layout
end

return UIKit
