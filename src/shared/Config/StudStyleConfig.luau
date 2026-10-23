--[[
	The studded style: classic Roblox studs on the whole map (owner 2026-10-24,
	branch art/stud-style, pictures first). Shared/StudStyle.luau does the work,
	StudStyleController runs it on every client, StudStyleService makes the
	custom stud materials on the server. Docs: docs/STUD_STYLE.md.

	Two looks (the owner picks one):
	- "Classic": Roblox's own square studs (SurfaceType.Studs on every face, Inlet
	  underneath). Roblox draws surfaces only on the Plastic material, so a
	  SmoothPlastic part turns Plastic for the look and keeps SmoothPlastic's
	  physics (CustomPhysicalProperties). Works with no uploads. Parts of other
	  materials (slate, metal, wood, ...) get the custom studs once the stud
	  pictures are uploaded, until then they stay as they are.
	- "Custom": our own stud pictures (docs/art/studs, NAHRAJ_DO_ROBLOXU/studs)
	  as MaterialVariants: every part keeps its Material, its colour and its
	  physics; only the surface gets studs. Needs the three uploaded ids below.

	Nothing is a new part: no stud instances, no Textures. The map on the server
	is never changed (the clients restyle what streams to them), and every
	changed part carries the StudStyle attribute with what it was, so
	StudStyle.restoreTree puts it back exactly.
]]

local StudStyleConfig = {}

export type Look = string -- "Classic" or "Custom" (Shared/StudStyle.look: anything else is Classic)

-- Master switch (off on main until the owner picks a look). At run time the
-- Workspace attribute "StudStyle" (true / false, set by StudStyleService from
-- this) switches it on every client: workspace:SetAttribute("StudStyle", false).
StudStyleConfig.Enabled = false
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

-- Classic look: the materials that turn Plastic (with their own physics kept)
-- and the surface on each face.
StudStyleConfig.Classic = {
	Convert = { SmoothPlastic = true } :: { [string]: boolean },
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
-- patterns stays smooth ("Sea$": Sea, OuterSea, not BenchSeat or GoldSeam):
-- clouds, water, the island's invisible walls, build ghosts, the golem pets
-- (GolemFollowers), the riders' boards (ClientHoverboards), short-lived effects (WorldMotion).
StudStyleConfig.SkipNames = { "Cloud", "Water", "Sea$", "Boundary", "Ghost", "Preview", "GolemFollowers", "Hoverboards", "WorldMotion" }
-- A part (or anything above it) with this tag or attribute (true) stays smooth.
StudStyleConfig.SkipTag = "NoStuds"

-- Clients restyle new parts in batches (streaming brings thousands at once).
StudStyleConfig.BatchSize = 1500 -- parts per frame

-- The custom stud materials can be made (ids uploaded, or a preview).
function StudStyleConfig.customReady(): boolean
	return StudStyleConfig.Previewing or StudStyleConfig.Assets.NormalMap > 0
end

return StudStyleConfig
