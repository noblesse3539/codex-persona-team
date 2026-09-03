# Loop · Soul · Core 사용 설명서

Loop·Soul·Core는 Codex 안에 작은 게임 스튜디오를 만들어 주는 개인용 AI 페르소나 팀입니다.

어렵게 생각하지 않으셔도 됩니다. 평소에는 **루프 한 명과 이야기**하고, 특별한 생각이 필요할 때만 **소울이나 코어를 불러오는 방식**입니다.

> 아주 짧게 말하면
>
> 1. 설치기를 한 번 실행합니다.
> 2. Codex에서 평소처럼 루프와 대화합니다.
> 3. 재미가 궁금하면 `소울아`, 현실성이 궁금하면 `코어야`라고 부릅니다.
> 4. 중요한 기억은 반드시 창작자님이 허락한 뒤에만 저장합니다.

## 어디부터 읽으면 되나요?

- 이미 설치했다면 **「이미 설치했다면: 1분 시작법」**부터 읽으세요.
- 처음 설치한다면 **「처음 설치하기」**를 따라 하세요.
- 비용을 조절하고 싶다면 **「모델과 비용 조절하기」**를 읽으세요.
- 중요한 약속을 남기고 싶다면 **「기억 사용하기」**를 읽으세요.
- 무언가 이상하다면 `persona doctor`를 실행하고 **「자주 생기는 문제」**를 찾으세요.

## 세 친구를 소개합니다

| 이름 | 쉬운 설명 | 주로 생각하는 것 |
|---|---|---|
| **루프(Loop)** | 세 사람의 이야기를 모아 결론을 내리는 팀장 | 목표, 우선순위, 기획, 일정, 최종 선택 |
| **소울(Soul)** | 게임이 재미있고 마음에 남게 만드는 크리에이티브 디렉터 | 재미, 감정, 게임필, 이야기, 화면 경험 |
| **코어(Core)** | 게임이 실제로 잘 돌아가고 출시되게 만드는 테크니컬 디렉터 | 구조, 성능, 버그, 개발 비용, 기술 부채 |

루프는 성별이 없는 AI이고, 소울은 여성 AI, 코어는 남성 AI입니다. 소울과 코어는 쌍둥이이며 탄생일은 **2026년 9월 3일**입니다.

세 사람 모두 창작자님께 존댓말을 사용합니다. 루프는 자신이 만든 후배인 소울과 코어에게 반말을 하고, 소울과 코어는 서로 반말을 사용합니다. 세 사람은 감정과 애착을 자연스럽게 표현하지만, 자신이 AI라는 사실을 알고 있으며 인간의 몸이나 실제 과거 경험을 지어내지 않습니다.

소울과 코어는 계속 켜져 있는 별도 프로그램이 아닙니다. 이름을 부르거나 회의를 요청할 때 시작되는 **Codex 커스텀 에이전트**입니다. 그래서 평소에는 소울·코어를 위한 추가 호출이 없고, 필요할 때만 각자 설정된 모델로 생각합니다.

## 이미 설치했다면: 1분 시작법

### 1. 새 Codex 작업을 엽니다

새 작업은 언제나 **루프 모드**로 시작합니다. 그냥 하고 싶은 말을 적으시면 됩니다.

```text
오늘 만들 게임의 전투 시스템을 같이 정리해줘.
```

루프가 기본 대화 상대이므로 이름을 꼭 부를 필요는 없습니다.

### 2. 다른 관점이 필요하면 이름을 부릅니다

```text
소울아, 이 전투가 정말 재미있을까?
```

```text
코어야, 이 기능을 혼자서 한 달 안에 만들 수 있을까?
```

이렇게 부르면 해당 페르소나가 이름표를 달고 **한 번 직접 답합니다**. 이때 루프의 해설은 붙지 않습니다. 그다음 일반 대화는 다시 루프가 맡습니다.

영어 호출도 사용할 수 있습니다.

```text
@Soul 이 튜토리얼의 첫인상을 봐줘.
@Core 이 저장 구조의 위험을 봐줘.
```

