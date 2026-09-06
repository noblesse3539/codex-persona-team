#!/usr/bin/env bash
# LOOP-PERSONA-TEAM:LAUNCHER

set -euo pipefail

PERSONA_VERSION="2.0.0"
PERSONA_SCHEMA_VERSION="2"
AGENTS_START="<!-- LOOP-PERSONA-TEAM:START -->"
AGENTS_END="<!-- LOOP-PERSONA-TEAM:END -->"
PATH_START="# LOOP-PERSONA-TEAM:PATH:START"
PATH_END="# LOOP-PERSONA-TEAM:PATH:END"
MANAGED_AGENT_MARKER="# Managed by Loop Persona Team"
LAUNCHER_MARKER="# LOOP-PERSONA-TEAM:LAUNCHER"

die() {
  printf 'persona: 오류: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'persona: 경고: %s\n' "$*" >&2
}

info() {
  printf 'persona: %s\n' "$*"
}

persona_codex_dir() {
  if [[ -n "${PERSONA_CODEX_DIR:-}" ]]; then
    printf '%s\n' "$PERSONA_CODEX_DIR"
  elif [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s\n' "$HOME/.codex"
  fi
}

persona_bin_dir() {
  if [[ -n "${PERSONA_BIN_DIR:-}" ]]; then
    printf '%s\n' "$PERSONA_BIN_DIR"
  else
    printf '%s/bin\n' "$(persona_codex_dir)"
  fi
}

CODEX_DIR="$(persona_codex_dir)"
PERSONA_ROOT="$CODEX_DIR/persona-team"
PRIVATE_DIR="$PERSONA_ROOT/private"
STATE_DIR="$PERSONA_ROOT/state"
STATE_FILE="$STATE_DIR/state.conf"
LEGACY_STATE_FILE="$PERSONA_ROOT/state.conf"
LEGACY_PROJECT_MAP="$PERSONA_ROOT/projects.tsv"
BACKUP_DIR="$PERSONA_ROOT/backups"
PENDING_DIR="$PERSONA_ROOT/pending"
SHARED_MEMORY_DIR="$PRIVATE_DIR/shared/entries"
JOURNAL_DIR="$PRIVATE_DIR/journals"
CAPSULE_DIR="$PRIVATE_DIR/capsules"
RETRACTION_DIR="$PRIVATE_DIR/retractions"
PRIVATE_INDEX_DIR="$PRIVATE_DIR/indexes"
PROJECT_STATE_DIR="$STATE_DIR/projects"
PROJECT_MAP="$PROJECT_STATE_DIR/paths.tsv"
TASK_BINDING_DIR="$STATE_DIR/task-bindings"
CURSOR_DIR="$STATE_DIR/cursors"
WRITER_LOCK_DIR="$STATE_DIR/writer-locks"
MODEL_OVERRIDE_DIR="$STATE_DIR/model-overrides"
HANDOFF_DIR="$PENDING_DIR/handoffs"
MEETING_DRAFT_DIR="$PENDING_DIR/meetings"
ROOT_MARKER="$PERSONA_ROOT/.persona-team-root"
PRIVATE_MARKER="$PRIVATE_DIR/.persona-private-data"

timestamp() {
  date -u '+%Y%m%dT%H%M%SZ'
}

platform_name() {
  if [[ -n "${PERSONA_TEST_UNAME:-}" ]]; then
    printf '%s\n' "$PERSONA_TEST_UNAME"
  else
    uname -s
  fi
}

require_macos() {
  [[ "$(platform_name)" == "Darwin" ]] \
    || die "Persona Team v2는 macOS에서만 실행할 수 있습니다."
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf '%s-%s-%s' "$(timestamp)" "$$" "$RANDOM" | hash_text
  fi
}

chmod_private_tree() {
  [[ -d "$PERSONA_ROOT" ]] || return 0
  find "$PERSONA_ROOT" -type d -exec chmod 700 {} + 2>/dev/null || true
  find "$PRIVATE_DIR" "$STATE_DIR" "$PENDING_DIR" "$BACKUP_DIR" -type f -exec chmod 600 {} + 2>/dev/null || true
}

create_local_layout() {
  local install_id root_physical tmp
  [[ ! -L "$PERSONA_ROOT" ]] || die "Persona 로컬 루트가 심볼릭 링크라서 사용할 수 없습니다: $PERSONA_ROOT"
  mkdir -p "$SHARED_MEMORY_DIR" "$JOURNAL_DIR/loop" "$JOURNAL_DIR/soul" "$JOURNAL_DIR/core" \
    "$CAPSULE_DIR" "$RETRACTION_DIR" "$PRIVATE_INDEX_DIR" "$PROJECT_STATE_DIR" \
    "$TASK_BINDING_DIR" "$CURSOR_DIR" "$WRITER_LOCK_DIR" "$MODEL_OVERRIDE_DIR" "$HANDOFF_DIR" "$MEETING_DRAFT_DIR" "$BACKUP_DIR"

  if [[ ! -f "$STATE_FILE" && -f "$LEGACY_STATE_FILE" && ! -L "$LEGACY_STATE_FILE" ]]; then
    cp -p "$LEGACY_STATE_FILE" "$STATE_FILE"
  fi
  if [[ ! -f "$PROJECT_MAP" && -f "$LEGACY_PROJECT_MAP" && ! -L "$LEGACY_PROJECT_MAP" ]]; then
    cp -p "$LEGACY_PROJECT_MAP" "$PROJECT_MAP"
  fi

  install_id="$(state_get install_id 2>/dev/null || true)"
  if [[ -z "$install_id" ]]; then
    install_id="$(new_uuid)"
    state_set install_id "$install_id"
  fi
  root_physical="$(cd "$PERSONA_ROOT" && pwd -P)"
  tmp="$(mktemp "$PERSONA_ROOT/.root-marker.XXXXXX")"
  {
    printf 'schema_version=%s\n' "$PERSONA_SCHEMA_VERSION"
    printf 'install_id=%s\n' "$install_id"
    printf 'root=%s\n' "$root_physical"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ROOT_MARKER"
  tmp="$(mktemp "$PRIVATE_DIR/.private-marker.XXXXXX")"
  {
    printf 'schema_version=%s\n' "$PERSONA_SCHEMA_VERSION"
    printf 'install_id=%s\n' "$install_id"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$PRIVATE_MARKER"
  chmod_private_tree
}

state_get() {
  local key="$1" source="$STATE_FILE"
  if [[ ! -f "$source" && -f "$LEGACY_STATE_FILE" ]]; then source="$LEGACY_STATE_FILE"; fi
  [[ -f "$source" && ! -L "$source" ]] || return 1
  awk -v wanted="$key" '
    index($0, wanted "=") == 1 {
      print substr($0, length(wanted) + 2)
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$source"
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp
  [[ "$key" =~ ^[a-z0-9_]+$ ]] || die "잘못된 상태 키입니다: $key"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "상태 값에는 줄바꿈을 넣을 수 없습니다."
  [[ ! -L "$STATE_DIR" && ! -L "$STATE_FILE" ]] || die "Persona 상태 경로가 심볼릭 링크입니다."
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
  if [[ -f "$STATE_FILE" ]]; then
    awk -v wanted="$key" -v replacement="$value" '
      index($0, wanted "=") == 1 {
        if (!written) print wanted "=" replacement
        written = 1
        next
      }
      { print }
      END { if (!written) print wanted "=" replacement }
    ' "$STATE_FILE" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$STATE_FILE"
}

resolve_repo_root() {
  local script_dir candidate
  if [[ -n "${PERSONA_SOURCE_ROOT:-}" ]]; then
    candidate="$PERSONA_SOURCE_ROOT"
  elif candidate="$(state_get repo_root 2>/dev/null)"; then
    :
  else
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    candidate="$(cd "$script_dir/.." && pwd -P)"
  fi
  [[ -d "$candidate/canon" && -d "$candidate/templates" && -d "$candidate/skills/persona-council" ]] \
    || die "Persona 저장소를 찾을 수 없습니다: $candidate"
  (cd "$candidate" && pwd -P)
}

toml_root_get() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  awk -v wanted="$key" '
    /^[[:space:]]*\[/ { exit }
    $0 ~ "^[[:space:]]*" wanted "[[:space:]]*=" {
      line = $0
      sub("^[[:space:]]*" wanted "[[:space:]]*=[[:space:]]*", "", line)
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]*\"|\"[[:space:]]*$/, "", line)
      print line
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$file"
}

write_config_pair() {
  local model="$1"
  local effort="$2"
  local config="$CODEX_DIR/config.toml"
  local tmp backup had_config=0
  [[ ! -L "$config" ]] || die "심볼릭 링크 config.toml은 안전하게 변경할 수 없어 중단했습니다: $config"
  mkdir -p "$CODEX_DIR" "$BACKUP_DIR"
  tmp="$(mktemp "$CODEX_DIR/.config.persona.XXXXXX")"
  if [[ -f "$config" ]]; then
    had_config=1
    awk -v wanted_model="$model" -v wanted_effort="$effort" '
      function emit_missing() {
        if (!model_seen && wanted_model != "__missing__") print "model = \"" wanted_model "\""
        if (!effort_seen && wanted_effort != "__missing__") print "model_reasoning_effort = \"" wanted_effort "\""
      }
      BEGIN { root = 1 }
      root && /^[[:space:]]*\[/ {
        emit_missing()
        root = 0
      }
      root && /^[[:space:]]*model[[:space:]]*=/ {
        if (!model_seen && wanted_model != "__missing__") print "model = \"" wanted_model "\""
        model_seen = 1
        next
      }
      root && /^[[:space:]]*model_reasoning_effort[[:space:]]*=/ {
        if (!effort_seen && wanted_effort != "__missing__") print "model_reasoning_effort = \"" wanted_effort "\""
        effort_seen = 1
        next
      }
      { print }
      END { if (root) emit_missing() }
    ' "$config" > "$tmp"
    backup="$BACKUP_DIR/config.toml.$(timestamp).$$.bak"
    cp -p "$config" "$backup"
  else
    : > "$tmp"
    if [[ "$model" != "__missing__" ]]; then printf 'model = "%s"\n' "$model" >> "$tmp"; fi
    if [[ "$effort" != "__missing__" ]]; then printf 'model_reasoning_effort = "%s"\n' "$effort" >> "$tmp"; fi
    backup=""
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$config"

  if [[ "${PERSONA_SKIP_CODEX_VALIDATE:-0}" != "1" ]] && command -v codex >/dev/null 2>&1; then
    if ! codex --strict-config --version >/dev/null 2>&1; then
      if [[ "$had_config" == "1" ]]; then
        cp -p "$backup" "$config"
      else
        rm -f "$config"
      fi
      die "Codex 설정 검증에 실패해 기존 config.toml을 복원했습니다."
    fi
  fi
}

profile_value() {
  local profile="$1" persona="$2" field="$3"
  case "$profile:$persona:$field" in
    economy:loop:model|economy:soul:model|economy:core:model) printf '%s\n' "gpt-5.6-luna" ;;
    balanced:loop:model) printf '%s\n' "gpt-5.6-terra" ;;
    balanced:soul:model|balanced:core:model) printf '%s\n' "gpt-5.6-luna" ;;
    max:loop:model|max:soul:model|max:core:model) printf '%s\n' "gpt-5.6-sol" ;;
    economy:loop:effort|economy:soul:effort|economy:core:effort|balanced:loop:effort|balanced:soul:effort|balanced:core:effort|max:loop:effort|max:soul:effort|max:core:effort) printf '%s\n' "max" ;;
    *) die "알 수 없는 프로필 값입니다: $profile/$persona/$field" ;;
  esac
}

effective_value() {
  local persona="$1" field="$2" profile override
  profile="$(state_get profile 2>/dev/null || printf '%s' economy)"
  override="$(state_get "override_${persona}_${field}" 2>/dev/null || true)"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
  else
    profile_value "$profile" "$persona" "$field"
  fi
}

validate_persona() {
  case "$1" in loop|soul|core) ;; *) die "페르소나는 loop, soul, core 중 하나여야 합니다." ;; esac
}

normalize_model() {
  case "$1" in
    luna|gpt-5.6-luna) printf '%s\n' "gpt-5.6-luna" ;;
    terra|gpt-5.6-terra) printf '%s\n' "gpt-5.6-terra" ;;
    sol|gpt-5.6-sol|gpt-5.6) printf '%s\n' "gpt-5.6-sol" ;;
    *) die "모델은 luna, terra, sol 중 하나여야 합니다." ;;
  esac
}

validate_effort() {
  local model="$1" effort="$2"
  case "$effort" in
    low|medium|high|xhigh|max) ;;
    ultra)
      [[ "$model" != "gpt-5.6-luna" ]] || die "Luna는 ultra를 지원하지 않습니다. low, medium, high, xhigh, max 중에서 선택하세요."
      ;;
    *) die "추론 강도는 low, medium, high, xhigh, max, ultra 중 하나여야 합니다." ;;
  esac
}

render_agent() {
  local repo="$1" persona="$2" model="$3" effort="$4"
  local source="$repo/templates/agents/$persona.toml.in"
  local target="$CODEX_DIR/agents/$persona.toml"
  local tmp
  [[ -f "$source" ]] || die "에이전트 템플릿이 없습니다: $source"
  [[ ! -L "$target" ]] || die "심볼릭 링크 에이전트 파일은 변경하지 않습니다: $target"
  mkdir -p "$CODEX_DIR/agents" "$BACKUP_DIR"
  if [[ -f "$target" ]]; then
    cp -p "$target" "$BACKUP_DIR/$persona.toml.$(timestamp).$$.bak"
  fi
  tmp="$(mktemp "$CODEX_DIR/agents/.$persona.XXXXXX")"
  sed -e "s|@@MODEL@@|$model|g" -e "s|@@EFFORT@@|$effort|g" "$source" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$target"
}

