# Godot 4.7: GDScript and core types

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: writing or reviewing any `.gd` file; building a cache, a copy or a snapshot of game state; choosing between Array, typed Array, packed array and Dictionary; typing a new class; adding randomness to the simulation; parsing text or binary data; silencing or turning on a GDScript warning.

Companion pages: `main-loop.md` (node lifecycle, tick order, files, threads, headless runs), `engine.md` (Object/Variant cost, GDExtension), `math.md` (vectors, transforms, float precision in 3D).

## Rules for this project

- Treat every `Array`, `Dictionary`, packed array (`PackedVector3Array` and the rest) and Object as **shared by reference**. Only `null`, `bool`, `int`, `float`, `String`, `StringName`, `NodePath`, the vector/matrix types, `Color`, `RID`, `Callable` and `Signal` are copied on assignment. A cache hands back `x.duplicate()` (or `duplicate(true)` when it holds nested arrays/dictionaries), never `x` (`tutorials/scripting/gdscript/gdscript_basics.rst`, "Built-in types").
- `duplicate()` is shallow by default: nested Array, Dictionary and **Resource** values stay shared. `duplicate(true)` copies nested arrays and dictionaries but **still shares Resources**; use `duplicate_deep(Resource.DEEP_DUPLICATE_ALL)` to copy those too (`classes/class_array.rst`, `class_dictionary.rst`).
- `Resource.duplicate()` copies only exported / `PROPERTY_USAGE_STORAGE` properties. A plain `var` (such as a lazily solved cache field) comes back at its default in the copy. Mark state that must survive a copy `@export_storage` (`classes/class_resource.rst`, `gdscript_exports.rst`).
- A packed array **returned by an engine property or method is already a copy** (writing to it changes nothing until you assign it back); one held in a GDScript variable is shared (`classes/class_packedvector3array.rst`).
- Type everything: `var x: T`, `:=`, `-> T`, `Array[T]`, `Dictionary[K, V]`, `for x: T in`. Typed code compiles to optimized opcodes when operand types are known (`static_typing.rst`). Use the typed global functions (`absf`, `clampf`, `clampi`, `lerpf`, `roundi`, `floori`, `signf`, `snappedf`...) instead of the Variant ones (`abs`, `clamp`, `lerp`...), which return Variant.
- `int / int` is integer division (`5 / 2 == 2`). Write `float(a) / b` or `a / 2.0`. The `integer_division` warning is on (Warn) by default; where truncation is intended, silence it with `@warning_ignore("integer_division")` on that line, as `tests/run_sim_checks.gd` does.
- GDScript `float` is 64-bit, but `Vector3`, `Transform3D`, `Basis`, `PackedFloat32Array` and most engine properties are 32-bit floats (6 reliable digits). Keep simulation time in `int` microseconds (as `SimClock` does), never as accumulated float seconds.
- Randomness that decides the game comes from a `RandomNumberGenerator` whose `seed` is set from tick/usec/userid data, never from the global `randf()`/`randi()`/`Array.shuffle()`/`pick_random()`, which share one global seed that `randomize()` sets from the clock at startup (`classes/class_@globalscope.rst`).
- Never override a non-virtual engine method (`get_class`, `queue_free`, `free`...): `NATIVE_METHOD_OVERRIDE` is an error by default and the engine would not call yours anyway. Only `_`-prefixed virtuals are overridable (`gdscript_basics.rst`, "Inheritance").
- Do not test a freed Object against `null`: use `is_instance_valid(obj)`. A variable holding a freed non-RefCounted Object is not nulled for you (`classes/class_object.rst`).
- Prefer `RefCounted` (the default when a script has no `extends`) for game data; plain `Object` must be `free()`d by hand (`classes/class_refcounted.rst`).

## Value and reference semantics (the whole table)

Source: `tutorials/scripting/gdscript/gdscript_basics.rst` "Built-in types", `gdscript_advanced.rst` "Pointers & referencing", the class pages.

| Type | Passed as | Copy with | Notes |
|---|---|---|---|
| `int`, `float`, `bool` | value | assignment | `int` is signed 64-bit and wraps on overflow; `float` is a C++ `double` |
| `Vector2/3/4(i)`, `Basis`, `Transform3D`, `Quaternion`, `AABB`, `Plane`, `Color`, `Rect2` | value | assignment | 32-bit float components unless the engine was built `precision=double` |
| `String` | value (copy-on-write, refcounted internally) | assignment | every modification returns a new String; passing is cheap |
| `StringName`, `NodePath` | value | assignment | immutable |
| `RID`, `Callable`, `Signal` | value | assignment | a Callable/Signal still points at its Object |
| `Array`, `Array[T]` | **reference** | `duplicate(deep := false)`, `duplicate_deep(mode)`, `assign()` into another array, `Array(from)` constructor | `const` arrays are read-only |
| `Dictionary`, `Dictionary[K, V]` | **reference** | `duplicate(deep)`, `duplicate_deep(mode)`, `assign()` | keeps insertion order |
| `PackedByteArray`, `PackedInt32/64Array`, `PackedFloat32/64Array`, `PackedStringArray`, `PackedVector2/3/4Array`, `PackedColorArray` | **reference** in GDScript; **copy** when returned by an engine property/method | `duplicate()` (no `deep` parameter) | exported packed arrays must default to empty |
| Object, Node, Resource, RefCounted | **reference** | `Node.duplicate(flags)`, `Resource.duplicate(deep)` / `duplicate_deep(mode)` | Resources from `load()` are one shared instance per path |

