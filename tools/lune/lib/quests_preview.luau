--[[
	The QUESTS window and the daily-streak popup over the lobby (scene "quests"
	for tools/lune/export_scene.luau; shots in tools/preview/quests_shots.json).
	Drawn with the game's own code (QuestView, QuestLogic, HudBubble). UI overlays:
	  ui_quests_pc            PC 1600 x 900: one daily done (CLAIM), the streak's day 4 waiting
	  ui_quests_pc_odds       PC: the day-7 capsule's odds panel
	  ui_quests_phone         844 x 390 pt phone (rendered x2)
	  ui_quests_phone_small   568 x 320 pt phone (rendered x3)
	  ui_streak_pc / _phone / _phone_small   the streak popup on join
	  ui_quests_hud_pc        the HUD with the MORE flyout open: the QUESTS tile and its badge
]]

local UiExport = require("./uiexport")

local Preview = {}

local DAY = 86400
local NOW = 20825 * DAY + 10 * 3600 -- a Thursday, 10:00 UTC

function Preview.build(Loader: any): { [string]: any }
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local QuestLogic = Loader.requirePath("ReplicatedStorage.Shared.Quests.QuestLogic")
	local QuestConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.QuestConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local QuestView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.QuestView")

	-- a blaster-4 player earning 1840/s: the first daily done, the second half way, the weekly at 40 %
	local function view(): any
		local stats = {
			OresMined = 5000,
			RocksBroken = 1500,
			OresCleaned = 200,
			FlawlessCleans = 10,
			IngotsSmelted = 300,
			ItemsSold = 900,
			TrainTrips = 80,
			PodiumEarned = 1e7,
			ArtifactsFound = 5,
			CapsulesOpened = 30,
			WheelSpins = 10,
		}
		local record: any = {}
		QuestLogic.refresh(record, {
			UserId = 1234,
			Now = NOW,
			Level = 4,
			Income = 1840,
			Stats = stats,
			Capsules = true,
		})
		local now = table.clone(stats)
		local function push(entry: any, share: number)
			local stat = QuestConfig.ById[entry.Id].Stat
			now[stat] = (now[stat] or 0) + math.floor(entry.Goal * share)
		end
		push(record.Daily[1], 1)
		push(record.Daily[2], 0.55)
		push(record.Daily[3], 0.12)
		push(record.Weekly[1], 0.4)
		local streak = { Day = 3, Last = QuestLogic.day(NOW) - 1 }
		return QuestLogic.view(record, streak, now, NOW, 4, 1840, Format.money)
	end

	local function hud(uiScale: number, compact: boolean, designW: number): any
		local refs = HudBubble.buildGame(if compact then 0.62 else 1.25)
		TeleportView.build(refs.TopBar, if compact then 0.62 else 1.25, designW)
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(4.82e6)
		refs.Income.Text = Format.perSecond(1840)
		HudView.setBackpack(refs, 0, 5)
		refs.Toasts:ClearAllChildren()
		-- the left tiles as the controllers claim them in the game
		HudBubble.claimTile(refs.Menu, "Build")
		local faces = {}
		for _, entry in SideMenuView.sorted() do
			local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
			if entry.Group == "Main" then
				faces[entry.Id] = HudBubble.claimTile(refs.Menu, entry.Id, spec)
			else
				faces[entry.Id] = HudBubble.addMore(refs.Menu, entry.Id, spec)
			end
		end
		HudBubble.setTileBadge(faces.Quests, 2)
		local more = refs.Menu:FindFirstChild("More")
		local moreFace = more and more:FindFirstChild("Face")
		if moreFace then
			HudBubble.setTileBadge(moreFace, 2)
		end
		return refs
	end

	-- a screen: render px (w x h), pt scale (k render px per pt), inset px, phone?
	local function screens(): { [string]: any }
		return {
			pc = { Scale = 1.25, W = 1600 / 1.25, H = (900 - 36) / 1.25, Compact = false },
			phone = { Scale = 0.62 * 2, W = 1688 / (0.62 * 2), H = (780 - 72) / (0.62 * 2), Compact = true },
			phone_small = { Scale = 0.62 * 3, W = 1704 / (0.62 * 3), H = (960 - 108) / (0.62 * 3), Compact = true },
		}
	end

	local exports: { [string]: any } = {}
	for name, s in screens() do
		local window = QuestView.build()
		window.Gui.Scale.Scale = s.Scale
		window.Gui.Enabled = true
		QuestView.layout(window, s.W, s.H, s.Compact)
		QuestView.setView(window, view(), NOW)
		exports["ui_quests_" .. name] = UiExport.export({ hud(s.Scale, s.Compact, s.W).Gui, window.Gui })

		local popup = QuestView.buildPopup()
		popup.Gui.Scale.Scale = s.Scale
		popup.Gui.Enabled = true
		QuestView.layoutPopup(popup, s.W, s.H, s.Compact)
		QuestView.setPopup(popup, view())
		exports["ui_streak_" .. name] = UiExport.export({ hud(s.Scale, s.Compact, s.W).Gui, popup.Gui })
	end
	local pc = screens().pc
	local odds = QuestView.build()
	odds.Gui.Scale.Scale = pc.Scale
	odds.Gui.Enabled = true
	QuestView.layout(odds, pc.W, pc.H, false)
	QuestView.setView(odds, view(), NOW)
	QuestView.showOdds(odds, QuestView.oddsLines(false))
	exports.ui_quests_pc_odds = UiExport.export({ hud(pc.Scale, false, pc.W).Gui, odds.Gui })
	local open = hud(pc.Scale, false, pc.W)
	HudBubble.toggleMore(open.Menu, true)
	exports.ui_quests_hud_pc = UiExport.export({ open.Gui })
	return exports
end

return Preview
