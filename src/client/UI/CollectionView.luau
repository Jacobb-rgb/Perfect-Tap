--[[
	The artifact collection book and the ARTIFACT FOUND card (step 7): pure
	builders, layout math and texts (ArtifactController fills them in and
	handles input; the Lune preview builds the same views).

	  book    "ARTIFACTS OF KALDRUM", how many of all are found, JOURNAL
	          (the journal, the Prologue always open), an X (B / Backspace
	          close it too). Left: one tab per collection
	          (its color, "3 / 6", a check when complete, NEW while its
	          chapter is unread; LB / RB switch). Middle: the collection's
	          artifacts as tiles, found ones in color with their name and
	          rarity, missing ones as dark silhouettes ("???", rarity shown).
	          Right: the selected artifact (name, rarity; under them a
	          scrolling text: how many, its lore once found, where it turns
	          up most with the exact chance per rock there and, for a
	          missing one, how shards can restore it; small phones put the
	          icon beside the name so the text gets the room). Bottom: the
	          collection's reward, USE TITLE + SKIN once it is complete (IN
	          USE when its title and podium skin show), RESTORE: N SHARDS
	          while exactly one artifact is missing (ArtifactConfig.
	          restoreQuote; greyed while it can't be paid or its mine isn't
	          open) and the chapter button ("READ CHAPTER 1", or what
	          unlocks it).
	  banner  its own ScreenGui: the small NEW ARTIFACT! note at the left
	          under the coins (icon, name, rarity, collection progress, a
	          BOOK button and a key hint on a keyboard; shorter without
	          one). Not modal: it takes no gamepad selection and leaves the
	          thumbstick and jump areas free.
	  reveal  its own ScreenGui: the big COLLECTION COMPLETE card (the relic's
	          icon, name, rarity, collection progress, its lore, the reward
	          and the chapter) with READ CHAPTER and OK.
	  menu    the BOOK button for the HUD's right-side menu (a NEW badge
	          while a chapter is unread; only without the side menu).
	  title   the BillboardGui with a player's collection title over their head.
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
local UIConfig = require(Shared.Config.UIConfig)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local Rarity = require(Shared.Config.Rarity)
local StatConfig = require(Shared.Config.StatConfig)
local StoryConfig = require(Shared.Config.StoryConfig)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

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
	Journal: TextButton,
	Close: TextButton,
	Tabs: { [string]: TextButton },
	TabList: { TextButton },
	Grid: Frame,
	Tiles: { Tile },
	Detail: Frame,
	DetailIcon: Frame,
	DetailName: TextLabel,
	DetailChip: TextLabel,
	DetailBody: ScrollingFrame,
	DetailCount: TextLabel,
	DetailLore: TextLabel,
	DetailWhere: TextLabel,
	DetailRestore: TextLabel, -- how shards restore a missing one ("" = hidden)
	Footer: Frame,
	Reward: TextLabel,
	Use: TextButton,
	Restore: TextButton,
	Chapter: TextButton,
	Hint: TextLabel,
	Collection: string,
	Selected: string?,
	Compact: boolean,
	Short: boolean, -- the detail column is short (small phones): icon beside the name
}

export type BannerRefs = {
	Gui: ScreenGui,
	Card: Frame,
	Icon: Frame,
	Title: TextLabel,
	Name: TextLabel,
	Chip: TextLabel,
	Progress: TextLabel,
	Book: TextButton,
	Keys: Frame,
	BookGlyph: ImageLabel,
	BookKey: TextLabel,
	CloseGlyph: ImageLabel,
	CloseKey: TextLabel,
	Compact: boolean,
}

export type MenuRefs = { Button: TextButton, New: TextLabel }

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
-- The detail column's head: tall (a big icon over the name and the rarity)
-- when the text under it still fits without scrolling for every artifact
-- (CollectionView.detailNeed; the icon may shrink to MinTallIcon for that),
-- else side by side (the icon beside the name: phones). Always side by side
-- under ShortDetail design units.
CollectionView.ShortDetail = 260
CollectionView.MinTallIcon = 56
CollectionView.NotFoundLore = "Break rocks to find it. Rarer artifacts turn up deeper."
CollectionView.RestoreHint = "The last missing artifact of a collection can be restored with crystal shards."
CollectionView.SilhouetteColor = Color3.fromRGB(34, 28, 32)
CollectionView.MissingName = "???"

local RESTORE_TEXT = Color3.fromRGB(140, 210, 245)
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

