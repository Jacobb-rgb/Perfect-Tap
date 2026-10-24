--[[
	The shopkeepers (owner 2026-10-24): a big golem behind every shop counter,
	each shop a different cool golem (GolemBuilder's own golems, just bigger:
	Builders/GolemKeeper), with emotes (Moves/GolemEmotes): it waves when you
	walk up, cheers after a buy, and now and then hops, spins, dances or
	bows by itself. None at the EGGS temple (owner).

	  World builders mark each keeper's spot with an Attachment on the shop's
	  counter (ShopkeeperConfig.mark: tag ShopkeeperSpot, attribute Shop, the
	  attachment's frame = the golem's feet on the floor, LookVector = toward
	  the customers). An Attachment is no part: the map's part budgets don't
	  change, and the spot streams in and out with its counter.
	  ShopkeeperController (client) builds a golem on a spot only while the
	  player is within ShowDistance (and takes it away past HideDistance), so
	  a phone draws one or two of them at a time, and moves only the ones
	  within AnimateDistance.
]]

local ShopkeeperConfig = {}

ShopkeeperConfig.Tag = "ShopkeeperSpot"

ShopkeeperConfig.ShowDistance = 90 -- studs from the player: build the golem
ShopkeeperConfig.HideDistance = 110 -- and take it away again past this
ShopkeeperConfig.CheckEvery = 0.4 -- seconds between the distance checks
ShopkeeperConfig.AnimateDistance = 60 -- studs: golems farther away stand still

-- A soft light in front of the nearest golem inside LightDistance (the
-- shops' insides are dark; one light only: the game's light budget, phones).
ShopkeeperConfig.LightDistance = 40
ShopkeeperConfig.FaceLight = {
	Ahead = 3.4, -- studs in front of the golem
	Up = 0.45, -- share of its height
	Range = 9,
	Brightness = 0.5,
	Color = Color3.fromRGB(255, 236, 214),
}

ShopkeeperConfig.LookDistance = 28 -- studs: the golem turns toward the player inside this
ShopkeeperConfig.LookYaw = math.rad(35) -- at most this far left or right
ShopkeeperConfig.LookSpeed = 4 -- how fast it turns (per second)

ShopkeeperConfig.GreetDistance = 14 -- studs: a wave and a hello when the player walks up
ShopkeeperConfig.GreetCooldown = 25 -- seconds before the same golem greets again
ShopkeeperConfig.ThanksDistance = 24 -- studs: a buy or a sale this close makes the golem cheer
ShopkeeperConfig.EmoteEvery = { 6, 12 } -- seconds between the moves it does by itself
ShopkeeperConfig.BubbleSeconds = 3.2
ShopkeeperConfig.BurstCount = 22 -- gold sparkles when it says thanks
ShopkeeperConfig.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"

export type Shop = {
	Golem: string, -- a GolemConfig kind
	Size: number, -- GolemBuilder's Size (on top of the golem's own Scale)
	Lit: boolean?, -- false: no soft light (a bright shop inside)
	Hello: { string }, -- what it says when the player walks up
	Thanks: { string }, -- after a buy or a sale
}

local THANKS = { "Thanks!", "Great choice!", "Come back soon!" }

-- (sizes: 6 to 7.5 studs tall, clear of each counter; the spots stand the
-- golems on steps the counters hide, so their big heads show over the goods)
ShopkeeperConfig.Shops = {
	Gear = { Golem = "ScaleKnight", Size = 1.6, Hello = { "Gear up, miner!", "Boots, lamps, magnets!" }, Thanks = THANKS },
	Tech = { Golem = "StormSentinel", Size = 1.35, Hello = { "Machines and upgrades!", "Build a bigger factory!" }, Thanks = THANKS },
	Sell = {
		Golem = "Flamewing",
		Size = 1.9, -- (owner: "not very visible, a bit bigger")
		Hello = { "Got ore? I'll buy it!", "Bring me your ore!" },
		Thanks = { "Pleasure doing business!", "Thanks, miner!" },
	},
	Enchant = { Golem = "AetherKing", Size = 1.4, Hello = { "Want some magic?", "Runes for your blaster!" }, Thanks = THANKS },
	Vault = { Golem = "DragonKing", Size = 1.45, Hello = { "The best blasters are here!", "Welcome to the Vault!" }, Thanks = THANKS },
	Droppers = {
		Golem = "EmberHatchling",
		Size = 1.5,
		Lit = false,
		Hello = { "Droppers! Ore all day!", "Need a dropper?" },
		Thanks = THANKS,
	},
	Backpacks = { Golem = "SkySprite", Size = 1.5, Hello = { "Need a bigger backpack?", "Carry more ore!" }, Thanks = THANKS },
} :: { [string]: Shop }

-- Does the golem at `shop` get the soft light (when it is the nearest)?
function ShopkeeperConfig.lit(shop: string): boolean
	local s = ShopkeeperConfig.Shops[shop]
	return not (s and s.Lit == false)
end

-- The golem kind and size at a shop (a plain Gear golem for an unknown one).
function ShopkeeperConfig.golem(shop: string): (string, number)
	local s = ShopkeeperConfig.Shops[shop] or ShopkeeperConfig.Shops.Gear
	return s.Golem, s.Size
end

-- Line `n` (1-based, wraps) of a shop's hello or thanks list.
function ShopkeeperConfig.line(shop: string, kind: "Hello" | "Thanks", n: number): string
	local s = ShopkeeperConfig.Shops[shop]
	local lines = if s then s[kind] else THANKS
	return lines[(n - 1) % #lines + 1]
end

-- Should the golem at `distance` studs be there? (`shown` = it is now:
-- between ShowDistance and HideDistance it stays as it is.)
function ShopkeeperConfig.wanted(distance: number, shown: boolean): boolean
	if shown then
		return distance <= ShopkeeperConfig.HideDistance
	end
	return distance <= ShopkeeperConfig.ShowDistance
end

-- Marks a keeper spot on `counter`: `feet` = the golem's feet on the floor,
-- facing the customers (LookVector). `shop` = a key of ShopkeeperConfig.Shops.
function ShopkeeperConfig.mark(counter: BasePart, feet: CFrame, shop: string): Attachment
	local spot = Instance.new("Attachment")
	spot.Name = "ShopkeeperSpot"
	spot.CFrame = counter.CFrame:ToObjectSpace(feet)
	spot:SetAttribute("Shop", shop)
	spot:AddTag(ShopkeeperConfig.Tag)
	spot.Parent = counter
	return spot
end

-- How far the golem turns toward `target` (radians, clamped; 0 when the
-- target is behind it): `body` = its feet frame, facing -Z.
function ShopkeeperConfig.lookYaw(body: CFrame, target: Vector3): number
	local rel = body:PointToObjectSpace(target)
	if rel.Z > 0 or (rel.X * rel.X + rel.Z * rel.Z) < 0.01 then
		return 0
	end
	-- Roblox faces -Z: a target on its right (+X) turns it right (negative yaw)
	local yaw = math.atan2(-rel.X, -rel.Z)
	return math.clamp(yaw, -ShopkeeperConfig.LookYaw, ShopkeeperConfig.LookYaw)
end

return ShopkeeperConfig
