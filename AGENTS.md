# herdr-subagent repository instructions

Follow the
[Portable Agent Authoring](https://github.com/jpbaking/portable-agent-authoring)
guides, especially *Agent toolkit repositories*, for every skill or harness
change.

- Edit the skill only under `.agents/skills/herdr-subagent/`. It is the only
  install source.
- Regenerate `.claude/skills/herdr-subagent/` as a byte-identical
  full-directory mirror after every change, and never edit it on its own:
  `rm -rf .claude/skills/herdr-subagent && cp -a .agents/skills/herdr-subagent .claude/skills/`.
- No skill may fetch this repository's files over raw HTTP.
- Keep `SKILL.md` under 24,000 bytes (`agy` truncates beyond that; CI checks
  it). Put per-CLI detail in `references/harnesses.md`.
- `scripts/herdr-subagent.sh` must pass `bash -n` and `shellcheck`. Keep it
  free of GNU-only flags (for example `sed -i`) so it also runs on macOS.
- When you change supported kinds, exit codes, or the report contract, update
  `SKILL.md`, `references/harnesses.md`, the script's usage header, and
  `README.md` together.
- Re-verify behavior against a live herdr session before release, and record
  the herdr and CLI versions in `references/harnesses.md`.
- Update `AGENT-INSTALL.md` and `README.md` whenever discovery, invocation, or
  installation changes, and keep `tests/contract-test.sh` in step with the
  contract. Run it after committing; it clones `HEAD`.
- Dogfooding collision: with herdr-subagent installed globally, every harness
  also sees this repository's skill. Claude Code and Cline prefer the global
  copy (your edits seem to have no effect), Codex lists both, and Gemini CLI
  and OpenCode prefer the workspace copy. Test changes in a fresh session with
  the global copy temporarily removed or disabled.
