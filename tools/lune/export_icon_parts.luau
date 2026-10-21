--[[
	Exports game models that become 3D UI icons (hotbar blaster, ore chunks)
	to build/preview/icon_parts/<name>.json for tools/preview/render_icons.mjs.

	  lune run tools/lune/export_icon_parts.luau [names...]   (no names: every model)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local CF = roblox.CFrame
local Kenney = require("./lib/blaster_kenney")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")

local models: { [string]: any } = {}

models.blaster = Kenney.gun(Loader, 1, "")
models.blaster_copper = Kenney.gun(Loader, 2, "Copper")
models.ore_raw = ItemBuilder.build({ Kind = "Raw", OreId = "Copper" }, CF.new(), 3)
models.ore_copper = ItemBuilder.build({ Kind = "Clean", OreId = "Copper", Grade = "Pristine" }, CF.new(), 4)
models.ore_silver = ItemBuilder.build({ Kind = "Clean", OreId = "Silver", Grade = "Pristine" }, CF.new(), 5)
models.ingot_gold = ItemBuilder.build({ Kind = "Ingot", OreId = "Gold", Grade = "Pristine" }, CF.new(), 6)

-- Ore Pen items for the backpack window (in the game these show as live 3D
-- ViewportFrames, so they need no uploads; the preview uses these pictures)
for _, row in
	{
		{ "Clean", "Ruby", "Pristine" },
		{ "Clean", "Silver", "Flawless" },
		{ "Ingot", "Gold", "Pristine" },
		{ "Clean", "Diamond", "Clean" },
		{ "Raw", "Copper" },
		{ "Clean", "Copper", "Rough" },
		{ "Clean", "Amethyst", "Clean" },
		{ "Ingot", "Silver", "Clean" },
		{ "Raw", "Stormcore" },
		{ "Clean", "Jade", "Pristine" },
		{ "Clean", "Stormcore", "Flawless" },
		{ "Crushed", "Iron", "Clean" },
		{ "Clean", "Quartz", "Clean" },
		{ "Clean", "Heartstone", "Pristine" },
		{ "Raw", "Silver" },
		{ "Ingot", "Copper", "Clean" },
		{ "Clean", "Emerald", "Clean" },
		{ "Clean", "Coal", "Rough" },
	}
do
	local name = "item_" .. row[1] .. "_" .. row[2]
	local ok, model = pcall(ItemBuilder.build, { Kind = row[1], OreId = row[2], Grade = row[3] }, CF.new(), name)
	if ok then
		models[name] = model
	else
		print("skipped " .. name .. " (no such ore any more)")
	end
end

-- the shop's Express Train pass: the game's own locomotive
local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
models.train = TrainBuilder.locomotive(roblox.Color3.fromRGB(226, 72, 60))

-- every roster machine (build tray cards; Soft style models from KitMachines)
local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
for _, entry in KitMachines.Catalog do
	models["machine_" .. entry.Id] = KitMachines.buildAny(entry.Id)
end

-- every ore, cleaned (the Ore Codex; in the game a live ViewportFrame)
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
for _, ore in OreData.List do
	local name = "item_Clean_" .. ore.Id
	if not models[name] then
		models[name] = ItemBuilder.build({ Kind = "Clean", OreId = ore.Id, Grade = "Clean" }, CF.new(), name)
	end
end

-- the older machines without a Soft-style model (MachineBuilder)
local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
for _, id in { "StorageCrate", "Anvil", "SellChute" } do
	if not models["machine_" .. id] then
		models["machine_" .. id] = MachineBuilder.build(id)
	end
end

-- the STAR blasters (the Star Forge's BLASTERS cards; in the game a live ViewportFrame)
local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
for _, star in StarBlasterData.List do
	models["star_" .. star.Id] = BlasterBuilder.buildStar(star, 10, "")
end

-- the 3D banknotes (the HUD's money, the shop's coin packs; in the game live ViewportFrames)
local CashBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.CashBuilder")
for name, make in CashBuilder.Pictures do
	models[name] = make()
end

-- every golem and capsule (IconAssets' Golems sheet; the shop banner's cards)
local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
for _, golem in GolemConfig.List do
	models["golem_" .. golem.Id] = GolemBuilder.build(golem.Id)
end
for _, capsule in CapsuleConfig.List do
	models["capsule_" .. capsule.Id] = GolemBuilder.capsule(capsule.Id)
end
-- the upcoming limited editions' golems and every set's shard (previews)
local LimitedUpcoming = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedUpcoming")
for _, set in LimitedUpcoming.Sets do
	for _, golem in set.Golems do
		models["golem_" .. golem.Id] = GolemBuilder.build(golem.Id)
	end
	models["shard_" .. set.Id] = GolemBuilder.shard(set.Id, nil, set.Backdrop.Ground, set.Backdrop.Accent)
end

-- only these: lune run tools/lune/export_icon_parts.luau star_Comet star_Nebula
local only = process.args
if #only > 0 then
	for name in models do
		if not table.find(only, name) then
			models[name] = nil
		end
	end
end

fs.writeDir(root .. "/build/preview/icon_parts")
for name, model in models do
	local scene = Export.collect(model)
	fs.writeFile(root .. "/build/preview/icon_parts/" .. name .. ".json", serde.encode("json", scene))
	print(string.format("Exported icon part model %s: %d parts", name, #scene.parts))
end
