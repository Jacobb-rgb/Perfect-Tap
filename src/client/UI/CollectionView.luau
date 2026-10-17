--[[
	The artifact collection book and the ARTIFACT FOUND card (step 7): pure
	builders, layout math and texts (ArtifactController fills them in and
	handles input; the Lune preview builds the same views).

	  book    "ARTIFACTS OF KALDRUM", how many of all are found, an X
	          (B / Backspace close it too). Left: one tab per collection
	          (its color, "3 / 6", a check when complete, NEW while its
	          chapter is unread; LB / RB switch). Middle: the collection's
	          artifacts as tiles, found ones in color with their name and
	          rarity, missing ones as dark silhouettes ("???", rarity shown).
	          Right: the selected artifact (name, rarity, how many, its lore
	          once found) and where it turns up most, with the exact chance
	          per rock there. Bottom: the collection's reward and the chapter
	          button ("READ CHAPTER 1", or what unlocks it).
	  reveal  its own ScreenGui: the ARTIFACT FOUND card (the relic's icon,
	          name, rarity, collection progress, its lore; a duplicate's
	          shards; a completed collection's reward and chapter) with OPEN
	          BOOK and OK.
	  glyph   every relic also has a flat icon made of frames (glyph(): the
	          same shape family and colors as ArtifactBuilder's 3D model), so
	          the book works the same in the game and in the preview renders;
	          a silhouette is the same shape in one dark color with a "?".

	Designed for 720 design units of height (HudController scales every
	TerraForge gui); `compact` (phones, TVs) uses 72-unit buttons (44 pt at
	uiScale 0.62) and bigger texts; layout() fits the panel down to a
	568 x 320 pt phone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local Rarity = require(Shared.Config.Rarity)
local StatConfig = require(Shared.Config.StatConfig)
local StoryConfig = require(Shared.Config.StoryConfig)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)

local CollectionView = {}

type Artifact = ArtifactConfig.Artifact

export type Tile = {
	Button: TextButton,
	Icon: Frame,
	Name: TextLabel,
	Chip: TextLabel,
	Count: TextLabel,
	Id: string,
}

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Title: TextLabel,
	Total: TextLabel,
	Close: TextButton,
	Tabs: { [string]: TextButton },
	TabList: { TextButton },
	Grid: Frame,
	Tiles: { Tile },
	Detail: Frame,
	DetailIcon: Frame,
	DetailName: TextLabel,
	DetailChip: TextLabel,
	DetailCount: TextLabel,
	DetailLore: TextLabel,
	DetailWhere: TextLabel,
	Footer: Frame,
	Reward: TextLabel,
	Chapter: TextButton,
	Hint: TextLabel,
	Collection: string,
	Selected: string?,
	Compact: boolean,
}

export type RevealRefs = {
	Gui: ScreenGui,
	Card: Frame,
	Icon: Frame,
	Title: TextLabel,
	Name: TextLabel,
	Chip: TextLabel,
	Progress: TextLabel,
	Lore: TextLabel,
	Extra: TextLabel,
	Book: TextButton,
	Ok: TextButton,
	Compact: boolean,
}

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Pad: number,
	TabWidth: number,
	TabHeight: number,
	DetailWidth: number,
	Footer: number,
	Button: number,
	Close: number,
	Title: number,
	TileName: number,
	Body: number,
	Hint: number,
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1000,
		Height = 600,
		Header = 70,
		Pad = 16,
		TabWidth = 230,
		TabHeight = 70,
		DetailWidth = 290,
		Footer = 76,
		Button = 56,
		Close = 54,
		Title = 36,
		TileName = 16,
		Body = 17,
		Hint = 16,
	},
	Compact = {
		Width = 1060,
		Height = 600,
		Header = 62,
		Pad = 12,
		TabWidth = 210,
		TabHeight = 76,
		DetailWidth = 300,
		Footer = 84,
		Button = 72,
		Close = 72,
		Title = 32,
		TileName = 18,
		Body = 19,
		Hint = 18,
	},
}

CollectionView.Columns = 3
CollectionView.SilhouetteColor = Color3.fromRGB(34, 28, 32)
CollectionView.MissingName = "???"

local GOLD = Color3.fromRGB(255, 196, 64)
local STAND = Color3.fromRGB(58, 46, 40)
local PAGES = Color3.fromRGB(240, 228, 196)
local WOOD = Color3.fromRGB(124, 82, 52)
local ROCK = Color3.fromRGB(64, 54, 60)

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- The best place to find an artifact: the zone where a broken rock most
-- often holds it, and that chance (rock chance x its share of the zone's
-- artifact odds; bonuses such as Prospector not counted).
function CollectionView.bestZone(artifactId: string): (string?, number)
	local bestZone: string? = nil
	local best = 0
	local zones = {}
	for zoneId in ArtifactConfig.ZoneChance do
		table.insert(zones, zoneId)
	end
	table.sort(zones)
	for _, zoneId in zones do
		for _, line in ArtifactConfig.odds(zoneId) do
			if line.Artifact == artifactId then
				local chance = ArtifactConfig.rockChance(zoneId) * line.Chance
				if chance > best then
					best, bestZone = chance, zoneId
				end
			end
		end
	end
	return bestZone, best
