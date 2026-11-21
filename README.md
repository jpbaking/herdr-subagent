# herdr-subagent

A skill that turns any interactive coding-agent CLI running in
[herdr](https://herdr.dev) into a **visible pseudo-subagent**. Your planner
agent spawns a delegate (opencode by default; also `agy`, `codex`, or
`claude`) in a herdr pane or tab, hands it a self-contained task, and then
reads only a compact report file. It never reads the delegate's raw trace. You
can watch the delegate work live in herdr's agent list.

The delegate session stays open while the planner reviews the report. The
planner can **steer** it with follow-up prompts that keep the session's
context, and it **closes** the pane or tab once it accepts the result.

The skill installs into Antigravity CLI, Codex, Claude Code, Gemini CLI,
Cline, and OpenCode, any of which can act as the planner.

https://github.com/user-attachments/assets/9b6b6661-b1ad-4d85-8be9-f75b2600ee60

## How it works

```text
planner (you)                        delegate (herdr pane or tab)
───────────────                      ────────────────────────────
spawn  sub-<task> opencode   ──▶     interactive opencode starts
prompt <prompt-file>         ──▶     works; you can watch it
wait   (background, one notice) ◀──  writes report, last line STATUS: …
review: re-run checks, read diffs
steer  <follow-up>           ──▶     continues with its context intact
close                        ──▶     pane or tab closes
```

- **Report contract.** Every prompt gets the same footer. The delegate writes
  a Markdown report (what it did, evidence, open questions) to
  `$TMPDIR/herdr-subagent/<name>-<time>.md` (`/tmp/…` when `TMPDIR` is
  unset). Its last line is `STATUS: success`, `STATUS: escalate - <question>`,
  or `STATUS: failed - <reason>`.
- **Escalate, don't guess.** A delegate stuck on a decision escalates with
  the exact question. The planner answers it in the same open session.
- **Wait outcomes.** `wait` exits with 0 success, 2 escalate, 3 failed,
  4 blocked (a permission prompt is waiting in the pane), 5 idle without a
  report, 6 session gone, or 7 timeout.
- **Layouts.** By default the first two open delegates share a column to the
  right of the planner, stacked top to bottom, and the third and later ones
  each get a background tab. `--layout split` or `--layout tab` overrides it.
- **Concurrency.** The skill follows your stated limit, or one running
  delegate per model backend. Use that for a local model server that serves
  one session at a time.
- **Goal Ledger.** With the
  [goal-ledger](https://github.com/jpbaking/goal-ledger) skills, this is the
  transport for a delegated phase. The executor gets the standard
  `goal-ledger-execute` prompt, `needs-human` escalations are answered in the
  phase file and then steered into the same session, and the session closes
  after the planner accepts the phase.

## Requirements

- [herdr](https://herdr.dev) 0.7.5 or later, with the planner running inside it
- `bash` and `jq`
- At least one delegate CLI, installed, signed in, and on `PATH`:

| Delegate | Verified |
| --- | --- |
| `opencode` | full lifecycle, split and tab, multi-turn steer, escalation |
| `codex` | full round-trip |
| `agy` | full round-trip |
| `claude` | full round-trip |

See [`references/harnesses.md`](.agents/skills/herdr-subagent/references/harnesses.md)
for per-CLI flags and caveats. Tested on Linux; macOS should work but is
untested. Windows needs WSL. `cline` is not supported, because herdr 0.7.5
does not detect it as an agent.

## Install

Installation is agent-guided only; there are no install scripts. Paste this
into Antigravity CLI, Codex, Claude Code, Gemini CLI, Cline, or OpenCode:

```text
Install herdr-subagent. Using git with my existing credentials (do not
download raw files or archives), clone https://github.com/jpbaking/herdr-subagent
at tag v0.1.3 with --depth 1 and git's terminal prompt disabled
(GIT_TERMINAL_PROMPT=0) into a new temporary directory outside any project;
a "not a commit" warning about the tag is normal. If the clone fails for lack
of credentials, stop and tell me how to sign in. Then read AGENT-INSTALL.md
from that clone and follow it exactly. Merge with—never blindly overwrite—any
existing files, ask me which harnesses to install for, and report every file
you created or changed.
```

This prompt pins release `v0.1.3`. To install another release, change the
tag; to track the default branch, drop `at tag v0.1.3`. On a fork, mirror, or
enterprise host, substitute the remote you clone from.

**What the prompt does:** your agent clones this repository with your own git
credentials and executes [AGENT-INSTALL.md](./AGENT-INSTALL.md), the
authoritative install contract. It writes only the skill directory, to these
user-global paths, and changes no instruction files and nothing in your repos:

| Harness | Skill destination |
| --- | --- |
| Antigravity CLI (`agy`) | `~/.gemini/antigravity-cli/skills/herdr-subagent/` |
| Claude Code | `~/.claude/skills/herdr-subagent/` |
| Codex, Gemini CLI, Cline, OpenCode | `~/.agents/skills/herdr-subagent/` |

AGENT-INSTALL.md also covers update and uninstall.

## Usage

Start your planner agent inside herdr and ask for the skill by name:

- any harness: "Use the herdr-subagent skill to have opencode survey `src/`."
- `agy`, Claude Code, Cline: `/herdr-subagent`
- Codex: type `$` and select `herdr-subagent`
- OpenCode: `@herdr-subagent`
- Gemini CLI: name the skill in the prompt

You can also run the bundled script yourself:

```sh
S=~/.claude/skills/herdr-subagent/scripts/herdr-subagent.sh   # or your harness's path
$S spawn sub-survey opencode                  # auto layout; --layout split|tab; -- <cli flags>
$S prompt sub-survey task.txt                 # prints the report path
$S wait sub-survey /tmp/herdr-subagent/sub-survey-….md
$S read sub-survey 40                         # pane tail, for blocked/idle cases
$S list
$S close sub-survey
```

## Repository layout

```text
AGENT-INSTALL.md                     # install contract (authoritative)
AGENTS.md                            # contributor instructions
CLAUDE.md                            # @AGENTS.md bridge for Claude Code
.gemini/settings.json                # points Gemini CLI at AGENTS.md
.agents/skills/herdr-subagent/       # authoritative skill (the only install source)
  SKILL.md
  references/harnesses.md
  scripts/herdr-subagent.sh
.claude/skills/herdr-subagent/       # generated byte-identical mirror
tests/contract-test.sh               # install-contract walk-through for CI
```

## Development

```sh
bash -n .agents/skills/herdr-subagent/scripts/herdr-subagent.sh
shellcheck .agents/skills/herdr-subagent/scripts/herdr-subagent.sh tests/contract-test.sh
diff -r .agents/skills .claude/skills
tests/contract-test.sh      # walks AGENT-INSTALL.md against a scratch HOME
```

The contract test clones the committed `HEAD` of this checkout, so commit
first. Set `REMOTE` and `TAG` to test a published release instead. CI runs
all of these on Linux and macOS. The delegate round-trips need a live herdr
session and signed-in CLIs, so they are verified by hand before each release
and recorded in `references/harnesses.md`.

## License

This repository is licensed under [0BSD](LICENSE).