-- Lines `text` needs at `size` in `width` design units (a generous estimate
-- of the fonts' letter widths, so a box sized from it never clips).
function CollectionView.textLines(text: string, size: number, width: number): number
	local perLine = math.max(1, math.floor(width / (size * 0.56)))
	local lines = 0
	for paragraph in (text .. "\n"):gmatch("(.-)\n") do
		local count, line = 1, 0
		for word in paragraph:gmatch("%S+") do
			local need = if line == 0 then #word else line + 1 + #word
			if need > perLine and line > 0 then
				count += 1
				line = #word
			else
				line = need
			end
		end
		lines += count
	end
	return math.max(1, lines)
end

-- Height of `text` at `size` in `width` design units (textLines lines).
function CollectionView.textHeight(text: string, size: number, width: number): number
	return math.ceil(CollectionView.textLines(text, size, width) * size * 1.25 + 4)
end

-- The biggest text size from `size` down to `smallest` at which `text`
-- fits a `width` x `height` box (`smallest` when nothing fits).
function CollectionView.fitBox(text: string, size: number, smallest: number, width: number, height: number): number
	for s = size, smallest, -1 do
		if CollectionView.textHeight(text, s, width) <= height then
			return s
		end
	end
	return smallest
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

-- Found / total of a collection in a data.Artifacts record. `alsoFound`: an
-- artifact to count as found even when the record doesn't have it yet (a
-- find whose State push hasn't arrived).
function CollectionView.progress(artifacts: any, collectionId: string, alsoFound: string?): (number, number)
	local list: { Artifact } = ArtifactConfig.ByCollection[collectionId] or {}
	local found = 0
	for _, art in list do
		if art.Id == alsoFound or ArtifactConfig.countOf(artifacts, art.Id) > 0 then
			found += 1
		end
	end
	return found, #list
end

-- Is the reward of this collection the one that shows (title + podium skin)?
function CollectionView.inUse(artifacts: any, collectionId: string): boolean
	return ArtifactConfig.equipped(artifacts) == collectionId
end

-- The USE button of a completed collection: its text, and the Equip
-- argument a press sends ("" takes the reward off again).
function CollectionView.useButton(artifacts: any, collectionId: string): (string, string)
	if CollectionView.inUse(artifacts, collectionId) then
		return "IN USE", ""
	end
	return "USE TITLE + SKIN", collectionId
end

-- What the book knows about the player besides the record (State snapshot).
export type Wallet = { BlasterLevel: number, Shards: number, Vip: boolean? }

--[[
	The RESTORE button of a collection with exactly one artifact missing:
	(text, the artifact a press restores or nil when it can't be pressed
	now, the reason code then). nil text: no button (complete, or more than
	one missing).
]]
function CollectionView.restoreButton(artifacts: any, collectionId: string, wallet: Wallet): (string?, string?, string?)
	local missing = ArtifactConfig.lastMissing(artifacts, collectionId)
	local art = if missing then ArtifactConfig.ById[missing] else nil
	if not missing or not art then
		return nil, nil, nil
	end
	local cost = ArtifactConfig.RestoreShards[art.Rarity] or 0
	local price, reason = ArtifactConfig.restoreQuote(artifacts, missing, wallet.BlasterLevel, wallet.Shards, wallet.Vip)
	local text = `RESTORE: {Format.commas(cost)} SHARDS`
	if price then
		return text, missing, nil
	end
	return text, nil, reason
end

-- The restore line under a missing artifact's "where" (nil: found already).
function CollectionView.restoreText(artifacts: any, artifactId: string, wallet: Wallet): string?
	local art = ArtifactConfig.ById[artifactId]
	if not art or ArtifactConfig.countOf(artifacts, artifactId) > 0 then
		return nil
	end
	if ArtifactConfig.lastMissing(artifacts, art.Collection) ~= artifactId then
		return CollectionView.RestoreHint
	end
	local cost = Format.commas(ArtifactConfig.RestoreShards[art.Rarity] or 0)
	local _, reason = ArtifactConfig.restoreQuote(artifacts, artifactId, wallet.BlasterLevel, wallet.Shards, wallet.Vip)
	if reason == "Locked" then
		return `The last one missing! Restore it for {cost} shards once your blaster opens a mine where it turns up.`
	elseif reason == "NoShards" then
		return `The last one missing! Restore it for {cost} shards (you have {Format.commas(wallet.Shards)}). Copies and the wheel give shards.`
	end
	return `The last one missing! RESTORE it for {cost} shards (you have {Format.commas(wallet.Shards)}).`
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
		Pop.text(box, "?", 30, {
			Name = "Unknown",
			Size = UDim2.fromScale(1, 1),
			FontFace = PopTheme.Heavy,
			TextColor3 = Color3.fromRGB(214, 220, 236),
			TextScaled = true,
			ZIndex = box.ZIndex + 2,
		})
	end
end

---------------------------------------------------------------- the Pop pieces

-- the book's colour (its band; LightSkin.BandRoles "Artifacts")
CollectionView.Paint = "Yellow"
-- a missing artifact's card: a dark slate (a silhouette and "?" on it)
CollectionView.HiddenPaint = {
	Top = Color3.fromRGB(70, 74, 88),
	Bottom = Color3.fromRGB(34, 36, 46),
	Edge = PopTheme.Outline,
} :: Pop.Paint
CollectionView.SelectColor = Color3.fromRGB(255, 222, 64) -- the picked card's gold outline
CollectionView.SoftInk = Color3.fromRGB(206, 214, 232)
CollectionView.OffPaint = PopTheme.Gray -- a button that can't be pressed now

-- A paint from one colour (a collection's): lighter at the top, deeper at the bottom.
-- (saturated like the shop's paints: a bright top, a deep bottom)
function CollectionView.colorPaint(color: Color3): Pop.Paint
	local h, s, v = color:ToHSV()
	return {
		Top = Color3.fromHSV(h, math.clamp(s * 0.9, 0, 1), 1),
		Bottom = Color3.fromHSV(h, math.clamp(s * 1.15 + 0.1, 0, 1), math.clamp(v * 0.72, 0, 1)),
		Edge = PopTheme.Outline,
	}
end

-- A rarity's chip colour: its paint's deep end (white words read on it).
function CollectionView.chipColor(rarity: string): Color3
	return Pop.rarityPaint(rarity).Bottom:Lerp(Color3.new(0, 0, 0), 0.3)
end

-- A round chip label (UIKit.chip) in the Pop look: a solid colour, a black
-- border, white words with a black edge.
local function chip(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local label = UIKit.chip(parent, text, PopTheme.Paints.Slate.Bottom, props)
	label.FontFace = PopTheme.Font
	label.TextColor3 = PopTheme.Ink
	local corner = label:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	for _, stroke in label:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke.Color = PopTheme.Outline
			stroke.Thickness = if stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then 2.5 else 1.6
		end
	end
	return label
end

--[[
	A painted Pop button: the holder is the painted face (studs, the light
	rim; layouts size the holder like UIKit.button's lip holder), the
	TextButton over it is clear and shows its own Text (white, a black
	edge), so a controller that sets .Text ("CLICK AGAIN TO PAY") shows it.
	Props go to the holder (Size, Position, AnchorPoint, LayoutOrder,
	Visible) or the button; the holder is named props.Name .. "Holder".
]]
local function popButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }): TextButton
	local holder = UIKit.new("Frame", {
		Name = (props.Name or text) .. "Holder",
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 3,
	}, parent)
	Pop.face(holder, paint)
	Pop.studs(holder, PopTheme.Corner, 0.45, 28, 3)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		FontFace = PopTheme.Font,
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = PopTheme.Ink,
		TextSize = 22,
		ZIndex = 5,
	}, holder)
	Pop.edge(button, 2.2)
	for key, value in props do
		if key == "Size" or key == "Position" or key == "AnchorPoint" or key == "LayoutOrder" or key == "Visible" then
			(holder :: any)[key] = value
		elseif key ~= "Name" then
			(button :: any)[key] = value
		end
	end
	return button
end
CollectionView.popButton = popButton

-- Recolours a popButton (its holder's paint).
local function repaintButton(button: TextButton, paint: string | Pop.Paint)
	local holder = button.Parent
	if holder and holder:IsA("GuiObject") then
		Pop.repaint(holder, paint)
	end
end

-- The red square X in a holder (the holder is what layouts and the touch tests size).
local function closeButton(parent: Instance, size: number, props: { [string]: any }): TextButton
	local holder = UIKit.new("Frame", {
		Name = "CloseHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
	}, parent)
	for key, value in props do
		(holder :: any)[key] = value
	end
	return Pop.close(holder, size, { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
end

-- The light burst of a card: rays, glows and sparkles (marked "Fx"; hidden on a missing artifact).
local function markFx(card: GuiObject)
	for _, child in card:GetChildren() do
		local name = child.Name
		if child:IsA("GuiObject") and (name == "Rays" or string.sub(name, 1, 4) == "Glow" or string.sub(name, 1, 7) == "Sparkle") then
			child:SetAttribute("Fx", true)
		end
	end
end

local function setFx(card: GuiObject, on: boolean)
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("Fx") then
			child.Visible = on
		end
	end
end

-- Moves a card's light burst (rays and glows, not the sparkles) to `centre`.
local function centreFx(card: GuiObject, centre: UDim2)
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("Fx") and string.sub(child.Name, 1, 7) ~= "Sparkle" then
			child.Position = centre
		end
	end
end

--[[
	Paints a Frame like Pop.card (a pane, not a button): the paint, light
	rays and a soft glow around `centre`, the studs, the light rim and a few
	sparkles. It clips its rays.
]]
local function paintFrame(frame: Frame, paint: string | Pop.Paint, centre: UDim2, long: number, short: number)
	local p = Pop.paint(paint)
	Pop.face(frame, p, PopTheme.Corner + 2, false)
	frame.ClipsDescendants = true
	local rays = Pop.fx(frame, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = centre,
		Size = UDim2.fromOffset(long * 2.2, long * 2.2),
		ZIndex = 2,
	})
	if not rays then
		Pop.rays(frame, centre, 10, long, 0.6, 2)
	end
	local glow = Pop.fx(frame, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = 0.3,
		Position = centre,
		Size = UDim2.fromOffset(math.floor(short * 1.1), math.floor(short * 1.1)),
		ZIndex = 2,
	})
	if not glow then
		for i, k in { 0.62, 0.42 } do
			local disc = UIKit.new("Frame", {
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = if i == 1 then 0.8 else 0.7,
				BorderSizePixel = 0,
				Position = centre,
				Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
				ZIndex = 2,
			}, frame)
			UIKit.corner(disc, 999)
		end
	end
	Pop.studs(frame, PopTheme.Corner + 2, 0.5, 44, 3)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	for i, spot in { { 0.16, 0.08, 22 }, { 0.86, 0.14, 18 }, { 0.8, 0.3, 14 } } do
		Pop.sparkle(frame, UDim2.fromScale(spot[1], spot[2]), spot[3], 3, 0.15 + i * 0.08)
	end
	markFx(frame)
end

--[[
	A Pop window's chrome on a panel (black frame, the dark studded floor,
	the bright header band in the book's colour); `header` = the band's
	height (layoutChrome resizes it).
]]
local function chrome(panel: Frame, paint: string | Pop.Paint, header: number)
	panel.BackgroundColor3 = PopTheme.Outline
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	local old = panel:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, PopTheme.WindowCorner + 2)
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = PopTheme.Outline
		stroke.Thickness = 4
	end
	local back = UIKit.new("Frame", {
		Name = "Back",
		BackgroundColor3 = PopTheme.Body,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, panel)
	UIKit.corner(back, 6)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 198, 206)), Rotation = 90 }, back)
	Pop.studs(back, 6, 0.55, 36, 0)
	local band = UIKit.new("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(4, 4),
		ZIndex = 0,
	}, panel)
	Pop.face(band, paint, 6, false)
	local border = band:FindFirstChild("Border") :: UIStroke
	border.Thickness = 3
	Pop.studs(band, 6, 0.35, 40, 0)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 0,
	}, band)
	for i, s in { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.6, 0),
			ZIndex = 0,
		}, band)
	end
	CollectionView.layoutChrome(panel, header)
