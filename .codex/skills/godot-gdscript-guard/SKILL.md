---
name: godot-gdscript-guard
description: Guard Godot 4.7 GDScript work against Python syntax drift and hallucinated APIs. Use when Codex edits, creates, reviews, or explains Godot/GDScript/GDスクリプト files, compares GDScript and Python, prevents hallucinations, validates .gd code, or works in this repository's Godot game project.
---

# Godot GDScript Guard

## Core Rule

Treat GDScript as a Godot-specific language, not as Python with engine APIs. Before writing or changing `.gd`, `.tscn`, or `.tres` behavior, ground the answer in the current project and Godot 4.7 documentation.

## Workflow

1. Inspect local context first: read `project.godot`, then search relevant `.gd`, `.tscn`, and `.tres` files with `rg --files`.
2. Match the project's Godot version. This repository targets Godot 4.7; prefer the 4.7 official docs and Class reference unless local project files prove otherwise.
3. If syntax, lifecycle, node APIs, signals, annotations, resources, or typed containers are uncertain, verify against official Godot docs before implementing.
4. Read `references/gdscript_python_differences.md` when translating Python-like intent into GDScript or when reviewing code that "looks Pythonic".
5. Implement with GDScript idioms: `func`, `var`, `const`, `true`, `false`, `null`, `@export`, `@onready`, `signal`, `.emit()`, `await`, `_ready()`, `_process(delta)`, and `_physics_process(delta)`.
6. Validate after edits:
   - Run `python .codex\skills\godot-gdscript-guard\scripts\gdscript_guard.py --project .`.
   - For each touched `.gd` file, run `godot --headless --path . --check-only --script <script>` when the local Godot binary is available.
   - Report any validation that could not be run and why.

## Anti-Hallucination Checks

- Do not use Python keywords or constants in GDScript: `def`, `import`, `from`, `None`, `True`, `False`, `try`, `except`, `finally`, `raise`, `async def`.
- Do not invent Python decorators. GDScript annotations start with `@`, but they must be Godot annotations such as `@export`, `@onready`, `@tool`, or documented variants.
- Do not use Godot 3.x snippets blindly. For Godot 4.x, prefer `await` over old `yield()` patterns and use current signal connection syntax.
- Do not claim an API exists from memory when the exact class, method, signal, enum, or annotation matters. Verify the versioned docs or local Class reference.
- Prefer typed GDScript for new gameplay code unless existing files clearly use a dynamic style.

## Resources

- `references/gdscript_python_differences.md`: concise GDScript-vs-Python differences and source links.
- `scripts/gdscript_guard.py`: scans `.gd` files for common Python syntax drift.

Use the guard script as a fast first pass. It is not a compiler and does not replace Godot's parser or runtime tests.
