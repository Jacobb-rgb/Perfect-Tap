--[[
	LightSkin: dresses a window built with the old dark kit (UIKit + UITheme) in
	the light "Bubble" look, without touching the window's code or layout.
	Used while UIConfig.lightUI() is on (the light UI, ships off) by the older
	windows: SellView, TechShopView, TrainView, IronBoxView, FoundryView,
	CleaningView.

	  backgrounds  the dark panel colours become white / light tints; the
	               button colours become the light button colours (green, red,
	               orange, blue); everything else (ore and rarity colours)
	               stays
	  outlines     the dark brown outlines become navy
	  text         on a light background: dark ink, no outline (the dim text a
	               soft ink, green / orange / gold a darker shade); on a colour
	               or over the world: white with a navy outline

	apply(root) skins everything under root now and keeps skinning: new
	children and later colour changes (a controller setting Theme.Text again)
	are mapped too. refresh(root) skins again once (Lune previews, where
	Roblox signals don't run).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local BubbleTheme = require(Shared.Config.BubbleTheme)

local LightSkin = {}

local rgb = Color3.fromRGB
local Roles = BubbleTheme.Roles

local function key(c: Color3): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- old background colour -> light background colour
local BACKGROUNDS: { [string]: Color3 } = {
	[key(Theme.Panel)] = BubbleTheme.Panel,
	[key(Theme.PanelLight)] = BubbleTheme.PanelTint,
	[key(Theme.PanelDark)] = rgb(214, 224, 240),
	[key(Theme.Good)] = Roles.Go.Base,
	[key(Theme.GoodDark)] = Roles.Go.Lip,
	[key(Theme.Bad)] = Roles.Danger.Base,
	[key(Theme.BadDark)] = Roles.Danger.Lip,
	[key(Theme.Accent)] = Roles.Vault.Base,
	[key(Theme.AccentDark)] = Roles.Vault.Lip,
	[key(Theme.Info)] = Roles.Lobby.Base,
	[key(rgb(60, 120, 190))] = Roles.Lobby.Lip, -- the old info-button lip
	[key(rgb(46, 104, 164))] = Roles.Lobby.Lip, -- the Ore Pen's send lip
	[key(rgb(128, 118, 110))] = Roles.Settings.Base, -- grey "off" buttons
	[key(rgb(74, 66, 60))] = Roles.Settings.Lip,
	[key(rgb(120, 114, 108))] = rgb(150, 158, 176), -- dirty ore grey
}

-- old text colour -> text colour on a light background (nil = keep the colour)
local INK: { [string]: Color3 } = {
	[key(Theme.Text)] = BubbleTheme.Ink,
	[key(rgb(255, 255, 255))] = BubbleTheme.Ink,
	[key(Theme.TextDim)] = BubbleTheme.InkSoft,
	[key(Theme.Good)] = rgb(30, 160, 70),
	[key(Theme.Accent)] = rgb(226, 112, 0),
	[key(Theme.Coin)] = rgb(206, 132, 0),
	[key(Theme.Info)] = rgb(30, 120, 210),
}
-- these stay without an outline on light backgrounds (plain dark text)
local PLAIN_INK: { [string]: boolean } = {
	[key(BubbleTheme.Ink)] = true,
	[key(BubbleTheme.InkSoft)] = true,
}

local LIGHT_GRADIENT = ColorSequence.new(Color3.new(1, 1, 1), rgb(236, 241, 249))
local OUTLINE_KEY = key(Theme.Outline)
local ACCENT_DARK_KEY = key(Theme.AccentDark)

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- The colour behind a GuiObject: the first ancestor (or itself) that paints one.
local function backdrop(object: Instance): Color3?
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		local gui = node :: GuiObject
		if gui.BackgroundTransparency < 0.5 then
			return gui.BackgroundColor3
		end
		node = node.Parent
	end
	return nil
end

local function isLight(c: Color3?): boolean
	return c ~= nil and luminance(c :: Color3) > 0.72
end

local function skinBackground(gui: GuiObject)
	local mapped = BACKGROUNDS[key(gui.BackgroundColor3)]
	if mapped then
		gui.BackgroundColor3 = mapped
	end
	if isLight(gui.BackgroundColor3) and gui.BackgroundTransparency < 0.5 then
		-- the old panels' dark-bottom gradient would grey a white panel
		local gradient = gui:FindFirstChildOfClass("UIGradient")
		if gradient and gradient.Color.Keypoints[1].Value == Color3.new(1, 1, 1) then
			gradient.Color = LIGHT_GRADIENT
		end
	end
end

local function textStroke(label: GuiObject): UIStroke?
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return nil
end

local function skinText(object: GuiObject)
	local label: any = object -- a TextLabel, TextButton or TextBox
	local stroke = textStroke(label)
	local behind = backdrop(label)
	if isLight(behind) then
		local colour = label.TextColor3
		local mapped = INK[key(colour)]
		if mapped then
			label.TextColor3 = mapped
		elseif luminance(colour) > 0.6 then
			label.TextColor3 = BubbleTheme.Ink -- a light colour meant for the dark panels
		end
		-- body text is plain; only titles (LuckiestGuy) keep a thin navy edge
		local title = string.find(label.FontFace.Family, "Luckiest") ~= nil
		local plain = PLAIN_INK[key(label.TextColor3)] == true
		if stroke then
			stroke.Enabled = title and not plain
			stroke.Color = BubbleTheme.Outline
			stroke.Thickness = math.min(stroke.Thickness, 1.5)
		end
	else
		-- on a colour or over the world: white with a navy edge
		if key(label.TextColor3) == key(Theme.Text) or key(label.TextColor3) == key(Theme.TextDim) then
			label.TextColor3 = BubbleTheme.White
		end
		if stroke then
			stroke.Enabled = true
			stroke.Color = BubbleTheme.Outline
		end
	end
end

-- Skins one instance (idempotent: light colours map to themselves).
function LightSkin.skin(instance: Instance)
	if instance:IsA("UIStroke") then
		local k = key(instance.Color)
		if k == OUTLINE_KEY or k == ACCENT_DARK_KEY or k == key(rgb(214, 140, 10)) then
			instance.Color = BubbleTheme.Outline
		end
		return
	end
	if instance:IsA("ScrollingFrame") then
		local k = key(instance.ScrollBarImageColor3)
		if k == key(Theme.Accent) or k == key(Theme.TextDim) then
			instance.ScrollBarImageColor3 = BubbleTheme.InkSoft
		end
	end
	if instance:IsA("GuiObject") then
		skinBackground(instance)
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		skinText(instance)
	end
end

-- Skins everything under root once (backgrounds first, then the texts that read them).
function LightSkin.refresh(root: Instance)
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, d in all do
		if not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then
			LightSkin.skin(d)
		end
	end
	for _, d in all do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			LightSkin.skin(d)
		end
	end
end

-- Skins root now and keeps skinning new children and colour changes.
function LightSkin.apply(root: Instance)
	root:SetAttribute("LightSkin", true)
	LightSkin.refresh(root)
	pcall(function()
		local function watch(d: Instance)
			if d:IsA("GuiObject") then
				d:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
					LightSkin.skin(d)
				end)
			end
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				d:GetPropertyChangedSignal("TextColor3"):Connect(function()
					LightSkin.skin(d)
				end)
			end
			if d:IsA("UIStroke") then
				d:GetPropertyChangedSignal("Color"):Connect(function()
					LightSkin.skin(d)
				end)
			end
		end
		for _, d in root:GetDescendants() do
			watch(d)
		end
		root.DescendantAdded:Connect(function(d)
			task.defer(function()
				LightSkin.skin(d)
				watch(d)
			end)
		end)
	end)
end

return LightSkin