Details that bite:

- Shallow `Array.duplicate()`: "all nested Array, Dictionary, and Resource elements are shared with the original array". `deep = true`: nested arrays and dictionaries copied recursively, "Any Resource is still shared" (`classes/class_array.rst`). Same wording for Dictionary.
- `duplicate_deep(deep_subresources_mode: int = 1)` on Array/Dictionary/Resource takes `Resource.DeepDuplicateMode`: `DEEP_DUPLICATE_NONE` (0, arrays/dicts copied, resources shared), `DEEP_DUPLICATE_INTERNAL` (1, default: only resources with no path or a scene-local path copied), `DEEP_DUPLICATE_ALL` (2, every resource, even ones saved in their own file) (`classes/class_resource.rst`).
- `Resource.duplicate(deep := false)`: shallow shares nested Array, Dictionary and Resource properties; deep copies nested arrays, dictionaries **and packed arrays**, and Resources only if local (like `DEEP_DUPLICATE_INTERNAL`). Properties flagged `PROPERTY_USAGE_ALWAYS_DUPLICATE` / `PROPERTY_USAGE_NEVER_DUPLICATE` override that. It fails for a custom Resource whose `_init()` has required parameters (`classes/class_resource.rst`).
- `Node.duplicate(flags := 15)` copies only properties marked for storage (exported) unless you add `DUPLICATE_INTERNAL_STATE` (16) (`classes/class_node.rst`). `@export_storage` makes a property copied by both `Resource.duplicate()` and `Node.duplicate()` without showing it in the Inspector (`gdscript_exports.rst`).
- `Array.assign(other)` copies contents (with type conversion into a typed array); `=` copies the reference. You cannot assign an `Array[Node2D]` to an `Array[Node]` variable; use `b.assign(a)` (`gdscript_basics.rst`, "Typed arrays").
- `make_read_only()` (Array, Dictionary) is shallow: nested containers stay writable. Arrays and dictionaries declared `const` are read-only automatically (`classes/class_array.rst`, `class_dictionary.rst`).
- Lambdas capture locals **by value, once, at creation**; reassigning the outer variable later is not seen, and assigning to it inside the lambda only shadows it (`CONFUSABLE_CAPTURE_REASSIGNMENT`). But a captured Array/Dictionary/Object is the same instance, so `append()` inside the lambda is visible outside (`gdscript_basics.rst`, "Lambda functions").
- A `for` loop variable is a copy for value types: `for s in strings: s = "x"` changes nothing; use `for i in arr.size(): arr[i] = ...`. Erasing or adding elements while iterating an Array or Dictionary is **not supported** ("unpredictable behavior"); iterate `dict.keys()` if you must erase (`gdscript_basics.rst`, `class_array.rst`, `class_dictionary.rst`).
- Non-static member initializers run per instance, including `var a := []` and `var d := {}`: every instance gets its own container (unlike Python class attributes) (`gdscript_basics.rst`, "Registering named classes" note). `static var` is one value per class, shared by all instances and subclasses.
- Equality: `Array == Array` compares size and contents; `Dictionary == Dictionary` compares keys and values and ignores order; `is_same(a, b)` compares identity for reference types and value for value types. `==` between some mismatched types raises a runtime error; `match` is stricter than `==` (`1` does not match `1.0`; `String` and `StringName` do match) (`gdscript_basics.rst`, `class_@globalscope.rst`).
- `Dictionary.hash()` differs for the same entries in a different order; equal hashes do not mean equal contents (`classes/class_dictionary.rst`).

## Numbers

Source: `classes/class_int.rst`, `class_float.rst`, `class_vector3.rst`, `gdscript_basics.rst` "Operators".

