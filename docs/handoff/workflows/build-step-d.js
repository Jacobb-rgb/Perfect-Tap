export const meta = {
  name: 'build-step-d',
  description: 'Implement Terra Forge step d (machines, conveyors, build mode, storage, selling, anvil) from docs/plans/STEP_D_PLAN.md: contracts -> core -> 5 parallel packages in worktrees -> integration',
  phases: [
    { title: 'Contracts', detail: 'P0: configs, Net, data, pure shared logic, models, tests' },
    { title: 'Core', detail: 'P1: items, machine lifecycle, intake router, client hooks' },
    { title: 'Features', detail: '5 packages in parallel, each in its own worktree' },
    { title: 'Integrate', detail: 'merge the 5 branches, fix integration errors, rebake, docs' },
  ],
}

const PATHS = `export PATH=<TOOLS_BIN>:$PATH`
const COMMON = `
You are implementing part of TERRA FORGE, an original Roblox mining/crafting game in Luau (Rojo project). The full step d plan is in
docs/plans/STEP_D_PLAN.md (read the Summary, the Contracts section, the Modules sections for your files, the Remotes, Data changes, Risks
and Tests sections, and your work package). The plan's file paths are written as /home/user/Perfect-Tap/...; if you work in a git worktree,
use the same paths relative to your working directory instead. The game design is in docs/GAME_DESIGN.md.
Approved design decisions: all of the plan's items A-K are approved as written.
Rules:
- Only edit the files your package OWNS (plus brand-new test files for your own modules). If you need something from a file you don't own,
  work around it and report it under "requests".
- Follow the existing code style: ModuleScripts with init()/start(), strict Luau types (the project runs luau-lsp in strict mode),
  server-authoritative logic, Net remotes with rate limits, plain-English comments matching the codebase density, everything original.
- Never start a line with "(" (Luau ambiguous-syntax error); use a local variable instead.
- Lune specifics for tests: the virtual Roblox tree loader is tools/lune/lib/loader.luau; tests live in tests/*.spec.luau (see existing ones).
  Under Lune there is no .Position on CFrame-less objects (use .CFrame.Position) and CFrame.lookAt must come from Loader.CFrame.
- Checks: run \`${PATHS}; bash tools/check.sh\` (strict type analysis, all Lune tests, place build + bake). It must pass before you finish.
  You can also run just the tests with \`lune run tools/lune/test.luau\`.
- When done, commit your work with git (do NOT push). End the commit message with these two lines:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_015FhtpEMnYae51vfkaDdPiU
- Report honestly: list every place where you deviated from the plan's contracts (names, signatures, payloads, attributes, data fields),
  because other implementers build against those contracts.`

const RESULT = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    commit: { type: 'string', description: 'full hash of your final commit' },
    branch: { type: 'string', description: 'git branch you committed on (git rev-parse --abbrev-ref HEAD)' },
    workdir: { type: 'string', description: 'absolute path of the working directory you used' },
    checksPassed: { type: 'boolean' },
    checkOutputTail: { type: 'string', description: 'last lines of tools/check.sh output' },
    deviations: { type: 'array', items: { type: 'string' }, description: 'every deviation from the plan contracts' },
    requests: { type: 'array', items: { type: 'string' }, description: 'changes needed in files you do not own' },
    studioTests: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'commit', 'branch', 'workdir', 'checksPassed', 'deviations', 'requests'],
}

function pkgPrompt(name, extra) {
  return `${COMMON}\n\nYOUR PACKAGE: "${name}" (see "### ${name}" under "## Work packages" in docs/plans/STEP_D_PLAN.md).\n${extra || ''}`
}

phase('Contracts')
const p0 = await agent(pkgPrompt('P0 Contracts (configs, Net, data, pure shared logic, models, tests)', `
You work directly in /home/user/Perfect-Tap on branch claude/keen-wozniak-mx7azn. Nobody else edits files right now except read-only reviewers.
The pure shared modules (Grid, Placement, ConveyorLogic, MachineLogic) are the backbone: make their APIs exactly match the Contracts section,
and give them thorough Lune tests (including the conservation fuzz test for MachineLogic and idempotent migration tests). Keep the existing
Cleaning Station working (its OrePoint/CamPoint must not move). WorldBuilder.Version goes to 3 so the map rebuilds; tools/check.sh rebakes
build/TerraForge.rbxl, commit it too.`), { label: 'P0 contracts', phase: 'Contracts', agentType: 'luau-dev', schema: RESULT })
if (!p0) throw new Error('P0 failed')
log(`P0 done: ${p0.commit} checks=${p0.checksPassed}`)

const p0notes = `P0 (contracts) is already committed (${p0.commit}). Its summary: ${p0.summary}\nP0 deviations from the plan: ${JSON.stringify(p0.deviations)}\nP0 requests to others: ${JSON.stringify(p0.requests)}`