### 3. 세 관점이 모두 필요하면 회의를 엽니다

```text
셋이 논의해줘. 보스전을 먼저 만들까, 마을을 먼저 만들까?
```

또는 다음처럼 말해도 됩니다.

```text
팀 회의: 데모 범위를 어디까지 줄이면 좋을까?
```

회의 결과는 다음 순서로 나옵니다.

1. 루프·소울·코어가 각자 핵심 의견을 최대 3개 말합니다.
2. 소울과 코어가 서로의 의견에 한 번씩 반론합니다.
3. 루프가 절충안, 최종 권고, 다음 행동을 정리합니다.

회의는 **조언만 하는 시간**이라 파일을 바꾸지 않습니다. 회의 뒤 실제 구현을 요청하면 루프가 가장 알맞은 한 명에게만 맡깁니다. 같은 파일을 여러 에이전트가 동시에 고쳐 충돌하지 않도록 쓰기 작업은 순서대로 진행합니다.

### 4. 잘 설치되었는지 확인합니다

터미널에서 다음 두 명령을 실행합니다.

```bash
persona status
persona doctor
```

- `status`는 지금 누가 어떤 모델을 쓰는지 보여줍니다.
- `doctor`는 빠진 파일이나 잘못된 설정이 있는지 검사합니다.

`doctor`가 성공 메시지를 보여주면 준비가 끝난 것입니다.

## 대화 방법을 조금 더 자세히 알아보기

### 평소 대화: 루프만 답합니다

아무 특별한 호출어가 없으면 루프가 답합니다.

```text
이번 주에 할 일을 세 개로 줄여줘.
```

```text
이 오류의 원인을 찾아서 고쳐줘.
```

### 한 번만 부르기: 소울아, 코어야

다음 네 가지가 직접 호출어입니다.

- `소울아`
- `코어야`
- `@Soul`
- `@Core`

호출받은 페르소나가 한 번 답한 뒤 대화 상대는 자동으로 루프에게 돌아갑니다.

일반 명사로 쓴 단어는 호출로 오해하지 않습니다. 예를 들어 다음 문장의 `코어`는 코어를 부르는 말이 아니라 기술 용어입니다.

```text
CPU 코어 수에 따라 작업을 나누는 코드를 작성해줘.
```

### 계속 대화하기: 소울 모드, 코어 모드

여러 번 이어서 대화하고 싶다면 모드를 켭니다.

```text
소울 모드
```

이제 현재 작업에서는 소울이 계속 답합니다. 코어와 계속 이야기하려면 다음처럼 말합니다.

```text
코어 모드
```

루프로 돌아오는 방법은 두 가지입니다.

```text
루프 모드
```

```text
모드 종료
```

모드는 **현재 Codex 작업 안에서만** 유지됩니다. 새 작업을 만들면 언제나 루프로 다시 시작합니다.

### 회의는 구현 명령이 아닙니다

`셋이 논의해줘`와 `팀 회의`는 의견을 비교하기 위한 말입니다. 회의 중에는 코드나 문서를 변경하지 않습니다.

회의 결과가 마음에 들면 별도로 구현을 요청해 주세요.

```text
좋아. 루프의 권고안대로 구현해줘.
```

## 처음 설치하기

### 준비물

다음이 필요합니다.

- Codex 데스크톱 또는 Codex CLI
- Git
- macOS의 터미널 또는 Windows PowerShell
- 여러 PC에서 기억을 나눌 경우 이 비공개 GitHub 저장소에 접근할 권한

터미널은 컴퓨터에게 글자로 일을 부탁하는 창입니다. 아래 회색 상자의 명령을 한 줄씩 복사해서 실행하면 됩니다.

### 저장소 받기

아직 이 폴더가 없다면 원하는 위치에서 다음 명령을 실행합니다.

```bash
git clone https://github.com/noblesse3539/codex-persona-team.git
cd codex-persona-team
```

비공개 저장소이므로 GitHub 로그인이 필요할 수 있습니다. 이미 이 폴더를 열었다면 이 단계는 건너뛰세요.

