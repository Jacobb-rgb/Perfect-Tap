-- MiningService with the steps 6-7 bonuses (src/server/Bonuses.luau): enchant
-- damage and Overcharge, Reach, ore luck re-rolls (Hexa Lucky), Twin Drop and
-- the artifact roll hook (Prospector). Without bonuses nothing extra is rolled.
-- Same small fakes as tests/Mining.spec.luau.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local MiningService = Loader.requirePath("ServerScriptService.Server.Services.MiningService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")

	local mining = MiningService._test
	local TICK = BlasterData.Beam.ServerTick
	local NOW = 1_800_000_000

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function fakeRock(zoneId: string, oreIds: { string }, base: any, _seed: any): any
		local model = Instance.new("Model")
		model.Name = "Rock"
		local body = Instance.new("Part")
		body.Name = "Rock1"
		body.Size = Vector3.new(4, 3, 4)
		body.CFrame = base * CFrame.new(0, 1.5, 0)
		body.CanCollide = true
		body.Parent = model
		model.PrimaryPart = body
		model:SetAttribute("Zone", zoneId)
		model:SetAttribute("OreCount", #oreIds)
		return model
	end

	local function fakePlayer(w: any, userId: number): any
		local p: any = { UserId = userId, Name = "Miner" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.root = { Position = Vector3.new(6, 1.5, 0) }
		p.tool = {
			Name = "Blaster",
			IsA = function(_, className: string)
				return className == "Tool"
			end,
		}
		p.Character = {
			FindFirstChildOfClass = function(_, className: string)
				return if className == "Humanoid" then { Health = 100 } else nil
			end,
			FindFirstChild = function(_, name: string)
				if name == "HumanoidRootPart" then
					return p.root
				elseif name == "Blaster" then
					return p.tool
				end
				return nil
			end,
		}
		p.data = deepCopy(DataTemplate)
		w.byPlayer[p] = p.data
		return p
	end

	local function setup(): any
		local w: any = { spawned = {}, mined = {}, found = {}, now = 100, rolls = {}, calls = 0, byPlayer = {} }
		w.folder = Instance.new("Folder")
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return w.byPlayer[p]
		end)
		patch(DataService, "changed", function() end)
		patch(Net, "fire", function() end)
		patch(Net, "fireNear", function() end)
		patch(ItemService, "spawn", function(info, owner)
			table.insert(w.spawned, { Info = info, Owner = owner })
			return nil
		end)
		patch(OreNodeBuilder, "buildRock", fakeRock)
		patch(OreNodeBuilder, "applyStage", function()
			return {}
		end)
		mining.reset(w.folder)
		Bonuses._test.reset()
		Bonuses._test.setClock(function()
			return NOW
		end)
		mining.setClock(function()
			return w.now
		end)
		-- rolls are used in order; 0.5 when the list runs out
		mining.setRandom(function()
			w.calls += 1
			return if #w.rolls > 0 then table.remove(w.rolls, 1) else 0.5
		end)
		MiningService.onChunkMined(function(p, oreId)
			table.insert(w.mined, { Player = p, OreId = oreId })
		end)
		w.player = fakePlayer(w, 601)
		w.restore = function()
			mining.reset(nil)
			Bonuses._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		w.rock = function(zoneId: string, ores: { string }, health: number): any
			local marker = Instance.new("Part")
			marker.Size = Vector3.new(2, 2, 2)
			marker.CFrame = CFrame.new(0, 1, 0)
			marker:SetAttribute("Zone", zoneId)
			local rock = mining.spawnRock(marker)
			rock.Ores = ores
			rock.Health = health
			rock.MaxHealth = health
			return rock
		end
		w.step = function()
			w.now += TICK
			mining.tick(w.now)
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = setup()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function slot(p: any, owned: { [string]: number }, slots: { string }, level: number?)
		p.data.BlasterLevel = level or p.data.BlasterLevel
		p.data.Enchants = { Owned = owned, Slots = { slots[1] or "", slots[2] or "", slots[3] or "", slots[4] or "" } }
	end

	withWorld("Step67 Mining: Power multiplies the beam, Overcharge only in the last third", function(w)
		local p = w.player
		slot(p, { Power = 1, Overcharge = 1 }, { "Power", "Overcharge" }, 4)
		local rock = w.rock("Outcrops", { "Coal" }, 1e6)
		mining.blast(p, rock.Model)
		local dps = BlasterData.damage(4, "")
		w.step()
		T.near(rock.Health, 1e6 - dps * TICK * 1.1, 1e-6, "Power I: +10%")
		rock.Stage = 2 -- the last third
		local before = rock.Health
		w.step()
		T.near(before - rock.Health, dps * TICK * 1.1 * 1.25, 1e-6, "Overcharge I: +25% on top")
		-- the enchants only count in open slots: level 1 opens one
		p.data.BlasterLevel = 1
		before = rock.Health
		w.step()
		T.near(before - rock.Health, BlasterData.damage(1, "") * TICK * 1.1, 1e-6, "slot 2 closed")
	end)

	withWorld("Step67 Mining: Reach lets the beam hit from further away", function(w)
		local p = w.player
		p.root.Position = Vector3.new(30, 1.5, 0) -- 28 studs from the rock surface (range 22 + slack 4)
		local rock = w.rock("Outcrops", { "Coal" }, 1e6)
		mining.blast(p, rock.Model)
		w.step()
		T.eq(rock.Health, 1e6, "out of range")
		slot(p, { Reach = 3 }, { "Reach" })
		w.step()
		T.truthy(rock.Health < 1e6, "Reach III (+6 studs) reaches")
	end)

	withWorld("Step67 Mining: ore luck re-rolls a dropped ore with Rare+ weights x luck", function(w)
		local p = w.player
		-- no luck: the rock's own ore, and no extra roll
		local rock = w.rock("Quarry", { "Coal" }, 0.01)
		w.rolls = { 0.9999 }
		mining.blast(p, rock.Model)
		w.step()
		T.eq(#w.spawned, 1)
		T.eq(w.spawned[1].Info.OreId, "Coal", "no luck: the rolled ore stays")
		-- Hexa Lucky: the first roll of the drop re-picks from the quarry weights (Gold is last)
		p.data.Boosts.HexaLuckyUntil = NOW + 600
		w.spawned = {}
		local lucky = w.rock("Quarry", { "Coal" }, 0.01)
		w.rolls = { 0.9999 }
		mining.blast(p, lucky.Model)
		w.step()
		T.eq(#w.spawned, 1)
		T.eq(w.spawned[1].Info.OreId, "Gold", "re-rolled with luck")
		T.eq(w.mined[#w.mined].OreId, "Gold", "onChunkMined sees the real ore")
	end)

	withWorld("Step67 Mining: Twin Drop drops a second chunk of the same ore", function(w)
		local p = w.player
		slot(p, { TwinDrop = 3 }, { "TwinDrop" }) -- 15 %
		local rock = w.rock("Outcrops", { "Tin" }, 0.01)
		w.rolls = { 0.5, 0.5, 0.5, 0.5, 0.1 } -- 4 for the chunk's flight, then the twin roll
		mining.blast(p, rock.Model)
		w.step()
		T.eq(#w.spawned, 2, "a twin")
		T.eq(w.spawned[2].Info.OreId, "Tin")
		T.eq(p.data.Stats.OresMined, 2, "both counted")
		w.spawned = {}
		local other = w.rock("Outcrops", { "Tin" }, 0.01)
		w.rolls = { 0.5, 0.5, 0.5, 0.5, 0.2 }
		mining.blast(p, other.Model)
		w.step()
		T.eq(#w.spawned, 1, "no twin above the chance")
	end)

	withWorld("Step67 Mining: the artifact roll calls its listeners, Prospector raises the chance", function(w)
		local p = w.player
		-- no listener: no artifact roll at all
		local plain = w.rock("Quarry", { "Coal" }, 0.01)
		w.calls = 0
		mining.blast(p, plain.Model)
		w.step()
		local without = w.calls
		MiningService.onArtifactRoll(function(player, zoneId, position)
			table.insert(w.found, { Player = player, Zone = zoneId, Position = position })
		end)
		local chance = ArtifactConfig.rockChance("Quarry")
		local rock = w.rock("Quarry", { "Coal" }, 0.01)
		w.calls = 0
		w.rolls = { 0.5, 0.5, 0.5, 0.5, chance * 0.5 }
		mining.blast(p, rock.Model)
		w.step()
		T.eq(w.calls, without + 1, "exactly one extra roll per rock")
		T.eq(#w.found, 1, "found")
		T.eq(w.found[1].Player, p)
		T.eq(w.found[1].Zone, "Quarry")
		T.truthy(w.found[1].Position, "where the rock broke")
		local miss = w.rock("Quarry", { "Coal" }, 0.01)
		w.rolls = { 0.5, 0.5, 0.5, 0.5, chance * 1.5 }
		mining.blast(p, miss.Model)
		w.step()
		T.eq(#w.found, 1, "above the chance: nothing")
		slot(p, { Prospector = 3 }, { "Prospector" }) -- +100 %
		local lucky = w.rock("Quarry", { "Coal" }, 0.01)
		w.rolls = { 0.5, 0.5, 0.5, 0.5, chance * 1.5 }
		mining.blast(p, lucky.Model)
		w.step()
		T.eq(#w.found, 2, "Prospector III doubles the chance")
	end)
end
