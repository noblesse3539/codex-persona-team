#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT_RAW="$(mktemp -d "${TMPDIR:-/tmp}/persona-test.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT_RAW" && pwd -P)"
SOURCE="$TEST_ROOT/source"
TEST_CODEX="$TEST_ROOT/codex"
TEST_BIN="$TEST_ROOT/bin"
GAME="$TEST_ROOT/game"
LEGACY="$TEST_ROOT/legacy-persona"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

assert_not_file() {
  [[ ! -f "$1" ]] || fail "unexpected file: $1"
}

assert_not_exists() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" wanted="$2"
  grep -Fq "$wanted" "$file" || fail "$file does not contain: $wanted"
}

assert_not_contains() {
  local file="$1" unwanted="$2"
  if grep -Fq "$unwanted" "$file"; then fail "$file unexpectedly contains: $unwanted"; fi
}

tree_fingerprint() {
  local root="$1" file
  (
    cd "$root"
    while IFS= read -r file; do
      shasum -a 256 "$file"
    done < <(find . -type f -print | LC_ALL=C sort)
  ) | shasum -a 256 | awk '{print $1}'
}

protected_local_fingerprint() {
  local root="$1" relative
  {
    for relative in private pending state/projects state/task-bindings state/cursors state/writer-locks state/model-overrides; do
      if [[ -d "$root/$relative" ]]; then
        printf '%s %s\n' "$(tree_fingerprint "$root/$relative")" "$relative"
      else
        printf 'absent %s\n' "$relative"
      fi
    done
    grep -E '^(install_id|profile|override_(loop|soul|core)_(model|effort))=' "$root/state/state.conf" | LC_ALL=C sort
  } | shasum -a 256 | awk '{print $1}'
}

run_persona() {
  (
    cd "$SOURCE"
    PERSONA_CODEX_DIR="$TEST_CODEX" \
    PERSONA_BIN_DIR="$TEST_BIN" \
    PERSONA_SKIP_PATH_UPDATE=1 \
    PERSONA_SKIP_CODEX_VALIDATE=1 \
    PERSONA_UPDATE_SKIP_PULL="${PERSONA_UPDATE_SKIP_PULL:-0}" \
      "$SOURCE/scripts/persona.sh" "$@"
  )
}

run_persona_in() {
  local directory="$1"
  shift
  (
    cd "$directory"
    PERSONA_CODEX_DIR="$TEST_CODEX" \
    PERSONA_BIN_DIR="$TEST_BIN" \
    PERSONA_SKIP_PATH_UPDATE=1 \
    PERSONA_SKIP_CODEX_VALIDATE=1 \
      "$SOURCE/scripts/persona.sh" "$@"
  )
}

mkdir -p "$SOURCE" "$TEST_CODEX" "$TEST_BIN" "$GAME" "$LEGACY/memory/global/shared" "$LEGACY/memory/projects/old-game"
cp -R "$ROOT/." "$SOURCE/"
rm -rf -- "$SOURCE/.git"
chmod +x "$SOURCE/scripts/persona.sh" "$SOURCE/scripts/install.sh" "$SOURCE/tests/test_persona.sh"

git -C "$SOURCE" init -b main >/dev/null
git -C "$SOURCE" add .
git -C "$SOURCE" -c user.name='Persona Test' -c user.email='persona-test@local' commit -m 'test fixture' >/dev/null
git -C "$GAME" init -b main >/dev/null
printf '# Test game\n' > "$GAME/README.md"
git -C "$GAME" add README.md
git -C "$GAME" -c user.name='Persona Test' -c user.email='persona-test@local' commit -m 'game fixture' >/dev/null

printf '%s\n' \
  'notify = ["keep-me"]' \
  'model = "user-model"' \
  'model_reasoning_effort = "high"' \
  '' \
  '[features]' \
  'memories = true' > "$TEST_CODEX/config.toml"
printf '# Existing global instruction\n' > "$TEST_CODEX/AGENTS.md"
mkdir -p "$TEST_CODEX/memories" "$TEST_CODEX/persona-team"
printf 'Codex-owned memory must survive.\n' > "$TEST_CODEX/memories/native.md"
printf '%s\n' \
  "repo_root=$LEGACY" \
  'profile=balanced' > "$TEST_CODEX/persona-team/state.conf"
printf '%s\n' \
  '---' \
  'id: "legacy-profile"' \
  'summary: "v1 local profile"' \
  '---' \
  '' \
  'This profile must migrate to local-only storage.' > "$LEGACY/memory/global/shared/profile.md"