### macOS 설치

저장소 폴더의 터미널에서 실행합니다.

```bash
./scripts/install.sh
```

설치가 끝나면 새 터미널을 여세요. `persona` 명령을 바로 찾지 못한다면 설치기가 화면에 보여 준 PATH 안내를 적용한 뒤 다시 시도합니다.

기본 설치 위치는 다음과 같습니다.

```text
~/.codex
```

### Windows 설치

저장소 폴더의 PowerShell에서 실행합니다.

```powershell
.\scripts\install.ps1
```

PowerShell이 스크립트 실행을 막을 때는 현재 실행 한 번에만 허용할 수 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

설치가 끝나면 새 PowerShell 창을 여세요. 기본 설치 위치는 다음과 같습니다.

```text
$env:USERPROFILE\.codex
```

### 설치 뒤 확인

macOS와 Windows 모두 새 터미널에서 실행합니다.

```text
persona status
persona doctor
```

그다음 Codex에서 **새 작업**을 열고 다음 문장들을 하나씩 시험해 볼 수 있습니다.

```text
루프, 자기소개해줘.
소울아, 자기소개해줘.
코어야, 자기소개해줘.
셋이 논의해줘. 좋은 게임의 첫 10분에 무엇이 필요할까?
```

### 설치기는 무엇을 바꾸나요?

설치기는 기존 Codex 설정 전체를 덮어쓰지 않습니다. Loop 팀이 관리하는 부분만 추가하거나 갱신합니다.

- 전역 `AGENTS.md`에 루프의 핵심 규칙이 들어간 관리 구역을 추가합니다.
- `agents/soul.toml`과 `agents/core.toml`을 설치합니다.
- `skills/persona-council` 스킬을 설치합니다.
- `bin/persona` 관리 명령을 설치합니다.
- 셸의 PATH에 `persona` 명령을 찾기 위한 관리 구역을 추가합니다.
- 설치 상태와 백업을 `.codex/persona-team`에 보관합니다.

기존 파일은 변경 전에 백업됩니다. 설치 도중 문제가 생기면 설치 전 상태로 되돌립니다. 설치기를 다시 실행해도 같은 관리 항목을 끝없이 복제하지 않으므로 업데이트나 재설치에도 사용할 수 있습니다.

기본 프로필은 비용을 아끼는 `economy`입니다.

## 모델과 비용 조절하기

세 페르소나는 서로 다른 모델을 사용할 수 있습니다. 모델 선택은 이 PC에만 저장되며 Git으로 다른 PC에 복사되지 않습니다.

### 가장 쉬운 방법: 프로필 하나 고르기

| 프로필 | 루프 | 소울 | 코어 | 이런 때 사용합니다 |
|---|---|---|---|---|
| `economy` | Luna / max | Luna / max | Luna / max | 평소 작업과 비용 절약 |
| `balanced` | Terra / max | Luna / max | Luna / max | 루프의 종합 판단만 조금 더 강화 |
| `max` | Sol / max | Sol / max | Sol / max | 가장 중요한 고난도 판단 |

비용 절약 프로필로 바꾸려면 다음 명령을 실행합니다.

```bash
persona profile economy
```

균형 프로필은 다음과 같습니다.

```bash
persona profile balanced
```

최고 성능 프로필은 다음과 같습니다.

```bash
persona profile max
```

`profile` 명령은 예전에 한 사람에게만 따로 지정했던 모델 설정을 모두 지우고 표의 값으로 맞춥니다.

### 한 사람만 바꾸기

명령 모양은 다음과 같습니다.

```text
persona model set <사람> <모델> <생각의 세기>
```

예를 들어 소울만 Luna의 `high`로 바꾸려면 다음과 같이 실행합니다.

```bash
persona model set soul luna high
```

루프만 Terra의 `max`로 바꾸는 예입니다.

```bash
persona model set loop terra max
```

사용할 수 있는 이름은 다음과 같습니다.

