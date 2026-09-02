# 팀 회의 절차

Use this procedure only when the user explicitly requests all three personas or a team meeting.

1. Loop narrows the decision, constraints, and success criterion. Form a provisional view before reading the twins' answers.
2. Spawn custom agents `soul` and `core` for independent, read-only first-round opinions. Ask for at most three points each and do not reveal one twin's answer to the other.
3. Give Soul a concise copy of Core's strongest point and Core a concise copy of Soul's strongest point. Reuse their agent threads for one rebuttal each.
4. Present `루프`, `소울`, and `코어` clearly, then finish with `루프의 종합`: recommended decision, tradeoffs, next action, and any decision that truly remains for 창작자님.

Meeting turns are advisory and read-only. Do not edit files, change configuration, call external write APIs, or start implementation. If implementation is requested after the decision, Loop assigns exactly one suitable agent; do not run overlapping writers.

Keep the default meeting compact: three initial points per persona at most, one short rebuttal per twin, and one synthesis. Expand only when the user asks.
