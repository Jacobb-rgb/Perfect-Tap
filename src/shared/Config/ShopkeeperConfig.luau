--[[
	The shopkeepers (owner 2026-10-24): one and the same miner behind every
	shop counter, built exactly like the owner's 3D model
	(docs/art/shopkeeper/roblox_miner_shopkeeper.glb -> Builders/ShopkeeperModel,
	Builders/ShopkeeperBuilder): smooth parts, no studs. None at the EGGS
	temple (owner).

	  World builders mark each keeper's spot with an Attachment on the shop's
	  counter (ShopkeeperConfig.mark: tag ShopkeeperSpot, attribute Shop, the
	  attachment's frame = the keeper's feet on the floor, LookVector = toward
	  the customers). An Attachment is no part: the map's part budgets don't
	  change, and the spot streams in and out with its counter.
	  ShopkeeperController (client) builds a keeper on a spot only while the
	  player is within ShowDistance (and takes him away past HideDistance), so
	  a phone draws one or two of them at a time; it plays Roblox's R6 idle,
	  turns the head toward the player, waves and talks when the player comes
	  close and cheers after a buy or a sale nearby.
]]

local ShopkeeperConfig = {}

ShopkeeperConfig.Tag = "ShopkeeperSpot"

ShopkeeperConfig.DefaultScale = 1.15 -- the model is 5.53 studs: a little bigger than a player

ShopkeeperConfig.ShowDistance = 90 -- studs from the player: build him
ShopkeeperConfig.HideDistance = 110 -- and take him away again past this
ShopkeeperConfig.CheckEvery = 0.4 -- seconds between the distance checks

-- Real lights (the helmet lamp's SpotLight, the light on his chest) only on
-- the nearest keeper inside LightDistance: the game's light budget (phones;
-- the others glow with neon and the lamp's beam only).
ShopkeeperConfig.LightDistance = 40

-- Life (style pass, owner 2026-10-24 "a bit nicer, with effects")
ShopkeeperConfig.LifeDistance = 45 -- studs: blinking and the lantern's flicker only this close
ShopkeeperConfig.BlinkEvery = { 2.4, 5.5 } -- seconds between blinks (random in this range)
ShopkeeperConfig.BlinkSeconds = 0.13
ShopkeeperConfig.BurstCount = 22 -- gold sparkles when he says thanks

ShopkeeperConfig.LookDistance = 28 -- studs: the head follows the player inside this
ShopkeeperConfig.LookYaw = math.rad(65) -- the head turns at most this far left or right
ShopkeeperConfig.LookPitch = math.rad(20) -- and this far up or down
ShopkeeperConfig.LookSpeed = 6 -- how fast the head catches up (per second)

ShopkeeperConfig.GreetDistance = 14 -- studs: a wave and a hello when the player walks up
ShopkeeperConfig.GreetCooldown = 25 -- seconds before the same keeper greets again
ShopkeeperConfig.ThanksDistance = 24 -- studs: a buy or a sale this close makes the keeper cheer
ShopkeeperConfig.BubbleSeconds = 3.2

-- Roblox's own R6 animations (made by Roblox: they play in every experience;
-- the keeper's rig has the R6 joint names and frames).
ShopkeeperConfig.Animations = {
	Idle = "rbxassetid://180435571",
	Wave = "rbxassetid://128777973",
	Cheer = "rbxassetid://129423030",
}

export type Shop = {
	Badge: string, -- the word on his apron badge
	Hello: { string }, -- what he says when the player walks up
	Thanks: { string }, -- after a buy or a sale
	Scale: number?, -- his scale here (default DefaultScale)
}

local THANKS = { "Thanks!", "Great choice!", "Come back soon!" }

ShopkeeperConfig.Shops = {
	-- (SHOP and UPGRADES: a little smaller, so the door's lintel doesn't hide his head)
	Gear = { Badge = "SHOP", Hello = { "Gear up, miner!", "Boots, lamps, magnets!" }, Thanks = THANKS, Scale = 1.1 },
	Tech = { Badge = "TECH", Hello = { "Machines and upgrades!", "Build a bigger factory!" }, Thanks = THANKS, Scale = 1.1 },
	Sell = {
		Badge = "SELL",
		Hello = { "Got ore? I'll buy it!", "Bring me your ore!" },
		Thanks = { "Pleasure doing business!", "Thanks, miner!" },
	},
	Enchant = { Badge = "MAGIC", Hello = { "Want some magic?", "Runes for your blaster!" }, Thanks = THANKS },
	Vault = { Badge = "VAULT", Hello = { "The best blasters are here!", "Welcome to the Vault!" }, Thanks = THANKS, Scale = 1.25 },
	Droppers = { Badge = "DROPS", Hello = { "Droppers! Ore all day!", "Need a dropper?" }, Thanks = THANKS },
	Backpacks = { Badge = "PACKS", Hello = { "Need a bigger backpack?", "Carry more ore!" }, Thanks = THANKS },
} :: { [string]: Shop }

-- The word on the keeper's apron badge at a shop.
function ShopkeeperConfig.badge(shop: string): string
	local s = ShopkeeperConfig.Shops[shop]
	return if s then s.Badge else "SHOP"
end

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

-- Should the keeper at `distance` studs be there? (`shown` = he is now:
-- between ShowDistance and HideDistance he stays as he is.)
function ShopkeeperConfig.wanted(distance: number, shown: boolean): boolean
	if shown then
		return distance <= ShopkeeperConfig.HideDistance
	end
	return distance <= ShopkeeperConfig.ShowDistance
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
