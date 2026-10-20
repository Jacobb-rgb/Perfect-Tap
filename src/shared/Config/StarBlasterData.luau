--[[
	STAR blasters (proposal 2026-10-20, the owner's idea): five weapons above
	the ten blaster levels that unlock only after rebirths ("Star Forge"),
	buyable for Robux and KEPT through every later rebirth (losing something
	you paid for isn't fair). DESIGN ONLY until the owner picks the options
	below; the pictures come from tools/lune/lib/star_blasters_preview.luau.

	Each one is a Kenney Blaster Kit shape the levels don't use (the kit's
	f, h, l, o, q: KenneyBlaster.Models 11-15), in its own celestial skin,
	with the level 10 detail (crystals, a crown round the barrel, sparks or
	flames).

	  Unlock   the rebirth count that opens it (Rebirths >= Unlock)
	  Mult     its damage against your blaster level's (owner's pick: see
	           POWER below); the beam takes its Glow
	  Robux    a one-time Game Pass price (placeholder, the owner decides)
	  Stars    the Forge Stars price if the owner wants a way without Robux
	           (placeholder; one option below)

	Owner's open choices (docs/plans/STAR_BLASTERS.md):
	  POWER  A (recommended) Mult x the damage of the blaster level you have
	           forged: the best gun at every level, never a skip after a
	           rebirth; B a fixed power over LV 10 at any level (a rebirth
	           run becomes trivial: pay-to-win)
	  EARN   1 Robux only; 2 (recommended) Robux OR Forge Stars in the Star
	           Shop; 3 free at a higher rebirth count, Robux opens it at its
	           Unlock count
]]

export type StarBlaster = {
	Id: string,
	Name: string,
	Index: number, -- 1..5: KenneyBlaster.Models[10 + Index]
	Unlock: number, -- rebirths needed
	Mult: number, -- damage x (see POWER)
	Body: Color3,
	Glow: Color3,
	Magma: boolean, -- lava cracks and flames (else stars and sparks)
	Robux: number, -- placeholder Game Pass price
	Stars: number, -- placeholder Forge Stars price (EARN option 2)
	Text: string,
}

local rgb = Color3.fromRGB

local StarBlasterData = {}

StarBlasterData.List = {
	{
		Id = "Comet",
		Name = "Comet Launcher",
		Index = 1,
		Unlock = 1,
		Mult = 1.2,
		Body = rgb(44, 82, 160),
		Glow = rgb(150, 226, 255),
		Magma = false,
		Robux = 149,
		Stars = 20,
		Text = "An icy comet in a launcher",
	},
	{
		Id = "Nebula",
		Name = "Nebula Twin",
		Index = 2,
		Unlock = 2,
		Mult = 1.35,
		Body = rgb(98, 40, 150),
		Glow = rgb(255, 120, 225),
		Magma = false,
		Robux = 249,
		Stars = 30,
		Text = "Twin barrels full of pink star dust",
	},
	{
		Id = "Pulsar",
		Name = "Pulsar Rifle",
		Index = 3,
		Unlock = 3,
		Mult = 1.5,
		Body = rgb(20, 84, 104),
		Glow = rgb(80, 255, 220),
		Magma = false,
		Robux = 399,
		Stars = 45,
		Text = "A long rifle that pulses like a dead star",
	},
	{
		Id = "Supernova",
		Name = "Supernova Gatling",
		Index = 4,
		Unlock = 5,
		Mult = 1.65,
		Body = rgb(40, 22, 18),
		Glow = rgb(255, 170, 60),
		Magma = true,
		Robux = 599,
		Stars = 65,
		Text = "Four barrels of an exploding star",
	},
	{
		Id = "Singularity",
		Name = "Singularity Rail",
		Index = 5,
		Unlock = 8,
		Mult = 1.8,
		Body = rgb(38, 26, 70),
		Glow = rgb(176, 110, 255),
		Magma = false,
		Robux = 899,
		Stars = 90,
		Text = "A black hole between two rails",
	},
} :: { StarBlaster }

StarBlasterData.ById = {} :: { [string]: StarBlaster }
for _, star in StarBlasterData.List do
	StarBlasterData.ById[star.Id] = star
end

return StarBlasterData
