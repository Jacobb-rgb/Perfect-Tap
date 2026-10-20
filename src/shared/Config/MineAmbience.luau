--[[
	Quiet mine ambience for the five mine floors (2026-10-18). What plays where:

	  MineDrip    water dripping now and then        floor 1 by the crystals on the
	                                                 side and back walls, floor 3 from
	                                                 the ceiling
	  MineRumble  a rare, distant deep rumble        floors 1, 2 and 4 (deep in the back
	                                                 or up at the ceiling)
	  LagoonLap   water lapping at the shore, a      floor 3 along the lagoon
	              ripple slapping the stones
	  PalaceEcho  a hollow breath through the hall,  floor 4 in the throne hall
	              a far low chime
	  CrystalHum  a soft hum and a crystal tinkle    every floor's Giant Crystal spot and
	                                                 the big hero crystals
	  LavaBubble  lava blorping and a low flow       floor 2 along the lava river and at
	              roar                               the lava fall, floor 5 at the
	                                                 Heartstone (the living ember)

	The floor builders (World/Mine/Floor*.luau) mark the spots with
	MineKit.ambience: an Attachment on a part that is already there (no new
	parts), tagged Tag with the attribute Attribute = the kind, the same
	marking as the lobby's World/Lobby/Ambience.luau, so the lobby's client
	AmbienceController (branch review/hory-noc) plays them as they stream in.
	Few spots (4-8 per floor), loops only where they matter, and no point on
	a floor hears more than MaxLoops loops at once (phones).

	WHEN review/hory-noc AND art/mine-floors MEET (whichever lands on main
	second does this):
	  1. Config/AmbienceConfig.luau requires this module and pulls the kinds in
	     right after its `AmbienceConfig.Kinds = { ... }` table, so that
	     AmbienceConfig.def(), the AmbienceController and tests/Ambience.spec's
	     layer checks all see the mine kinds too:
	       local MineAmbience = require(script.Parent.MineAmbience)
	       ...
	       for kind, layers in MineAmbience.Kinds do
	           AmbienceConfig.Kinds[kind] = layers
	       end
	     This module must never require AmbienceConfig (that would be a require
	     loop), so its Layer type is a copy of AmbienceConfig.Layer.
	  2. tests/Ambience.spec.luau's lobby-only checks are scoped to the lobby
	     kinds (Waterfall, Brook, Pond, Forge, Plaza): "exactly 5 kinds", "every
	     spot is in the lobby area" and "<= 20 spots" count only those; the mine
	     spots are checked by tests/MineAmbience.spec.luau.
	Until then the spots are inert markers (nothing on this branch plays them).

	Sounds are SoundConfig keys (the Amb* mine keys: shipped content/sounds files
	or Roblox's own uploads, checked by tests/BlasterFeel.spec.luau and
	tests/MineAmbience.spec.luau).
]]

-- A copy of AmbienceConfig.Layer (review/hory-noc): keep the two the same.
export type Layer = {
	Sound: string?, -- a SoundConfig key
	Id: number?, -- or a Creator Store audio id the owner picks (0 = silent: the layer is skipped)
	Volume: number?, -- for an Id layer
	Pitch: { number }?, -- for an Id layer
	Loop: boolean?, -- loops while the camera is in earshot; otherwise one-shots
	Every: { number }?, -- seconds between one-shots (random in the range)
	Burst: { number }?, -- plays per one-shot (random count in the range)
	Gap: number?, -- seconds between the plays of a burst
	MinDistance: number, -- full volume inside this (Sound.RollOffMinDistance)
	MaxDistance: number, -- silent past this (Sound.RollOffMaxDistance)
}

local MineAmbience = {}

-- the same values as AmbienceConfig.Tag / AmbienceConfig.Attribute (review/hory-noc)
MineAmbience.Tag = "AmbienceSpot"
MineAmbience.Attribute = "Ambience"

-- Nothing is heard further than this: under Workspace.StreamingMinRadius (96,
-- default.project.json), so a spot's part is streamed in while it is audible.
MineAmbience.MaxEarshot = 90

-- per floor: at least / at most this many spots, and never more than MaxLoops loops
-- audible at one point
MineAmbience.SpotsPerFloor = { 4, 8 }
MineAmbience.MaxLoops = 3

MineAmbience.Kinds = {
	MineDrip = {
		{ Sound = "AmbDrip", Every = { 3, 8 }, Burst = { 1, 2 }, Gap = 0.45, MinDistance = 5, MaxDistance = 40 },
	},
	MineRumble = {
		{ Sound = "AmbRumble", Every = { 40, 90 }, MinDistance = 30, MaxDistance = 90 },
	},
	LagoonLap = {
		{ Sound = "AmbLap", Loop = true, MinDistance = 7, MaxDistance = 26 },
		{ Sound = "AmbRipple", Every = { 4, 10 }, MinDistance = 5, MaxDistance = 24 },
	},
	PalaceEcho = {
		{ Sound = "AmbEcho", Every = { 14, 30 }, MinDistance = 20, MaxDistance = 80 },
		{ Sound = "AmbChime", Every = { 25, 50 }, MinDistance = 15, MaxDistance = 70 },
	},
	CrystalHum = {
		{ Sound = "AmbHum", Loop = true, MinDistance = 4, MaxDistance = 22 },
		{ Sound = "AmbTink", Every = { 6, 15 }, Burst = { 1, 3 }, Gap = 0.14, MinDistance = 3, MaxDistance = 18 },
	},
	LavaBubble = {
		{ Sound = "AmbLavaFlow", Loop = true, MinDistance = 6, MaxDistance = 32 },
		{ Sound = "AmbBubble", Every = { 1.2, 3.5 }, Burst = { 1, 3 }, Gap = 0.22, MinDistance = 5, MaxDistance = 30 },
	},
} :: { [string]: { Layer } }

-- The kinds each floor uses (floor index -> kinds); the builders place exactly these.
MineAmbience.Floors = {
	{ "MineDrip", "MineRumble", "CrystalHum" },
	{ "LavaBubble", "MineRumble", "CrystalHum" },
	{ "LagoonLap", "MineDrip", "CrystalHum" },
	{ "PalaceEcho", "MineRumble", "CrystalHum" },
	{ "LavaBubble", "CrystalHum" },
} :: { { string } }

return MineAmbience
