# Team meeting protocol

Use this only for an explicit three-person meeting.

## Preflight

1. Validate `docs/persona/`, all three exact task bindings, installed version, pending history gaps, and writer-lock state. A meeting never acquires a writer lock.
2. Show Soul, Core, and Loop's configured model, reasoning effort, and the five-turn specialist cap. Ask 창작자님 to confirm Loop's current UI model because local config cannot override an already-open task.
3. Loop forms a provisional view and makes one common packet from the current conversation, `project.md`, `NOW.md`, and only linked relevant documents. Store it locally with `persona meeting draft`; do not modify project files.

## Discussion

1. Send the identical packet to the bound Soul and Core tasks. Ask for independent first-round views with at most three points each.
2. Use no more than five model turns per specialist for the entire meeting.
3. Research only when an external fact materially affects the decision, with at most three high-quality sources per specialist.
4. Give each twin one concise copy of the other's strongest point and request exactly one rebuttal.
5. Loop presents labeled views, one synthesis, one concrete recommendation, tradeoffs, and the next action, then asks for 창작자님's decision.

The meeting is advisory and read-only: no project/configuration edits, external writes, implementation, commits, or pushes. A paused meeting remains only in local pending storage.

After explicit approval of the record, Loop may publish the sanitized meeting bundle to project documents. Approval to record a meeting is not approval to implement it. Implementation starts only after a separate explicit request and is assigned to one writer.