end

-- "Most often in Deep Hollow: 1 in 1,650 broken rocks".
function CollectionView.whereText(artifactId: string): string
	local zoneId, chance = CollectionView.bestZone(artifactId)
	if not zoneId or chance <= 0 then
		return "Not found in today's mines"
	end
	local zone = WorldLayout.ZoneById[zoneId]
	local name = if zone then zone.Name else zoneId
	return `Most often in {name}: 1 in {Format.commas(math.floor(1 / chance + 0.5))} broken rocks`
end

-- "Reward: title "Heir of Kaldrum" · Royal Velvet podium skin · +5% podium income"
function CollectionView.rewardText(collectionId: string): string
	local collection = ArtifactConfig.CollectionById[collectionId]
	if not collection then
		return ""
	end
	local reward = collection.Reward
	local skin = ArtifactConfig.PodiumSkins[reward.PodiumSkin]
	local parts = { `title "{reward.Title}"` }
	if skin then
		table.insert(parts, `{skin.Name} podium skin`)
	end
	table.insert(parts, StatConfig.describe(reward.Bonus.Stat, reward.Bonus.Value))
	return "Reward: " .. table.concat(parts, " · ")
end

-- Found / total of a collection in a data.Artifacts record.
function CollectionView.progress(artifacts: any, collectionId: string): (number, number)
	local list: { Artifact } = ArtifactConfig.ByCollection[collectionId] or {}
	local found = 0
	for _, art in list do
		if ArtifactConfig.countOf(artifacts, art.Id) > 0 then
			found += 1
		end
	end
	return found, #list
end

-- Has a completed collection's chapter not been read yet?
function CollectionView.chapterNew(artifacts: any, collectionId: string): boolean
	if not ArtifactConfig.isComplete(artifacts, collectionId) then
		return false
	end
	local chapters = if type(artifacts) == "table" then artifacts.Chapters else nil
	return not (type(chapters) == "table" and chapters[collectionId] == true)
end

-- The chapter button's text and whether it can be pressed.
function CollectionView.chapterButton(artifacts: any, collectionId: string): (string, boolean)
	local chapter = StoryConfig.ByCollection[collectionId]
	local number = if chapter then chapter.Number else 0
	if ArtifactConfig.isComplete(artifacts, collectionId) then
		return `READ CHAPTER {number}`, true
	end
	local _, total = CollectionView.progress(artifacts, collectionId)
	return `FIND ALL {total} TO UNLOCK CHAPTER {number}`, false
end

---------------------------------------------------------------- glyphs

-- A glyph piece: centre (x, y) and size (w, h) in shares of the icon box,
-- rotation, color key (P primary, A accent, G glow or accent, D stand,
-- L pages, T light primary, K dark primary, W wood, R rock), roundness.
type Piece = { X: number, Y: number, W: number, H: number, R: number?, C: string, Round: number? }

local function p(x: number, y: number, w: number, h: number, c: string, r: number?, round: number?): Piece
	return { X = x, Y = y, W = w, H = h, C = c, R = r, Round = round }
end

