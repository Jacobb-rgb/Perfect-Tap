--[[
	The STAR blasters (Config/StarBlasterData, the owner's picks 2026-10-20)
	under Lune: the five weapons and their passes, the rules (open at a
	rebirth count, bought once for stars or Robux, equipped, power A), the
	save (kept by every rebirth, Migrations keeps a newer build's ids), the
	service (RebirthAction "Weapon" / "Equip", the "RebirthWeapon" pass
	grant and refund), the held tool and the BLASTERS page of the window.
]]
return function(T, Loader)
	local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local RebirthService = Loader.requirePath("ServerScriptService.Server.Services.RebirthService")
	local MonetizationService = Loader.requirePath("ServerScriptService.Server.Services.MonetizationService")
	local RebirthView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RebirthView")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")

	local function fresh(): { [string]: any }
		local data = ProfileStore.deepCopy(DataTemplate)
		Migrations.run(data)
		return data
	end

	T.test("StarBlasters: five weapons, the owner's prices, a pass each", function()
		local list = StarBlasterData.List
		T.eq(#list, 5)
		local unlocks, robux, stars = { 1, 2, 3, 5, 8 }, { 75, 125, 199, 299, 449 }, { 20, 30, 45, 65, 90 }
		local seen = {}
		for i, star in list do
			T.falsy(seen[star.Id], "unique id " .. star.Id)
			seen[star.Id] = true
			T.eq(StarBlasterData.ById[star.Id], star)
			T.eq(star.Index, i, "Kenney shape 10 + " .. i)
			T.eq(star.Unlock, unlocks[i], star.Id .. " opens at its rebirth")
			T.eq(star.Robux, robux[i], star.Id .. " R$")
			T.eq(star.Stars, stars[i], star.Id .. " stars")
			T.truthy(star.Mult >= 1.2 - 1e-9 and star.Mult <= 1.8 + 1e-9, star.Id .. " power A: x1.2 .. x1.8")
			if i > 1 then
				T.truthy(star.Mult > list[i - 1].Mult, "each one hits harder than the one before")
			end
			-- its one-time game pass
			local entry = MonetizationConfig.get("Star" .. star.Id)
			T.truthy(entry, "pass Star" .. star.Id)
			T.eq(entry.Kind, "GamePass")
			T.eq(entry.Grant, "RebirthWeapon")
			T.eq(entry.WeaponId, star.Id)
			T.eq(entry.Robux, star.Robux, "the pass price is the weapon's")
			T.falsy(entry.PaidRandom, "nothing random")
			T.falsy(entry.CoinPack, "never coins")
		end
	end)

	T.test("StarBlasters: open at a rebirth count, bought once, equipped, power A", function()
		local data = fresh()
		T.eq(data.StarBlaster, "")
		T.eq(StarBlasterData.equipped(data), nil)
		T.eq(StarBlasterData.mult(data), 1, "the forged blaster")
		T.eq(select(2, StarBlasterData.quote(data, "Comet")), "Locked", "no rebirth yet")
		T.eq(StarBlasterData.cardState(data, "Comet"), "Locked")
		data.Rebirths = 1
		T.eq(select(2, StarBlasterData.quote(data, "Comet")), "NoStars")
		T.eq(StarBlasterData.cardState(data, "Comet"), "Buy")
		T.eq(select(2, StarBlasterData.quote(data, "Nebula")), "Locked", "Nebula opens at rebirth 2")
		data.Stars = 25
		local cost, why = StarBlasterData.quote(data, "Comet")
		T.eq(cost, 20)
		T.eq(why, nil)
		StarBlasterData.buy(data, "Comet")
		T.eq(data.Stars, 5)
		T.eq(data.RebirthWeapons.Comet, true)
		T.eq(data.StarBlaster, "Comet", "equipped at once")
		T.eq(StarBlasterData.equipped(data), StarBlasterData.ById.Comet)
		T.eq(StarBlasterData.mult(data), 1.2)
		T.eq(StarBlasterData.cardState(data, "Comet"), "Equipped")
		T.eq(select(2, StarBlasterData.quote(data, "Comet")), "Owned", "never twice")
		-- power A: the forged level's damage times Mult (the level gates stay the forged level's)
		data.BlasterLevel = 6
		T.near(BlasterData.damage(6, "") * StarBlasterData.mult(data), BlasterData.damage(6, "") * 1.2, 1e-9)
		-- an id that isn't equipped, owned or open is never fought with
		data.StarBlaster = "Nebula"
		T.eq(StarBlasterData.equipped(data), nil, "not owned")
		data.RebirthWeapons.Nebula = true -- a pass bought on the game page before rebirth 2
		T.eq(StarBlasterData.equipped(data), nil, "owned but closed")
		T.eq(StarBlasterData.cardState(data, "Nebula"), "Waiting")
		data.Rebirths = 2
		T.eq(StarBlasterData.equipped(data), StarBlasterData.ById.Nebula, "open now")
		T.eq(StarBlasterData.cardState(data, "Comet"), "Owned")
		for _, junk in { 5, {}, "Nope", string.rep("x", 80) } do
			data.StarBlaster = junk
			T.eq(StarBlasterData.equipped(data), nil, "junk")
			T.eq(StarBlasterData.mult(data), 1)
		end
		T.eq(select(2, StarBlasterData.quote(data, "Nope")), "BadWeapon")
		T.eq(StarBlasterData.mult(nil), 1)
	end)

	T.test("StarBlasters: every rebirth keeps them; Migrations keeps a newer build's ids", function()
		local data = fresh()
		data.BlasterLevel = BlasterData.MaxLevel
		data.Rebirths = 3
		data.Stats.RunForged = BlasterData.MaxLevel
		data.RebirthWeapons = { Comet = true, Pulsar = true }
		data.RebirthWeaponPasses = { Pulsar = true }
		data.StarBlaster = "Pulsar"
		local before = ProfileStore.deepCopy(data)
		T.truthy(RebirthConfig.canRebirth(data))
		RebirthConfig.reset(data)
		T.eq(data.Rebirths, 4)
		for _, key in { "RebirthWeapons", "RebirthWeaponPasses", "StarBlaster" } do
			T.eq(type(data[key]), type(before[key]), key)
		end
		T.eq(data.RebirthWeapons.Comet, true, "a star-bought weapon is kept")
		T.eq(data.RebirthWeapons.Pulsar, true, "a pass weapon is kept")
		T.eq(data.RebirthWeaponPasses.Pulsar, true)
		T.eq(data.StarBlaster, "Pulsar", "still equipped")
		T.eq(StarBlasterData.equipped(data), StarBlasterData.ById.Pulsar, "in hand after the rebirth")
		T.eq(data.BlasterLevel, 1, "the forged blaster still starts over: the run isn't skipped")
		-- Migrations: a newer build's weapon stays, junk goes
		data.RebirthWeapons.Quasar = true
		data.RebirthWeapons[5] = true
		data.RebirthWeapons.Bad = "yes"
		data.RebirthWeaponPasses[string.rep("x", 90)] = true
		data.StarBlaster = "Quasar"
		local report = Migrations.run(data)
		T.eq(data.RebirthWeapons.Quasar, true, "unknown short ids are kept")
		T.eq(data.RebirthWeapons[5], nil)
		T.eq(data.RebirthWeapons.Bad, nil)
		T.eq(report.Dropped, 3)
		T.eq(data.StarBlaster, "Quasar", "a newer build's pick stays")
		T.eq(StarBlasterData.equipped(data), nil, "but this build fights with the forged one")
		data.StarBlaster = 7
		data.RebirthWeapons = "junk"
		Migrations.run(data)
		T.eq(data.StarBlaster, "")
		T.eq(type(data.RebirthWeapons), "table")
		-- an old save without the fields
		local old = fresh()
		old.RebirthWeapons, old.RebirthWeaponPasses, old.StarBlaster = nil, nil, nil
		Migrations.run(old)
		T.eq(type(old.RebirthWeapons), "table")
		T.eq(type(old.RebirthWeaponPasses), "table")
		T.eq(old.StarBlaster, "")
	end)

	---------------------------------------------------------------- the service

	local function world(): any
		local w: any = { results = {}, notes = {}, changed = 0 }
		w.data = fresh()
		w.player = { UserId = 5501, Name = "Starry", Parent = true }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a)
			if p == w.player and name == "RebirthResult" then
				table.insert(w.results, a)
			elseif p == w.player and name == "Notify" then
				table.insert(w.notes, a.Text)
			end
		end)
		w.restore = function()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = world()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	withWorld("StarBlasters: RebirthAction Weapon / Equip", function(w)
		local action = RebirthService._test.action
		local function last(): any
			return w.results[#w.results]
		end
		action(w.player, { Action = "Weapon", Id = "Comet" })
		T.eq(last().Reason, "Locked", "no rebirth yet")
		w.data.Rebirths = 1
		action(w.player, { Action = "Weapon", Id = "Comet" })
		T.eq(last().Reason, "NoStars")
		w.data.Stars = 21
		action(w.player, { Action = "Weapon", Id = "Comet" })
		T.truthy(last().Ok)
		T.eq(last().Id, "Comet")
		T.eq(w.data.Stars, 1)
		T.eq(w.data.StarBlaster, "Comet")
		action(w.player, { Action = "Weapon", Id = "Comet" })
		T.eq(last().Reason, "Owned")
		T.eq(w.data.Stars, 1, "never paid twice")
		action(w.player, { Action = "Equip", Id = "" })
		T.truthy(last().Ok, "back to the forged blaster")
		T.eq(w.data.StarBlaster, "")
		action(w.player, { Action = "Equip", Id = "Nebula" })
		T.eq(last().Reason, "Locked", "not owned")
		action(w.player, { Action = "Equip", Id = "Comet" })
		T.truthy(last().Ok)
		T.eq(w.data.StarBlaster, "Comet")
		-- junk
		for _, id in { 5, {}, "Nope", string.rep("C", 40) } do
			action(w.player, { Action = "Equip", Id = id })
			T.falsy(last().Ok, "junk equip")
			action(w.player, { Action = "Weapon", Id = id })
			T.falsy(last().Ok, "junk buy")
		end
		T.eq(w.data.StarBlaster, "Comet", "junk changes nothing")
		T.eq(w.data.Stars, 1)
		-- the snapshot
		local snap = RebirthService.snapshot(w.data)
		T.eq(snap.Weapons.Comet, true)
		T.eq(snap.Weapons.Nebula, nil)
		T.eq(snap.Weapon, "Comet")
	end)

	withWorld("StarBlasters: the RebirthWeapon pass: kept forever, a refund takes back only what it gave", function(w)
		local grant, revoke = RebirthService._test.grantWeapon, RebirthService._test.revokeWeapon
		local nebula = MonetizationConfig.get("StarNebula")
		-- bought on the game page before rebirth 2: owned, waiting, not equipped
		w.data.Rebirths = 1
		T.truthy(grant(w.player, w.data, nebula))
		T.eq(w.data.RebirthWeapons.Nebula, true)
		T.eq(w.data.RebirthWeaponPasses.Nebula, true)
		T.eq(w.data.StarBlaster, "", "closed: not equipped")
		T.truthy(string.find(w.notes[#w.notes], "rebirth 2", 1, true), "it says when it opens")
		T.falsy(grant(w.player, w.data, nebula), "the check on the next load changes nothing")
		T.eq(#w.notes, 1, "and says nothing")
		-- open now: a fresh grant equips it when nothing else is in hand
		local comet = MonetizationConfig.get("StarComet")
		T.truthy(grant(w.player, w.data, comet))
		T.eq(w.data.StarBlaster, "Comet")
		T.truthy(string.find(w.notes[#w.notes], "equipped", 1, true), "it says it is equipped already")
		-- a live pass not checked yet: no stars are spent on it ("Checking")
		w.data.Rebirths = 3
		w.data.Stars = 50
		local pulsar = MonetizationConfig.get("StarPulsar")
		local knownNow = false
		local roundDone = false
		local oldId, oldKnown, oldChecked = pulsar.Id, rawget(MonetizationService, "known"), rawget(MonetizationService, "passesChecked")
		pulsar.Id = 4242
		rawset(MonetizationService, "known", function(p, key)
			return p == w.player and key == "StarPulsar" and knownNow
		end)
		rawset(MonetizationService, "passesChecked", function(p)
			return p == w.player and roundDone
		end)
		local ok, err = pcall(function()
			RebirthService._test.action(w.player, { Action = "Weapon", Id = "Pulsar" })
			T.eq(w.results[#w.results].Reason, "Checking")
			T.eq(w.data.Stars, 50, "nothing spent")
			-- the first round is over but this pass's check kept failing: never "Checking" all session
			roundDone = true
			local before = { Stars = w.data.Stars, StarBlaster = w.data.StarBlaster }
			T.truthy(RebirthService.buyWeapon(w.player, "Pulsar"), "not blocked once the first round is done")
			w.data.RebirthWeapons.Pulsar = nil -- (undone: the answered check below buys it again)
			w.data.Stars, w.data.StarBlaster = before.Stars, before.StarBlaster
			roundDone = false
			knownNow = true
			RebirthService._test.action(w.player, { Action = "Weapon", Id = "Pulsar" })
			T.truthy(w.results[#w.results].Ok, "the check answered: stars work")
		end)
		pulsar.Id = oldId
		rawset(MonetizationService, "known", oldKnown)
		rawset(MonetizationService, "passesChecked", oldChecked)
		if not ok then
			error(err, 0)
		end
		T.eq(w.data.Stars, 5)
		-- bought with stars AND the pass: the stars go back once, the pass holds it from then on
		T.truthy(grant(w.player, w.data, pulsar), "the stars come back")
		T.eq(w.data.Stars, 50)
		T.eq(w.data.RebirthWeaponPasses.Pulsar, true)
		T.truthy(string.find(w.notes[#w.notes], "45", 1, true), "it says so")
		T.falsy(grant(w.player, w.data, pulsar), "only once")
		T.eq(w.data.Stars, 50)
		T.eq(w.data.RebirthWeapons.Pulsar, true)
		T.eq(w.data.StarBlaster, "Pulsar")
		-- a weapon bought with stars only is never taken by a refund
		w.data.Rebirths = 5
		w.data.Stars = 100
		RebirthService._test.action(w.player, { Action = "Weapon", Id = "Supernova" })
		T.truthy(w.results[#w.results].Ok)
		T.falsy(revoke(w.player, w.data, MonetizationConfig.get("StarSupernova")), "a refund of that pass takes nothing")
		T.eq(w.data.RebirthWeapons.Supernova, true)
		-- a refund takes back the pass weapon (unequipped if in hand)
		RebirthService._test.action(w.player, { Action = "Equip", Id = "Nebula" })
		T.eq(w.data.StarBlaster, "Nebula")
		T.truthy(revoke(w.player, w.data, nebula))
		T.eq(w.data.RebirthWeapons.Nebula, nil)
		T.eq(w.data.RebirthWeaponPasses.Nebula, nil)
		T.eq(w.data.StarBlaster, "", "back to the forged blaster")
		T.falsy(revoke(w.player, w.data, nebula), "twice: nothing")
		T.eq(w.data.RebirthWeapons.Comet, true, "the other pass weapon stays")
		-- junk entries
		T.falsy(grant(w.player, w.data, { Key = "X", WeaponId = "Nope" }))
		T.falsy(revoke(w.player, w.data, { Key = "X" }))
	end)

	---------------------------------------------------------------- the tool

	T.test("StarBlasters: the held tool: its own shape and glow, the forged level's range", function()
		for _, star in StarBlasterData.List do
			local tool = BlasterBuilder.buildStar(star, 4, "Gold")
			T.eq(tool.Name, BlasterBuilder.ToolName)
			T.eq(tool.ToolTip, star.Name)
			T.eq(tool:GetAttribute("Star"), star.Id)
			T.eq(tool:GetAttribute("Level"), 4, "the gates follow the forged level")
			T.eq(tool:GetAttribute("Range"), BlasterData.get(4).Range)
			T.eq(tool:GetAttribute("Glow"), star.Glow, "the beam takes its glow")
			local parts = 0
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "Handle" then
					parts += 1
				end
			end
			T.truthy(parts > 10 and parts <= BlasterBuilder.MaxParts, `{star.Id}: {parts} parts`)
			local handle = tool:FindFirstChild("Handle")
			T.truthy(handle and handle:FindFirstChild("Muzzle"), "a muzzle for the beam")
			T.truthy(tool:FindFirstChild("Effects", true), "sparks or flames")
		end
	end)

	---------------------------------------------------------------- the window

	local function info(count: number, stars: number, weapons: any, weapon: string, robux: boolean): any
		return {
			Count = count,
			Stars = stars,
			Perks = {},
			Level = 5,
			Ready = false,
			StarsNow = 0,
			Weapons = weapons,
			Weapon = weapon,
			RobuxOn = robux,
		}
	end

	T.test("StarBlasters: the BLASTERS cards say what you can do", function()
		local comet, nebula = StarBlasterData.ById.Comet, StarBlasterData.ById.Nebula
		local locked = RebirthView.weaponCard(info(0, 99, {}, "", true), comet)
		T.eq(locked.Main, "🔒 REBIRTH 1")
		T.eq(locked.Robux, nil, "no Robux before it opens")
		local buy = RebirthView.weaponCard(info(1, 5, {}, "", false), comet)
		T.eq(buy.Main, "⭐ 20")
		T.eq(buy.Style, "Off", "too few stars: grey")
		T.eq(buy.Robux, "R$ 75")
		T.falsy(buy.RobuxOn, "the receipts gate is shut")
		T.eq(RebirthView.weaponCard(info(1, 20, {}, "", true), comet).Style, "Buy")
		T.falsy(RebirthView.weaponCard(info(1, 20, {}, "", true), comet).RobuxOn, "placeholder pass id 0: never prompted")
		local owned = RebirthView.weaponCard(info(2, 0, { Comet = true }, "", true), comet)
		T.eq(owned.Main, "EQUIP")
		T.eq(owned.Robux, nil)
		local equipped = RebirthView.weaponCard(info(2, 0, { Comet = true }, "Comet", true), comet)
		T.eq(equipped.Main, "EQUIPPED ✓")
		local waiting = RebirthView.weaponCard(info(1, 0, { Nebula = true }, "", true), nebula)
		T.eq(waiting.State, "Waiting")
		T.truthy(string.find(waiting.Line, "Yours", 1, true))
	end)

	-- design-unit screens: { label, compact, width, height } (as RebirthView.spec)
	local SCREENS = {
		{ "PC 1280 x 720", false, 1280 / 1, (720 - 36) / 1 },
		{ "phone 667 x 375", true, 667 / 0.62, (375 - 58) / 0.62 },
		{ "phone 568 x 320", true, 568 / 0.62, (320 - 58) / 0.62 },
		{ "TV 1920 x 1080", true, 1920 / 1.25, (1080 - 36) / 1.25 },
	}

	T.test("StarBlasters: the BLASTERS page fits PC, phones and TVs", function()
		for _, screen in SCREENS do
			local label, compact, w, h = screen[1], screen[2], screen[3], screen[4]
			for _, data in { info(0, 0, {}, "", false), info(3, 45, { Comet = true }, "Comet", true), info(8, 999, {}, "", true) } do
				local refs = RebirthView.build()
				RebirthView.setTab(refs, "Blasters")
				RebirthView.layout(refs, compact, w, h)
				RebirthView.setInfo(refs, data)
				T.truthy(refs.Pages.Blasters.Visible)
				T.falsy(refs.Pages.Rebirth.Visible)
				local cell = (refs.Pages.Blasters:FindFirstChild("Grid") :: any).CellSize
				local cw, ch = cell.X.Offset, cell.Y.Offset
				T.truthy(cw * 2 + 10 <= refs.Pages.Blasters.Size.X.Offset, label .. ": two cards a row")
				for _, card in refs.Weapons do
					for _, text in { card.Name, card.Text } do
						local x, y, tw, th = text.Position.X.Offset, text.Position.Y.Offset, text.Size.X.Offset, text.Size.Y.Offset
						T.truthy(x + tw <= cw + 1e-6 and y + th <= ch + 1e-6, `{label}: {card.Id} {text.Name} inside the card`)
						T.truthy(TechShopView.fits(text.Text, tw, th, text.TextSize, text.TextWrapped), `{label}: "{text.Text}" fits`)
					end
					for _, button in { card.Main, card.Robux } do
						local holder = MenuPanel.holderOf(button)
						if holder.Visible then
							local x, y = holder.Position.X.Offset, holder.Position.Y.Offset
							local bw, bh = holder.Size.X.Offset, holder.Size.Y.Offset
							T.truthy(x + bw <= cw + 1e-6 and y + bh <= ch + 1e-6, `{label}: {card.Id} {holder.Name} inside the card`)
							T.truthy(TechShopView.fits(button.Text, bw - 8, bh, button.TextSize, false), `{label}: "{button.Text}" fits`)
							if compact then
								T.truthy(bw * MenuPanel.PhoneScale >= MenuPanel.MinTouch, `{label}: {holder.Name} wide enough`)
								T.truthy(bh * MenuPanel.PhoneScale >= MenuPanel.MinTouch, `{label}: {holder.Name} tall enough`)
							end
						end
					end
					T.eq(MenuPanel.holderOf(card.Robux).Visible, card.Robuxed)
				end
				-- the tabs fit their text
				for _, id in RebirthView.TabIds do
					local tab = refs.Tabs[id]
					local holder = MenuPanel.holderOf(tab)
					T.truthy(
						TechShopView.fits(tab.Text, holder.Size.X.Offset - 8, holder.Size.Y.Offset, tab.TextSize, false),
						`{label}: tab {id}`
					)
				end
			end
		end
	end)

	T.test("StarBlasters: the card picture holds the live gun", function()
		local refs = RebirthView.build()
		local card = refs.Weapons[5]
		T.eq(card.Picture:GetAttribute("Icon"), "star_Singularity", "the preview's icon")
		RebirthView.fillPicture(card)
		local gun = card.View:FindFirstChild("Gun")
		T.truthy(gun, "built")
		local parts = 0
		for _, d in gun:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.truthy(d.Anchored, "anchored")
			end
		end
		T.truthy(parts > 10 and parts <= BlasterBuilder.MaxParts, `{parts} parts`)
		T.truthy(card.View:FindFirstChildOfClass("Camera") ~= nil, "a camera (Lune reads no CurrentCamera)")
		RebirthView.fillPicture(card)
		T.eq(#card.View:GetChildren(), 2, "once (the gun and its camera)")
	end)
end
