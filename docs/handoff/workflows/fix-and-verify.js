export const meta = {
  name: 'fix-step-c-round2',
  description: 'Fix the 12 confirmed findings of the step c re-review (chisel resume, camera FOV, bot lower bound, touch tolerance, prompts, polish feedback...) in a worktree, then adversarially verify',
  phases: [
    { title: 'Fix', detail: 'one luau-dev in a worktree implements all fixes + tests' },
    { title: 'Verify', detail: 'qa-tester tries to break the fixes; fixer applies confirmed problems' },
  ],
}

const TOOLS = `export PATH=<TOOLS_BIN>:$PATH`
const COMMON = `
Project: TERRA FORGE (Roblox, Luau, Rojo). Cleaning Station minigame code: src/shared/Cleaning/{CleaningScoring,CleaningPatterns,Geometry2D}.luau,
src/client/Cleaning/{ChiselStep,ScrapeStep,PolishStep,PointerInput,CameraFit}.luau, src/client/Controllers/CleaningController.luau,
src/client/UI/CleaningView.luau, src/shared/Builders/OreShellBuilder.luau, src/server/Services/CleaningService.luau, tests/Cleaning.spec.luau.
Checks: \`${TOOLS}; bash tools/check.sh\` (strict luau-lsp, Lune tests, place build). Never start a Luau line with "(".
Another team is rewriting src/server/Services/CleaningService.luau in parallel (step d core runtime). Keep your edits to that file SMALL and
self-contained (a few hunks) so they merge easily; put logic in shared modules (CleaningScoring) where possible.
Do NOT commit build/TerraForge.rbxl (\`git checkout -- build/TerraForge.rbxl\` before committing). Commit (never push) with message ending:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015FhtpEMnYae51vfkaDdPiU`

const RESULT = {
  type: 'object',
  properties: {
    summary: { type: 'string' }, commit: { type: 'string' }, checksPassed: { type: 'boolean' },
    perFinding: { type: 'array', items: { type: 'string' }, description: 'one line per finding: what you did (or why not)' },
    studioTests: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'commit', 'checksPassed', 'perFinding'],
}

phase('Fix')
const fix = await agent(`${COMMON}

You work in your own git worktree. Read the 12 confirmed review findings in
<SCRATCHPAD>/qa_c2_findings.txt (each has problem, scenario, proposed fix and
a verifier note; the reviewers' Lune simulation scripts are in <SCRATCHPAD>/qa2/ and
you may reuse them). Fix ALL of them. Decisions already made by the lead:
1. Chisel resume: use the reviewers' deferred-restart design (no reset on release; on the next press, restart only if the press is far from
   the groove tip or off the line). Also: once a cut started, hide the end marker it started from and pulse a "continue here" marker at the
   groove tip; play scratch/dust/sparks only when progress increased or the pointer is within tol*4 of the tip; otherwise hint
   "Continue from the glowing tip!" (max once per 0.8 s). Client and server must replay identically (server replays recorded samples).
2. Camera: keep the pre-cleaning camera CFrame/FOV at module level so a quick restart never saves a half-restored camera.
3. Bot lower bound: shared CleaningScoring.ClientPauses constants used by BOTH the client waits and the server timeline check (minimum gaps
   between steps/cuts, first sample >= intro), and onSubmit requires latest + 0.6 <= elapsed. Add tests: a compressed bot payload is
   rejected, padded honest timelines pass. Update docs/QA_REPORTS.md wording (a bot needs at least as long as a perfect player through the
   real client; a perfect synthetic run can't be told apart = accepted risk).
4. Crystal omission: option (b): docs only (accepted risk), as the verifier recommends.
5. Touch tolerance: raise CleaningScoring.InputLeniency.Touch to 2.0 (Gamepad 1.4). Add the reviewers' Lune wobble test (phone at ~105 pt
   per face unit, 8 pt RMS AR(1) wobble, 60 seeds: Mythic reaches Clean or better in >= 80% of seeds).
6. Prompts: Exclusivity AlwaysShow on both station prompts; Take Ore Back uses G / ButtonB... BUT ButtonB is also Leave in the minigame
   (only bound during the minigame, so OK) — check InteractController/PromptController for conflicts and pick free keys; update comments.
7. Polish feedback: needle reflects true speed (time-window average), "Slower!"/"Faster!" hints with cooldown, demo dot at mid-band speed,
   instruction mentions keeping the needle in the green; consider PolishBand.Max ~10.5 (justify with the reviewer simulation).
8. Fragile dirt: remove the FragileDirt look-alike (or make it a clearly different pale ring smaller than 2*FragileRadius) and make the
   crystal shard stick out and glow so it reads on a phone.
9. Leave: hide Leave and unbind B/Backspace during the reveal; show "(B)"/"(A)" labels for gamepad; first Leave press after a finished
   cut asks to press again within 2 s ("your ore stays in the vise").
10. Rub toggle: rename to "Easy polish: ON/OFF" with the key hint, and show "Easy polish: max 75% shine" the first time it affects scoring.
11. Chisel tool: make it semi-transparent (or lean away from the travel direction) while pressed so it never hides the dots ahead.
Keep everything else working (run all tests; update tests/Cleaning.spec.luau and add new specs). Re-render the cleaning previews to check
visuals: \`ln -sfn /home/user/Perfect-Tap/tools/preview/node_modules tools/preview/node_modules\`, then for each stage
\`lune run tools/lune/export_scene.luau cleaning Gold chisel\` (stages chisel/scrape/polish; add "phone" as 4th arg for the phone layout;
"Solarite reveal" for the reveal) and \`node tools/preview/render.mjs x clean_chisel clean_scrape clean_polish clean_reveal clean_chisel_phone\`,
then look at build/preview/shots/*.jpg (update tools/lune/export_scene.luau if labels changed). Commit and report per finding.`,
  { label: 'fix step c', phase: 'Fix', agentType: 'luau-dev', isolation: 'worktree', schema: RESULT })