local GLYPHS: { [string]: { Piece } } = {
	Coin = {
		p(0.5, 0.5, 0.8, 0.8, "P", 0, 1),
		p(0.5, 0.5, 0.56, 0.56, "T", 0, 1),
		p(0.5, 0.54, 0.18, 0.18, "A", 45),
		p(0.5, 0.37, 0.1, 0.1, "A", 0, 1),
	},
	Seal = {
		p(0.5, 0.82, 0.7, 0.16, "P", 0, 0.4),
		p(0.5, 0.72, 0.74, 0.07, "A"),
		p(0.5, 0.55, 0.16, 0.3, "A"),
		p(0.5, 0.33, 0.34, 0.34, "P", 0, 1),
		p(0.5, 0.13, 0.12, 0.12, "A", 45),
	},
	Gem = {
		p(0.5, 0.82, 0.08, 0.22, "A"),
		p(0.5, 0.93, 0.44, 0.07, "D"),
		p(0.5, 0.45, 0.66, 0.66, "A", 0, 1),
		p(0.5, 0.45, 0.4, 0.4, "P", 45),
		p(0.5, 0.45, 0.16, 0.16, "G", 45),
	},
	Rod = {
		p(0.5, 0.55, 0.08, 0.62, "A"),
		p(0.5, 0.9, 0.32, 0.06, "D"),
		p(0.5, 0.32, 0.2, 0.06, "P"),
		p(0.5, 0.22, 0.26, 0.26, "P", 0, 1),
		p(0.5, 0.07, 0.12, 0.12, "G", 0, 1),
	},
	Crown = {
		p(0.5, 0.8, 0.86, 0.16, "A", 0, 0.3),
		p(0.27, 0.46, 0.2, 0.2, "P", 45),
		p(0.5, 0.42, 0.2, 0.2, "P", 45),
		p(0.73, 0.46, 0.2, 0.2, "P", 45),
		p(0.5, 0.6, 0.7, 0.24, "P"),
		p(0.5, 0.6, 0.13, 0.13, "G", 0, 1),
	},
	Spike = {
		p(0.5, 0.9, 0.8, 0.1, "W"),
		p(0.5, 0.79, 0.86, 0.12, "A"),
		p(0.5, 0.46, 0.1, 0.56, "P"),
		p(0.45, 0.18, 0.3, 0.08, "P"),
	},
	Whistle = {
		p(0.5, 0.86, 0.5, 0.06, "D"),
		p(0.5, 0.73, 0.06, 0.2, "D"),
		p(0.28, 0.5, 0.28, 0.14, "P"),
		p(0.58, 0.5, 0.42, 0.32, "P", 0, 1),
		p(0.52, 0.38, 0.12, 0.04, "K"),
		p(0.82, 0.4, 0.14, 0.14, "A", 0, 1),
	},
	Lantern = {
		p(0.5, 0.52, 0.34, 0.44, "G"),
		p(0.5, 0.52, 0.06, 0.46, "P"),
		p(0.31, 0.52, 0.05, 0.46, "P"),
		p(0.69, 0.52, 0.05, 0.46, "P"),
		p(0.5, 0.8, 0.5, 0.08, "P"),
		p(0.5, 0.25, 0.5, 0.08, "P"),
		p(0.5, 0.17, 0.2, 0.2, "P", 45),
		p(0.5, 0.06, 0.12, 0.08, "A", 0, 1),
	},
	Tablet = {
		p(0.5, 0.92, 0.7, 0.08, "D"),
		p(0.5, 0.48, 0.62, 0.78, "P", 0, 0.12),
		p(0.5, 0.4, 0.42, 0.05, "G"),
		p(0.5, 0.52, 0.32, 0.05, "G"),
		p(0.5, 0.64, 0.42, 0.05, "G"),
		p(0.5, 0.24, 0.08, 0.08, "G", 45),
	},
	Crest = {
		p(0.5, 0.56, 0.46, 0.46, "P", 45),
		p(0.5, 0.36, 0.64, 0.36, "P"),
		p(0.5, 0.48, 0.12, 0.62, "A"),
		p(0.5, 0.17, 0.72, 0.07, "A"),
		p(0.5, 0.4, 0.16, 0.16, "G", 0, 1),
	},
	Gear = {
		p(0.5, 0.92, 0.5, 0.06, "D"),
		p(0.5, 0.45, 0.82, 0.14, "P", 0),
		p(0.5, 0.45, 0.82, 0.14, "P", 45),
		p(0.5, 0.45, 0.82, 0.14, "P", 90),
		p(0.5, 0.45, 0.82, 0.14, "P", 135),
		p(0.5, 0.45, 0.6, 0.6, "P", 0, 1),
		p(0.5, 0.45, 0.22, 0.22, "A", 0, 1),
	},
	Vial = {
		p(0.5, 0.88, 0.46, 0.05, "A"),
		p(0.5, 0.62, 0.4, 0.46, "T", 0, 0.4),
		p(0.5, 0.68, 0.32, 0.3, "G", 0, 0.3),
		p(0.5, 0.33, 0.16, 0.16, "T"),
		p(0.5, 0.22, 0.2, 0.1, "A"),
	},
	Scroll = {
		p(0.5, 0.9, 0.7, 0.06, "D"),
		p(0.5, 0.42, 0.86, 0.1, "A", 0, 1),
		p(0.5, 0.42, 0.7, 0.3, "P", 0, 1),
		p(0.5, 0.42, 0.08, 0.32, "A"),
		p(0.55, 0.67, 0.52, 0.22, "T", 4),
	},
	Orb = {
		p(0.5, 0.88, 0.4, 0.08, "A"),
		p(0.5, 0.45, 0.66, 0.66, "P", 0, 1),
		p(0.5, 0.45, 0.7, 0.06, "A"),
		p(0.5, 0.45, 0.3, 0.3, "G", 0, 1),
		p(0.5, 0.45, 0.12, 0.12, "K", 0, 1),
	},
	Hammer = {
		p(0.5, 0.45, 0.1, 0.66, "A"),
		p(0.5, 0.22, 0.13, 0.2, "D"),
		p(0.5, 0.78, 0.6, 0.24, "P"),
		p(0.2, 0.78, 0.06, 0.28, "K"),
		p(0.8, 0.78, 0.06, 0.28, "K"),
		p(0.5, 0.78, 0.3, 0.05, "G"),
	},
	Book = {
		p(0.5, 0.92, 0.7, 0.06, "D"),
		p(0.79, 0.5, 0.05, 0.7, "L"),
		p(0.5, 0.48, 0.58, 0.76, "P", 0, 0.08),
		p(0.22, 0.48, 0.07, 0.76, "A"),
		p(0.52, 0.42, 0.16, 0.16, "G", 45),
	},
	Lens = {
		p(0.5, 0.82, 0.08, 0.18, "A"),
		p(0.5, 0.92, 0.4, 0.06, "A"),
		p(0.5, 0.42, 0.72, 0.72, "A", 0, 1),
		p(0.5, 0.42, 0.56, 0.56, "T", 0, 1),
		p(0.5, 0.42, 0.22, 0.22, "G", 0, 1),
	},
	Shard = {
		p(0.5, 0.88, 0.7, 0.14, "R", 0, 0.3),
		p(0.7, 0.62, 0.13, 0.36, "P", -28),
		p(0.5, 0.5, 0.24, 0.62, "P", 6),
		p(0.5, 0.2, 0.17, 0.17, "P", 45),
		p(0.5, 0.52, 0.08, 0.44, "G", 6),
	},
}
CollectionView.Glyphs = GLYPHS

