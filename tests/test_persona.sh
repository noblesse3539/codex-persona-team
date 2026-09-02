#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/persona-test.XXXXXX")"
SOURCE="$TEST_ROOT/source"
TEST_CODEX="$TEST_ROOT/codex"
TEST_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_not_file() {
  [[ ! -f "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
  local file="$1" text="$2"
  grep -Fq "$text" "$file" || fail "$file does not contain: $text"
}

assert_not_contains() {
  local file="$1" text="$2"
  if grep -Fq "$text" "$file"; then fail "$file unexpectedly contains: $text"; fi
}

mkdir -p "$SOURCE" "$TEST_CODEX" "$TEST_BIN"
cp -R "$ROOT/." "$SOURCE/"
rm -rf "$SOURCE/.git"
chmod +x "$SOURCE/scripts/persona.sh" "$SOURCE/scripts/install.sh"

git -C "$SOURCE" init -b main >/dev/null
git -C "$SOURCE" add .
git -C "$SOURCE" -c user.name='Persona Test' -c user.email='persona-test@local' commit -m 'test fixture' >/dev/null

printf '%s\n' \
  'notify = ["keep-me"]' \
  'model = "user-model"' \
  'model_reasoning_effort = "high"' \
  '' \
  '[features]' \
  'memories = true' > "$TEST_CODEX/config.toml"
printf '# Existing global instruction\n' > "$TEST_CODEX/AGENTS.md"

# A mid-install launcher failure must roll back every earlier managed change.
BLOCKED_BIN="$TEST_ROOT/blocked-bin"
printf 'not a directory\n' > "$BLOCKED_BIN"
if PERSONA_CODEX_DIR="$TEST_CODEX" \
  PERSONA_BIN_DIR="$BLOCKED_BIN" \
  PERSONA_SKIP_PATH_UPDATE=1 \
  PERSONA_SKIP_CODEX_VALIDATE=1 \
  PERSONA_SOURCE_ROOT="$SOURCE" \
    "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'broken launcher path did not fail installation'
fi
assert_contains "$TEST_CODEX/config.toml" 'model = "user-model"'
assert_not_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_not_file "$TEST_CODEX/agents/soul.toml"
assert_not_file "$TEST_CODEX/agents/core.toml"
assert_not_file "$TEST_CODEX/skills/persona-council/SKILL.md"
rm -f "$BLOCKED_BIN"

# An unmanaged launcher and symlinked settings must be preserved, not overwritten.
printf '#!/usr/bin/env bash\nprintf "mine\\n"\n' > "$TEST_BIN/persona"
chmod +x "$TEST_BIN/persona"
if PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'unmanaged persona launcher was overwritten'
fi
assert_contains "$TEST_BIN/persona" 'mine'
rm -f "$TEST_BIN/persona"

mv "$TEST_CODEX/config.toml" "$TEST_CODEX/config.real.toml"
ln -s "$TEST_CODEX/config.real.toml" "$TEST_CODEX/config.toml"
if PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'symlinked config was replaced'
fi
[[ -L "$TEST_CODEX/config.toml" ]] || fail 'config symlink was not preserved'
rm -f "$TEST_CODEX/config.toml"
mv "$TEST_CODEX/config.real.toml" "$TEST_CODEX/config.toml"

run_persona() {
  (
    cd "$SOURCE"
    PERSONA_CODEX_DIR="$TEST_CODEX" \
    PERSONA_BIN_DIR="$TEST_BIN" \
    PERSONA_SKIP_PATH_UPDATE=1 \
    PERSONA_SKIP_CODEX_VALIDATE=1 \
      "$SOURCE/scripts/persona.sh" "$@"
  )
}

PERSONA_CODEX_DIR="$TEST_CODEX" \
PERSONA_BIN_DIR="$TEST_BIN" \
PERSONA_SKIP_PATH_UPDATE=1 \
PERSONA_SKIP_CODEX_VALIDATE=1 \
PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null

assert_contains "$TEST_CODEX/AGENTS.md" '# Existing global instruction'
assert_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_file "$TEST_CODEX/agents/soul.toml"
assert_file "$TEST_CODEX/agents/core.toml"
assert_file "$TEST_CODEX/skills/persona-council/SKILL.md"
assert_file "$TEST_BIN/persona"
assert_contains "$TEST_CODEX/config.toml" 'notify = ["keep-me"]'
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-luna"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "max"'

# Reinstall must preserve one managed block and the active state.
cp "$TEST_CODEX/AGENTS.md" "$TEST_ROOT/AGENTS.first.md"
PERSONA_CODEX_DIR="$TEST_CODEX" \
PERSONA_BIN_DIR="$TEST_BIN" \
PERSONA_SKIP_PATH_UPDATE=1 \
PERSONA_SKIP_CODEX_VALIDATE=1 \
PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null
[[ "$(grep -Fc '<!-- LOOP-PERSONA-TEAM:START -->' "$TEST_CODEX/AGENTS.md")" == "1" ]] || fail 'install is not idempotent'
cmp -s "$TEST_ROOT/AGENTS.first.md" "$TEST_CODEX/AGENTS.md" || fail 'reinstall changed AGENTS content'

run_persona profile balanced >/dev/null
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-terra"'
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-luna"'
run_persona model set soul terra high >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-terra"'
assert_contains "$TEST_CODEX/agents/soul.toml" 'model_reasoning_effort = "high"'
run_persona model reset soul >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-luna"'
if run_persona model set soul luna ultra >/dev/null 2>&1; then fail 'unsupported effort was accepted'; fi
run_persona model set soul terra ultra >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model_reasoning_effort = "ultra"'
run_persona model reset soul >/dev/null
status_file="$TEST_ROOT/status.txt"
run_persona status > "$status_file"
assert_contains "$status_file" 'soul: gpt-5.6-luna / max (source: profile balanced)'

# A failed strict-config check must restore both config.toml and local profile state.
mkdir -p "$TEST_ROOT/failing-bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_ROOT/failing-bin/codex"
chmod +x "$TEST_ROOT/failing-bin/codex"
if (
  cd "$SOURCE"
  PATH="$TEST_ROOT/failing-bin:$PATH" \
  PERSONA_CODEX_DIR="$TEST_CODEX" \
  PERSONA_BIN_DIR="$TEST_BIN" \
  PERSONA_SKIP_PATH_UPDATE=1 \
  PERSONA_SKIP_CODEX_VALIDATE=0 \
    "$SOURCE/scripts/persona.sh" profile economy
) >/dev/null 2>&1; then
  fail 'failed Codex validation was accepted'
fi
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-terra"'
assert_contains "$TEST_CODEX/persona-team/state.conf" 'profile=balanced'

before_count="$(find "$SOURCE/memory" -type f -name '*.md' | wc -l | tr -d ' ')"
if run_persona memory add --scope global --audience soul --summary '미승인' --text '기록되면 안 됨' >/dev/null 2>&1; then fail 'unapproved memory was accepted'; fi
after_count="$(find "$SOURCE/memory" -type f -name '*.md' | wc -l | tr -d ' ')"
[[ "$before_count" == "$after_count" ]] || fail 'unapproved memory changed files'
if run_persona memory add --scope global --audience shared --summary 'secret test' --text 'api_key=do-not-store' --approved >/dev/null 2>&1; then fail 'secret-like memory was accepted'; fi

memory_output="$(run_persona memory add --scope global --audience soul --kind reflection --summary '첫 승인 기억' --text '소울은 첫 테스트 기억을 소중히 여깁니다.' --approved)"
memory_id="$(printf '%s\n' "$memory_output" | sed -n 's/.*기록했습니다: //p')"
[[ -n "$memory_id" ]] || fail 'memory id was not returned'
context_file="$TEST_ROOT/context.txt"
run_persona context soul > "$context_file"
assert_contains "$context_file" "$memory_id"
assert_contains "$context_file" '소울은 첫 테스트 기억을 소중히 여깁니다.'

if run_persona memory retract "$memory_id" >/dev/null 2>&1; then fail 'unapproved retraction was accepted'; fi
run_persona memory retract "$memory_id" --approved >/dev/null
run_persona context soul > "$context_file"
assert_not_contains "$context_file" "$memory_id"

run_persona project use game-one >/dev/null
project_output="$(run_persona memory add --scope project --audience shared --kind decision --summary '프로젝트 결정' --text '게임 원은 엔진 중립으로 유지합니다.' --approved)"
[[ "$project_output" == *'기억을 기록했습니다:'* ]] || fail 'project memory was not recorded'
project_memory_id="$(printf '%s\n' "$project_output" | sed -n 's/.*기록했습니다: //p')"
run_persona context core > "$context_file"
assert_contains "$context_file" 'game-one'
assert_contains "$context_file" '게임 원은 엔진 중립으로 유지합니다.'

# Approved content is hash-bound and secrets are checked again at sync time.
project_memory_file="$(find "$SOURCE/memory" -type f -name "$project_memory_id.md" -print -quit)"
cp "$project_memory_file" "$TEST_ROOT/project-memory.approved"
printf '\n승인 뒤 바뀐 내용\n' >> "$project_memory_file"
if run_persona sync >/dev/null 2>&1; then fail 'modified approved memory was synchronized'; fi
cp "$TEST_ROOT/project-memory.approved" "$project_memory_file"
printf '\napi_key=changed-after-approval\n' >> "$project_memory_file"
if run_persona sync >/dev/null 2>&1; then fail 'secret added after approval was synchronized'; fi
cp "$TEST_ROOT/project-memory.approved" "$project_memory_file"

# Existing staged work and detached HEAD must stop before the memory commit.
printf 'user staged work\n' > "$SOURCE/staged-user.txt"
git -C "$SOURCE" add staged-user.txt
if run_persona sync >/dev/null 2>&1; then fail 'sync accepted pre-existing staged changes'; fi
git -C "$SOURCE" restore --staged staged-user.txt
rm -f "$SOURCE/staged-user.txt"
git -C "$SOURCE" switch --detach >/dev/null
if run_persona sync >/dev/null 2>&1; then fail 'sync accepted detached HEAD'; fi
git -C "$SOURCE" switch main >/dev/null

run_persona sync >/dev/null
git -C "$SOURCE" log -1 --pretty=%s | grep -Fq 'memory: sync approved persona memories' || fail 'sync did not commit pending memories'
[[ ! -s "$TEST_CODEX/persona-team/pending-memory.txt" ]] || fail 'pending memory list was not cleared'

run_persona doctor >/dev/null
run_persona uninstall >/dev/null
assert_not_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_contains "$TEST_CODEX/AGENTS.md" '# Existing global instruction'
assert_not_file "$TEST_CODEX/agents/soul.toml"
assert_not_file "$TEST_CODEX/agents/core.toml"
assert_contains "$TEST_CODEX/config.toml" 'model = "user-model"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "high"'
assert_contains "$TEST_CODEX/config.toml" 'notify = ["keep-me"]'
assert_file "$SOURCE/memory/retractions/$memory_id.md"

# A fresh install after uninstall must capture the user's new defaults, and
# uninstall restores each untouched key independently.
printf '%s\n' \
  'notify = ["second-install"]' \
  'model = "user-model-two"' \
  'model_reasoning_effort = "medium"' > "$TEST_CODEX/config.toml"
PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null
awk '{ if ($0 ~ /^model =/) print "model = \"changed-after-install\""; else print }' "$TEST_CODEX/config.toml" > "$TEST_ROOT/config.changed.toml"
mv "$TEST_ROOT/config.changed.toml" "$TEST_CODEX/config.toml"
run_persona uninstall >/dev/null
assert_contains "$TEST_CODEX/config.toml" 'model = "changed-after-install"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "medium"'
assert_contains "$TEST_CODEX/config.toml" 'notify = ["second-install"]'

printf 'All macOS/POSIX persona tests passed.\n'