write_model_state_snapshot() {
  local persona profile model effort source tmp target
  profile="$(state_get profile 2>/dev/null || printf economy)"
  mkdir -p "$MODEL_OVERRIDE_DIR"
  for persona in loop soul core; do
    model="$(effective_value "$persona" model)"; effort="$(effective_value "$persona" effort)"
    if [[ -n "$(state_get "override_${persona}_model" 2>/dev/null || true)" ]]; then source="local-override"; else source="profile-$profile"; fi
    target="$MODEL_OVERRIDE_DIR/$persona.conf"; tmp="$(mktemp "$MODEL_OVERRIDE_DIR/.$persona.XXXXXX")"
    printf 'profile=%s\nmodel=%s\neffort=%s\nsource=%s\n' "$profile" "$model" "$effort" "$source" > "$tmp"
    chmod 600 "$tmp"; mv "$tmp" "$target"
  done
}

apply_models() {
  local repo loop_model loop_effort soul_model soul_effort core_model core_effort
  repo="$(resolve_repo_root)"
  loop_model="$(effective_value loop model)"
  loop_effort="$(effective_value loop effort)"
  soul_model="$(effective_value soul model)"
  soul_effort="$(effective_value soul effort)"
  core_model="$(effective_value core model)"
  core_effort="$(effective_value core effort)"

  write_config_pair "$loop_model" "$loop_effort"
  render_agent "$repo" soul "$soul_model" "$soul_effort"
  render_agent "$repo" core "$core_model" "$core_effort"
  state_set last_written_loop_model "$loop_model"
  state_set last_written_loop_effort "$loop_effort"
  write_model_state_snapshot
}

strip_managed_block() {
  local input="$1" start="$2" end="$3"
  awk -v begin="$start" -v finish="$end" '
    index($0, begin) { if (inside) bad = 1; inside = 1; starts++; next }
    index($0, finish) { if (!inside) bad = 1; inside = 0; ends++; next }
    !inside { print }
    END { if (inside || bad || starts != ends) exit 42 }
  ' "$input"
}

trim_trailing_blank_lines() {
  local file="$1" tmp
  tmp="$(mktemp "$(dirname "$file")/.persona-trim.XXXXXX")"
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

install_agents_block() {
  local repo="$1" target="$CODEX_DIR/AGENTS.md" block="$repo/templates/AGENTS.block.md"
  local tmp backup
  mkdir -p "$CODEX_DIR" "$BACKUP_DIR"
  [[ -f "$block" ]] || die "전역 AGENTS 템플릿이 없습니다."
  [[ ! -L "$target" ]] || die "심볼릭 링크 AGENTS.md는 안전하게 변경할 수 없어 중단했습니다: $target"
  [[ -f "$target" ]] || : > "$target"
  backup="$BACKUP_DIR/AGENTS.md.$(timestamp).$$.bak"
  cp -p "$target" "$backup"
  tmp="$(mktemp "$CODEX_DIR/.AGENTS.persona.XXXXXX")"
  if ! strip_managed_block "$target" "$AGENTS_START" "$AGENTS_END" > "$tmp"; then
    rm -f "$tmp"
    die "AGENTS.md의 Persona 관리 마커가 손상되어 변경하지 않았습니다."
  fi
  trim_trailing_blank_lines "$tmp"
  if [[ -s "$tmp" ]]; then printf '\n' >> "$tmp"; fi
  cat "$block" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$target"
}

install_skill() {
  local repo="$1" source="$repo/skills/persona-council" target="$CODEX_DIR/skills/persona-council"
  local archived tmp
  mkdir -p "$CODEX_DIR/skills" "$BACKUP_DIR"
  [[ ! -L "$target" ]] || die "심볼릭 링크 스킬 경로는 변경하지 않습니다: $target"
  tmp="$(mktemp -d "$CODEX_DIR/skills/.persona-council.XXXXXX")"
  cp -R "$source/." "$tmp/"
  {
    printf '# Installed runtime paths\n\n'
    printf -- '- Persona command: `%s/persona`\n' "$(persona_bin_dir)"
    printf -- '- Canonical repository: `%s`\n' "$repo"
    printf '\nThese paths are generated locally and are not synchronized to Git.\n'
  } > "$tmp/references/runtime-paths.md"
  if [[ -e "$target" ]]; then
    [[ -f "$target/.persona-team-managed" ]] || die "기존 persona-council 스킬이 이 설치기의 관리 대상이 아닙니다."
    archived="$BACKUP_DIR/persona-council.$(timestamp).$$"
    mv "$target" "$archived"
  fi
  mv "$tmp" "$target"
}

install_launcher() {
  local repo="$1" bin target tmp
  bin="$(persona_bin_dir)"
  target="$bin/persona"
  mkdir -p "$bin"
  [[ ! -L "$target" ]] || die "심볼릭 링크 persona 런처는 변경하지 않습니다: $target"
  if [[ -f "$target" ]]; then cp -p "$target" "$BACKUP_DIR/persona.$(timestamp).$$.bak"; fi
  tmp="$(mktemp "$bin/.persona.XXXXXX")"
  cp "$repo/scripts/persona.sh" "$tmp"
  chmod 700 "$tmp"
  mv "$tmp" "$target"
  state_set bin_dir "$bin"
}

install_path_entry() {
  local bin rc tmp quoted
  [[ "${PERSONA_SKIP_PATH_UPDATE:-0}" == "1" ]] && return 0
  bin="$(persona_bin_dir)"
  case ":$PATH:" in *":$bin:"*) return 0 ;; esac
  if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == */zsh ]]; then
    rc="${ZDOTDIR:-$HOME}/.zshrc"
  else
    rc="$HOME/.profile"
  fi
  [[ -f "$rc" ]] || : > "$rc"
  [[ ! -L "$rc" ]] || die "심볼릭 링크 셸 설정 파일은 안전하게 변경할 수 없어 중단했습니다: $rc"
  mkdir -p "$BACKUP_DIR"
  cp -p "$rc" "$BACKUP_DIR/$(basename "$rc").$(timestamp).$$.bak"
  tmp="$(mktemp "$(dirname "$rc")/.persona-rc.XXXXXX")"
  if ! strip_managed_block "$rc" "$PATH_START" "$PATH_END" > "$tmp"; then
    rm -f "$tmp"
    die "셸 PATH 관리 마커가 손상되어 변경하지 않았습니다."
  fi
  trim_trailing_blank_lines "$tmp"
  quoted="$(printf '%s' "$bin" | sed "s/'/'\\\\''/g")"
  if [[ -s "$tmp" ]]; then printf '\n' >> "$tmp"; fi
  {
    printf '%s\n' "$PATH_START"
    printf "export PATH='%s':\$PATH\n" "$quoted"
    printf '%s\n' "$PATH_END"
  } >> "$tmp"
  mv "$tmp" "$rc"
  state_set shell_rc "$rc"
}

check_install_conflicts() {
  local target rc launcher
  for target in "$STATE_FILE" "$CODEX_DIR/config.toml" "$CODEX_DIR/AGENTS.md"; do
    [[ ! -L "$target" ]] || die "심볼릭 링크 관리 대상은 변경하지 않습니다: $target"
  done
  for target in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml"; do
    [[ ! -L "$target" ]] || die "심볼릭 링크 관리 대상은 변경하지 않습니다: $target"
    if [[ -f "$target" ]] && ! grep -Fq "$MANAGED_AGENT_MARKER" "$target"; then
      die "기존 파일과 충돌합니다: $target"
    fi
  done
  target="$CODEX_DIR/skills/persona-council"
  [[ ! -L "$target" ]] || die "심볼릭 링크 관리 대상은 변경하지 않습니다: $target"
  if [[ -e "$target" && ! -f "$target/.persona-team-managed" ]]; then
    die "기존 스킬과 충돌합니다: $target"
  fi
  if [[ -f "$CODEX_DIR/AGENTS.md" ]] && ! strip_managed_block "$CODEX_DIR/AGENTS.md" "$AGENTS_START" "$AGENTS_END" >/dev/null; then
    die "AGENTS.md의 Persona 관리 마커가 손상되어 있습니다."
  fi
  if [[ "${PERSONA_SKIP_PATH_UPDATE:-0}" != "1" ]]; then
    if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == */zsh ]]; then rc="${ZDOTDIR:-$HOME}/.zshrc"; else rc="$HOME/.profile"; fi
    [[ ! -L "$rc" ]] || die "심볼릭 링크 셸 설정 파일은 안전하게 변경할 수 없어 중단했습니다: $rc"
    if [[ -f "$rc" ]] && ! strip_managed_block "$rc" "$PATH_START" "$PATH_END" >/dev/null; then
      die "셸 PATH 관리 마커가 손상되어 있습니다: $rc"
    fi
  fi
  launcher="$(persona_bin_dir)/persona"
  [[ ! -L "$launcher" ]] || die "심볼릭 링크 persona 런처는 변경하지 않습니다: $launcher"
  if [[ -e "$launcher" ]] && { [[ ! -f "$launcher" ]] || ! grep -Fq "$LAUNCHER_MARKER" "$launcher"; }; then
    die "기존 persona 명령과 충돌합니다: $launcher"
  fi
}

snapshot_install_target() {
  local transaction="$1" name="$2" target="$3"
  if [[ -e "$target" ]]; then
    cp -Rp "$target" "$transaction/$name"
    : > "$transaction/$name.present"
  else
    : > "$transaction/$name.absent"
  fi
}

restore_install_target() {
  local transaction="$1" name="$2" target="$3"
  [[ -n "$target" && "$target" != "/" ]] || die "복구 대상 경로가 안전하지 않습니다."
  if [[ -f "$transaction/$name.present" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then rm -rf -- "$target"; fi
    mkdir -p "$(dirname "$target")"
    cp -Rp "$transaction/$name" "$target"
  elif [[ -f "$transaction/$name.absent" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then rm -rf -- "$target"; fi
  fi
}

command_install() {
  local repo config original_model original_effort installed_state transaction install_status shell_rc=""
  require_macos
  validate_local_destination_precreate
  repo="$(resolve_repo_root)"
  create_local_layout
  validate_local_layout
  migrate_v1_memory_once
  check_install_conflicts
  mkdir -p "$STATE_DIR" "$BACKUP_DIR"
  config="$CODEX_DIR/config.toml"
  if [[ "${PERSONA_SKIP_PATH_UPDATE:-0}" != "1" ]]; then
    if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == */zsh ]]; then shell_rc="${ZDOTDIR:-$HOME}/.zshrc"; else shell_rc="$HOME/.profile"; fi
  fi
  transaction="$(mktemp -d "$STATE_DIR/.install-transaction.XXXXXX")"
  set +e
  (
    set -e
    snapshot_install_target "$transaction" state "$STATE_FILE"
    snapshot_install_target "$transaction" config "$config"
    snapshot_install_target "$transaction" agents "$CODEX_DIR/AGENTS.md"
    snapshot_install_target "$transaction" soul "$CODEX_DIR/agents/soul.toml"
    snapshot_install_target "$transaction" core "$CODEX_DIR/agents/core.toml"
    snapshot_install_target "$transaction" skill "$CODEX_DIR/skills/persona-council"
    snapshot_install_target "$transaction" launcher "$(persona_bin_dir)/persona"
    if [[ -n "$shell_rc" ]]; then snapshot_install_target "$transaction" shell_rc "$shell_rc"; fi

    installed_state="$(state_get installed 2>/dev/null || printf '%s' false)"
    if [[ "$installed_state" != "true" ]]; then
      original_model="$(toml_root_get "$config" model 2>/dev/null || printf '%s' __missing__)"
      original_effort="$(toml_root_get "$config" model_reasoning_effort 2>/dev/null || printf '%s' __missing__)"
      state_set original_model "$original_model"
      state_set original_effort "$original_effort"
    fi
    state_set repo_root "$repo"
    if ! state_get profile >/dev/null 2>&1; then state_set profile economy; fi
    for key in override_loop_model override_loop_effort override_soul_model override_soul_effort override_core_model override_core_effort; do
      if ! state_get "$key" >/dev/null 2>&1; then state_set "$key" ""; fi
    done
    apply_models
    install_agents_block "$repo"
    install_skill "$repo"
    install_launcher "$repo"
    install_path_entry
    state_set installed true
    state_set version "$PERSONA_VERSION"
  )
  install_status=$?
  set -e
  if (( install_status != 0 )); then
    restore_install_target "$transaction" config "$config"
    restore_install_target "$transaction" agents "$CODEX_DIR/AGENTS.md"
    restore_install_target "$transaction" soul "$CODEX_DIR/agents/soul.toml"
    restore_install_target "$transaction" core "$CODEX_DIR/agents/core.toml"
    restore_install_target "$transaction" skill "$CODEX_DIR/skills/persona-council"
    restore_install_target "$transaction" launcher "$(persona_bin_dir)/persona"
    if [[ -n "$shell_rc" ]]; then restore_install_target "$transaction" shell_rc "$shell_rc"; fi
    restore_install_target "$transaction" state "$STATE_FILE"
    rm -rf -- "$transaction"
    die "설치에 실패해 관리 대상 파일을 이전 상태로 복구했습니다."
  fi
  rm -rf -- "$transaction"
  rm -f -- "$LEGACY_STATE_FILE" "$LEGACY_PROJECT_MAP" "$PERSONA_ROOT/pending-memory.txt"
  if [[ "${PERSONA_SKIP_PENDING_CLEANUP:-0}" != "1" ]]; then cleanup_expired_pending; fi
  chmod_private_tree
  info "설치가 완료되었습니다. 활성 프로필: $(state_get profile)"
  if [[ ":$PATH:" != *":$(persona_bin_dir):"* ]]; then
    info "새 터미널을 열면 persona 명령을 사용할 수 있습니다."
  fi
}

command_profile() {
  local profile="${1:-}" state_backup
  [[ $# -eq 1 ]] || die "사용법: persona profile economy|balanced|max"
  case "$profile" in economy|balanced|max) ;; *) die "사용법: persona profile economy|balanced|max" ;; esac
  state_backup="$(mktemp "$STATE_DIR/.state-profile.XXXXXX")"
  cp -p "$STATE_FILE" "$state_backup"
  state_set profile "$profile"
  for persona in loop soul core; do
    state_set "override_${persona}_model" ""
    state_set "override_${persona}_effort" ""
  done
  if ! (apply_models); then
    cp -p "$state_backup" "$STATE_FILE"
    rm -f "$state_backup"
    die "프로필 적용에 실패해 이전 로컬 상태를 복원했습니다."
  fi
  rm -f "$state_backup"
  info "프로필을 $profile 로 변경했습니다. 열린 작업의 모델은 데스크톱 UI에서 별도로 바꾸세요."
}

command_model() {
  local action="${1:-}" persona="${2:-}" model effort state_backup
  case "$action" in
    set)
      [[ $# -eq 4 ]] || die "사용법: persona model set loop|soul|core luna|terra|sol <effort>"
      validate_persona "$persona"
      model="$(normalize_model "$3")"
      effort="$4"
      validate_effort "$model" "$effort"
      state_backup="$(mktemp "$STATE_DIR/.state-model.XXXXXX")"
      cp -p "$STATE_FILE" "$state_backup"
      state_set "override_${persona}_model" "$model"
      state_set "override_${persona}_effort" "$effort"
      if ! (apply_models); then
        cp -p "$state_backup" "$STATE_FILE"
        rm -f "$state_backup"
        die "모델 적용에 실패해 이전 로컬 상태를 복원했습니다."
      fi
      rm -f "$state_backup"
      info "$persona 모델을 $model / $effort 로 재정의했습니다."
      ;;
    reset)
      [[ $# -eq 2 ]] || die "사용법: persona model reset loop|soul|core"
      validate_persona "$persona"
      state_backup="$(mktemp "$STATE_DIR/.state-model.XXXXXX")"
      cp -p "$STATE_FILE" "$state_backup"
      state_set "override_${persona}_model" ""
      state_set "override_${persona}_effort" ""
      if ! (apply_models); then
        cp -p "$state_backup" "$STATE_FILE"
        rm -f "$state_backup"
        die "모델 초기화에 실패해 이전 로컬 상태를 복원했습니다."
      fi
      rm -f "$state_backup"
      info "$persona 모델을 현재 프로필 값으로 되돌렸습니다."
      ;;
    *) die "사용법: persona model set ... | persona model reset ..." ;;
  esac
}

hash_text() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print substr($1,1,12)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print substr($1,1,12)}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print substr($NF,1,12)}'
  else
    cksum | awk '{print $1}'
  fi
}