local function colorOf(art: Artifact, key: string): Color3
	if key == "P" then
		return art.Primary
	elseif key == "A" then
		return art.Accent
	elseif key == "G" then
		return art.Glow or art.Accent
	elseif key == "D" then
		return STAND
	elseif key == "L" then
		return PAGES
	elseif key == "T" then
		return art.Primary:Lerp(Color3.new(1, 1, 1), 0.25)
	elseif key == "K" then
		return art.Primary:Lerp(Color3.new(0, 0, 0), 0.6)
	elseif key == "W" then
		return WOOD
	end
	return ROCK
end

--[[
	Draws an artifact's flat icon into `box` (cleared first; the box keeps
	its own size and background). `silhouette`: one dark color and a "?".
]]
function CollectionView.glyph(box: Frame, artifactId: string, silhouette: boolean)
	for _, child in box:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local art = ArtifactConfig.ById[artifactId]
	local pieces = if art then GLYPHS[art.Shape] else nil
	if not art or not pieces then
		return
	end
	for i, piece in pieces do
		local frame = UIKit.new("Frame", {
			Name = "Piece" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(piece.X, piece.Y),
			Size = UDim2.fromScale(piece.W, piece.H),
			Rotation = piece.R or 0,
			BackgroundColor3 = if silhouette then CollectionView.SilhouetteColor else colorOf(art, piece.C),
			BorderSizePixel = 0,
			ZIndex = box.ZIndex + 1,
		}, box)
		local round = piece.Round
		if round and round > 0 then
			UIKit.new("UICorner", { CornerRadius = UDim.new(round / 2, 0) }, frame)
		end
	end
	if silhouette then
		UIKit.label(box, "?", 30, {
			Name = "Unknown",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Theme.TextDim,
			TextScaled = true,
			ZIndex = box.ZIndex + 2,
		})
	end
end

---------------------------------------------------------------- the book

local function tile(parent: Instance, index: number, m: Metrics): Tile
	local button = UIKit.new("TextButton", {
		Name = "Tile" .. index,
		LayoutOrder = index,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Selectable = true,
	}, parent)
	UIKit.corner(button, 12)
	UIKit.stroke(button, 2, Theme.Outline)
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.62, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, button)
	local name = UIKit.label(button, "", m.TileName, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(1, -10, 0, m.TileName * 2 + 4),
		TextWrapped = true,
		ZIndex = 3,
	})
	local chip = UIKit.chip(button, "", Theme.PanelLight, {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(96, 22),
		ZIndex = 3,
	})
	local count = UIKit.label(button, "", 15, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 4),
		Size = UDim2.fromOffset(44, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = GOLD,
		ZIndex = 3,
	})
	return { Button = button, Icon = icon, Name = name, Chip = chip, Count = count, Id = "" }
end