end

-- Sizes a chrome'd panel's band (`header` tall from the top) and floor (the rest).
function CollectionView.layoutChrome(panel: Frame, header: number)
	local band = panel:FindFirstChild("Band") :: Frame?
	local back = panel:FindFirstChild("Back") :: Frame?
	local h = math.max(20, header - 8)
	if band then
		band.Size = UDim2.new(1, -8, 0, h)
	end
	if back then
		back.Position = UDim2.fromOffset(4, 4 + h)
		back.Size = UDim2.new(1, -8, 1, -(8 + h))
	end
end

-- (the journal, StoryView, is built from the same pieces)
CollectionView.closeButton = closeButton
CollectionView.chrome = chrome

-- A title's drop shadow (Pop.shadow) follows its text, place and size.
local function syncShadow(label: TextLabel)
	local parent = label.Parent
	local shadow = if parent then parent:FindFirstChild(label.Name .. "Shadow") :: TextLabel? else nil
	if shadow then
		shadow.Text = label.Text
		shadow.TextSize = label.TextSize
		shadow.AnchorPoint = label.AnchorPoint
		shadow.Position = label.Position + UDim2.fromOffset(0, 3)
		shadow.Size = label.Size
		shadow.Visible = label.Visible
		shadow.TextXAlignment = label.TextXAlignment
	end
end

---------------------------------------------------------------- the book

--[[
	The pixel reels (owner 2026-10-22, docs/art/ui_pixel_refs: "the
	inventory exactly like this"): every tile is a square reel card, its
	name in pixel letters on top (two lines at most, shrunk to fit), the
	relic big in the middle on its sunburst, the rarity as a short pixel
	line at the bottom and the count as a tilted tag beside the picture.
]]
local function pixelWords(label: TextLabel, size: number)
	label.FontFace = PopTheme.Pixel
	label.TextScaled = true
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint") or UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	local l = limit :: UITextSizeConstraint
	l.MaxTextSize = math.max(8, math.floor(size * PopTheme.PixelScale + 0.5))
	l.MinTextSize = 7
	local edge = label:FindFirstChild("Edge") or label:FindFirstChildOfClass("UIStroke")
	if edge and edge:IsA("UIStroke") then
		edge.LineJoinMode = Enum.LineJoinMode.Miter
	end
end

--[[
	Long names (review 2026-10-22: "HEARTSTONE FRAGMENT" shrank to 5.6 pt
	on a 568x320 phone): a tile's name and rarity stay pixel letters while
	they are at least NameMin there, else they take the round font when it
	is bigger (it is narrower). Design units; the phones' UI scale is 0.62,
	so 13 units are 8 pt.
]]
CollectionView.NameMin = 10 -- PC
CollectionView.NameMinCompact = 13 -- phones and TVs
local PIXEL_EM, PIXEL_LINE = 1, 1.1 -- a pixel letter's width and a line's height (em; room to spare)
local ROUND_EM, ROUND_LINE = 0.6, 1.2 -- the round font's (a generous capital)

-- Lines `text` takes wrapped at `perLine` letters (math.huge: a word is longer than a line).
local function wrapLines(text: string, perLine: number): number
	local lines, line = 1, 0
	for _, word in string.split(text, " ") do
		local n = utf8.len(word) or #word
		if n > perLine then
			return math.huge
		end
		local need = if line == 0 then n else line + 1 + n
		if need > perLine then
			lines += 1
			line = n
		else
			line = need
		end
	end
	return lines
end

--[[
	The biggest whole size (at most `max`) at which `text` fits `w` x `h`
	design units in a font whose letter is `em` wide and line `line` tall
	(wrapped at spaces when `wrap`, else on one line); 1 when nothing fits.
]]
function CollectionView.wrapSize(text: string, max: number, w: number, h: number, em: number, line: number, wrap: boolean): number
	local n = utf8.len(text) or #text
	for s = math.floor(max), 2, -1 do
		local perLine = math.floor(w / (s * em))
		local lines = if wrap then wrapLines(text, perLine) else (if n <= perLine then 1 else math.huge)
		if lines * s * line <= h then
			return s
		end
	end
	return 1
end

-- A tile's word(s) in a `w` x `h` box: pixel (at most `max`) or round (at most `roundMax`), see above.
local function tileWords(label: TextLabel, max: number, roundMax: number, w: number, h: number, floor: number, wrap: boolean)
	local text = label.Text
	local pixelSize = CollectionView.wrapSize(text, max, w, h, PIXEL_EM, PIXEL_LINE, wrap)
	local roundSize = CollectionView.wrapSize(text, roundMax, w, h, ROUND_EM, ROUND_LINE, wrap)
	local round = pixelSize < floor and roundSize > pixelSize
	local size = if round then roundSize else pixelSize
	label.FontFace = if round then PopTheme.Font else PopTheme.Pixel
	label.TextWrapped = wrap
	label.TextScaled = true
	label:SetAttribute("Round", if round then true else nil)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	l.MinTextSize = 1
	l.MaxTextSize = size
	l.MinTextSize = math.min(size, 7)
	for _, edge in label:GetChildren() do
		if edge:IsA("UIStroke") and edge.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			edge.LineJoinMode = if round then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter
		end
	end
end

--[[
	The tile name box's height for names `w` units wide: two lines of
	TileName, taller (at most three round lines at the floor) while some
	artifact's name would still shrink under the floor (review 2026-10-22:
	"CHRONICLE OF THE SHATTERING" was 7 pt on a 568x320 phone).
]]
function CollectionView.nameHeight(compact: boolean, w: number): number
	local m = metrics(compact)
	local floor = if compact then CollectionView.NameMinCompact else CollectionView.NameMin
	local base = math.floor((m.TileName + 4) * PopTheme.PixelScale + 0.5)
	local h = m.TileName * 2 + 4
	local top = math.ceil(3 * floor * ROUND_LINE) + 1
	while h < top do
		local short = false
		for _, art in ArtifactConfig.List do
			local text = string.upper(art.Name)
			local pixelSize = CollectionView.wrapSize(text, base, w, h, PIXEL_EM, PIXEL_LINE, true)
			local roundSize = CollectionView.wrapSize(text, m.TileName, w, h, ROUND_EM, ROUND_LINE, true)
			if math.max(pixelSize, roundSize) < floor then
				short = true
				break
			end
		end
		if not short then
			break
		end
		h += 1
	end
	return h
end

local function tile(parent: Instance, index: number, m: Metrics): Tile
	local button = Pop.card(parent, CollectionView.HiddenPaint, {
		Name = "Tile" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(130, 150),
	}, UDim2.fromScale(0.5, 0.36))
	markFx(button)
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.62, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, button)
	-- (the reels: the pixel name on top, the rarity line at the bottom)
	local name = Pop.text(button, "", m.TileName, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 0, m.TileName * 2 + 4),
		TextWrapped = true,
		ZIndex = 7,
	})
	pixelWords(name, m.TileName + 4)
	local rarity = chip(button, "", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Size = UDim2.new(1, -16, 0, 22),
		ZIndex = 7,
	})
	pixelWords(rarity, 18)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, rarity)
	local count = Pop.text(button, "", 22, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, m.TileName * 2 + 14),
		Rotation = 10,
		Size = UDim2.fromOffset(44, 22),
		FontFace = PopTheme.Heavy,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 232, 110),
		ZIndex = 8,
	})
	Pop.fxTag(button, "Press")
	return { Button = button, Icon = icon, Name = name, Chip = rarity, Count = count, Id = "" }
end

