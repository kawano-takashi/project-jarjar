# GDScript vs Python Differences

Use this reference when code intent is Python-like but the target file is Godot 4.7 GDScript.

Official sources:
- Godot 4.7 GDScript reference: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html
- Static typing in GDScript: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html
- GDScript style guide: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html
- GDScript exported properties: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_exports.html
- Godot command line tutorial: https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html
- Python built-in types: https://docs.python.org/3/library/stdtypes.html

## High-Risk Differences

| Topic | Python | GDScript 4.x |
| --- | --- | --- |
| Function declaration | `def move():` | `func move() -> void:` |
| Variable declaration | implicit assignment | `var name: Type = value` or `var name := value` |
| Constants | uppercase convention only | `const MAX_SPEED := 200.0` |
| Boolean/null literals | `True`, `False`, `None` | `true`, `false`, `null` |
| Imports | `import`, `from ... import` | no Python imports; use `preload()`, `load()`, `class_name`, autoloads, scenes, and resources |
| Exceptions | `try/except/finally/raise` | no Python exception flow; use explicit result values, `assert()` for debug checks, and error-return APIs |
| Async | `async def`, `await coroutine()` | no `async def`; use `await signal` or await a coroutine function call |
| Decorators | `@staticmethod`, `@property` | Godot annotations such as `@export`, `@onready`, `@tool`; verify annotation names |
| Signals | callbacks/decorators/libraries | `signal name(args)`, `signal_name.emit(args)`, `node.signal_name.connect(callable)` |
| Lifecycle | `__init__`, arbitrary entrypoints | `_init()`, `_enter_tree()`, `_ready()`, `_process(delta)`, `_physics_process(delta)` |

## Types And Containers

- GDScript is independent from Python even though its indentation and surface syntax are similar.
- Use typed declarations for new gameplay code: `func take_damage(amount: int) -> void:`.
- Use `Array[Type]` for typed arrays. Nested typed arrays such as `Array[Array[int]]` are not supported.
- Typed dictionaries use `Dictionary[KeyType, ValueType]`; nested typed collections are not supported.
- Built-in vector/color/transform values are value-like. `Object`, `Array`, `Dictionary`, and packed arrays are shared by reference; use `duplicate()` when a separate copy is required.
- Prefer Godot math and engine types (`Vector2`, `Vector2i`, `Rect2i`, `Color`, `NodePath`, `StringName`) instead of Python tuples or ad hoc dictionaries when the API expects engine types.

## Exports, Nodes, And Lifecycle

- Use `@export var value: Type` for Inspector-editable properties.
- Do not read Inspector-overridden exported values in `_init()`; read them after construction, commonly in `_ready()`, or use a setter where appropriate.
- Use `@onready var label: Label = $Label` for node references that depend on the scene tree.
- Cast node lookups deliberately when useful: `var timer: Timer = $Timer`.
- Prefer directly exported node/resource types when the Inspector should wire dependencies.

## Godot 3.x Snippet Caution

- Treat old `yield()` examples as suspect in Godot 4.x; use `await`.
- Treat old `setget` examples as suspect; Godot 4 uses property `set` and `get` blocks.
- Treat old signal connection examples using string method names as suspect; prefer signal objects and callables.
- Check renamed classes and methods before copying snippets from older tutorials.

## Validation Commands

Run the local guard first:

```powershell
python .codex\skills\godot-gdscript-guard\scripts\gdscript_guard.py --project .
```

When a `.gd` file changes and Godot is installed, parse it with Godot:

```powershell
godot --headless --path . --check-only --script path\to\script.gd
```
