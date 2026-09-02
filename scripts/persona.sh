#!/usr/bin/env bash
# LOOP-PERSONA-TEAM:LAUNCHER

set -euo pipefail

PERSONA_VERSION="1.0.0"
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
STATE_DIR="$CODEX_DIR/persona-team"
STATE_FILE="$STATE_DIR/state.conf"
BACKUP_DIR="$STATE_DIR/backups"
PENDING_FILE="$STATE_DIR/pending-memory.txt"
PROJECT_MAP="$STATE_DIR/projects.tsv"

timestamp() {
  date -u '+%Y%m%dT%H%M%SZ'
}

state_get() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  awk -v wanted="$key" '
    index($0, wanted "=") == 1 {
      print substr($0, length(wanted) + 2)
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$STATE_FILE"
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp
  [[ "$key" =~ ^[a-z0-9_]+$ ]] || die "잘못된 상태 키입니다: $key"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "상태 값에는 줄바꿈을 넣을 수 없습니다."
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
  repo="$(resolve_repo_root)"
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

normalize_remote() {
  local remote="$1"
  remote="${remote%.git}"
  remote="${remote%/}"
  remote="$(printf '%s' "$remote" | sed -E 's#^[a-zA-Z]+://([^/@]+@)?##; s#^git@([^:]+):#\1/#' | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$remote"
}

mapped_project() {
  local here line path slug best="" best_len=0
  here="$(pwd -P)"
  [[ -f "$PROJECT_MAP" ]] || return 1
  while IFS=$'\t' read -r path slug; do
    [[ -n "$path" && -n "$slug" ]] || continue
    case "$here/" in
      "$path/"*)
        if (( ${#path} > best_len )); then best="$slug"; best_len=${#path}; fi
        ;;
    esac
  done < "$PROJECT_MAP"
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

auto_project_id() {
  local remote normalized slug digest
  if remote="$(git remote get-url origin 2>/dev/null)"; then
    normalized="$(normalize_remote "$remote")"
    slug="$(basename "$normalized" | tr -cd '[:alnum:]._-')"
    slug="$(printf '%s' "${slug:-project}" | tr '[:upper:]' '[:lower:]')"
    digest="$(printf '%s' "$normalized" | hash_text)"
    printf '%s-%s\n' "$slug" "$digest"
    return 0
  fi
  mapped_project
}

command_project() {
  local action="${1:-}" slug="${2:-}" root tmp
  [[ "$action" == "use" && $# -eq 2 ]] || die "사용법: persona project use <slug>"
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "프로젝트 slug는 영문자나 숫자로 시작하고 영문자, 숫자, 점, 밑줄, 하이픈만 사용할 수 있습니다."
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp "$STATE_DIR/.projects.XXXXXX")"
  if [[ -f "$PROJECT_MAP" ]]; then
    awk -F '\t' -v wanted="$root" '$1 != wanted { print }' "$PROJECT_MAP" > "$tmp"
  fi
  printf '%s\t%s\n' "$root" "$slug" >> "$tmp"
  mv "$tmp" "$PROJECT_MAP"
  info "현재 프로젝트를 $slug 로 연결했습니다."
}

memory_is_retracted() {
  local repo="$1" id="$2"
  [[ -f "$repo/memory/retractions/$id.md" ]]
}

memory_summary() {
  local file="$1"
  awk -F ': ' '$1 == "summary" { line=substr($0, index($0, ":")+2); gsub(/^\"|\"$/, "", line); print line; exit }' "$file"
}

memory_id() {
  local file="$1"
  basename "$file" .md
}

collect_memory_files() {
  local repo="$1" persona="$2" project_id="${3:-}" dir
  for dir in \
    "$repo/memory/global/shared/entries" \
    "$repo/memory/global/journals/$persona"; do
    [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -type f -name '*.md' -print
  done
  if [[ -n "$project_id" ]]; then
    for dir in \
      "$repo/memory/projects/$project_id/shared" \
      "$repo/memory/projects/$project_id/journals/$persona"; do
      [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -type f -name '*.md' -print
    done
  fi
  return 0
}

command_context() {
  local persona="${1:-}" repo project_id="" list_file active_file file id summary count=0
  [[ $# -eq 1 ]] || die "사용법: persona context loop|soul|core"
  validate_persona "$persona"
  repo="$(resolve_repo_root)"
  project_id="$(auto_project_id 2>/dev/null || true)"
  printf '# Persona canonical context\n\n'
  cat "$repo/canon/team.md"
  printf '\n'
  cat "$repo/canon/$persona.md"
  printf '\n'
  cat "$repo/memory/global/shared/profile.md"
  if [[ -n "$project_id" ]]; then
    printf '\n## Current project\n\n- id: `%s`\n' "$project_id"
    if [[ -f "$repo/memory/projects/$project_id/shared/profile.md" ]]; then
      printf '\n'
      cat "$repo/memory/projects/$project_id/shared/profile.md"
    fi
  fi

  list_file="$(mktemp "${TMPDIR:-/tmp}/persona-memory-list.XXXXXX")"
  active_file="$(mktemp "${TMPDIR:-/tmp}/persona-memory-active.XXXXXX")"
  collect_memory_files "$repo" "$persona" "$project_id" | sort > "$list_file"
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    id="$(memory_id "$file")"
    if ! memory_is_retracted "$repo" "$id"; then printf '%s\n' "$file" >> "$active_file"; fi
  done < "$list_file"
  rm -f "$list_file"

  if [[ -s "$active_file" ]]; then
    printf '\n## Active memory index\n\n'
    while IFS= read -r file; do
      id="$(memory_id "$file")"
      summary="$(memory_summary "$file")"
      printf -- '- `%s`: %s\n' "$id" "${summary:-승인된 기억}"
      count=$((count + 1))
    done < "$active_file"
    printf '\n## Recent memory details\n'
    tail -n 8 "$active_file" | while IFS= read -r file; do
      printf '\n'
      cat "$file"
    done
  fi
  rm -f "$active_file"
}

contains_secret() {
  LC_ALL=C grep -Eqi '(BEGIN[[:space:]].*PRIVATE KEY|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|session[_ -]?cookie|password[[:space:]]*[:=]|secret[[:space:]]*[:=]|recovery[_ -]?code|sk-[A-Za-z0-9_-]{12,}|비밀번호[[:space:]]*[:=]|API[[:space:]]*키[[:space:]]*[:=]|(접근|갱신)?[[:space:]]*토큰[[:space:]]*[:=]|개인[[:space:]]*키[[:space:]]*[:=]|복구[[:space:]]*코드[[:space:]]*[:=])'
}

pending_add() {
  local repo="$1" file="$2" relative digest tmp
  relative="${file#"$repo/"}"
  digest="$(hash_file "$file")"
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp "$STATE_DIR/.pending-memory.XXXXXX")"
  if [[ -f "$PENDING_FILE" ]]; then
    awk -F '\t' -v wanted="$relative" 'NF < 2 || $2 != wanted { print }' "$PENDING_FILE" > "$tmp"
  fi
  printf '%s\t%s\n' "$digest" "$relative" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$PENDING_FILE"
}

validate_pending_memory() {
  local repo="$1" expected_hash="$2" relative="$3" file id actual_hash expected_scope="" expected_audience=""
  case "$relative" in
    memory/global/shared/entries/*.md) expected_scope="global"; expected_audience="shared" ;;
    memory/global/journals/loop/*.md) expected_scope="global"; expected_audience="loop" ;;
    memory/global/journals/soul/*.md) expected_scope="global"; expected_audience="soul" ;;
    memory/global/journals/core/*.md) expected_scope="global"; expected_audience="core" ;;
    memory/projects/*/shared/*.md) expected_scope="project"; expected_audience="shared" ;;
    memory/projects/*/journals/loop/*.md) expected_scope="project"; expected_audience="loop" ;;
    memory/projects/*/journals/soul/*.md) expected_scope="project"; expected_audience="soul" ;;
    memory/projects/*/journals/core/*.md) expected_scope="project"; expected_audience="core" ;;
    memory/retractions/*.md) ;;
    *) die "허용되지 않은 기억 경로가 동기화 대기열에 있습니다: $relative" ;;
  esac
  [[ "$relative" =~ ^memory/(global/(shared/entries|journals/(loop|soul|core))|projects/[A-Za-z0-9._-]+/(shared|journals/(loop|soul|core))|retractions)/[A-Za-z0-9._:-]+\.md$ ]] \
    || die "안전하지 않은 기억 경로가 동기화 대기열에 있습니다: $relative"
  file="$repo/$relative"
  [[ -f "$file" && ! -L "$file" ]] || die "대기 중인 기억 파일이 없거나 심볼릭 링크입니다: $relative"
  id="$(basename "$file" .md)"
  grep -Fqx "id: \"$id\"" "$file" || die "기억 ID 메타데이터가 파일명과 다릅니다: $relative"
  grep -Fqx 'approved_by: "creator"' "$file" || die "승인 메타데이터가 없는 기억입니다: $relative"
  if [[ -n "$expected_scope" ]]; then
    grep -Fqx "scope: \"$expected_scope\"" "$file" || die "기억 범위 메타데이터가 경로와 다릅니다: $relative"
    grep -Fqx "audience: \"$expected_audience\"" "$file" || die "기억 대상 메타데이터가 경로와 다릅니다: $relative"
    grep -Fqx 'status: "active"' "$file" || die "활성 상태 메타데이터가 없는 기억입니다: $relative"
  fi
  if contains_secret < "$file"; then die "비밀정보로 보이는 내용이 기억 파일에 추가되어 동기화를 중단했습니다: $relative"; fi
  actual_hash="$(hash_file "$file")"
  [[ "$actual_hash" == "$expected_hash" ]] || die "승인 뒤 변경된 기억은 다시 승인해야 합니다: $relative"
}

yaml_escape() {
  printf '%s' "$1" | tr '\r\n' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

command_memory_add() {
  local scope="" audience="" summary="" body="" kind="note" approved=0 project_id=""
  local repo base id created file tmp safe_summary
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope) [[ $# -ge 2 ]] || die "--scope 값이 필요합니다."; scope="$2"; shift 2 ;;
      --audience) [[ $# -ge 2 ]] || die "--audience 값이 필요합니다."; audience="$2"; shift 2 ;;
      --summary) [[ $# -ge 2 ]] || die "--summary 값이 필요합니다."; summary="$2"; shift 2 ;;
      --text) [[ $# -ge 2 ]] || die "--text 값이 필요합니다."; body="$2"; shift 2 ;;
      --kind) [[ $# -ge 2 ]] || die "--kind 값이 필요합니다."; kind="$2"; shift 2 ;;
      --approved) approved=1; shift ;;
      *) die "알 수 없는 memory add 옵션입니다: $1" ;;
    esac
  done
  [[ "$approved" == "1" ]] || die "창작자님의 명시적 승인 뒤 --approved를 지정해야 합니다."
  case "$scope" in global|project) ;; *) die "--scope는 global 또는 project여야 합니다." ;; esac
  case "$audience" in shared|loop|soul|core) ;; *) die "--audience는 shared, loop, soul, core 중 하나여야 합니다." ;; esac
  case "$kind" in note|fact|decision|preference|journal|reflection) ;; *) die "지원하지 않는 기억 종류입니다." ;; esac
  [[ -n "$summary" && -n "$body" ]] || die "--summary와 --text는 비워둘 수 없습니다."
  if printf '%s\n%s\n' "$summary" "$body" | contains_secret; then
    die "비밀정보로 보이는 내용은 공식 기억에 저장할 수 없습니다."
  fi
  repo="$(resolve_repo_root)"
  if [[ "$scope" == "project" ]]; then
    project_id="$(auto_project_id 2>/dev/null || true)"
    [[ -n "$project_id" ]] || die "프로젝트를 식별할 수 없습니다. 먼저 persona project use <slug>를 실행하세요."
    if [[ "$audience" == "shared" ]]; then base="$repo/memory/projects/$project_id/shared"; else base="$repo/memory/projects/$project_id/journals/$audience"; fi
  else
    if [[ "$audience" == "shared" ]]; then base="$repo/memory/global/shared/entries"; else base="$repo/memory/global/journals/$audience"; fi
  fi
  mkdir -p "$base"
  created="$(timestamp)"
  if command -v uuidgen >/dev/null 2>&1; then
    id="${created}-$(uuidgen | tr '[:upper:]' '[:lower:]')"
  else
    id="${created}-$$-$(printf '%s' "$summary$created$$" | hash_text)"
  fi
  file="$base/$id.md"
  tmp="$(mktemp "$base/.memory.XXXXXX")"
  safe_summary="$(yaml_escape "$summary")"
  {
    printf '%s\n' '---'
    printf 'id: "%s"\n' "$id"
    printf 'created_at: "%s"\n' "$created"
    printf 'scope: "%s"\n' "$scope"
    if [[ -n "$project_id" ]]; then printf 'project: "%s"\n' "$project_id"; fi
    printf 'audience: "%s"\n' "$audience"
    printf 'kind: "%s"\n' "$kind"
    printf 'summary: "%s"\n' "$safe_summary"
    printf 'approved_by: "creator"\n'
    printf 'status: "active"\n'
    printf '%s\n\n' '---'
    printf '%s\n' "$body"
  } > "$tmp"
  mv "$tmp" "$file"
  pending_add "$repo" "$file"
  info "기억을 기록했습니다: $id"
}

command_memory_retract() {
  local id="${1:-}" approved="${2:-}" repo original tombstone tmp
  [[ $# -eq 2 && "$approved" == "--approved" ]] || die "사용법: persona memory retract <id> --approved"
  [[ "$id" =~ ^[A-Za-z0-9._:-]+$ ]] || die "잘못된 기억 ID입니다."
  repo="$(resolve_repo_root)"
  original="$(find "$repo/memory" -type f -name "$id.md" ! -path '*/retractions/*' -print -quit)"
  [[ -n "$original" ]] || die "기억 ID를 찾을 수 없습니다: $id"
  tombstone="$repo/memory/retractions/$id.md"
  [[ ! -e "$tombstone" ]] || die "이미 철회된 기억입니다: $id"
  mkdir -p "$(dirname "$tombstone")"
  tmp="$(mktemp "$repo/memory/retractions/.retract.XXXXXX")"
  {
    printf '%s\n' '---'
    printf 'id: "%s"\n' "$id"
    printf 'retracted_at: "%s"\n' "$(timestamp)"
    printf 'approved_by: "creator"\n'
    printf '%s\n\n' '---'
    printf 'This memory is excluded from active persona context.\n'
  } > "$tmp"
  mv "$tmp" "$tombstone"
  pending_add "$repo" "$tombstone"
  info "기억을 활성 문맥에서 철회했습니다: $id"
}

command_memory() {
  local action="${1:-}"
  shift || true
  case "$action" in
    add) command_memory_add "$@" ;;
    retract) command_memory_retract "$@" ;;
    *) die "사용법: persona memory add ... | persona memory retract ..." ;;
  esac
}

deploy_from_repo() {
  local repo
  repo="$(resolve_repo_root)"
  check_install_conflicts
  install_agents_block "$repo"
  install_skill "$repo"
  install_launcher "$repo"
  apply_models
}

command_sync() {
  local repo branch pending_count=0 line expected_hash relative extra remote_heads
  local pending_paths=()
  repo="$(resolve_repo_root)"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "저장소가 아직 Git 저장소가 아닙니다."
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" \
    || die "detached HEAD에서는 기억을 안전하게 동기화할 수 없습니다. 브랜치로 전환하세요."
  if ! git -C "$repo" diff --cached --quiet --; then
    die "기존 staged 변경이 있어 기억 동기화를 중단했습니다. 먼저 stage를 비우거나 커밋하세요."
  fi
  if [[ -s "$PENDING_FILE" ]]; then
    while IFS=$'\t' read -r expected_hash relative extra; do
      [[ -n "$expected_hash" && -n "$relative" && -z "$extra" ]] \
        || die "이전 형식이거나 손상된 기억 대기열입니다. 해당 기억을 다시 승인해 주세요."
      validate_pending_memory "$repo" "$expected_hash" "$relative"
      pending_paths+=("$relative")
      pending_count=$((pending_count + 1))
    done < "$PENDING_FILE"
    if (( pending_count > 0 )); then
      for line in "${pending_paths[@]}"; do
        if ! git -C "$repo" add -- "$line"; then
          git -C "$repo" reset --quiet -- "${pending_paths[@]}" 2>/dev/null || true
          die "기억 파일을 stage하지 못했습니다: $line"
        fi
      done
      if ! git -C "$repo" -c user.name='Persona Memory' -c user.email='persona-memory@local' \
        commit --only -m "memory: sync approved persona memories $(timestamp)" -- "${pending_paths[@]}"; then
        git -C "$repo" reset --quiet -- "${pending_paths[@]}" 2>/dev/null || true
        die "기억 커밋에 실패했습니다. 대기 중인 파일은 보존했습니다."
      fi
      : > "$PENDING_FILE"
    fi
  fi

  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    die "기억 외의 커밋되지 않은 변경이 있어 pull/push를 중단했습니다. 먼저 해당 변경을 정리하세요."
  fi
  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    deploy_from_repo
    warn "origin 원격이 없어 로컬 커밋까지만 완료했습니다. 비공개 GitHub 저장소를 연결한 뒤 다시 sync 하세요."
    return 0
  fi
  if remote_heads="$(git -C "$repo" ls-remote --heads origin "$branch")"; then
    if [[ -n "$remote_heads" ]]; then
      git -C "$repo" pull --rebase origin "$branch" || die "리베이스가 중단되었습니다. 충돌을 직접 확인하세요."
    fi
  else
    die "원격 저장소에 연결하지 못했습니다. 로컬 커밋은 보존되어 있습니다."
  fi
  git -C "$repo" push -u origin "$branch" || die "push에 실패했습니다. 로컬 커밋은 보존되어 있습니다."
  deploy_from_repo
  info "공식 기억과 페르소나 자료를 동기화했습니다."
}

find_project_override() {
  local root current
  current="$(pwd -P)"
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$root" && -f "$root/.codex/config.toml" ]]; then
    toml_root_get "$root/.codex/config.toml" model 2>/dev/null || true
  elif [[ -f "$current/.codex/config.toml" ]]; then
    toml_root_get "$current/.codex/config.toml" model 2>/dev/null || true
  fi
}

command_status() {
  local profile project_override
  profile="$(state_get profile 2>/dev/null || printf '%s' 'not-installed')"
  printf 'Persona Team %s\n' "$PERSONA_VERSION"
  printf 'profile: %s\n' "$profile"
  if [[ "$profile" != "not-installed" ]]; then
    for persona in loop soul core; do
      if [[ -n "$(state_get "override_${persona}_model" 2>/dev/null || true)" ]]; then
        printf '%s: %s / %s (source: local override)\n' "$persona" "$(effective_value "$persona" model)" "$(effective_value "$persona" effort)"
      else
        printf '%s: %s / %s (source: profile %s)\n' "$persona" "$(effective_value "$persona" model)" "$(effective_value "$persona" effort)" "$profile"
      fi
    done
  fi
  printf 'config loop: %s / %s\n' \
    "$(toml_root_get "$CODEX_DIR/config.toml" model 2>/dev/null || printf '%s' '<unset>')" \
    "$(toml_root_get "$CODEX_DIR/config.toml" model_reasoning_effort 2>/dev/null || printf '%s' '<unset>')"
  project_override="$(find_project_override)"
  if [[ -n "$project_override" ]]; then
    printf 'project override: %s (전역 Loop 기본값보다 우선)\n' "$project_override"
  fi
  printf 'active desktop task: 작업별 UI 모델 선택이 위 값보다 우선할 수 있습니다.\n'
  printf 'repository: %s\n' "$(state_get repo_root 2>/dev/null || printf '%s' '<unset>')"
  printf 'project memory: %s\n' "$(auto_project_id 2>/dev/null || printf '%s' '<unmapped>')"
}

command_doctor() {
  local failures=0 marker_count repo
  if command -v codex >/dev/null 2>&1; then
    info "Codex: $(codex --version 2>/dev/null || printf '%s' '실행 실패')"
    if [[ "${PERSONA_SKIP_CODEX_VALIDATE:-0}" != "1" ]] && ! codex --strict-config --version >/dev/null 2>&1; then
      warn "config.toml 엄격 검증 실패"
      failures=$((failures + 1))
    fi
  else
    warn "codex 명령을 PATH에서 찾지 못했습니다."
    failures=$((failures + 1))
  fi
  marker_count="$(grep -Fc "$AGENTS_START" "$CODEX_DIR/AGENTS.md" 2>/dev/null || true)"
  if [[ "$marker_count" != "1" ]]; then warn "전역 AGENTS 관리 블록 개수가 1이 아닙니다."; failures=$((failures + 1)); fi
  for file in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml" "$CODEX_DIR/skills/persona-council/SKILL.md"; do
    if [[ ! -f "$file" ]]; then warn "설치 파일 누락: $file"; failures=$((failures + 1)); fi
  done
  repo="$(state_get repo_root 2>/dev/null || true)"
  if [[ -z "$repo" || ! -d "$repo/.git" ]]; then warn "Git 저장소 상태를 확인하세요: ${repo:-<unset>}"; failures=$((failures + 1)); fi
  if (( failures > 0 )); then
    die "진단에서 $failures개 문제를 찾았습니다."
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
  local current_model current_effort last_model last_effort original_model original_effort restore_model restore_effort shell_rc bin
  mkdir -p "$BACKUP_DIR"
  if [[ -f "$CODEX_DIR/AGENTS.md" ]]; then cp -p "$CODEX_DIR/AGENTS.md" "$BACKUP_DIR/AGENTS.md.uninstall.$(timestamp).$$.bak"; fi
  remove_block_from_file "$CODEX_DIR/AGENTS.md" "$AGENTS_START" "$AGENTS_END"
  for file in "$CODEX_DIR/agents/soul.toml" "$CODEX_DIR/agents/core.toml"; do
    if [[ -f "$file" ]] && grep -Fq "$MANAGED_AGENT_MARKER" "$file"; then rm -f "$file"; fi
  done
  if [[ -d "$CODEX_DIR/skills/persona-council" && -f "$CODEX_DIR/skills/persona-council/.persona-team-managed" ]]; then
    mv "$CODEX_DIR/skills/persona-council" "$BACKUP_DIR/persona-council.uninstall.$(timestamp).$$"
  fi
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
  write_config_pair "$restore_model" "$restore_effort"
  info "변경되지 않은 Loop 기본 설정을 설치 전 값으로 복원했습니다."
  shell_rc="$(state_get shell_rc 2>/dev/null || true)"
  if [[ -n "$shell_rc" ]]; then remove_block_from_file "$shell_rc" "$PATH_START" "$PATH_END"; fi
  bin="$(state_get bin_dir 2>/dev/null || persona_bin_dir)"
  if [[ -f "$bin/persona" ]] && grep -Fq "$LAUNCHER_MARKER" "$bin/persona"; then rm -f "$bin/persona"; fi
  state_set installed false
  info "전역 설치를 제거했습니다. 저장소, 기억과 백업은 보존했습니다."
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
  persona project use <slug>
  persona context loop|soul|core
  persona memory add ... --approved
  persona memory retract <id> --approved
  persona sync
  persona uninstall
EOF
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in
    __install) command_install "$@" ;;
    profile) command_profile "$@" ;;
    model) command_model "$@" ;;
    status) command_status "$@" ;;
    doctor) command_doctor "$@" ;;
    project) command_project "$@" ;;
    context) command_context "$@" ;;
    memory) command_memory "$@" ;;
    sync) [[ $# -eq 0 ]] || die "사용법: persona sync"; command_sync ;;
    uninstall) [[ $# -eq 0 ]] || die "사용법: persona uninstall"; command_uninstall ;;
    help|-h|--help) usage ;;
    version|--version) printf '%s\n' "$PERSONA_VERSION" ;;
    *) usage >&2; die "알 수 없는 명령입니다: $command" ;;
  esac
}

main "$@"
