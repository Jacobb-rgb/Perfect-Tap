--[[
	Quick teleports (owner 2026-10-17): a bar at the top centre of the HUD
	with BASE (your own plot), LOBBY (the town spawn) and VAULT (the Blaster
	Vault). TeleportService moves the character, TeleportController /
	TeleportView draw the bar. The "Elevator" spot (Bar = false) has no
	button here: ElevatorController's left side button (shown only while the
	world has a stop: ElevatorAttribute) sends it, and the stop's prompt then
	opens the floor picker (owner 2026-10-18).
]]

local rgb = Color3.fromRGB

local TeleportConfig = {}

export type Destination = "Base" | "Lobby" | "Vault" | "Elevator"

export type Spot = {
	Id: Destination,
	Label: string, -- the button's name (words only, no emoji)
	Color: Color3,
	Dark: Color3,
	Bar: boolean, -- true = the top bar; false = no bar button (the elevator: ElevatorController's side button)
}

TeleportConfig.Spots = {
	{ Id = "Base", Label = "BASE", Color = rgb(255, 176, 64), Dark = rgb(196, 106, 26), Bar = true },
	{ Id = "Lobby", Label = "LOBBY", Color = rgb(96, 186, 255), Dark = rgb(38, 110, 186), Bar = true },
	{ Id = "Vault", Label = "VAULT", Color = rgb(182, 118, 255), Dark = rgb(104, 56, 178), Bar = true },
	{ Id = "Elevator", Label = "LIFT", Color = rgb(110, 214, 92), Dark = rgb(52, 136, 50), Bar = false },
} :: { Spot }

TeleportConfig.ById = {} :: { [string]: Spot }
for _, spot in TeleportConfig.Spots do
	TeleportConfig.ById[spot.Id] = spot
end

TeleportConfig.Cooldown = 3 -- seconds between two teleports (the server allows a little less for lag)
TeleportConfig.ServerCooldown = 2.5
TeleportConfig.Fade = 0.18 -- seconds the screen takes to go dark / come back
TeleportConfig.ReplyTimeout = 4 -- the client fades back in by itself after this long
TeleportConfig.StandHeight = 3 -- studs above the ground a character lands
TeleportConfig.Spread = 3 -- studs of random spread so players don't land inside each other
TeleportConfig.VaultFront = 6 -- studs in front of the Blaster Vault's steps
TeleportConfig.ElevatorTag = "MineElevator" -- MineKit elevator stops (attribute Floor, a "Base" plate, front -Z)
TeleportConfig.ElevatorAttribute = "TeleportElevator" -- Workspace attribute: true while an elevator stop exists

-- Refusal codes -> text for the player.
TeleportConfig.Reasons = {
	Cooldown = "Wait a moment before teleporting again.",
	NoBase = "Your base isn't ready yet.",
	NotHere = "That place isn't open yet.",
	Cleaning = "Finish cleaning first.",
	Dead = "You can't teleport right now.",
}

return TeleportConfig
