# The game's native code

C++ built into a GDExtension of the game's own, for what the script is too
slow at. So far one thing: the movement's step (`src/hull_mover.cpp`,
class `HullMover`), which is `PlayerBody._simulate_step` and everything it
calls, with the hull's sweep as `Box3DQueries` answers it.

## Building it

    scripts/build_native.sh            # Linux, macOS, Git Bash
    scripts/build_native.ps1           # Windows

It needs git, Python 3 and a C++ compiler (Visual Studio's on Windows). The
script fetches godot-cpp 10.0.0-stable at a pinned commit into
`.godot/native-build` (or where `CSGODOT_NATIVE_BUILD` points, or
`-BuildDirectory`: it is 300 MB built), puts SCons 4.8.1 in a virtual
environment there when there is none, builds
`addons/csgodot_native/bin/libcsgodot_native.<platform>.template_debug.<arch>`,
copies `csgodot_native.gdextension` beside it and runs Godot's import pass,
which lists the extension for the game to load. The first build compiles
godot-cpp, about six minutes; later ones only what changed. `release` after
the script's name builds the library an exported game loads as well.

Neither the library nor the copied `.gdextension` is committed. A checkout
without them runs the movement by the script, as it always did, and says
nothing about it. The `.gdextension` is kept out of the project until there
is a library because Godot prints three errors at every start for a listed
extension with none.

The editor binary, which runs the game and the checks, loads the
`template_debug` library. godot-cpp builds it optimized (`/O2` with Visual
Studio, `-O2` elsewhere, where `template_release` is `/O2` and `-O3`); it
differs from the release one in godot-cpp's own checks.

After a change under `native/src`, build again and restart Godot
(`reloadable` is off: the game is not the editor's to reload under).

## The rule it is held to

The script is the reference. The native step gives the same body as the
script's, to the last bit of every part, or it is wrong.

- Every check file runs each native step by the script first, from the same
  start, and compares the two (`PlayerBody.check_steps`, turned on by
  `tests/check_suite.gd`): a file in which one step differed has failed,
  with the step's start and the parts that differed.
  `tests/run_native_movement_checks.gd` walks a course made to reach the
  branches a match seldom does, with the movement's settings changed under
  it.
- A change to `PlayerBody`'s step, `MovementSolver`, or the box sweep in
  `Box3DQueries` (`shape_cast_prepared`, `_native_cast`, `_mapped`) is made
  in both, in the same pull request. The checks fail until it is.
- Where the native code cannot run a step, the script does:
  `PlayerBody._native_mover` says when (no library, Godot's own physics, a
  hull that is no upright box, a body under anything moved or turned).
  `--movement script` after `--`, or the project setting
  `csgodot/simulation/movement`, has the script run every step.

## Writing it to give the same bits

GDScript's `float` is a 64-bit double. A `Vector3`'s parts are 32-bit
floats. The script's arithmetic widens and narrows between the two at
every step, and the C++ has to do so at the same steps:

| In script | What happens | In C++ |
|---|---|---|
| `v * s` (vector by float) | `s` is narrowed to 32 bits, then three 32-bit multiplies | `times(v, s)`: `v * (real_t)s` |
| `v.x * s` (a part by a float) | the part is widened, a 64-bit multiply | `(double)v.x * s` |
| `v.dot(w)`, `v.length()` | 32-bit arithmetic, the result widened | godot-cpp's own, then `(double)` |
| `a + b * c` on floats | two 64-bit operations, each rounded | the same, and never fused: `/fp:precise`, `-ffp-contract=off` (`SConstruct`) |
| `Vector3(a, b, c)` from floats | each narrowed | `Vector3((real_t)a, (real_t)b, (real_t)c)` |
| `cos(deg_to_rad(x))` | the engine's C runtime | passed in from the script: two runtimes' `cos` may differ in the last bit |

`hull_mover.cpp` keeps every scalar as `double` and every vector as
godot-cpp's `Vector3`, whose operators are the engine's own source.

## What crosses between the two

`HullMover.step(body, world, dt, walkable_y)` reads the body's state and
its config by property name, runs the step on its own copy, and writes the
state back. The body's place is written to the node once a step. It calls
back into script for two things: `_set_hull` when a duck changes the hull's
height (the node's place is written first), and
`_ground_normal_in_quadrants_at` for the four rays under the hull's
corners. It asks Box3D's binding for its sweeps by name
(`world.call("shape_cast_box", ...)`), so it is built against Godot's API
alone and not against Box3D's.

A property it reads that `PlayerBody` no longer has comes back as nil and
reads as zero: rename one in both.