hash_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    die "기억 무결성 검사에 필요한 SHA-256 도구를 찾지 못했습니다."
  fi
}

hash_stream_full() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  else
    die "무결성 검사에 필요한 SHA-256 도구를 찾지 못했습니다."
  fi
}

document_seal_hash() {
  local file="$1"
  awk '!/^sealed_sha256:[[:space:]]*/ { print }' "$file" | hash_stream_full
}

copy_private_file_once() {
  local source="$1" target="$2"
  [[ -f "$source" && ! -L "$source" ]] || return 1
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" ]]; then
    if cmp -s "$source" "$target"; then return 0; fi
    warn "같은 이름의 로컬 기억이 이미 있어 v1 파일을 건너뜁니다: $target"
    return 1
  fi
  cp -p "$source" "$target"
  chmod 600 "$target"
}

migrate_v1_memory_from() {
  local legacy_repo="$1" migrated=0 file relative target report legacy_id
  [[ -n "$legacy_repo" && -d "$legacy_repo/memory" && ! -L "$legacy_repo/memory" ]] || return 1

  if [[ -f "$legacy_repo/memory/global/shared/profile.md" ]]; then
    if copy_private_file_once "$legacy_repo/memory/global/shared/profile.md" "$PRIVATE_DIR/shared/profile.md"; then
      migrated=$((migrated + 1))
    fi
  fi
  for file in \
    "$legacy_repo"/memory/global/shared/entries/*.md \
    "$legacy_repo"/memory/global/journals/loop/*.md \
    "$legacy_repo"/memory/global/journals/soul/*.md \
    "$legacy_repo"/memory/global/journals/core/*.md \
    "$legacy_repo"/memory/retractions/*.md; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    relative="${file#"$legacy_repo/memory/"}"
    case "$relative" in
      global/shared/entries/*) target="$SHARED_MEMORY_DIR/${file##*/}" ;;
      global/journals/loop/*) target="$JOURNAL_DIR/loop/${file##*/}" ;;
      global/journals/soul/*) target="$JOURNAL_DIR/soul/${file##*/}" ;;
      global/journals/core/*) target="$JOURNAL_DIR/core/${file##*/}" ;;
      retractions/*) target="$RETRACTION_DIR/${file##*/}" ;;
      *) continue ;;
    esac
    if copy_private_file_once "$file" "$target"; then migrated=$((migrated + 1)); fi
  done

  report="$STATE_DIR/v1-project-memory-report.txt"
  if [[ -d "$legacy_repo/memory/projects" ]]; then
    : > "$report"
    while IFS= read -r file; do
      legacy_id="$(frontmatter_value "$file" id 2>/dev/null || printf unknown)"
      printf '%s\t%s\n' "$legacy_id" "$file" >> "$report"
    done < <(find "$legacy_repo/memory/projects" -type f -name '*.md' -print 2>/dev/null | sort)
    chmod 600 "$report"
  fi
  if (( migrated > 0 )); then info "v1 전역 기억 ${migrated}개를 이 Mac의 로컬 저장소로 이전했습니다."; fi
  return 0
}

migrate_v1_memory_once() {
  local marker="$STATE_DIR/v1-memory-migrated" legacy_repo current_repo
  [[ ! -f "$marker" ]] || return 0
  legacy_repo="$(state_get repo_root 2>/dev/null || true)"
  current_repo="$(resolve_repo_root)"
  migrate_v1_memory_from "$legacy_repo" || true
  if [[ "$current_repo" != "$legacy_repo" ]]; then migrate_v1_memory_from "$current_repo" || true; fi
  {
    printf 'migrated_at=%s\n' "$(timestamp)"
    printf 'legacy_repo=%s\n' "$legacy_repo"
  } > "$marker"
  chmod 600 "$marker"
  rebuild_private_indexes
}

cleanup_expired_pending() {
  local dir
  for dir in "$HANDOFF_DIR" "$MEETING_DRAFT_DIR"; do
    [[ -d "$dir" && ! -L "$dir" ]] || continue
    find "$dir" -type f -name '*.md' -mtime +30 -delete 2>/dev/null || true
  done
}

path_is_within() {
  local child="$1" parent="$2"
  case "$child/" in "$parent/"*) return 0 ;; *) return 1 ;; esac
}

path_has_symlink_component() {
  local path="$1" current="/" part
  [[ "$path" == /* ]] || return 0
  path="${path#/}"
  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    if [[ "$current" == "/" ]]; then current="/$part"; else current="$current/$part"; fi
    [[ ! -L "$current" ]] || return 0
  done
  return 1
}

validate_local_destination_precreate() {
  local probe containing_git
  [[ "$CODEX_DIR" == /* && "$PERSONA_ROOT" == /* ]] || die "Persona 설치 경로는 절대 경로여야 합니다."
  case "$PERSONA_ROOT" in */../*|*/./*|/|"$HOME"|"$CODEX_DIR") die "Persona 설치 경로 범위가 안전하지 않습니다: $PERSONA_ROOT" ;; esac
  if path_has_symlink_component "$PERSONA_ROOT"; then
    die "Persona 로컬 경로가 심볼릭 링크를 통과합니다: $PERSONA_ROOT"
  fi
  probe="$CODEX_DIR"
  while [[ ! -d "$probe" ]]; do
    [[ "$probe" != "/" ]] || break
    probe="$(dirname "$probe")"
  done
  containing_git="$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$containing_git" ]] && path_is_within "$PERSONA_ROOT" "$(cd "$containing_git" && pwd -P)"; then
    die "Persona 로컬 데이터는 Git 작업 트리 안에 설치할 수 없습니다: $PERSONA_ROOT"
  fi
}

validate_local_layout() {
  local expected_root actual_root install_id marker_id private_marker_id marker_root repo containing_git
  [[ -d "$PERSONA_ROOT" && ! -L "$PERSONA_ROOT" ]] || die "Persona 전용 로컬 루트가 없거나 심볼릭 링크입니다: $PERSONA_ROOT"
  if path_has_symlink_component "$PERSONA_ROOT"; then
    die "Persona 로컬 경로가 심볼릭 링크를 통과합니다: $PERSONA_ROOT"
  fi
  [[ -f "$ROOT_MARKER" && ! -L "$ROOT_MARKER" && -f "$PRIVATE_MARKER" && ! -L "$PRIVATE_MARKER" ]] \
    || die "Persona 전용 로컬 데이터 식별 마커가 없습니다."
  expected_root="$(cd "$CODEX_DIR" && pwd -P)/persona-team"
  actual_root="$(cd "$PERSONA_ROOT" && pwd -P)"
  [[ "$actual_root" == "$expected_root" && "$actual_root" != "/" && "$actual_root" != "$HOME" && "$actual_root" != "$(cd "$CODEX_DIR" && pwd -P)" ]] \
    || die "Persona 로컬 루트 경로가 안전하지 않습니다: $actual_root"
  install_id="$(state_get install_id 2>/dev/null || true)"
  marker_id="$(awk -F= '$1=="install_id" {print substr($0,index($0,"=")+1); exit}' "$ROOT_MARKER")"
  private_marker_id="$(awk -F= '$1=="install_id" {print substr($0,index($0,"=")+1); exit}' "$PRIVATE_MARKER")"
  marker_root="$(awk -F= '$1=="root" {print substr($0,index($0,"=")+1); exit}' "$ROOT_MARKER")"
  [[ -n "$install_id" && "$marker_id" == "$install_id" && "$private_marker_id" == "$install_id" && "$marker_root" == "$actual_root" ]] \
    || die "Persona 로컬 데이터의 설치 식별자가 일치하지 않습니다."
  containing_git="$(git -C "$actual_root" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$containing_git" ]] && path_is_within "$actual_root" "$(cd "$containing_git" && pwd -P)"; then
    die "Persona 로컬 데이터가 Git 작업 트리 안에 있습니다: $actual_root"
  fi
  for repo in "$(resolve_repo_root 2>/dev/null || true)" "$(git rev-parse --show-toplevel 2>/dev/null || true)"; do
    [[ -z "$repo" ]] && continue
    repo="$(cd "$repo" && pwd -P)"
    if path_is_within "$actual_root" "$repo"; then die "Persona 로컬 데이터가 Git 작업 트리 안에 있습니다: $actual_root"; fi
  done
}

yaml_escape() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

contains_secret() {
  LC_ALL=C grep -Eqi '(BEGIN[[:space:]].*PRIVATE KEY|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|session[_ -]?cookie|password[[:space:]]*[:=]|secret[[:space:]]*[:=]|recovery[_ -]?code|sk-[A-Za-z0-9_-]{12,}|비밀번호[[:space:]]*[:=]|API[[:space:]]*키[[:space:]]*[:=]|(접근|갱신)?[[:space:]]*토큰[[:space:]]*[:=]|개인[[:space:]]*키[[:space:]]*[:=]|복구[[:space:]]*코드[[:space:]]*[:=])'
}

contains_sensitive_inference() {
  LC_ALL=C grep -Eqi '((정치|종교|성적[[:space:]]*지향|인종|민족|건강|장애|정신[[:space:]]*질환|노조|범죄|유전)[^\n]{0,30}(성향|같다|보인다|추정|추측|일[[:space:]]*것)|(political|religious|sexual orientation|ethnicity|race|health condition|disability|mental illness|union|criminal|genetic)[^\n]{0,40}(infer|likely|seems|probably))'
}

contains_local_project_metadata() {
  LC_ALL=C grep -Eqi '(/Users/[^ /]+/|/private/var/|/var/folders/|/home/[^ /]+/|~/?\.codex/|codex://|(^|[^A-Za-z])(thread|task|host)[_ -]?id[[:space:]]*:|^[[:space:]]*model(_reasoning_effort)?[[:space:]]*:)'
}

frontmatter_value() {
  local file="$1" key="$2"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  awk -v wanted="$key" '
    NR == 1 && $0 != "---" { exit 2 }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, wanted ":") == 1 {
      value=substr($0, length(wanted) + 2)
      sub(/^[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      found=1
      exit
    }
    END { if (!found) exit 1 }
  ' "$file"
}

validate_project_id() {
  [[ "$1" =~ ^project-[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "안전하지 않은 프로젝트 ID입니다: $1"
}

project_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  (cd "$root" && pwd -P)
}

validate_docs_relative_path() {
  local value="$1" part
  [[ -n "$value" && "$value" != /* && "$value" != "." && "$value" != */ ]] \
    || die "프로젝트 문서 경로는 프로젝트 안의 상대경로여야 합니다."
  [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] || die "프로젝트 문서 경로에는 영문자, 숫자, 점, 밑줄, 하이픈과 슬래시만 사용할 수 있습니다."
  IFS='/' read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || die "안전하지 않은 프로젝트 문서 경로입니다."; done
}

