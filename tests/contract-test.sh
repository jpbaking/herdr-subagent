#!/usr/bin/env bash
# Walk AGENT-INSTALL.md step by step against a scratch HOME: clean install,
# idempotent re-run, stale copy plus user content, and uninstall.
#
#   tests/contract-test.sh                      # test this checkout
#   REMOTE=https://github.com/jpbaking/herdr-subagent TAG=v0.1.3 tests/contract-test.sh
# shellcheck disable=SC2015  # "test && ok || bad" is safe: ok always succeeds.
set -uo pipefail
REMOTE=${REMOTE:-file://$(cd "$(dirname "$0")/.." && pwd)}
TAG=${TAG:-}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/herdr-subagent-ctest.XXXX")
export HOME="$ROOT/home"; mkdir -p "$HOME"
PROJ="$ROOT/someproject"; mkdir -p "$PROJ"
DESTS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.gemini/antigravity-cli/skills")
SURVEY=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.gemini/antigravity-cli/skills"
        "$HOME/.gemini/skills" "$HOME/.gemini/config/skills" "$HOME/.cline/skills" "$HOME/.config/opencode/skills")
pass=0; fail=0
ok()  { echo "  PASS $*"; pass=$((pass+1)); }
bad() { echo "  FAIL $*"; fail=$((fail+1)); }
sum() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }
snap() { (cd "$ROOT" && find . -path ./stage -prune -o -type f -exec cat {} + ; find . -path ./stage -prune -o -print | LC_ALL=C sort) | sum | cut -c1-16; }

acquire() { # contract step 1
  STAGE="$ROOT/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$REMOTE" >/dev/null 2>&1 || { bad "ls-remote"; return 1; }
  GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 ${TAG:+--branch "$TAG"} "$REMOTE" "$STAGE/herdr-subagent" 2>/dev/null
  [ -f "$STAGE/herdr-subagent/AGENT-INSTALL.md" ] || { bad "clone"; return 1; }
  SRC="$STAGE/herdr-subagent/.agents/skills/herdr-subagent"
}
survey() { # contract step 2.2-2.3: prints classification per location
  local d
  for d in "${SURVEY[@]}" "$PROJ/.agents/skills" "$PROJ/.claude/skills"; do
    [ -e "$d/herdr-subagent" ] || continue
    if diff -rq "$SRC" "$d/herdr-subagent" >/dev/null; then echo "identical $d"; else echo "differs $d"; fi
  done
}
install() { # contract step 3 + 5 (all three destinations selected)
  local d
  for d in "${DESTS[@]}"; do
    mkdir -p "$d"; rm -rf "$d/herdr-subagent"; cp -a "$SRC" "$d/herdr-subagent"
  done
  for d in "${DESTS[@]}"; do
    diff -r "$SRC" "$d/herdr-subagent" >/dev/null && [ -x "$d/herdr-subagent/scripts/herdr-subagent.sh" ] \
      && ok "validate $d" || bad "validate $d"
  done
  rm -rf "$STAGE"
}
uninstall() { # Uninstall section
  local d; for d in "${DESTS[@]}"; do rm -rf "$d/herdr-subagent"; done
}

echo "== missing remote fails fast without prompting"
start=$(date +%s)
if GIT_TERMINAL_PROMPT=0 git ls-remote "file://$ROOT/does-not-exist" >/dev/null 2>&1; then bad "ls-remote on missing repo succeeded"; else
  [ $(( $(date +%s) - start )) -lt 30 ] && ok "missing remote fails in $(( $(date +%s) - start ))s, no hang" || bad "slow failure"; fi

echo "== state 1: clean home"
acquire || exit 1
[ -z "$(survey)" ] && ok "survey finds nothing" || bad "survey: $(survey)"
install
[ -z "$(find "$HOME" -maxdepth 3 -name '*.md' -not -path '*/skills/*')" ] && ok "no instruction files created" || bad "instruction files created"

echo "== state 2: immediate re-run is a no-op"
before=$(snap); acquire; [ "$(survey | grep -c identical)" = 3 ] && ok "survey: 3 identical" || bad "survey: $(survey)"
install; after=$(snap); [ "$before" = "$after" ] && ok "tree unchanged after re-run" || bad "tree changed on re-run"

echo "== state 3: older copy with a stale file, user content, other skills, same-name project skill"
echo "stale" > "$HOME/.claude/skills/herdr-subagent/references/old-notes.md"
mkdir -p "$HOME/.claude/skills/other-skill" "$HOME/.agents/skills/other-skill" "$HOME/.gemini" "$HOME/.codex" "$HOME/.config/opencode"
echo "keep me" > "$HOME/.claude/skills/other-skill/SKILL.md"; cp "$HOME/.claude/skills/other-skill/SKILL.md" "$HOME/.agents/skills/other-skill/"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"; do printf '# mine\nuser text\n' > "$f"; done
mkdir -p "$PROJ/.agents/skills/herdr-subagent"; echo "project copy" > "$PROJ/.agents/skills/herdr-subagent/SKILL.md"
userbefore=$( (cat "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME"/.claude/skills/other-skill/SKILL.md "$HOME"/.agents/skills/other-skill/SKILL.md "$PROJ/.agents/skills/herdr-subagent/SKILL.md") | sum)
acquire; s=$(survey)
echo "$s" | grep -q "differs $HOME/.claude/skills" && ok "survey flags modified Claude copy" || bad "survey missed modified copy"
echo "$s" | grep -q "differs $PROJ/.agents/skills" && ok "survey reports same-name project skill" || bad "survey missed project skill"
install
[ ! -e "$HOME/.claude/skills/herdr-subagent/references/old-notes.md" ] && ok "stale file removed" || bad "stale file remains"
userafter=$( (cat "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME"/.claude/skills/other-skill/SKILL.md "$HOME"/.agents/skills/other-skill/SKILL.md "$PROJ/.agents/skills/herdr-subagent/SKILL.md") | sum)
[ "$userbefore" = "$userafter" ] && ok "user files, other skills, project copy untouched" || bad "user content changed"

echo "== uninstall"
uninstall
for d in "${DESTS[@]}"; do [ ! -e "$d/herdr-subagent" ] && [ -d "$d" ] && ok "removed from $d, parent kept" || bad "uninstall $d"; done
[ -f "$HOME/.claude/skills/other-skill/SKILL.md" ] && [ -f "$PROJ/.agents/skills/herdr-subagent/SKILL.md" ] && ok "other skills and project copy survive" || bad "collateral removal"
useruninst=$( (cat "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME"/.claude/skills/other-skill/SKILL.md "$HOME"/.agents/skills/other-skill/SKILL.md "$PROJ/.agents/skills/herdr-subagent/SKILL.md") | sum)
[ "$userbefore" = "$useruninst" ] && ok "instruction files and other skills intact after uninstall" || bad "user content changed by uninstall"

echo "== result: $pass passed, $fail failed"
rm -rf "$ROOT"
[ "$fail" = 0 ]
