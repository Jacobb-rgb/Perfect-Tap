--[[
	Which animation sets are live in the game (owner 2026-10-21). He saw
	videos of all of them. "Zatím žádné" (none yet) for the first three sets;
	then "add the emotes and the golems running". The others stay built and
	tested but switched off until he says yes: flip a switch here.

	  Emotes        the 12 emotes (EmoteConfig) from the EMOTES menu          ON
	  GolemMotion   golem followers run / fly / idle / equip jump             ON
	  PlayerMoves   carry, throw, recoil, spray, hammer, celebrations, cash   off
	  UIMotion      windows pop, button squash, shine, money fly-in           off
	  WorldFx       ore pops out of rocks, hit flash + debris, sell burst     off
]]

local AnimConfig = {
	Emotes = true,
	GolemMotion = true,
	PlayerMoves = false,
	UIMotion = false,
	WorldFx = false,
}

return AnimConfig
