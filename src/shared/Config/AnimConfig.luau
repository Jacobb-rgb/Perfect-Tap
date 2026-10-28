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
	  PixelFx       the pixel reels (owner 2026-10-22): rays turn behind      ON
	                pictures, a gleam sweeps across buttons, pictures lean
	                on hover (Controllers/PixelFxController)
	  RoundMotion   the UI pack reel's motions in the round look (owner OK     ON
	                2026-10-28, round_motion.mp4):
	                windows pop 0.5 -> 1.1 -> 1 in about 0.2 s, buttons grow
	                5 % under the mouse and squash to 0.93 on a press; no
	                shine or breathe loops (UI/Motion.roundMotion)
]]

local AnimConfig = {
	Emotes = true,
	GolemMotion = true,
	PlayerMoves = false,
	UIMotion = false,
	WorldFx = false,
	PixelFx = true,
	RoundMotion = true,
}

return AnimConfig
