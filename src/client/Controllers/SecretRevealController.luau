--[[
	SecretRevealController: the SECRET ores on the client (owner 2026-10-29).

	  SecretFound { OreId, New, Stars }   the server graded a secret ore this
	      player cleaned: kept until the cleaning's dirt bursts
	      (SecretCleanFx calls play), so NEW! knows a first find.
	  SecretChat { UserId, Name, OreId, Global }   a line in the chat for a
	      find on this server (Global: Rainbow Nova from any server), built
	      here from OreData (TextChatService RBXGeneral:DisplaySystemMessage):
	      "[SECRET] Mia found Hollow Eye! (1 in 4,000)"
	  Fx "SecretPillar" (position, oreId)   a column of rainbow light over a
	      station where someone near found a secret (everyone within
	      SecretService.PillarRadius sees it): six turning shafts round a
	      white core, rings climbing it, PillarSeconds, then it fades.
	  play(oreId, onDone?, result?)   the cinematic reveal (owner 2026-10-30:
	      Effects/SecretOreReveal plays Effects/SecretCinematic: discovery,
	      charging, the burst, SECRET + its name, rarity, chance and value,
	      CONTINUE) from the moment the dirt bursts. `result` is the server's
	      CleanResult: its Value (the graded value) and Into (a clean ore that
	      went into the backpack flies into the bag button at the close, one
	      that went to the pen or the tray fades). Skip, CONTINUE, Reduce
	      motion, phones, its one flash (RevealKit's gap), the camera's kick and
	      the sounds: see SecretOreReveal. onDone runs once when it is over
	      (or cut short: a reset, another play).
	  flashPlan / retryFlash   the burst's one-flash rule (SecretCinematic.boomFlash /
	      retryBoomFlash: relative to the burst)
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local SecretCinematic = require(script.Parent.Parent.Effects.SecretCinematic)
local SecretOreReveal = require(script.Parent.Parent.Effects.SecretOreReveal)
local Motion = require(script.Parent.Parent.UI.Motion)

local SecretRevealController = {}

SecretRevealController.KeepFound = 30 -- seconds a SecretFound waits for its cleaning to burst
SecretRevealController.Color = "#FF78E6" -- the chat line's colour (Rarity.Secret)
SecretRevealController.PillarSeconds = 3.6
SecretRevealController.PillarHeight = 120

---------------------------------------------------------------- pure (specced)

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

-- The chat line for a SecretChat (nil for an unknown ore or a broken name).
function SecretRevealController.chatLine(data: any): string?
	local length = if type(data) == "table" and type(data.Name) == "string" then utf8.len(data.Name) else nil
	if not length or length == 0 or length > 20 then
		return nil -- (a DisplayName is 1..20 characters)
	end
	local secret = if type(data.OreId) == "string" then SecretOreConfig.ByOre[data.OreId] else nil
	local ore = if secret then OreData.ById[secret.Ore] else nil
	if not secret or not ore then
		return nil
	end
	local chance = SecretOreConfig.chanceText(secret.OneIn)
	local text = `[SECRET] {escape(data.Name)} found {ore.Name}! ({chance})`
	return `<font color="{SecretRevealController.Color}"><b>{text}</b></font>`
end

-- The burst's one flash (RevealKit's gap): 0 (at the burst) if it may flash `now`; else math.huge
-- and the clock to try once more. Reduce motion: none, no slot taken. (SecretCinematic.boomFlash)
function SecretRevealController.flashPlan(now: number, reduced: boolean): (number, number?)
	return SecretCinematic.boomFlash(now, reduced)
end

-- The flash that waited, `t` seconds after the burst: `t` if it may flash now, nil when the slot is
-- taken again or it is too late (SecretCinematic.Timing.FlashWindow: a hitch, a skip; then no slot).
function SecretRevealController.retryFlash(t: number, now: number): number?
	return SecretCinematic.retryBoomFlash(t, now)
end

-- The value the cinematic shows: the server's graded value of the clean ore (CleanResult.Value),
-- else what a Flawless one is worth (ItemData.value, the grade the cleaning gives a secret).
function SecretRevealController.valueOf(oreId: string, result: any?): number
	local value = if type(result) == "table" then result.Value else nil
	if type(value) == "number" and value == value and value > 0 and value < math.huge then
		return value
	end
	local grade = if type(result) == "table"
			and type(result.Grade) == "string"
			and ItemData.GradeById[result.Grade]
		then result.Grade
		else SecretOreConfig.Grade
	return ItemData.value("Clean", oreId, grade)
end

-- Where the ore flies at the close (px on the cinematic's full screen): into the bag when the clean
-- ore went into the backpack (`into` "Backpack" or unknown): the HUD's backpack button when it is
-- shown (`bag`: its middle), else the bottom middle where it sits; nil (it fades) for the pen or the tray.
function SecretRevealController.flyTo(into: any, screen: Vector2, bag: Vector2?): Vector2?
	if into ~= nil and into ~= "Backpack" then
		return nil
	end
	return bag or Vector2.new(screen.X / 2, screen.Y - 64)
end

---------------------------------------------------------------- the client

local found: { [string]: { New: boolean, At: number } } = {}

-- The SecretFound of `oreId` if it came in the last KeepFound seconds (and forgets it).
function SecretRevealController.takeFound(oreId: string): { New: boolean }?
	local entry = found[oreId]
	found[oreId] = nil
	if entry and os.clock() - entry.At <= SecretRevealController.KeepFound then
		return { New = entry.New }
	end
	return nil
end

local function showChat(data: any)
	local line = SecretRevealController.chatLine(data)
	if not line then
		return
	end
	pcall(function()
		local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(line)
		end
	end)
end

-- The HUD's backpack button's middle on the cinematic's full screen (nil when the HUD is hidden:
-- the cleaning hides it).
local function bagPoint(): Vector2?
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = gui and gui:FindFirstChild("TerraForgeHud")
	if not hud or not hud:IsA("ScreenGui") or not hud.Enabled then
		return nil
	end
	local pack = hud:FindFirstChild("Backpack", true)
	if not pack or not pack:IsA("GuiObject") or not pack.Visible or pack.AbsoluteSize.X <= 0 then
		return nil
	end
	local inset = Vector2.zero
	if not hud.IgnoreGuiInset then
		local ok, top = pcall(function()
			return GuiService:GetGuiInset()
		end)
		inset = if ok then Vector2.new(0, top.Y) else Vector2.zero
	end
	return pack.AbsolutePosition + pack.AbsoluteSize / 2 + inset
end

function SecretRevealController.play(oreId: string, onDone: (() -> ())?, result: any?)
	if not SecretOreConfig.isSecret(oreId) then
		if onDone then
			onDone()
		end
		return
	end
	local info = SecretRevealController.takeFound(oreId)
	local secret = SecretOreConfig.ByOre[oreId]
	local into = if type(result) == "table" then result.Into else nil
	SecretOreReveal.Play(oreId, OreData.get(oreId).Name, secret.Stars, SecretRevealController.valueOf(oreId, result), {
		Chance = SecretOreConfig.chanceText(secret.OneIn),
		New = info ~= nil and info.New,
		OnDone = onDone,
		Target = function()
			local camera = Workspace.CurrentCamera
			local screen = if camera then camera.ViewportSize else Vector2.new(1280, 720)
			return SecretRevealController.flyTo(into, screen, bagPoint())
		end,
	})
end

-- The column of light over a station (Fx "SecretPillar").
local function pillar(position: any, _oreId: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SecretPillar"
	folder.Parent = Workspace
	local function neon(color: Color3): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Parent = folder
		return p
	end
	local shafts = {}
	for _, color in SecretOreConfig.Rainbow do
		table.insert(shafts, neon(color))
	end
	local core = neon(Color3.fromRGB(255, 246, 228))
	local rings = {}
	for k = 1, 3 do
		local bars = {}
		for j = 1, 12 do
			table.insert(bars, neon(SecretOreConfig.Rainbow[(j + k) % #SecretOreConfig.Rainbow + 1]))
		end
		rings[k] = bars
	end
	local reduced = Motion.reduced()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local st = os.clock() - started
		local life = SecretRevealController.PillarSeconds
		if st >= life then
			connection:Disconnect()
			folder:Destroy()
			return
		end
		local up = if reduced then 1 else math.min(st / 0.25, 1)
		local fade = math.clamp((st - (life - 0.8)) / 0.8, 0, 1)
		local height = SecretRevealController.PillarHeight * up
		local spin = if reduced then 0 else st * 1.6
		for k, shaft in shafts do
			local a = k * math.pi / 3 + spin
			shaft.Size = Vector3.new(0.7, height, 0.7)
			shaft.CFrame = CFrame.new(position + Vector3.new(math.cos(a) * 1.3, height / 2, math.sin(a) * 1.3))
			shaft.Transparency = 0.25 + 0.75 * fade
		end
		core.Size = Vector3.new(1.4, height, 1.4)
		core.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0))
		core.Transparency = 0.15 + 0.85 * fade
		for k, bars in rings do
			local u = if reduced then k / 3 else (st * 0.7 + k / 3) % 1
			local y = position.Y + 4 + u * 50
			local r = 2.6 + 1.5 * math.sin(u * math.pi)
			for j, bar in bars do
				local a = j * math.pi / 6 + spin
				local at = Vector3.new(position.X + math.cos(a) * r, y, position.Z + math.sin(a) * r)
				bar.Size = Vector3.new(0.25, 0.25, r * 0.5)
				bar.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a)))
				bar.Transparency = math.max(fade, u * 0.8)
			end
		end
	end)
end

function SecretRevealController.init()
	local FxController = require(script.Parent.FxController)
	FxController.register("SecretPillar", pillar)
	Net.listen("SecretFound", function(data)
		if type(data) == "table" and SecretOreConfig.isSecret(data.OreId) then
			found[data.OreId] = { New = data.New == true, At = os.clock() }
		end
	end)
	Net.listen("SecretChat", showChat)
end

function SecretRevealController.start() end

return SecretRevealController
