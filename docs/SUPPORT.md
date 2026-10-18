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

Copy the version id from the list. Then restore it while the player is **offline**: the write is refused if a lock
is on the save.

```lua
local store = game:GetService("DataStoreService"):GetDataStore("TerraForge_PlayerData_v1")
local key = "Player_" .. 12345
local old = store:GetVersionAsync(key, "PASTE_VERSION_ID")
assert(type(old) == "table" and type(old.Data) == "table", "that version isn't a save")
store:UpdateAsync(key, function(current)
	if type(current) == "table" and current.Lock ~= nil then
		warn("the player is online (or a server still holds the save): try again when the lock is gone")
		return nil
	end
	return { Data = old.Data, Saved = os.time() }
end)
```

- An older version has a lower `Data.Version`. The game's Migrations bring it up to date on the next join.
- A lock that stays for more than `GameConfig.StaleLockSeconds` (180 s) belongs to a crashed server. The next join
  takes it over by itself.

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

Don't edit coins by hand to "fix" a cheater. Restore a version from before the cheating instead (2).

## 5. "My progress is gone" checklist

1. Look at the save (1). Is `Lock` set? Then the player is in a server. If it never clears, a crashed server's
   lock is taken over after 180 s.
2. Is `Data.Version` higher than the game's `Migrations.Latest`? Then an old server is still running. Use
   *Migrate To Latest Update* (docs/PUBLISHING.md step 12).
3. Look for these warns in the server log (Creator Dashboard > Error Report / Logs):
   - `[DataService] ... repaired before saving: <path>`: a value the DataStore couldn't hold was fixed. Fix the code
     that wrote it.
   - `[DataService] could not load <name>: <reason>`: `malformed`, `newer` or `error: migrate: ...`. The save was
     left untouched; fix the reason, then the player can join again.
   - `[DataService] final save failed for user <id>`: the last minute of play may be lost. Restore from a version
     if the player lost more.
4. If nothing explains it, restore the last good version (2).