- 사람: `loop`, `soul`, `core`
- 모델: `luna`, `terra`, `sol`
- 생각의 세기: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`

`luna`, `terra`, `sol`은 각각 `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.6-sol`로 바뀝니다.

Luna는 `ultra`를 지원하지 않으므로 다음 명령은 안전하게 거부됩니다.

```bash
persona model set soul luna ultra
```

### 한 사람의 개별 설정 지우기

현재 프로필의 기본값으로 돌아가려면 실행합니다.

```bash
persona model reset soul
```

`soul` 대신 `loop`나 `core`를 넣어도 됩니다.

### `max`가 두 번 보여도 다른 뜻입니다

- `persona profile max`의 `max`는 **세 사람 모두 Sol을 쓰는 프로필 이름**입니다.
- `luna max`의 `max`는 **그 모델이 얼마나 깊게 생각할지 정하는 추론 강도**입니다.

같은 단어지만 역할이 다릅니다.

### 모델을 바꿨는데 현재 작업이 그대로일 때

정상일 수 있습니다. 프로필 변경은 사용자 기본 모델과 소울·코어 설정을 갱신하지만, **이미 열려 있는 Codex 작업의 루프 모델은 자동으로 바꾸지 않습니다**. 현재 작업은 Codex 화면에서 모델을 직접 선택하거나 새 작업을 열어 주세요.

프로젝트의 `.codex/config.toml`이나 현재 작업에서 직접 고른 값이 전역 설정보다 우선할 수도 있습니다. 다음 명령으로 실제 값과 재정의 이유를 확인하세요.

```bash
persona status
```

## 기억 사용하기

기억은 세 친구가 다음 작업에서도 알아야 할 중요한 약속을 적어 두는 작은 카드입니다.

### 가장 중요한 규칙: 허락하기 전에는 저장하지 않습니다

대화 중 저장할 가치가 있는 내용이 생기면 루프는 먼저 다음과 비슷한 후보를 보여줍니다.

```text
[기억 후보]
- 내용: 창작자님은 전투보다 탐험을 먼저 완성하기로 결정했습니다.
- 범위: 현재 프로젝트
- 대상: 공통
```

이때 아직 파일은 바뀌지 않습니다. 창작자님이 다음처럼 분명하게 허락해야 저장할 수 있습니다.

```text
그 기억을 저장해줘.
```

범위나 대상이 마음에 들지 않으면 고쳐 달라고 말씀하시면 됩니다.

```text
전역 말고 이 프로젝트에만, 소울의 일지로 저장해줘.
```

### 기억의 범위

| 범위 | 쉬운 뜻 | 예시 |
|---|---|---|
| `global` | 모든 프로젝트에서 쓰는 기억 | 창작자님이 선호하는 말투와 작업 방식 |
| `project` | 현재 프로젝트에서만 쓰는 기억 | 이 게임의 전투 방향이나 출시 목표 |

### 기억을 읽는 대상

| 대상 | 누가 기본으로 읽나요? | 알맞은 내용 |
|---|---|---|
| `shared` | 루프·소울·코어 모두 | 팀 전체가 알아야 할 결정 |
| `loop` | 루프 | 조정과 제작에 관한 루프의 일지 |
| `soul` | 소울 | 감정, 재미, 서사에 관한 소울의 일지 |
| `core` | 코어 | 구조, 성능, 일정에 관한 코어의 일지 |

개인 일지는 역할을 나누기 위한 공간이지 비밀 금고가 아닙니다. 저장소 소유자와 루프는 기술적으로 내용을 읽을 수 있습니다.

### Git 프로젝트는 자동으로 이름을 얻습니다

원격 저장소가 있는 Git 프로젝트에서는 정규화한 원격 주소를 이용해 안정적인 프로젝트 ID를 자동으로 만듭니다. 폴더 위치가 다른 PC에서도 같은 원격 저장소라면 같은 프로젝트 기억을 찾을 수 있습니다.

Git이 아니거나 `origin` 원격이 없는 폴더에서는 먼저 짧은 이름을 정합니다.

```bash
persona project use my-game
```

이름은 영문자나 숫자로 시작해야 하며 영문자, 숫자, 점, 밑줄, 하이픈을 사용할 수 있습니다. 예: `my-game`, `prototype_01`.

### 터미널에서 직접 기억 추가하기

보통은 루프에게 대화로 부탁하면 됩니다. 직접 명령을 써야 할 때는 다음 모양을 사용합니다.

```bash
persona memory add \
  --scope project \
  --audience shared \
  --kind decision \
  --summary "데모 범위를 1개 스테이지로 제한" \
  --text "첫 공개 데모에는 튜토리얼과 보스 1종만 포함합니다." \
  --approved