printf '%s\n' \
  '---' \
  'id: "legacy-project-decision"' \
  '---' \
  '' \
  'Report this as a project-document candidate; do not convert it automatically.' > "$LEGACY/memory/projects/old-game/decision.md"

# The installer must reject another platform before making any changes.
NON_MAC_CODEX="$TEST_ROOT/non-mac-codex"
if PERSONA_TEST_UNAME=NotDarwin PERSONA_CODEX_DIR="$NON_MAC_CODEX" PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'non-macOS installation was accepted'
fi
assert_not_exists "$NON_MAC_CODEX"

# Local private state must never be created inside any Git worktree.
UNSAFE_GIT="$TEST_ROOT/unsafe-local-repo"
UNSAFE_CODEX="$UNSAFE_GIT/.codex"
mkdir -p "$UNSAFE_CODEX"
git -C "$UNSAFE_GIT" init -b main >/dev/null
if PERSONA_CODEX_DIR="$UNSAFE_CODEX" PERSONA_BIN_DIR="$TEST_ROOT/unsafe-bin" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'local Persona data inside a Git worktree was accepted'
fi
assert_not_exists "$UNSAFE_CODEX/persona-team"

# A failure after installation begins must restore every managed Codex target.
ROLLBACK_CODEX="$TEST_ROOT/rollback-codex"
ROLLBACK_BIN="$TEST_ROOT/blocked-bin"
mkdir -p "$ROLLBACK_CODEX"
printf 'model = "rollback-user-model"\n' > "$ROLLBACK_CODEX/config.toml"
printf '# Rollback instruction\n' > "$ROLLBACK_CODEX/AGENTS.md"
printf 'not a directory\n' > "$ROLLBACK_BIN"
if PERSONA_CODEX_DIR="$ROLLBACK_CODEX" PERSONA_BIN_DIR="$ROLLBACK_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'broken launcher path did not fail installation'
fi
assert_contains "$ROLLBACK_CODEX/config.toml" 'model = "rollback-user-model"'
assert_not_contains "$ROLLBACK_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_not_file "$ROLLBACK_CODEX/agents/soul.toml"
assert_not_file "$ROLLBACK_CODEX/agents/core.toml"
rm -f -- "$ROLLBACK_BIN"

# Unmanaged targets and symlinked configuration must never be overwritten.
printf '#!/usr/bin/env bash\nprintf "mine\\n"\n' > "$TEST_BIN/persona"
chmod +x "$TEST_BIN/persona"
if PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'unmanaged persona launcher was overwritten'
fi
assert_contains "$TEST_BIN/persona" 'mine'
rm -f -- "$TEST_BIN/persona"

mv "$TEST_CODEX/config.toml" "$TEST_CODEX/config.real.toml"
ln -s "$TEST_CODEX/config.real.toml" "$TEST_CODEX/config.toml"
if PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null 2>&1; then
  fail 'symlinked config was replaced'
fi
[[ -L "$TEST_CODEX/config.toml" ]] || fail 'config symlink was not preserved'
rm -f -- "$TEST_CODEX/config.toml"
mv "$TEST_CODEX/config.real.toml" "$TEST_CODEX/config.toml"

# Install v2 and migrate the old global memory to private local storage.
source_before="$(git -C "$SOURCE" status --porcelain)"
PERSONA_CODEX_DIR="$TEST_CODEX" \
PERSONA_BIN_DIR="$TEST_BIN" \
PERSONA_SKIP_PATH_UPDATE=1 \
PERSONA_SKIP_CODEX_VALIDATE=1 \
PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null
[[ "$(git -C "$SOURCE" status --porcelain)" == "$source_before" ]] || fail 'installation changed the Persona source worktree'

LOCAL_ROOT="$TEST_CODEX/persona-team"
assert_file "$LOCAL_ROOT/.persona-team-root"
assert_file "$LOCAL_ROOT/private/.persona-private-data"
assert_file "$LOCAL_ROOT/state/state.conf"
assert_file "$LOCAL_ROOT/private/shared/profile.md"
assert_file "$LOCAL_ROOT/state/v1-project-memory-report.txt"
assert_contains "$LOCAL_ROOT/state/v1-project-memory-report.txt" 'legacy-project-decision'
assert_not_file "$LOCAL_ROOT/state.conf"
assert_dir "$LOCAL_ROOT/private/journals/loop"
assert_dir "$LOCAL_ROOT/private/journals/soul"
assert_dir "$LOCAL_ROOT/private/journals/core"
[[ "$(stat -f '%Lp' "$LOCAL_ROOT")" == "700" ]] || fail 'local root permission is not 0700'
[[ "$(stat -f '%Lp' "$LOCAL_ROOT/private/shared/profile.md")" == "600" ]] || fail 'migrated memory permission is not 0600'