if (!fix) throw new Error('fix failed')

phase('Verify')
const verdict = await agent(`You are a skeptical QA tester for TERRA FORGE (Roblox/Luau). In a scratch checkout, inspect commit ${fix.commit}
(\`git -C /home/user/Perfect-Tap show --stat ${fix.commit}\`, \`git -C /home/user/Perfect-Tap diff ${fix.commit}~1 ${fix.commit}\`; to run things,
\`git -C /home/user/Perfect-Tap worktree add <SCRATCHPAD>/verify_c2 ${fix.commit}\` and work there;
${TOOLS}; bash tools/check.sh). The commit claims to fix the findings in
<SCRATCHPAD>/qa_c2_findings.txt. The fixer's report:
${fix.perFinding.map((s) => '- ' + s).join('\n')}
For each finding, verify it is really fixed (re-run the reviewers' Lune simulations in scratchpad/qa2/ against the new code where
possible) and look for NEW bugs the fix introduced: client/server divergence (any way client tracker state differs from the server replay),
honest players rejected by the new timeline lower bounds (check every client wait really is >= the constants, including high latency and
low FPS), runtime errors, CAS binding leaks, prompt key conflicts. Report only concrete, verified problems. Remove the scratch worktree when done
(\`git -C /home/user/Perfect-Tap worktree remove --force <path>\`).`,
  { label: 'verify fixes', phase: 'Verify', agentType: 'qa-tester', schema: {
    type: 'object', properties: {
      problems: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, file: { type: 'string' }, detail: { type: 'string' }, fix: { type: 'string' } }, required: ['title', 'detail', 'fix'] } },
      notFixed: { type: 'array', items: { type: 'string' } },
    }, required: ['problems', 'notFixed'] } })

let final = fix
if (verdict && (verdict.problems.length > 0 || verdict.notFixed.length > 0)) {
  const again = await agent(`${COMMON}

You work in your own git worktree: first run \`git checkout -B stepc-fix2 ${fix.commit}\`. A QA tester verified the previous fix commit and found:
Problems:\n${verdict.problems.map((p) => `- ${p.title} (${p.file || ''}): ${p.detail}\n  fix: ${p.fix}`).join('\n')}
Not fixed:\n${verdict.notFixed.map((s) => '- ' + s).join('\n')}
Fix them all, run tools/check.sh, commit and report.`,
    { label: 'fix again', phase: 'Verify', agentType: 'luau-dev', isolation: 'worktree', schema: RESULT })
  if (again && again.checksPassed) final = again
}
return { firstCommit: fix.commit, finalCommit: final.commit, checks: final.checksPassed, perFinding: fix.perFinding, verdict, studioTests: final.studioTests || fix.studioTests }
