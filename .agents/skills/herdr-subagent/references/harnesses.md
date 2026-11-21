# Delegate CLI notes

Verified on 2026-11-21 with herdr 0.7.5 on Linux. Re-check these notes after
upgrading herdr or a delegate CLI; `herdr agent start --help` lists the kinds
herdr can start.

The script supports four delegate kinds: `opencode`, `agy`, `codex`, and
`claude`. herdr detects each of them natively (it tracks their state from the
screen, with no integration installed), so prompting goes through
`herdr agent prompt` and waiting uses herdr's `working`, `idle`, `done`, and
`blocked` states.

herdr launches the CLI by typing its name into the pane's interactive shell,
so the user's shell aliases apply. An alias that adds a permission-bypass
flag puts the delegate in that mode. Pass extra CLI flags after `--` on
`spawn`, and only the ones the user asked for.

`herdr integration install <kind>` adds hook-based state reporting, which can
be more accurate than screen detection. It changes that CLI's own
configuration, so install it only when the user asks.

| Kind | Tested version | Verified | Model flag | Permission and mode flags |
| --- | --- | --- | --- | --- |
| `opencode` | v2.3.2 | full lifecycle in split and tab: spawn, prompt, wait, multi-turn steer, escalate, close | none in the interactive TUI; uses the configured default | `--auto` |
| `claude` | 2.1.330 | spawn, prompt, wait, report, close | `--model <alias or id>` | `--permission-mode <mode>`, `--dangerously-skip-permissions` |
| `codex` | 0.171.0 | spawn, prompt, wait, report, close | `-m <model>`, `-p <profile>` | `-s <sandbox>`, `--dangerously-bypass-approvals-and-sandbox` |
| `agy` | 1.5.13 | spawn, prompt, wait, report, close | `--model <model>` | `--mode accept-edits\|auto\|plan`, `--dangerously-skip-permissions` |

Start-up dialogs are the most common failure. A CLI may open on an update
offer, a folder-trust question, or a sign-in screen, and herdr can still
report it as idle or working. A prompt sent then lands in the dialog, and its
Enter key answers it. In testing, codex accepted its own update offer this
way, upgraded itself, and exited, so `wait` returned code 6 (gone). Read the
pane once after `spawn` and prompt only when the CLI is at its input prompt.

After upgrading herdr or a delegate CLI, treat the first delegation as a
trial: send a trivial read-only prompt, and confirm that `wait` returns on
the report before you hand it real work.

## opencode

- The interactive TUI has no model flag. It always uses the model set in the
  opencode configuration, so changing it means changing that configuration,
  which is the user's decision.
- opencode is often pointed at a local model server that can serve only one
  session at a time. Ask, or follow the user's stated limit, before running two.
- With a default configuration, writing the report outside the project
  caused no permission prompt. A stricter configuration may block on it; then
  `wait` exits with code 4.

## claude (Claude Code)

- Cloud models, so usage costs apply. Pass `-- --model <alias>` only when the
  user names a model.
- A planner running in Claude Code can delegate to another Claude Code
  session. The delegate is a separate session with its own context and its
  own permission mode.

## codex

- Cloud models; pass `-- -m <model>` only when the user names one.
- Without a bypass flag or alias, codex asks for approvals in its pane, and
  `wait` exits with code 4 (blocked).
- codex offers to update itself at start-up. Answering that offer by accident
  upgrades codex and exits the session (see above).

## agy (Antigravity CLI)

- It must be signed in. An unsigned agy opens on "You are currently not
  signed in" and a login-method menu, and herdr still reports it as idle.
  Prompting then would pick a login method. The user must sign in with `agy`
  in a terminal first, and confirm that a fresh `agy` opens at its input prompt.
- `-- --mode plan` suits read-only tasks.

## Not supported

The script refuses other kinds, including ones herdr can start. In
particular, herdr 0.7.5 does not detect `cline`. It runs as `node` plus a
`.cline` child process, so `herdr agent start` times out and
`herdr agent prompt` refuses it.
