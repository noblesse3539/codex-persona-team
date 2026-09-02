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


def validate_agent_templates() -> None:
    for path in sorted((ROOT / "templates" / "agents").glob("*.toml.in")):
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


def validate_skill() -> None:
    path = ROOT / "skills" / "persona-council" / "SKILL.md"
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


def validate_layout() -> None:
    required = [
        ROOT / "canon" / "team.md",
        ROOT / "canon" / "loop.md",
        ROOT / "canon" / "soul.md",
        ROOT / "canon" / "core.md",
        ROOT / "templates" / "AGENTS.block.md",
        ROOT / "scripts" / "persona.sh",
        ROOT / "scripts" / "persona.ps1",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if missing:
        fail(f"required files are missing: {missing}")


if __name__ == "__main__":
    validate_layout()
    validate_agent_templates()
    validate_skill()
    print("Repository templates are valid.")