mapped_project_line() {
  local here root id rel name best="" best_len=0
  here="$(pwd -P)"
  [[ -f "$PROJECT_MAP" && ! -L "$PROJECT_MAP" ]] || return 1
  while IFS=$'\t' read -r root id rel name; do
    [[ -n "$root" && -n "$id" && -n "$rel" ]] || continue
    case "$here/" in
      "$root/"*) if (( ${#root} > best_len )); then best="$root"$'\t'"$id"$'\t'"$rel"$'\t'"$name"; best_len=${#root}; fi ;;
    esac
  done < "$PROJECT_MAP"
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

current_project_docs() {
  local line root id rel name manifest
  if line="$(mapped_project_line 2>/dev/null)"; then
    IFS=$'\t' read -r root id rel name <<< "$line"
    manifest="$root/$rel/project.md"
    if [[ -f "$manifest" && "$(frontmatter_value "$manifest" id 2>/dev/null || true)" == "$id" ]]; then
      validate_project_id "$id"
      printf '%s\t%s\t%s\t%s\n' "$root" "$id" "$rel" "$name"
      return 0
    fi
  fi
  root="$(project_root)"
  rel="docs/persona"
  manifest="$root/$rel/project.md"
  [[ -f "$manifest" ]] || return 1
  id="$(frontmatter_value "$manifest" id 2>/dev/null || true)"
  name="$(frontmatter_value "$manifest" name 2>/dev/null || basename "$root")"
  [[ -n "$id" ]] || return 1
  validate_project_id "$id"
  printf '%s\t%s\t%s\t%s\n' "$root" "$id" "$rel" "$name"
}

register_project() {
  local root="$1" id="$2" rel="$3" name="$4" allow_clone="${5:-0}" tmp old_root old_id old_rel old_name
  validate_project_id "$id"
  mkdir -p "$PROJECT_STATE_DIR"
  if [[ -f "$PROJECT_MAP" ]]; then
    while IFS=$'\t' read -r old_root old_id old_rel old_name; do
      if [[ "$old_id" == "$id" && "$old_root" != "$root" && "$allow_clone" != "1" ]]; then
        die "같은 프로젝트 ID가 다른 경로에 등록되어 있습니다. 복제본이라면 --clone을 붙여 다시 실행하세요: $old_root"
      fi
    done < "$PROJECT_MAP"
  fi
  tmp="$(mktemp "$PROJECT_STATE_DIR/.paths.XXXXXX")"
  if [[ -f "$PROJECT_MAP" ]]; then awk -F '\t' -v wanted="$root" '$1 != wanted { print }' "$PROJECT_MAP" > "$tmp"; fi
  printf '%s\t%s\t%s\t%s\n' "$root" "$id" "$rel" "$(printf '%s' "$name" | tr '\t\r\n' '   ')" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$PROJECT_MAP"
}

render_project_template() {
  local source="$1" target="$2" project_id="$3" now_id="$4" created="$5" name="$6" index_id="${7:-}" index_title="${8:-}"
  local line yaml_name
  yaml_name="$(yaml_escape "$name")"
  : > "$target"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//@@PROJECT_ID@@/$project_id}"
    line="${line//@@NOW_ID@@/$now_id}"
    line="${line//@@CREATED_AT@@/$created}"
    line="${line//@@PROJECT_NAME_YAML@@/$yaml_name}"
    line="${line//@@PROJECT_NAME@@/$name}"
    line="${line//@@INDEX_ID@@/$index_id}"
    line="${line//@@INDEX_TITLE@@/$index_title}"
    printf '%s\n' "$line" >> "$target"
  done < "$source"
}

validate_project_docs() {
  local docs="$1" ids file id link target dir status type immutable expected_seal actual_seal root_project_id document_project_id resolved_target
  [[ -d "$docs" && ! -L "$docs" && -f "$docs/project.md" && -f "$docs/NOW.md" ]] \
    || die "Persona 프로젝트 문서 구조가 없거나 손상되었습니다: $docs"
  root_project_id="$(frontmatter_value "$docs/project.md" id 2>/dev/null || true)"
  validate_project_id "$root_project_id"
  ids="$(mktemp "${TMPDIR:-/tmp}/persona-doc-ids.XXXXXX")"
  while IFS= read -r file; do
    [[ ! -L "$file" ]] || { rm -f "$ids"; die "프로젝트 문서에 심볼릭 링크를 사용할 수 없습니다: $file"; }
    id="$(frontmatter_value "$file" id 2>/dev/null || true)"
    [[ -n "$id" ]] || { rm -f "$ids"; die "문서 ID가 없습니다: $file"; }
    [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { rm -f "$ids"; die "안전하지 않은 문서 ID입니다: $file"; }
    if [[ "$file" != "$docs/project.md" ]]; then
      document_project_id="$(frontmatter_value "$file" project_id 2>/dev/null || true)"
      [[ "$document_project_id" == "$root_project_id" ]] || { rm -f "$ids"; die "문서의 프로젝트 ID가 정본과 다릅니다: $file"; }
    fi
    printf '%s\t%s\n' "$id" "$file" >> "$ids"
    if contains_secret < "$file"; then rm -f "$ids"; die "프로젝트 문서에 비밀정보로 보이는 내용이 있습니다: $file"; fi
    if contains_local_project_metadata < "$file"; then
      rm -f "$ids"; die "프로젝트 문서에 로컬 경로나 작업 ID로 보이는 내용이 있습니다: $file"
    fi
    case "$file" in
      "$docs"/meetings/*.md)
        type="$(frontmatter_value "$file" type 2>/dev/null || true)"
        status="$(frontmatter_value "$file" status 2>/dev/null || true)"
        immutable="$(frontmatter_value "$file" immutable 2>/dev/null || true)"
        expected_seal="$(frontmatter_value "$file" sealed_sha256 2>/dev/null || true)"
        actual_seal="$(document_seal_hash "$file")"
        [[ "$type" == "meeting" && "$status" == "approved" && "$immutable" == "true" && -n "$expected_seal" && "$expected_seal" == "$actual_seal" ]] \
          || { rm -f "$ids"; die "승인된 회의 기록의 봉인이 없거나 내용이 변경되었습니다: $file"; }
        ;;
    esac
    dir="$(dirname "$file")"
    while IFS= read -r link; do
      link="${link#](}"; link="${link%)}"; target="${link%%#*}"
      [[ -n "$target" ]] || continue
      case "$target" in
        http://*|https://*|mailto:*) continue ;;
        codex:*|/*) rm -f "$ids"; die "프로젝트 문서에는 로컬 앱 링크나 절대 경로를 넣을 수 없습니다: $file -> $target" ;;
      esac
      [[ -e "$dir/$target" ]] || { rm -f "$ids"; die "깨진 상대 링크입니다: $file -> $target"; }
      [[ ! -L "$dir/$target" ]] || { rm -f "$ids"; die "심볼릭 링크 대상은 Persona 문서에서 참조할 수 없습니다: $file -> $target"; }
      resolved_target="$(cd "$(dirname "$dir/$target")" && pwd -P)/$(basename "$target")"
      path_is_within "$resolved_target" "$(cd "$docs" && pwd -P)" \
        || { rm -f "$ids"; die "Persona 문서 폴더 밖으로 나가는 상대 링크입니다: $file -> $target"; }
    done < <(grep -Eo '\]\([^)]*\)' "$file" 2>/dev/null || true)
  done < <(find "$docs" -type f -name '*.md' -print | sort)
  if [[ -n "$(cut -f1 "$ids" | sort | uniq -d)" ]]; then
    rm -f "$ids"; die "프로젝트 문서 ID가 중복됩니다."
  fi
  rm -f "$ids"
  status="$(frontmatter_value "$docs/project.md" status 2>/dev/null || true)"
  [[ "$status" == "active" || "$status" == "archived" ]] || die "project.md 상태가 올바르지 않습니다."
}

write_generated_index() {
  local target="$1" title="$2" project_id="$3" docs="$4" category="$5" created original_created id tmp listing file rel heading status
  created="$(timestamp)"
  original_created="$(frontmatter_value "$target" created_at 2>/dev/null || printf '%s' "$created")"
  id="$(frontmatter_value "$target" id 2>/dev/null || printf 'index-%s' "$(new_uuid)")"
  tmp="$(mktemp "$(dirname "$target")/.index.XXXXXX")"
  listing="$(mktemp "$(dirname "$target")/.index-list.XXXXXX")"
  if [[ "$category" == "archive" ]]; then
    while IFS= read -r file; do
      [[ "$(frontmatter_value "$file" status 2>/dev/null || true)" == "archived" ]] || continue
      rel="${file#"$docs/"}"; heading="$(awk '/^# / {sub(/^# /, ""); print; exit}' "$file")"
      printf -- '- [%s](../%s)\n' "${heading:-${file##*/}}" "$rel" >> "$listing"
    done < <(find "$docs/projects" "$docs/meetings" "$docs/resources" "$docs/decisions" -type f -name '*.md' -print 2>/dev/null | sort)
  elif [[ "$category" == "backlinks" ]]; then
    while IFS= read -r file; do
      rel="${file#"$docs/"}"
      while IFS= read -r status; do
        status="${status#](}"; status="${status%)}"
        case "$status" in http://*|https://*|mailto:*|codex:*|/*|'') continue ;; esac
        printf -- '- `%s` <- [%s](../%s)\n' "$status" "${file##*/}" "$rel" >> "$listing"
      done < <(grep -Eo '\]\([^)]*\)' "$file" 2>/dev/null || true)
    done < <(find "$docs" -type f -name '*.md' ! -path "$docs/indexes/*" -print | sort)
  else
    while IFS= read -r file; do
      rel="${file#"$docs/"}"; heading="$(awk '/^# / {sub(/^# /, ""); print; exit}' "$file")"; status="$(frontmatter_value "$file" status 2>/dev/null || printf unknown)"
      printf -- '- [%s](../%s) - `%s`\n' "${heading:-${file##*/}}" "$rel" "$status" >> "$listing"
    done < <(find "$docs/$category" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | sort)
  fi
  {
    printf '%s\n' '---'
    printf 'id: "%s"\n' "$id"
    printf 'schema_version: "2"\n'
    printf 'type: "generated-index"\nstatus: "active"\n'
    printf 'created_at: "%s"\nupdated_at: "%s"\n' "$original_created" "$created"
    printf 'project_id: "%s"\nvisibility: "public-safe"\ngenerated: true\n' "$project_id"
    printf '%s\n\n' '---'
    printf '# %s\n\n<!-- PERSONA-GENERATED:START -->\n' "$title"
    if [[ -s "$listing" ]]; then cat "$listing"; else printf '아직 기록이 없습니다.\n'; fi
    printf '%s\n' '<!-- PERSONA-GENERATED:END -->'
  } > "$tmp"
  rm -f "$listing"
  chmod 644 "$tmp"
  mv "$tmp" "$target"
}

generate_project_indexes() {
  local docs="$1" project_id="$2"
  mkdir -p "$docs/indexes"
  write_generated_index "$docs/indexes/projects.md" "작업 주기" "$project_id" "$docs" projects
  write_generated_index "$docs/indexes/meetings.md" "회의" "$project_id" "$docs" meetings
  write_generated_index "$docs/indexes/resources.md" "리소스" "$project_id" "$docs" resources
  write_generated_index "$docs/indexes/decisions.md" "결정" "$project_id" "$docs" decisions
  write_generated_index "$docs/indexes/archive.md" "Archive" "$project_id" "$docs" archive
  write_generated_index "$docs/indexes/backlinks.md" "역링크" "$project_id" "$docs" backlinks
}

command_project_init() {
  local docs_rel="docs/persona" name="" allow_clone=0 root target stage repo project_id now_id created
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --docs) [[ $# -ge 2 ]] || die "--docs 값이 필요합니다."; docs_rel="$2"; shift 2 ;;
      --name) [[ $# -ge 2 ]] || die "--name 값이 필요합니다."; name="$2"; shift 2 ;;
      --clone) allow_clone=1; shift ;;
      *) die "사용법: persona project init [--docs <relative-path>] [--name <name>] [--clone]" ;;
    esac
  done
  validate_docs_relative_path "$docs_rel"
  root="$(project_root)"; target="$root/$docs_rel"; name="${name:-$(basename "$root")}"; name="$(printf '%s' "$name" | tr '\t\r\n' '   ')"
  [[ -n "$name" ]] || die "프로젝트 이름은 비워둘 수 없습니다."
  [[ "$name" != *'@@'* ]] || die "프로젝트 이름에는 템플릿 표시인 @@를 사용할 수 없습니다."
  [[ "$root" != *$'\t'* && "$name" != *$'\t'* ]] || die "프로젝트 경로나 이름에 탭을 사용할 수 없습니다."
  if [[ -e "$target" ]]; then
    [[ -d "$target" && ! -L "$target" && -f "$target/project.md" ]] || die "선택한 문서 경로에 Persona가 관리하지 않는 자료가 있습니다: $target"
    project_id="$(frontmatter_value "$target/project.md" id 2>/dev/null || true)"
    [[ -n "$project_id" ]] || die "기존 project.md에 프로젝트 ID가 없습니다."
    validate_project_docs "$target"
    register_project "$root" "$project_id" "$docs_rel" "$name" "$allow_clone"
    info "기존 Persona 프로젝트 문서를 연결했습니다: $project_id"
    return 0
  fi
  repo="$(resolve_repo_root)"; project_id="project-$(new_uuid)"; now_id="now-$(new_uuid)"; created="$(timestamp)"
  stage="$(mktemp -d "$root/.persona-docs-init.XXXXXX")"
  mkdir -p "$stage/projects" "$stage/meetings" "$stage/resources" "$stage/decisions" "$stage/indexes"
  render_project_template "$repo/templates/project-docs/project.md.in" "$stage/project.md" "$project_id" "$now_id" "$created" "$name"
  render_project_template "$repo/templates/project-docs/NOW.md.in" "$stage/NOW.md" "$project_id" "$now_id" "$created" "$name"
  generate_project_indexes "$stage" "$project_id"
  validate_project_docs "$stage"
  mkdir -p "$(dirname "$target")"
  mv "$stage" "$target"
  register_project "$root" "$project_id" "$docs_rel" "$name" "$allow_clone"
  info "Persona 프로젝트 문서를 만들었습니다: $target"
  info "project id: $project_id"
}

command_project() {
  local action="${1:-}" line root id rel name docs
  case "$action" in
    init) command_project_init "$@" ;;
    status)
      [[ $# -eq 1 ]] || die "사용법: persona project status"
      line="$(current_project_docs 2>/dev/null || true)"; [[ -n "$line" ]] || die "현재 프로젝트에 Persona 문서가 없습니다."
      IFS=$'\t' read -r root id rel name <<< "$line"
      printf 'project: %s\nname: %s\nroot: %s\ndocs: %s/%s\n' "$id" "$name" "$root" "$root" "$rel"
      ;;
    validate)
      [[ $# -eq 1 ]] || die "사용법: persona project validate"
      line="$(current_project_docs 2>/dev/null || true)"; [[ -n "$line" ]] || die "현재 프로젝트에 Persona 문서가 없습니다."
      IFS=$'\t' read -r root id rel name <<< "$line"; validate_project_docs "$root/$rel"; info "프로젝트 문서 검증을 통과했습니다."
      ;;
    index)
      [[ $# -eq 2 && "$2" == "--approved" ]] || die "사용법: persona project index --approved"
      line="$(current_project_docs 2>/dev/null || true)"; [[ -n "$line" ]] || die "현재 프로젝트에 Persona 문서가 없습니다."
      IFS=$'\t' read -r root id rel name <<< "$line"; docs="$root/$rel"; validate_project_docs "$docs"; generate_project_indexes "$docs" "$id"; validate_project_docs "$docs"; info "프로젝트 색인을 갱신했습니다."
      ;;
    use) die "persona project use는 v2에서 제거되었습니다. persona project init --name <name>을 사용하세요." ;;
    *) die "사용법: persona project init|status|validate|index" ;;
  esac
}

memory_is_retracted() { [[ -f "$RETRACTION_DIR/$1.md" ]]; }
memory_summary() { frontmatter_value "$1" summary 2>/dev/null || true; }
memory_id() { basename "$1" .md; }

collect_memory_files() {
  local persona="$1" dir
  for dir in "$SHARED_MEMORY_DIR" "$CAPSULE_DIR" "$JOURNAL_DIR/$persona"; do
    [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -type f -name '*.md' -print
  done
}

rebuild_private_indexes() {
  local persona file id relative summary unsorted tmp
  mkdir -p "$PRIVATE_INDEX_DIR"
  for persona in loop soul core; do
    unsorted="$(mktemp "$PRIVATE_INDEX_DIR/.${persona}-index-unsorted.XXXXXX")"
    tmp="$(mktemp "$PRIVATE_INDEX_DIR/.${persona}-index.XXXXXX")"
    while IFS= read -r file; do
      [[ -f "$file" && ! -L "$file" ]] || continue
      id="$(memory_id "$file")"; memory_is_retracted "$id" && continue
      relative="${file#"$PRIVATE_DIR/"}"; summary="$(memory_summary "$file" | tr '\t\r\n' '   ')"
      printf '%s\t%s\t%s\n' "$id" "$relative" "${summary:-로컬 기억}" >> "$unsorted"
    done < <(collect_memory_files "$persona")
    LC_ALL=C sort "$unsorted" > "$tmp"
    rm -f "$unsorted"; chmod 600 "$tmp"; mv "$tmp" "$PRIVATE_INDEX_DIR/$persona.tsv"
  done
}

command_context() {
  local persona="${1:-}" repo index file id relative summary line root project_id rel name count=0 recent
  [[ $# -eq 1 ]] || die "사용법: persona context loop|soul|core"
  validate_persona "$persona"; repo="$(resolve_repo_root)"
  printf '# Persona canonical context\n\n'; cat "$repo/canon/team.md"; printf '\n'; cat "$repo/canon/$persona.md"
  if [[ -f "$PRIVATE_DIR/shared/profile.md" && ! -L "$PRIVATE_DIR/shared/profile.md" ]]; then printf '\n'; cat "$PRIVATE_DIR/shared/profile.md"; fi
  index="$PRIVATE_INDEX_DIR/$persona.tsv"; [[ -f "$index" && ! -L "$index" ]] || rebuild_private_indexes
  if [[ -s "$index" ]]; then
    printf '\n## Active local persona memory\n\n'
    while IFS=$'\t' read -r id relative summary; do printf -- '- `%s`: %s\n' "$id" "$summary"; count=$((count+1)); done < "$index"
    printf '\n## Relevant recent details\n'
    recent="$(mktemp "${TMPDIR:-/tmp}/persona-memory-recent.XXXXXX")"; tail -n 8 "$index" > "$recent"
    while IFS=$'\t' read -r id relative summary; do file="$PRIVATE_DIR/$relative"; [[ -f "$file" && ! -L "$file" ]] || continue; printf '\n'; cat "$file"; done < "$recent"
    rm -f "$recent"
  fi
  line="$(current_project_docs 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r root project_id rel name <<< "$line"
    printf '\n## Current project\n\n- id: `%s`\n- docs: `%s`\n' "$project_id" "$rel"
    if [[ -f "$root/$rel/NOW.md" ]]; then printf '\n'; cat "$root/$rel/NOW.md"; fi
  fi
}

command_memory_add() {
  local scope="" audience="" summary="" body="" kind="note" approval="" base id created file tmp safe_summary count
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope) [[ $# -ge 2 ]] || die "--scope 값이 필요합니다."; scope="$2"; shift 2 ;;
      --audience) [[ $# -ge 2 ]] || die "--audience 값이 필요합니다."; audience="$2"; shift 2 ;;
      --summary) [[ $# -ge 2 ]] || die "--summary 값이 필요합니다."; summary="$2"; shift 2 ;;
      --text) [[ $# -ge 2 ]] || die "--text 값이 필요합니다."; body="$2"; shift 2 ;;
      --kind) [[ $# -ge 2 ]] || die "--kind 값이 필요합니다."; kind="$2"; shift 2 ;;
      --approved) approval="creator"; shift ;;
      --standing-consent) approval="standing-consent"; shift ;;
      *) die "알 수 없는 memory add 옵션입니다: $1" ;;
    esac
  done
  [[ "$scope" != "project" ]] || die "프로젝트 기억은 v2에서 docs/persona/에 기록합니다. persona project init을 사용하세요."
  [[ "$scope" == "global" ]] || die "--scope는 global만 지원합니다."
  case "$audience" in shared|loop|soul|core) ;; *) die "--audience는 shared, loop, soul, core 중 하나여야 합니다." ;; esac
  case "$kind" in note|fact|decision|preference|journal|reflection|capsule) ;; *) die "지원하지 않는 기억 종류입니다." ;; esac
  [[ -n "$summary" && -n "$body" ]] || die "--summary와 --text는 비워둘 수 없습니다."
  if [[ "$approval" == "standing-consent" ]]; then
    [[ "$audience" != "shared" && ( "$kind" == "journal" || "$kind" == "reflection" ) ]] \
      || die "상시 동의는 페르소나별 journal 또는 reflection에만 사용할 수 있습니다."
  elif [[ "$approval" != "creator" ]]; then
    die "창작자님의 명시적 승인 뒤 --approved를 지정해야 합니다."
  fi
  if printf '%s\n%s\n' "$summary" "$body" | contains_secret; then die "비밀정보로 보이는 내용은 로컬 기억에도 저장할 수 없습니다."; fi
  if printf '%s\n%s\n' "$summary" "$body" | contains_sensitive_inference; then die "민감한 성향이나 상태에 대한 추론은 Persona 기억에 저장할 수 없습니다."; fi
  case "$kind:$audience" in capsule:shared) base="$CAPSULE_DIR" ;; *:shared) base="$SHARED_MEMORY_DIR" ;; *) base="$JOURNAL_DIR/$audience" ;; esac
  mkdir -p "$base"; created="$(timestamp)"; id="${created}-$(new_uuid)"; file="$base/$id.md"; tmp="$(mktemp "$base/.memory.XXXXXX")"; safe_summary="$(yaml_escape "$summary")"
  {
    printf '%s\n' '---'; printf 'id: "%s"\ncreated_at: "%s"\nscope: "global-local"\naudience: "%s"\nkind: "%s"\nsummary: "%s"\napproved_by: "%s"\nevidence: "%s"\nstatus: "active"\n' "$id" "$created" "$audience" "$kind" "$safe_summary" "$approval" "$approval"; printf '%s\n\n' '---'; printf '%s\n' "$body"
  } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$file"
  if [[ "$audience" != "shared" ]]; then
    count="$(find "$JOURNAL_DIR/$audience" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
    if (( count > 30 )); then warn "$audience 활성 관계 일지가 30개를 넘었습니다. 다음 자연스러운 확인 지점에 통합이 필요합니다."; fi
  fi
  rebuild_private_indexes
  info "이 Mac의 로컬 기억에 기록했습니다: $id"
}

