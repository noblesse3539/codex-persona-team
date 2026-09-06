# Persistent project team

## Create the team only on request

Create three tasks only when 창작자님 explicitly asks `이 프로젝트에 팀 만들어줘` or clearly approves the same action. Task creation is an external state change; never infer it from a normal Soul/Core call.

1. Confirm this is a saved local Codex project and run `persona project init --name <project-name>` from its checkout.
2. Read `persona status` and record the effective model and effort for each persona. Never test-call a model merely to verify configuration.
3. Identify the current task exactly. If the task API does not expose its ID directly, give it a unique temporary UUID title, list tasks, and require exactly one match on the same host and project. Abort on zero or multiple matches. Save the exact returned ID immediately; never select by recency or a similar title.
4. Rename and bind the current task as `<project-name> · 루프` with `persona team bind loop <thread-id> <host-id>`.
5. Inspect saved projects before creating tasks. Use the same saved-project checkout so all three see one `docs/persona/` tree; its writer lock prevents overlapping writes.
6. Create only missing `<project-name> · 소울` and `<project-name> · 코어` tasks. Their opening prompt must state the persona, require `persona context <persona>`, require reading `project.md`, `NOW.md`, and linked relevant documents, prohibit meeting writes, and prohibit implementation without explicit assignment.
7. Bind only IDs returned by task APIs. If setup returns a pending client ID, wait for the real task ID before binding.
8. Run `persona team status` and report all three exact bindings. Task IDs stay in local state and never enter project documents.

If any identity check is ambiguous, stop team setup without guessing.

## Direct calls and modes

Read exact task IDs from `persona team status`.

- Name only (`소울아`, `코어야`, `@Soul`, `@Core`): navigate to that bound task. Sending a message would spend a model turn, so do not send one.
- Name plus a question: send only a short current-context note and the exact question to the bound task, using that persona's local model setting, then navigate there.
- `소울 모드`, `코어 모드`, `루프 모드`, or `모드 종료`: navigate to the corresponding bound task. The persistent task itself supplies continuity.
- If this is a project but no team is bound, do not create a one-off agent. Ask whether to create the project team.
- In a projectless conversation or a CLI/IDE surface without task controls, use the installed one-off custom agent and keep mode only in the current task.

## Loop's incremental handoff review

At the beginning of each activity in a connected Loop task, inspect cheap task metadata first. Do not message or wake Soul/Core merely to check them.

For each changed bound task:

1. Read only content after the saved cursor, up to 20 turns.
2. Use creator messages and final AI answers only. Exclude tool output, progress commentary, hidden reasoning, and generated logs.
3. Loop—not Soul/Core tags—judges meaningful decisions, changes, preferences, and unresolved items.
4. Save each useful candidate atomically with `persona handoff add`; only then move the cursor with `persona team cursor set`.
5. Do not automatically publish a candidate to `docs/persona/` or global memory.

If task history is compacted, truncated, or lacks the saved checkpoint, ask that task for one short handoff summary. Until it arrives, pause only the related meeting finalization, document publication, or work-cycle closure. Other Loop conversation may continue.

## Single writer

Before implementation in a shared checkout, run `persona writer acquire <persona> <scope> <thread-id>`. Release it after verification with `persona writer release <persona>`, including after a handled failure. A different owner must not write concurrently. An expired lock may be removed only after inspection and creator approval with `persona writer recover --approved`.
