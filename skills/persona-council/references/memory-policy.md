# Local persona memory policy

## Boundaries and precedence

Interpret context in this order: current request, versioned team canon, current project's `docs/persona/`, approved local Persona memory, then Codex's own local memory. A current correction always wins.

- Team identity and speech relationships belong in the Persona Git repository.
- Project meetings, decisions, resources, and work cycles belong in that project's `docs/persona/`.
- Creator preferences, relationship observations, and cross-project capsules belong only in `~/.codex/persona-team/private/` on this Mac.
- Codex's `~/.codex/memories/` is a separate system and is never changed or removed by Persona commands.

Do not use `persona memory --scope project`; point to the project documents instead. There is no memory sync, export, import, or remote backup in v2.

## Candidate and approval

Before a shared preference, fact, decision, or capsule is stored, show:

```text
[로컬 기억 후보]
범위: 이 Mac의 전역 Persona 기억
대상: 공통 | 루프 | 소울 | 코어
종류: ...
요약: ...
내용: ...
근거: 직접 확인 | 서로 다른 반복 사건 2개
```

Use `persona memory add --scope global ... --approved` only after unambiguous creator approval. One observation must not silently change default behavior. A common-profile preference needs direct confirmation or two distinct supporting incidents; the candidate must name that evidence.

Persona-specific relationship journals/reflections may use the creator's standing consent with `--standing-consent`; they remain local and must not be promoted to the shared profile without approval. Journals are routing boundaries, not security boundaries.

If 창작자님 says `기록하지 마`, immediately exclude that topic from new memory, handoff candidates, and meeting drafts. Remove matching unapproved local candidates/drafts. An already approved memory is excluded with `persona memory retract <id> --approved` after confirming the exact ID.

Never store credentials, API/access tokens, passwords, private keys, session cookies, recovery codes, sensitive-trait inferences, or comparable secrets. Local-only storage is not a secret manager.

`persona uninstall` permanently deletes Persona's local memory after its exact confirmation phrase. It does not delete project documents, source code, Codex memory, or existing tasks.
