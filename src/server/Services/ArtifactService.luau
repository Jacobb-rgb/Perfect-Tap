--[[
	ArtifactService: artifacts of Kaldrum, the collection book, the story
	chapters and the museum on every base (step 7; the rules and numbers
	live in Shared/Config/ArtifactConfig and StoryConfig).

	Finding one
	  MiningService rolls once per shattered rock (Bonuses.artifactChance:
	  the zone's chance x the Prospector bonus) and calls onArtifactRoll
	  (player, zoneId, position); this service then picks WHICH artifact
	  (ArtifactConfig.pick(zone, roll), rarer deeper) and records it at once,
	  with no yield: ArtifactConfig.add into data.Artifacts, Stats.ArtifactsFound
	  + 1 (duplicates too: the ARTIFACTS board), a duplicate's
	  ArtifactConfig.DuplicateShards (Shards.add), DataService.changed.
	  Chosen on purpose (the simpler, robust way): the find goes straight
	  into the collection, there is no relic item in the world to pick up,
	  so nothing can be lost, stolen, duplicated or left behind in a mine.
	  ArtifactFound { Artifact, Count, New, Collection, Completed, Shards?,
	  Position } then lets the finder's client play the moment: a relic pops
	  out of the rock and flies to the player, then the reveal card.
	Completing a collection (its last missing artifact)
	  unlocks its StoryConfig chapter and its reward, both derived from the
	  save: the bonus reaches the player through Bonuses' "Collections"
	  provider (the IncomePct one through EconomyService's one income
	  bonus), the title and the podium skin are ArtifactConfig.titles /
	  Reward.PodiumSkin. The finder gets a "Reward" toast with all three.
	ArtifactAction ("ReadChapter", { Collection }): marks a completed
	  collection's chapter read (data.Artifacts.Chapters[id] = true; the
	  "NEW" badge in the book goes away). ActionResult { Action = "Artifact",
	  Op = "ReadChapter", Ok, Reason? ("BadCollection" | "NotComplete"), Id }.
	Prompts (F / gamepad Y)
	  FossilDig (lobby)  "Collection Book" at the dig's gate side and "Read
	                     Journal" at the story screen at its back
	  GuildBoard (lobby) "Read Journal"
	  Museum (base)      "Collection Book"
	  They open the book (OpenUI "Artifacts") or the journal (OpenUI "Story").
	The museum
	  At server start every plot's yard gets a MuseumBuilder museum
	  (Plot_<id>.Yard.Museum, Atomic streaming; PlotBuilder is not changed).
	  When a plot is assigned it shows its owner's finds (MuseumBuilder.show),
	  a new find adds its relic, a freed plot is emptied.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local StatConfig = require(Shared.Config.StatConfig)
local StoryConfig = require(Shared.Config.StoryConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local Shards = require(script.Parent.Parent.Shards)
local MuseumBuilder = require(script.Parent.Parent.World.MuseumBuilder)
local DataService = require(script.Parent.DataService)
local MiningService = require(script.Parent.MiningService)
local PlotService = require(script.Parent.PlotService)

local ArtifactService = {}

ArtifactService.PromptDistance = 12
ArtifactService.PromptTag = "ArtifactPrompt" -- every prompt this service adds (tests, the client)

export type Found = {
	Artifact: string,
	Count: number,
	New: boolean,
	Collection: string,
	Completed: boolean,
	Shards: number?,
	Position: Vector3?,
}

-- Swappable for the Lune tests.
local rng: Random? = nil
local function nextRoll(): number
	local r = rng or Random.new()
	rng = r
	return r:NextNumber()
end
local random: () -> number = nextRoll

local hooked: { [Instance]: boolean } = {}
local foundCallbacks: { (Player, Found) -> () } = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Listeners (badges, analytics, tutorial): (player, found) after every find.
function ArtifactService.onFound(callback: (Player, Found) -> ())
	table.insert(foundCallbacks, callback)
end

-- data.Artifacts as a record with its two tables (a pure fix-up for writers).
local function artifactsOf(data: { [string]: any }): { [string]: any }
	local artifacts = data.Artifacts
	if type(artifacts) ~= "table" then
		artifacts = {}
		data.Artifacts = artifacts
	end
	if type(artifacts.Found) ~= "table" then
		artifacts.Found = {}
	end
	if type(artifacts.Chapters) ~= "table" then
		artifacts.Chapters = {}
	end
	return artifacts
end

-- The toast for a completed collection: chapter, title, skin and bonus.
function ArtifactService.completedText(collectionId: string): string
	local collection = ArtifactConfig.CollectionById[collectionId]
	if not collection then
		return "Collection complete!"
	end
	local chapter = StoryConfig.ByCollection[collectionId]
	local reward = collection.Reward
	local skin = ArtifactConfig.PodiumSkins[reward.PodiumSkin]
	local parts = {}
	if chapter then
		table.insert(parts, `Chapter {chapter.Number} unlocked`)
	end
	table.insert(parts, `title "{reward.Title}"`)
	if skin then
		table.insert(parts, `{skin.Name} podium skin`)
	end
	table.insert(parts, StatConfig.describe(reward.Bonus.Stat, reward.Bonus.Value))
	return `{collection.Name} complete! ` .. table.concat(parts, ", ")
end

---------------------------------------------------------------- the museum

local function museumOf(plotId: number): Model?
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	local museum = yard and yard:FindFirstChild(MuseumBuilder.Name)
	return if museum and museum:IsA("Model") then museum else nil
end

-- Shows the plot owner's finds in its museum (none without an owner).
function ArtifactService.refreshMuseum(plotId: number): number
	local museum = museumOf(plotId)
	if not museum then
		return 0
	end
	local owner = PlotService.ownerOf(plotId)
	local data = owner and DataService.get(owner)
	return MuseumBuilder.show(museum, PlotService.plotCFrame(plotId), if data then data.Artifacts else nil)
end

---------------------------------------------------------------- finds

--[[
	Records one artifact find for `player` in `zoneId` (see the header).
	`artifactId` forces which one (tests, events); nil = rolled by the zone's
	odds. Returns what was found (nil: no save, or nothing to find).
]]
function ArtifactService.find(player: Player, zoneId: string, position: Vector3?, artifactId: string?): Found?
	local data = DataService.get(player)
	if not data or type(zoneId) ~= "string" then
		return nil
	end
	local id = artifactId or ArtifactConfig.pick(zoneId, random())
	local art = if id then ArtifactConfig.ById[id] else nil
	if not id or not art then
		return nil
	end
	local artifacts = artifactsOf(data)
	local count, isNew, completed = ArtifactConfig.add(artifacts, id)
	if count <= 0 then
		return nil
	end
	local stats = data.Stats
	if type(stats) ~= "table" then
		stats = {}
		data.Stats = stats
	end
	stats.ArtifactsFound = (if finite(stats.ArtifactsFound) then stats.ArtifactsFound else 0) + 1
	local found: Found = {
		Artifact = id,
		Count = count,
		New = isNew,
		Collection = art.Collection,
		Completed = completed ~= nil,
		Position = position,
	}
	if not isNew then
		local shards = ArtifactConfig.DuplicateShards[art.Rarity] or 0
		if shards > 0 then
			Shards.add(data, shards)
			found.Shards = shards
		end
	end
	DataService.changed(player)
	if player.Parent then
		Net.fire("ArtifactFound", player, found)
		if completed then
			Net.fire("Notify", player, { Text = ArtifactService.completedText(completed), Kind = "Reward" })
		end
	end
	if isNew then
		local plotId = PlotService.plotOf(player)
		if plotId then
			local ok, err = pcall(ArtifactService.refreshMuseum, plotId)
			if not ok then
				warn("[ArtifactService] museum: " .. tostring(err))
			end
		end
	end
	for _, callback in foundCallbacks do
		task.spawn(callback, player, found)
	end
	return found
end

---------------------------------------------------------------- the book and the journal

local function reply(player: Player, ok: boolean, reason: string?, id: string?)
	Net.fire("ActionResult", player, { Action = "Artifact", Op = "ReadChapter", Ok = ok, Reason = reason, Id = id })
end

-- ArtifactAction "ReadChapter" { Collection }: (ok, reason?).
function ArtifactService.readChapter(player: Player, collectionId: any): (boolean, string?)
	local data = DataService.get(player)
	if type(collectionId) ~= "string" or not ArtifactConfig.CollectionById[collectionId] or not data then
		return false, "BadCollection"
	end
	local artifacts = artifactsOf(data)
	if not ArtifactConfig.isComplete(artifacts, collectionId) then
		return false, "NotComplete"
	end
	if artifacts.Chapters[collectionId] ~= true then
		artifacts.Chapters[collectionId] = true
		DataService.changed(player)
	end
	return true, nil
end

local function onAction(player: Player, action: any, arg: any)
	if action ~= "ReadChapter" then
		return
	end
	local collectionId = if type(arg) == "table" then arg.Collection else nil
	local ok, reason = ArtifactService.readChapter(player, collectionId)
	reply(player, ok, reason, if type(collectionId) == "string" and #collectionId <= 64 then collectionId else nil)
end

---------------------------------------------------------------- prompts

local function makePrompt(part: BasePart, name: string, offset: CFrame, action: string, object: string, ui: string)
	local old = part:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local point = Instance.new("Attachment")
	point.Name = name
	point.CFrame = offset
	point.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ArtifactService.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt:AddTag(ArtifactService.PromptTag)
	prompt.Parent = point
	prompt.Triggered:Connect(function(player: Player)
		if DataService.get(player) then
			Net.fire("OpenUI", player, ui, {})
		end
	end)
end

local function primaryOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- The dig's bed (PrimaryPart, front = -Z): the book at the gate side, the
-- journal at the story screen behind the pit.
local function hookDig(instance: Instance)
	local bed = primaryOf(instance)
	if hooked[instance] or not bed then
		return
	end
	hooked[instance] = true
	local half = bed.Size / 2
	makePrompt(bed, "BookPoint", CFrame.new(half.X * 0.35, 3, -half.Z + 1.5), "Collection Book", "Artifacts of Kaldrum", "Artifacts")
	makePrompt(bed, "StoryPoint", CFrame.new(0, 3.5, half.Z - 1), "Read Journal", "Kingdom of Kaldrum", "Story")
end

-- The Guild board (PrimaryPart "Board", front = -Z).
local function hookBoard(instance: Instance)
	local board = primaryOf(instance)
	if hooked[instance] or not board then
		return
	end
	hooked[instance] = true
	makePrompt(board, "StoryPoint", CFrame.new(0, -1, -board.Size.Z / 2 - 1), "Read Journal", "Kingdom of Kaldrum", "Story")
end

-- Builds a plot's museum (once) with its prompt; true when it stands.
local function setupPlot(plotId: number): boolean
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	if not plot or not yard then
		warn(`[ArtifactService] plot {plotId} has no Yard (old map?)`)
		return false
	end
	if museumOf(plotId) then
		return true
	end
	local museum = MuseumBuilder.build(PlotService.plotCFrame(plotId))
	museum:SetAttribute("PlotId", plotId)
	museum.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	museum.Parent = yard
	local floor = museum.PrimaryPart
	local point = floor and floor:FindFirstChild(MuseumBuilder.PromptName)
	if floor and point and point:IsA("Attachment") then
		makePrompt(floor, "BookPoint", point.CFrame, "Collection Book", "Museum", "Artifacts")
		point:Destroy()
	end
	return true
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/Artifacts.spec.luau).
ArtifactService._test = {
	action = onAction,
	setupPlot = setupPlot,
	hookDig = hookDig,
	hookBoard = hookBoard,
	museumOf = museumOf,
	setRandom = function(fn: () -> number)
		random = fn
	end,
	reset = function()
		table.clear(hooked)
		table.clear(foundCallbacks)
		rng = nil
		random = nextRoll
	end,
}

function ArtifactService.init()
	Net.on("ArtifactAction", onAction)
	MiningService.onArtifactRoll(function(player: Player, zoneId: string, position: Vector3)
		ArtifactService.find(player, zoneId, position, nil)
	end)
	for _, plot in WorldLayout.Plots do
		local ok, err = pcall(setupPlot, plot.Id)
		if not ok then
			warn(`[ArtifactService] plot {plot.Id}: {err}`)
		end
	end
	PlotService.onAssigned(function(_player: Player, plotId: number)
		ArtifactService.refreshMuseum(plotId)
	end)
	PlotService.onReleased(function(_player: Player, plotId: number)
		local museum = museumOf(plotId)
		if museum then
			MuseumBuilder.show(museum, PlotService.plotCFrame(plotId), nil)
		end
	end)
end

function ArtifactService.start()
	-- the map is built in WorldService.init, so the lobby props exist by now
	for _, instance in CollectionService:GetTagged("FossilDig") do
		hookDig(instance)
	end
	for _, instance in CollectionService:GetTagged("GuildBoard") do
		hookBoard(instance)
	end
	CollectionService:GetInstanceAddedSignal("FossilDig"):Connect(hookDig)
	CollectionService:GetInstanceAddedSignal("GuildBoard"):Connect(hookBoard)
	local function unhook(instance: Instance)
		hooked[instance] = nil
	end
	CollectionService:GetInstanceRemovedSignal("FossilDig"):Connect(unhook)
	CollectionService:GetInstanceRemovedSignal("GuildBoard"):Connect(unhook)
end

return ArtifactService
