--[[
	The emotes in the game (owner 2026-10-21: "add the emotes") and the
	player moves switched off (AnimConfig.PlayerMoves = false):

	  EmoteRules        the whitelist, the attribute format, what blocks a
	                    start, what stops a playing emote (moving first)
	  EmoteService      the Net "Emote" whitelist, Guard, the cooldown, the
	                    blocks (carrying, cleaning, board, seat, dead), the
	                    Blaster Spin needing the blaster, "" stops, the poll,
	                    the rate limit; nothing registered with Emotes off
	  MoveService       PlayerMoves off: no Net "Move" handler, no hooks, no
	                    attribute (on: all of them, as before)
	  MoveController    on fake services (Env), proved by the connections:
	                    moves off = no Stepped loop, no Fx / ActionResult /
	                    Notify listeners, no Move / MoveLoop / CarryCount
	                    listeners, no sends; an emote nearby connects the one
	                    loop, moving stops it (outro), the loop disconnects
	                    when it is over; far away = no loop; the Gem Juggle's
	                    gems come from the pool and go back
	  EmoteView         the menu builds 12 word cards, fits PC and phones
	                    (cards and the X >= 44 pt), the Blaster Spin card greys
	  keys              N is free (no other KeyCode.N, not a Roblox key, not
	                    one the integrator listed); no new pad button
	  EmoteProps        the gem pool and the juggling path
	  review anim/ship  the blaster in hand goes away for every emote but the
	                    Blaster Spin; a stop before the server's echo is
	                    sent; a late "" echo never stops your next emote;
	                    the gems go back on a switch; a stopped emote far
	                    away is dropped; the Blaster Spin twirls the grip
	                    (and puts it back); the server's cooldown is a
	                    little shorter; no EMOTES menu in a close-up
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance, Vector3, Vector2 = roblox.Instance, roblox.Vector3, roblox.Vector2
	local CFrame = Loader.CFrame
	local Enum = roblox.Enum
	local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")
	local EmoteConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EmoteConfig")
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	local EmoteRules = Loader.requirePath("ReplicatedStorage.Shared.Moves.EmoteRules")
	local EmoteProps = Loader.requirePath("ReplicatedStorage.Shared.Moves.EmoteProps")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local Players = Loader.game:GetService("Players")

	local function withAnim(moves: boolean, emotes: boolean, fn: () -> ())
		local was = { AnimConfig.PlayerMoves, AnimConfig.Emotes }
		AnimConfig.PlayerMoves = moves
		AnimConfig.Emotes = emotes
		local ok, err = pcall(fn)
		AnimConfig.PlayerMoves = was[1]
		AnimConfig.Emotes = was[2]
		if not ok then
			error(err, 0)
		end
	end

	-- a signal with Connect / Disconnect, fire() and the number of live connections
	local function signal(): any
		local s: any = { list = {} }
		function s.Connect(_, fn)
			local c: any = { Connected = true }
			function c.Disconnect(self)
				self.Connected = false
			end
			table.insert(s.list, { fn = fn, c = c })
			return c
		end
		function s.fire(...)
			for _, h in s.list do
				if h.c.Connected then
					h.fn(...)
				end
			end
		end
		function s.count(): number
			local n = 0
			for _, h in s.list do
				if h.c.Connected then
					n += 1
				end
			end
			return n
		end
		return s
	end

	---------------------------------------------------------------- EmoteRules

	T.test("emotes live: the whitelist and the attribute format", function()
		for _, name in EmoteConfig.List do
			T.truthy(EmoteRules.allowed(name), name .. " is allowed")
			local back, seq = EmoteRules.decode(EmoteRules.encode(name, 7))
			T.eq(back, name, name .. " round trip")
			T.eq(seq, 7, "seq")
		end
		for _, bad in { "Carry", "Throw", "BigCelebrate", "robot", "Robot ", "", 12, true, string.rep("R", 60) } do
			T.falsy(EmoteRules.allowed(bad), "refused: " .. tostring(bad))
		end
		for _, bad in { "", "Robot", "Robot:", ":3", "Carry:2", "Robot:1:2", "Robot:-1", 5 } do
			T.eq(EmoteRules.decode(bad), nil, "not an emote: " .. tostring(bad))
		end
		T.eq(EmoteRules.nextSeq(EmoteRules.MaxSeq), 1, "the seq wraps")
	end)

	T.test("emotes live: what blocks a start and what stops a playing emote", function()
		T.eq(EmoteRules.blocked({}), nil, "free to dance")
		T.eq(EmoteRules.blocked({ Carrying = true }), "Carrying", "never while carrying ore")
		T.eq(EmoteRules.blocked({ Cleaning = true }), "Cleaning", "never while cleaning")
		T.eq(EmoteRules.blocked({ Building = true }), "Building", "never in build mode / a close-up")
		T.eq(EmoteRules.blocked({ Riding = true }), "Riding", "never on a hoverboard")
		T.eq(EmoteRules.blocked({ Seated = true }), "Seated", "never seated")
		T.eq(EmoteRules.blocked({ Dead = true }), "Dead", "never dead")
		T.truthy(EmoteRules.needsTool("BlasterSpin"), "the Blaster Spin needs a tool")
		T.falsy(EmoteRules.toolOk("BlasterSpin", false), "not without the blaster")
		T.truthy(EmoteRules.toolOk("BlasterSpin", true), "with the blaster")
		T.truthy(EmoteRules.toolOk("Robot", false), "the others need nothing")
		local still = { Speed = 0, State = "Running" }
		T.eq(EmoteRules.stopReason("Robot", still), nil, "standing still: it plays on")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0.5 }), "Moving", "walking stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0.05 }), nil, "a stick drift doesn't")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, State = "Jumping" }), "Moving", "a jump stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Seated = true }), "State", "a seat stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Riding = true }), "Riding", "a board stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Tool = true }), "Tool", "a tool in hand stops it")
		T.eq(EmoteRules.stopReason("BlasterSpin", { Speed = 0, Tool = true, Blaster = true }), nil, "the Blaster Spin keeps its blaster")
		T.eq(EmoteRules.stopReason("BlasterSpin", { Speed = 0 }), "NoBlaster", "the blaster put away stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Firing = true }), "Firing", "firing stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Panel = true }), "Panel", "a panel opening stops it")
		T.eq(EmoteRules.stopReason("Robot", { Speed = 0, Carrying = true }), "Carrying", "picking ore up stops it")
		T.truthy(EmoteRules.canPlay(nil, 0, 1) and not EmoteRules.canPlay(5, 5.5, 1) and EmoteRules.canPlay(5, 6, 1), "the cooldown")
	end)

	---------------------------------------------------------------- EmoteService

	local EmoteService = Loader.requirePath("ServerScriptService.Server.Services.EmoteService")

	local function fakeServerPlayer(name: string): any
		local humanoid = { Health = 100, Sit = false }
		local root = { Position = Vector3.new(0, 3, 0) }
		local character: any = { Parent = true, attrs = {} }
		function character.GetAttribute(_, k)
			return character.attrs[k]
		end
		function character.SetAttribute(_, k, v)
			character.attrs[k] = v
		end
		function character.FindFirstChildOfClass(_, class)
			return if class == "Humanoid" then humanoid else nil
		end
		function character.FindFirstChild(_, n)
			if n == "HumanoidRootPart" then
				return root
			end
			local tool = character.tool
			if tool and n == tool.Name then
				return tool
			end
			return nil
		end
		local player: any = { Name = name, UserId = #name, Parent = Players, Character = character, attrs = {}, humanoid = humanoid }
		function player.GetAttribute(_, k)
			return player.attrs[k]
		end
		return player
	end
	local function blasterTool(): any
		return {
			Name = EmoteRules.BlasterTool,
			IsA = function(_, class)
				return class == "Tool"
			end,
		}
	end
	local function attr(player: any): any
		return player.Character.attrs[EmoteRules.Attribute]
	end

	T.test("emotes live: EmoteService plays only whitelisted emotes, with Guard, blocks and a cooldown", function()
		local now = 100
		local cleaning = false
		local test = EmoteService._test
		test.reset()
		test.setClock(function()
			return now
		end)
		test.setCleaning(function()
			return cleaning
		end)
		local ok, err = pcall(function()
			local p = fakeServerPlayer("Dancer")
			for _, bad in { "Carry", "Throw", "robot", 12, {}, true, string.rep("W", 200), "Robot:1" } do
				test.onEmote(p, bad)
				T.eq(attr(p), nil, "refused: " .. tostring(bad))
			end
			test.onEmote(p, "Robot")
			T.eq(attr(p), "Robot:1", "the attribute: name and seq")
			T.eq(EmoteService.playing(p), "Robot", "playing")
			test.onEmote(p, "")
			T.eq(attr(p), "", '"" stops it')
			test.onEmote(p, "Robot")
			T.eq(attr(p), "", "the same emote again within its cooldown: refused")
			now += EmoteRules.Cooldown
			test.onEmote(p, "Robot")
			T.eq(attr(p), "Robot:2", "after the cooldown")
			test.onEmote(p, "Worm")
			T.eq(attr(p), "Worm:3", "another emote right away")
			-- the blocks
			test.onEmote(p, "")
			p.attrs[MoveConfig.CarryAttribute] = 2
			now += 2
			test.onEmote(p, "Headspin")
			T.eq(attr(p), "", "never while carrying ore")
			p.attrs[MoveConfig.CarryAttribute] = 0
			cleaning = true
			test.onEmote(p, "Headspin")
			T.eq(attr(p), "", "never while cleaning")
			cleaning = false
			p.Character.attrs[HoverboardData.Attribute] = "Board"
			test.onEmote(p, "Headspin")
			T.eq(attr(p), "", "never on a hoverboard")
			p.Character.attrs[HoverboardData.Attribute] = nil
			p.humanoid.Sit = true
			test.onEmote(p, "Headspin")
			T.eq(attr(p), "", "never seated")
			p.humanoid.Sit = false
			p.humanoid.Health = 0
			test.onEmote(p, "Headspin")
			T.eq(attr(p), "", "never dead (Guard.rootPart)")
			p.humanoid.Health = 100
			-- the Blaster Spin needs the blaster
			test.onEmote(p, "BlasterSpin")
			T.eq(attr(p), "", "no Blaster Spin without the blaster")
			p.Character.tool = blasterTool()
			test.onEmote(p, "BlasterSpin")
			T.eq(attr(p), "BlasterSpin:4", "with the blaster in hand")
			-- the poll: the blaster put away / ore picked up clear it
			p.Character.tool = nil
			test.poll()
			T.eq(attr(p), "", "the poll stops a Blaster Spin without the blaster")
			now += 2
			test.onEmote(p, "Victory")
			p.attrs[MoveConfig.CarryAttribute] = 1
			test.poll()
			T.eq(attr(p), "", "the poll stops it when ore is picked up")
		end)
		test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	-- Net.spec's trick: fake remotes, spy on what is registered
	local function withFakeNet(fn: (remotes: { [string]: any }, registered: { string }) -> ())
		local remotes: { [string]: any } = {}
		local registered: { string } = {}
		local originalEvent = rawget(Net, "event")
		rawset(Net, "event", function(remoteName: string)
			local remote = remotes[remoteName]
			if not remote then
				remote = { Listeners = {} }
				remote.OnServerEvent = {
					Connect = function(_, f)
						table.insert(remote.Listeners, f)
						table.insert(registered, remoteName)
						return { Connected = true, Disconnect = function() end }
					end,
				}
				remotes[remoteName] = remote
			end
			return remote
		end)
		Net._test.reset()
		local ok, err = pcall(fn, remotes, registered)
		Net._test.reset()
		rawset(Net, "event", originalEvent)
		if not ok then
			error(err, 0)
		end
	end

	T.test("emotes live: the server's cooldown is a little shorter than the menu's (network jitter)", function()
		T.truthy(EmoteRules.ServerCooldown < EmoteRules.Cooldown, "the server waits less than the client")
		T.truthy(EmoteRules.ServerCooldown >= 0.5 * EmoteRules.Cooldown, "still a real cooldown")
		local now = 300
		local test = EmoteService._test
		test.reset()
		test.setClock(function()
			return now
		end)
		test.setCleaning(function()
			return false
		end)
		local ok, err = pcall(function()
			local p = fakeServerPlayer("Jitter")
			test.onEmote(p, "Robot")
			T.eq(attr(p), "Robot:1")
			test.onEmote(p, "")
			-- the client waited its full second, but the first packet came in late: 0.9 s apart here
			now += EmoteRules.Cooldown - 0.1
			test.onEmote(p, "Robot")
			T.eq(attr(p), "Robot:2", "taken: the client shows it, so does everyone else")
			test.onEmote(p, "")
			now += EmoteRules.ServerCooldown - 0.2
			test.onEmote(p, "Robot")
			T.eq(attr(p), "", "a real spam is still refused")
		end)
		test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("emotes live: Net Emote is rate limited", function()
		local limit = Net.Events.Emote
		T.truthy(type(limit) == "table" and limit.Rate <= 3 and limit.Burst <= 5, "a tight limit")
		withFakeNet(function(remotes)
			local calls = 0
			Net.on("Emote", function()
				calls += 1
			end)
			local player = { Name = "Spammer", UserId = 9, Parent = Players }
			for _ = 1, 30 do
				for _, listener in remotes.Emote.Listeners do
					listener(player, "Robot")
				end
			end
			T.eq(calls, limit.Burst, "a burst gets through, the rest is dropped")
		end)
	end)

	T.test("emotes live: switched off, the services register nothing", function()
		local MoveService = Loader.requirePath("ServerScriptService.Server.Services.MoveService")
		local Discovery = Loader.requirePath("ServerScriptService.Server.Discovery")
		local CleaningService = Loader.requirePath("ServerScriptService.Server.Services.CleaningService")
		local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
		local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
		local SellService = Loader.requirePath("ServerScriptService.Server.Services.SellService")
		local hooks = 0
		local spies = {
			{ Discovery, "onDiscovered" },
			{ CleaningService, "onCleaned" },
			{ CapsuleService, "onOpened" },
			{ DataService, "onLoaded" },
			{ DataService, "onChanged" },
			{ SellService, "onSold" },
		}
		local saved = {}
		for i, s in spies do
			saved[i] = rawget(s[1], s[2])
			rawset(s[1], s[2], function()
				hooks += 1
			end)
		end
		local removing = rawget(Players, "PlayerRemoving")
		rawset(Players, "PlayerRemoving", signal())
		local ok, err = pcall(function()
			withFakeNet(function(_remotes, registered)
				withAnim(false, false, function()
					MoveService.init()
					EmoteService.init()
				end)
				T.eq(#registered, 0, "moves and emotes off: no Net handler at all")
				T.eq(hooks, 0, "moves off: no celebration hooks")
				local p = fakeServerPlayer("Quiet")
				withAnim(false, true, function()
					T.falsy(MoveService.play(p, "Celebrate"), "moves off: play() sets nothing")
					MoveService.setLoop(p, "Spray")
				end)
				T.eq(p.Character.attrs[MoveConfig.Attribute], nil, "no Move attribute")
				T.eq(p.Character.attrs[MoveConfig.LoopAttribute], nil, "no MoveLoop attribute")
			end)
			withFakeNet(function(_remotes, registered)
				withAnim(false, true, function()
					MoveService.init()
					EmoteService.init()
				end)
				T.truthy(table.find(registered, "Emote"), "emotes on: Net Emote is handled")
				T.falsy(table.find(registered, "Move"), "moves off: Net Move is not")
				T.eq(hooks, 0, "still no move hooks")
			end)
			withFakeNet(function(_remotes, registered)
				withAnim(true, false, function()
					MoveService.init()
				end)
				T.truthy(table.find(registered, "Move"), "moves on: Net Move is handled")
				T.eq(hooks, #spies, "moves on: every celebration hook")
			end)
		end)
		for i, s in spies do
			rawset(s[1], s[2], saved[i])
		end
		rawset(Players, "PlayerRemoving", removing)
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- MoveController on fake services

	local MoveController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.MoveController")

	local function fakeCharacter(name: string, at: any): (any, any, { [string]: any })
		local character: any = { Name = name, Parent = true, attrs = {}, signals = {}, tool = nil }
		function character.GetAttribute(_, k)
			return character.attrs[k]
		end
		function character.GetAttributeChangedSignal(_, k)
			local s = character.signals[k]
			if not s then
				s = signal()
				character.signals[k] = s
			end
			return s
		end
		function character.SetAttribute(_, k, v)
			character.attrs[k] = v
			local s = character.signals[k]
			if s then
				s.fire()
			end
		end
		local parts: { [string]: any } = {}
		for joint, partName in MoveConfig.JointPart do
			local part = parts[partName]
			if not part then
				part = { Name = partName, Parent = character, CFrame = CFrame.new(at), Position = at, motors = {} }
				function part.IsA(_, class)
					return class == "BasePart"
				end
				function part.FindFirstChild(_, n)
					return part.motors[n]
				end
				parts[partName] = part
			end
			local motor: any = { Name = joint, Parent = part, Transform = CFrame.identity }
			function motor.IsA(_, class)
				return class == "Motor6D"
			end
			part.motors[joint] = motor
		end
		local root = { Name = "HumanoidRootPart", Parent = character, Position = at }
		function root.IsA(_, class)
			return class == "BasePart"
		end
		local humanoid: any = {
			Parent = character,
			RigType = Enum.HumanoidRigType.R15,
			Health = 100,
			Sit = false,
			MoveDirection = Vector3.zero,
			state = Enum.HumanoidStateType.Running,
			unequips = 0,
		}
		function humanoid.GetState(self)
			return self.state
		end
		-- (the tool goes to the backpack)
		function humanoid.UnequipTools(self)
			self.unequips += 1
			character.tool = nil
		end
		function character.FindFirstChildOfClass(_, class)
			if class == "Humanoid" then
				return humanoid
			elseif class == "Tool" then
				return character.tool
			end
			return nil
		end
		function character.FindFirstChild(_, n)
			if n == "HumanoidRootPart" then
				return root
			end
			local tool = character.tool
			if tool and n == tool.Name then
				return tool
			end
			return parts[n]
		end
		return character, humanoid, parts
	end

	local function fakePlayer(name: string, character: any): any
		local player: any = { Name = name, Character = character, attrs = {}, signals = {} }
		function player.GetAttribute(_, k)
			return player.attrs[k]
		end
		function player.GetAttributeChangedSignal(_, k)
			local s = player.signals[k]
			if not s then
				s = signal()
				player.signals[k] = s
			end
			return s
		end
		player.CharacterAdded = signal()
		player.CharacterRemoving = signal()
		return player
	end

	-- runs `fn` with MoveController on fake services; returns nothing
	local function withController(moves: boolean, emotes: boolean, fn: (w: any) -> (), title: string?)
		T.test(title or `emotes live: MoveController with PlayerMoves {moves} and Emotes {emotes}`, function()
			local w: any = { now = 1000, sends = {}, listens = {} }
			local meChar, meHum, meParts = fakeCharacter("Me", Vector3.new(0, 3, 0))
			local themChar, themHum, themParts = fakeCharacter("Them", Vector3.new(6, 3, 0))
			w.me = fakePlayer("Me", meChar)
			w.them = fakePlayer("Them", themChar)
			w.meChar, w.meHum, w.meParts = meChar, meHum, meParts
			w.themChar, w.themHum, w.themParts = themChar, themHum, themParts
			w.stepped = signal()
			w.panel = false
			w.camera = {
				CameraType = Enum.CameraType.Custom,
				CFrame = CFrame.new(0, 6, 14),
				WorldToViewportPoint = function(_, p)
					return p, true
				end,
			}
			local env = MoveController.Env
			local saved = table.clone(env)
			env.RunService = { Stepped = w.stepped }
			env.Players = {
				LocalPlayer = w.me,
				GetPlayers = function()
					return { w.me, w.them }
				end,
				PlayerAdded = signal(),
				PlayerRemoving = signal(),
			}
			env.GuiService = {
				ReducedMotionEnabled = false,
				GetPropertyChangedSignal = function()
					return signal()
				end,
			}
			env.Workspace = { CurrentCamera = w.camera }
			env.listen = function(name: string)
				table.insert(w.listens, name)
				return { Connected = true, Disconnect = function() end }
			end
			env.send = function(name: string, ...: any)
				table.insert(w.sends, { name, ... })
			end
			env.firing = function()
				return false
			end
			env.controlsOwner = function()
				return nil
			end
			env.panelOpen = function()
				return w.panel
			end
			env.onSettings = function() end
			env.propsFolder = function()
				return Instance.new("Folder")
			end
			env.clock = function()
				return w.now
			end
			function w.step(seconds: number)
				local frames = math.max(1, math.floor(seconds * 30 + 0.5))
				for _ = 1, frames do
					w.now += 1 / 30
					if w.stepped.count() > 0 then
						MoveController._test.step(1 / 30)
					end
				end
			end
			MoveController._test.reset()
			local ok, err = pcall(function()
				withAnim(moves, emotes, function()
					MoveController.init()
					MoveController.start()
					fn(w)
				end)
			end)
			MoveController._test.reset()
			for k in env do
				env[k] = nil
			end
			for k, v in saved do
				env[k] = v
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function changed(parts: { [string]: any }): boolean
		for _, part in parts do
			for _, motor in part.motors do
				if motor.Transform ~= CFrame.identity then
					return true
				end
			end
		end
		return false
	end

	withController(false, true, function(w)
		-- moves off: nothing of them is connected or sent
		T.eq(w.stepped.count(), 0, "no Stepped loop while nobody emotes")
		T.falsy(MoveController.status().Loop, "status: no loop")
		for _, name in { "Fx", "ActionResult", "Notify" } do
			T.falsy(table.find(w.listens, name), "no " .. name .. " listener")
		end
		T.eq(w.meChar.signals[MoveConfig.Attribute], nil, "no Move attribute listener")
		T.eq(w.meChar.signals[MoveConfig.LoopAttribute], nil, "no MoveLoop attribute listener")
		T.eq(w.me.signals[MoveConfig.CarryAttribute], nil, "no CarryCount listener")
		T.truthy(w.themChar.signals[EmoteRules.Attribute], "the Emote attribute is followed")
		MoveController.playLocal("Throw")
		MoveController.playLocal("Wave")
		T.eq(#w.sends, 0, "no Throw / Wave sent")
		w.step(1)
		T.eq(w.stepped.count(), 0, "still no loop")

		-- another player's emote nearby: the loop connects and poses the rig
		w.themChar:SetAttribute(EmoteRules.Attribute, "Robot:1")
		T.eq(w.stepped.count(), 1, "an emote nearby connects the one loop")
		w.step(0.8)
		T.truthy(changed(w.themParts), "the emote poses their joints")
		-- they walk off: the outro plays, then the loop goes away
		w.themHum.MoveDirection = Vector3.new(1, 0, 0)
		w.step(0.1)
		T.eq(MoveController._test.entryOf(w.themChar).Slots[4].Stop ~= nil, true, "moving starts the outro")
		w.step(2)
		T.eq(w.stepped.count(), 0, "the loop disconnects when nothing plays")
		T.falsy(changed(w.themParts), "the joints are given back")
		T.eq(#w.sends, 0, "the others' stops send nothing")

		-- yours: plays at once, asks the server; picking it again stops it
		w.themHum.MoveDirection = Vector3.zero
		local ok, why = MoveController.playEmote("Headspin")
		T.truthy(ok and why == "Playing", "your emote plays")
		T.eq(w.sends[1][1], "Emote", "Net Emote")
		T.eq(w.sends[1][2], "Headspin", "with its name")
		T.eq(MoveController.emote(), "Headspin", "playing")
		T.eq(w.stepped.count(), 1, "the loop runs while it plays")
		MoveController.playEmote("Headspin")
		T.eq(w.sends[2][2], "", "picked again: stop sent")
		T.eq(MoveController.emote(), nil, "stopping (its outro)")
		w.step(3)
		T.eq(w.stepped.count(), 0, "idle again")

		-- the blocks and the blaster
		w.me.attrs[MoveConfig.CarryAttribute] = 2
		local okCarry, reason = MoveController.playEmote("Worm")
		T.falsy(okCarry, "not while carrying")
		T.eq(reason, "Carrying", "says why")
		w.me.attrs[MoveConfig.CarryAttribute] = 0
		local okGun, gunReason = MoveController.playEmote("BlasterSpin")
		T.falsy(okGun, "no Blaster Spin without the blaster")
		T.eq(gunReason, "NoBlaster", "says why")
		T.falsy(MoveController.holdingBlaster(), "no blaster")
		w.meChar.tool = blasterTool()
		T.truthy(MoveController.holdingBlaster(), "the blaster in hand")
		T.truthy((MoveController.playEmote("BlasterSpin")), "with the blaster")
		w.meChar.tool = nil
		w.step(0.4)
		T.eq(MoveController.emote(), nil, "putting the blaster away stops it")
		T.eq(w.sends[#w.sends][2], "", "and tells the server")
		w.step(3)

		-- your emote stops when a panel opens, and when you walk
		w.now += 5
		MoveController.playEmote("Robot")
		w.panel = true
		w.step(0.4)
		T.eq(MoveController.emote(), nil, "a panel opening stops it")
		w.panel = false
		w.step(3)
		w.now += 5
		MoveController.playEmote("Victory")
		w.meHum.MoveDirection = Vector3.new(0, 0, 1)
		w.step(0.1)
		T.eq(MoveController.emote(), nil, "walking stops it")
		T.eq(w.sends[#w.sends][2], "", "stop sent")
		w.meHum.MoveDirection = Vector3.zero
		w.step(3)

		-- Reduce Motion keeps the emotes (only the moves get calmer): a Headspin stays a Headspin
		local MoveRules = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRules")
		T.eq(MoveRules.substitute("Headspin", true), "Headspin", "Reduce Motion never touches an emote")

		-- far away: no loop at all (the slow check only)
		w.themChar.FindFirstChild(nil, "HumanoidRootPart").Position = Vector3.new(400, 3, 0)
		w.themChar:SetAttribute(EmoteRules.Attribute, "Worm:2")
		T.eq(w.stepped.count(), 0, "an emote out of range runs no loop")

		-- the Gem Juggle's gems: from the pool, back to it
		w.themChar.FindFirstChild(nil, "HumanoidRootPart").Position = Vector3.new(6, 3, 0)
		w.themChar:SetAttribute(EmoteRules.Attribute, "GemJuggle:3")
		w.step(0.6)
		T.eq(MoveController.status().Gems, 1, "one juggler holds a gem set")
		local entry = MoveController._test.entryOf(w.themChar)
		T.eq(#entry.Gems, EmoteProps.GemCount, "three gems")
		for _, gem in entry.Gems do
			T.truthy(
				gem.Parent ~= nil and gem.Material == Enum.Material.Neon and not gem.CanCollide,
				"a Neon gem, no collision, in the props folder"
			)
		end
		w.themChar:SetAttribute(EmoteRules.Attribute, "")
		w.step(0.1)
		T.eq(MoveController.status().Gems, 0, "the gems go back when it stops")
	end)

	-- a fake RightGrip weld in a hand (Roblox puts one there when a tool is equipped)
	local GRIP_BASE = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local function gripWeld(hand: any): any
		local grip: any = { Name = "RightGrip", Parent = hand, C0 = GRIP_BASE, C1 = CFrame.identity }
		function grip.IsA(_, class)
			return class == "Weld" or class == "JointInstance"
		end
		hand.motors.RightGrip = grip
		return grip
	end
	local function turned(grip: any): number
		return (grip.C0.LookVector - GRIP_BASE.LookVector).Magnitude
	end

	withController(false, true, function(w)
		local entryOf = MoveController._test.entryOf

		-- 1. the blaster in hand (it stays out after mining): any emote but the Blaster Spin puts it away
		w.meChar.tool = blasterTool()
		local ok, why = MoveController.playEmote("Robot")
		T.truthy(ok and why == "Playing", "Robot plays with the blaster in hand")
		T.eq(w.meHum.unequips, 1, "the blaster goes to the backpack (as cleaning and build mode do)")
		T.eq(w.meChar.tool, nil, "nothing in hand")
		w.step(0.6)
		T.eq(MoveController.emote(), "Robot", "it keeps playing through the checks (no Tool stop on the first frame)")
		T.eq(#w.sends, 1, "only the start was sent")
		MoveController.playEmote("Robot")
		w.step(3)

		-- the Blaster Spin keeps the blaster and twirls it: the RightGrip weld's C0 turns, then goes back
		w.now += 5
		w.meChar.tool = blasterTool()
		local grip = gripWeld(w.meParts.RightHand)
		T.truthy((MoveController.playEmote("BlasterSpin")), "the Blaster Spin")
		T.eq(w.meHum.unequips, 1, "keeps the blaster in hand")
		w.step(0.47)
		T.truthy(turned(grip) > 0.5, "the blaster twirls round the finger: " .. turned(grip))
		T.near((grip.C0.Position - GRIP_BASE.Position).Magnitude, 0, 1e-6, "about the grip (the hand holds it)")
		T.eq(grip.C1, CFrame.identity, "C1 is BlasterFx's (the kick)")
		MoveController.playEmote("BlasterSpin")
		w.step(3)
		T.eq(grip.C0, GRIP_BASE, "the grip is back as it was")
		T.eq(entryOf(w.meChar).Grip, nil, "and let go")
		-- the others' Blaster Spin twirls on your screen too
		w.themChar.tool = blasterTool()
		local theirGrip = gripWeld(w.themParts.RightHand)
		w.themChar:SetAttribute(EmoteRules.Attribute, "BlasterSpin:5")
		w.step(0.47)
		T.truthy(turned(theirGrip) > 0.5, "their blaster twirls")
		w.themChar:SetAttribute(EmoteRules.Attribute, "")
		w.step(3)
		T.eq(theirGrip.C0, GRIP_BASE, "theirs is put back too")
		w.themChar.tool = nil
		w.meChar.tool = nil

		-- 2. a stop before the server's echo came back is still sent (the attribute reads "" from before)
		w.now += 5
		w.meChar:SetAttribute(EmoteRules.Attribute, "")
		local before = #w.sends
		MoveController.playEmote("Worm")
		w.meHum.MoveDirection = Vector3.new(0, 0, 1)
		w.step(0.1)
		T.eq(MoveController.emote(), nil, "walking off stops it")
		T.eq(#w.sends, before + 2, "the start and the stop")
		T.eq(w.sends[#w.sends][1], "Emote")
		T.eq(w.sends[#w.sends][2], "", "the stop went out before the echo")
		w.meHum.MoveDirection = Vector3.zero
		w.meChar:SetAttribute(EmoteRules.Attribute, "Worm:7")
		w.step(1)
		T.eq(MoveController.emote(), nil, "the late echo never restarts yours")
		T.eq(#w.sends, before + 2, "nothing more to send")
		-- ... and the "" echo of that stop, arriving after you picked the next emote, never stops it
		w.now += 5
		MoveController.playEmote("Victory")
		w.meChar:SetAttribute(EmoteRules.Attribute, "Victory:8")
		w.step(0.3)
		w.meHum.MoveDirection = Vector3.new(0, 0, 1)
		w.step(0.1)
		w.meHum.MoveDirection = Vector3.zero
		T.eq(w.sends[#w.sends][2], "", "Victory's stop")
		MoveController.playEmote("Headspin")
		w.meChar:SetAttribute(EmoteRules.Attribute, "")
		w.step(0.2)
		T.eq(MoveController.emote(), "Headspin", "the echo of the earlier stop leaves the new emote alone")
		w.meChar:SetAttribute(EmoteRules.Attribute, "Headspin:9")
		w.step(MoveController.EchoGrace + 0.2)
		w.meChar:SetAttribute(EmoteRules.Attribute, "")
		T.eq(MoveController.emote(), nil, "a later stop from the server is honoured")
		w.step(3)

		-- 3. switching from the Gem Juggle gives the gems back
		w.themChar:SetAttribute(EmoteRules.Attribute, "GemJuggle:10")
		w.step(0.6)
		T.eq(MoveController.status().Gems, 1, "a juggler")
		local gems = entryOf(w.themChar).Gems
		w.themChar:SetAttribute(EmoteRules.Attribute, "Robot:11")
		w.step(0.2)
		T.eq(MoveController.status().Gems, 0, "another emote: the gems go back to the pool")
		T.eq(gems[1].Parent, nil, "none hangs in the air")

		-- 4. a stopped emote far away is dropped (nothing left for the slow check to watch)
		local root = w.themChar.FindFirstChild(nil, "HumanoidRootPart")
		root.Position = Vector3.new(400, 3, 0)
		w.themChar:SetAttribute(EmoteRules.Attribute, "Worm:12")
		MoveController._test.check()
		local slot = entryOf(w.themChar).Slots[4]
		T.truthy(slot.Move ~= nil, "far away an emote waits (it plays when they come into view)")
		T.falsy(MoveController.status().Loop, "no loop for it")
		w.themChar:SetAttribute(EmoteRules.Attribute, "")
		T.eq(slot.Move, nil, "stopped out of range: dropped")
		T.eq(slot.Layer.Weight, 0)
		root.Position = Vector3.new(6, 3, 0)

		-- 5. a close-up (cleaning, build mode, the Foundry, the vault): no EMOTES menu there
		T.falsy(MoveController.inCloseUp(), "no close-up now")
		w.camera.CameraType = Enum.CameraType.Scriptable
		T.truthy(MoveController.inCloseUp(), "a Scriptable camera is a close-up")
		w.camera.CameraType = Enum.CameraType.Custom
	end, "emotes live: review anim/ship: blaster, early stops, echoes, gems, far emotes, the twirl, close-ups")

	withController(true, true, function(w)
		-- moves on: everything as before
		T.eq(w.stepped.count(), 1, "the moves keep their one loop")
		for _, name in { "Fx", "ActionResult", "Notify" } do
			T.truthy(table.find(w.listens, name), "the " .. name .. " listener")
		end
		T.truthy(w.meChar.signals[MoveConfig.Attribute], "the Move attribute is followed")
		T.truthy(w.meChar.signals[MoveConfig.LoopAttribute], "the MoveLoop attribute is followed")
		T.truthy(w.me.signals[MoveConfig.CarryAttribute], "CarryCount is followed")
		MoveController.playLocal("Shrug")
		T.eq(w.sends[1] and w.sends[1][1], "Move", "a client move is sent")
		w.step(1)
		T.eq(w.stepped.count(), 1, "still one loop")
	end)

	withController(false, false, function(w)
		T.eq(w.stepped.count(), 0, "both off: no loop")
		T.eq(#w.listens, 0, "no listeners")
		T.eq(MoveController.status().Entries, 0, "no characters followed")
	end)

	---------------------------------------------------------------- the menu

	local EmoteView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EmoteView")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")

	T.test("emotes live: the EMOTES menu builds word cards and fits PC and phones (44 pt)", function()
		local refs = EmoteView.build()
		T.eq(#refs.Order, #EmoteConfig.List, "a card per emote")
		for _, name in EmoteConfig.List do
			local card = refs.Cards[name]
			T.truthy(card, name .. " card")
			T.truthy(card.Title.Text:match("^[A-Z ]+$"), name .. ": its name in capital words")
			T.truthy(#card.Note.Text > 0, name .. ": a short line")
			T.truthy(card.Button.Selectable, name .. ": the gamepad can select it")
		end
		T.truthy(refs.Group.SelectionGroup, "a selection group (the pad stays in the menu)")
		-- PC
		EmoteView.layout(refs, 1280, 690, false)
		local pc = EmoteView.cardSize(refs)
		T.truthy(pc.X >= 180 and pc.Y >= 90, "big cards on a PC")
		-- phones (HudController's scale floor 0.62, the top inset)
		for _, phone in { Vector2.new(667, 375), Vector2.new(568, 320), Vector2.new(844, 390) } do
			local scale = 0.62
			local w, h = phone.X / scale, (phone.Y - 36) / scale
			EmoteView.layout(refs, w, h, true)
			local fit = EmoteView.fit(refs)
			local card = EmoteView.cardSize(refs)
			T.truthy(card.Y * fit * scale >= 44, `{phone}: cards {card.Y * fit * scale} pt high`)
			T.truthy(card.X * fit * scale >= 44, `{phone}: cards wide enough`)
			local close = refs.Window.Close.Size.X.Offset * fit * scale
			T.truthy(close >= 44, `{phone}: the X {close} pt`)
			local size = refs.Window.Root.Size
			T.truthy(size.X.Offset * fit <= w + 1 and size.Y.Offset * fit <= h + 1, `{phone}: the window fits the screen`)
		end
		-- states
		EmoteView.setCard(refs, "BlasterSpin", "Locked", EmoteRules.NeedsBlaster)
		T.eq(refs.Cards.BlasterSpin.Note.Text, "Hold your blaster", "the Blaster Spin says why")
		T.eq(refs.Cards.BlasterSpin.State, "Locked", "greyed")
		EmoteView.setCard(refs, "Robot", "Playing")
		T.truthy(refs.Cards.Robot.Tag.Visible, "the PLAYING tag")
		EmoteView.setCard(refs, "Robot", "Ready")
		T.falsy(refs.Cards.Robot.Tag.Visible, "gone again")
	end)

	T.test("emotes live: the EMOTES tile in the left HUD menu fits with the others", function()
		local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		local refs = HudBubble.buildGame(1)
		HudBubble.claimTile(refs.Menu, "Build")
		for _, entry in SideMenuView.sorted() do
			local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
			if entry.Group == "Main" then
				HudBubble.claimTile(refs.Menu, entry.Id, spec)
			else
				HudBubble.addMore(refs.Menu, entry.Id, spec)
			end
		end
		local face = HudBubble.claimTile(refs.Menu, "Emotes", { Label = "EMOTES", IconName = "Emotes", Order = 40 })
		T.truthy(face and face:IsA("TextButton"), "the tile's button")
		local label = face:FindFirstChild("Label") :: any
		T.eq(label.Text, "EMOTES", "its word")
		T.falsy(IconAssets.has("emotes"), "no picture: the word shows (never an emoji)")
		local visible = 0
		for _, child in refs.Menu:GetChildren() do
			if child:IsA("Frame") and child.Visible then
				visible += 1
			end
		end
		T.le(visible, #HudBubble.GameMenu, "every claimed tile fits the menu's rows (nothing under the TRAIN chip)")
		local faces = HudBubble.linkMenu(refs.Menu)
		T.truthy(table.find(faces, face), "the D-pad reaches it")
	end)

	---------------------------------------------------------------- keys

	T.test("emotes live: the N key is free and no new gamepad button is bound", function()
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/EmoteController.luau")
		T.truthy(source:find("EmoteController.Key = Enum.KeyCode.N", 1, true), "the key is N")
		-- no other part of the game uses N
		local function walk(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk(Loader.root .. "/src", files)
		for _, path in files do
			if not path:find("EmoteController", 1, true) then
				local text = fs.readFile(path)
				T.falsy(text:find("KeyCode%.N[^%w]"), path .. " uses KeyCode.N")
				T.falsy(text:find('KeyCode%["N"%]'), path .. " uses KeyCode N")
			end
		end
		-- not one the integrator listed as taken, not a Roblox key (moving, camera zoom, chat, menus)
		local taken = { "V", "E", "F", "B", "R", "M", "X", "Q", "G", "H", "T", "L" }
		local roblox = { "W", "A", "S", "D", "I", "O", "Space", "Tab", "Slash", "Escape", "LeftShift", "RightShift", "F9" }
		for _, key in taken do
			T.falsy(key == "N", key)
		end
		for _, key in roblox do
			T.falsy(key == "N", key)
		end
		-- the menu binds N only (no touch button: phones use the tile), and B / Backspace to close
		T.truthy(source:find("BindAction(KEY_ACTION, onKey, false, EmoteController.Key)", 1, true), "N, no touch button")
		for _, pad in { "ButtonA", "ButtonX", "ButtonY", "ButtonL1", "ButtonR1", "ButtonL2", "ButtonR2", "ButtonL3", "ButtonR3", "DPad" } do
			T.falsy(source:find("KeyCode." .. pad, 1, true), "no " .. pad .. " binding")
		end
		T.truthy(source:find("Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace", 1, true), "B / Backspace close it")
		-- (review anim/ship #13) never over a close-up: N passes, the tile does nothing there
		T.truthy(
			source:find("if not isOpen and inCloseUp() then\n\t\treturn Enum.ContextActionResult.Pass", 1, true),
			"N passes in a close-up"
		)
		T.truthy(source:find("if isOpen or not AnimConfig.Emotes or inCloseUp() then", 1, true), "open() refuses a close-up")
		T.truthy(source:find("MoveController.inCloseUp()", 1, true), "a Scriptable camera or claimed controls")
		T.truthy(source:find('FindFirstChild("CleaningController")', 1, true), "and the cleaning minigame")
		local panels = fs.readFile(Loader.root .. "/src/client/Util/MenuPanels.luau")
		T.truthy(panels:find('"EmoteController"', 1, true), "a MenuPanels panel: it closes when another opens")
	end)

	---------------------------------------------------------------- the gems

	T.test("emotes live: the gem pool and the juggling path", function()
		local made = 0
		local pool = EmoteProps.newPool(function(i: number): any
			made += 1
			return EmoteProps.makeGem(i)
		end, 2)
		local a = pool.acquire("A")
		T.eq(#a, EmoteProps.GemCount, "three gems per juggler")
		T.eq(pool.acquire("A"), a, "the same set again for the same juggler")
		local b = pool.acquire("B")
		T.truthy(b and b ~= a, "a second juggler")
		T.eq(pool.acquire("C"), nil, "no more than the limit")
		T.eq(pool.active(), 2, "two jugglers")
		pool.release("A")
		T.eq(a[1].Parent, nil, "released gems leave the world")
		local c = pool.acquire("C")
		T.eq(c, a, "a released set is reused")
		T.eq(made, 2 * EmoteProps.GemCount, "no new parts after the first sets")
		pool.release("Nobody")
		T.eq(pool.active(), 2, "releasing a stranger changes nothing")
		local gem = EmoteProps.makeGem(1)
		T.truthy(gem.Anchored and not gem.CanCollide and not gem.CanQuery and not gem.CanTouch and not gem.CastShadow, "a look only")
		T.eq(gem.Material, Enum.Material.Neon, "Neon")
		-- the path: gems leave and land in the hands, never higher than the arc
		local right, left = Vector3.new(1, 3, -1), Vector3.new(-1, 3, -1)
		for i = 1, EmoteProps.GemCount do
			for f = 0, 72 do
				local p = EmoteProps.juggle(f / 30, i, right, left)
				T.truthy(p.Y >= 3 - 1e-6 and p.Y <= 3 + EmoteProps.Height + 1e-6, "within the arc")
				T.truthy(math.abs(p.X) <= 1 + 1e-6, "between the hands")
			end
		end
		T.truthy((EmoteProps.juggle(0, 1, right, left) - right).Magnitude < 1e-6, "gem 1 starts in the right hand")
		T.truthy((EmoteProps.juggle(EmoteProps.Flight, 1, right, left) - left).Magnitude < 1e-6, "and lands in the left")
	end)
end
