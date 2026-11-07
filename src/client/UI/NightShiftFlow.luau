--[[
	NightShiftFlow: the crate's little state machine in the Night Shift window
	(pure, specced; NightShiftController drives it). A prize is never lost: while
	Open Crate waits for the server the window can't be closed by its own buttons;
	a late answer still shows, and a refusal never overwrites a prize.
]]

local NightShiftFlow = {}

export type State = { Opening: boolean, Token: number, Prize: boolean }

function NightShiftFlow.new(): State
	return { Opening = false, Token = 0, Prize = false }
end

-- The window opens for a new return.
function NightShiftFlow.show(s: State)
	s.Opening = false
	s.Prize = false
	s.Token += 1
end

function NightShiftFlow.mayPress(s: State): boolean
	return not s.Opening and not s.Prize
end

-- Open Crate pressed: the token for its timeout.
function NightShiftFlow.press(s: State): number
	s.Opening = true
	s.Token += 1
	return s.Token
end

-- The answer didn't come in time (a dropped request): true if the button comes back.
function NightShiftFlow.timeout(s: State, token: number): boolean
	if token == s.Token and s.Opening then
		s.Opening = false
		return true
	end
	return false
end

function NightShiftFlow.mayClose(s: State): boolean
	return not s.Opening
end

-- The server's answer: "Prize" (show it, also if the window was closed by now), "Nothing"
-- (refused, nothing shown yet: no crate waits) or "Ignore" (a refusal after a prize).
function NightShiftFlow.answer(s: State, result: any): string
	s.Opening = false
	s.Token += 1
	if type(result) == "table" and result.Ok == true then
		s.Prize = true
		return "Prize"
	end
	return if s.Prize then "Ignore" else "Nothing"
end

return NightShiftFlow
