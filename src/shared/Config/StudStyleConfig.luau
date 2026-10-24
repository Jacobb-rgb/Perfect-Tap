--[[
	The studded style: classic Roblox studs on the whole map (owner 2026-10-24:
	proposal A "Classic" goes into the game). Shared/StudStyle.luau does the work,
	StudStyleController runs it on every client, StudStyleService makes the
	custom stud materials on the server. Docs: docs/STUD_STYLE.md.

	Two looks (the owner picks one):
	- "Classic" (in the game): Roblox's own square studs (SurfaceType.Studs on
	  every face, Inlet underneath). Roblox draws surfaces only on the Plastic
	  material, so every stud material (SmoothPlastic, slate, wood, marble, ...)
	  turns Plastic for the look and keeps its own physics
	  (CustomPhysicalProperties). Works with no uploads.
	- "Custom": our own stud pictures (docs/art/studs, NAHRAJ_DO_ROBLOXU/vystupky)
	  as MaterialVariants: every part keeps its Material, its colour and its
	  physics; only the surface gets studs. Needs the three uploaded ids below.

	Nothing is a new part: no stud instances, no Textures. The map on the server
	is never changed (the clients restyle what streams to them), and every
	changed part carries the StudStyle attribute with what it was, so
	StudStyle.restoreTree puts it back exactly.
]]

local StudStyleConfig = {}

export type Look = string -- "Classic" or "Custom" (Shared/StudStyle.look: anything else is Classic)

-- Master switch (owner 2026-10-24: on, proposal A). At run time the Workspace
-- attribute "StudStyle" (true / false, set by StudStyleService from this)
-- switches it on every client: workspace:SetAttribute("StudStyle", false).
StudStyleConfig.Enabled = true
StudStyleConfig.Look = "Classic" :: Look -- "Classic" | "Custom"

-- The stud pictures (rbxassetid numbers; 0 = not uploaded yet). One picture
-- holds 2 x 2 studs; StudsPerTile 2 makes every stud one stud wide like
-- Roblox's own surfaces, the same size everywhere.
StudStyleConfig.Assets = {
	ColorMap = 0, -- studs_color.png: white with the studs' soft shading (tinted by the part's colour)
	NormalMap = 0, -- studs_normal.png: the raised studs for the light (OpenGL, green up)
	RoughnessMap = 0, -- studs_roughness.png: plastic sheen
}
StudStyleConfig.StudsPerTile = 2

-- Previews outside Roblox (tools/lune/export_scene.luau with STUD_STYLE=...) make
-- the custom materials without ids.
StudStyleConfig.Previewing = false

-- Base materials that get studs. Neon, Glass, ForceField, Foil, Water and Air
-- never do (glows, windows, water, shiny trim); Metal stays metal by default.
StudStyleConfig.Materials = {
	Plastic = true,
	SmoothPlastic = true,
	Slate = true,
	Concrete = true,
	Wood = true,
	WoodPlanks = true,
	Brick = true,
	Cobblestone = true,
	Granite = true,
	Marble = true,
	Pebble = true,
	Fabric = true,
	Plaster = true,
	Grass = true,
	LeafyGrass = true,
	Ground = true,
	Sand = true,
	Sandstone = true,
	Limestone = true,
	Basalt = true,
	Rock = true,
	Pavement = true,
	Asphalt = true,
	Mud = true,
	Snow = true,
	Ice = true,
	Metal = false,
	DiamondPlate = false,
	CorrodedMetal = false,
} :: { [string]: boolean }

-- Classic look: the materials that turn Plastic (each with its own physics
-- kept): every stud material, so the whole map has Roblox's studs as in the
-- owner's picture A, with no uploads. And the surface on each face.
local convert: { [string]: boolean } = {}
for name, on in StudStyleConfig.Materials do
	convert[name] = on
