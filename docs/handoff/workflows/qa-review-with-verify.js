export const meta = {
  name: 'qa-step-c-fixes',
  description: 'Re-review the step c QA fixes (diff 0417277..7284d00) for regressions, plus the design-brief review that never ran; each finding adversarially verified',
  phases: [
    { title: 'Review', detail: '3 qa-tester reviewers on the fix diff' },
    { title: 'Verify', detail: 'a skeptic per reviewer tries to refute each finding' },
  ],
}

const CONTEXT = `
Project: TERRA FORGE, a Roblox game in Luau (Rojo) at /home/user/Perfect-Tap. src/shared -> ReplicatedStorage.Shared,
src/server -> ServerScriptService.Server, src/client -> StarterPlayerScripts.Client.
The Cleaning Station minigame (chisel -> scrape -> polish -> reveal, grades Rough/Clean/Pristine/Flawless) was reviewed and then fixed.
The fixes are in git: run \`git diff 0417277 7284d00 -- src tests\` to see them. The original findings are in docs/qa/step_c_findings.txt
and the summary of what was fixed is in docs/QA_REPORTS.md (section "Step c").
Key changes: CleaningScoring.ScrapeTracker (scrape now sends brush positions that changed something; server replays them),
CleaningScoring.timeline + CleaningService.onSubmit (all timestamps must fit the real session time, steps in order),
ChiselStep (only samples after the cut started are recorded; false start reset on release; chips of abandoned attempts removed),
PolishStep (shared polishScore, rub toggle on R/ButtonY), CleaningController (CameraFit, compact layout, backpack hidden,
CleanBegin while active -> CleanCancel, camera reset guard), PointerInput (initial kind from GetLastInputType),
CleaningView (touch sizes, setCompact), Vfx FineDust, MachineService.register catch-up, CameraFit module + tests.
Checks: export PATH=<TOOLS_BIN>:$PATH; cd /home/user/Perfect-Tap; bash tools/check.sh
You may write throwaway Lune scripts ONLY under <SCRATCHPAD>/qa2/ (see tests/*.spec.luau and
tools/lune/lib/loader.luau for loading modules). Do NOT edit repo files. Report only concrete problems with file + line and a realistic scenario.`

const DIMENSIONS = [
  { key: 'fix-regressions', prompt: `Dimension: REGRESSIONS AND BUGS INTRODUCED BY THE FIXES. Read the whole diff line by line. Look for runtime errors (nil access,
wrong field names e.g. submission.Scrape shape mismatches between client/server/tests, RubToggle.Parent usage), client-server divergence (any way the
client's ScrapeTracker/CutTracker state can differ from the server replay of the recorded samples: e.g. samples recorded vs fed, resetAttempt
timing, chips accounting, timeline ordering for honest play: can an honest client ever produce out-of-order timestamps, e.g. scrape sample t before
the last cut sample t, or polish before scrape?), CameraFit math sign errors, CAS bindings leaking, and anything that would make an honest player fail.
Prove claims with a Lune simulation where possible.` },
  { key: 'exploits-after-fix', prompt: `Dimension: ANTI-CHEAT AFTER THE FIX. Try to break the new server checks as an exploiter who controls the client: can a bot
still get Flawless faster than a careful human (timeline check, slack, CleaningMinSeconds, ordering), forge the scrape samples to skip crystals or
dirt, overflow sizes, send NaN/huge numbers to the new code paths (ScrapeTracker, timeline), or crash/lag the server (payload size limits, loops)?
Also check whether honest high-latency mobile players could fail the timeline check (client clock starts on CleanBegin receipt).` },
  { key: 'design-brief', prompt: `Dimension: GAME DESIGN / BRIEF COMPLIANCE AND UX FLOW (this review never ran before). The brief: step-by-step tactile cleaning
like Fishing Chef's rib cutting; chisel along guide lines -> scrape -> polish; quality grades Rough/Clean/Pristine/Flawless; chips when off the line but
NEVER a hard fail; juice (feedback text, shake, sounds, particles); a satisfying reveal; harder for rarer ores (check Rarity.luau parameters scale
difficulty sensibly and remain doable for Mythic); an Auto Cleaner later capped at a lower max grade. Walk the full flow as a fresh 10-year-old
player on PC, phone and controller: getting raw ore into the station (prompt or throwing into the vise), instructions clarity, cancel/retry,
can they always recover their ore, is grade tuning sensible (could an average honest player reach Clean/Pristine?). Put up to 10 manual Studio
tests in "studioTests".` },
]

const FINDINGS = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' }, title: { type: 'string' }, severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
      file: { type: 'string' }, line: { type: 'number' }, problem: { type: 'string' }, scenario: { type: 'string' }, fix: { type: 'string' },
    }, required: ['id', 'title', 'severity', 'file', 'problem', 'scenario', 'fix'] } },
    studioTests: { type: 'array', items: { type: 'string' } },
  },
  required: ['findings'],
}
const VERDICTS = {
  type: 'object',
  properties: { verdicts: { type: 'array', items: { type: 'object', properties: {
    id: { type: 'string' }, real: { type: 'boolean' }, severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    reason: { type: 'string' }, fix: { type: 'string' },
  }, required: ['id', 'real', 'severity', 'reason'] } } },
  required: ['verdicts'],
}

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(`${CONTEXT}\n\n${d.prompt}`, { label: `review:${d.key}`, phase: 'Review', agentType: 'qa-tester', schema: FINDINGS }),
  (review, d) => {
    if (!review || !review.findings || review.findings.length === 0) {
      return { key: d.key, findings: [], verdicts: [], studioTests: (review && review.studioTests) || [] }
    }
    const list = review.findings.map((f) => `- id=${f.id} [${f.severity}] ${f.title}\n  file: ${f.file}:${f.line ?? '?'}\n  problem: ${f.problem}\n  scenario: ${f.scenario}\n  fix: ${f.fix}`).join('\n')
    return agent(`${CONTEXT}\n\nYou are a skeptical second reviewer. For EACH finding below (dimension "${d.key}"), open the code and try hard to REFUTE it:
is the path reachable in Roblox, does the scenario really fail, is it handled elsewhere, is the severity right? real=false if wrong, handled,
theoretical or style. real=true only with concrete evidence. Refine the fix if needed.\n\nFindings:\n${list}`,
      { label: `verify:${d.key}`, phase: 'Verify', agentType: 'qa-tester', schema: VERDICTS })
      .then((v) => ({ key: d.key, findings: review.findings, verdicts: (v && v.verdicts) || [], studioTests: review.studioTests || [] }))
  },
)

const confirmed = [], rejected = [], studioTests = []
for (const r of results.filter(Boolean)) {
  studioTests.push(...r.studioTests)
  for (const f of r.findings) {
    const v = r.verdicts.find((x) => x.id === f.id)
    if (!v) confirmed.push({ ...f, dimension: r.key, verified: false })
    else if (v.real) confirmed.push({ ...f, dimension: r.key, severity: v.severity || f.severity, verifierReason: v.reason, fix: v.fix || f.fix, verified: true })
    else rejected.push({ id: f.id, dimension: r.key, title: f.title, reason: v.reason })
  }
}
log(`${confirmed.length} confirmed, ${rejected.length} refuted`)
return { confirmed, rejected, studioTests }