phase('Core')
const p1 = await agent(pkgPrompt('P1 Core runtime (items, machine lifecycle, intake router, client hooks)', `
You work directly in /home/user/Perfect-Tap on branch claude/keen-wozniak-mx7azn.
${p0notes}
You own the ORDER lists in src/server/init.server.luau and src/client/init.client.luau: add EVERY service/controller of step d now
(BuildService, ProcessingService, EconomyService, StorageService, SellService, ConveyorService, AnvilService, IntakeService; client
PlacementController, MachineFxController, StorageController, SellController, AnvilController), and make the init scripts skip a module
that does not exist yet with a warning (the feature packages create them later). Keep the Cleaning Station fully working with the new
MachineService behaviour API (CleaningService must use IntakeService for its vise intake if the plan says so).`), { label: 'P1 core', phase: 'Core', agentType: 'luau-dev', schema: RESULT })
if (!p1) throw new Error('P1 failed')
log(`P1 done: ${p1.commit} checks=${p1.checksPassed}`)

const baseNotes = `${p0notes}\nP1 (core runtime) is committed on top (${p1.commit}). Its summary: ${p1.summary}\nP1 deviations: ${JSON.stringify(p1.deviations)}\nP1 requests: ${JSON.stringify(p1.requests)}`

phase('Features')
const PACKAGES = [
  { name: 'WP-Build Build mode (server authority + client placement)', extra: 'The build camera, ghost, rotate, place/move/pickup must work on PC (B key), phone (BUILD button, tap a cell then a big Place button) and gamepad (D-pad Up). Mobile performance matters (grid overlay must be cheap).' },
  { name: 'WP-Process Processing machines and machine juice', extra: 'Clay Furnace, Blast Furnace, Crusher, Auto Cleaner (capped grades) with queues, timers (Bellows), output emit/back-pressure, glow/hum/progress billboard. Machine contents persist in the placed entry In/Out.' },
  { name: 'WP-StorageSell Storage Crate, selling, economy entry point', extra: 'Pell\'s SellBin/SellCounter in town, the Sell Chute (pays the item owner), the Storage Crate with a count sign and a take-out UI, EconomyService.award. Selling must be satisfying (+N popups, coin burst) and safe (no double sell).' },
  { name: 'WP-Conveyor Belts', extra: 'Belts move loose items, hand them to machines via IntakeService belt handler, players walk through belts, corners do not snag, cheap on mobile.' },
  { name: 'WP-Anvil Anvil forging', extra: 'Ingots onto the anvil, Forge prompt, choose a recipe, tap to hammer (every tap counts, timing only changes PERFECT/GOOD juice), server validates strikes, gear pops out. Works on PC, phone and gamepad.' },
]

const features = await parallel(PACKAGES.map((p) => () => agent(pkgPrompt(p.name, `
You work in your OWN git worktree (a separate copy of the repo created from the latest commit, which already contains P0 and P1).
Commit on your worktree's branch; another agent merges all packages afterwards. Other packages are being built at the same time in
other worktrees, so services from other packages may be missing in your copy: the init scripts skip missing modules.
${baseNotes}
Package focus: ${p.extra}`), { label: p.name.split(' ')[0], phase: 'Features', agentType: 'luau-dev', isolation: 'worktree', schema: RESULT })))

const done = features.map((r, i) => ({ name: PACKAGES[i].name, result: r }))
const ok = done.filter((d) => d.result)
log(`${ok.length}/${PACKAGES.length} feature packages finished`)

phase('Integrate')
const integration = await agent(`${COMMON}

YOUR JOB: INTEGRATOR (merge and finish step d). Work in /home/user/Perfect-Tap on branch claude/keen-wozniak-mx7azn (it already has P0 + P1).
Five feature packages were built in separate git worktrees. Merge each package's commit into the branch with \`git merge --no-ff <commit>\`
(the commits live in the same repository; if a hash isn't found, look at \`git worktree list\` and \`git branch -a\`). Resolve conflicts
carefully (they should be rare: packages own separate files). Then run tools/check.sh and fix every integration problem (type errors,
mismatched contracts between packages, missing registrations, failing tests). You may edit any file now, but keep fixes minimal and
consistent with the plan. Then do the WP-Docs/QA package: update docs/PLAN.md and docs/STUDIO_CHECKLIST.md for step d (QA_REPORTS gets a
step d section with what is built and what to test in Studio), make sure build/TerraForge.rbxl is rebaked, commit, and report.

Packages to merge:
${done.map((d) => `- ${d.name}: ${d.result ? `commit ${d.result.commit} (branch ${d.result.branch}, worktree ${d.result.workdir}), checks passed=${d.result.checksPassed}\n  summary: ${d.result.summary}\n  deviations: ${JSON.stringify(d.result.deviations)}\n  requests: ${JSON.stringify(d.result.requests)}` : 'FAILED (no result): implement what is missing yourself if feasible, otherwise report it'}`).join('\n')}

Base notes:
${baseNotes}`, { label: 'integrate', phase: 'Integrate', agentType: 'luau-dev', schema: RESULT })

return {
  p0: { commit: p0.commit, checks: p0.checksPassed, deviations: p0.deviations, requests: p0.requests },
  p1: { commit: p1.commit, checks: p1.checksPassed, deviations: p1.deviations, requests: p1.requests },
  features: done.map((d) => ({ name: d.name, ok: !!d.result, commit: d.result && d.result.commit, checks: d.result && d.result.checksPassed, deviations: d.result && d.result.deviations, requests: d.result && d.result.requests, studioTests: d.result && d.result.studioTests })),
  integration,
}
