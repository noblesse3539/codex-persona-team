#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def validate_macos_only_layout() -> None:
    required = [
        "README.md",
        "canon/team.md",
        "canon/loop.md",
        "canon/soul.md",
        "canon/core.md",
        "templates/AGENTS.block.md",
        "scripts/install.sh",
        "scripts/persona.sh",
        "tests/test_persona.sh",
        ".github/workflows/ci.yml",
    ]
    missing = [path for path in required if not (ROOT / path).is_file()]
    if missing:
        fail(f"required files are missing: {missing}")

    powershell_files = sorted(path.relative_to(ROOT) for path in ROOT.rglob("*.ps1"))
    if powershell_files:
        fail(f"macOS-only v2 still contains PowerShell files: {powershell_files}")
    if (ROOT / "memory").exists():
        fail("the Persona source repository must not contain a runtime memory directory")

    workflow = read(".github/workflows/ci.yml")
    if "runs-on: macos-latest" not in workflow:
        fail("CI must run on macos-latest")
    if re.search(r"windows-latest|pwsh|powershell", workflow, re.IGNORECASE):
        fail("CI still contains a non-macOS job")

    readme = read("README.md")
    if re.search(r"Windows|PowerShell|install\.ps1|persona\.ps1", readme, re.IGNORECASE):
        fail("README still contains removed platform instructions")
    for phrase in [
        "macOS 전용",
        "~/.codex/persona-team/",
        "docs/persona/",
        "persona update",
        "DELETE-PERSONA-DATA",
        "persona sync",
    ]:
        if phrase not in readme:
            fail(f"README is missing required v2 guidance: {phrase}")


def validate_agent_templates() -> None:
    paths = sorted((ROOT / "templates" / "agents").glob("*.toml.in"))
    if {path.name for path in paths} != {"soul.toml.in", "core.toml.in"}:
        fail("custom-agent template set is incomplete")
    for path in paths:
        rendered = path.read_text(encoding="utf-8")
        rendered = rendered.replace("@@MODEL@@", "gpt-5.6-luna").replace("@@EFFORT@@", "max")
        try:
            data = tomllib.loads(rendered)
        except tomllib.TOMLDecodeError as exc:
            fail(f"invalid rendered TOML in {path}: {exc}")
        required = {"name", "description", "developer_instructions", "model", "model_reasoning_effort"}
        missing = required - data.keys()
        if missing:
            fail(f"{path} is missing keys: {sorted(missing)}")
        if data["name"] not in {"soul", "core"}:
            fail(f"unexpected custom agent name in {path}: {data['name']}")
        if "persona context" not in data["developer_instructions"]:
            fail(f"{path} does not load Persona context")
        if "writer lock" not in data["developer_instructions"]:
            fail(f"{path} does not enforce the single-writer rule")


def validate_skill() -> None:
    skill_dir = ROOT / "skills" / "persona-council"
    path = skill_dir / "SKILL.md"
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not match:
        fail("persona-council SKILL.md has invalid frontmatter delimiters")
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            fail(f"unsupported frontmatter line: {line}")
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    if set(fields) != {"name", "description"}:
        fail(f"unexpected skill frontmatter fields: {sorted(fields)}")
    if fields["name"] != "persona-council":
        fail("skill name must be persona-council")
    if not fields["description"] or len(fields["description"]) > 1024:
        fail("skill description is empty or too long")
    if re.search(r"^\s*\[TODO:.*\]\s*$", text, re.MULTILINE):
        fail("skill contains an unfinished TODO")
    if not (skill_dir / ".persona-team-managed").is_file():
        fail("managed skill marker is missing")

    links = re.findall(r"\[[^]]+\]\((references/[^)]+)\)", text)
    if not links:
        fail("SKILL.md does not route to any reference files")
    for link in links:
        if not (skill_dir / link).is_file():
            fail(f"SKILL.md has a broken reference: {link}")
    required_references = {
        "persistent-team.md",
        "project-docs.md",
        "meeting-protocol.md",
        "memory-policy.md",
        "runtime-paths.md",
        "team-canon.md",
    }
    actual_references = {path.name for path in (skill_dir / "references").glob("*.md")}
    if not required_references <= actual_references:
        fail(f"skill references are incomplete: {sorted(required_references - actual_references)}")