end
StudStyleConfig.Classic = {
	Convert = convert,
	Faces = {
		Top = "Studs",
		Bottom = "Inlet",
		Front = "Studs",
		Back = "Studs",
		Left = "Studs",
		Right = "Studs",
	} :: { [string]: string },
}

-- Which parts are "suitable" (StudStyle.skipReason):
StudStyleConfig.Classes = { Part = true, WedgePart = true, CornerWedgePart = true } :: { [string]: boolean }
StudStyleConfig.Shapes = { Block = true, Wedge = true, CornerWedge = true, Cylinder = true, Ball = false } :: { [string]: boolean }
StudStyleConfig.MaxTransparency = 0.02 -- see-through parts (water, holograms, ghosts) keep their look
StudStyleConfig.MaxReflectance = 0.1 -- mirror-like parts (the sea 0.2, glass); the wet slate paving (0.05) gets studs
StudStyleConfig.MinSide = 0.35 -- studs: the part's middle size (a fence board 0.35 x 0.45 still gets them)
StudStyleConfig.MinLength = 1 -- studs: the part's longest size (pebbles, buds and tiny trim stay smooth)
-- Workspace children that are never touched (ore rocks, carried ore, debris)
StudStyleConfig.SkipRoots = { Nodes = true, Items = true, Debris = true } :: { [string]: boolean }
-- A part (or a model / folder above it) whose name matches one of these Lua
-- patterns stays smooth ("Sea$": Sea, OuterSea, not BenchSeat or GoldSeam).
-- Only the map's ground, roads, floors, walls, fences, buildings, stalls and
-- machines get studs (owner 2026-10-24), not what lies or moves on them.
StudStyleConfig.SkipNames = {
	-- sky, water, the island's invisible walls, build ghosts
	"Cloud",
	"Water",
	"Sea$",
	"Boundary",
	"Ghost",
	"Preview",
	-- golem pets, the riders' boards, short-lived effects, the golem hatching pop
	"GolemFollowers",
	"Hoverboards",
	"WorldMotion",
	"^OpenPop$",
	-- crystals (the mines' clusters, the shards on islands, stalls and the forge),
	-- not the plaza's FireCrystalRing, its CrystalFloor or the CrystalIsle's ground
	"^Crystals?%d*$",
	"^CrystalCluster",
	"^CrystalGroup",
	"^CrystalFacet",
	"EggCrystal",
	"IconCrystal",
	-- ores and relics on show (podiums, the Iron Box glass, museums, the relic pop)
	"^Display",
	"^Artifact$",
	-- the client's trains, the cleaning minigame, the crate opening
	"ClientTrains",
	"CleaningClient",
	"CrateOpening",
}
-- A part (or anything above it) with this tag or attribute (true) stays smooth.
StudStyleConfig.SkipTag = "NoStuds"
-- Single parts another script changes at run time (studs decided once would
-- differ per client), matched by their own name and their model's name (Lua
-- patterns): the podium rims (PodiumService.refreshLocks flips Plot_N.Yard.Podium<slot>.Rim
-- to Neon and back) and the belts' side rails (ConveyorService.setRail opens a
-- belt's RailL / RailR: Transparency 1 and back).
StudStyleConfig.SkipParts = {
	{ Name = "^Rim$", Parent = "^Podium%d+$" },
	{ Name = "^Rail[LR]$", Parent = "" },
} :: { { Name: string, Parent: string } }

-- Clients restyle new parts a little each frame (streaming brings thousands at
-- once): until BudgetMs of the frame is used, looking at the clock every
-- MinPerFrame parts (so at least that many per frame, it always goes on).
StudStyleConfig.BudgetMs = 2
StudStyleConfig.MinPerFrame = 50

-- The custom stud materials can be made (ids uploaded, or a preview).
function StudStyleConfig.customReady(): boolean
	return StudStyleConfig.Previewing or StudStyleConfig.Assets.NormalMap > 0
end

return StudStyleConfig
