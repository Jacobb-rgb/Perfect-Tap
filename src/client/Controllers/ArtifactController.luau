--[[
	ArtifactController: artifacts of Kaldrum on this screen (step 7).

	- ArtifactFound (only to the finder): the server has already put the find
	  into the collection (ArtifactService). The moment: the relic
	  (ArtifactBuilder, built locally) pops out of the broken rock with a
	  sparkle, turns in the air and flies to the player, then:
	    a copy        a toast only: "Golem Cog (copy) +1 Shard"
	    a new one     the small NEW ARTIFACT! banner at the left under the
	                  coins (CollectionView.buildBanner): not modal, no
	                  gamepad selection, the thumbstick and jump areas stay
	                  free; it goes away by itself after BannerSeconds, or
	                  sooner with Backspace (a keyboard; only while no panel,
	                  minigame or prompt wants that key: below the panels'
	                  close priority), or opens the book (its BOOK button,
	                  J). A gamepad's B is never taken (panels and the B
	                  prompts keep it). A newer find replaces it.
	    a completed   the big COLLECTION COMPLETE card (modal: OK, READ
	      collection  CHAPTER; B / Backspace close it; a gamepad starts on
	                  OK); it never closes by itself. Several wait their turn.
	- The collection book (CollectionView) opens on OpenUI "Artifacts" (the
	  "Collection Book" prompts at the FOSSIL DIG and the base museum), the
	  side menu's ARTIFACTS button (SideMenuController.press calls
	  ArtifactController.open / toggle / close; onUnseenChanged feeds its
	  badge), J on a keyboard, the banner and the card. One book button
	  only: the HUD's own BOOK button (right-side menu, NEW while a chapter
	  waits unread) is added only in a game without the side menu. No
	  gamepad shortcut of its own (the D-pad belongs to the side menu,
	  boosts, build mode and the teleport bar). Tabs: click / tap, or LB / RB;
	  tiles show an artifact's detail; USE TITLE + SKIN sends ArtifactAction
	  "Equip" (IN USE takes it off again); RESTORE: N SHARDS (a collection
	  with exactly one artifact missing) asks for a second press within
	  RESTORE_CONFIRM seconds, then sends ArtifactAction "Restore" (the
	  COLLECTION COMPLETE card follows; a greyed one says why in a toast);
	  READ CHAPTER and JOURNAL (the header, left of the X) open the journal.
	- The journal (StoryView) opens on OpenUI "Story" (the "Read Journal"
	  prompts at the Guild board and the FOSSIL DIG's story screen) and from
	  the book. Pages: PREV / NEXT, LB / RB or the arrow keys. Opening a
	  completed chapter that is still unread sends ArtifactAction
	  "ReadChapter" (its NEW badge goes away with the next State).
	- Titles: every player's "Title" attribute (ArtifactService) shows over
	  their head (CollectionView.titleBoard, a BillboardGui in this
	  PlayerGui adorned to their Head, up to TitleDistance studs).
	- Every screen closes with its X, B (gamepad), Backspace, respawning or
	  another big panel opening (OtherPanels, plus the side menu's
	  MenuPanels.Names when that module is in the game); gamepads get a
	  selected button on open. Nothing opens over the cleaning minigame or
	  build mode.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local Rarity = require(Shared.Config.Rarity)
local ArtifactBuilder = require(Shared.Builders.ArtifactBuilder)
local Net = require(Shared.Net)
local CollectionView = require(script.Parent.Parent.UI.CollectionView)
local StoryView = require(script.Parent.Parent.UI.StoryView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local CleaningController = require(script.Parent.CleaningController)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local ArtifactController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }
type Screen = "Book" | "Story"

local CLOSE_ACTION = "TerraForgeArtifactsClose"
local PAGE_ACTION = "TerraForgeArtifactsPage"
local REVEAL_ACTION = "TerraForgeArtifactReveal"
local BANNER_ACTION = "TerraForgeArtifactBanner"
local BOOK_ACTION = "TerraForgeBook"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
-- below every panel's close binding (High + 10): an open panel keeps its Backspace
local BANNER_PRIORITY = Enum.ContextActionPriority.High.Value + 2
local REVEAL_PRIORITY = Enum.ContextActionPriority.High.Value + 15
local TITLE_ATTRIBUTE = "Title" -- ArtifactService.TitleAttribute
local EQUIP_COOLDOWN = 0.5
local RESTORE_CONFIRM = 4 -- seconds the RESTORE button waits for its second press

-- Every big panel of the game so far (missing ones are skipped); the side
-- menu's MenuPanels.Names are added when that module is in the game.
ArtifactController.OtherPanels = {
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"TechShopController",
	"GearShopController",
	"GearController",
	"EnchantController",
	"BoostController",
	"CapsuleController",
	"GolemController",
	"WheelController",
	"CodexController",
	"SettingsController",
	"LeaderboardController",
	"StoreController",
}

ArtifactController.BannerSeconds = 6 -- the NEW ARTIFACT! banner goes away by itself
ArtifactController.PopRange = 140 -- studs: farther finds skip the relic flight
ArtifactController.PopSeconds = 1.8
ArtifactController.BookKey = Enum.KeyCode.J -- the book shortcut on a keyboard (no gamepad shortcut)
ArtifactController.SideMenu = "SideMenuController" -- with it in the game, the HUD gets no BOOK button

local player = Players.LocalPlayer
local book: CollectionView.Refs? = nil
local journal: StoryView.Refs? = nil
local reveal: CollectionView.RevealRefs? = nil
local screen: Screen? = nil
local openedAt = 0
local others: { Panel }? = nil
local queue: { { [string]: any } } = {}
local showing: { [string]: any }? = nil
local banner: CollectionView.BannerRefs? = nil
local bannerFound: { [string]: any }? = nil -- the find the banner shows
local bannerToken = 0
local menu: CollectionView.MenuRefs? = nil
local titles: { [Player]: BillboardGui } = {}
local lastEquip = -math.huge
local restoreArmed: { Artifact: string, Until: number }? = nil -- the first RESTORE press
local unseenCallbacks: { (count: number) -> () } = {}
local unseenShown = -1
local shownPrompts: { [ProximityPrompt]: boolean } = {}

function ArtifactController.isOpen(): boolean
	return screen ~= nil
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function compactNow(): boolean
	return isTouch() or GuiService:IsTenFootInterface() or HudController.uiScale() <= 0.75
end

local function artifacts(): any
	local state = StateController.get()
	return if state then state.Artifacts else nil
end

local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

-- The names of every other big panel: OtherPanels plus the side menu's list.
function ArtifactController.panelNames(): { string }
	local names = table.clone(ArtifactController.OtherPanels)
	local util = script.Parent.Parent:FindFirstChild("Util")
	local menuPanels = util and util:FindFirstChild("MenuPanels")
	if menuPanels and menuPanels:IsA("ModuleScript") then
		local ok, module = pcall(require, menuPanels :: any)
		local listed = if ok and type(module) == "table" then (module :: any).Names else nil
		if type(listed) == "table" then
			for _, name in listed do
				if type(name) == "string" and not table.find(names, name) then
					table.insert(names, name)
				end
			end
		end
	end
	return names
end

local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in ArtifactController.panelNames() do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" then
				local c = controller :: any
				if c ~= ArtifactController and type(c.isOpen) == "function" and type(c.close) == "function" then
					table.insert(list, c :: Panel)
				end
			end
		end
	end
	others = list
	return list
end

local function viewport(): (number, number)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return size.X / scale, (size.Y - inset.Y) / scale
end

local function popIn(frame: GuiObject)
	local scale = frame:FindFirstChild("OpenPop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = frame
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- the book

local openStory: (key: string?) -> ()

local shownRecord: any = nil -- the data.Artifacts table the open screen shows
local shownWallet = "" -- the blaster level and shards the open book shows

-- The player's blaster level and shards (RESTORE) from the latest State.
local function wallet(): CollectionView.Wallet
	local state = StateController.get()
	local level = if state then tonumber(state.BlasterLevel) else nil
	local shards = if state then tonumber(state.Shards) else nil
	return {
		BlasterLevel = if level and level == level then level else 1,
		Shards = if shards and shards == shards then shards else 0,
	}
end

local function walletKey(w: CollectionView.Wallet): string
	return `{w.BlasterLevel}/{w.Shards}`
end

local function refreshBook()
	local view = book
	if view and screen == "Book" then
		shownRecord = artifacts()
		local w = wallet()
		shownWallet = walletKey(w)
		CollectionView.fill(view, shownRecord, w)
		-- a RESTORE waiting for its second press keeps asking for it
		local armed = restoreArmed
		if armed and os.clock() < armed.Until and view.Restore:GetAttribute("Restore") == armed.Artifact then
			view.Restore.Text = if usingGamepad() or isTouch() then "PRESS AGAIN TO PAY" else "CLICK AGAIN TO PAY"
		end
	end
end

-- RESTORE: the first press arms it (the button asks for a second press),
-- the second within RESTORE_CONFIRM seconds sends ArtifactAction "Restore".
local function pressRestore(view: CollectionView.Refs)
	local id = view.Restore:GetAttribute("Restore")
	if type(id) ~= "string" then
		local why = view.Restore:GetAttribute("Reason")
		local text = if type(why) == "string" then ArtifactConfig.Reasons[why] else nil
		HudController.toast(text or "You can't restore it yet", "Deny")
		return
	end
	local armed = restoreArmed
	if armed and armed.Artifact == id and os.clock() < armed.Until then
		restoreArmed = nil
		Net.send("ArtifactAction", "Restore", { Artifact = id })
		view.Restore.Text = "RESTORING..."
		Sfx.play("UIClick")
		return
	end
	restoreArmed = { Artifact = id, Until = os.clock() + RESTORE_CONFIRM }
	view.Restore.Text = if usingGamepad() or isTouch() then "PRESS AGAIN TO PAY" else "CLICK AGAIN TO PAY"
	Sfx.play("UIClick")
	task.delay(RESTORE_CONFIRM, function()
		local still = restoreArmed
		if still and still.Artifact == id and os.clock() >= still.Until then
			restoreArmed = nil
			refreshBook()
		end
	end)
end

local function selectTab(collectionId: string)
	local view = book
	if not view or not ArtifactConfig.CollectionById[collectionId] then
		return
	end
	view.Collection = collectionId
	view.Selected = nil
	refreshBook()
end

local function ensureBook(): CollectionView.Refs
	local existing = book
	if existing and existing.Compact == compactNow() then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
	end
	local view = CollectionView.build(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		ArtifactController.close()
		Sfx.play("UIClick")
	end)
	for id, button in view.Tabs do
		button.Activated:Connect(function()
			selectTab(id)
			Sfx.play("UIClick")
		end)
	end
	for _, t in view.Tiles do
		t.Button.Activated:Connect(function()
			if t.Id ~= "" then
				view.Selected = t.Id
				refreshBook()
				Sfx.play("UIClick")
			end
		end)
	end
	view.Chapter.Activated:Connect(function()
		if view.Chapter:GetAttribute("Enabled") == true then
			Sfx.play("UIClick")
			openStory(view.Collection)
		else
			Sfx.play("UIDeny")
		end
	end)
	view.Journal.Activated:Connect(function()
		Sfx.play("UIClick")
		openStory(nil)
	end)
	view.Restore.Activated:Connect(function()
		pressRestore(view)
	end)
	view.Use.Activated:Connect(function()
		local arg = view.Use:GetAttribute("Equip")
		if type(arg) ~= "string" or os.clock() - lastEquip < EQUIP_COOLDOWN then
			Sfx.play("UIDeny")
			return
		end
		lastEquip = os.clock()
		Net.send("ArtifactAction", "Equip", { Collection = arg })
		Sfx.play("UIClick")
	end)
	book = view
	return view
end

---------------------------------------------------------------- the journal

local showEntry: (view: StoryView.Refs, key: string, page: number) -> ()

-- The chapter list (rebuilt on every refresh) with its buttons wired.
local function listEntries(view: StoryView.Refs, entries: { StoryView.Entry })
	local selected = GuiService.SelectedObject
	local hadSelection = selected ~= nil and selected:IsDescendantOf(view.List)
	StoryView.setEntries(view, entries, function(key: string)
		Sfx.play("UIClick")
		showEntry(view, key, 1)
	end)
	-- a gamepad's selection was on a rebuilt button: keep it on the current chapter
	if hadSelection then
		GuiService.SelectedObject = view.Buttons[view.Key]
	end
end

showEntry = function(view: StoryView.Refs, key: string, page: number)
	shownRecord = artifacts()
	local entries = StoryView.entries(shownRecord)
	local entry = StoryView.entry(entries, key) or entries[1]
	view.Key = entry.Key
	listEntries(view, entries)
	StoryView.showPage(view, entry, page)
	-- reading a completed chapter for the first time
	if entry.New and entry.Key ~= StoryView.PrologueKey then
		Net.send("ArtifactAction", "ReadChapter", { Collection = entry.Key })
	end
end

local function turnPage(delta: number)
	local view = journal
	if not view or screen ~= "Story" then
		return
	end
	local entry = StoryView.entry(StoryView.entries(artifacts()), view.Key)
	if not entry or not entry.Unlocked then
		return
	end
	local target = math.clamp(view.PageIndex + delta, 1, #entry.Pages)
	if target ~= view.PageIndex then
		StoryView.showPage(view, entry, target)
		Sfx.play("UIClick")
	end
end

local function ensureJournal(): StoryView.Refs
	local existing = journal
	if existing and existing.Compact == compactNow() then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
	end
	local view = StoryView.build(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		ArtifactController.close()
		Sfx.play("UIClick")
	end)
	view.Prev.Activated:Connect(function()
		turnPage(-1)
	end)
	view.Next.Activated:Connect(function()
		turnPage(1)
	end)
	journal = view
	return view
end

---------------------------------------------------------------- open / close

local function hint(text: string)
	local view = if screen == "Book" then book elseif screen == "Story" then journal else nil
	if view then
		view.Hint.Text = text
	end
end

local function updateHint()
	if usingGamepad() then
		local lb, rb, b = padName(Enum.KeyCode.ButtonL1), padName(Enum.KeyCode.ButtonR1), padName(Enum.KeyCode.ButtonB)
		hint(if screen == "Book" then `{lb} / {rb}: collection  ·  {b}: close` else `{lb} / {rb}: page  ·  {b}: close`)
	elseif isTouch() then
		hint(if screen == "Book" then "Tap a collection, then an artifact" else "Tap a chapter, then NEXT")
	else
		hint(
			if screen == "Book"
				then "Click a collection, then an artifact  ·  Backspace: close"
				else "Arrow keys: page  ·  Backspace: close"
		)
	end
end

function ArtifactController.close()
	if not screen then
		return
	end
	screen = nil
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(PAGE_ACTION)
	local guis: { ScreenGui } = {}
	local b, j = book, journal
	if b then
		table.insert(guis, b.Gui)
	end
	if j then
		table.insert(guis, j.Gui)
	end
	for _, gui in guis do
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		gui.Enabled = false
	end
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not screen then
		return Enum.ContextActionResult.Pass
	end
	ArtifactController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function onPage(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not screen then
		return Enum.ContextActionResult.Pass
	end
	local back = input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.Left
	if screen == "Story" then
		turnPage(if back then -1 else 1)
	elseif screen == "Book" and (input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1) then
		local view = book
		if view then
			local ids = {}
			for _, collection in ArtifactConfig.Collections do
				table.insert(ids, collection.Id)
			end
			local index = table.find(ids, view.Collection) or 1
			selectTab(ids[(index - 1 + (if back then -1 else 1)) % #ids + 1])
			Sfx.play("UIClick")
		end
	else
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

-- Opens one of the two screens (closing other panels); false when it can't.
local function begin(kind: Screen): boolean
	local owner = PlayerControls.owner()
	if owner ~= nil or CleaningController.isActive() then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return false
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	ArtifactController.close()
	screen = kind
	openedAt = os.clock()
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(
		PAGE_ACTION,
		onPage,
		false,
		CLOSE_PRIORITY,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right
	)
	return true
end

function ArtifactController.openBook(collectionId: string?, selectedId: string?)
	if not begin("Book") then
		return
	end
	local view = ensureBook()
	if collectionId and ArtifactConfig.CollectionById[collectionId] then
		view.Collection = collectionId
		view.Selected = selectedId
	end
	local w, h = viewport()
	CollectionView.layout(view, w, h)
	refreshBook()
	view.Gui.Enabled = true
	updateHint()
	popIn(view.Panel)
	Sfx.play("UIClick")
	if usingGamepad() then
		GuiService.SelectedObject = view.Tiles[1].Button
	end
end

openStory = function(key: string?)
	if not begin("Story") then
		return
	end
	local view = ensureJournal()
	local w, h = viewport()
	StoryView.layout(view, w, h)
	-- default: the newest unread chapter, else the last one read, else the Prologue
	local target = key
	if not target then
		target = StoryView.PrologueKey
		for _, entry in StoryView.entries(artifacts()) do
			if entry.New then
				target = entry.Key
				break
			end
		end
	end
	showEntry(view, target :: string, 1)
	view.Gui.Enabled = true
	updateHint()
	popIn(view.Panel)
	Sfx.play("UIClick")
	if usingGamepad() then
		local nextHolder = view.Next.Parent
		GuiService.SelectedObject = if nextHolder and nextHolder:IsA("Frame") and nextHolder.Visible then view.Next else view.Close
	end
end

function ArtifactController.openStory(key: string?)
	openStory(key)
end

---------------------------------------------------------------- the found moment

local showNext: () -> ()

-- The COLLECTION COMPLETE card.
local function hideReveal()
	local card = reveal
	showing = nil
	ContextActionService:UnbindAction(REVEAL_ACTION)
	if card then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(card.Gui) then
			GuiService.SelectedObject = nil
		end
		card.Gui.Enabled = false
	end
	task.defer(showNext)
end

local function onRevealClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not showing then
		return Enum.ContextActionResult.Pass
	end
	hideReveal()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureReveal(): CollectionView.RevealRefs
	local existing = reveal
	if existing and existing.Compact == compactNow() then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
	end
	local card = CollectionView.buildReveal(compactNow())
	card.Gui.Parent = player:WaitForChild("PlayerGui")
	card.Ok.Activated:Connect(function()
		hideReveal()
		Sfx.play("UIClick")
	end)
	card.Book.Activated:Connect(function()
		local found = showing
		hideReveal()
		local art = if found then ArtifactConfig.ById[tostring(found.Artifact)] else nil
		if found and found.Completed == true and art then
			openStory(art.Collection)
		else
			ArtifactController.openBook(if art then art.Collection else nil, if art then art.Id else nil)
		end
	end)
	reveal = card
	return card
end

-- The relic pops out of the rock, turns, and flies to the player (local only).
local function popOut(found: { [string]: any }): number
	local position = found.Position
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if typeof(position) ~= "Vector3" or not root or ((position :: Vector3) - root.Position).Magnitude > ArtifactController.PopRange then
		return 0
	end
	local from = position :: Vector3
	local id = tostring(found.Artifact)
	local art = ArtifactConfig.ById[id]
	local model = ArtifactBuilder.build(id, CFrame.new(from), 1.4)
	if not art or not model then
		return 0
	end
	model.Parent = Workspace
	local glow = art.Glow or art.Primary
	Vfx.burst("Glint", from + Vector3.new(0, 1.5, 0), 30, glow)
	Vfx.burst("Sparks", from + Vector3.new(0, 1, 0), 16, glow)
	Sfx.play("Discovery", from)
	local started = os.clock()
	local total = ArtifactController.PopSeconds
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / total
		local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if t >= 1 or not model.Parent then
			connection:Disconnect()
			model:Destroy()
			return
		end
		local spin = CFrame.Angles(0, t * 9, 0)
		local cf: CFrame
		if t < 0.35 then
			-- up out of the rock
			local k = 1 - (1 - t / 0.35) ^ 3
			cf = CFrame.new(from + Vector3.new(0, 4.5 * k, 0)) * spin
		elseif t < 0.65 or not body then
			-- hovering, bobbing
			cf = CFrame.new(from + Vector3.new(0, 4.5 + math.sin((t - 0.35) * 20) * 0.25, 0)) * spin
		else
			-- to the player, shrinking
			local k = (t - 0.65) / 0.35
			local target = (body :: BasePart).Position + Vector3.new(0, 1.5, 0)
			local p = (from + Vector3.new(0, 4.5, 0)):Lerp(target, k * k)
			cf = CFrame.new(p) * spin
			local scale = math.max(0.05, 1 - k)
			model:ScaleTo(scale)
		end
		model:PivotTo(cf)
	end)
	return total
end

showNext = function()
	if showing or #queue == 0 then
		return
	end
	local found = table.remove(queue, 1) :: { [string]: any }
	local card = ensureReveal()
	showing = found
	CollectionView.showReveal(card, found, artifacts())
	local w, h = viewport()
	local fit = CollectionView.fitReveal(card, w, h)
	local scale = card.Card:FindFirstChild("Fit") :: UIScale?
	if scale then
		scale.Scale = fit * 0.85
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	end
	Sfx.play("Reveal")
	ContextActionService:BindActionAtPriority(
		REVEAL_ACTION,
		onRevealClose,
		false,
		REVEAL_PRIORITY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace
	)
	-- a completed collection is rare and worth the stop: a gamepad starts on OK
	if usingGamepad() then
		GuiService.SelectedObject = card.Ok
	end
end

-- The NEW ARTIFACT! banner (not modal).
local function hideBanner()
	bannerToken += 1
	bannerFound = nil
	ContextActionService:UnbindAction(BANNER_ACTION)
	local view = banner
	if view then
		view.Gui.Enabled = false
	end
end

-- The key row: a keyboard's J / Backspace only (a gamepad and touch have
-- no keys for the banner: it goes by itself, its BOOK button is a tap; the
-- banner is then shorter, CollectionView.setBannerKeys).
local function bannerKeys(view: CollectionView.BannerRefs)
	if usingGamepad() or isTouch() then
		CollectionView.setBannerKeys(view, "", "", "", "")
	else
		local key = UserInputService:GetStringForKeyCode(ArtifactController.BookKey)
		CollectionView.setBannerKeys(view, "", `{if key ~= "" then key else "J"}: book`, "", "Backspace: close")
	end
end

local function ensureBanner(): CollectionView.BannerRefs
	local existing = banner
	if existing and existing.Compact == compactNow() then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
	end
	local view = CollectionView.buildBanner(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Book.Activated:Connect(function()
		local found = bannerFound
		hideBanner()
		local art = if found then ArtifactConfig.ById[tostring(found.Artifact)] else nil
		ArtifactController.openBook(if art then art.Collection else nil, if art then art.Id else nil)
	end)
	banner = view
	return view
end

-- Does anything else want a key right now (a panel, the minigame, build
-- mode, a menu with the selection, a prompt bound to that key)?
local function keyWanted(key: Enum.KeyCode): boolean
	if screen ~= nil or showing ~= nil or PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return true
	end
	if GuiService.SelectedObject ~= nil then
		return true
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			return true
		end
	end
	for prompt in shownPrompts do
		if prompt.Parent and (prompt.KeyboardKeyCode == key or prompt.GamepadKeyCode == key) then
			return true
		end
	end
	return false
end

local function onBannerClose(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not bannerFound or keyWanted(input.KeyCode) then
		return Enum.ContextActionResult.Pass
	end
	hideBanner()
	return Enum.ContextActionResult.Sink
end

local function showBanner(found: { [string]: any })
	local view = ensureBanner()
	bannerToken += 1
	local token = bannerToken
	bannerFound = found
	-- the key row first: it sets the banner's height and the name's width
	bannerKeys(view)
	CollectionView.showBanner(view, found, artifacts())
	-- slides in from the left edge
	local card = view.Card
	card.Position = UDim2.fromOffset(-card.Size.X.Offset - 20, CollectionView.BannerTop)
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(16, CollectionView.BannerTop),
	}):Play()
	Sfx.play("Reveal")
	ContextActionService:BindActionAtPriority(BANNER_ACTION, onBannerClose, false, BANNER_PRIORITY, Enum.KeyCode.Backspace)
	task.delay(ArtifactController.BannerSeconds, function()
		if bannerToken == token then
			hideBanner()
		end
	end)
end

local function onFound(payload: any)
	if type(payload) ~= "table" or type(payload.Artifact) ~= "string" or not ArtifactConfig.ById[payload.Artifact] then
		return
	end
	local delay = popOut(payload)
	task.delay(delay, function()
		if payload.Completed == true then
			-- the big card (modal), after any card already showing
			hideBanner()
			table.insert(queue, payload)
			showNext()
		elseif payload.New == true then
			showBanner(payload)
		else
			-- a copy: a toast only, mining goes on
			local art = ArtifactConfig.ById[payload.Artifact]
			HudController.toast(CollectionView.copyText(payload), "Info", Rarity.get(art.Rarity).Color)
		end
	end)
end

---------------------------------------------------------------- the book shortcut and the HUD button

local function toggleBook()
	if screen == "Book" then
		ArtifactController.close()
		Sfx.play("UIClick")
		return
	end
	local found = bannerFound
	hideBanner()
	local art = if found then ArtifactConfig.ById[tostring(found.Artifact)] else nil
	ArtifactController.openBook(if art then art.Collection else nil, if art then art.Id else nil)
end

-- The side menu's ARTIFACTS button (SideMenuController.press: open /
-- toggle / close through MenuPanels) and anything else that opens the book
-- (on the banner's new find, when one shows).
function ArtifactController.open()
	if screen ~= "Book" then
		toggleBook()
	end
end

function ArtifactController.toggle()
	toggleBook()
end

-- J: the book (not while a minigame or build mode holds the controls or a
-- big card shows). Keyboard only.
local function onBookKey(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or showing then
		return Enum.ContextActionResult.Pass
	end
	if PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return Enum.ContextActionResult.Pass
	end
	toggleBook()
	return Enum.ContextActionResult.Sink
end

--[[
	Listeners for the book's badge (the side menu's ARTIFACTS button, like
	CodexController.onUnseenChanged): called with how many completed
	chapters wait unread, now and whenever that changes.
]]
function ArtifactController.onUnseenChanged(callback: (count: number) -> ())
	table.insert(unseenCallbacks, callback)
	task.spawn(callback, CollectionView.unreadChapters(artifacts()))
end

local function updateMenu()
	local unread = CollectionView.unreadChapters(artifacts())
	if unread ~= unseenShown then
		unseenShown = unread
		for _, callback in unseenCallbacks do
			task.spawn(callback, unread)
		end
	end
	local m = menu
	if m then
		m.New.Visible = unread > 0
	end
end

---------------------------------------------------------------- titles over players

local function refreshTitle(other: Player)
	local text = other:GetAttribute(TITLE_ATTRIBUTE)
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	local board = titles[other]
	if type(text) ~= "string" or text == "" or not head or not head:IsA("BasePart") then
		if board then
			board:Destroy()
			titles[other] = nil
		end
		return
	end
	if not board then
		local made = CollectionView.titleBoard(text)
		made.Parent = player:FindFirstChildOfClass("PlayerGui")
		titles[other] = made
		board = made
	end
	local shown = board :: BillboardGui
	local label = shown:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = "★ " .. text .. " ★"
	end
	shown.Adornee = head
end

local function watchTitle(other: Player)
	other:GetAttributeChangedSignal(TITLE_ATTRIBUTE):Connect(function()
		refreshTitle(other)
	end)
	local function onCharacter(character: Model)
		-- streaming may bring the head back as a new part
		character.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Head" then
				refreshTitle(other)
			end
		end)
		refreshTitle(other)
	end
	other.CharacterAdded:Connect(onCharacter)
	if other.Character then
		onCharacter(other.Character)
	end
end

---------------------------------------------------------------- lifecycle

function ArtifactController.init()
	Net.listen("OpenUI", function(kind)
		if kind == "Artifacts" then
			ArtifactController.openBook(nil)
		elseif kind == "Story" then
			openStory(nil)
		end
	end)
	Net.listen("ArtifactFound", onFound)
	Net.listen("ActionResult", function(payload: any)
		if type(payload) ~= "table" or payload.Action ~= "Artifact" or payload.Ok == true then
			return
		end
		local reason = if type(payload.Reason) == "string" then ArtifactConfig.Reasons[payload.Reason] else nil
		HudController.toast(reason or "That didn't work", "Deny")
		if payload.Op == "Restore" then
			refreshBook()
		end
	end)
	-- the BOOK button in the HUD's right-side menu, only without the side
	-- menu (its ARTIFACTS button is the one book button then)
	local hud = HudController.refs()
	if hud and hud.Menu and not script.Parent:FindFirstChild(ArtifactController.SideMenu) then
		local m = CollectionView.menuButton(hud.Menu)
		m.Button.Activated:Connect(function()
			if PlayerControls.owner() ~= nil or CleaningController.isActive() then
				Sfx.play("UIDeny")
				return
			end
			toggleBook()
		end)
		menu = m
	end
	ContextActionService:BindAction(BOOK_ACTION, onBookKey, false, ArtifactController.BookKey)
	-- the prompts on screen (the banner leaves their keys alone)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = nil
	end)
	-- titles over every player's head
	for _, other in Players:GetPlayers() do
		watchTitle(other)
	end
	Players.PlayerAdded:Connect(watchTitle)
	Players.PlayerRemoving:Connect(function(other: Player)
		local board = titles[other]
		if board then
			board:Destroy()
			titles[other] = nil
		end
	end)
	StateController.onChanged(function()
		updateMenu()
		-- an unchanged record comes back as the same table (StateService sends
		-- it only when it changed): nothing to redraw
		local record = artifacts()
		if record == shownRecord and (screen ~= "Book" or walletKey(wallet()) == shownWallet) then
			return
		end
		if screen == "Book" then
			refreshBook()
		elseif screen == "Story" then
			local view = journal
			if view then
				shownRecord = record
				listEntries(view, StoryView.entries(record))
			end
		end
	end)
	player.CharacterRemoving:Connect(function()
		ArtifactController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		if screen then
			updateHint()
		end
		updateMenu()
		local view = banner
		if view and bannerFound then
			bannerKeys(view)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local w, h = viewport()
			local b = book
			if b and screen == "Book" then
				CollectionView.layout(b, w, h)
			end
			local j = journal
			if j and screen == "Story" then
				StoryView.layout(j, w, h)
			end
		end)
	end
end

function ArtifactController.start()
	-- another big panel opening closes the book / the journal
	while true do
		task.wait(0.25)
		if screen and os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					ArtifactController.close()
					break
				end
			end
		end
	end
end

return ArtifactController