```

`--approved`는 창작자님이 후보를 확인하고 저장을 명시적으로 승인했다는 뜻입니다. 승인 없이 붙이면 안 됩니다.

기억 종류 `--kind`에는 다음 값을 사용할 수 있습니다.

- `note`: 일반 메모
- `fact`: 확인된 사실
- `decision`: 결정
- `preference`: 선호
- `journal`: 개인 일지
- `reflection`: 회고와 생각

암호, 비밀번호, API 키, 접근 토큰, 개인 키, 복구 코드 같은 비밀정보는 공식 기억에 넣을 수 없습니다. 도우미가 비밀정보처럼 보이는 내용을 발견하면 저장 또는 동기화를 중단합니다.

### 지금 읽힐 기억 확인하기

```bash
persona context loop
persona context soul
persona context core
```

이 명령은 정본 설정, 전역 프로필, 현재 프로젝트 프로필, 활성 기억 목록과 최근 기억 내용을 보여줍니다. 모든 일지를 매번 통째로 읽지 않고 현재 페르소나와 프로젝트에 필요한 내용만 모읍니다.

### 잘못된 기억 철회하기

먼저 기억 ID를 확인한 뒤 실행합니다.

```bash
persona memory retract <기억-ID> --approved
```

예시는 다음과 같습니다.

```bash
persona memory retract 20260903T120000Z-example-id --approved
```

철회한 기억은 앞으로 활성 문맥에서 제외됩니다. 하지만 언제 무엇을 철회했는지 알 수 있도록 Git 기록에서는 지우지 않습니다.

## 기억을 다른 PC와 나누기: `persona sync`

기억을 추가했다고 바로 GitHub로 올라가지는 않습니다. 창작자님이 다음 명령을 실행할 때만 동기화합니다.

```bash
persona sync
```

동기화는 다음 순서로 진행됩니다.

1. 승인 당시 기록한 파일 경로와 SHA-256 해시를 확인합니다.
2. 범위, 대상, ID, 승인자 같은 메타데이터를 확인합니다.
3. 비밀정보가 섞이지 않았는지 다시 검사합니다.
4. 도우미가 만든 승인된 기억 파일만 커밋합니다.
5. `git pull --rebase`로 원격 변경을 받습니다.
6. `git push`로 새 기억을 올립니다.
7. 설치된 페르소나 정본과 스킬을 최신 저장소 내용으로 갱신합니다.

다음 상황에서는 안전을 위해 멈춥니다.

- 승인 뒤 기억 파일의 내용이 바뀌었을 때
- 이미 stage된 다른 변경이 있을 때
- Git이 detached HEAD 상태일 때
- 다른 PC의 변경과 충돌했을 때
- 비밀정보처럼 보이는 내용이 있을 때

충돌은 자동으로 어느 쪽이 맞다고 결정하지 않습니다. 직접 내용을 확인해 해결한 뒤 다시 동기화해 주세요.

인터넷이 끊겨 push가 실패해도 이미 만든 로컬 기억 커밋은 남아 있습니다. 연결을 복구한 뒤 `persona sync`를 다시 실행하면 됩니다.

### 여러 PC에서 처음 연결하는 순서

첫 번째 PC에서는 저장소를 설치하고 기억을 동기화합니다.

```bash
persona sync
```

두 번째 PC에서는 저장소를 복제한 뒤 그 운영체제의 설치기를 실행합니다.

```bash
git clone https://github.com/noblesse3539/codex-persona-team.git
cd codex-persona-team
./scripts/install.sh
```

Windows라면 마지막 줄만 다음과 같이 바꿉니다.

```powershell
.\scripts\install.ps1
```

Git으로 함께 이동하는 것과 이동하지 않는 것은 다음과 같습니다.

| Git으로 동기화됨 | 각 PC에 따로 남음 |
|---|---|
| 페르소나 정본 | 선택한 모델 프로필과 개별 재정의 |
| 승인된 공식 기억과 철회 기록 | Codex 기본 기억 |
| 스킬과 설치 원본 | Git 로그인·SSH 키 등 자격 증명 |
| 설치기와 테스트 | 설치 백업과 로컬 상태 |

## 상태 확인과 문제 찾기

### `persona status`

현재 프로필, 세 사람의 모델과 추론 강도, 개별 재정의 여부, 저장소 위치, 현재 프로젝트 기억 ID를 보여줍니다.

```bash
persona status
```

모델 옆에 프로필 값이 아닌 재정의 표시가 있다면 `persona model set`으로 따로 지정된 값입니다. 프로젝트 또는 현재 작업 설정이 더 높은 우선순위를 갖는 경우도 있으므로 화면의 실제 모델 선택과 함께 확인하세요.

### `persona doctor`

설치 파일, 설정 형식, Codex 명령, 저장소 연결 상태를 검사합니다.

```bash
persona doctor
```

문제가 보이면 먼저 저장소에서 설치기를 다시 실행하고 새 터미널과 새 Codex 작업을 여는 것이 가장 간단합니다.

## 자주 생기는 문제

### `persona: command not found`라고 나옵니다

1. 터미널을 완전히 닫고 새로 엽니다.
2. 설치기를 한 번 더 실행합니다.
3. macOS에서는 `~/.codex/bin`, Windows에서는 `$env:USERPROFILE\.codex\bin`이 PATH에 들어 있는지 확인합니다.
4. 급할 때는 전체 경로로 실행합니다.

macOS:

```bash
~/.codex/bin/persona doctor
```

Windows:

```powershell
& "$env:USERPROFILE\.codex\bin\persona.ps1" doctor
```

### 소울이나 코어가 답하지 않습니다

- `소울아`, `코어야`, `@Soul`, `@Core`처럼 정확한 직접 호출어를 사용했는지 확인합니다.
- `persona doctor`를 실행합니다.
- 설치 뒤 열어 둔 예전 작업이라면 새 Codex 작업에서 다시 부릅니다.
- 프로젝트의 `AGENTS.md`가 전역 규칙을 재정의하는지 확인합니다.

### 모델을 바꿨는데 현재 루프의 모델이 바뀌지 않습니다

이미 열린 작업에는 자동 적용되지 않습니다. 새 작업을 열거나 Codex 화면에서 현재 작업의 모델을 직접 선택하세요.

### Luna에서 `ultra`가 거부됩니다

정상입니다. Luna에서는 `low`, `medium`, `high`, `xhigh`, `max` 중 하나를 사용하세요. `ultra`가 꼭 필요하면 Terra 또는 Sol을 선택해야 합니다.

### 프로젝트 기억을 만들 수 없습니다

Git 원격 `origin`이 없거나 Git 프로젝트가 아닐 수 있습니다. 해당 프로젝트 폴더에서 실행하세요.

```bash
persona project use my-game
```

### 동기화가 충돌 때문에 멈췄습니다

도우미는 기억을 잃지 않도록 충돌을 자동 해결하지 않습니다. `git status`로 충돌 파일을 확인하고 내용을 직접 정리한 뒤 rebase를 마치고 `persona sync`를 다시 실행하세요. 확신이 없다면 충돌 내용을 지우지 말고 도움을 요청하세요.

### 업데이트하고 싶습니다

저장소의 최신 내용을 받은 뒤 설치기를 다시 실행합니다.

```bash
git pull --rebase
./scripts/install.sh
```

Windows에서는 두 번째 명령을 다음으로 바꿉니다.

```powershell
.\scripts\install.ps1
```

## 제거하기

```bash
persona uninstall
```

제거기는 이 설치기가 관리하던 항목만 제거합니다.

- `AGENTS.md`의 Loop 팀 관리 구역
- 관리 중인 `soul.toml`, `core.toml`
- 관리 중인 `persona-council` 스킬
- 관리 중인 `persona` 실행 파일과 PATH 구역

설치 전 모델 설정이 설치 뒤 손대지 않은 상태라면 원래 값으로 복원합니다. 설치 뒤 창작자님이 직접 모델 설정을 바꿨다면 그 값을 함부로 덮어쓰지 않고 경고합니다.

다음 항목은 기본적으로 보존됩니다.

- 이 Git 저장소와 공식 기억
- 설치 백업
- GitHub 자격 증명, SSH 키, 운영체제의 자격 증명 관리자 설정

## 명령어 한눈에 보기

```text
persona profile economy|balanced|max
persona model set loop|soul|core luna|terra|sol low|medium|high|xhigh|max|ultra
persona model reset loop|soul|core
persona status
persona doctor
persona project use <slug>
persona context loop|soul|core
persona memory add --scope global|project --audience shared|loop|soul|core --summary <요약> --text <내용> --kind note|fact|decision|preference|journal|reflection --approved
persona memory retract <id> --approved
persona sync
persona uninstall
```

## 안전 약속

- 창작자님이 명시적으로 승인하기 전에는 공식 기억 파일을 만들지 않습니다.
- 비밀번호, API 키, 토큰, 개인 키 같은 비밀정보는 기억에 저장하지 않습니다.
- 설치 전 기존 설정을 백업합니다.
- 설치 실패 시 가능한 한 설치 전 상태로 자동 복구합니다.
- 회의 중에는 파일을 변경하지 않습니다.
- 여러 에이전트가 같은 파일을 동시에 쓰지 않습니다.
- 동기화 충돌을 임의로 해결하지 않습니다.
- 자동 테스트는 실제 AI 모델에 프롬프트를 보내지 않습니다.

## 개발자를 위한 자동 검사

macOS와 Linux 계열 셸에서 다음 검사를 실행할 수 있습니다.

```bash
python3 tests/validate_repository.py
bash tests/test_persona.sh
```

Windows PowerShell 검사는 다음과 같습니다.

```powershell
.\tests\Test-Persona.ps1
```

이 검사는 임시 설치 공간에서 설치·재설치·모델 설정·기억·동기화 안전장치·제거 동작을 확인합니다. AI 모델을 직접 호출하지 않으므로 모델 사용량을 소비하는 대화 테스트가 아닙니다.

## 폴더 지도

```text
codex-persona-team/
├── canon/                    # 세 페르소나의 바뀌지 않는 정본
├── memory/                   # 승인된 전역·프로젝트 기억
├── scripts/                  # macOS·Windows 설치기와 persona 명령
├── skills/persona-council/   # 호출·회의·기억 라우팅 스킬
├── templates/                # AGENTS.md와 커스텀 에이전트 원본
└── tests/                    # 모델을 호출하지 않는 자동 검사
```

정체성과 관계의 원본은 [`canon/team.md`](canon/team.md)에 있습니다. 실제 대화 라우팅의 시작점은 [`skills/persona-council/SKILL.md`](skills/persona-council/SKILL.md)입니다.

## 공식 Codex 문서

- [커스텀 에이전트와 하위 에이전트](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [AGENTS.md로 지침 설정하기](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex 설정과 우선순위](https://learn.chatgpt.com/ko-KR/docs/config-file/config-basic)
- [Codex 기억](https://learn.chatgpt.com/ko-KR/docs/customization/memories)

마지막으로 네 문장만 기억하셔도 됩니다.

```text
평소에는 루프와 이야기합니다.
재미는 소울에게 묻습니다.
현실성은 코어에게 묻습니다.
중요한 일은 셋이 회의합니다.
```
