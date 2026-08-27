#!/usr/bin/env python3
"""Detect common Python syntax drift in Godot GDScript files."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys
import tempfile


EXCLUDED_DIRS = {
    ".git",
    ".godot",
    ".codex",
    ".import",
    ".mono",
    "__pycache__",
    "bin",
    "build",
    "dist",
    "export",
    "exports",
}


@dataclass(frozen=True)
class Rule:
    rule_id: str
    pattern: re.Pattern[str]
    message: str


@dataclass(frozen=True)
class Issue:
    path: Path
    line: int
    column: int
    rule_id: str
    message: str
    excerpt: str


RULES = [
    Rule(
        "python-async-def",
        re.compile(r"\basync\s+def\b"),
        "Use GDScript 'func' with 'await'; Python 'async def' is invalid.",
    ),
    Rule(
        "python-def",
        re.compile(r"^\s*def\s+[A-Za-z_]\w*"),
        "Use 'func name(...)' instead of Python 'def'.",
    ),
    Rule(
        "python-import",
        re.compile(r"^\s*(?:from\s+\S+\s+import|import\s+\S+)"),
        "GDScript has no Python imports; use preload(), load(), class_name, scenes, or resources.",
    ),
    Rule(
        "python-none-bool",
        re.compile(r"\b(?:None|True|False)\b"),
        "Use GDScript literals 'null', 'true', and 'false'.",
    ),
    Rule(
        "python-exception-flow",
        re.compile(r"^\s*(?:try|except|finally)\b|\braise\b"),
        "GDScript does not use Python try/except/finally/raise flow.",
    ),
    Rule(
        "python-decorator",
        re.compile(
            r"^\s*@(?:staticmethod|classmethod|property|dataclass|abstractmethod|"
            r"contextmanager|lru_cache|cache|cached_property|pytest\.|mock\.|patch)\b"
        ),
        "This looks like a Python decorator; use documented Godot annotations only.",
    ),
    Rule(
        "python-init-name",
        re.compile(r"\b__init__\b"),
        "Use GDScript '_init()' instead of Python '__init__'.",
    ),
    Rule(
        "godot3-yield",
        re.compile(r"^\s*yield\s*(?:\(|$)"),
        "Godot 4 uses 'await' for signals/coroutines; old yield() snippets are suspect.",
    ),
]


def iter_gd_files(project: Path) -> list[Path]:
    files: list[Path] = []
    for path in project.rglob("*.gd"):
        if any(part in EXCLUDED_DIRS for part in path.relative_to(project).parts[:-1]):
            continue
        files.append(path)
    return sorted(files)


def strip_comments_and_strings(text: str) -> list[str]:
    stripped: list[str] = []
    quote: str | None = None
    triple = False

    for raw_line in text.splitlines():
        line = raw_line
        out: list[str] = []
        i = 0

        while i < len(line):
            if quote is not None:
                if triple and line.startswith(quote * 3, i):
                    out.extend("   ")
                    i += 3
                    quote = None
                    triple = False
                    continue
                if not triple and line[i] == "\\":
                    out.append(" ")
                    if i + 1 < len(line):
                        out.append(" ")
                        i += 2
                    else:
                        i += 1
                    continue
                if not triple and line[i] == quote:
                    out.append(" ")
                    i += 1
                    quote = None
                    continue
                out.append(" ")
                i += 1
                continue

            if line[i] == "#":
                out.extend(" " * (len(line) - i))
                break

            if line.startswith('"""', i) or line.startswith("'''", i):
                quote = line[i]
                triple = True
                out.extend("   ")
                i += 3
                continue

            if line[i] in {'"', "'"}:
                quote = line[i]
                triple = False
                out.append(" ")
                i += 1
                continue

            out.append(line[i])
            i += 1

        stripped.append("".join(out))

    return stripped


def scan_file(path: Path) -> list[Issue]:
    text = path.read_text(encoding="utf-8")
    raw_lines = text.splitlines()
    clean_lines = strip_comments_and_strings(text)
    issues: list[Issue] = []

    for line_number, clean_line in enumerate(clean_lines, start=1):
        for rule in RULES:
            for match in rule.pattern.finditer(clean_line):
                excerpt = raw_lines[line_number - 1].strip()
                issues.append(
                    Issue(
                        path=path,
                        line=line_number,
                        column=match.start() + 1,
                        rule_id=rule.rule_id,
                        message=rule.message,
                        excerpt=excerpt,
                    )
                )
    return issues


def scan_project(project: Path) -> tuple[list[Path], list[Issue]]:
    files = iter_gd_files(project)
    issues: list[Issue] = []
    for path in files:
        issues.extend(scan_file(path))
    return files, issues


def format_issue(issue: Issue, root: Path) -> str:
    try:
        display_path = issue.path.relative_to(root)
    except ValueError:
        display_path = issue.path
    return (
        f"{display_path}:{issue.line}:{issue.column}: "
        f"{issue.rule_id}: {issue.message}\n"
        f"    {issue.excerpt}"
    )


def run_self_test() -> int:
    good = """extends Node

@export var speed: float = 4.0
@onready var label: Label = $Label
signal moved(position: Vector2)

func _ready() -> void:
\tvar values: Array[int] = [1, 2, 3]
\tif true:
\t\tmoved.emit(Vector2.ZERO)
"""

    bad = """extends Node

def _ready():
\tprint(True)

try:
\timport os
except Exception:
\traise

@staticmethod
async def load_data():
\treturn None

func old_wait() -> void:
\tyield($Timer, "timeout")
"""

    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        (root / "good.gd").write_text(good, encoding="utf-8")
        (root / "bad.gd").write_text(bad, encoding="utf-8")

        good_issues = scan_file(root / "good.gd")
        bad_issues = scan_file(root / "bad.gd")

    expected = {
        "python-def",
        "python-none-bool",
        "python-exception-flow",
        "python-import",
        "python-decorator",
        "python-async-def",
        "godot3-yield",
    }
    found = {issue.rule_id for issue in bad_issues}

    if good_issues:
        print("Self-test failed: valid GDScript sample produced issues.", file=sys.stderr)
        for issue in good_issues:
            print(f"- {issue.rule_id}: {issue.excerpt}", file=sys.stderr)
        return 1

    missing = expected - found
    if missing:
        print(f"Self-test failed: missing expected rules: {sorted(missing)}", file=sys.stderr)
        return 1

    print("Self-test passed.")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect Python-style syntax drift in Godot GDScript files."
    )
    parser.add_argument(
        "--project",
        default=".",
        help="Godot project root to scan. Defaults to the current directory.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run built-in tests for the guard rules.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        return run_self_test()

    project = Path(args.project).resolve()
    if not project.exists():
        print(f"Project path does not exist: {project}", file=sys.stderr)
        return 2
    if not project.is_dir():
        print(f"Project path is not a directory: {project}", file=sys.stderr)
        return 2

    files, issues = scan_project(project)
    if not files:
        print(f"No .gd files found under {project}.")
        return 0

    if issues:
        print(f"Found {len(issues)} possible Python-to-GDScript drift issue(s):")
        for issue in issues:
            print(format_issue(issue, project))
        return 1

    print(f"Scanned {len(files)} .gd file(s); no Python syntax drift found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
