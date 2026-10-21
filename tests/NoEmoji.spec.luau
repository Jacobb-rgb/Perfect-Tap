--[[
	No emoji in the game (the owner, 2026-10-21: "bez emoji, jenom text": no
	emoji, text only). A static check over every src/**/*.luau file: the code
	with its comments blanked out (strings stay, that is where player text
	lives) may not hold an emoji pictograph. Write words ("12 STARS",
	"LOCKED: REBIRTH 3", "EQUIPPED"), or draw a small mark from Frames (the
	Vault's owned tick, the rebirth rows' dots).

	What counts as an emoji (isEmoji):
	  U+1F000-U+1FAFF  the pictograph blocks (faces, objects, transport,
	                   flags, the supplements) and their neighbours
	  U+2600-U+27BF    Misc Symbols and Dingbats, except the plain text
	                   symbols in TEXT_SYMBOLS (the cleaning grade's stars,
	                   the sparkle): the rest render as emoji on phones
	  EXTRA            single emoji outside those blocks: U+2B50 star,
	                   U+FE0F (the "show as emoji" selector), the zero-width
	                   joiner and the keycap of emoji sequences, the clocks
	                   and media buttons, the coloured squares and circle
	Arrows (U+2190-2193), the middle dot and the like are ordinary text.

	FILE_ALLOWED could let one file keep one emoji; it is empty (the machine
	billboards' power line is words since 2026-10-21). Any emoji fails the
	spec, wherever it comes back.
]]
return function(T, Loader)
	local fs = require("@lune/fs")

	-- plain text symbols the fonts draw as text (kept on purpose)
	local TEXT_SYMBOLS: { [number]: string } = {
		[0x2605] = "BLACK STAR (cleaning grade, rebirth moment)",
		[0x2606] = "WHITE STAR (cleaning grade)",
		[0x2726] = "BLACK FOUR POINTED STAR (sparkles)",
	}

	-- single emoji outside the two big ranges: { first, last }
	local EXTRA_RANGES = {
		{ 0x2B50, 0x2B50 }, -- white medium star (the emoji star)
		{ 0x2B55, 0x2B55 }, -- heavy large circle
		{ 0x2B05, 0x2B07 }, -- the emoji arrows left / up / down
		{ 0x2B1B, 0x2B1C }, -- large black / white square
		{ 0xFE0F, 0xFE0F }, -- variation selector 16: "draw the one before as emoji"
		{ 0x200D, 0x200D }, -- zero-width joiner (emoji sequences)
		{ 0x20E3, 0x20E3 }, -- combining keycap
		{ 0x231A, 0x231B }, -- watch, hourglass
		{ 0x2328, 0x2328 }, -- keyboard
		{ 0x23CF, 0x23CF }, -- eject
		{ 0x23E9, 0x23F3 }, -- media buttons, alarm clock, timers
		{ 0x23F8, 0x23FA }, -- pause, stop, record
		{ 0x25AA, 0x25AB }, -- small black / white square
		{ 0x25B6, 0x25B6 }, -- play button
		{ 0x25C0, 0x25C0 }, -- reverse button
		{ 0x25FB, 0x25FE }, -- medium squares
		{ 0x2934, 0x2935 }, -- curved arrows
		{ 0x3030, 0x3030 }, -- wavy dash
		{ 0x303D, 0x303D }, -- part alternation mark
		{ 0x3297, 0x3297 }, -- circled ideograph congratulation
		{ 0x3299, 0x3299 }, -- circled ideograph secret
	}
	local EXTRA: { [number]: boolean } = {}
	for _, range in EXTRA_RANGES do
		for cp = range[1], range[2] do
			EXTRA[cp] = true
		end
	end

	-- path (from the project root) -> the emoji that file may keep
	-- (empty: the machine billboards say "Power 100%" / "+40 power" in words since 2026-10-21)
	local FILE_ALLOWED: { [string]: { [number]: boolean } } = {}

	local function isEmoji(cp: number): boolean
		if cp >= 0x1F000 and cp <= 0x1FAFF then
			return true
		elseif cp >= 0x2600 and cp <= 0x27BF then
			return TEXT_SYMBOLS[cp] == nil
		end
		return EXTRA[cp] == true
	end

	-- "[" "="* "[" at `at` (a long string or comment): its level and the index after it
	local function longOpen(source: string, at: number): (number?, number)
		local eqs = string.match(source, "^%[(=*)%[", at)
		if eqs then
			return #eqs, at + #eqs + 2
		end
		return nil, at
	end

	-- the end of the long bracket of `level` that starts its content at `from` (or the end of the file)
	local function longEnd(source: string, level: number, from: number): number
		local close = "]" .. string.rep("=", level) .. "]"
		local _, e = string.find(source, close, from, true)
		return e or #source
	end

	local function blank(text: string): string
		local spaces = string.gsub(text, "[^\n]", " ")
		return spaces
	end

	--[=[
		The code of a Luau source with every comment ("-- ..." and the long
		"--[[ ... ]]" / "--[==[ ... ]==]") blanked to spaces. Strings ("...",
		'...', `...`, [[...]]) are kept whole, so a "--" inside one is no
		comment. Newlines stay: a line number of the result is the file's.
	]=]
	local function code(source: string): string
		local parts: { string } = {}
		local n = #source
		local copied = 1 -- source[copied..] is not in parts yet
		local i = 1
		while true do
			local at = string.find(source, "[%-\"'`%[]", i)
			if not at then
				break
			end
			local c = string.sub(source, at, at)
			if c == "-" then
				if string.sub(source, at + 1, at + 1) == "-" then
					local level, after = longOpen(source, at + 2)
					local stop = if level then longEnd(source, level, after) else (string.find(source, "\n", at, true) or n + 1) - 1
					table.insert(parts, string.sub(source, copied, at - 1))
					table.insert(parts, blank(string.sub(source, at, stop)))
					copied = stop + 1
					i = stop + 1
				else
					i = at + 1
				end
			elseif c == "[" then
				local level, after = longOpen(source, at)
				i = if level then longEnd(source, level, after) + 1 else at + 1
			else
				-- a quoted string: up to its closing quote (backslash escapes), or the line's end
				local j = at + 1
				while j <= n do
					local d = string.sub(source, j, j)
					if d == "\\" then
						j += 2
					elseif d == c or (d == "\n" and c ~= "`") then
						break
					else
						j += 1
					end
				end
				i = j + 1
			end
		end
		table.insert(parts, string.sub(source, copied, n))
		return table.concat(parts)
	end

	type Hit = { Line: number, Code: number }

	-- The emoji left in a file's code (FILE_ALLOWED applies to `path`).
	local function scan(path: string, source: string): { Hit }
		local allowed = FILE_ALLOWED[path] or {}
		local hits: { Hit } = {}
		for lineNo, line in string.split(code(source), "\n") do
			if string.find(line, "[\128-\255]") then
				local ok = pcall(function()
					for _, cp in utf8.codes(line) do
						if isEmoji(cp) and not allowed[cp] then
							table.insert(hits, { Line = lineNo, Code = cp })
						end
					end
				end)
				if not ok then
					table.insert(hits, { Line = lineNo, Code = -1 }) -- not valid UTF-8
				end
			end
		end
		return hits
	end

	local function walk(dir: string, out: { string })
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path, out)
			elseif string.match(entry, "%.luau$") then
				table.insert(out, path)
			end
		end
	end

	T.test("NoEmoji: no emoji in any src file's code (words or drawn marks only)", function()
		local found: { string } = {}
		walk(Loader.root .. "/src", found)
		T.truthy(#found > 100, "the walk found the sources")
		local bad: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, full in found do
			local rel = string.sub(full, #Loader.root + 2)
			seen[rel] = true
			for _, hit in scan(rel, fs.readFile(full)) do
				local what = if hit.Code < 0 then "not valid UTF-8" else string.format("U+%04X %s", hit.Code, utf8.char(hit.Code))
				table.insert(bad, `{rel}:{hit.Line}: {what}`)
			end
		end
		table.sort(bad)
		T.truthy(#bad == 0, `emoji in player text (the owner: no emoji, text only):\n      {table.concat(bad, "\n      ")}\n     `)
		-- the allow-list names real files (a rename must not leave a stale exception)
		for path in FILE_ALLOWED do
			T.truthy(seen[path], path .. " exists")
		end
	end)

	T.test("NoEmoji: the scan sees emoji in strings, never in comments", function()
		local star, bolt, gear, vs16 = utf8.char(0x2B50), utf8.char(0x26A1), utf8.char(0x2699), utf8.char(0xFE0F)
		local lines = {
			`local a = "{star} 12"`, -- 1: a string
			`-- {star} a comment`, -- 2
			`--[[ {star}`, -- 3: a block comment
			`  {star} ]] local b = '{star}'`, -- 4: code after it
			`local c = 1 -- {star}`, -- 5: a trailing comment
			`local d = [[{star}]] .. "--" .. "{star}"`, -- 6: a long string, a "--" in a string
			`local e = \`x \{n} {star}\``, -- 7: an interpolated string
			`--[==[ {star} ]] {star} ]==] local f = 2`, -- 8: a level-2 block comment
		}
		local hits = scan("src/sample.luau", table.concat(lines, "\n"))
		local onLines = {}
		for _, hit in hits do
			table.insert(onLines, hit.Line)
		end
		T.eq(table.concat(onLines, ","), "1,4,6,6,7", "the strings' emoji, not the comments'")
		-- the plain text symbols stay; every emoji form fails
		local plain = utf8.char(0x2605, 0x2606, 0x2726, 0x2192, 0x00B7)
		T.eq(#scan("src/x.luau", `local s = "{plain}"`), 0, "stars, sparkle, arrow, dot are text")
		T.eq(#scan("src/x.luau", `local s = "{gear}{vs16} SETTINGS"`), 2, "a symbol + VS16: both")
		T.eq(#scan("src/x.luau", `local s = "{utf8.char(0x1F512)} REBIRTH 1"`), 1, "a lock pictograph")
		T.eq(#scan("src/x.luau", `local s = "{utf8.char(0x2713)}"`), 1, "the check mark (drawn from Frames instead)")
		-- no file keeps an emoji any more: the machine billboards say "Power 100%" in words
		T.eq(#scan("src/client/UI/MachineBillboard.luau", `local s = "{bolt} 100%"`), 1, "MachineBillboard's power line is words now")
		T.eq(#scan("src/client/Controllers/MachineFxController.luau", `local s = "{bolt}"`), 1, "MachineFxController too")
		T.eq(#scan("src/client/UI/HudView.luau", `local s = "{bolt} 100%"`), 1, "the sign anywhere else fails")
	end)
end