assert_contains "$TEST_CODEX/AGENTS.md" '# Existing global instruction'
assert_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_file "$TEST_CODEX/agents/soul.toml"
assert_file "$TEST_CODEX/agents/core.toml"
assert_file "$TEST_CODEX/skills/persona-council/SKILL.md"
assert_file "$TEST_BIN/persona"
assert_contains "$TEST_CODEX/config.toml" 'notify = ["keep-me"]'
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-terra"'
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-luna"'

# Reinstall is idempotent and keeps one managed block.
cp "$TEST_CODEX/AGENTS.md" "$TEST_ROOT/AGENTS.first.md"
PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null
[[ "$(grep -Fc '<!-- LOOP-PERSONA-TEAM:START -->' "$TEST_CODEX/AGENTS.md")" == "1" ]] || fail 'install is not idempotent'
cmp -s "$TEST_ROOT/AGENTS.first.md" "$TEST_CODEX/AGENTS.md" || fail 'reinstall changed the managed instructions unexpectedly'

# Profile and individual model state are local. These checks never invoke a model.
run_persona profile economy >/dev/null
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-luna"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "max"'
run_persona profile balanced >/dev/null
assert_contains "$TEST_CODEX/config.toml" 'model = "gpt-5.6-terra"'
run_persona model set soul terra high >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-terra"'
assert_contains "$TEST_CODEX/agents/soul.toml" 'model_reasoning_effort = "high"'
run_persona model reset soul >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model = "gpt-5.6-luna"'
if run_persona model set soul luna ultra >/dev/null 2>&1; then fail 'Luna ultra was accepted'; fi
run_persona model set soul terra ultra >/dev/null
assert_contains "$TEST_CODEX/agents/soul.toml" 'model_reasoning_effort = "ultra"'
run_persona model reset soul >/dev/null

status_file="$TEST_ROOT/status.txt"
run_persona status > "$status_file"
assert_contains "$status_file" 'platform: macOS only'
assert_contains "$status_file" 'soul: gpt-5.6-luna / max (source: profile balanced)'
assert_contains "$status_file" 'Git sync: disabled'

# A failed strict configuration check restores config and local profile state.
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
assert_contains "$LOCAL_ROOT/state/state.conf" 'profile=balanced'

# Global Persona memory stays local, requires approval, and rejects unsafe content.
private_before="$(tree_fingerprint "$LOCAL_ROOT/private")"
source_before="$(git -C "$SOURCE" status --porcelain)"
if run_persona memory add --scope global --audience soul --summary '미승인' --text '기록되면 안 됨' >/dev/null 2>&1; then fail 'unapproved memory was accepted'; fi
if run_persona memory add --scope project --audience shared --summary '프로젝트' --text '잘못된 위치' --approved >/dev/null 2>&1; then fail 'project-scoped memory was accepted'; fi
if run_persona memory add --scope global --audience shared --summary 'secret' --text 'api_key=do-not-store' --approved >/dev/null 2>&1; then fail 'secret-like memory was accepted'; fi
if run_persona memory add --scope global --audience shared --summary '민감 추론' --text '정치 성향인 것 같다' --approved >/dev/null 2>&1; then fail 'sensitive inference was accepted'; fi
[[ "$(tree_fingerprint "$LOCAL_ROOT/private")" == "$private_before" ]] || fail 'rejected memory changed private files'

memory_output="$(run_persona memory add --scope global --audience soul --kind reflection --summary '첫 승인 기억' --text '첫 테스트 관계 기록입니다.' --approved)"
memory_id="$(printf '%s\n' "$memory_output" | sed -n 's/.*기록했습니다: //p')"
[[ -n "$memory_id" ]] || fail 'memory ID was not returned'
memory_file="$(find "$LOCAL_ROOT/private/journals/soul" -type f -name "$memory_id.md" -print -quit)"
assert_file "$memory_file"
[[ "$(stat -f '%Lp' "$memory_file")" == "600" ]] || fail 'local memory permission is not 0600'
context_file="$TEST_ROOT/context.txt"
run_persona context soul > "$context_file"
assert_contains "$context_file" "$memory_id"
assert_contains "$context_file" '첫 테스트 관계 기록입니다.'
if run_persona memory retract "$memory_id" >/dev/null 2>&1; then fail 'unapproved retraction was accepted'; fi
run_persona memory retract "$memory_id" --approved >/dev/null
run_persona context soul > "$context_file"
assert_not_contains "$context_file" "$memory_id"
run_persona memory status > "$TEST_ROOT/memory-status.txt"
assert_contains "$TEST_ROOT/memory-status.txt" 'profile: present'
assert_contains "$TEST_ROOT/memory-status.txt" 'sync: disabled (local Mac only)'
[[ "$(git -C "$SOURCE" status --porcelain)" == "$source_before" ]] || fail 'local memory changed the Persona source worktree'

