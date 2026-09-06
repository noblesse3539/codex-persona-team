#!/usr/bin/env bash

set -euo pipefail

if [[ "${PERSONA_TEST_UNAME:-$(uname -s)}" != "Darwin" ]]; then
  printf 'persona: 오류: Persona Team v2는 macOS에서만 설치할 수 있습니다.\n' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

PERSONA_SOURCE_ROOT="$REPO_ROOT" "$SCRIPT_DIR/persona.sh" __install