function CollectionView.build(compact: boolean): Refs
	local m = metrics(compact)
	local gui = UIKit.screen("TerraForgeArtifacts", 20)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true)
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
	chrome(panel, CollectionView.Paint, m.Header)
	local title = Pop.text(panel, "ARTIFACTS OF KALDRUM", m.Title, {
		Name = "Title",
		Position = UDim2.fromOffset(m.Pad + 4, 10),
		Size = UDim2.new(0, 520, 0, m.Header - 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Pop.shadow(title)
	-- how many of all are found: a glossy gold bar left of JOURNAL
	local totalBar = Pop.bar(panel, 0, "Green", Vector2.new(170, 36), "", {
		Name = "TotalBar",
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 4,
	})
	local total = totalBar:FindFirstChild("Label") :: TextLabel
	-- the journal (the Prologue is always open), left of the X
	local journal = popButton(panel, "JOURNAL", "Purple", {
		Name = "Journal",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(m.Close + 20), 0, if compact then 8 else 12),
		Size = UDim2.fromOffset(if compact then 190 else 170, if compact then 72 else 46),
		TextSize = if compact then 24 else 21,
	})
	local close = closeButton(panel, m.Close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
	})
	-- tabs: one per collection, painted in its colour (the picked one bright with a gold edge)
	local tabs: { [string]: TextButton } = {}
	local tabList: { TextButton } = {}
	local tabColumn = UIKit.new("Frame", { Name = "Tabs", BackgroundTransparency = 1, ZIndex = 2 }, panel)
	UIKit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	for i, collection in ArtifactConfig.Collections do
		local button = popButton(tabColumn, "", CollectionView.colorPaint(collection.Color), {
			Name = collection.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, m.TabHeight),
		})
		local holder = button.Parent :: Frame
		-- the others wear a shade
		local shade = UIKit.new("Frame", {
			Name = "Shade",
			BackgroundColor3 = PopTheme.Outline,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, holder)
		UIKit.corner(shade, PopTheme.Corner)
		Pop.text(button, collection.Name, m.Body + 1, {
			Name = "Label",
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -20, 0.56, -4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			ZIndex = 6,
		})
		Pop.bar(button, 0, "Yellow", Vector2.new(150, 20), "", {
			Name = "Progress",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -7),
			Size = UDim2.new(1, -24, 0, 20),
			ZIndex = 6,
		})
		local badge = Pop.chip(button, "NEW", "Red", Vector2.new(52, 22), {
			Name = "New",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, -8),
			Rotation = 6,
			Visible = false,
			ZIndex = 9,
		})
		badge:SetAttribute("Badge", true)
		tabs[collection.Id] = button
		table.insert(tabList, button)
	end
	-- the tiles
	local grid = UIKit.new("Frame", { Name = "Grid", BackgroundTransparency = 1, ZIndex = 2 }, panel)
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
	-- the detail column: a bright card in the picked artifact's rarity colour
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		BorderSizePixel = 0,
		ZIndex = 2,
	}, panel)
	paintFrame(detail, CollectionView.HiddenPaint, UDim2.new(0.5, 0, 0, 65), 290, 150)
	local detailIcon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(110, 110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, detail)
	local detailName = Pop.text(detail, "", m.Body + 3, {
		Name = "Name",
		Position = UDim2.fromOffset(10, 126),
		Size = UDim2.new(1, -20, 0, (m.Body + 3) * 2 + 4),
		TextWrapped = true,
		ZIndex = 7,
	})
	local detailChip = chip(detail, "", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(110, 24),
		ZIndex = 7,
	})
	-- how many, the lore and where: one scrolling text (small phones scroll) in a dark well
	Pop.well(detail, { Name = "BodyWell", ZIndex = 4 })
	local detailBody = UIKit.new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(200, 208, 226),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Selectable = true,
		ZIndex = 6,
	}, detail)
	local function line(name: string, size: number, color: Color3, wrapped: boolean): TextLabel
		return Pop.text(detailBody, "", size, {
			Name = name,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = wrapped,
			ZIndex = 7,
		})
	end
	local detailCount = line("Count", m.Body - 1, Color3.fromRGB(255, 232, 110), false)
	detailCount.TextYAlignment = Enum.TextYAlignment.Center
	local detailLore = line("Lore", m.Body - 1, PopTheme.Ink, true)
	local detailWhere = line("Where", m.Body - 3, CollectionView.SoftInk, true)
	local detailRestore = line("Restore", m.Body - 3, RESTORE_TEXT, true)
	detailRestore.Visible = false
	-- the footer: reward and chapter
	local footer = UIKit.new("Frame", { Name = "Footer", BackgroundTransparency = 1, ZIndex = 2 }, panel)
	local reward = Pop.text(footer, "", m.Body - 1, {
		Name = "Reward",
		Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = CollectionView.SoftInk,
		TextWrapped = true,
		ZIndex = 3,
	})
	local use = popButton(footer, "USE TITLE + SKIN", "Blue", {
		Name = "Use",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(210, m.Button),
		TextSize = if compact then 20 else 18,
		TextWrapped = true,
		Visible = false,
	})
	-- the last missing artifact for crystal shards (the same slot as USE: never both)
	local restore = popButton(footer, "RESTORE", "Teal", {
		Name = "Restore",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(210, m.Button),
		TextSize = if compact then 20 else 18,
		TextWrapped = true,
		Visible = false,
	})
	local chapter = popButton(footer, "READ CHAPTER", "Orange", {
		Name = "Chapter",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 4),
		Size = UDim2.fromOffset(330, m.Button),
		TextSize = if compact then 22 else 20,
		TextWrapped = true,
	})
	local hint = Pop.text(panel, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = CollectionView.SoftInk,
		ZIndex = 3,
	})
	-- (a sentence: the round font, shrunk to fit like before; round for good: a
	-- short hint filled in later stays round, Pop.sentence leaves it alone)
	hint.FontFace = PopTheme.Font
	hint:SetAttribute("Round", true)
	local hintFit = hint:FindFirstChildOfClass("UITextSizeConstraint")
	if hintFit then
		hintFit.MaxTextSize = m.Hint
	end
	return {
		Gui = gui,
		Dim = dim,
		Panel = panel,
		Title = title,
		Total = total,
		Journal = journal,
		Close = close,
		Tabs = tabs,
		TabList = tabList,
		Grid = grid,
		Tiles = tiles,
		Detail = detail,
		DetailIcon = detailIcon,
		DetailName = detailName,
		DetailChip = detailChip,
		DetailBody = detailBody,
		DetailCount = detailCount,
		DetailLore = detailLore,
		DetailWhere = detailWhere,
		DetailRestore = detailRestore,
		Footer = footer,
		Reward = reward,
		Use = use,
		Restore = restore,
		Chapter = chapter,
		Hint = hint,
		Collection = ArtifactConfig.Collections[1].Id,
		Selected = nil,
		Compact = compact,
		Short = false,
	}
end

-- The detail column's scrolling text, one under the other at their own
-- heights (the canvas grows): how many, the lore, where it turns up and how
-- shards restore it. A short column (small phones) drops the count line
-- (the tile shows "x4", a silhouette says "not found"), uses one size
-- smaller texts and puts where (+ restore) first: the useful lines are in
-- view, the lore follows.
type PutBody = (which: string, size: number, y: number, h: number) -> ()

-- Stacks the detail text `w` design units wide as placeBody shows it and
-- returns its height; `put` (optional) places each piece ("Count", "Lore",
-- "Where", "Restore") at its size, y and height.
local function stackBody(compact: boolean, short: boolean, w: number, lore: string, where: string, restore: string?, put: PutBody?): number
	local m = metrics(compact)
	local loreSize = if short then m.Body - 2 else m.Body - 1
	local whereSize = if short then m.Body - 4 else m.Body - 3
	local y = 0
	local function add(which: string, text: string, size: number, gap: number)
		local h = CollectionView.textHeight(text, size, w)
		if put then
			put(which, size, y, h)
		end
		y += h + gap
	end
	if short then
		add("Where", where, whereSize, 2)
		if restore then
			add("Restore", restore, whereSize, 2)
		end
		y += 4
		add("Lore", lore, loreSize, 4)
	else
		local countH = m.Body + 6
		if put then
			put("Count", m.Body, y, countH)
		end
		y += countH + 4
		add("Lore", lore, loreSize, 6)
		add("Where", where, whereSize, 2)
		if restore then
			add("Restore", restore, whereSize, 2)
		end
		y += 2
	end
	return y
