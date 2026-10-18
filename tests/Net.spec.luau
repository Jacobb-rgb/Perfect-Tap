-- Net's server side (SECURITY_AUDIT #9, #10) on fake RemoteEvents: events
-- from a player who left are dropped before any per-player state is made,
-- the rate-limit buckets are weak-keyed, and every remote nothing handles
-- has a do-nothing listener that only counts the drop.
return function(T, Loader)
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local Players = Loader.game:GetService("Players")

	-- A RemoteEvent stand-in: OnServerEvent:Connect / Disconnect, and fire().
	local function fakeRemote(): any
		local remote: any = { Listeners = {} }
		remote.OnServerEvent = {
			Connect = function(_, fn)
				local connection: any = { Connected = true }
				function connection.Disconnect(self: any)
					self.Connected = false
				end
				table.insert(remote.Listeners, { Fn = fn, Connection = connection })
				return connection
			end,
		}
		function remote.fire(player: any, ...: any)
			for _, listener in remote.Listeners do
				if listener.Connection.Connected then
					listener.Fn(player, ...)
				end
			end
		end
		function remote.connected(): number
			local n = 0
			for _, listener in remote.Listeners do
				if listener.Connection.Connected then
					n += 1
				end
			end
			return n
		end
		return remote
	end

	local function withNet(name: string, fn: (remotes: { [string]: any }) -> ())
		T.test(name, function()
			local remotes: { [string]: any } = {}
			local original = rawget(Net, "event")
			rawset(Net, "event", function(remoteName: string)
				local remote = remotes[remoteName]
				if not remote then
					remote = fakeRemote()
					remotes[remoteName] = remote
				end
				return remote
			end)
			Net._test.reset()
			local ok, err = pcall(fn, remotes)
			Net._test.reset()
			rawset(Net, "event", original)
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function player(name: string, inGame: boolean): any
		return { Name = name, UserId = #name, Parent = if inGame then Players else nil }
	end

	withNet("Net: every remote without a handler gets a do-nothing listener that counts drops", function(remotes)
		local calls = 0
		Net.on("CarryDrop", function()
			calls += 1
		end) -- registered before setupServer: never gets a sink
		Net.setupServer()
		for name in Net.Events do
			T.truthy(remotes[name], "remote " .. name)
		end
		T.falsy(Net._test.hasSink("CarryDrop"), "a handled remote has no sink")
		T.eq(remotes.CarryDrop.connected(), 1, "only its handler")
		for _, name in { "CleanStart", "AnvilSubmit", "GroupClaim", "SetForgeName", "Notify", "State", "BuildResult" } do
			T.truthy(Net._test.hasSink(name), name .. " has a sink")
			T.eq(remotes[name].connected(), 1, name .. ": one listener")
		end
		local p = player("Spammer", true)
		for _ = 1, 50 do
			remotes.CleanStart.fire(p, "junk")
			remotes.Notify.fire(p)
		end
		T.eq(Net.unhandledCount(), 100, "every unhandled event counted")
		T.eq(Net.droppedCount(p), 100, "as drops of that player")
		-- a handler added later replaces the sink
		local mined = 0
		Net.on("MineBlast", function()
			mined += 1
		end)
		T.falsy(Net._test.hasSink("MineBlast"), "sink gone")
		T.eq(remotes.MineBlast.connected(), 1, "just the handler")
		remotes.MineBlast.fire(p, nil)
		T.eq(mined, 1, "the handler runs")
		T.eq(Net.unhandledCount(), 100, "not counted as unhandled")
		remotes.CarryDrop.fire(p)
		T.eq(calls, 1, "the early handler runs too")
	end)

	withNet("Net: events from a player who left make no state and reach no handler", function(remotes)
		Net.setupServer()
		local calls = 0
		Net.on("PenAction", function()
			calls += 1
		end)
		local gone = player("Leaver", false)
		remotes.PenAction.fire(gone, "Take", {})
		T.eq(calls, 0, "no handler call")
		T.falsy(Net._test.hasBucket(gone), "no rate-limit bucket made again")
		remotes.CleanStart.fire(gone)
		T.eq(Net.droppedCount(gone), 0, "no drop counter made for them either")
		T.eq(Net.unhandledCount(), 1, "(the sink still counts the event)")
		local here = player("Stayer", true)
		remotes.PenAction.fire(here, "Take", {})
		T.eq(calls, 1, "a player in the game gets through")
		T.truthy(Net._test.hasBucket(here), "with a bucket")
		Net.forget(here)
		T.falsy(Net._test.hasBucket(here), "forget clears it")
		T.truthy(Net._test.weakKeys(), "buckets and drop counters are weak-keyed")
	end)

	withNet("Net: the rate limits still hold for real handlers", function(remotes)
		Net.setupServer()
		local calls = 0
		Net.on("MineBlast", function()
			calls += 1
		end)
		local p = player("Bot", true)
		for _ = 1, 40 do
			remotes.MineBlast.fire(p, nil)
		end
		local burst = (Net.Events.MineBlast :: any).Burst
		T.le(calls, burst + 1, "no more than the burst at once")
		T.le(40 - calls, Net.droppedCount(p), "the rest counted as drops")
		T.eq(Net.unhandledCount(), 0, "none of them unhandled")
	end)
end