function CollectionView.build(compact: boolean): Refs
	local m = metrics(compact)
	local gui = UIKit.screen("TerraForgeArtifacts", 20)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 140),
		Position = UDim2.fromOffset(0, -140),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		Active = true,
	})
	local title = UIKit.label(panel, "ARTIFACTS OF KALDRUM", m.Title, {
		Name = "Title",
		Position = UDim2.fromOffset(m.Pad + 4, 10),
		Size = UDim2.new(0, 520, 0, m.Header - 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
		TextWrapped = false,
	})
	local total = UIKit.label(panel, "", 20, {
		Name = "Total",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(m.Close + 30), 0, 18),
		Size = UDim2.fromOffset(200, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(m.Close, m.Close),
		TextSize = 26,
	})
	-- tabs: one per collection
	local tabs: { [string]: TextButton } = {}
	local tabList: { TextButton } = {}
	local tabColumn = UIKit.new("Frame", { Name = "Tabs", BackgroundTransparency = 1 }, panel)
	UIKit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	for i, collection in ArtifactConfig.Collections do
		local button = UIKit.button(tabColumn, "", Theme.PanelLight, Theme.PanelDark, {
			Name = collection.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, m.TabHeight),
		})
		UIKit.new("Frame", {
			Name = "Stripe",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(0, 8, 1, -16),
			BackgroundColor3 = collection.Color,
			BorderSizePixel = 0,
		}, button)
		UIKit.label(button, collection.Name, m.Body, {
			Name = "Label",
			Position = UDim2.fromOffset(24, 4),
			Size = UDim2.new(1, -30, 0.6, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		})
		UIKit.label(button, "", m.Body - 1, {
			Name = "Progress",
			Position = UDim2.new(0, 24, 0.6, -2),
			Size = UDim2.new(1, -30, 0.4, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
		})
		local badge = UIKit.chip(button, "NEW", Theme.Bad, {
			Name = "New",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, -8),
			Size = UDim2.fromOffset(52, 22),
			Visible = false,
			ZIndex = 4,
		})
		badge.TextSize = 14
		tabs[collection.Id] = button
		table.insert(tabList, button)
	end
	-- the tiles
	local grid = UIKit.new("Frame", { Name = "Grid", BackgroundTransparency = 1 }, panel)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(130, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = CollectionView.Columns,
	}, grid)
	local tiles: { Tile } = {}
	local most = 0
	for _, list in ArtifactConfig.ByCollection do
		most = math.max(most, #list)
	end
	for i = 1, most do
		table.insert(tiles, tile(grid, i, m))
	end
	-- the detail column
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(detail, 12)
	local detailIcon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, detail)
	UIKit.corner(detailIcon, 14)
	local detailName = UIKit.label(detail, "", m.Body + 3, {
		Name = "Name",
		Position = UDim2.fromOffset(10, 126),
		Size = UDim2.new(1, -20, 0, (m.Body + 3) * 2 + 4),
		TextWrapped = true,
	})
	local detailChip = UIKit.chip(detail, "", Theme.PanelLight, {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(110, 24),
	})
	local detailCount = UIKit.label(detail, "", m.Body - 1, {
		Name = "Count",
		Size = UDim2.new(1, -20, 0, m.Body + 4),
		TextColor3 = GOLD,
		TextWrapped = false,
	})
	local detailLore = UIKit.label(detail, "", m.Body - 1, {
		Name = "Lore",
		TextColor3 = Theme.Text,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
	local detailWhere = UIKit.label(detail, "", m.Body - 3, {
		Name = "Where",
		AnchorPoint = Vector2.new(0, 1),
		TextColor3 = Theme.TextDim,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true,
	})
	-- the footer: reward and chapter
	local footer = UIKit.new("Frame", { Name = "Footer", BackgroundTransparency = 1 }, panel)
	local reward = UIKit.label(footer, "", m.Body - 1, {
		Name = "Reward",
		Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
	})
	local chapter = UIKit.button(footer, "READ CHAPTER", Theme.Accent, Theme.AccentDark, {
		Name = "Chapter",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 4),
		Size = UDim2.fromOffset(330, m.Button),
		TextSize = if compact then 22 else 20,
		TextWrapped = true,
	})
	local hint = UIKit.label(panel, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	return {
		Gui = gui,
		Dim = dim,
		Panel = panel,
		Title = title,
		Total = total,
		Close = close,
		Tabs = tabs,
		TabList = tabList,
		Grid = grid,
		Tiles = tiles,
		Detail = detail,
		DetailIcon = detailIcon,
		DetailName = detailName,
		DetailChip = detailChip,
		DetailCount = detailCount,
		DetailLore = detailLore,
		DetailWhere = detailWhere,
		Footer = footer,
		Reward = reward,
		Chapter = chapter,
		Hint = hint,
		Collection = ArtifactConfig.Collections[1].Id,
		Selected = nil,
		Compact = compact,
	}
end

-- Fits the book into `maxWidth` x `maxHeight` design units.
function CollectionView.layout(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local width = math.min(m.Width, maxWidth - 16)
	local height = math.min(m.Height, maxHeight - 12)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	local pad = m.Pad
	local hintH = m.Hint + 8
	local top = m.Header
	local bottom = height - pad - hintH
	local bodyH = bottom - top - m.Footer
	-- tabs on the left
	local firstHolder = refs.TabList[1].Parent
	local tabColumn = if firstHolder then firstHolder.Parent else nil
	local tabH = math.min(m.TabHeight, math.floor((bodyH + m.Footer - 8 * (#refs.TabList - 1)) / math.max(1, #refs.TabList)))
	if tabColumn and tabColumn:IsA("Frame") then
		tabColumn.Position = UDim2.fromOffset(pad, top)
		tabColumn.Size = UDim2.fromOffset(m.TabWidth, bodyH + m.Footer)
	end
	for _, button in refs.TabList do
		local holder = button.Parent
		if holder and holder:IsA("Frame") then
			holder.Size = UDim2.new(1, 0, 0, tabH)
		end
	end
	-- the detail column on the right
	-- (it starts below the X, which reaches under the header on phones)
	local detailW = math.min(m.DetailWidth, math.floor(width * 0.3))
	local detailTop = math.max(top, 8 + m.Close + 6)
	local detailH = bodyH - (detailTop - top)
	refs.Detail.Position = UDim2.fromOffset(width - pad - detailW, detailTop)
	refs.Detail.Size = UDim2.fromOffset(detailW, detailH)
	-- the tiles between
	local gridX = pad + m.TabWidth + pad
	local gridW = width - gridX - pad - detailW - pad
	local rows = math.ceil(#refs.Tiles / CollectionView.Columns)
	local gap = 10
	local cellW = math.floor((gridW - gap * (CollectionView.Columns - 1)) / CollectionView.Columns)
	local cellH = math.floor((bodyH - gap * (rows - 1)) / rows)
	-- square icons in every tile (the glyphs are drawn in a square box); short
	-- tiles (small phones) drop the rarity chip (the detail column shows it)
	local nameH = m.TileName * 2 + 4
	local withChip = cellH >= nameH + 22 + 90
	local iconSize = math.floor(math.min(cellW * 0.66, cellH - nameH - (if withChip then 40 else 16)))
	for _, t in refs.Tiles do
		t.Icon.Size = UDim2.fromOffset(math.max(24, iconSize), math.max(24, iconSize))
		local chipHolder = t.Chip
		chipHolder.Visible = withChip
		t.Name.Position = UDim2.new(0.5, 0, 1, if withChip then -30 else -6)
	end
	refs.Grid.Position = UDim2.fromOffset(gridX, top)
	refs.Grid.Size = UDim2.fromOffset(gridW, bodyH)
	local layout = refs.Grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
		layout.CellPadding = UDim2.fromOffset(gap, gap)
	end
	-- the footer under the tiles and the detail column
	refs.Footer.Position = UDim2.fromOffset(gridX, top + bodyH + 6)
	refs.Footer.Size = UDim2.fromOffset(width - gridX - pad, m.Footer - 6)
	local chapterHolder = refs.Chapter.Parent
	if chapterHolder and chapterHolder:IsA("Frame") then
		chapterHolder.Size = UDim2.fromOffset(math.min(360, math.floor((width - gridX - pad) * 0.5)), m.Button)
	end
	refs.Reward.Size = UDim2.new(0.5, -12, 1, 0)
	refs.Hint.Position = UDim2.fromOffset(pad, height - 6)
	refs.Hint.Size = UDim2.fromOffset(width - 2 * pad, m.Hint + 4)
	-- the detail column's inside follows its size
	local icon = math.min(110, math.floor(detailH * 0.3))
	refs.DetailIcon.Size = UDim2.fromOffset(icon, icon)
	local y = 10 + icon + 6
	local detailNameH = (m.Body + 3) * 2 + 4
	refs.DetailName.Position = UDim2.fromOffset(10, y)
	refs.DetailName.Size = UDim2.new(1, -20, 0, detailNameH)
	y += detailNameH + 2
	local chipHolder = refs.DetailChip
	chipHolder.Position = UDim2.new(0.5, 0, 0, y)
	y += 28
	refs.DetailCount.Position = UDim2.fromOffset(10, y)
	local whereH = (m.Body - 3) * 3 + 6
	refs.DetailCount.Visible = y + m.Body + 4 <= detailH - whereH - 8
	y += m.Body + 6
	local loreH = detailH - y - whereH - 14
	refs.DetailLore.Position = UDim2.fromOffset(12, y)
	refs.DetailLore.Size = UDim2.new(1, -24, 0, math.max(20, loreH))
	-- no room for two lines of lore (small phones): the lore waits for a bigger screen
	refs.DetailLore.Visible = loreH >= (m.Body - 1) * 2 + 4
	refs.DetailWhere.Position = UDim2.new(0, 12, 1, -8)
	refs.DetailWhere.Size = UDim2.new(1, -24, 0, whereH)
end

-- The biggest text size (from `size` down to 70 % of it) at which `text`
-- fits in two lines of `width` design units (a generous estimate of the
-- fonts' letter widths, so it never overflows on screen).
function CollectionView.fitSize(text: string, size: number, width: number): number
	local smallest = math.floor(size * 0.7)
	for s = size, smallest, -1 do
		local perLine = math.max(1, math.floor(width / (s * 0.68)))
		local lines, line = 1, 0
		for word in text:gmatch("%S+") do
			local need = if line == 0 then #word else line + 1 + #word
			if need > perLine and line > 0 then
				lines += 1
				line = #word
			else
				line = need
			end
		end
		if lines <= 2 then
			return s
		end
	end
	return smallest
end

-- Fills the tabs, tiles, detail and footer from a data.Artifacts record.
function CollectionView.fill(refs: Refs, artifacts: any)
	local unique = ArtifactConfig.uniqueCount(artifacts)
	refs.Total.Text = `{unique} / {#ArtifactConfig.List} found`
	for _, collection in ArtifactConfig.Collections do
		local button = refs.Tabs[collection.Id]
		if button then
			local found, count = CollectionView.progress(artifacts, collection.Id)
			local complete = found >= count and count > 0
			local progress = button:FindFirstChild("Progress") :: TextLabel?
			if progress then
				progress.Text = if complete then `{found} / {count}  ✓ complete` else `{found} / {count} found`
				progress.TextColor3 = if complete then Theme.Good else Theme.TextDim
			end
			local badge = button:FindFirstChild("New") :: TextLabel?
			if badge then
				badge.Visible = CollectionView.chapterNew(artifacts, collection.Id)
			end
			local selected = collection.Id == refs.Collection
			button.BackgroundColor3 = if selected then collection.Color:Lerp(Theme.Panel, 0.45) else Theme.PanelLight
		end
	end
	local list: { Artifact } = ArtifactConfig.ByCollection[refs.Collection] or {}
	local grid = refs.Grid:FindFirstChildOfClass("UIGridLayout")
	local cellWidth = if grid then grid.CellSize.X.Offset else 130
	for i, t in refs.Tiles do
		local art = list[i]
		t.Button.Visible = art ~= nil
		if art then
			t.Id = art.Id
			local count = ArtifactConfig.countOf(artifacts, art.Id)
			local found = count > 0
			local rarity = Rarity.get(art.Rarity)
			CollectionView.glyph(t.Icon, art.Id, not found)
			t.Name.Text = if found then art.Name else CollectionView.MissingName
			t.Name.TextSize = CollectionView.fitSize(t.Name.Text, metrics(refs.Compact).TileName, cellWidth - 10)
			t.Name.TextColor3 = if found then Theme.Text else Theme.TextDim
			t.Chip.Text = rarity.Name
			t.Chip.BackgroundColor3 = if found then rarity.Color else rarity.DarkColor
			t.Count.Text = if count > 1 then `x{count}` else ""
			local selected = refs.Selected == art.Id
			t.Button.BackgroundColor3 = if selected then Theme.PanelLight elseif found then Theme.PanelDark else Color3.fromRGB(22, 15, 14)
			local stroke = t.Button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected then GOLD else Theme.Outline
				stroke.Thickness = if selected then 3 else 2
			end
		end
	end
	-- the detail of the selected artifact (the first of the collection when none)
	local selectedId = refs.Selected
	local art = if selectedId then ArtifactConfig.ById[selectedId] else nil
	if not art or art.Collection ~= refs.Collection then
		art = list[1]
	end
	if art then
		local count = ArtifactConfig.countOf(artifacts, art.Id)
		local found = count > 0
		local rarity = Rarity.get(art.Rarity)
		CollectionView.glyph(refs.DetailIcon, art.Id, not found)
		refs.DetailName.Text = if found then art.Name else CollectionView.MissingName
		refs.DetailChip.Text = rarity.Name
		refs.DetailChip.BackgroundColor3 = if found then rarity.Color else rarity.DarkColor
		refs.DetailCount.Text = if found then `Found: {count}` else "Not found yet"
		refs.DetailLore.Text = if found then art.Lore else "Break rocks to find it. Rarer artifacts turn up deeper."
		refs.DetailWhere.Text = CollectionView.whereText(art.Id)
	end
	refs.Reward.Text = CollectionView.rewardText(refs.Collection)
	local text, enabled = CollectionView.chapterButton(artifacts, refs.Collection)
	refs.Chapter.Text = text
	refs.Chapter:SetAttribute("Enabled", enabled)
	refs.Chapter.BackgroundColor3 = if enabled then Theme.Accent else Color3.fromRGB(110, 98, 92)
	local holder = refs.Chapter.Parent
	if holder and holder:IsA("Frame") then
		holder.BackgroundColor3 = if enabled then Theme.AccentDark else Color3.fromRGB(64, 56, 52)
	end
end

---------------------------------------------------------------- the reveal card

function CollectionView.buildReveal(compact: boolean): RevealRefs
	local gui = UIKit.screen("TerraForgeArtifactReveal", 25)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local width, height = if compact then 620 else 560, if compact then 520 else 470
	local card = UIKit.panel(gui, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Active = true,
	})
	local title = UIKit.label(card, "ARTIFACT FOUND!", if compact then 38 else 36, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
	})
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, card)
	UIKit.corner(icon, 16)
	UIKit.stroke(icon, 3, GOLD)
	local body = if compact then 20 else 18
	local name = UIKit.label(card, "", body + 8, {
		Name = "Name",
		Position = UDim2.fromOffset(16, 188),
		Size = UDim2.new(1, -32, 0, body + 12),
		TextWrapped = false,
	})
	local chip = UIKit.chip(card, "", Theme.PanelLight, {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 222),
		Size = UDim2.fromOffset(120, 24),
	})
	local progress = UIKit.label(card, "", body, {
		Name = "Progress",
		Position = UDim2.fromOffset(16, 252),
		Size = UDim2.new(1, -32, 0, body + 6),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local lore = UIKit.label(card, "", body - 1, {
		Name = "Lore",
		Position = UDim2.fromOffset(28, 282),
		Size = UDim2.new(1, -56, 0, (body - 1) * 2 + 8),
		TextWrapped = true,
	})
	local extra = UIKit.label(card, "", body, {
		Name = "Extra",
		Position = UDim2.fromOffset(20, 282 + (body - 1) * 2 + 10),
		Size = UDim2.new(1, -40, 0, body * 3 + 8),
		TextColor3 = Theme.Good,
		TextWrapped = true,
	})
	local buttonH = if compact then 72 else 54
	local book = UIKit.button(card, "OPEN BOOK", Theme.Info, Color3.fromRGB(38, 110, 186), {
		Name = "Book",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -14),
		Size = UDim2.fromOffset(200, buttonH),
		TextSize = 22,
	})
	local ok = UIKit.button(card, "OK", Theme.Accent, Theme.AccentDark, {
		Name = "Ok",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -14),
		Size = UDim2.fromOffset(200, buttonH),
		TextSize = 24,
	})
	if compact then
		-- phones and TVs: the icon left, the texts beside it, low enough for a 320 pt phone
		card.Size = UDim2.fromOffset(900, 380)
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromOffset(28, 70)
		icon.Size = UDim2.fromOffset(170, 170)
		local x = 224
		local left = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(x, 62)
		name.Size = UDim2.new(1, -x - 20, 0, body + 12)
		name.TextXAlignment = left
		chip.AnchorPoint = Vector2.new(0, 0)
		chip.Position = UDim2.fromOffset(x, 102)
		progress.Position = UDim2.fromOffset(x + 136, 100)
		progress.Size = UDim2.new(1, -x - 156, 0, body + 6)
		progress.TextXAlignment = left
		lore.Position = UDim2.fromOffset(x, 136)
		lore.Size = UDim2.new(1, -x - 24, 0, (body - 1) * 3 + 8)
		lore.TextXAlignment = left
		extra.Position = UDim2.fromOffset(x, 136 + (body - 1) * 3 + 12)
		extra.Size = UDim2.new(1, -x - 24, 0, body * 2 + 8)
		extra.TextXAlignment = left
	end
	return {
		Gui = gui,
		Card = card,
		Icon = icon,
		Title = title,
		Name = name,
		Chip = chip,
		Progress = progress,
		Lore = lore,
		Extra = extra,
		Book = book,
		Ok = ok,
		Compact = compact,
	}
end

-- Shrinks the card to fit `maxWidth` x `maxHeight` design units (small
-- phones): its one UIScale "Fit" (the open animation tweens it). Returns the fit.
function CollectionView.fitReveal(refs: RevealRefs, maxWidth: number, maxHeight: number): number
	local size = refs.Card.Size
	local fit = math.min(1, (maxWidth - 16) / size.X.Offset, (maxHeight - 12) / size.Y.Offset)
	local scale = refs.Card:FindFirstChild("Fit") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "Fit"
		made.Parent = refs.Card
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = fit
	refs.Card:SetAttribute("Fit", fit)
	return fit
end

-- The card's texts for an ArtifactFound payload and the save after it.
function CollectionView.revealText(found: { [string]: any }, artifacts: any): (string, string, string)
	local id = tostring(found.Artifact)
	local art = ArtifactConfig.ById[id]
	if not art then
		return "ARTIFACT FOUND!", "", ""
	end
	local collection = ArtifactConfig.CollectionById[art.Collection]
	local have, total = CollectionView.progress(artifacts, art.Collection)
	local progress = `{if collection then collection.Name else art.Collection}: {have} / {total}`
	local title = if found.New == true then "NEW ARTIFACT!" else "ARTIFACT FOUND!"
	local extra = ""
	if found.Completed == true then
		title = "COLLECTION COMPLETE!"
		local chapter = StoryConfig.ByCollection[art.Collection]
		extra = `Chapter {if chapter then chapter.Number else "?"} unlocked! ` .. CollectionView.rewardText(art.Collection)
	elseif found.New ~= true then
		local shards = tonumber(found.Shards) or 0
		extra = if shards > 0 then `A copy: +{shards} Shards` else "A copy"
	end
	return title, progress, extra
end

-- Fills the card for an ArtifactFound payload.
function CollectionView.showReveal(refs: RevealRefs, found: { [string]: any }, artifacts: any)
	local id = tostring(found.Artifact)
	local art = ArtifactConfig.ById[id]
	if not art then
		return
	end
	local rarity = Rarity.get(art.Rarity)
	local title, progress, extra = CollectionView.revealText(found, artifacts)
	refs.Title.Text = title
	CollectionView.glyph(refs.Icon, id, false)
	local stroke = refs.Icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.Color
	end
	refs.Name.Text = art.Name
	refs.Chip.Text = rarity.Name
	refs.Chip.BackgroundColor3 = rarity.Color
	refs.Progress.Text = progress
	refs.Lore.Text = art.Lore
	refs.Extra.Text = extra
	refs.Extra.TextColor3 = if found.Completed == true then GOLD else Theme.Good
	refs.Book.Text = if found.Completed == true then "READ CHAPTER" else "OPEN BOOK"
	refs.Gui.Enabled = true
end

return CollectionView