- `int`: signed 64-bit, range -2^63..2^63-1, wraps on overflow. Literals `0x8f`, `0b1010`, `1_000_000`.
- `float`: 64-bit, 14 reliable decimal digits. Engine 32-bit floats have 6. `Vector3`/`Vector2` store 32-bit components "unlike float which is always 64-bit"; double needs an engine compiled with `precision=double` (`class_vector3.rst`). So `var v := Vector3(x, 0, 0)` rounds `x` to float32. (Computed: at 4096 units from the origin one float32 step is about 0.0005 units.)
- `/` with two ints is integer division (C++ semantics, so it truncates toward zero). `%` works on ints only; use `fmod()` for floats. `%` and `fmod()` keep the sign of the dividend; `posmod()`/`fposmod()` give the mathematical modulus.
- float to int conversion truncates (`var x: int = 4.2` gives 4). Passing a float where an int parameter is typed raises `NARROWING_CONVERSION` (Warn by default).
- `**` is left-associative: `2 ** 2 ** 3 == (2 ** 2) ** 3`.
- Compare floats with `is_equal_approx()` / `is_zero_approx()`, not `==`.
- In a boolean context, `0`, `0.0`, `""`, empty Array/Dictionary/packed array, `Vector3.ZERO`, an empty StringName, an invalid RID, a null Callable and a null or **freed** Object are all false.

## Static typing and what it buys

Source: `tutorials/scripting/gdscript/static_typing.rst`.

- "Typed GDScript improves performance by using optimized opcodes when operand/argument types are known at compile time." There is no JIT/AOT (listed as planned).
- Type hints can be: `Variant`, `void` (return only), built-in types, native classes, `class_name` classes, inner classes, global/native/custom enums (an enum type is just `int`, nothing checks the value is in range), and constants holding a preloaded script or enum (`const Rifle = preload("res://rifle.gd")`).
- `:=` infers the type; inference from a Variant value is an error by default (`inference_on_variant` = Error), e.g. `var x := dict["k"]` fails; write `var x: int = dict["k"]`.
- Overrides may narrow the return type (covariance) and widen parameter types (contravariance).
- **4.7:** a method overriding one with a typed return now inherits that return type, so the override needs an explicit `return` on every path; add `return null` where needed (`tutorials/migrating/upgrading_to_godot_4.7.rst`).
- Typed Array: `Array[int]`, `Array[Node]`, `Array[MyClass]`, `Array[MyEnum]`. Writes are checked at runtime. Nested typed arrays (`Array[Array[int]]`) are not supported; `Array[Array]` is. `Array` is `Array[Variant]`. Methods such as `front()`, `back()`, `pop_back()`, `push_back()` stay untyped (Variant) even on a typed array; only `for`, `[]`, `[] =` and `+` use the element type.
- Typed Dictionary (since 4.4): `Dictionary[String, int]`; both types required (`Variant` for either side is allowed); nested typed collections not supported; value-returning methods stay Variant. `Dictionary` is `Dictionary[Variant, Variant]`.
- Typed loop variable (since 4.2): `for name: String in names:` types the variable even over an untyped array.
- `as` returns `null` silently when an Object is not of that type (and errors for a failed built-in conversion). Prefer `if x is T:` then `var t: T = x`, or `assert(x is T)`; `is not` exists. `var n: T = $Path` catches a wrong node type at load; `var n := $Path as T` silently becomes null.
- Where you cannot type: individual elements of a literal, nested typed collections, the rest parameter as `Array[int]`.

## Warnings (what the analyzer flags by default)

Source: `tutorials/scripting/gdscript/warning_system.rst`, `classes/class_projectsettings.rst` (`debug/gdscript/warnings/*`: 0 Ignore, 1 Warn, 2 Error).