# Initialize PARA documents in a separate project without committing them.
game_head_before="$(git -C "$GAME" rev-parse HEAD)"
run_persona_in "$GAME" project init --name '작은 게임' >/dev/null
DOCS="$GAME/docs/persona"
assert_file "$DOCS/project.md"
assert_file "$DOCS/NOW.md"
for category in projects meetings resources decisions indexes; do assert_dir "$DOCS/$category"; done
for index in projects meetings resources decisions archive backlinks; do assert_file "$DOCS/indexes/$index.md"; done
project_id="$(sed -n 's/^id: "\([^"]*\)"/\1/p' "$DOCS/project.md" | head -n 1)"
[[ "$project_id" == project-* ]] || fail 'project UUID was not created'
run_persona_in "$GAME" project init --name '작은 게임' >/dev/null
[[ "$(sed -n 's/^id: "\([^"]*\)"/\1/p' "$DOCS/project.md" | head -n 1)" == "$project_id" ]] || fail 'project UUID changed on reconnect'
run_persona_in "$GAME" project validate >/dev/null
[[ "$(git -C "$GAME" rev-parse HEAD)" == "$game_head_before" ]] || fail 'project initialization created a commit'

cp "$DOCS/NOW.md" "$TEST_ROOT/NOW.clean.md"
printf '\n[local](/Users/example/private.md)\n' >> "$DOCS/NOW.md"
if run_persona_in "$GAME" project validate >/dev/null 2>&1; then fail 'absolute project link was accepted'; fi
cp "$TEST_ROOT/NOW.clean.md" "$DOCS/NOW.md"
printf '\n[escape](../../README.md)\n' >> "$DOCS/NOW.md"
if run_persona_in "$GAME" project validate >/dev/null 2>&1; then fail 'project link escaping docs/persona was accepted'; fi
cp "$TEST_ROOT/NOW.clean.md" "$DOCS/NOW.md"

# Bind exact task IDs and preserve local cursors.
run_persona_in "$GAME" team bind loop task-loop host-local >/dev/null
run_persona_in "$GAME" team bind soul task-soul host-local >/dev/null
run_persona_in "$GAME" team bind core task-core host-local >/dev/null
run_persona_in "$GAME" team cursor set soul turn-20 >/dev/null
run_persona_in "$GAME" team status > "$TEST_ROOT/team-status.txt"
assert_contains "$TEST_ROOT/team-status.txt" 'loop: task-loop / host-local'
assert_contains "$TEST_ROOT/team-status.txt" 'soul: task-soul / host-local'
assert_contains "$TEST_ROOT/team-status.txt" 'soul cursor: turn-20'

handoff_output="$(run_persona_in "$GAME" handoff add --persona soul --source task-soul --summary '선택 후보' --text '플레이어 피드백을 먼저 확인합니다.' --cursor turn-21)"
handoff_id="$(printf '%s\n' "$handoff_output" | sed -n 's/.*보관했습니다: //p')"
[[ -n "$handoff_id" ]] || fail 'handoff candidate ID was not returned'
run_persona_in "$GAME" handoff list > "$TEST_ROOT/handoffs.txt"
assert_contains "$TEST_ROOT/handoffs.txt" "$handoff_id"
[[ "$(run_persona_in "$GAME" team cursor get soul)" == 'turn-21' ]] || fail 'handoff cursor did not advance after atomic save'

# A meeting draft is local and read-only; publication needs separate approval.
docs_before="$(tree_fingerprint "$DOCS")"
meeting_output="$(run_persona_in "$GAME" meeting draft --summary '첫 팀 회의' --text '같은 패킷을 소울과 코어에게 전달합니다.')"
meeting_id="$(printf '%s\n' "$meeting_output" | sed -n 's/.*만들었습니다: //p')"
[[ -n "$meeting_id" ]] || fail 'meeting draft ID was not returned'
[[ "$(tree_fingerprint "$DOCS")" == "$docs_before" ]] || fail 'meeting draft changed project documents'
if run_persona_in "$GAME" meeting publish "$meeting_id" --title '첫 팀 회의' --text '작게 검증한 뒤 확장합니다.' >/dev/null 2>&1; then fail 'unapproved meeting publication was accepted'; fi
[[ "$(tree_fingerprint "$DOCS")" == "$docs_before" ]] || fail 'rejected meeting publication changed project documents'

run_persona_in "$GAME" meeting publish "$meeting_id" --title '첫 팀 회의' --text '작게 검증한 뒤 확장합니다.' --decision-title '첫 구현 범위' --decision-text '한 개의 작은 플레이 루프부터 만듭니다.' --approved >/dev/null
meeting_file="$DOCS/meetings/$meeting_id.md"
assert_file "$meeting_file"
assert_contains "$meeting_file" 'immutable: true'
assert_contains "$meeting_file" 'sealed_sha256:'
decision_file="$(find "$DOCS/decisions" -maxdepth 1 -type f -name 'decision-*.md' -print -quit)"
assert_file "$decision_file"
assert_contains "$DOCS/indexes/meetings.md" "$meeting_id.md"
assert_contains "$DOCS/indexes/backlinks.md" "$(basename "$decision_file")"
assert_not_file "$LOCAL_ROOT/pending/meetings/$project_id/$meeting_id.md"
run_persona_in "$GAME" project validate >/dev/null

cp "$meeting_file" "$TEST_ROOT/meeting.sealed.md"
printf '\n몰래 바꾼 내용\n' >> "$meeting_file"
if run_persona_in "$GAME" project validate >/dev/null 2>&1; then fail 'modified sealed meeting was accepted'; fi
cp "$TEST_ROOT/meeting.sealed.md" "$meeting_file"

# Writer locks prevent overlap and allow approved stale-lock recovery.
run_persona_in "$GAME" writer acquire soul 'UX implementation' task-soul >/dev/null
if run_persona_in "$GAME" writer acquire core 'architecture' task-core >/dev/null 2>&1; then fail 'overlapping writer was accepted'; fi
run_persona_in "$GAME" writer release soul >/dev/null
run_persona_in "$GAME" writer acquire core 'architecture' task-core >/dev/null
touch -t 202001010000 "$LOCAL_ROOT/state/writer-locks/$project_id.lock"
PERSONA_LOCK_STALE_MINUTES=0 run_persona_in "$GAME" writer recover --approved >/dev/null
run_persona_in "$GAME" writer status > "$TEST_ROOT/writer-status.txt"
assert_contains "$TEST_ROOT/writer-status.txt" 'writer: <none>'

# A busy writer blocks the whole approved meeting transaction.
second_output="$(run_persona_in "$GAME" meeting draft --summary '잠금 회의' --text '잠금 중에는 게시하지 않습니다.')"
second_id="$(printf '%s\n' "$second_output" | sed -n 's/.*만들었습니다: //p')"
run_persona_in "$GAME" writer acquire core 'other work' task-core >/dev/null
docs_before="$(tree_fingerprint "$DOCS")"
if run_persona_in "$GAME" meeting publish "$second_id" --title '잠금 회의' --text '게시되면 안 됩니다.' --approved >/dev/null 2>&1; then fail 'meeting published through an active writer lock'; fi
[[ "$(tree_fingerprint "$DOCS")" == "$docs_before" ]] || fail 'blocked meeting transaction changed project documents'
run_persona_in "$GAME" writer release core >/dev/null

run_persona_in "$GAME" project index --approved >/dev/null
run_persona_in "$GAME" project validate >/dev/null
[[ "$(git -C "$GAME" rev-parse HEAD)" == "$game_head_before" ]] || fail 'project helpers created a commit'

# The removed sync command fails without changing memory or Git.
private_before="$(tree_fingerprint "$LOCAL_ROOT/private")"
source_head_before="$(git -C "$SOURCE" rev-parse HEAD)"
if run_persona sync > "$TEST_ROOT/sync.txt" 2>&1; then fail 'removed sync command succeeded'; fi
assert_contains "$TEST_ROOT/sync.txt" 'persona update'
[[ "$(tree_fingerprint "$LOCAL_ROOT/private")" == "$private_before" ]] || fail 'removed sync changed local memory'
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$source_head_before" ]] || fail 'removed sync created a commit'

# A code-only update installs local source without commits, pushes, or memory changes.
protected_before="$(protected_local_fingerprint "$LOCAL_ROOT")"
PERSONA_UPDATE_SKIP_PULL=1 run_persona update >/dev/null
[[ "$(tree_fingerprint "$LOCAL_ROOT/private")" == "$private_before" ]] || fail 'code update changed local memory'
[[ "$(protected_local_fingerprint "$LOCAL_ROOT")" == "$protected_before" ]] || fail 'code update changed protected local state'
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$source_head_before" ]] || fail 'code update changed Git history'
[[ -z "$(git -C "$SOURCE" status --porcelain)" ]] || fail 'code update dirtied the Persona source worktree'

run_persona doctor >/dev/null

# Uninstall requires the exact phrase and deletes only Persona-owned local data.
if run_persona uninstall --confirm WRONG >/dev/null 2>&1; then fail 'wrong uninstall phrase was accepted'; fi
assert_dir "$LOCAL_ROOT"
cp "$LOCAL_ROOT/.persona-team-root" "$TEST_ROOT/root-marker.safe"
awk '{ if ($0 ~ /^root=/) print "root=/"; else print }' "$LOCAL_ROOT/.persona-team-root" > "$TEST_ROOT/root-marker.unsafe"
mv "$TEST_ROOT/root-marker.unsafe" "$LOCAL_ROOT/.persona-team-root"
chmod 600 "$LOCAL_ROOT/.persona-team-root"
if run_persona uninstall --confirm DELETE-PERSONA-DATA >/dev/null 2>&1; then fail 'uninstall accepted a broad mismatched root marker'; fi
assert_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
cp "$TEST_ROOT/root-marker.safe" "$LOCAL_ROOT/.persona-team-root"
run_persona uninstall --confirm DELETE-PERSONA-DATA >/dev/null
assert_not_exists "$LOCAL_ROOT"
assert_not_contains "$TEST_CODEX/AGENTS.md" '<!-- LOOP-PERSONA-TEAM:START -->'
assert_contains "$TEST_CODEX/AGENTS.md" '# Existing global instruction'
assert_not_file "$TEST_CODEX/agents/soul.toml"
assert_not_file "$TEST_CODEX/agents/core.toml"
assert_not_exists "$TEST_CODEX/skills/persona-council"
assert_not_file "$TEST_BIN/persona"
assert_contains "$TEST_CODEX/config.toml" 'model = "user-model"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "high"'
assert_contains "$TEST_CODEX/config.toml" 'notify = ["keep-me"]'
assert_file "$TEST_CODEX/memories/native.md"
assert_file "$SOURCE/README.md"
assert_file "$DOCS/project.md"

# A symlink anywhere inside local Persona data blocks deletion, and user model edits survive a later safe uninstall.
PERSONA_CODEX_DIR="$TEST_CODEX" PERSONA_BIN_DIR="$TEST_BIN" PERSONA_SKIP_PATH_UPDATE=1 PERSONA_SKIP_CODEX_VALIDATE=1 PERSONA_SOURCE_ROOT="$SOURCE" \
  "$SOURCE/scripts/install.sh" >/dev/null
awk '{ if ($0 ~ /^model =/) print "model = \"changed-after-install\""; else print }' "$TEST_CODEX/config.toml" > "$TEST_ROOT/config.changed.toml"
mv "$TEST_ROOT/config.changed.toml" "$TEST_CODEX/config.toml"
printf 'outside data\n' > "$TEST_ROOT/outside.txt"
ln -s "$TEST_ROOT/outside.txt" "$TEST_CODEX/persona-team/private/unsafe-link"
if run_persona uninstall --confirm DELETE-PERSONA-DATA >/dev/null 2>&1; then fail 'uninstall accepted a symlinked local data tree'; fi
assert_file "$TEST_ROOT/outside.txt"
assert_dir "$TEST_CODEX/persona-team"
rm -f -- "$TEST_CODEX/persona-team/private/unsafe-link"
run_persona uninstall --confirm DELETE-PERSONA-DATA >/dev/null
assert_contains "$TEST_CODEX/config.toml" 'model = "changed-after-install"'
assert_contains "$TEST_CODEX/config.toml" 'model_reasoning_effort = "high"'
assert_file "$TEST_CODEX/memories/native.md"
assert_file "$DOCS/project.md"

printf 'All macOS Persona Team v2 tests passed without model calls.\n'
