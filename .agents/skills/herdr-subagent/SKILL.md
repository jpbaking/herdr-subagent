---
name: herdr-subagent
description: Delegate a task to an interactive agent CLI (opencode by default; also agy, codex, claude) running in a visible herdr pane or tab, as a pseudo-subagent that reports back through a compact report file in a temp directory, stays open so the planner can review and steer it in the same session, and is closed after acceptance. Use when the user asks for the herdr-subagent skill, a herdr or visible subagent, a pseudo-subagent, to delegate to opencode (or another CLI) in herdr, or when a Goal Ledger planner delegates a phase and wants the executor visible in herdr. Not for in-process subagents, not for headless one-shot CLI runs, and not outside herdr (HERDR_ENV unset).
---

# herdr pseudo-subagent

Run a delegate agent as a real interactive CLI session in a herdr pane, so the
user can watch it while the planner (you) reads only a compact report file.
The session stays open through review, so you can steer it with follow-up
prompts that keep its context, and you close it once you accept the result.

Any planner harness that can run shell commands inside herdr can use this
skill. All mechanics go through `scripts/herdr-subagent.sh` in this skill's
directory, which needs bash and `jq`. Run it by its absolute path. Per-harness behavior and known issues
are in [references/harnesses.md](references/harnesses.md); read the section
for the kind you are about to use.

## Inputs

Determine these from the request. Ask only for what you cannot determine.

1. **Task**: a self-contained description, or a Goal Ledger phase ID.
2. **Kind**: the agent CLI. Default `opencode`. Supported: `opencode`,
   `agy`, `codex`, `claude`. The script refuses other kinds.
3. **Model**: the CLI's configured default. Pass a model flag only when the
   user names a model.
4. **Layout**: `split` (a pane to the right of yours) by default. Use `tab`
   when more than one delegate session will be open at the same time, or when
   the user asks for tabs.
5. **Concurrency limit**: follow the user's stated limit. If none is known,
   allow one running delegate per model backend. Delegates on the same
   backend, such as two CLIs pointed at one local model server, count
   together. Never exceed a limit to save time; queue the work instead.

## Preflight

Stop and tell the user if any check fails.

- `HERDR_ENV` is set (you are inside herdr), and `herdr` and `jq` are on PATH.
- The kind's CLI is installed and, where it needs one, signed in (see the
  harness notes; `agy` needs a one-time interactive sign-in).
- Run the script's `list` command. Count running delegates against the
  concurrency limit. Reuse an existing idle session for related follow-up work
  instead of spawning a new one.

## Lifecycle

1. **Name it** `sub-<short-task>`, using only letters, digits, `.`, `_` and `-`.
2. **Spawn**: run `herdr-subagent.sh spawn <name> <kind> --layout split|tab`.
   Add `-- <cli flags>` only for flags the user asked for. It prints the pane
   and tab, and it fails if the CLI is not on PATH or herdr cannot start it.
   Then run `herdr-subagent.sh read <name> 20` once. Confirm the CLI is at its
   input prompt. If it shows an update offer, a folder-trust question, or a
   sign-in screen, do not prompt yet: your prompt's Enter key would answer
   that dialog. Ask the user to deal with it, or close the session.
3. **Write the prompt** to a file in your scratch or temp area. Make it
   self-contained: the delegate has none of your context. Include:
   - the goal, and the exact paths in scope;
   - what it may write; say "read-only" when it may write nothing;
   - for anything that is not a Goal Ledger phase, the sentence
     `Ignore .goal-ledger and all Goal Ledger skills. Follow only the task in this prompt.`;
   - "done when" checks, and the situations in which it must escalate rather than guess.
   The script appends the report contract itself: the report path, its
   sections, and a final `STATUS:` line.
4. **Prompt**: run `herdr-subagent.sh prompt <name> <prompt-file>`. It prints a new report path.
5. **Wait**: run `herdr-subagent.sh wait <name> <report-path> [timeout-seconds]` in the
   background so you are notified once, and do other work meanwhile. The
   default timeout is 1800 s. Do not read the pane while it works.
6. **Handle the result** by exit code:
   - `0` success, `2` escalate, `3` failed: read the report file only.
   - `4` blocked: the CLI is waiting on a prompt in its pane. Run
     `herdr-subagent.sh read <name>` to see it. Answer it with `herdr pane send-keys`
     only if it approves an action inside the task scope the user authorized.
     Otherwise ask the user. Then run `wait` again with the same report path.
   - `5` idle without a report, or `7` timeout: run `read <name>` to see why, then
     steer (step 8) with a prompt asking it to finish and write the report.
   - `6` gone: the session exited. Read any report, then close.
7. **Review** while the session stays open. Treat the report as claims:
   re-run its key checks yourself, read the diffs of any files it changed, and
   spot-check its file:line citations. Smaller models often cite the wrong line.
8. **Steer** when the work needs correction, more work, or an answer to its
   escalation: write a short follow-up prompt that relies on the context the
   session already has, then repeat steps 4 to 7. Each turn gets a new report
   path. Never spawn a fresh session just to continue the same task.
9. **Close** with `herdr-subagent.sh close <name>` once you accept the result,
   abandon the task, or hand it back to the user. Do not leave accepted
   sessions open. Reports stay in `$TMPDIR/herdr-subagent/`, or in
   `/tmp/herdr-subagent/` when `TMPDIR` is unset.

## With the goal-ledger skill

When a Goal Ledger planner delegates a phase (`Execution mode: delegated`,
`Owner: executor`), use this skill as the transport for that skill's
"Delegate a phase" step:

- Prepare the ledger and Handoff exactly as the `goal-ledger` skill says, then
  use its executor prompt verbatim as the prompt file:
  `Use the goal-ledger-execute skill.`, the project root, the phase ID, and
  `Execute that phase only. Do not plan, re-scope, or continue to another phase.`
  Do not add the "Ignore .goal-ledger" sentence to a phase prompt.
- The ledger stays authoritative. The report is a summary; review the phase
  file's `## Evidence`, re-run `## Verify`, and read the phase's commits as
  the `goal-ledger` skill requires.
- If the executor escalates (`needs-human`), record your answer in the phase
  file as the `goal-ledger` skill requires, return the affected sub-tasks to
  `[todo]`, and commit. Then steer the same open session:
  `The planner answered in phase-NNNN; re-read the phase file and continue phase-NNNN only.`
- Close the session only after you accept the phase. One executor holds a
  ledger at a time, so never run two phase delegates on one ledger at once.

## Stop conditions

Stop and ask the user when:

- preflight fails, or the CLI needs a sign-in or setup only the user can do;
- starting another delegate would break the concurrency limit, and nothing can be queued;
- a blocked prompt asks for anything outside the authorized task scope;
- the same delegate fails or escalates twice on one task after steering; then
  take the task back or ask how to proceed.

## Report to the user

After each accepted, abandoned or escalated delegation, tell the user in a
few lines: the delegate name, kind and layout; what it did; what you verified
and how; the report path; and whether the session is closed or still open,
and why.