- Error by default (2): `get_node_default_without_onready` (`var n = $X` without `@onready`), `inference_on_variant`, `native_method_override`, `onready_with_export` (`@onready @export` on one variable: the `@onready` value overwrites the Inspector value).
- Warn by default (1), the ones this code hits: `integer_division`, `narrowing_conversion`, `unused_variable`, `unused_parameter` (prefix with `_`), `unused_signal`, `unused_private_class_variable`, `shadowed_variable`, `shadowed_variable_base_class`, `shadowed_global_identifier`, `static_called_on_instance`, `unreachable_code`, `unsafe_void_return`, `confusable_capture_reassignment`, `redundant_await`, `standalone_expression`, `int_as_enum_without_cast`, `assert_always_true/false`.
- Off by default (0), worth turning on for a fully typed codebase: `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`, `return_value_discarded`, `missing_await`, `inferred_declaration`.
- `debug/gdscript/warnings/directory_rules` defaults to `{ "res://addons": 0 }` (addons excluded). Warnings do not stop a run unless set to Error.
- Silence one line: `@warning_ignore("integer_division")` (name = the setting's last segment). A region: `@warning_ignore_start("x")` ... `@warning_ignore_restore("x")`; omit the restore to cover the rest of the file.

## GDScript features older training data misses

- **Typed dictionaries** `Dictionary[K, V]` (4.4, `gdscript_basics.rst`).
- **Abstract classes and methods** (4.5): `@abstract class_name Shape` / `@abstract class Inner:` and `@abstract func draw()` (no body; newline or `;` after the header). A class with any unimplemented abstract method must itself be `@abstract`; instantiating one is an error; an abstract script cannot be attached to a node ("Cannot set object script ... should not be abstract"). For unnamed scripts `@abstract` goes before `extends` (`gdscript_basics.rst`, "Abstract classes and methods").
- **Variadic functions** (4.5): `func f(a, b = 0, ...args):` collects extra arguments into an Array. One rest parameter, last, no default; static functions and lambdas may be variadic; the rest parameter can be typed `Array` but **not** `Array[int]`. There is no spread operator: forward with `callable.callv(args)` (`gdscript_basics.rst`, "Variadic functions").
- **Static variables** (4.1): `static var x`, with types and setters/getters, shared across instances and subclasses; not allowed with `@export`/`@onready`; no static locals. `static func _static_init()` runs when the class loads, after static vars are initialized. A script with static variables is never unloaded; `@static_unload` exists but "due to a bug, scripts are never freed" even with it (`gdscript_basics.rst`).
- **`@warning_ignore_start` / `@warning_ignore_restore`** (region ignores).
- **`is not`** operator, **`when`** pattern guards in `match`, raw strings `r"..."`, `&"name"` StringName and `^"a/b"` NodePath literals, `%UniqueNode` shorthand, `#region`/`#endregion` folding.
- **Script backtraces** (4.5): errors log the GDScript call stack in editor and debug builds; release builds need `debug/settings/gdscript/always_track_call_stacks`. `Engine.capture_script_backtraces(include_variables := false)` returns `Array[ScriptBacktrace]` (`tutorials/scripting/logging.rst`, `classes/class_engine.rst`). Custom loggers via `OS.add_logger()` (4.5).
- **Exports**: `@export_storage` (saved and duplicated, hidden), `@export_custom(hint, hint_string, usage := 6)`, `@export_tool_button(text, icon := "")` on a Callable var in a `@tool` script, `@export_file_path`, `@export_placeholder`, `@export_flags_avoidance` (`gdscript_exports.rst`, `classes/class_@gdscript.rst`).
- **Changes in 4.6/4.7 that affect scripts**: setting an element of a packed-array property (`prop[i] = v`) no longer calls the property's setter (4.7); typed return inherited by overrides (4.7); `Object.is_class()` takes a `StringName` (4.7); `FileAccess.get_as_text()` lost its `skip_cr` parameter (4.6); `AnimationPlayer.current_animation`, `assigned_animation`, `autoplay` are `StringName` (4.6); the default `InputEvent.device` for mouse and keyboard is now `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD`, not `0` (4.7) (`tutorials/migrating/upgrading_to_godot_4.6.rst`, `upgrading_to_godot_4.7.rst`).
- Gone since Godot 3: `yield` (use `await`), `setget` (use `set:`/`get:`), `onready`/`export` keywords (now `@onready`/`@export`), `funcref` (Callable), `continue` inside `match`.

## Variables, properties and initialization order

Source: `gdscript_basics.rst` "Initialization order", "Properties (setters and getters)", `tutorials/best_practices/godot_notifications.rst`.

Member initialization, in order:
1. Every member gets `null` (untyped/objects) or its type's default (`0`, `false`...).
2. Initializers run top to bottom (initializer values are written directly, **setters are not called**). `@onready` ones are deferred to step 5. An initializer that calls a function which writes another member can be overwritten by a later initializer (the `_data = {}` example).
3. `_init()` runs (assignments here do call setters).
4. When instantiated from a scene/resource file, exported values are assigned (setters called).
5. Nodes only: `@onready` initializers.
6. Nodes only: `_ready()`.

- Exported values read in `_init()` are still the script defaults; read them in `_ready()` or in the property's setter.
- `set:`/`get:` are **always** called, from inside the class too (with or without `self.`), except: inside the property's own setter/getter (direct access, no recursion) and for the initializer. A helper function called from the setter that assigns the property recurses forever.
- Inline setters/getters take no type hints; the variable's type applies. `var p: get = get_p, set = set_p` uses named functions (typed allowed).
- `_init()` with **required** parameters means the object can only be made with `.new(args)`: `PackedScene.instantiate()`, `Node.duplicate()` and `Resource.duplicate()` fail for it (`classes/class_object.rst`, `class_node.rst`, `class_resource.rst`). Give every `_init` parameter a default if the class may ever be in a scene, a `.tres`, or duplicated.
- A subclass whose base `_init` takes arguments must define `_init` and call `super(...)`.
- `self.x` resolves at runtime (dynamic); bare `x` must exist at compile time.

## Functions, Callables, signals and await

Source: `gdscript_basics.rst` "Functions", "Signals", "Awaiting signals or coroutines"; `classes/class_callable.rst`, `class_signal.rst`, `class_object.rst`.

- A method name without `()` is a `Callable`. Call it with `.call(args)` / `.callv(array)`; `()` directly on a Callable is not allowed. `preload` is a keyword, not a Callable.
- `bind(...)` appends bound args **after** call args; `unbind(n)` drops the last n call args; chained binds/unbinds apply right to left.
- `Callable.create(variant, method)` is required for built-in-type methods on a Dictionary (`dict.clear` means the key `"clear"`).
- `is_null()` is not the opposite of `is_valid()`; check `is_valid()` before calling a stored Callable whose object may be freed.
- Connect with `sig.connect(callable, flags := 0)`. Flags: `CONNECT_DEFERRED` (1, run at idle time), `CONNECT_PERSIST` (2, saved with the scene; never for lambdas), `CONNECT_ONE_SHOT` (4), `CONNECT_REFERENCE_COUNTED` (8, allow the same Callable repeatedly), `CONNECT_APPEND_SOURCE_OBJECT` (16). Connecting the same Callable twice otherwise errors (`ERR_INVALID_PARAMETER`). Connections die with the target object. Signal methods are thread-safe.
- Signals are synchronous: `emit()` runs every connected Callable before returning (inferred from "Callback mechanism"; deferred only with `CONNECT_DEFERRED`). Signal argument lists are not enforced: "you can still emit any number of arguments".
- `await sig` suspends the function and returns control to the caller immediately; the awaited value is the single argument, an Array for several, `null` for none. A function containing `await` is a coroutine: calling it without `await` runs it until its first `await` and returns; taking its return value without `await` is an error. `await` on a non-signal, non-coroutine value returns it immediately. There is no function-state object (unlike Godot 3 `yield`).
- `await` has no place in simulation code: resumption timing depends on when the signal fires, not on the tick (project rule; tick order is in `main-loop.md`).
- `assert(cond, msg := "")` is stripped in release builds, arguments not evaluated: no side effects inside.

## Classes, inheritance and loading scripts

Source: `gdscript_basics.rst` "Classes", "Inheritance", "Inner classes", "Classes as resources", "Memory management"; `classes/class_gdscript.rst`.

- A script without `class_name` is referenced by path: `extends "res://tests/check_suite.gd"`, `const X = preload("res://x.gd")`. `class_name X` registers it globally (the editor's import/scan pass builds the global class list: `scripts/run_tests.sh` runs `--import` first for this reason, inferred from its comment and `ProjectSettings.get_global_class_list()`).
- Without `extends`, a script extends `RefCounted`. One base only.
- `super(args)` calls the parent's same method; `super.other()` calls another parent method. Virtual `_notification()` is called on every script in the chain automatically; do not call `super` in it (`classes/class_object.rst`).
- `GDScript.new(...)` instantiates a loaded script; `Object.set_script()` attaches one.
- Inner classes (`class Name:`) cannot be the script of a saved `.tres`: the resource file stores the script path, and custom properties of an inner-class Resource do not serialize (`tutorials/scripting/resources.rst`).
- Memory: RefCounted (and Resource) free themselves at zero references; reference **cycles leak** (break one side with `weakref()`); Node and Object need `free()`/`queue_free()`; freeing a Node frees its children (`classes/class_refcounted.rst`).

## Strings, StringName, NodePath

Source: `classes/class_string.rst`, `class_stringname.rst`, `class_nodepath.rst`, `gdscript_basics.rst`.

- `String` is copy-on-write; methods suffixed `n` are case-insensitive (`findn`, `replacen`), prefixed `r` search from the end.
- `StringName`: interned, one instance per name, very fast comparison, good dictionary keys; slower to create and "may result in waiting for locks when multithreading". Calling String methods on a StringName converts it and is "highly inefficient". Literal `&"name"`. Engine APIs that take names (`is_action_pressed`, `call`, `has_method`, signal names, `AnimationPlayer.play`) take StringName; pass a `&""` literal or a `const` in hot code to avoid a conversion per call.
- `NodePath` literal `^"A/B:position:x"`; `":"` separates property subnames; a leading `/` is absolute from the root Window.
- `%` formatting: `"%d %s %.3f" % [a, b, c]` (`gdscript_format_string.rst`).
- `str_to_var()` / `var_to_str()` round-trip any Variant as text; `JSON` does not (see `main-loop.md`).

## Randomness and determinism

Source: `classes/class_randomnumbergenerator.rst`, `class_@globalscope.rst`, `class_array.rst`.

- `RandomNumberGenerator` is currently PCG32, but "the underlying algorithm is an implementation detail and should not be depended upon": do not store expected random sequences in tests across engine upgrades, or ship them in network protocol expectations, without a check that would catch a change.
- A new RNG's `seed` and `state` are pseudo-random (the documented `0` is a placeholder). Set `seed` for reproducibility. `state` can be saved and restored (only values read from `state`); set `seed` **before** `state` because setting `seed` resets the state.
- Similar seeds give similar streams (no avalanche): hash inputs first (`hash([a, b])`, `"text".hash()`), as `weapon.gd` does.
- Ranges: `randf()` 0..1 inclusive; `randf_range(from, to)` inclusive; `randi()` unsigned 32-bit 0..4294967295; `randi_range(from, to)` inclusive; `randfn(mean, deviation)` Box-Muller; `rand_weighted(PackedFloat32Array)` returns an index, `-1` on empty.
- Global `randi()`, `randf()`, `randf_range()`, `Array.shuffle()`, `Array.pick_random()` use one global seed; `randomize()` is called automatically at startup; `seed(base)` fixes it for all callers at once.
- `Array.sort()` and `sort_custom()` are **not stable**; a `sort_custom` comparator must be consistent (never random) and returns `true` if `a` goes before `b`. Sort with a tie-breaker (e.g. userid) wherever order decides the game.

## Parsing text and bytes

- `RegEx`: `RegEx.create_from_string(pattern)` or `.new()` + `compile(pattern) -> Error`; `search(subject, offset := 0, end := -1) -> RegExMatch` (null on no match), `search_all(...) -> Array[RegExMatch]`, `sub(subject, replacement, all := false, ...)`. Escape for GDScript first (`"\\d+"`) or use raw strings (`r"\d+"`). Named groups `(?<name>...)`. Compile once (a `static var` or const-initialized member), not per call (`classes/class_regex.rst`).
- `Expression`: `parse(expression, input_names := PackedStringArray()) -> Error`, then `execute(inputs := [], base_instance := null, show_error := true, const_calls_only := false)`, check `has_execute_failed()` / `get_error_text()`. `/` on two ints is integer division here too. With a `base_instance` the text can call that object's methods, so never feed it untrusted text (`tutorials/scripting/evaluating_expressions.rst`, `classes/class_expression.rst`).
- `StreamPeerBuffer`: a cursor over `data_array` (a `PackedByteArray`; the getter returns a copy; setting it resets the cursor). `put_u8/16/32/64`, `put_float` (32-bit), `put_double`, `put_var(value, full_objects := false)`, matching `get_*`; `seek(position)`, `get_position()`, `resize(size)` (does not move the cursor); `big_endian` inherited from `StreamPeer` (`classes/class_streampeerbuffer.rst`, `class_streampeer.rst`). The natural fit for building snapshot/UserCmd packets later.
- `PackedByteArray` has in-place `encode_u8/u16/u32/u64/s8.../float/double/half/var` and `decode_*` at byte offsets, `compress()`/`decompress()`, `get_string_from_utf8()`, `to_float32_array()`, `to_vector3_array()` and friends (`classes/class_packedbytearray.rst`).
- `var_to_bytes(v)` / `bytes_to_var(b)` do not encode Objects (use the `_with_objects` variants only for trusted data); a `Callable` encodes to an empty value (`classes/class_@globalscope.rst`).

## Style the project already follows

Source: `tutorials/scripting/gdscript/gdscript_styleguide.rst` "Code order".

`@tool/@icon/@static_unload`, `class_name`, `extends`, `##` doc comment, signals, enums, constants, static vars, `@export` vars, other vars, `@onready` vars, `_static_init()`, static methods, virtuals in the order `_init`, `_enter_tree`, `_ready`, `_process`, `_physics_process`, other virtuals, then custom methods, then inner classes. Private members prefixed `_`. Tabs for indentation.

## Class notes

**Array** (`classes/class_array.rst`)
- Constructors: `Array()`, `Array(from: Array)`, `Array(base: Array, type: int, class_name: StringName, script: Variant)` (make a typed array at runtime), `Array(from: Packed*Array)`.
- `duplicate(deep: bool = false) -> Array`; `duplicate_deep(deep_subresources_mode: int = 1) -> Array`; `assign(array: Array)` (copies, converts type); `resize(size: int) -> int` (Error; then fill by index; faster than repeated `append`); `insert/remove_at/erase/pop_front` shift every later element (slow on big arrays); `pop_front()`/`pop_back()` return `null` on empty, `back()`/`front()` error on empty; `has`, `find`, `find_custom`, `rfind_custom`, `count`, `filter`, `map`, `reduce`, `any`, `all`, `min`, `max`, `slice`, `bsearch`, `bsearch_custom`.
- `is_typed()`, `get_typed_builtin()`, `get_typed_class_name()`, `is_same_typed(array)`, `make_read_only()`, `is_read_only()`, `hash()` (32-bit).
- `sort()` / `sort_custom(func)`: unstable. `shuffle()`, `pick_random()`: global RNG.

**Dictionary** (`classes/class_dictionary.rst`)
- Keeps insertion order. `get(key, default = null)` (default is evaluated eagerly), `get_or_add(key, default = null)`, `has`, `has_all`, `erase(key) -> bool`, `keys()`, `values()`, `find_key(value)`, `merge(dict, overwrite := false)`, `merged(...)`, `sort()` (by key; makes `keys()`/`str()`/`JSON.stringify()` order stable), `recursive_equal(dict, recursion_count)`, `duplicate(deep)`, `duplicate_deep(mode)`, `assign(dict)`, `make_read_only()`, `is_typed()`/`is_typed_key()`/`is_typed_value()`.
- `d.key` is `d["key"]` for String keys; bracket syntax needed for other key types. Lua-style literal `{a = 1}` makes String keys.
- Named `enum State {A, B}` in GDScript is a constant Dictionary: `State.keys()`, `State.values()` work.

**Packed arrays** (`classes/class_packedvector3array.rst`, `class_packedfloat32array.rst`, `class_packedbytearray.rst`)
- Faster to iterate and modify than `Array[T]` and smaller; `Array[T]` in turn faster than untyped Array. No `map/filter/reduce`.
- Methods: `append`/`push_back` (return bool), `append_array`, `resize(new_size) -> int`, `set(i, v)`, `get(i)`, `insert`, `remove_at`, `erase(value) -> bool`, `has`, `find`, `rfind`, `count`, `fill`, `reverse`, `slice(begin, end := 2147483647)`, `sort`, `bsearch`, `duplicate()` (no deep flag), `to_byte_array()`, `is_empty()`.
- `PackedFloat32Array` holds float32; use `PackedFloat64Array` when doubles matter.
- Engine getters (for example `Mesh.get_faces()`, `StreamPeerBuffer.data_array`) return a **copy**: to change such a property, modify and reassign.

**Object** (`classes/class_object.rst`)
- `free()`: immediate; later access is a runtime error. `is_queued_for_deletion()` (false on children of a queued node). `get_instance_id()` / `instance_from_id(id)`: session-only IDs, never send them over the network. `call_deferred(method, ...)` and `set_deferred(property, value)`: run at idle time (see `main-loop.md`); `call_deferred` always returns null.
- `set()`, `get()`, `call()`, `has_method()`, `"name" in obj`: "much slower than direct references".
- `_notification(what)`: called on every script in the chain; `NOTIFICATION_PREDELETE` (1) is the destructor hook, sent in reverse order.
- Boolean context: false if null or freed.

**RefCounted** (`classes/class_refcounted.rst`): freed at zero references; cycles leak unless one side is a `weakref()`. The default base of a script with no `extends`.

**Variant** (`classes/class_variant.rst`): 20 bytes; `typeof(x)` returns `Variant.Type` (`TYPE_INT`, `TYPE_FLOAT`, `TYPE_ARRAY`...). `Variant` as a type hint means untyped.

**Callable** (`classes/class_callable.rst`): `call`, `callv`, `call_deferred`, `bind`, `bindv`, `unbind`, `create(variant, method) static`, `get_argument_count`, `get_bound_arguments`, `get_method`, `get_object`, `get_object_id`, `is_valid`, `is_null`, `is_custom` (lambdas, bound, built-in-type methods), `is_standard`, `hash`. `==` is true when both invoke the same target.

**Signal** (`classes/class_signal.rst`): `connect(callable, flags := 0) -> int`, `disconnect`, `emit(...)`, `is_connected`, `has_connections`, `get_connections`, `get_name`, `get_object`. Prefer `obj.sig.connect(f)` over `obj.connect("sig", f)`.

**StringName** (`classes/class_stringname.rst`), **NodePath** (`class_nodepath.rst`), **String** (`class_string.rst`): see "Strings" above.

**RID** (`classes/class_rid.rst`): opaque server handle; `is_valid()`, `get_id()`; session-only, never serialize.

**RandomNumberGenerator** (`classes/class_randomnumbergenerator.rst`): `seed: int`, `state: int`, `randf()`, `randf_range(from, to)`, `randfn(mean := 0.0, deviation := 1.0)`, `randi()`, `randi_range(from, to)`, `rand_weighted(weights)`, `randomize()`.

**RegEx** (`classes/class_regex.rst`), **Expression** (`class_expression.rst`), **StreamPeerBuffer** (`class_streampeerbuffer.rst`): see "Parsing text and bytes".

**GDScript** (`classes/class_gdscript.rst`): the script resource; `new(...)` instantiates. `@GDScript` holds `load(path)`, `preload(path)` (const path, loaded when the script is parsed), `range()`, `len()`, `is_instance_of(value, type)`, `type_exists()`, `inst_to_dict()`/`dict_to_inst()`, `get_stack()` (debug builds only unless `always_track_call_stacks`), `print_debug()`, `print_stack()`, `char()`/`ord()`, `Color8()`, `convert()`.

## Where the code already does this

- Caches that hand out copies, as the docs require for shared containers: `src/weapons/recoil_pattern.gd:28` (`PackedVector2Array.duplicate()`), `src/weapons/recoil_state.gd:101` and `:125`, `src/combat/hitbox_set.gd:71` (`duplicate(true)` for an `Array[Dictionary]`), `src/game/item_registry.gd:96` (`_order.duplicate()`) and `:126` (`WeaponData.duplicate()`).
- `static var` caches loaded once per process: `src/weapons/weapon_sheet.gd:23`, `src/weapons/weapon_vdata.gd:25`, `src/map/surface_properties.gd:26-27`, `src/audio/sound_bank.gd:12-13`, `src/player/rig_model.gd:65-67`; `static var current: GameWorld` in `src/sim/game_world.gd:37`.
- Typed loop over a copied typed array: `src/sim/game_world.gd:114` (`for player: PlayerSim in players.duplicate():`), so joining or leaving mid-tick cannot disturb the iteration.
- Seeded RNGs for anything the simulation decides: `src/weapons/weapon.gd:707-708` and `:728-730` (`rng.seed = hash([...])`), `src/bomb/bomb_system.gd:210`, `src/bots/bot.gd:357-358`, `src/game/item_drops.gd:208-210`.
- Integer microsecond time: `src/sim/sim_clock.gd` (`tick_usec() -> int`, no float accumulation).
- `@warning_ignore("integer_division")` where truncation is meant: `tests/run_sim_checks.gd:18-21`.
- JSON numbers come back as float and are cast: `src/map/brush_volume.gd:164-165` (`int(primitive["attributes"]["POSITION"])`).
- `StreamPeerBuffer` for building binary fixtures: `tests/run_map_tests.gd:698`, `:831`.

Looks at odds with the docs (not verified, not changed):

- `src/weapons/weapon_sheet.gd:28-30` (`rows()`), `src/weapons/weapon_vdata.gd:30-32` (`classes()`) and `src/map/surface_properties.gd:33-35` (`rows()`) return the cached `Dictionary` itself, not a copy. Dictionaries are passed by reference, so a caller that writes into the result (for example `src/game/item_registry.gd:169` takes `WeaponVData.classes()[weapon_class]`, a nested Dictionary) would change the cache for every later caller. The callers seen only read, so this is a latent risk against the "caches hand out copies" rule, not a live bug.
- `src/game/item_registry.gd:126` returns `WeaponData.duplicate()` (shallow). Per `class_resource.rst` that (a) shares the `scoped: WeaponData` sub-resource with the cached original, so writing to `copy.scoped.*` changes the cache, and (b) does not copy the non-exported lazy fields `_solved_kick_up` / `_solved_model_hold_time` (`src/weapons/weapon_data.gd:30-31`), so every copy re-solves them on first use (on whatever tick that happens). `@export_storage` on those two fields would carry them over.
- `src/bots/bot.gd:140` keeps an unseeded `RandomNumberGenerator` (pseudo-random seed per instance) and draws aim error from it at `:289-290`. The simulation still only reads commands, but a bot's commands differ from run to run, so a replay of the same match from bot inputs is not reproducible.
- `src/player/player_view.gd:102` is a Node with a required `_init(p_player)`: fine while it is only made with `.new(player)`, but it can never be placed in a `.tscn` or `Node.duplicate()`d.

## Not covered here

- Node lifecycle, tick/frame order, `process_physics_priority`, `queue_free`, pausing, SceneTree, autoloads, files, `res://` vs `user://`, JSON/ConfigFile, threads, headless runs: `main-loop.md`.
- Documentation comments (`##`, `@tutorial`, `@deprecated`): `tutorials/scripting/gdscript/gdscript_documentation_comments.rst`.
- Full `@export_*` hint syntax, `_get_property_list()` for dynamic properties: `tutorials/scripting/gdscript/gdscript_exports.rst`.
- Format-string specifiers in full: `tutorials/scripting/gdscript/gdscript_format_string.rst`.
- Custom iterators (`_iter_init`, `_iter_next`, `_iter_get`): `tutorials/scripting/gdscript/gdscript_advanced.rst`.
- Cross-language scripting, C#: `tutorials/scripting/cross_language_scripting.rst`, `tutorials/scripting/c_sharp/`.
- Binary serialization format of `var_to_bytes`: `tutorials/io/binary_serialization_api.rst`.
- `@rpc` and multiplayer: `tutorials/networking/`.
- The cost of Object/Variant calls from GDScript and when to move code to C++: `engine.md`.
