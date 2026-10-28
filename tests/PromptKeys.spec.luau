-- Prompt keys (owner playtest 2026-10-20: every prompt on E, in the stock
-- Roblox prompt look; Grab moved to F). Static checks over src/:
--   1. every ProximityPrompt is made by PromptConfig.make (the only
--      Instance.new("ProximityPrompt"), the only place that sets prompt keys);
--   2. E (PromptConfig.Keys.Main.Keyboard) belongs to the prompts: no
--      ContextActionService binding, and no other key check, uses it, except
--      the modal close-ups in E_ALLOWED. Each of those suppresses every prompt
--      while it is up (PromptController.setSuppressed), so one E press there
--      never also fires a prompt behind it.
-- Plus PromptConfig.make itself and the role keys against Grab / the backpack window.
local roblox = require("@lune/roblox") :: any
local Enum = roblox.Enum
local Instance = roblox.Instance
local Vector2 = roblox.Vector2

return function(T, Loader)
	local fs = require("@lune/fs")
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")

	local HELPER = "src/shared/Config/PromptConfig.luau"
	-- the light UI's own pill sets the Custom style, only behind UIConfig.CustomPrompts (off)
	local CUSTOM_STYLE = "src/client/Controllers/LightWorldController.luau"
	--[[
		The one other exception (owner 2026-10-28, round 2: "yes, a big E"):
		the EGGS temple's egg prompts draw their own big round E
		(UI/EggPrompt). EggPanelController sets the Custom style in exactly one
		place, behind its own switch EggPanel.BigE, only on the prompts
		it made with PromptConfig.make (so their keys are still the roles'),
		and marks them OwnLook so the light UI never draws over them.
	]]
	local EGG_STYLE = "src/client/Controllers/EggPanelController.luau"
	local EGG_SWITCH = "if EggPanel.BigE then Enum.ProximityPromptStyle.Custom else Enum.ProximityPromptStyle.Default"

	--[[
		The allow-list for E outside the prompts: modal close-ups whose own key
		map has E, while every prompt is suppressed.
		- CleaningController "TerraForgeCleanCollect": E / Enter / A collects the
		  result card. The card is part of the cleaning close-up, which
		  suppresses the prompts ("Cleaning", from enter() to exit()), so the
		  station's "Clean Ore" (back on the moment you submit) can't fire too.
		Nothing else may bind E: Grab is F now, so E next to a podium or a
		machine only ever fires the prompt.
	]]
	local E_ALLOWED: { [string]: { Action: string, Reason: string } } = {
		["src/client/Controllers/CleaningController.luau"] = { Action = '"TerraForgeCleanCollect"', Reason = '"Cleaning"' },
	}

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

	-- the code without its comments (block comments first, then line comments)
	local function code(source: string): string
		local stripped = string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", "")
		stripped = string.gsub(stripped, "%-%-[^\n]*", "")
		return stripped
	end

	local files: { [string]: string } = {} -- "src/..." -> its code
	local paths = {}
	do
		local found = {}
		walk(Loader.root .. "/src", found)
		for _, full in found do
			local rel = string.sub(full, #Loader.root + 2)
			files[rel] = code(fs.readFile(full))
			table.insert(paths, rel)
		end
		table.sort(paths)
	end

	local E_KEY = "Enum%.KeyCode%.E%f[^%w_]"
	local MAIN_KEY = "PromptConfig%.Keys%.Main%.Keyboard"

	local function count(text: string, pattern: string): number
		local _, n = string.gsub(text, pattern, "")
		return n
	end

	-- every ContextActionService:BindAction / BindActionAtPriority call: its argument list
	local function bindings(text: string): { string }
		local out = {}
		for args in string.gmatch(text, "ContextActionService:BindAction%w*%s*(%b())") do
			table.insert(out, args)
		end
		return out
	end

	local function firstArg(args: string): string
		local inner = string.sub(args, 2, -2)
		return (string.match(inner, "^%s*([^,]+)") or ""):match("^(.-)%s*$") :: string
	end

	T.test("PromptKeys: every ProximityPrompt in src/ is made by PromptConfig.make", function()
		T.truthy(#paths > 100, "the whole src/ tree (" .. #paths .. " files)")
		local makers = 0
		for _, rel in paths do
			local text = files[rel]
			local made = count(text, "Instance%.new%(%s*[\"']ProximityPrompt[\"']%s*%)")
			if rel == HELPER then
				T.eq(made, 1, "PromptConfig.make makes them")
			else
				T.eq(made, 0, rel .. ": makes its prompts with PromptConfig.make")
				T.eq(count(text, "%.KeyboardKeyCode%s*=[^=]"), 0, rel .. ": sets no prompt key (PromptConfig roles)")
				T.eq(count(text, "%.GamepadKeyCode%s*=[^=]"), 0, rel .. ": sets no prompt button (PromptConfig roles)")
				if count(text, "PromptConfig%.make%(") > 0 then
					makers += 1
				end
			end
			if rel == EGG_STYLE then
				T.eq(count(text, "ProximityPromptStyle%.Custom"), 1, rel .. ": the egg prompts' own look, in one place")
				T.truthy(string.find(text, EGG_SWITCH, 1, true), rel .. ": only behind EggPanel.BigE")
				T.truthy(string.find(text, ':SetAttribute("OwnLook", true)', 1, true), rel .. ": marked OwnLook (the light UI leaves them)")
			elseif rel ~= CUSTOM_STYLE then
				T.eq(count(text, "ProximityPromptStyle%.Custom"), 0, rel .. ": the stock prompt look")
			end
		end
		-- the sites live in 19 files: 17 server services, CodexController and TrainController
		-- (FoundryService went with the Foundry, owner 2026-10-24)
		T.truthy(makers >= 19, "the prompt sites use the helper (" .. makers .. " files)")
	end)

	T.test("PromptKeys: E is the prompts' key; only modal close-ups that suppress the prompts bind it", function()
		T.eq(PromptConfig.Keys.Main.Keyboard, Enum.KeyCode.E, "the prompts are on E")
		local allowedSeen = 0
		for _, rel in paths do
			if rel ~= HELPER then
				local text = files[rel]
				local inBindings = 0
				for _, args in bindings(text) do
					local e = count(args, E_KEY) + count(args, MAIN_KEY)
					if e > 0 then
						local allowed = E_ALLOWED[rel]
						local action = firstArg(args)
						T.truthy(allowed and allowed.Action == action, `{rel}: {action} binds E (the prompts' key)`)
						inBindings += e
						allowedSeen += 1
					end
				end
				-- the E literal nowhere else either (an InputBegan key check, IsKeyDown...)
				local literal = 0
				for _, args in bindings(text) do
					literal += count(args, E_KEY)
				end
				T.eq(count(text, E_KEY), literal, rel .. ": Enum.KeyCode.E only inside a binding")
				T.truthy(inBindings == 0 or E_ALLOWED[rel], rel .. ": E only in an allowed modal binding")
			end
		end
		T.eq(allowedSeen, 1, "the cleaning card's Collect binding is still the only one (the Foundry's went with it)")
		for rel, allowed in E_ALLOWED do
			local text = files[rel]
			T.truthy(text, rel .. " exists")
			local on = `PromptController.setSuppressed({allowed.Reason}, true)`
			local off = `PromptController.setSuppressed({allowed.Reason}, false)`
			T.truthy(string.find(text, on, 1, true), `{rel}: suppresses the prompts during its close-up`)
			T.truthy(string.find(text, off, 1, true), `{rel}: and brings them back`)
		end
	end)

	T.test("PromptKeys: Grab is F / X and no role shares a key with Grab or the backpack window", function()
		local interact = files["src/client/Controllers/InteractController.luau"]
		local grab, throw
		for _, args in bindings(interact) do
			local action = firstArg(args)
			if action == '"TerraForgeGrab"' then
				grab = args
			elseif action == '"TerraForgeThrow"' then
				throw = args
			end
		end
		T.truthy(grab, "InteractController binds Grab")
		T.falsy(throw, "no Throw since the backpack (owner 2026-10-24: nothing is thrown)")
		T.truthy(string.find(grab, "Enum.KeyCode.F,", 1, true), "Grab on F")
		T.truthy(string.find(grab, "Enum.KeyCode.ButtonX", 1, true), "Grab on gamepad X")
		T.eq(count(grab, E_KEY), 0, "Grab left E to the prompts")
		-- the backpack window took the throw's Q / R1 (BackpackController)
		local backpack = files["src/client/Controllers/BackpackController.luau"]
		T.truthy(string.find(backpack, "BackpackController.Key = Enum.KeyCode.Q\n", 1, true), "the backpack on Q")
		T.truthy(string.find(backpack, "BackpackController.PadKey = Enum.KeyCode.ButtonR1\n", 1, true), "and gamepad R1")
		local taken = {
			[Enum.KeyCode.F] = "Grab",
			[Enum.KeyCode.ButtonX] = "Grab",
			[Enum.KeyCode.Q] = "Backpack",
			[Enum.KeyCode.ButtonR1] = "Backpack",
		}
		local seen = {}
		for _, role in { "Main", "Second", "Panel" } do
			local keys = PromptConfig.keys(role)
			T.eq(keys, PromptConfig.Keys[role], role .. ": keys() returns its keys")
			for _, key in { keys.Keyboard, keys.Gamepad } do
				T.falsy(taken[key], `{role}: {key.Name} is free (not {taken[key]})`)
				T.falsy(seen[key], `{role}: {key.Name} is its own`)
				seen[key] = role
			end
		end
		T.eq(PromptConfig.keys(nil), PromptConfig.Keys.Main, "no role: Main")
		-- the gamepad buttons stay what they were (Y main, B second, L3 panel)
		T.eq(PromptConfig.Keys.Main.Gamepad, Enum.KeyCode.ButtonY)
		T.eq(PromptConfig.Keys.Second.Keyboard, Enum.KeyCode.G)
		T.eq(PromptConfig.Keys.Second.Gamepad, Enum.KeyCode.ButtonB)
		T.eq(PromptConfig.Keys.Panel.Keyboard, Enum.KeyCode.T)
		T.eq(PromptConfig.Keys.Panel.Gamepad, Enum.KeyCode.ButtonL3)
	end)

	T.test("PromptKeys: PromptConfig.make (defaults, every field, Parent last)", function()
		local plain = PromptConfig.make({})
		T.eq(plain.ClassName, "ProximityPrompt")
		T.eq(plain.Style, Enum.ProximityPromptStyle.Default, "the stock Roblox prompt")
		T.eq(plain.KeyboardKeyCode, Enum.KeyCode.E, "Main by default")
		T.eq(plain.GamepadKeyCode, Enum.KeyCode.ButtonY)
		T.eq(plain.HoldDuration, 0, "a tap")
		T.eq(plain.MaxActivationDistance, 10, "10 studs")
		T.eq(plain.RequiresLineOfSight, false, "seen through walls")
		T.eq(plain.UIOffset, Vector2.new(0, 0), "slot 0")
		T.eq(plain.Exclusivity, Enum.ProximityPromptExclusivity.OnePerButton, "Roblox's default")
		T.truthy(plain.Enabled)
		T.eq(plain.Parent, nil, "no parent unless asked")
		local parent = Instance.new("Attachment")
		local full = PromptConfig.make({
			Role = "Second",
			Name = "TakePrompt",
			ActionText = "Take Ore Back",
			ObjectText = "Cleaning Station",
			Hold = 0.4,
			Distance = 8,
			Sight = true,
			Slot = 1,
			Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow,
			Enabled = false,
			Parent = parent,
		})
		T.eq(full.Parent, parent, "parented")
		T.eq(full.Name, "TakePrompt")
		T.eq(full.ActionText, "Take Ore Back")
		T.eq(full.ObjectText, "Cleaning Station")
		T.eq(full.KeyboardKeyCode, Enum.KeyCode.G, "Second")
		T.eq(full.GamepadKeyCode, Enum.KeyCode.ButtonB)
		T.near(full.HoldDuration, 0.4, 1e-6)
		T.eq(full.MaxActivationDistance, 8)
		T.eq(full.RequiresLineOfSight, true)
		T.eq(full.UIOffset, Vector2.new(0, PromptConfig.SlotHeight), "slot 1")
		T.eq(full.Exclusivity, Enum.ProximityPromptExclusivity.AlwaysShow)
		T.falsy(full.Enabled)
		local panel = PromptConfig.make({ Role = "Panel", Slot = 2 })
		T.eq(panel.KeyboardKeyCode, Enum.KeyCode.T)
		T.eq(panel.UIOffset, Vector2.new(0, 144), "slot 2")
		T.eq(PromptConfig.SlotHeight, 72, "the step every stacked prompt uses")
		-- the slot step is the one the trains use
		local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
		T.eq(TrainConfig.PromptSlotHeight, PromptConfig.SlotHeight, "TrainConfig's slot step")
		-- (the HoldDuration/Text set before Parent: make() parents last; the setter order is in the helper)
		local helper = files[HELPER]
		local parentAt = string.find(helper, "prompt.Parent = spec.Parent", 1, true)
		T.truthy(parentAt, "make() parents")
		for _, field in { "prompt.Style", "prompt.KeyboardKeyCode", "prompt.UIOffset", "prompt.Enabled", "prompt.Exclusivity" } do
			local at = string.find(helper, field .. " =", 1, true)
			T.truthy(at and at < (parentAt :: number), field .. " is set before Parent")
		end
	end)
end
