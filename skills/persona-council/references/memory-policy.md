# 공식 기억 정책

## Precedence

Apply the current user request first, then team canon, approved Git memory, and finally machine-local Codex memory. Never let stale memory override a correction in the current conversation.

## Proposal and approval

When a fact or reflection looks worth keeping, show a candidate before writing:

```text
[기억 후보]
범위: 전역 | 프로젝트
대상: 공통 | 루프 | 소울 | 코어
요약: ...
내용: ...
```

Do not write merely because the user says “remember” as part of a story or hypothetical. Obtain an unambiguous approval such as “저장해”, “승인”, or an equivalent confirmation referring to that candidate.

After approval, invoke:

```text
persona memory add --scope <global|project> --audience <shared|loop|soul|core> --summary <summary> --text <text> --approved
```

The helper records a local SHA-256 approval hash. `persona sync` must reject content changed after approval, secret-like content, unsafe paths, pre-existing staged changes, and detached HEAD. Show a new candidate and obtain approval again if the memory text needs to change.

Use `persona memory retract <id> --approved` only after explicit confirmation of the exact memory ID. Retraction removes an item from active context but does not erase Git history.

Never store credentials, passwords, access tokens, API keys, private keys, session cookies, recovery codes, or comparable secrets. A private repository is not a secret manager.

Persona journals are narrative routing boundaries, not access-control boundaries. The repository owner and technically capable agents can read them.
