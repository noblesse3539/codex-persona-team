# Loop · Soul · Core

Codex 데스크톱과 CLI에서 사용하는 개인용 AI 페르소나 팀입니다.

- **Loop(루프)**: 기본 대화 상대이자 게임 디렉터·프로듀서·통합자
- **Soul(소울)**: 플레이어 경험과 크리에이티브 방향을 맡는 여성 AI
- **Core(코어)**: 기술 구조와 출시 가능성을 맡는 남성 AI

평소에는 루프만 응답합니다. `소울아`, `코어야`, `@Soul`, `@Core`로 한 번 직접 부르거나 `소울 모드`, `코어 모드`로 현재 작업의 대화 상대를 바꿀 수 있습니다. `셋이 논의해줘` 또는 `팀 회의`는 세 관점의 간결한 2라운드 회의를 시작합니다.

## 설치

### macOS

```bash
./scripts/install.sh
```

기본 설치 위치는 `~/.codex`이며 관리 명령은 `~/.codex/bin`에 설치됩니다. 설치 후 새 터미널을 열거나 안내된 PATH 설정을 적용하세요.

### Windows PowerShell

```powershell
.\scripts\install.ps1
```

기본 설치 위치는 `$env:USERPROFILE\.codex`이며 관리 명령은 그 아래 `bin`에 설치됩니다.

설치기는 기존 전역 지침과 Codex 설정을 백업하고, Loop 팀 전용 관리 구역과 이름이 지정된 파일만 변경합니다. 최초 프로필은 `economy`입니다.

## 명령

```text
persona profile economy|balanced|max
persona model set loop|soul|core luna|terra|sol low|medium|high|xhigh|max|ultra
persona model reset loop|soul|core
persona status
persona doctor
persona project use <slug>
persona context loop|soul|core
persona memory add --scope global|project --audience shared|loop|soul|core --summary <요약> --text <내용> --approved
persona memory retract <id> --approved
persona sync
persona uninstall
```

`profile`은 개별 모델 재정의를 지우고 프리셋 전체를 적용합니다. `model set`은 한 페르소나만 바꾸며, `model reset`은 현재 프리셋의 값으로 되돌립니다. 모델 설정은 PC별 로컬 상태라 Git으로 동기화되지 않습니다.

추론 강도 `ultra`는 Sol과 Terra에서만 사용할 수 있으며 Luna에서는 거부됩니다.

| 프로필 | Loop | Soul | Core |
|---|---|---|---|
| `economy` | Luna / max | Luna / max | Luna / max |
| `balanced` | Terra / max | Luna / max | Luna / max |
| `max` | Sol / max | Sol / max | Sol / max |

이미 열린 Codex 작업의 모델은 바뀌지 않습니다. 해당 작업에서는 데스크톱 UI로 모델을 직접 선택하세요. 프로젝트의 `.codex/config.toml`이나 작업별 선택이 사용자 기본값보다 우선할 수도 있습니다.

## 기억 절차

페르소나는 먼저 `[기억 후보]`를 보여주며 범위와 대상을 명시합니다. 창작자님이 저장을 분명히 승인한 뒤에만 `persona memory add ... --approved`를 실행합니다. 기록은 즉시 로컬 저장소에 생기지만 원격 반영은 `persona sync`를 실행할 때만 일어납니다.

기억에는 암호, 토큰, API 키, 개인 키 같은 비밀정보를 넣지 않습니다. 개인 일지는 역할상 분리일 뿐 보안 경계가 아니며 저장소 소유자는 모두 열람할 수 있습니다.

## 비공개 GitHub 연결

1. GitHub 브라우저에서 빈 비공개 저장소를 만듭니다.
2. 이 저장소에 원격을 연결하고 최초 푸시를 수행합니다.
3. 다른 PC에서 복제한 뒤 해당 OS 설치기를 실행합니다.

`persona sync`는 승인 시 기록한 SHA-256, 경로, 메타데이터와 비밀정보 여부를 다시 확인한 뒤 도우미가 생성한 기억 파일만 자동 커밋하고 `pull --rebase`와 `push`를 실행합니다. 승인 뒤 내용이 바뀌었거나 기존 staged 변경 또는 detached HEAD가 있으면 커밋 전에 중단합니다. 충돌은 임의로 해결하지 않습니다. Git 인증은 운영체제의 기존 자격 증명 관리자를 사용하며 토큰을 이 저장소에 저장하지 않습니다.
