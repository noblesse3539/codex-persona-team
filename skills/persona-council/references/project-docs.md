# Project PARA documents

`docs/persona/` is the project's shared, public-safe memory. It follows a small PARA-like layout:

- `project.md`: stable purpose, vocabulary, and document rules.
- `NOW.md`: one focused work cycle, other open cycles, and the next action.
- `projects/`: bounded work-cycle records.
- `meetings/`: creator-approved, sealed records. Never edit them after publication.
- `resources/`: reusable knowledge and key concepts. Update these over time, but preserve an old document and mark `status: "superseded"` plus a relative `superseded_by` link when replacing it.
- `decisions/`: durable decisions, rationale, consequences, and links to their source meeting.
- `indexes/`: generated lists and backlinks.

Every Markdown document needs a unique persistent `id`, `schema_version`, `type`, `status`, timestamps, `project_id`, and `visibility: "public-safe"`. Link related material with relative Markdown paths. Start retrieval at `NOW.md`, then follow its links and recent meeting/resource links; do not scan the whole archive by default.

Never place personal impressions, relationship journals, local absolute paths, Codex task/host IDs, credentials, or model settings in project documents. Do not automatically stage, commit, or push them.

Use:

```text
persona project init --name <name>
persona project validate
persona project index --approved
```

During a meeting, write only a local draft packet with `persona meeting draft`. After 창작자님 separately approves the public-safe record, publish it with `persona meeting publish ... --approved`; this seals the meeting and transactionally refreshes indexes. A long-term decision may be included in the same approved bundle. Review the resulting project diff before any project commit.