end

-- The detail text's height (design units) at `w` wide (placeBody's canvas).
function CollectionView.bodyHeight(compact: boolean, short: boolean, w: number, lore: string, where: string, restore: string?): number
	return stackBody(compact, short, w, lore, where, restore, nil)
end

-- The tallest detail text any artifact needs at `w` wide: found (its lore),
-- or not (NotFoundLore and the restore hint every missing one shows), with
-- where it turns up. (The last missing one of a collection gets a longer
-- restore line with its price: that one rare case may scroll.)
function CollectionView.detailNeed(compact: boolean, short: boolean, w: number): number
	local need = 0
	for _, art in ArtifactConfig.List do
		local where = CollectionView.whereText(art.Id)
		need = math.max(
			need,
			CollectionView.bodyHeight(compact, short, w, art.Lore, where, nil),
			CollectionView.bodyHeight(compact, short, w, CollectionView.NotFoundLore, where, CollectionView.RestoreHint)
		)
	end
	return need
end

local function placeBody(refs: Refs)
	local width = refs.DetailBody:GetAttribute("TextWidth")
	local w = if type(width) == "number" then width else 240
	local short = refs.Short
	refs.DetailCount.Visible = not short
	refs.DetailRestore.Visible = refs.DetailRestore.Text ~= ""
	local labels: { [string]: TextLabel } = {
		Count = refs.DetailCount,
		Lore = refs.DetailLore,
		Where = refs.DetailWhere,
		Restore = refs.DetailRestore,
	}
	local restore = if refs.DetailRestore.Visible then refs.DetailRestore.Text else nil
	local height = stackBody(refs.Compact, short, w, refs.DetailLore.Text, refs.DetailWhere.Text, restore, function(which, size, y, h)
		local label = labels[which]
		if which ~= "Count" then
			label.TextSize = size
		end
		label.Position = UDim2.fromOffset(4, y)
		label.Size = UDim2.fromOffset(w, h)
	end)
	refs.DetailBody.CanvasSize = UDim2.fromOffset(0, height)
end

-- The detail name's text size: as big as fits its box.
local function fitName(refs: Refs)
	local m = metrics(refs.Compact)
	local size = refs.DetailName.Size
	refs.DetailName.TextSize = CollectionView.fitBox(refs.DetailName.Text, m.Body + 3, 14, math.max(60, size.X.Offset), size.Y.Offset)
end

-- The reward line's text size: as big as fits its box (never below 12).
local function fitReward(refs: Refs)
	local m = metrics(refs.Compact)
	local size = refs.Reward.Size
	refs.Reward.TextSize = CollectionView.fitBox(refs.Reward.Text, m.Body - 1, 12, size.X.Offset, size.Y.Offset)
end

