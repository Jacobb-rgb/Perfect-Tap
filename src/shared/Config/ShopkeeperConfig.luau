--[[
	The shopkeepers (owner 2026-10-24: "one guy for every shop, made from my
	skin, all of them identical"): the owner's own Roblox avatar stands behind
	every shop counter.

	  World builders mark each keeper's spot with an Attachment on the shop's
	  counter (ShopkeeperConfig.mark: tag ShopkeeperSpot, attribute Shop, the
	  attachment's frame = the keeper's feet on the floor, LookVector = toward
	  the customers). An Attachment is no part: the map's part budgets don't
	  change, and the spot streams in and out with its counter.
	  ShopkeeperService (server) builds ONE avatar model from the owner's
	  UserId at start into ReplicatedStorage (TemplateName).
	  ShopkeeperController (client) clones it onto every spot that streams in
	  (client-side only: nothing more streams to the phones), plays the idle,
	  turns the head toward the player, waves and talks when the player comes
	  close and says thanks after a buy or a sale nearby.

	Whose avatar: UserId when set (> 0), else the game's creator when a user
	owns it (game.CreatorType User), else in Studio the first player (the one
	pressing Play). No one found = no keepers (the shops still work).
]]

local ShopkeeperConfig = {}

ShopkeeperConfig.Tag = "ShopkeeperSpot"
ShopkeeperConfig.TemplateName = "ShopkeeperTemplate"

-- The owner's Roblox UserId (0 = the game's creator, see above).
ShopkeeperConfig.UserId = 0

-- how often / how long the server retries a failed avatar download
ShopkeeperConfig.Retries = 4
ShopkeeperConfig.RetryDelay = 8 -- seconds, doubled after every failure

ShopkeeperConfig.DefaultScale = 1.15 -- a little bigger than a player: he reads over the counters

-- A soft light in front of his chest (client-side, only on the keepers that
-- streamed in): the shops' insides are dark and the owner's skin is black.
ShopkeeperConfig.FaceLight = {
	Offset = Vector3.new(0, 1.2, -2.6), -- from his root, in his own frame (-Z = in front)
	Range = 8,
	Brightness = 1.3,
	Color = Color3.fromRGB(255, 236, 214),
}

ShopkeeperConfig.LookDistance = 28 -- studs: the head follows the player inside this
ShopkeeperConfig.LookYaw = math.rad(65) -- the head turns at most this far left or right
ShopkeeperConfig.LookPitch = math.rad(20) -- and this far up or down
ShopkeeperConfig.LookSpeed = 6 -- how fast the head catches up (per second)

ShopkeeperConfig.GreetDistance = 14 -- studs: a wave and a hello when the player walks up
ShopkeeperConfig.GreetCooldown = 25 -- seconds before the same keeper greets again
ShopkeeperConfig.ThanksDistance = 24 -- studs: a buy or a sale this close makes the keeper cheer
ShopkeeperConfig.BubbleSeconds = 3.2

-- Roblox's own animations (made by Roblox: they play in every experience).
ShopkeeperConfig.Animations = {
	R15 = {
		Idle = "rbxassetid://507766666",
		Wave = "rbxassetid://507770239",
		Cheer = "rbxassetid://507770677",
	},
	R6 = {
		Idle = "rbxassetid://180435571",
		Wave = "rbxassetid://128777973",
		Cheer = "rbxassetid://129423030",
	},
}

export type Shop = {
	Hello: { string }, -- what he says when the player walks up
	Thanks: { string }, -- after a buy or a sale
	Scale: number?, -- the avatar's scale here (default DefaultScale)
}

local THANKS = { "Thanks!", "Great choice!", "Come back soon!" }

ShopkeeperConfig.Shops = {
	Gear = { Hello = { "Gear up, miner!", "Boots, lamps, magnets!" }, Thanks = THANKS, Scale = 1.1 }, -- (the door's lintel)
	Tech = { Hello = { "Machines and upgrades!", "Build a bigger factory!" }, Thanks = THANKS, Scale = 1.1 },
	Sell = { Hello = { "Got ore? I'll buy it!", "Bring me your ore!" }, Thanks = { "Pleasure doing business!", "Thanks, miner!" } },
	Enchant = { Hello = { "Want some magic?", "Runes for your blaster!" }, Thanks = THANKS },
	Vault = { Hello = { "The best blasters are here!", "Welcome to the Vault!" }, Thanks = THANKS, Scale = 1.25 },
	Eggs = { Hello = { "Hatch a golem!", "Which egg today?" }, Thanks = { "Good luck!", "Enjoy your golem!" } },
	Droppers = { Hello = { "Droppers! Ore all day!", "Need a dropper?" }, Thanks = THANKS },
	Backpacks = { Hello = { "Need a bigger backpack?", "Carry more ore!" }, Thanks = THANKS },
} :: { [string]: Shop }

-- The keeper's scale at a shop.
function ShopkeeperConfig.scale(shop: string): number
	local s = ShopkeeperConfig.Shops[shop]
	return if s and s.Scale then s.Scale else ShopkeeperConfig.DefaultScale
end

-- Line `n` (1-based, wraps) of a shop's hello or thanks list.
function ShopkeeperConfig.line(shop: string, kind: "Hello" | "Thanks", n: number): string
	local s = ShopkeeperConfig.Shops[shop]
	local lines = if s then s[kind] else THANKS
	return lines[(n - 1) % #lines + 1]
end

-- Whose avatar the keepers wear (0 = not known yet: in Studio the first
-- player then, ShopkeeperService): see the header.
function ShopkeeperConfig.ownerId(configured: number, creatorIsUser: boolean, creatorId: number): number
	if configured > 0 then
		return configured
	elseif creatorIsUser and creatorId > 0 then
		return creatorId
	end
	return 0
end

-- Marks a keeper spot on `counter`: `feet` = his feet on the floor, facing
-- the customers (LookVector). `shop` = a key of ShopkeeperConfig.Shops.
function ShopkeeperConfig.mark(counter: BasePart, feet: CFrame, shop: string): Attachment
	local spot = Instance.new("Attachment")
	spot.Name = "ShopkeeperSpot"
	spot.CFrame = counter.CFrame:ToObjectSpace(feet)
	spot:SetAttribute("Shop", shop)
	spot:AddTag(ShopkeeperConfig.Tag)
	spot.Parent = counter
	return spot
end

-- The head's turn toward `target` from a head at `head` (yaw, pitch in the
-- keeper's own frame `body`, clamped; 0, 0 when the target is behind him).
function ShopkeeperConfig.lookAngles(body: CFrame, head: Vector3, target: Vector3): (number, number)
	local rel = body:VectorToObjectSpace(target - head)
	local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
	if flat < 0.05 or rel.Z > 0 then
		return 0, 0 -- right on top of him or behind him: look ahead
	end
	-- Roblox faces -Z: a target on his right (+X) turns the head right (negative yaw)
	local yaw = math.atan2(-rel.X, -rel.Z)
	local pitch = math.atan2(rel.Y, flat)
	local maxYaw, maxPitch = ShopkeeperConfig.LookYaw, ShopkeeperConfig.LookPitch
	return math.clamp(yaw, -maxYaw, maxYaw), math.clamp(pitch, -maxPitch, maxPitch)
end

return ShopkeeperConfig
