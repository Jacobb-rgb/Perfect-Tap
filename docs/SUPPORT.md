# Support: player saves after launch

What to do when a player's save needs help (docs/SAVE_AUDIT.md #14). Every step runs in the **Studio command bar**
with *Game Settings > Security > Enable Studio Access to API Services* on. Live saves are in the DataStore
`TerraForge_PlayerData_v1`, key `Player_<UserId>`. A Studio play session uses `TerraForge_PlayerData_Studio`
instead, so testing never touches these.

A stored save looks like `{ Data = {...}, Lock = { JobId, SessionId, Time }?, Saved = os.time() }`. `Lock` is set
while the player is in a server. **Never write a save while it has a Lock**: the server holding it would see that its
session was lost and stop saving. Ask the player to leave the game first.

## 1. Look at a save

```lua
local store = game:GetService("DataStoreService"):GetDataStore("TerraForge_PlayerData_v1")
local value = store:GetAsync("Player_" .. 12345)
print(value and value.Lock, value and value.Data.Coins, value and value.Data.Version)
```

## 2. Restore an earlier version (rollback)

The DataStore keeps every version for 30 days.

List the versions of the last week, newest first:

```lua
local store = game:GetService("DataStoreService"):GetDataStore("TerraForge_PlayerData_v1")
local key = "Player_" .. 12345
local pages = store:ListVersionsAsync(key, Enum.SortDirection.Descending, (os.time() - 7 * 86400) * 1000)
for _, info in pages:GetCurrentPage() do
	print(info.Version, os.date("!%Y-%m-%d %H:%M", info.CreatedTime // 1000), info.IsDeleted)
end
```

Copy the version id from the list. Then restore it while the player is **offline**. The write is refused while a
live lock is on the save (a lock dated ahead of this PC's clock counts as live), but goes through when the stored
value is broken (not a save) or its lock is stale (a crashed server).

**Robux purchases made after that version are undone by a restore.** Roblox never delivers an acknowledged receipt
again, so the snippet keeps every purchase id of the current save and prints the ones the old version doesn't
have. Re-grant those products by hand on the restored save (the player bought them):

```lua
local store = game:GetService("DataStoreService"):GetDataStore("TerraForge_PlayerData_v1")
local key = "Player_" .. 12345
local old = store:GetVersionAsync(key, "PASTE_VERSION_ID")
assert(type(old) == "table" and type(old.Data) == "table", "that version isn't a save")
store:UpdateAsync(key, function(current)
	local isSave = type(current) == "table" and type(current.Data) == "table"
	local lock = if isSave and type(current.Lock) == "table" then current.Lock else nil
	local age = if lock then os.time() - (tonumber(lock.Time) or 0) else math.huge
	if lock and age < 600 then
		warn(`the player is online (or a server still holds the save, {age} s ago): try again in a few minutes`)
		return nil
	end
	-- purchases since that version: keep their ids, list them for a re-grant
	local data = old.Data
	data.Purchases = if type(data.Purchases) == "table" then data.Purchases else {}
	if isSave and type(current.Data.Purchases) == "table" then
		for id, at in current.Data.Purchases do
			if data.Purchases[id] == nil then
				data.Purchases[id] = at
				print("RE-GRANT purchase", id, os.date("!%Y-%m-%d %H:%M", tonumber(at) or 0))
			end
		end
	end
	return { Data = data, Saved = os.time() }
end)
```

- An older version has a lower `Data.Version`. The game's Migrations bring it up to date on the next join.
- A lock older than `GameConfig.StaleLockSeconds` (180 s; 600 s for locks from servers older than the SessionId
  change) belongs to a crashed server. The next join takes it over by itself, and the snippet above writes over it.

## 3. Data-erasure request (Right to be Forgotten)

Roblox sends these to the creator's messages. Remove the save and the leaderboard entries:

```lua
local store = game:GetService("DataStoreService"):GetDataStore("TerraForge_PlayerData_v1")
store:RemoveAsync("Player_" .. 12345)
-- once steps 6-7 are in the game (the lobby leaderboards):
require(game.ServerScriptService.Server.Services.LeaderboardService).removeUser(12345)
```

The leaderboard call has to run on a server that has started the services: a Studio play session with API access,
or your own command in a live server. Older versions of the removed key expire by themselves after 30 days.

## 4. Bans

To take a cheater off the boards, call `LeaderboardService.removeUser(id)` as in 3: it hides them on every server
and keeps them off. To keep them out of the game, use Roblox's ban tools in the Creator Dashboard or
`Players:BanAsync`.

Don't edit coins by hand to "fix" a cheater. Restore a version from before the cheating instead (2), and re-grant
the Robux purchases it prints: those were paid for.

## 5. "My progress is gone" checklist

1. Look at the save (1). Is `Lock` set? Then the player is in a server. If it never clears, a crashed server's
   lock is taken over after 180 s.
2. Is `Data.Version` higher than the game's `Migrations.Latest`? Then an old server is still running. Use
   *Migrate To Latest Update* (docs/PUBLISHING.md step 12). It is also the sign of a rollback to an older build:
   fix forward instead (republish the newest build with the broken feature off). An older build must never run on
   these saves: its Migrations drop what it doesn't know (PUBLISHING step 12).
3. Look for these warns in the server log (Creator Dashboard > Error Report / Logs):
   - `[DataService] ... repaired before saving: <path>`: a value the DataStore couldn't hold was fixed. Fix the code
     that wrote it.
   - `[DataService] could not load <name>: <reason>`: `malformed`, `newer` or `error: migrate: ...`. The save was
     left untouched; fix the reason, then the player can join again.
   - `[DataService] final save failed for user <id>`: the last minute of play may be lost. Restore from a version
     if the player lost more.
4. If nothing explains it, restore the last good version (2), then re-grant the purchases it prints.

## 6. "Couldn't read your save" / "couldn't prepare your save"

The player was kicked with one of these and gets the same message on every join:
- `malformed`: the stored value isn't a save any more, for example after a manual edit in a DataStore editor.
- `error: migrate: ...`: the save is fine as stored, but this build's Migrations throw on it.

The game never writes over such a save, so the stored value is exactly what broke it.

1. Look at it (1), and at the live server log for the full `could not load` line.
2. For `malformed`: restore the last good version (2). The snippet writes over a broken value, with or without a
   lock on it.
3. For `error: migrate`: fix the Migrations bug and republish. If one field is broken, restoring a version from before
   it broke (2) also works.
