-- Machine rules and In/Out queues, plus a conservation fuzz test: no item
-- ever appears or disappears, whatever order things happen in.
return function(T, Loader)
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")

	local MAX_IN = GameConfig.MachineIntakeQueue
	local MAX_OUT = MachineData.MaxOutBuffer

	local function entry(id: string): any
		return { Id = id, X = 0, Z = 0, R = 0 }
	end
	local function clean(ore: string, grade: string?): any
		return { K = "Clean", O = ore, G = grade or "Rough" }
	end
	local function ingot(ore: string, grade: string?): any
		return { K = "Ingot", O = ore, G = grade }
	end

	T.test("MachineLogic: isValidDesc", function()
		T.truthy(MachineLogic.isValidDesc({ K = "Raw", O = "Copper" }))
		T.truthy(MachineLogic.isValidDesc({ K = "Clean", O = "Gold", G = "Flawless" }))
		T.truthy(MachineLogic.isValidDesc({ K = "Gear", O = "Iron", G = "Rough", R = "Helm" }))
		T.falsy(MachineLogic.isValidDesc(nil))
		T.falsy(MachineLogic.isValidDesc("Raw|Copper||"))
		T.falsy(MachineLogic.isValidDesc({ K = "Rock", O = "Copper" }), "unknown kind")
		T.falsy(MachineLogic.isValidDesc({ K = "Raw", O = "Plastic" }), "unknown ore")
		T.falsy(MachineLogic.isValidDesc({ K = "Clean", O = "Copper", G = "Shiny" }), "unknown grade")
		T.falsy(MachineLogic.isValidDesc({ K = "Clean", O = "Copper", G = 3 }), "grade not a string")
		T.falsy(MachineLogic.isValidDesc({ K = "Gear", O = "Copper", G = "Rough" }), "gear without recipe")
		T.falsy(MachineLogic.isValidDesc({ K = "Gear", O = "Copper", R = "Spoon" }), "unknown recipe")
		T.falsy(MachineLogic.isValidDesc({ K = "Ingot", O = "Copper", R = "Dagger" }), "recipe on an ingot")
	end)

	T.test("MachineLogic: queue sizes", function()
		for _, id in { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner", "Anvil" } do
			T.eq(MachineLogic.queueSize(id), MAX_IN, id)
		end
		for _, id in { "StorageCrate", "SellChute", "CleaningStation", "Conveyor", "Nope" } do
			T.eq(MachineLogic.queueSize(id), 0, id)
		end
	end)

	T.test("MachineLogic: accept rules per machine", function()
		local raw = { K = "Raw", O = "Copper" }
		local crushed = { K = "Crushed", O = "Copper", G = "Rough" }
		for _, id in { "ClayFurnace", "BlastFurnace" } do
			local furnace = entry(id)
			T.eq(select(2, MachineLogic.accepts(id, raw, furnace, true)), "Wrong", id .. " raw")
			T.truthy(MachineLogic.accepts(id, clean("Copper"), furnace, true), id .. " clean")
			T.truthy(MachineLogic.accepts(id, crushed, furnace, true), id .. " crushed")
			T.eq(select(2, MachineLogic.accepts(id, ingot("Copper"), furnace, true)), "Wrong", id .. " ingot")
			for _ = 1, MAX_IN do
				MachineLogic.push(furnace, clean("Copper"))
			end
			T.eq(select(2, MachineLogic.accepts(id, clean("Copper"), furnace, true)), "Full", id .. " 5th item")
		end
		T.truthy(MachineLogic.accepts("Crusher", clean("Iron"), entry("Crusher"), true))
		T.eq(select(2, MachineLogic.accepts("Crusher", crushed, entry("Crusher"), true)), "Wrong", "crusher crushed")
		T.eq(select(2, MachineLogic.accepts("Crusher", raw, entry("Crusher"), true)), "Wrong", "crusher raw")
		T.truthy(MachineLogic.accepts("AutoCleaner", raw, entry("AutoCleaner"), true))
		T.eq(select(2, MachineLogic.accepts("AutoCleaner", clean("Copper"), entry("AutoCleaner"), true)), "Wrong")
		-- anvil: ingots of one ore
		local anvil = entry("Anvil")
		T.eq(select(2, MachineLogic.accepts("Anvil", clean("Copper"), anvil, true)), "Wrong", "anvil clean")
		T.truthy(MachineLogic.accepts("Anvil", ingot("Copper"), anvil, true))
		MachineLogic.push(anvil, ingot("Copper"))
		T.eq(select(2, MachineLogic.accepts("Anvil", ingot("Iron"), anvil, true)), "Mixed", "mixed ingots")
		T.truthy(MachineLogic.accepts("Anvil", ingot("Copper", "Flawless"), anvil, true), "other grades are fine")
		for _ = 2, MAX_IN do
			MachineLogic.push(anvil, ingot("Copper"))
		end
		T.eq(select(2, MachineLogic.accepts("Anvil", ingot("Copper"), anvil, true)), "Full", "anvil full")
		-- foreign items are refused everywhere except the Sell Chute
		for _, machine in MachineData.List do
			local ok, reason = MachineLogic.accepts(machine.Id, clean("Copper"), entry(machine.Id), false)
			if machine.Id == "SellChute" then
				T.truthy(ok, "chute takes foreign items")
			else
				T.falsy(ok, machine.Id .. " foreign")
				T.eq(reason, "Foreign", machine.Id .. " foreign reason")
			end
		end
		-- sell chute takes anything valid, refuses junk
		for _, kind in { "Raw", "Clean", "Crushed", "Ingot" } do
			T.truthy(MachineLogic.accepts("SellChute", { K = kind, O = "Silver", G = "Clean" }, entry("SellChute"), false), "chute " .. kind)
		end
		T.truthy(MachineLogic.accepts("SellChute", { K = "Gear", O = "Silver", G = "Clean", R = "Dagger" }, entry("SellChute"), true))
		T.eq(select(2, MachineLogic.accepts("SellChute", { K = "Gear", O = "Silver" }, entry("SellChute"), true)), "Wrong")
		-- crate: anything valid from the owner (capacity is the service's job)
		T.truthy(MachineLogic.accepts("StorageCrate", raw, entry("StorageCrate"), true))
		T.eq(select(2, MachineLogic.accepts("StorageCrate", { K = "Raw", O = "Nope" }, entry("StorageCrate"), true)), "Wrong")
		-- station and belts never take items this way
		T.eq(select(2, MachineLogic.accepts("CleaningStation", raw, entry("CleaningStation"), true)), "Wrong")
		T.eq(select(2, MachineLogic.accepts("Conveyor", raw, entry("Conveyor"), true)), "Wrong")
		T.eq(select(2, MachineLogic.accepts("Nope", raw, entry("Nope"), true)), "Wrong")
	end)

	T.test("MachineLogic: outputs per machine", function()
		local crushed = MachineLogic.outputs("Crusher", clean("Gold", "Pristine"), 0.5)
		T.eq(#crushed, 2, "crusher makes 2")
		for _, d in crushed do
			T.eq(d.K, "Crushed")
			T.eq(d.O, "Gold")
			T.eq(d.G, "Pristine", "same grade")
		end
		T.truthy(crushed[1] ~= crushed[2], "separate tables")
		for _, id in { "ClayFurnace", "BlastFurnace" } do
			local out = MachineLogic.outputs(id, clean("Iron", "Flawless"), 0.5)
			T.eq(#out, 1)
			T.eq(out[1].K, "Ingot")
			T.eq(out[1].O, "Iron")
			T.eq(out[1].G, "Flawless", id .. " keeps the grade")
			out = MachineLogic.outputs(id, { K = "Crushed", O = "Iron" }, 0.5)
			T.eq(out[1].G, "Rough", id .. " nil grade becomes Rough")
		end
		local cleaned = MachineLogic.outputs("AutoCleaner", { K = "Raw", O = "Copper" }, 0.1)
		T.eq(#cleaned, 1)
		T.eq(cleaned[1].K, "Clean")
		T.eq(cleaned[1].G, "Rough")
		T.eq(MachineLogic.outputs("AutoCleaner", { K = "Raw", O = "Copper" }, 0.99)[1].G, "Clean")
		T.eq(#MachineLogic.outputs("StorageCrate", clean("Copper"), 0.5), 0)
		T.eq(#MachineLogic.outputs("Anvil", ingot("Copper"), 0.5), 0)
	end)

	T.test("MachineLogic: Auto Cleaner gives 60% Rough / 40% Clean over 10,000 rolls", function()
		local rng = Rng.new(2024)
		local counts = {}
		local n = 10000
		for _ = 1, n do
			local out = MachineLogic.outputs("AutoCleaner", { K = "Raw", O = "Emberite" }, rng:next())
			counts[out[1].G] = (counts[out[1].G] or 0) + 1
		end
		for grade in counts do
			T.truthy(grade == "Rough" or grade == "Clean", "unexpected grade " .. grade)
		end
		T.near((counts.Rough or 0) / n, 0.6, 0.03, "Rough share")
		T.near((counts.Clean or 0) / n, 0.4, 0.03, "Clean share")
	end)

	T.test("MachineLogic: rollGrade never goes above the max grade", function()
		local chances = { Rough = 0.2, Clean = 0.3, Pristine = 0.5 }
		for i = 0, 99 do
			local g = MachineLogic.rollGrade(chances, "Clean", i / 100)
			T.truthy(g == "Rough" or g == "Clean", g)
		end
		T.eq(MachineLogic.rollGrade(chances, "Flawless", 0.99), "Pristine")
		T.eq(MachineLogic.rollGrade(chances, "Flawless", 0), "Rough")
		T.eq(MachineLogic.rollGrade({}, "Clean", 0.5), "Rough", "no odds")
		T.eq(MachineLogic.rollGrade(chances, "Flawless", 0 / 0), "Rough", "NaN roll")
	end)

	T.test("MachineLogic: queues stay small and empty ones become nil", function()
		local e = entry("ClayFurnace")
		T.eq(MachineLogic.popOut(e), nil)
		MachineLogic.push(e, clean("Copper"))
		MachineLogic.push(e, clean("Iron"))
		T.eq(#e.In, 2)
		MachineLogic.complete(e, MachineLogic.outputs("ClayFurnace", e.In[1], 0))
		T.eq(#e.In, 1)
		T.eq(e.In[1].O, "Iron", "FIFO")
		T.eq(#e.Out, 1)
		MachineLogic.complete(e, MachineLogic.outputs("ClayFurnace", e.In[1], 0))
		T.eq(e.In, nil, "empty In is nil")
		local first = MachineLogic.popOut(e)
		T.eq(first.O, "Copper")
		T.eq(MachineLogic.popOut(e).O, "Iron")
		T.eq(e.Out, nil, "empty Out is nil")
		MachineLogic.push(e, clean("Gold"))
		e.Out = { ingot("Silver") }
		local drained = MachineLogic.drain(e)
		T.eq(#drained, 2)
		T.eq(drained[1].O, "Gold", "In first")
		T.eq(drained[2].O, "Silver", "then Out")
		T.eq(e.In, nil)
		T.eq(e.Out, nil)
		T.eq(#MachineLogic.drain(e), 0)
	end)

	T.test("MachineLogic: recipe options and forging", function()
		local function ids(list: { string }): string
			return table.concat(list, ",")
		end
		T.eq(ids(MachineLogic.recipeOptions(0)), "")
		T.eq(ids(MachineLogic.recipeOptions(1)), "Dagger")
		T.eq(ids(MachineLogic.recipeOptions(2)), "Dagger,ToolHead")
		T.eq(ids(MachineLogic.recipeOptions(3)), "Dagger,ToolHead,Helm")
		T.eq(ids(MachineLogic.recipeOptions(4)), "Dagger,ToolHead,Helm,Greatsword")
		local anvil = entry("Anvil")
		MachineLogic.push(anvil, ingot("Copper", "Flawless"))
		MachineLogic.push(anvil, ingot("Copper", "Clean"))
		MachineLogic.push(anvil, ingot("Copper", "Rough"))
		local gear, used = MachineLogic.forge(anvil, "ToolHead")
		T.eq(used, 2)
		T.eq(gear.K, "Gear")
		T.eq(gear.O, "Copper")
		T.eq(gear.R, "ToolHead")
		T.eq(gear.G, "Clean", "lowest of the first two")
		T.eq(#anvil.In, 1, "one ingot left")
		T.eq(anvil.In[1].G, "Rough", "the first N were used")
		local none, zero = MachineLogic.forge(anvil, "Helm")
		T.eq(none, nil, "not enough ingots")
		T.eq(zero, 0)
		T.eq(#anvil.In, 1, "nothing changed")
		T.eq(MachineLogic.forge(anvil, "Spoon"), nil, "unknown recipe")
		gear = MachineLogic.forge(anvil, "Dagger")
		T.eq(gear.G, "Rough")
		T.eq(anvil.In, nil)
		-- an ingot without a grade counts as Rough
		MachineLogic.push(anvil, ingot("Iron", nil))
		T.eq(MachineLogic.forge(anvil, "Dagger").G, "Rough")
		T.truthy(MachineLogic.isValidDesc(gear), "gear is a valid item")
		T.truthy(ItemData.value(gear.K, gear.O, gear.G, gear.R) > 0, "gear has a value")
	end)

	T.test("MachineLogic: validateStrikes", function()
		local gap = GameConfig.AnvilMinStrikeGap
		local per = GameConfig.AnvilMinSecondsPerHit
		T.truthy(MachineLogic.validateStrikes({ 0.5, 1.0, 1.5, 2.0 }, 4, 3), "normal hammering")
		T.truthy(MachineLogic.validateStrikes({ 0.3, 0.6, 0.9 + 1e-9 }, 3, 0.95), "fast but human")
		local function bad(strikes: any, hits: number, elapsed: number, label: string)
			local ok, why = MachineLogic.validateStrikes(strikes, hits, elapsed)
			T.falsy(ok, label)
			T.truthy(type(why) == "string", label .. " gives a reason")
		end
		bad({ 0.5, 1.0, 1.5 }, 4, 3, "too few")
		bad({ 0.5, 1.0, 1.5, 2.0, 2.5 }, 4, 3, "too many")
		bad({ 0.5, 0 / 0, 1.5, 2.0 }, 4, 3, "NaN")
		bad({ 0.5, 1.0, 1.5, math.huge }, 4, 3, "inf")
		bad({ 0.5, 1.0, "1.5", 2.0 }, 4, 3, "string")
		bad({ 0.5, 1.0, 1.0, 2.0 }, 4, 3, "not strictly increasing")
		bad({ 0.5, 1.5, 1.0, 2.0 }, 4, 3, "going back")
		bad({ 0.5, 0.5 + gap - 0.01, 1.5, 2.0 }, 4, 3, "gap under the minimum")
		bad({ 0.0, 0.2, 0.4, 0.6 }, 4, 3, "under Hits x " .. per)
		bad({ 0.5, 1.0, 1.5, 4.5 }, 4, 3, "after elapsed + 1")
		bad({ -0.1, 1.0, 1.5, 2.0 }, 4, 3, "negative time")
		bad({ 0.5, 1.0, 1.5, 2.0, Extra = 1 }, 4, 3, "extra keys")
		bad({ [1] = 0.5, [2] = 1.0, [4] = 2.0, [5] = 2.5 }, 4, 3, "holes")
		bad(nil, 4, 3, "nil")
		bad({ 0.5 }, 0, 3, "zero hits")
		bad({ 0.5, 1.0, 1.5, 2.0 }, 4, 0 / 0, "NaN elapsed")
		-- every recipe can be hammered by a person at the minimum pace
		for _, recipe in ItemData.Recipes do
			local strikes = {}
			for i = 1, recipe.Hits do
				strikes[i] = i * math.max(gap, per) + 0.01
			end
			T.truthy(MachineLogic.validateStrikes(strikes, recipe.Hits, strikes[recipe.Hits]), recipe.Id .. " is doable")
		end
	end)

	T.test("MachineLogic: CONSERVATION FUZZ (20,000 random steps)", function()
		local rng = Rng.new(31337)
		local kinds = { "Raw", "Clean", "Crushed", "Ingot", "Gear" }
		local ores = { "Copper", "Iron", "Gold", "Copper", "Iron", "Plastic" }
		local grades = { "Rough", "Clean", "Pristine", "Flawless", "Rough" }
		local recipeIds = { "Dagger", "ToolHead", "Helm", "Greatsword", "Spoon" }

		local function randomDesc(): any
			local kind = rng:pick(kinds)
			local desc: any = { K = kind, O = rng:pick(ores) }
			if kind ~= "Raw" and rng:chance(0.9) then
				desc.G = rng:pick(grades)
			end
			if kind == "Gear" and rng:chance(0.8) then
				desc.R = rng:pick(recipeIds)
			end
			return desc
		end

		type Ledger = { [string]: { [string]: number } }
		local machines = {}
		for _, id in { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner", "Anvil", "ClayFurnace", "Anvil" } do
			table.insert(machines, {
				Entry = entry(id),
				Info = MachineData.ById[id],
				-- per ore: items pushed, inputs consumed, outputs produced, and where they went
				L = { Pushed = {}, Consumed = {}, Produced = {}, Popped = {}, DrainedIn = {}, DrainedOut = {} } :: Ledger,
			})
		end
		local function add(map: { [string]: number }, ore: string, n: number)
			map[ore] = (map[ore] or 0) + n
		end
		local function countIn(list: { any }?, ore: string): number
			local n = 0
			if list then
				for _, d in list do
					if d.O == ore then
						n += 1
					end
				end
			end
			return n
		end

		local stats = { push = 0, refused = 0, complete = 0, blocked = 0, pop = 0, drain = 0, forge = 0 }
		for step = 1, 20000 do
			local m = rng:pick(machines)
			local e = m.Entry
			local id = e.Id
			local op = rng:int(1, 10)
			if op <= 5 then
				local desc = randomDesc()
				local before = if e.In then #e.In else 0
				local ok, reason = MachineLogic.accepts(id, desc, e, rng:chance(0.9))
				if ok then
					T.truthy(m.Info.Accepts[desc.K], `step {step}: {id} took a {desc.K}`)
					T.lt(before, MAX_IN, `step {step}: accepted into a full queue`)
					MachineLogic.push(e, desc)
					add(m.L.Pushed, desc.O, 1)
					stats.push += 1
				else
					T.truthy(reason == "Wrong" or reason == "Foreign" or reason == "Mixed" or reason == "Full", "reason " .. tostring(reason))
					stats.refused += 1
				end
			elseif op <= 7 and id ~= "Anvil" then
				if e.In then
					local input = e.In[1]
					local outputs = MachineLogic.outputs(id, input, rng:next())
					T.eq(#outputs, m.Info.OutputCount, `step {step}: output count`)
					local outCount = if e.Out then #e.Out else 0
					if outCount + #outputs <= MAX_OUT then
						for _, d in outputs do
							T.eq(d.K, m.Info.Output, "output kind")
							T.eq(d.O, input.O, "output ore")
							if m.Info.GradeChances then
								T.truthy(d.G == "Rough" or d.G == "Clean", "auto-cleaned grade")
							else
								T.eq(d.G, input.G or "Rough", "grade kept")
							end
						end
						MachineLogic.complete(e, outputs)
						add(m.L.Consumed, input.O, 1)
						add(m.L.Produced, input.O, #outputs)
						stats.complete += 1
					else
						stats.blocked += 1
					end
				end
			elseif op <= 7 then
				local options = MachineLogic.recipeOptions(if e.In then #e.In else 0)
				local recipeId = if #options > 0 and rng:chance(0.9) then rng:pick(options) else rng:pick(recipeIds)
				local firstOre = if e.In then e.In[1].O else nil
				local gear, used = MachineLogic.forge(e, recipeId)
				if gear then
					local recipe = ItemData.RecipeById[recipeId]
					T.eq(used, recipe.Ingots, "ingots used")
					T.eq(gear.O, firstOre, "gear ore")
					T.eq(gear.R, recipeId, "gear recipe")
					add(m.L.Consumed, gear.O, used)
					stats.forge += 1
				else
					T.eq(used, 0, "failed forge uses nothing")
				end
			elseif op <= 9 then
				local d = MachineLogic.popOut(e)
				if d then
					add(m.L.Popped, d.O, 1)
					stats.pop += 1
				end
			elseif rng:chance(0.15) then
				local nIn = if e.In then #e.In else 0
				local list = MachineLogic.drain(e)
				for i, d in list do
					add(if i <= nIn then m.L.DrainedIn else m.L.DrainedOut, d.O, 1)
				end
				stats.drain += 1
			end

			-- invariants after every step, on every machine
			for _, other in machines do
				local oe = other.Entry
				T.truthy(oe.In == nil or #oe.In > 0, `step {step}: empty In table left behind`)
				T.truthy(oe.Out == nil or #oe.Out > 0, `step {step}: empty Out table left behind`)
				T.le(if oe.In then #oe.In else 0, MAX_IN, `step {step}: In too long`)
				T.le(if oe.Out then #oe.Out else 0, MAX_OUT, `step {step}: Out too long`)
				local L = other.L
				local seen = {}
				for _, map in L do
					for ore in map do
						seen[ore] = true
					end
				end
				for ore in seen do
					local pushed = L.Pushed[ore] or 0
					local consumed = L.Consumed[ore] or 0
					local produced = L.Produced[ore] or 0
					T.eq(pushed, countIn(oe.In, ore) + consumed + (L.DrainedIn[ore] or 0), `step {step}: {oe.Id} {ore} inputs`)
					T.eq(produced, countIn(oe.Out, ore) + (L.Popped[ore] or 0) + (L.DrainedOut[ore] or 0), `step {step}: {oe.Id} {ore} outputs`)
					if oe.Id ~= "Anvil" then
						T.eq(produced, consumed * (other.Info.OutputCount or 1), `step {step}: {oe.Id} {ore} ratio`)
					end
				end
			end
		end
		for name, n in stats do
			T.truthy(n > 100, `fuzz exercised {name} ({n})`)
		end
	end)
end