-- Fits the book into `maxWidth` x `maxHeight` design units.
function CollectionView.layout(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local width = math.min(m.Width, maxWidth - 16)
	local height = math.min(m.Height, maxHeight - 12)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	CollectionView.layoutChrome(refs.Panel, m.Header)
	-- the header: the title, how many are found, JOURNAL and the X
	local journalHolder = refs.Journal.Parent
	local journalW = if journalHolder and journalHolder:IsA("Frame") then journalHolder.Size.X.Offset else 170
	local totalBar = refs.Total.Parent
	if totalBar and totalBar:IsA("GuiObject") then
		totalBar.Position = UDim2.new(1, -(12 + m.Close + 8 + journalW + 12), 0, math.floor(m.Header / 2) - 18)
	end
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
		-- the collection's name as big as fits above its progress bar
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextSize = CollectionView.fitBox(label.Text, m.Body + 1, 12, m.TabWidth - 24, math.floor(tabH * 0.56) - 4)
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
	local nameH = CollectionView.nameHeight(refs.Compact, cellW - 14)
	local withChip = cellH >= nameH + 22 + 90
	local iconSize = math.floor(math.min(cellW * 0.66, cellH - nameH - (if withChip then 40 else 16)))
	for _, t in refs.Tiles do
		local icon = math.max(24, iconSize)
		t.Icon.Size = UDim2.fromOffset(icon, icon)
		local chipHolder = t.Chip
		chipHolder.Visible = withChip
		-- (the reels: the name on top, the picture on its sunburst under it)
		t.Name.Position = UDim2.new(0.5, 0, 0, 6)
		t.Name.Size = UDim2.new(1, -12, 0, nameH)
		t.Count.Position = UDim2.new(1, -6, 0, nameH + 10)
		t.Icon.Position = UDim2.new(0.5, 0, 0, nameH + 8)
		centreFx(t.Button, UDim2.new(0.5, 0, 0, nameH + 8 + icon / 2))
	end
	refs.Grid.Position = UDim2.fromOffset(gridX, top)
	refs.Grid.Size = UDim2.fromOffset(gridW, bodyH)
	local layout = refs.Grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
		layout.CellPadding = UDim2.fromOffset(gap, gap)
	end
	-- the footer under the tiles and the detail column: the reward, USE and the chapter button
	local footerW = width - gridX - pad
	refs.Footer.Position = UDim2.fromOffset(gridX, top + bodyH + 6)
	refs.Footer.Size = UDim2.fromOffset(footerW, m.Footer - 6)
	local chapterW = math.min(260, math.floor(footerW * 0.34))
	local useW = math.min(200, math.floor(footerW * 0.26))
	local chapterHolder = refs.Chapter.Parent
	if chapterHolder and chapterHolder:IsA("Frame") then
		chapterHolder.Size = UDim2.fromOffset(chapterW, m.Button)
	end
	for _, button in { refs.Use, refs.Restore } do
		local holder = button.Parent
		if holder and holder:IsA("Frame") then
			holder.Position = UDim2.new(1, -(chapterW + 10), 0.5, 4)
			holder.Size = UDim2.fromOffset(useW, m.Button)
		end
	end
	refs.Reward.Size = UDim2.fromOffset(math.max(80, footerW - chapterW - useW - 24), m.Footer - 6)
	refs.Hint.Position = UDim2.fromOffset(pad, height - 6)
	refs.Hint.Size = UDim2.fromOffset(width - 2 * pad, m.Hint + 4)
	-- the detail column's inside follows its size: the icon, the name and the
	-- rarity at the top, the scrolling text under them. The tall head keeps
	-- room for the longest text (detailNeed: "Most often in ...: 1 in N" is
	-- never cut off), shrinking its icon down to MinTallIcon; a column where
	-- even that doesn't fit (phones) puts the icon beside the name and the
	-- rarity, so the lore and where it turns up get the room
	local y: number
	local detailNameH = (m.Body + 3) * 2 + 4
	local textW = detailW - 12 - 8 - 10
	local tallIcon =
		math.min(110, math.floor(detailH * 0.24), detailH - (detailNameH + 56) - CollectionView.detailNeed(refs.Compact, false, textW))
	refs.Short = detailH < CollectionView.ShortDetail or tallIcon < CollectionView.MinTallIcon
	if refs.Short then
		local icon = math.min(56, math.floor(detailH * 0.28))
		refs.DetailIcon.AnchorPoint = Vector2.new(0, 0)
		refs.DetailIcon.Position = UDim2.fromOffset(8, 8)
		refs.DetailIcon.Size = UDim2.fromOffset(icon, icon)
		local x = 8 + icon + 8
		refs.DetailName.Position = UDim2.fromOffset(x, 6)
		refs.DetailName.Size = UDim2.fromOffset(detailW - x - 8, 30)
		refs.DetailName.TextXAlignment = Enum.TextXAlignment.Left
		refs.DetailChip.AnchorPoint = Vector2.new(0, 0)
		refs.DetailChip.Position = UDim2.fromOffset(x, 38)
		y = 8 + math.max(icon, 60) + 6
	else
		local icon = tallIcon
		refs.DetailIcon.AnchorPoint = Vector2.new(0.5, 0)
		refs.DetailIcon.Position = UDim2.new(0.5, 0, 0, 10)
		refs.DetailIcon.Size = UDim2.fromOffset(icon, icon)
		y = 10 + icon + 6
		refs.DetailName.Position = UDim2.fromOffset(10, y)
		refs.DetailName.Size = UDim2.fromOffset(detailW - 20, detailNameH)
		refs.DetailName.TextXAlignment = Enum.TextXAlignment.Center
		y += detailNameH + 2
		refs.DetailChip.AnchorPoint = Vector2.new(0.5, 0)
		refs.DetailChip.Position = UDim2.new(0.5, 0, 0, y)
		y += 30
	end
	fitName(refs)
	refs.DetailBody.Position = UDim2.fromOffset(8, y)
	refs.DetailBody.Size = UDim2.new(1, -12, 0, math.max(30, detailH - y - 8))
	-- the text's dark well, and the card's light burst behind the icon
	local well = refs.Detail:FindFirstChild("BodyWell") :: Frame?
	if well then
		well.Position = UDim2.fromOffset(5, y - 4)
		well.Size = UDim2.new(1, -10, 0, math.max(30, detailH - y - 8) + 8)
	end
	local headIcon = refs.DetailIcon.Size.X.Offset
	centreFx(
		refs.Detail,
		if refs.Short then UDim2.fromOffset(8 + headIcon / 2, 8 + headIcon / 2) else UDim2.new(0.5, 0, 0, 10 + headIcon / 2)
	)
	refs.DetailBody:SetAttribute("TextWidth", textW)
	placeBody(refs)
	fitReward(refs)
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

-- Fills the tabs, tiles, detail and footer from a data.Artifacts record
-- (`wallet`: the player's blaster level and shards for RESTORE; nil = none).
function CollectionView.fill(refs: Refs, artifacts: any, wallet: Wallet?)
	local purse: Wallet = wallet or { BlasterLevel = 1, Shards = 0 }
	local unique = ArtifactConfig.uniqueCount(artifacts)
	refs.Total.Text = `{unique} / {#ArtifactConfig.List} found`
	local totalBar = refs.Total.Parent
	if totalBar and totalBar:IsA("GuiObject") then
		Pop.setBar(totalBar, if #ArtifactConfig.List > 0 then unique / #ArtifactConfig.List else 0)
	end
	for _, collection in ArtifactConfig.Collections do
		local button = refs.Tabs[collection.Id]
		if button then
			local found, count = CollectionView.progress(artifacts, collection.Id)
			local complete = found >= count and count > 0
			local progress = button:FindFirstChild("Progress") :: Frame?
			if progress then
				Pop.setBar(
					progress,
					if count > 0 then found / count else 0,
					if complete then `{found} / {count} complete` else `{found} / {count} found`
				)
				local barFill = progress:FindFirstChild("Fill") :: Frame?
				if barFill then
					Pop.repaint(barFill, if complete then "Green" else "Yellow")
				end
			end
			local badge = button:FindFirstChild("New") :: GuiObject?
			if badge then
				badge.Visible = CollectionView.chapterNew(artifacts, collection.Id)
			end
			-- the picked collection bright with a gold edge, the others shaded
			local selected = collection.Id == refs.Collection
			local holder = button.Parent
			if holder and holder:IsA("GuiObject") then
				local shade = holder:FindFirstChild("Shade") :: Frame?
				if shade then
					shade.Visible = not selected
				end
				local border = holder:FindFirstChild("Border") :: UIStroke?
				if border then
					border.Color = if selected then CollectionView.SelectColor else PopTheme.Outline
					border.Thickness = if selected then 5 else PopTheme.Edge
				end
			end
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
			-- a found artifact's card in its rarity's paint, a missing one dark
			Pop.repaint(t.Button, if found then Pop.rarityPaint(art.Rarity) else CollectionView.HiddenPaint)
			setFx(t.Button, found)
			CollectionView.glyph(t.Icon, art.Id, not found)
			t.Name.Text = string.upper(if found then art.Name else CollectionView.MissingName)
			-- (a pixel letter is 1 em wide: the longest word fits the tile's width; a
			-- name too long for that takes the round font)
			local tileName = metrics(refs.Compact).TileName
			local floor = if refs.Compact then CollectionView.NameMinCompact else CollectionView.NameMin
			local base = math.floor((tileName + 4) * PopTheme.PixelScale + 0.5)
			t.Name.TextSize = CollectionView.fitSize(t.Name.Text, tileName, cellWidth - 10)
			tileWords(t.Name, base, tileName, cellWidth - 14, t.Name.Size.Y.Offset, floor, true)
			t.Name.TextColor3 = if found then PopTheme.Ink else CollectionView.SoftInk
			t.Chip.Text = string.upper(rarity.Name)
			-- (the chip: 16 narrower than the tile, 6 padding a side, 2 to spare)
			local chipH = t.Chip.Size.Y.Offset
			tileWords(t.Chip, math.floor(18 * PopTheme.PixelScale + 0.5), 16, cellWidth - 30, chipH, floor, false)
			t.Chip.BackgroundColor3 = if found then CollectionView.chipColor(art.Rarity) else PopTheme.Well
			t.Chip.TextColor3 = if found then PopTheme.Ink else CollectionView.SoftInk
			t.Count.Text = if count > 1 then `x{count}` else ""
			local selected = refs.Selected == art.Id
			local stroke = t.Button:FindFirstChild("Border") :: UIStroke?
			if stroke then
				stroke.Color = if selected then CollectionView.SelectColor else PopTheme.Outline
				stroke.Thickness = if selected then 6 else PopTheme.Edge
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
		Pop.repaint(refs.Detail, if found then Pop.rarityPaint(art.Rarity) else CollectionView.HiddenPaint, false)
		setFx(refs.Detail, found)
		CollectionView.glyph(refs.DetailIcon, art.Id, not found)
		refs.DetailName.Text = if found then art.Name else CollectionView.MissingName
		refs.DetailChip.Text = rarity.Name
		refs.DetailChip.BackgroundColor3 = if found then CollectionView.chipColor(art.Rarity) else PopTheme.Well
		refs.DetailCount.Text = if found then `Found: {count}` else "Not found yet"
		refs.DetailLore.Text = if found then art.Lore else CollectionView.NotFoundLore
		refs.DetailWhere.Text = CollectionView.whereText(art.Id)
		refs.DetailRestore.Text = CollectionView.restoreText(artifacts, art.Id, purse) or ""
		fitName(refs)
		placeBody(refs)
	end
	refs.Reward.Text = CollectionView.rewardText(refs.Collection)
	fitReward(refs)
	-- USE TITLE + SKIN once the collection is complete (IN USE when it shows)
	local complete = ArtifactConfig.isComplete(artifacts, refs.Collection)
	local useHolder = refs.Use.Parent
	if useHolder and useHolder:IsA("Frame") then
		useHolder.Visible = complete
	end
	local useText, useArg = CollectionView.useButton(artifacts, refs.Collection)
	refs.Use.Text = useText
	refs.Use:SetAttribute("Equip", if complete then useArg else nil)
	local inUse = complete and useArg == ""
	repaintButton(refs.Use, if inUse then "Green" else "Blue")
	-- RESTORE while exactly one is missing (greyed while it can't be paid / its mine is closed)
	local restoreText, restoreArg, restoreWhy = CollectionView.restoreButton(artifacts, refs.Collection, purse)
	local restoreHolder = refs.Restore.Parent
	if restoreHolder and restoreHolder:IsA("Frame") then
		restoreHolder.Visible = restoreText ~= nil and not complete
	end
	refs.Restore.Text = restoreText or ""
	refs.Restore:SetAttribute("Restore", restoreArg)
	refs.Restore:SetAttribute("Reason", restoreWhy)
	repaintButton(refs.Restore, if restoreArg then "Teal" else CollectionView.OffPaint)
	local text, enabled = CollectionView.chapterButton(artifacts, refs.Collection)
	refs.Chapter.Text = text
	refs.Chapter:SetAttribute("Enabled", enabled)
	repaintButton(refs.Chapter, if enabled then "Orange" else CollectionView.OffPaint)
end

---------------------------------------------------------------- the reveal card

function CollectionView.buildReveal(compact: boolean): RevealRefs
	local gui = UIKit.screen("TerraForgeArtifactReveal", 25)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true)
	gui.Enabled = false
	local width, height = if compact then 620 else 560, if compact then 520 else 470
	local card = UIKit.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Active = true,
		ZIndex = 1,
	}, gui)
	-- a bright card in the artifact's rarity colour (showReveal), the rays behind its icon
	paintFrame(card, "Yellow", UDim2.new(0.5, 0, 0, 122), 520, 220)
	local border = card:FindFirstChild("Border") :: UIStroke
	border.Thickness = 4
	local title = Pop.title(card, "ARTIFACT FOUND!", if compact then 40 else 38, "Gold", {
		Name = "Title",
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 7,
	})
	Pop.shadow(title)
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, card)
	UIKit.corner(icon, 16)
	UIKit.stroke(icon, 3, CollectionView.SelectColor)
	local body = if compact then 20 else 18
	local name = Pop.text(card, "", body + 8, {
		Name = "Name",
		Position = UDim2.fromOffset(16, 188),
		Size = UDim2.new(1, -32, 0, body + 12),
		ZIndex = 7,
	})
	local rarity = chip(card, "", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 222),
		Size = UDim2.fromOffset(120, 24),
		TextSize = 15,
		ZIndex = 7,
	})
	local progress = Pop.text(card, "", body, {
		Name = "Progress",
		Position = UDim2.fromOffset(16, 252),
		Size = UDim2.new(1, -32, 0, body + 6),
		TextColor3 = Color3.fromRGB(255, 248, 220),
		ZIndex = 7,
	})
	local lore = Pop.text(card, "", body - 1, {
		Name = "Lore",
		Position = UDim2.fromOffset(28, 282),
		Size = UDim2.new(1, -56, 0, (body - 1) * 2 + 8),
		TextWrapped = true,
		ZIndex = 7,
	})
	local extra = Pop.text(card, "", body, {
		Name = "Extra",
		Position = UDim2.fromOffset(20, 282 + (body - 1) * 2 + 10),
		Size = UDim2.new(1, -40, 0, body * 3 + 8),
		TextColor3 = PopTheme.Money,
		TextWrapped = true,
		ZIndex = 7,
	})
	local buttonH = if compact then 72 else 54
	local book = popButton(card, "OPEN BOOK", "Blue", {
		Name = "Book",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -14),
		Size = UDim2.fromOffset(200, buttonH),
		TextSize = 24,
	})
	local ok = popButton(card, "OK", "Green", {
		Name = "Ok",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -14),
		Size = UDim2.fromOffset(200, buttonH),
		TextSize = 26,
	})
	if compact then
		-- phones and TVs: the icon left, the texts beside it, low enough for a 320 pt phone
		card.Size = UDim2.fromOffset(900, 380)
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromOffset(28, 70)
		icon.Size = UDim2.fromOffset(170, 170)
		centreFx(card, UDim2.fromOffset(113, 155))
		local x = 224
		local left = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(x, 62)
		name.Size = UDim2.new(1, -x - 20, 0, body + 12)
		name.TextXAlignment = left
		rarity.AnchorPoint = Vector2.new(0, 0)
		rarity.Position = UDim2.fromOffset(x, 102)
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
		Chip = rarity,
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
	-- a new find counts even before the State push with it arrives
	local have, total = CollectionView.progress(artifacts, art.Collection, if found.New == true then id else nil)
	local progress = `{if collection then collection.Name else art.Collection}: {have} / {total}`
	local title = if found.New == true then "NEW ARTIFACT!" else "ARTIFACT FOUND!"
	local extra = ""
	if found.Completed == true then
		title = "COLLECTION COMPLETE!"
		local chapter = StoryConfig.ByCollection[art.Collection]
		extra = `Chapter {if chapter then chapter.Number else "?"} unlocked! ` .. CollectionView.rewardText(art.Collection)
		if found.Restored == true then
			extra = "Restored with crystal shards. " .. extra
		end
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
	syncShadow(refs.Title)
	Pop.repaint(refs.Card, Pop.rarityPaint(art.Rarity), false)
	CollectionView.glyph(refs.Icon, id, false)
	local stroke = refs.Icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.Color
	end
	refs.Name.Text = art.Name
	refs.Chip.Text = rarity.Name
	refs.Chip.BackgroundColor3 = CollectionView.chipColor(art.Rarity)
	refs.Progress.Text = progress
	refs.Lore.Text = art.Lore
	refs.Extra.Text = extra
	refs.Extra.TextColor3 = if found.Completed == true then Color3.fromRGB(255, 232, 110) else PopTheme.Money
	refs.Book.Text = if found.Completed == true then "READ CHAPTER" else "OPEN BOOK"
	refs.Gui.Enabled = true