find_memory_file() {
  local id="$1" dir file
  for dir in "$SHARED_MEMORY_DIR" "$CAPSULE_DIR" "$JOURNAL_DIR/loop" "$JOURNAL_DIR/soul" "$JOURNAL_DIR/core"; do
    file="$dir/$id.md"; if [[ -f "$file" && ! -L "$file" ]]; then printf '%s\n' "$file"; return 0; fi
  done
  return 1
}

command_memory_retract() {
  local id="${1:-}" approved="${2:-}" original tombstone tmp
  [[ $# -eq 2 && "$approved" == "--approved" ]] || die "사용법: persona memory retract <id> --approved"
  [[ "$id" =~ ^[A-Za-z0-9._:-]+$ ]] || die "잘못된 기억 ID입니다."
  original="$(find_memory_file "$id" 2>/dev/null || true)"; [[ -n "$original" ]] || die "로컬 기억 ID를 찾을 수 없습니다: $id"
  tombstone="$RETRACTION_DIR/$id.md"; [[ ! -e "$tombstone" ]] || die "이미 철회된 기억입니다: $id"; tmp="$(mktemp "$RETRACTION_DIR/.retract.XXXXXX")"
  { printf '%s\n' '---'; printf 'id: "%s"\nretracted_at: "%s"\napproved_by: "creator"\n' "$id" "$(timestamp)"; printf '%s\n\n' '---'; printf 'This local memory is excluded from active persona context.\n'; } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$tombstone"; rebuild_private_indexes; info "로컬 기억을 활성 문맥에서 철회했습니다: $id"
}

command_memory_status() {
  local profile shared journals capsules retracted
  if [[ -f "$PRIVATE_DIR/shared/profile.md" ]]; then profile="present"; else profile="absent"; fi
  shared="$(find "$SHARED_MEMORY_DIR" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  journals="$(find "$JOURNAL_DIR" -type f -name '*.md' | wc -l | tr -d ' ')"
  capsules="$(find "$CAPSULE_DIR" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  retracted="$(find "$RETRACTION_DIR" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  printf 'storage: %s\nprofile: %s\nshared: %s\njournals: %s\ncapsules: %s\nretracted: %s\nsync: disabled (local Mac only)\n' "$PRIVATE_DIR" "$profile" "$shared" "$journals" "$capsules" "$retracted"
}

command_memory() {
  local action="${1:-}"; shift || true
  case "$action" in add) command_memory_add "$@" ;; retract) command_memory_retract "$@" ;; status) [[ $# -eq 0 ]] || die "사용법: persona memory status"; command_memory_status ;; *) die "사용법: persona memory add|retract|status" ;; esac
}

current_project_fields() {
  local line
  line="$(current_project_docs 2>/dev/null || true)"
  [[ -n "$line" ]] || die "현재 프로젝트에 Persona 문서가 없습니다. 먼저 persona project init을 실행하세요."
  printf '%s\n' "$line"
}

team_binding_file() {
  local project_id="$1"
  printf '%s/%s.tsv\n' "$TASK_BINDING_DIR" "$project_id"
}

team_cursor_file() {
  local project_id="$1" persona="$2"
  printf '%s/%s/%s.cursor\n' "$CURSOR_DIR" "$project_id" "$persona"
}

command_team() {
  local action="${1:-}" line root project_id rel name persona thread_id host_id file tmp cursor_file value
  case "$action" in
    bind)
      [[ $# -ge 3 && $# -le 4 ]] || die "사용법: persona team bind loop|soul|core <thread-id> [host-id]"
      persona="$2"; thread_id="$3"; host_id="${4:--}"; validate_persona "$persona"
      [[ "$thread_id" =~ ^[A-Za-z0-9._:-]+$ && "$host_id" =~ ^[A-Za-z0-9._:-]+$ ]] || die "작업 또는 호스트 ID 형식이 안전하지 않습니다."
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; file="$(team_binding_file "$project_id")"; mkdir -p "$TASK_BINDING_DIR"; tmp="$(mktemp "$TASK_BINDING_DIR/.binding.XXXXXX")"
      if [[ -f "$file" ]]; then awk -F '\t' -v wanted="$persona" '$1 != wanted { print }' "$file" > "$tmp"; fi
      printf '%s\t%s\t%s\n' "$persona" "$thread_id" "$host_id" >> "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$file"; info "$name 프로젝트의 $persona 작업을 정확한 ID로 연결했습니다."
      ;;
    status)
      [[ $# -eq 1 ]] || die "사용법: persona team status"
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; file="$(team_binding_file "$project_id")"
      printf 'project: %s\nname: %s\n' "$project_id" "$name"
      for persona in loop soul core; do
        if [[ -f "$file" ]] && value="$(awk -F '\t' -v wanted="$persona" '$1==wanted {print $2 " / " $3; found=1; exit} END{if(!found) exit 1}' "$file" 2>/dev/null)"; then
          printf '%s: %s\n' "$persona" "$value"
        else printf '%s: <unbound>\n' "$persona"; fi
        cursor_file="$(team_cursor_file "$project_id" "$persona")"; if [[ -f "$cursor_file" ]]; then printf '%s cursor: %s\n' "$persona" "$(cat "$cursor_file")"; fi
      done
      ;;
    cursor)
      [[ $# -ge 3 ]] || die "사용법: persona team cursor get|set loop|soul|core [cursor]"
      persona="$3"; validate_persona "$persona"; line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; cursor_file="$(team_cursor_file "$project_id" "$persona")"
      case "$2" in
        get) [[ $# -eq 3 ]] || die "사용법: persona team cursor get <persona>"; [[ -f "$cursor_file" ]] && cat "$cursor_file" || printf '<none>\n' ;;
        set) [[ $# -eq 4 ]] || die "사용법: persona team cursor set <persona> <cursor>"; value="$4"; [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "확인 지점 값이 안전하지 않습니다."; mkdir -p "$(dirname "$cursor_file")"; chmod 700 "$(dirname "$cursor_file")"; tmp="$(mktemp "$(dirname "$cursor_file")/.cursor.XXXXXX")"; printf '%s\n' "$value" > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$cursor_file" ;;
        *) die "사용법: persona team cursor get|set ..." ;;
      esac
      ;;
    clear)
      [[ $# -eq 2 && "$2" == "--approved" ]] || die "사용법: persona team clear --approved"
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; file="$(team_binding_file "$project_id")"
      rm -f -- "$file"; [[ ! -e "$CURSOR_DIR/$project_id" || -L "$CURSOR_DIR/$project_id" ]] || rm -rf -- "$CURSOR_DIR/$project_id"
      info "$name 프로젝트의 로컬 작업 연결과 확인 지점을 제거했습니다. 프로젝트 문서는 보존했습니다."
      ;;
    *) die "사용법: persona team bind|status|cursor|clear" ;;
  esac
}

write_pending_record() {
  local base="$1" prefix="$2" project_id="$3" persona="$4" source_id="$5" summary="$6" body="$7" id created file tmp
  mkdir -p "$base/$project_id"; chmod 700 "$base/$project_id"; created="$(timestamp)"; id="$prefix-$created-$(new_uuid)"; file="$base/$project_id/$id.md"; tmp="$(mktemp "$base/$project_id/.pending.XXXXXX")"
  {
    printf '%s\n' '---'; printf 'id: "%s"\ncreated_at: "%s"\nproject_id: "%s"\npersona: "%s"\nsource_id: "%s"\nsummary: "%s"\nstatus: "pending"\n' "$id" "$created" "$project_id" "$persona" "$(yaml_escape "$source_id")" "$(yaml_escape "$summary")"; printf '%s\n\n' '---'; printf '%s\n' "$body"
  } > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$file"; printf '%s\n' "$id"
}

write_approved_meeting() {
  local target="$1" meeting_id="$2" project_id="$3" title="$4" body="$5" approved_at="$6" decision_id="$7"
  local tmp sealed seal
  tmp="$(mktemp "$(dirname "$target")/.meeting.XXXXXX")"
  {
    printf '%s\n' '---'
    printf 'id: "%s"\nschema_version: "2"\ntype: "meeting"\nstatus: "approved"\n' "$meeting_id"
    printf 'created_at: "%s"\napproved_at: "%s"\nproject_id: "%s"\n' "$approved_at" "$approved_at" "$project_id"
    printf 'visibility: "public-safe"\nimmutable: true\nsealed_sha256: ""\n'
    printf '%s\n\n' '---'
    printf '# %s\n\n%s\n' "$title" "$body"
    if [[ -n "$decision_id" ]]; then
      printf '\n## 관련 결정\n\n- [확정 결정](../decisions/%s.md)\n' "$decision_id"
    fi
  } > "$tmp"
  seal="$(document_seal_hash "$tmp")"
  sealed="$(mktemp "$(dirname "$target")/.meeting-sealed.XXXXXX")"
  awk -v value="$seal" '/^sealed_sha256:[[:space:]]*/ { print "sealed_sha256: \"" value "\""; next } { print }' "$tmp" > "$sealed"
  rm -f "$tmp"; chmod 644 "$sealed"; mv "$sealed" "$target"
}

write_approved_decision() {
  local target="$1" decision_id="$2" project_id="$3" meeting_id="$4" title="$5" body="$6" created="$7" tmp
  tmp="$(mktemp "$(dirname "$target")/.decision.XXXXXX")"
  {
    printf '%s\n' '---'
    printf 'id: "%s"\nschema_version: "2"\ntype: "decision"\nstatus: "active"\n' "$decision_id"
    printf 'created_at: "%s"\nupdated_at: "%s"\nproject_id: "%s"\nvisibility: "public-safe"\n' "$created" "$created" "$project_id"
    printf '%s\n\n' '---'
    printf '# %s\n\n%s\n\n## 근거 회의\n\n- [승인된 회의](../meetings/%s.md)\n' "$title" "$body" "$meeting_id"
  } > "$tmp"
  chmod 644 "$tmp"; mv "$tmp" "$target"
}

command_handoff() {
  local action="${1:-}" persona="" source_id="" summary="" body="" cursor="" line root project_id rel name id file count
  case "$action" in
    add)
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --persona) persona="$2"; shift 2 ;; --source) source_id="$2"; shift 2 ;; --summary) summary="$2"; shift 2 ;; --text) body="$2"; shift 2 ;; --cursor) cursor="$2"; shift 2 ;; *) die "알 수 없는 handoff add 옵션입니다: $1" ;;
        esac
      done
      validate_persona "$persona"; [[ "$persona" != "loop" ]] || die "인계 후보의 출처는 soul 또는 core여야 합니다."; [[ -n "$source_id" && -n "$summary" && -n "$body" ]] || die "handoff add에는 persona, source, summary, text가 필요합니다."
      if printf '%s\n%s\n' "$summary" "$body" | contains_secret; then die "인계 후보에 비밀정보를 저장할 수 없습니다."; fi
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; id="$(write_pending_record "$HANDOFF_DIR" handoff "$project_id" "$persona" "$source_id" "$summary" "$body")"
      if [[ -n "$cursor" ]]; then command_team cursor set "$persona" "$cursor"; fi
      info "로컬 인계 후보를 보관했습니다: $id"
      ;;
    list)
      [[ $# -eq 1 ]] || die "사용법: persona handoff list"
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; count=0
      while IFS= read -r file; do printf -- '- `%s`: %s (%s)\n' "$(basename "$file" .md)" "$(frontmatter_value "$file" summary 2>/dev/null || printf 후보)" "$(frontmatter_value "$file" persona 2>/dev/null || printf unknown)"; count=$((count+1)); done < <(find "$HANDOFF_DIR/$project_id" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | sort)
      printf 'count: %s\n' "$count"
      ;;
    clear)
      [[ $# -eq 3 && "$3" == "--approved" ]] || die "사용법: persona handoff clear <id> --approved"; id="$2"; [[ "$id" =~ ^handoff-[A-Za-z0-9._:-]+$ ]] || die "안전하지 않은 인계 후보 ID입니다."
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; file="$HANDOFF_DIR/$project_id/$id.md"; [[ -f "$file" && ! -L "$file" ]] || die "인계 후보를 찾을 수 없습니다: $id"; rm -f -- "$file"; info "인계 후보를 처리 완료로 제거했습니다: $id"
      ;;
    *) die "사용법: persona handoff add|list|clear" ;;
  esac
}

command_meeting() {
  local action="${1:-}" summary="" body="" title="" decision_title="" decision_body="" approved=0
  local line root project_id rel name id file count docs draft stage backup lock tree_before tree_after created decision_id=""
  case "$action" in
    draft)
      shift
      while [[ $# -gt 0 ]]; do case "$1" in --summary) summary="$2"; shift 2 ;; --text) body="$2"; shift 2 ;; *) die "알 수 없는 meeting draft 옵션입니다: $1" ;; esac; done
      [[ -n "$summary" && -n "$body" ]] || die "meeting draft에는 summary와 text가 필요합니다."; if printf '%s\n%s\n' "$summary" "$body" | contains_secret; then die "회의 초안에 비밀정보를 저장할 수 없습니다."; fi
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; id="$(write_pending_record "$MEETING_DRAFT_DIR" meeting "$project_id" loop conversation "$summary" "$body")"; info "로컬 회의 패킷을 만들었습니다: $id"
      ;;
    list)
      [[ $# -eq 1 ]] || die "사용법: persona meeting list"; line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; count=0
      while IFS= read -r file; do printf -- '- `%s`: %s\n' "$(basename "$file" .md)" "$(frontmatter_value "$file" summary 2>/dev/null || printf 초안)"; count=$((count+1)); done < <(find "$MEETING_DRAFT_DIR/$project_id" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | sort); printf 'count: %s\n' "$count"
      ;;
    publish)
      [[ $# -ge 2 ]] || die "사용법: persona meeting publish <id> --title <title> --text <text> [--decision-title <title> --decision-text <text>] --approved"
      id="$2"; shift 2
      [[ "$id" =~ ^meeting-[A-Za-z0-9._:-]+$ ]] || die "안전하지 않은 회의 초안 ID입니다."
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --title) [[ $# -ge 2 ]] || die "--title 값이 필요합니다."; title="$2"; shift 2 ;;
          --text) [[ $# -ge 2 ]] || die "--text 값이 필요합니다."; body="$2"; shift 2 ;;
          --decision-title) [[ $# -ge 2 ]] || die "--decision-title 값이 필요합니다."; decision_title="$2"; shift 2 ;;
          --decision-text) [[ $# -ge 2 ]] || die "--decision-text 값이 필요합니다."; decision_body="$2"; shift 2 ;;
          --approved) approved=1; shift ;;
          *) die "알 수 없는 meeting publish 옵션입니다: $1" ;;
        esac
      done
      title="$(printf '%s' "$title" | tr '\t\r\n' '   ')"; decision_title="$(printf '%s' "$decision_title" | tr '\t\r\n' '   ')"
      [[ "$approved" == "1" && -n "$title" && -n "$body" ]] || die "창작자님 승인과 title, text가 모두 필요합니다."
      if [[ -n "$decision_title" || -n "$decision_body" ]]; then [[ -n "$decision_title" && -n "$decision_body" ]] || die "결정 제목과 내용은 함께 지정해야 합니다."; fi
      if printf '%s\n%s\n%s\n%s\n' "$title" "$body" "$decision_title" "$decision_body" | contains_secret; then die "승인 묶음에 비밀정보를 저장할 수 없습니다."; fi
      if printf '%s\n%s\n%s\n%s\n' "$title" "$body" "$decision_title" "$decision_body" | contains_local_project_metadata; then die "승인 묶음에 로컬 경로나 Codex 작업 ID를 저장할 수 없습니다."; fi
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; docs="$root/$rel"; draft="$MEETING_DRAFT_DIR/$project_id/$id.md"
      [[ -f "$draft" && ! -L "$draft" ]] || die "로컬 회의 초안을 찾을 수 없습니다: $id"
      [[ ! -e "$docs/meetings/$id.md" ]] || die "같은 회의가 이미 프로젝트 문서에 있습니다: $id"
      validate_project_docs "$docs"; tree_before="$(directory_tree_hash "$docs")"; created="$(timestamp)"
      if [[ -n "$decision_title" ]]; then decision_id="decision-$created-$(new_uuid)"; fi
      stage="$(mktemp -d "$root/.persona-meeting-apply.XXXXXX")"; backup="$root/.persona-meeting-backup.$(new_uuid)"
      cp -Rp "$docs/." "$stage/"
      write_approved_meeting "$stage/meetings/$id.md" "$id" "$project_id" "$title" "$body" "$created" "$decision_id"
      if [[ -n "$decision_id" ]]; then write_approved_decision "$stage/decisions/$decision_id.md" "$decision_id" "$project_id" "$id" "$decision_title" "$decision_body" "$created"; fi
      generate_project_indexes "$stage" "$project_id"; validate_project_docs "$stage"
      tree_after="$(directory_tree_hash "$docs")"; [[ "$tree_before" == "$tree_after" ]] || { rm -rf -- "$stage"; die "준비 중 프로젝트 문서가 바뀌어 승인 묶음을 적용하지 않았습니다."; }
      lock="$WRITER_LOCK_DIR/$project_id.lock"; if ! mkdir "$lock" 2>/dev/null; then rm -rf -- "$stage"; die "다른 쓰기 작업이 진행 중이라 회의 묶음을 적용하지 않았습니다."; fi; chmod 700 "$lock"
      { printf 'owner=loop\nscope=approved-meeting\ntask_id=persona-cli\ncreated_at=%s\n' "$created"; } > "$lock/info"; chmod 600 "$lock/info"
      if ! mv "$docs" "$backup"; then rm -f "$lock/info"; rmdir "$lock"; rm -rf -- "$stage"; die "기존 프로젝트 문서를 안전하게 보관하지 못했습니다."; fi
      if ! mv "$stage" "$docs"; then mv "$backup" "$docs" 2>/dev/null || true; rm -f "$lock/info"; rmdir "$lock" 2>/dev/null || true; die "승인 묶음 적용에 실패해 기존 프로젝트 문서를 복구했습니다."; fi
      rm -rf -- "$backup"; rm -f "$lock/info"; rmdir "$lock"; rm -f -- "$draft"
      info "승인된 회의를 프로젝트 문서에 원자적으로 반영했습니다: $rel/meetings/$id.md"
      if [[ -n "$decision_id" ]]; then info "장기 결정을 함께 기록했습니다: $rel/decisions/$decision_id.md"; fi
      ;;
    clear)
      [[ $# -eq 3 && "$3" == "--approved" ]] || die "사용법: persona meeting clear <id> --approved"; id="$2"; [[ "$id" =~ ^meeting-[A-Za-z0-9._:-]+$ ]] || die "안전하지 않은 회의 초안 ID입니다."; line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; file="$MEETING_DRAFT_DIR/$project_id/$id.md"; [[ -f "$file" && ! -L "$file" ]] || die "회의 초안을 찾을 수 없습니다: $id"; rm -f -- "$file"; info "회의 초안을 제거했습니다: $id"
      ;;
    *) die "사용법: persona meeting draft|list|publish|clear" ;;
  esac
}

writer_lock_is_stale() {
  local lock="$1" minutes="${PERSONA_LOCK_STALE_MINUTES:-720}"
  [[ "$minutes" =~ ^[0-9]+$ ]] || die "잠금 만료 시간은 분 단위 숫자여야 합니다."
  [[ -d "$lock" && ! -L "$lock" ]] || return 1
  [[ -n "$(find "$lock" -prune -mmin "+$minutes" -print 2>/dev/null)" ]]
}

command_writer() {
  local action="${1:-}" persona scope="" task_id="-" force=0 approved=0 line root project_id rel name lock tmp owner
  case "$action" in
    acquire)
      [[ $# -ge 3 && $# -le 4 ]] || die "사용법: persona writer acquire <persona> <scope> [task-id]"; persona="$2"; scope="$3"; task_id="${4:--}"; validate_persona "$persona"; [[ -n "$scope" && "$scope" != *$'\n'* && "$scope" != *$'\t'* ]] || die "쓰기 범위가 안전하지 않습니다."; [[ "$task_id" =~ ^[A-Za-z0-9._:-]+$ ]] || die "작업 ID 형식이 안전하지 않습니다."
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; lock="$WRITER_LOCK_DIR/$project_id.lock"; mkdir -p "$WRITER_LOCK_DIR"
      if ! mkdir "$lock" 2>/dev/null; then owner="$(awk -F= '$1=="owner" {print $2}' "$lock/info" 2>/dev/null || printf unknown)"; if writer_lock_is_stale "$lock"; then die "오래된 $owner 쓰기 잠금이 있습니다. 상태를 확인한 뒤 persona writer recover --approved를 사용하세요."; fi; die "이미 $owner 페르소나가 이 프로젝트의 쓰기를 맡고 있습니다."; fi; chmod 700 "$lock"
      tmp="$lock/.info.temporary"; { printf 'owner=%s\nscope=%s\ntask_id=%s\ncreated_at=%s\n' "$persona" "$scope" "$task_id" "$(timestamp)"; } > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$lock/info"; info "$persona 쓰기 잠금을 획득했습니다: $scope"
      ;;
    status)
      [[ $# -eq 1 ]] || die "사용법: persona writer status"; line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; lock="$WRITER_LOCK_DIR/$project_id.lock"; if [[ -f "$lock/info" ]]; then cat "$lock/info"; else printf 'writer: <none>\n'; fi
      ;;
    release)
      [[ $# -ge 2 ]] || die "사용법: persona writer release <persona> [--force --approved]"; persona="$2"; validate_persona "$persona"; shift 2; while [[ $# -gt 0 ]]; do case "$1" in --force) force=1 ;; --approved) approved=1 ;; *) die "알 수 없는 writer release 옵션입니다: $1" ;; esac; shift; done
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; lock="$WRITER_LOCK_DIR/$project_id.lock"; [[ -d "$lock" && ! -L "$lock" && -f "$lock/info" ]] || die "활성 쓰기 잠금이 없습니다."; owner="$(awk -F= '$1=="owner" {print $2; exit}' "$lock/info")"
      if [[ "$owner" != "$persona" ]]; then [[ "$force" == "1" && "$approved" == "1" ]] || die "잠금 소유자는 $owner 입니다. 상태 확인과 창작자님 승인 뒤 --force --approved를 사용하세요."; fi
      rm -f -- "$lock/info"; rmdir "$lock"; info "쓰기 잠금을 해제했습니다."
      ;;
    recover)
      [[ $# -eq 2 && "$2" == "--approved" ]] || die "사용법: persona writer recover --approved"
      line="$(current_project_fields)"; IFS=$'\t' read -r root project_id rel name <<< "$line"; lock="$WRITER_LOCK_DIR/$project_id.lock"
      [[ -d "$lock" && ! -L "$lock" && -f "$lock/info" ]] || die "복구할 쓰기 잠금이 없습니다."
      writer_lock_is_stale "$lock" || die "잠금이 아직 만료되지 않았습니다. 소유 페르소나가 직접 release 해야 합니다."
      rm -f -- "$lock/info"; rmdir "$lock"; info "창작자님 승인으로 오래된 쓰기 잠금을 복구했습니다."
      ;;
    *) die "사용법: persona writer acquire|status|release|recover" ;;
  esac
}

command_sync() {
  die "persona sync는 v2에서 폐지되었습니다. 기억은 이 Mac에만 남습니다. 코드 갱신에는 persona update를 사용하세요."
}

directory_tree_hash() {
  local root="$1" listing digest_list file relative result
  [[ -d "$root" ]] || { printf 'absent\n'; return 0; }
  listing="$(mktemp "${TMPDIR:-/tmp}/persona-private-files.XXXXXX")"
  digest_list="$(mktemp "${TMPDIR:-/tmp}/persona-private-digests.XXXXXX")"
  find "$root" -type f -print | LC_ALL=C sort > "$listing"
  while IFS= read -r file; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    relative="${file#"$root/"}"
    printf '%s  %s\n' "$(hash_file "$file")" "$relative" >> "$digest_list"
  done < "$listing"
  result="$(hash_file "$digest_list")"
  rm -f "$listing" "$digest_list"
  printf '%s\n' "$result"
}

protected_local_hash() {
  local digest_list key
  digest_list="$(mktemp "${TMPDIR:-/tmp}/persona-protected-state.XXXXXX")"
  for directory in "$PRIVATE_DIR" "$PENDING_DIR" "$PROJECT_STATE_DIR" "$TASK_BINDING_DIR" "$CURSOR_DIR" "$WRITER_LOCK_DIR" "$MODEL_OVERRIDE_DIR"; do
    printf '%s  %s\n' "$(directory_tree_hash "$directory")" "$directory" >> "$digest_list"
  done
  for key in install_id profile override_loop_model override_loop_effort override_soul_model override_soul_effort override_core_model override_core_effort; do
    printf '%s=%s\n' "$key" "$(state_get "$key" 2>/dev/null || true)" >> "$digest_list"
  done
  hash_file "$digest_list"
  rm -f "$digest_list"
}

command_update() {
  local repo branch before_protected after_protected before_head after_head
  require_macos
  validate_local_layout
  repo="$(resolve_repo_root)"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "Persona 소스가 Git 저장소가 아닙니다: $repo"
  [[ -z "$(git -C "$repo" status --porcelain)" ]] \
    || die "Persona 소스 저장소에 커밋되지 않은 변경이 있어 업데이트를 중단했습니다."
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" \
    || die "브랜치가 아닌 상태에서는 안전하게 업데이트할 수 없습니다."
  before_protected="$(protected_local_hash)"
  before_head="$(git -C "$repo" rev-parse HEAD)"

  if [[ "${PERSONA_UPDATE_SKIP_PULL:-0}" != "1" ]]; then
    git -C "$repo" remote get-url origin >/dev/null 2>&1 \
      || die "origin 원격 저장소가 없어 코드를 받을 수 없습니다."
    git -C "$repo" pull --ff-only origin "$branch" \
      || die "fast-forward 업데이트가 불가능합니다. 저장소 상태를 직접 확인하세요."
  fi

  [[ -z "$(git -C "$repo" status --porcelain)" ]] \
    || die "코드를 받은 뒤 저장소가 깨끗하지 않아 설치 갱신을 중단했습니다."
  if ! PERSONA_SOURCE_ROOT="$repo" PERSONA_SKIP_PENDING_CLEANUP=1 "$repo/scripts/persona.sh" __install; then
    after_protected="$(protected_local_hash)"
    [[ "$before_protected" == "$after_protected" ]] \
      || die "설치 갱신 실패와 함께 보호된 로컬 데이터가 달라졌습니다. 백업을 확인하세요."
    die "새 코드는 받았지만 설치 자료 갱신에 실패했습니다. 보호된 로컬 데이터는 보존했습니다."
  fi
  after_protected="$(protected_local_hash)"
  [[ "$before_protected" == "$after_protected" ]] \
    || die "업데이트가 보호된 로컬 데이터를 변경해 중단했습니다. 백업을 확인하세요."
  after_head="$(git -C "$repo" rev-parse HEAD)"
  info "Persona 코드와 설치 자료를 갱신했습니다: ${before_head:0:12} -> ${after_head:0:12}"
  info "로컬 기억과 프로젝트 문서는 변경하지 않았고, 커밋하거나 push하지 않았습니다."
}

find_project_override() {
  local field="${1:-model}" root current
  current="$(pwd -P)"
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$root" && -f "$root/.codex/config.toml" ]]; then
    toml_root_get "$root/.codex/config.toml" "$field" 2>/dev/null || true
  elif [[ -f "$current/.codex/config.toml" ]]; then
    toml_root_get "$current/.codex/config.toml" "$field" 2>/dev/null || true
  fi
}

command_status() {
  local profile project_override project_effort line root project_id rel name
  profile="$(state_get profile 2>/dev/null || printf '%s' 'not-installed')"
  printf 'Persona Team %s\n' "$PERSONA_VERSION"
  printf 'platform: macOS only\n'
  printf 'profile: %s\n' "$profile"
  if [[ "$profile" != "not-installed" ]]; then
    for persona in loop soul core; do
      if [[ -n "$(state_get "override_${persona}_model" 2>/dev/null || true)" || -n "$(state_get "override_${persona}_effort" 2>/dev/null || true)" ]]; then
        printf '%s: %s / %s (source: local override)\n' "$persona" "$(effective_value "$persona" model)" "$(effective_value "$persona" effort)"
      else
        printf '%s: %s / %s (source: profile %s)\n' "$persona" "$(effective_value "$persona" model)" "$(effective_value "$persona" effort)" "$profile"
      fi
    done
  fi
  printf 'config loop: %s / %s\n' \
    "$(toml_root_get "$CODEX_DIR/config.toml" model 2>/dev/null || printf '%s' '<unset>')" \
    "$(toml_root_get "$CODEX_DIR/config.toml" model_reasoning_effort 2>/dev/null || printf '%s' '<unset>')"
  project_override="$(find_project_override model)"; project_effort="$(find_project_override model_reasoning_effort)"
  if [[ -n "$project_override" || -n "$project_effort" ]]; then
    printf 'project override: %s / %s (전역 Loop 기본값보다 우선)\n' "${project_override:-<model unchanged>}" "${project_effort:-<effort unchanged>}"
  fi
  printf 'active desktop task: 작업별 UI 모델 선택이 위 값보다 우선할 수 있습니다.\n'
  printf 'repository: %s\n' "$(state_get repo_root 2>/dev/null || printf '%s' '<unset>')"
  printf 'local persona data: %s (Git sync: disabled)\n' "$PERSONA_ROOT"
  line="$(current_project_docs 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r root project_id rel name <<< "$line"
    printf 'current project: %s (%s)\nproject docs: %s/%s\n' "$name" "$project_id" "$root" "$rel"
  else
    printf 'current project: <not connected>\n'
  fi
}

command_doctor() {
  local failures=0 marker_count repo line root project_id rel name mode file relative tracked_memory=""
  require_macos
  if ! validate_local_layout; then
    failures=$((failures + 1))
  fi
  if command -v codex >/dev/null 2>&1; then
    info "Codex: $(codex --version 2>/dev/null || printf '%s' '실행 실패')"
    if [[ "${PERSONA_SKIP_CODEX_VALIDATE:-0}" != "1" ]] && ! codex --strict-config --version >/dev/null 2>&1; then
      warn "config.toml 엄격 검증 실패"
      failures=$((failures + 1))
    fi
  else
    warn "codex 명령을 PATH에서 찾지 못했습니다."
    if [[ "${PERSONA_SKIP_CODEX_VALIDATE:-0}" != "1" ]]; then
      failures=$((failures + 1))
    fi
  fi
  marker_count="$(grep -Fc "$AGENTS_START" "$CODEX_DIR/AGENTS.md" 2>/dev/null || true)"
  if [[ "$marker_count" != "1" ]]; then warn "전역 AGENTS 관리 블록 개수가 1이 아닙니다."; failures=$((failures + 1)); fi
  for file in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml" "$CODEX_DIR/skills/persona-council/SKILL.md"; do
    if [[ ! -f "$file" ]]; then warn "설치 파일 누락: $file"; failures=$((failures + 1)); fi
  done
  repo="$(state_get repo_root 2>/dev/null || true)"
  if [[ -z "$repo" || ! -d "$repo/.git" ]]; then warn "Git 저장소 상태를 확인하세요: ${repo:-<unset>}"; failures=$((failures + 1)); fi
  if [[ -n "$repo" && -d "$repo/.git" ]]; then
    while IFS= read -r relative; do
      if [[ -e "$repo/$relative" || -L "$repo/$relative" ]]; then tracked_memory="$relative"; break; fi
    done < <(git -C "$repo" ls-files 'memory/**' 2>/dev/null || true)
    if [[ -n "$tracked_memory" ]]; then
      warn "v2 소스 저장소가 전역 기억 파일을 추적하고 있습니다."
      failures=$((failures + 1))
    fi
    if find "$repo" -type f \( -name '*.ps1' -o -name '*PowerShell*' \) -print -quit 2>/dev/null | grep -q .; then
      warn "macOS 전용 v2 저장소에 Windows/PowerShell 구현 파일이 남아 있습니다."
      failures=$((failures + 1))
    fi
  fi
  line="$(current_project_docs 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r root project_id rel name <<< "$line"
    if ! validate_project_docs "$root/$rel"; then failures=$((failures + 1)); fi
  fi
  while IFS= read -r file; do
    mode="$(stat -f '%Lp' "$file" 2>/dev/null || printf unknown)"
    if [[ "$mode" != "700" ]]; then warn "로컬 전용 디렉터리 권한이 0700이 아닙니다: $file ($mode)"; failures=$((failures + 1)); fi
  done < <(find "$PERSONA_ROOT" -type d -print 2>/dev/null)
  while IFS= read -r file; do
    mode="$(stat -f '%Lp' "$file" 2>/dev/null || printf unknown)"
    if [[ "$mode" != "600" ]]; then warn "로컬 전용 파일 권한이 0600이 아닙니다: $file ($mode)"; failures=$((failures + 1)); fi
  done < <(find "$PERSONA_ROOT" -type f -print 2>/dev/null)
  if (( failures > 0 )); then
    die "진단에서 ${failures}개 문제를 찾았습니다."
  fi
  info "진단을 통과했습니다."
}

remove_block_from_file() {
  local file="$1" start="$2" end="$3" tmp
  [[ -f "$file" ]] || return 0
  [[ ! -L "$file" ]] || die "심볼릭 링크 파일은 제거 과정에서 변경하지 않습니다: $file"
  tmp="$(mktemp "$(dirname "$file")/.persona-remove.XXXXXX")"
  if ! strip_managed_block "$file" "$start" "$end" > "$tmp"; then
    rm -f "$tmp"
    die "관리 마커가 손상되어 제거를 중단했습니다: $file"
  fi
  mv "$tmp" "$file"
}

command_uninstall() {
  local current_model current_effort last_model last_effort original_model original_effort restore_model restore_effort
  local shell_rc bin file confirmation="" count size transaction uninstall_status
  require_macos
  validate_local_layout
  if [[ $# -eq 2 && "$1" == "--confirm" ]]; then
    confirmation="$2"
  elif [[ $# -ne 0 ]]; then
    die "사용법: persona uninstall [--confirm DELETE-PERSONA-DATA]"
  fi

  if find "$PERSONA_ROOT" -type l -print -quit 2>/dev/null | grep -q .; then
    die "Persona 전용 로컬 데이터 안에 심볼릭 링크가 있어 아무것도 삭제하지 않았습니다."
  fi
  if [[ -f "$CODEX_DIR/AGENTS.md" ]] && ! strip_managed_block "$CODEX_DIR/AGENTS.md" "$AGENTS_START" "$AGENTS_END" >/dev/null; then
    die "전역 AGENTS 관리 마커가 손상되어 아무것도 삭제하지 않았습니다."
  fi
  for file in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml"; do
    if [[ -e "$file" ]] && { [[ ! -f "$file" ]] || ! grep -Fq "$MANAGED_AGENT_MARKER" "$file"; }; then
      die "관리 파일 식별자가 일치하지 않아 아무것도 삭제하지 않았습니다: $file"
    fi
  done
  if [[ -e "$CODEX_DIR/skills/persona-council" ]] && \
    { [[ ! -d "$CODEX_DIR/skills/persona-council" ]] || [[ ! -f "$CODEX_DIR/skills/persona-council/.persona-team-managed" ]]; }; then
    die "관리 스킬 식별자가 일치하지 않아 아무것도 삭제하지 않았습니다."
  fi
  bin="$(state_get bin_dir 2>/dev/null || persona_bin_dir)"
  if [[ -e "$bin/persona" ]] && { [[ ! -f "$bin/persona" ]] || ! grep -Fq "$LAUNCHER_MARKER" "$bin/persona"; }; then
    die "관리 명령 식별자가 일치하지 않아 아무것도 삭제하지 않았습니다: $bin/persona"
  fi
  shell_rc="$(state_get shell_rc 2>/dev/null || true)"
  if [[ -n "$shell_rc" && -f "$shell_rc" ]] && ! strip_managed_block "$shell_rc" "$PATH_START" "$PATH_END" >/dev/null; then
    die "셸 PATH 관리 마커가 손상되어 아무것도 삭제하지 않았습니다: $shell_rc"
  fi

  count="$(find "$PERSONA_ROOT" -type f -print | wc -l | tr -d ' ')"
  size="$(du -sh "$PERSONA_ROOT" 2>/dev/null | awk '{print $1}')"
  printf '영구 삭제 대상: %s\n파일 수: %s\n크기: %s\n' "$PERSONA_ROOT" "$count" "${size:-unknown}"
  printf '보존: Persona 소스 저장소, 각 프로젝트의 docs/persona, Git 자격 증명, Codex 자체 기억과 기존 작업\n'
  if [[ -z "$confirmation" ]]; then
    [[ -t 0 && -r /dev/tty ]] || die "대화형 터미널이 아닙니다. --confirm DELETE-PERSONA-DATA가 필요합니다."
    printf '계속하려면 DELETE-PERSONA-DATA를 정확히 입력하세요: '
    IFS= read -r confirmation </dev/tty
  fi
  [[ "$confirmation" == "DELETE-PERSONA-DATA" ]] || die "확인 문구가 일치하지 않아 아무것도 삭제하지 않았습니다."

  current_model="$(toml_root_get "$CODEX_DIR/config.toml" model 2>/dev/null || printf '%s' __missing__)"
  current_effort="$(toml_root_get "$CODEX_DIR/config.toml" model_reasoning_effort 2>/dev/null || printf '%s' __missing__)"
  last_model="$(state_get last_written_loop_model 2>/dev/null || printf '%s' __unknown__)"
  last_effort="$(state_get last_written_loop_effort 2>/dev/null || printf '%s' __unknown__)"
  original_model="$(state_get original_model 2>/dev/null || printf '%s' __missing__)"
  original_effort="$(state_get original_effort 2>/dev/null || printf '%s' __missing__)"
  restore_model="$current_model"
  restore_effort="$current_effort"
  if [[ "$current_model" == "$last_model" ]]; then restore_model="$original_model"; else warn "Loop 모델이 설치 후 변경되어 현재 값을 보존했습니다."; fi
  if [[ "$current_effort" == "$last_effort" ]]; then restore_effort="$original_effort"; else warn "Loop 추론 강도가 설치 후 변경되어 현재 값을 보존했습니다."; fi

  transaction="$(mktemp -d "${TMPDIR:-/tmp}/persona-uninstall.XXXXXX")"
  chmod 700 "$transaction"
  snapshot_install_target "$transaction" local_root "$PERSONA_ROOT"
  snapshot_install_target "$transaction" config "$CODEX_DIR/config.toml"
  snapshot_install_target "$transaction" agents "$CODEX_DIR/AGENTS.md"
  snapshot_install_target "$transaction" soul "$CODEX_DIR/agents/soul.toml"
  snapshot_install_target "$transaction" core "$CODEX_DIR/agents/core.toml"
  snapshot_install_target "$transaction" skill "$CODEX_DIR/skills/persona-council"
  snapshot_install_target "$transaction" launcher "$bin/persona"
  if [[ -n "$shell_rc" ]]; then snapshot_install_target "$transaction" shell_rc "$shell_rc"; fi

  set +e
  (
    set -e
    remove_block_from_file "$CODEX_DIR/AGENTS.md" "$AGENTS_START" "$AGENTS_END"
    for file in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml"; do [[ ! -e "$file" ]] || rm -f -- "$file"; done
    if [[ -d "$CODEX_DIR/skills/persona-council" ]]; then rm -rf -- "$CODEX_DIR/skills/persona-council"; fi
    write_config_pair "$restore_model" "$restore_effort"
    if [[ -n "$shell_rc" ]]; then remove_block_from_file "$shell_rc" "$PATH_START" "$PATH_END"; fi
    if [[ -f "$bin/persona" ]]; then rm -f -- "$bin/persona"; fi
    rm -rf -- "$PERSONA_ROOT"
  )
  uninstall_status=$?
  set -e
  if (( uninstall_status != 0 )); then
    restore_install_target "$transaction" local_root "$PERSONA_ROOT"
    restore_install_target "$transaction" config "$CODEX_DIR/config.toml"
    restore_install_target "$transaction" agents "$CODEX_DIR/AGENTS.md"
    restore_install_target "$transaction" soul "$CODEX_DIR/agents/soul.toml"
    restore_install_target "$transaction" core "$CODEX_DIR/agents/core.toml"
    restore_install_target "$transaction" skill "$CODEX_DIR/skills/persona-council"
    restore_install_target "$transaction" launcher "$bin/persona"
    if [[ -n "$shell_rc" ]]; then restore_install_target "$transaction" shell_rc "$shell_rc"; fi
    rm -rf -- "$transaction"
    die "제거 중 오류가 발생해 설치와 로컬 데이터를 이전 상태로 복구했습니다."
  fi
  rm -rf -- "$transaction"
  info "Persona 전역 설치와 전용 로컬 데이터 ${count}개를 영구 삭제했습니다. 이 데이터는 Persona 백업에서도 복구할 수 없습니다."
  info "Persona 소스 저장소, 프로젝트 문서, Codex 자체 기억과 기존 작업은 보존했습니다."
}

usage() {
  cat <<'EOF'
Loop · Soul · Core persona manager

Usage:
  persona profile economy|balanced|max
  persona model set loop|soul|core luna|terra|sol low|medium|high|xhigh|max|ultra
  persona model reset loop|soul|core
  persona status
  persona doctor
  persona update
  persona project init [--name <name>]
  persona project status|validate
  persona project index --approved
  persona team bind|status|cursor|clear ...
  persona handoff add|list|clear ...
  persona meeting draft|list|publish|clear ...
  persona writer acquire|status|release|recover ...
  persona context loop|soul|core
  persona memory add --scope global ... --approved
  persona memory retract <id> --approved
  persona memory status
  persona uninstall [--confirm DELETE-PERSONA-DATA]
EOF
}

ensure_installed() {
  validate_local_layout
  [[ "$(state_get installed 2>/dev/null || true)" == "true" ]] || die "Persona Team이 설치되어 있지 않습니다."
  cleanup_expired_pending
  chmod_private_tree
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in help|-h|--help|version|--version) ;; *) require_macos ;; esac
  case "$command" in
    __install) command_install "$@" ;;
    profile) ensure_installed; command_profile "$@" ;;
    model) ensure_installed; command_model "$@" ;;
    status) ensure_installed; command_status "$@" ;;
    doctor) command_doctor "$@" ;;
    update) [[ $# -eq 0 ]] || die "사용법: persona update"; command_update ;;
    project) ensure_installed; command_project "$@" ;;
    team) ensure_installed; command_team "$@" ;;
    handoff) ensure_installed; command_handoff "$@" ;;
    meeting) ensure_installed; command_meeting "$@" ;;
    writer) ensure_installed; command_writer "$@" ;;
    context) ensure_installed; command_context "$@" ;;
    memory) ensure_installed; command_memory "$@" ;;
    sync) [[ $# -eq 0 ]] || die "사용법: persona sync"; command_sync ;;
    uninstall) command_uninstall "$@" ;;
    help|-h|--help) usage ;;
    version|--version) printf '%s\n' "$PERSONA_VERSION" ;;
    *) usage >&2; die "알 수 없는 명령입니다: $command" ;;
  esac
}

main "$@"
