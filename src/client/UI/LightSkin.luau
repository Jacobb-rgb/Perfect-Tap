--[[
	LightSkin: dresses a window built with the old dark kit (UIKit + UITheme:
	brown panels) in the game's current look, the dark "Store card" style
	(owner 2026-10-20, Config/BubbleTheme + Config/CardTheme), without
	touching the window's code or layout. Used while UIConfig.lightUI() is
	on by the older windows (SellView, TechShopView, TrainView, IronBoxView,
	FoundryView, CleaningView, the steps 6-7 windows, MenuPanel windows).

	  backgrounds  the brown panels become dark slate; the button colours
	               become the kit's button colours (green, red, orange, blue);
	               everything else (ore and rarity colours) stays
	  outlines     the dark brown outlines become near black
	  text         on the dark panels or over the world: cream with a dark
	               edge (the dim text a soft grey); on a light face (a yellow
	               button): dark ink, no edge (green / orange / gold a darker
	               shade)

	apply(root) skins everything under root now and keeps skinning: new
	children and later colour changes (a controller setting Theme.Text again)
	are mapped too. refresh(root) skins again once (Lune previews, where
	Roblox signals don't run). (The name stays from the light look it first
	made, 2026-10-18.)
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
	[key(Theme.PanelDark)] = rgb(20, 22, 27),
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
	[key(rgb(26, 40, 90))] = BubbleTheme.PanelTint, -- the Hall of Fame's navy boards
	[key(rgb(160, 168, 255))] = Roles.Rebirth.Base, -- the STAR FORGE window (RebirthView.Colors)
	[key(rgb(120, 108, 100))] = Roles.Settings.Base,
	[key(rgb(70, 62, 58))] = Roles.Settings.Lip,
}

-- old text colour -> text colour on a light face (nil = keep the colour)
local SOFT_DARK = rgb(70, 82, 112)
local INK: { [string]: Color3 } = {
	[key(Theme.Text)] = BubbleTheme.DarkInk,
	[key(rgb(255, 255, 255))] = BubbleTheme.DarkInk,
	[key(BubbleTheme.Ink)] = BubbleTheme.DarkInk,
	[key(Theme.TextDim)] = SOFT_DARK,
	[key(BubbleTheme.InkSoft)] = SOFT_DARK,
	[key(Theme.Good)] = rgb(30, 160, 70),
	[key(Theme.Accent)] = rgb(226, 112, 0),
	[key(Theme.Coin)] = rgb(206, 132, 0),
	[key(Theme.Info)] = rgb(30, 120, 210),
}
-- these stay without an outline on light faces (plain dark text)
local PLAIN_INK: { [string]: boolean } = {
	[key(BubbleTheme.DarkInk)] = true,
	[key(SOFT_DARK)] = true,
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

-- A light text colour meant for the dark panels, readable on white: near
-- white / grey becomes ink, a bright hue (a rarity or grade colour) keeps
-- its hue a shade darker. Idempotent (the result maps to itself).
local function readable(c: Color3): Color3
	local h, sat, v = c:ToHSV()
	if sat < 0.25 then
		return BubbleTheme.DarkInk
	end
	return Color3.fromHSV(h, math.max(sat, 0.75), math.min(v, 0.66))
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
	if key(label.TextStrokeColor3) == OUTLINE_KEY then
		label.TextStrokeColor3 = BubbleTheme.Outline -- the old built-in text edge
	end
	local stroke = textStroke(label)
	local behind = backdrop(label)
	if isLight(behind) then
		local colour = label.TextColor3
		local mapped = INK[key(colour)]
		if mapped then
			label.TextColor3 = mapped
		elseif luminance(colour) > 0.6 then
			label.TextColor3 = readable(colour)
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
		-- on the dark panels, a colour or over the world: cream with a dark
		-- edge (also text we inked while its background was light: a row
		-- that got selected)
		local k = key(label.TextColor3)
		if k == key(Theme.Text) or k == key(BubbleTheme.DarkInk) then
			label.TextColor3 = BubbleTheme.Ink
		elseif k == key(Theme.TextDim) or k == key(SOFT_DARK) then
			label.TextColor3 = BubbleTheme.InkSoft
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

--[[
	The store-card header band (owner 2026-10-20: every window like the store
	photos): a window whose panel has a big title (a "Title" label in the old
	title font) gets a band across the panel's top in the window's own colour
	(BandRoles by the ScreenGui's name, else orange) with faint diagonal
	stripes; the title turns cream with a dark edge in the comic font. The
	band follows the title when the window's layout moves it.
]]
LightSkin.BandRoles = {
	TerraForgeCodex = "Codex",
	TerraForgeSettings = "Settings",
	TerraForgeHallOfFame = "Boards",
	TerraForgeRebirth = "Rebirth",
	TerraForgeWheel = "Wheel",
	TerraForgeArtifacts = "Artifacts",
	TerraForgeJournal = "Artifacts",
	TerraForgeEnchants = "Enchant",
	TerraForgeBoosts = "Boosts",
	TerraForgeCapsules = "Golems",
	TerraForgeGolems = "Golems",
	TerraForgeGearShop = "Gear",
	TerraForgeSell = "Shop",
	TerraForgeTechShop = "Build",
	TerraForgeTrain = "Lobby",
	TerraForgeTrainPanel = "Lobby",
	TerraForgeIronBox = "Settings",
	TerraForgeFoundry = "Vault",
	TerraForgePen = "Backpack",
} :: { [string]: string }

local BAND = "SkinBand"

local function bandHeight(title: GuiObject): number
	local bottom = title.Position.Y.Offset + title.Size.Y.Offset
	return math.max(48, bottom + 10)
end

local function sizeBand(band: GuiObject)
	local parent = band.Parent
	local title = if parent then parent:FindFirstChild("Title") else nil
	if title and title:IsA("GuiObject") then
		local height = bandHeight(title)
		-- the line under the title rides in the band too
		local subtitle = if parent then parent:FindFirstChild("Subtitle") else nil
		if subtitle and subtitle:IsA("GuiObject") and subtitle.Visible and subtitle.Position.Y.Offset >= title.Position.Y.Offset then
			height = math.max(height, bandHeight(subtitle) - 4)
		end
		band.Size = UDim2.new(1, 0, 0, height)
	end
end

local function addBand(title: TextLabel, roleName: string)
	local panel = title.Parent :: GuiObject
	if panel:FindFirstChild(BAND) then
		return
	end
	local role = Roles[roleName] or Roles.Vault
	local corner = panel:FindFirstChildOfClass("UICorner")
	local band = Instance.new("Frame")
	band.Name = BAND
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.BorderSizePixel = 0
	band.ClipsDescendants = true
	band.ZIndex = 0 -- under every other part of the window
	local colours = ColorSequence.new({
		ColorSequenceKeypoint.new(0, role.Base),
		ColorSequenceKeypoint.new(0.6, role.Base:Lerp(role.Top, 0.5)),
		ColorSequenceKeypoint.new(1, role.Top),
	})
	local gradient = Instance.new("UIGradient")
	gradient.Color = colours
	gradient.Parent = band
	if corner then
		local round = Instance.new("UICorner")
		round.CornerRadius = corner.CornerRadius
		round.Parent = band
		-- the band's bottom corners stay square
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		fill.BorderSizePixel = 0
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		fill.Size = UDim2.new(1, 0, 0.5, 0)
		fill.ZIndex = 0
		local fillGradient = Instance.new("UIGradient")
		fillGradient.Color = colours
		fillGradient.Parent = fill
		fill.Parent = band
	end
	for i = 0, 60 do
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.BackgroundColor3 = Color3.new(1, 1, 1)
		stripe.BackgroundTransparency = 0.86
		stripe.BorderSizePixel = 0
		stripe.Position = UDim2.new(0, 14 + i * 26, 0.5, 0)
		stripe.Rotation = 35
		stripe.Size = UDim2.new(0, 8, 2, 0)
		stripe.ZIndex = 0
		stripe.Parent = band
	end
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = BubbleTheme.Outline
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, 3)
	line.ZIndex = 0
	line.Parent = band
	band.Parent = panel
	sizeBand(band)
	title.FontFace = BubbleTheme.CardFont
	title.TextColor3 = BubbleTheme.Ink
	local edge = textStroke(title)
	if not edge then
		local made = Instance.new("UIStroke")
		made.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		made.Parent = title
		edge = made
	end
	local stroke = edge :: UIStroke
	stroke.Enabled = true
	stroke.Color = BubbleTheme.Outline
	stroke.Thickness = 3
	stroke.Transparency = 0
	pcall(function()
		title:GetPropertyChangedSignal("Position"):Connect(function()
			sizeBand(band)
		end)
		title:GetPropertyChangedSignal("Size"):Connect(function()
			sizeBand(band)
		end)
	end)
end

-- Adds the header band to the window(s) under root (see BandRoles).
function LightSkin.bands(root: Instance)
	local gui = if root:IsA("ScreenGui") then root else root:FindFirstAncestorOfClass("ScreenGui")
	local roleName = if gui then LightSkin.BandRoles[gui.Name] else nil
	for _, d in root:GetDescendants() do
		if d.Name == "Title" and d:IsA("TextLabel") then
			local parent = d.Parent
			local family = d.FontFace.Family
			local titleFont = string.find(family, "Luckiest") ~= nil or string.find(family, "ComicNeue") ~= nil
			-- (a window title: big, on an opaque panel; card titles are smaller)
			if titleFont and d.TextSize >= 28 and parent and parent:IsA("Frame") and parent.BackgroundTransparency < 0.5 then
				addBand(d, roleName or "Vault")
			end
		elseif d.Name == BAND and d:IsA("GuiObject") then
			sizeBand(d)
		end
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
	LightSkin.bands(root)
end

--[[
	World labels (BillboardGuis): the light skin, plus the light look's bold
	edge on every text floating over the world: a navy outline (UIStroke,
	about a tenth of the text size, at least 2.5) instead of Roblox's thin
	built-in text edge. Runs once; LightWorldController calls it for new labels.
]]
function LightSkin.world(root: Instance)
	LightSkin.apply(root)
	local all = root:GetDescendants()
	for _, d in all do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and backdrop(d) == nil then
			local label: any = d
			local stroke = textStroke(label)
			if not stroke then
				local created = Instance.new("UIStroke")
				created.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				created.Parent = label
				stroke = created
			end
			local s = stroke :: UIStroke
			s.Enabled = true
			s.Color = BubbleTheme.Outline
			s.Transparency = 0
			local size = if label.TextScaled then 30 else label.TextSize
			s.Thickness = math.max(2.5, math.floor(size / 10 + 0.5))
			label.TextStrokeTransparency = 1
		end
	end
end

-- Skins root now and keeps skinning new children and colour changes.
function LightSkin.apply(root: Instance)
	if root:GetAttribute("LightSkin") then
		LightSkin.refresh(root) -- already watched (a window built inside another)
		return
	end
	root:SetAttribute("LightSkin", true)
	LightSkin.refresh(root)
	pcall(function()
		local function watch(d: Instance)
			if d:IsA("GuiObject") then
				d:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
					LightSkin.skin(d)
					-- the texts on it read their backdrop again (a row selected / deselected)
					for _, inner in d:GetDescendants() do
						if inner:IsA("TextLabel") or inner:IsA("TextButton") or inner:IsA("TextBox") then
							LightSkin.skin(inner)
						end
					end
					if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
						LightSkin.skin(d)
					end
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