end

---------------------------------------------------------------- the found banner and the copy toast

CollectionView.BannerTop = 100 -- design units: right under the coins panel (16..90), high above the thumbstick
CollectionView.BannerSize = { Normal = Vector2.new(480, 128), Compact = Vector2.new(500, 140) }
-- the height without the key row (touch, gamepad): no empty strip at the bottom
CollectionView.BannerShort = { Normal = 100, Compact = 102 }

-- The toast for a copy: "Golem Cog (copy) +1 Shard".
function CollectionView.copyText(found: { [string]: any }): string
	local art = ArtifactConfig.ById[tostring(found.Artifact)]
	local name = if art then art.Name else "Artifact"
	local shards = tonumber(found.Shards) or 0
	if shards <= 0 then
		return `{name} (copy)`
	end
	return `{name} (copy) +{shards} {if shards == 1 then "Shard" else "Shards"}`
end

-- The small NEW ARTIFACT! note (its own ScreenGui, hidden). Not modal: only
-- its BOOK button takes input (never a gamepad selection). The key row
-- (Keys) shows the book shortcut and how to close it: glyph images on a
-- gamepad, text on a keyboard, nothing on touch (the controller fills it).
function CollectionView.buildBanner(compact: boolean): BannerRefs
	local gui = UIKit.screen("TerraForgeArtifactBanner", 6)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true)
	gui.Enabled = false
	local size = if compact then CollectionView.BannerSize.Compact else CollectionView.BannerSize.Normal
	local card = UIKit.new("Frame", {
		Name = "Card",
		Position = UDim2.fromOffset(16, CollectionView.BannerTop),
		Size = UDim2.fromOffset(size.X, size.Y),
		Active = false,
		ZIndex = 1,
	}, gui)
	local iconSize = size.Y - 24
	-- a bright card in the find's rarity colour (showBanner), the rays behind its icon
	paintFrame(card, "Yellow", UDim2.fromOffset(12 + iconSize / 2, 12 + iconSize / 2), 220, 120)
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(iconSize, iconSize),
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, card)
	UIKit.corner(icon, 12)
	UIKit.stroke(icon, 3, CollectionView.SelectColor)
	local x = 12 + iconSize + 12
	local buttonW = if compact then 116 else 104
	local buttonH = if compact then 72 else 50
	local textW = size.X - x - buttonW - 24
	local title = Pop.text(card, "NEW ARTIFACT!", if compact then 24 else 22, {
		Name = "Title",
		Position = UDim2.fromOffset(x, 8),
		Size = UDim2.fromOffset(textW, 28),
		FontFace = PopTheme.Heavy,
		TextColor3 = Color3.fromRGB(255, 236, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local name = Pop.text(card, "", if compact then 21 else 19, {
		Name = "Name",
		Position = UDim2.fromOffset(x, 36),
		Size = UDim2.fromOffset(textW, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local rarity = chip(card, "", {
		Name = "Rarity",
		Position = UDim2.fromOffset(x, 68),
		Size = UDim2.fromOffset(96, 22),
		ZIndex = 7,
	})
	local progress = Pop.text(card, "", if compact then 17 else 16, {
		Name = "Progress",
		Position = UDim2.fromOffset(x + 104, 66),
		Size = UDim2.fromOffset(textW - 104, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 248, 220),
		ZIndex = 7,
	})
	local book = popButton(card, "BOOK", "Blue", {
		Name = "Book",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 16),
		Size = UDim2.fromOffset(buttonW, buttonH),
		TextSize = if compact then 26 else 22,
		Selectable = false,
	})
	-- the key row under the texts
	local keys = UIKit.new("Frame", {
		Name = "Keys",
		Position = UDim2.fromOffset(x, size.Y - 32),
		Size = UDim2.fromOffset(size.X - x - 12, 26),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, card)
	UIKit.list(keys, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local function glyph(order: number, keyName: string): ImageLabel
		return UIKit.new("ImageLabel", {
			Name = keyName,
			LayoutOrder = order,
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 7,
		}, keys)
	end
	local function keyText(order: number, keyName: string): TextLabel
		return Pop.text(keys, "", if compact then 16 else 15, {
			Name = keyName,
			LayoutOrder = order,
			Size = UDim2.fromOffset(150, 24),
			AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 248, 220),
			ZIndex = 7,
		})
	end
	local bookGlyph = glyph(1, "BookGlyph")
	local bookKey = keyText(2, "BookKey")
	local closeGlyph = glyph(3, "CloseGlyph")
	local closeKey = keyText(4, "CloseKey")
	return {
		Gui = gui,
		Card = card,
		Icon = icon,
		Title = title,
		Name = name,
		Chip = rarity,
		Progress = progress,
		Book = book,
		Keys = keys,
		BookGlyph = bookGlyph,
		BookKey = bookKey,
		CloseGlyph = closeGlyph,
		CloseKey = closeKey,
		Compact = compact,
	}
end

-- The banner's height and inside for a key row or none: the icon fills the
-- height left, the texts start right of it.
local function layoutBanner(refs: BannerRefs, withKeys: boolean)
	local size = if refs.Compact then CollectionView.BannerSize.Compact else CollectionView.BannerSize.Normal
	local height = if withKeys
		then size.Y
		else (if refs.Compact then CollectionView.BannerShort.Compact else CollectionView.BannerShort.Normal)
	refs.Card.Size = UDim2.fromOffset(size.X, height)
	local iconSize = height - 24
	refs.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
	centreFx(refs.Card, UDim2.fromOffset(12 + iconSize / 2, 12 + iconSize / 2))
	local x = 12 + iconSize + 12
	local bookHolder = refs.Book.Parent
	local buttonW = if bookHolder and bookHolder:IsA("Frame") then bookHolder.Size.X.Offset else 104
	local textW = size.X - x - buttonW - 24
	refs.Title.Position = UDim2.fromOffset(x, 8)
	refs.Title.Size = UDim2.fromOffset(textW, 28)
	refs.Name.Position = UDim2.fromOffset(x, 36)
	refs.Name.Size = UDim2.fromOffset(textW, 28)
	refs.Chip.Position = UDim2.fromOffset(x, 68)
	refs.Progress.Position = UDim2.fromOffset(x + 104, 66)
	refs.Progress.Size = UDim2.fromOffset(textW - 104, 26)
	refs.Keys.Position = UDim2.fromOffset(x, size.Y - 32)
	refs.Keys.Size = UDim2.fromOffset(size.X - x - 12, 26)
end

-- The key row: `bookImage` / `closeImage` are glyph images (a gamepad), else
-- `bookText` / `closeText` alone (a keyboard); all empty hides it (touch and
-- gamepads today) and the banner gets shorter (BannerShort).
function CollectionView.setBannerKeys(refs: BannerRefs, bookImage: string, bookText: string, closeImage: string, closeText: string)
	local m = if refs.Compact then 16 else 15
	refs.BookGlyph.Image = bookImage
	refs.BookGlyph.Visible = bookImage ~= ""
	refs.CloseGlyph.Image = closeImage
	refs.CloseGlyph.Visible = closeImage ~= ""
	refs.BookKey.Text = bookText
	refs.CloseKey.Text = closeText
	refs.BookKey.Size = UDim2.fromOffset(math.ceil(#bookText * m * 0.56) + 6, 24)
	refs.CloseKey.Size = UDim2.fromOffset(math.ceil(#closeText * m * 0.56) + 6, 24)
	refs.BookKey.Visible = bookText ~= ""
	refs.CloseKey.Visible = closeText ~= ""
	local withKeys = bookText ~= "" or closeText ~= "" or bookImage ~= "" or closeImage ~= ""
	refs.Keys.Visible = withKeys
	layoutBanner(refs, withKeys)
end

-- Fills the note for a new find (ArtifactFound payload) and shows it.
function CollectionView.showBanner(refs: BannerRefs, found: { [string]: any }, artifacts: any)
	local id = tostring(found.Artifact)
	local art = ArtifactConfig.ById[id]
	if not art then
		return
	end
	local rarity = Rarity.get(art.Rarity)
	Pop.repaint(refs.Card, Pop.rarityPaint(art.Rarity), false)
	CollectionView.glyph(refs.Icon, id, false)
	local stroke = refs.Icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.Color
	end
	refs.Name.Text = art.Name
	local nameWidth = refs.Name.Size.X.Offset
	refs.Name.TextSize = CollectionView.fitBox(art.Name, if refs.Compact then 21 else 19, 14, nameWidth, 30)
	refs.Chip.Text = rarity.Name
	refs.Chip.BackgroundColor3 = CollectionView.chipColor(art.Rarity)
	-- the find counts even before the State push with it arrives
	local have, total = CollectionView.progress(artifacts, art.Collection, id)
	refs.Progress.Text = `{have} / {total} found`
	refs.Gui.Enabled = true
end

---------------------------------------------------------------- the HUD menu button

-- The BOOK button for the HUD's right-side menu (HudController.refs().Menu),
-- under BUILD and the elevator (only in a game without the side menu,
-- ArtifactController): a NEW badge while a chapter waits unread.
function CollectionView.menuButton(menu: Instance): MenuRefs
	local button = UIKit.button(menu, "", Color3.fromRGB(150, 96, 200), Color3.fromRGB(92, 56, 130), {
		Name = "Book",
		LayoutOrder = 30,
		Size = UDim2.fromOffset(84, 64),
	})
	UIKit.label(button, "", 26, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = false,
	})
	UIKit.label(button, "BOOK", 18, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -6, 0, 22),
		TextWrapped = false,
	})
	local badge = UIKit.chip(button, "NEW", Theme.Bad, {
		Name = "New",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -10),
		Size = UDim2.fromOffset(46, 20),
		Visible = false,
		ZIndex = 4,
	})
	badge.TextSize = 13
	return { Button = button, New = badge }
end

-- Does any completed collection's chapter wait unread (the menu's NEW badge)?
function CollectionView.anyChapterNew(artifacts: any): boolean
	return CollectionView.unreadChapters(artifacts) > 0
end

-- How many completed collections' chapters wait unread (the book's badge).
function CollectionView.unreadChapters(artifacts: any): number
	local count = 0
	for _, collection in ArtifactConfig.Collections do
		if CollectionView.chapterNew(artifacts, collection.Id) then
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------- the title over a player

CollectionView.TitleHeight = 3.3 -- studs above the head's centre (over the name)
CollectionView.TitleDistance = 70 -- studs: farther players show no title

-- The BillboardGui with a collection title (the controller sets its Adornee).
function CollectionView.titleBoard(text: string): BillboardGui
	local board = Instance.new("BillboardGui")
	board.Name = "TerraForgeTitle"
	board.Size = UDim2.fromOffset(260, 30)
	board.StudsOffset = Vector3.new(0, CollectionView.TitleHeight, 0)
	board.MaxDistance = CollectionView.TitleDistance
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.ResetOnSpawn = false
	UIKit.label(board, "★ " .. text .. " ★", 20, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
		TextWrapped = false,
	})
	return board
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- The book, the found card and the banner wear the Pop look (attribute
-- PopSkin: never the LightSkin recolouring). While the light UI is on the
-- book also hides Roblox's touch controls while it is open.
local popBuild = CollectionView.build
CollectionView.build = function(compact: boolean): Refs
	local refs = popBuild(compact)
	if UIConfig.lightUI() then
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return CollectionView