def validate_project_templates() -> None:
    template_dir = ROOT / "templates" / "project-docs"
    required = {"project.md.in", "NOW.md.in", "index.md.in", "README.md"}
    actual = {path.name for path in template_dir.iterdir() if path.is_file()}
    if not required <= actual:
        fail(f"project templates are incomplete: {sorted(required - actual)}")
    replacements = {
        "@@PROJECT_ID@@": "project-00000000-0000-0000-0000-000000000000",
        "@@NOW_ID@@": "now-00000000-0000-0000-0000-000000000000",
        "@@CREATED_AT@@": "20260906T000000Z",
        "@@PROJECT_NAME@@": "Example",
        "@@PROJECT_NAME_YAML@@": "Example",
        "@@INDEX_ID@@": "index-00000000-0000-0000-0000-000000000000",
        "@@INDEX_TITLE@@": "Example index",
    }
    for path in template_dir.glob("*.in"):
        rendered = path.read_text(encoding="utf-8")
        for source, target in replacements.items():
            rendered = rendered.replace(source, target)
        if "@@" in rendered:
            fail(f"unresolved template placeholder in {path}")
        if not rendered.startswith("---\n") or "\nid: \"" not in rendered:
            fail(f"invalid project document frontmatter in {path}")

    local_example = ROOT / "templates" / "local-memory" / "entry.md.example"
    if not local_example.is_file():
        fail("anonymous local-memory schema example is missing")
    example_text = local_example.read_text(encoding="utf-8")
    for field in ["scope: \"global-local\"", "audience:", "approved_by:", "evidence:"]:
        if field not in example_text:
            fail(f"local-memory schema example is missing: {field}")


def validate_model_table_without_calling_models() -> None:
    script = read("scripts/persona.sh")
    expected_fragments = [
        "economy:loop:model|economy:soul:model|economy:core:model",
        "balanced:loop:model",
        "balanced:soul:model|balanced:core:model",
        "max:loop:model|max:soul:model|max:core:model",
        '"gpt-5.6-luna"',
        '"gpt-5.6-terra"',
        '"gpt-5.6-sol"',
        "Luna는 ultra를 지원하지 않습니다",
    ]
    for fragment in expected_fragments:
        if fragment not in script:
            fail(f"model configuration is missing: {fragment}")

    integration_test = read("tests/test_persona.sh")
    forbidden_calls = [
        r"persona profile max",
        r"run_persona profile max",
        r"model set (loop|soul|core) sol ",
        r"gpt-5\.6-sol.*--",
    ]
    for pattern in forbidden_calls:
        if re.search(pattern, integration_test):
            fail(f"tests must not invoke Sol/max: {pattern}")


def validate_v2_workflows() -> None:
    script = read("scripts/persona.sh")
    meeting = read("skills/persona-council/references/meeting-protocol.md")
    required_script_phrases = [
        "Persona Team v2는 macOS",
        "persona sync는 v2에서 폐지",
        "git -C \"$repo\" pull --ff-only",
        "DELETE-PERSONA-DATA",
        "protected_local_hash",
        "sealed_sha256",
        "writer recover --approved",
    ]
    for phrase in required_script_phrases:
        if phrase not in script:
            fail(f"v2 workflow implementation is missing: {phrase}")

    update_body = script.split("command_update() {", 1)[1].split("find_project_override() {", 1)[0]
    if re.search(r"git -C \"\$repo\" (add|commit|push)", update_body):
        fail("persona update must not add, commit, or push")

    persistent = read("skills/persona-council/references/persistent-team.md")
    for phrase in ["up to 20 turns", "creator messages and final AI answers only", "compacted", "exact task IDs"]:
        if phrase not in persistent:
            fail(f"persistent handoff protocol is missing: {phrase}")
    meeting = read("skills/persona-council/references/meeting-protocol.md")
    for phrase in ["identical packet", "five model turns", "exactly one rebuttal", "read-only"]:
        if phrase not in meeting:
            fail(f"meeting protocol is missing: {phrase}")


if __name__ == "__main__":
    validate_macos_only_layout()
    validate_agent_templates()
    validate_skill()
    validate_project_templates()
    validate_model_table_without_calling_models()
    validate_v2_workflows()
    print("Repository templates and macOS-only boundaries are valid.")
