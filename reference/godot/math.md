# Godot 4.7: 3D math and coordinates

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: converting Source/CS2 data (Z-up positions, angles, vdata vectors) into the game, writing aim, recoil, spread or penetration math, building transforms for hitboxes, ragdolls, views or effects, interpolating between ticks, or worrying about float precision far from the origin.

The physics side (queries, shapes, Jolt) is on the companion page `physics.md`.

## Rules for this project

- **Godot is right-handed and Y-up, and -Z is forward.**
  - Constants: `Vector3.FORWARD = (0, 0, -1)`, `BACK = (0, 0, 1)`, `RIGHT = (1, 0, 0)`, `UP = (0, 1, 0)`.
  - A camera, a light or the player looks down its local -Z (`classes/class_vector3.rst`, `classes/class_basis.rst`, `tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.rst`).
  - Imported **models face +Z** (glTF convention): `Vector3.MODEL_FRONT = (0, 0, 1)` and `MODEL_LEFT = (1, 0, 0)`. That is why the project's third-person bodies are turned 180 degrees (`player_model.gd`, `view_model.gd`, `player_view.gd:434`).
- **Convert Source data in one place.** A Source position `(x, y, z)` (inches, Z-up) is `SourceEntities.to_game(v) = Vector3(v.y, v.z, v.x)` (`src/map/source_entities.gd:81`). A Source yaw is `SourceEntities.to_game_yaw(yaw) = wrapf(yaw + 180, -180, 180)`. Don't write a second conversion inline.
- **Keep angles outside transforms.** The docs say: don't read angles back out of a transform ("you don't"), and don't use `Node3D.rotation` for gameplay rotation. Keep yaw and pitch as numbers (as `UserCmd`/`PlayerInput` do) and build the Basis from them each time (`tutorials/3d/using_transforms.rst`).
- **Use `affine_inverse()` for any transform that may carry scale.** `Transform3D.inverse()` and `vector * transform` are only correct for orthonormal bases (rotation only) (`classes/class_transform3d.rst`, `classes/class_vector3.rst`).
- **Radians everywhere** in the engine API (`Basis(axis, angle)`, `rotated`, `from_euler`, joint limits). Degrees only via `deg_to_rad`/`rad_to_deg` or the `*_degrees` properties (`tutorials/math/matrices_and_transforms.rst`).
- **Vector math is 32-bit.** `float` in GDScript is 64-bit, but `Vector3`, `Basis`, `Transform3D`, `Quaternion`, `AABB` and `Plane` components are 32-bit in a normal build (`tutorials/physics/large_world_coordinates.rst`, `classes/class_vector3.rst`). Keep long-running accumulators (sim time, money, distance travelled) in `float`/`int`, not in vector components. `SimClock` already counts in integer microseconds.
- **Compare with tolerance.** `==` on vectors, bases and transforms is exact. The docs recommend `is_equal_approx()` / `is_zero_approx()` instead.

## Coordinate conventions

Doc: `tutorials/3d/introduction_to_3d.rst`, `tutorials/3d/using_transforms.rst`, `tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.rst`, `classes/class_vector3.rst`

- Godot: right-handed, "Y-is-up", "-Z axis as the camera's forward direction. This is the same as OpenGL", so +Z is back, +X is right and -X is left for a camera.
- Oriented assets (characters, weapons from glTF) face **+Z**, so +X is their left. Use `look_at(..., use_model_front = true)` and the `Vector3.MODEL_*` constants for asset space.
- For maps: +X is east, -X is west, +Z is south, -Z is north (`Vector3` docs on LEFT/RIGHT/FORWARD/BACK).
- `Basis.x/y/z` are the columns, i.e. the node's local right, up and back. So `-transform.basis.z` is "forward" and `transform.basis.x` is right (`using_transforms.rst`: "Keep in mind that -Z is forward").
- 3D rotation sign: a positive angle rotates counter-clockwise about the axis (right-hand rule) (`Basis.rotated`, `Transform3D.rotated`). `Vector3.signed_angle_to(to, axis)` is positive counter-clockwise viewed from the side `axis` points to.
- 2D is Y-down. The matrices tutorial's 2D examples use that convention, so don't carry them into 3D code.

## Source (Z-up) data into the game

Doc: none of the Godot docs cover Source. This section is from the project's code; the axis maths is marked where inferred.

- Source/Hammer axes (inferred from Source convention): +X forward (yaw 0), +Y left, +Z up, right-handed, 1 unit = 1 inch. The project keeps inches, so there's no scale change for gameplay numbers.
- **Positions and directions**: `to_game(v) = (v.y, v.z, v.x)`. Source X → game Z, Source Y → game X, Source Z → game Y.
  - This is a cyclic axis permutation, whose determinant is +1, so handedness is preserved and cross products carry over unchanged (inferred).
  - Apply the same mapping to direction vectors and normals (translation-free). A Source plane `(n, d)` becomes `Plane(to_game(n), d)` (inferred).
- It matches Source 2 Viewer's glTF exports once scaled by `MapImporter.SOURCE2_VIEWER_SCALE = 1 / 0.0254` (glTF metres to inches), and `tests/run_dust2_checks.gd` checks it against dust2's spawns.
- **Yaw**: Source yaw 0 looks down Source +X, which is game +Z. The project's yaw 0 looks down game -Z, hence `+180`.
  - A Source yaw θ turns counter-clockwise seen from above, from Source +X toward +Y. In game space that is from +Z toward +X, a positive rotation about +Y. So yaw keeps its sign, and only the 180-degree offset differs (inferred; consistent with `aim_direction` below).
- **Pitch**: Source pitch is positive looking **down**. The project's `PlayerInput` pitch is positive looking **up** (`aim_direction` returns `y = sin(pitch)`). Negate a Source pitch when importing one (inferred from both conventions).
- **Aim vector** (project convention, `src/player/player_input.gd:186`): `aim_direction(yaw, pitch) = (-sin(yaw) cos(pitch), sin(pitch), -cos(yaw) cos(pitch))`, which equals `Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD` with the default YXZ order (`player_view.gd:226` uses that form). Its inverse is `angles_from_direction`.
- **Source angles as a Basis** (inferred): `Basis.from_euler(Vector3(deg_to_rad(-src_pitch), deg_to_rad(src_yaw + 180), deg_to_rad(src_roll_sign_checked)))`. Roll's sign hasn't been checked in this project. Verify it against a known entity before relying on it.
- Source-space local frames that the project keeps as they are: the muzzle-flash tables use "+X down the barrel, +Y left, +Z up" (`src/effects/flash_table.gd:12`). Convert at the point of use, not in the data.
- `MapImporter.rotate_z_up_to_y_up` (default `false`) instead rotates the imported scene -90 degrees about X, which maps `(x, y, z)` to `(x, z, -y)`. That's a different Y-up mapping from `to_game`, a yaw of 90 degrees away. So (inferred) a map imported with that toggle on wouldn't line up with entity positions from `to_game`.

## Vectors

Doc: `tutorials/math/vector_math.rst`, `tutorials/math/vectors_advanced.rst`, `classes/class_vector3.rst`, `classes/class_vector3i.rst`

- `Vector3` components are 32-bit floats. A zero vector is falsy in a boolean context.
- Traps that differ from other engines:
  - `reflect(n)` in Godot "passes through the plane". **`bounce(n)` is what most engines call reflect.** For a grenade or ricochet off a wall use `v.bounce(normal)` (or the explicit `v - 2 * v.dot(n) * n`, as `grenade_flight.gd` does).
  - `slide(n)` removes the component along `n`. **`n` must be normalized.** This is the core of collide-and-slide clipping (Source's ClipVelocity also scales by overbounce, so it's not the same).
  - `project(b)` gives NaN components if `b` is zero.
  - `normalized()` returns `(0,0,0)` for a zero vector, and "may return incorrect values if the input vector length is near zero". Check `length_squared()` first. `is_normalized()` checks length ≈ 1.
  - `rotated(axis, angle)`: the axis must be normalized.
  - `cross(with)` is right-handed and returns zero for parallel vectors (a cheap parallel test).
  - `angle_to(to)` is unsigned. `signed_angle_to(to, axis)` is signed.
  - `limit_length(length = 1.0)` clamps the length (a speed cap). `move_toward(to, delta)` steps by a fixed amount without overshooting (friction or accel-style approach).
  - `slerp(to, weight)` interpolates the direction **and** the length. It behaves like `lerp` when either length is zero.
  - `snapped(step)` / `snappedf(step)` round to a grid. `posmod`/`posmodv` wrap positively.
  - `distance_squared_to` and `length_squared` are cheaper. Use them for comparisons.
- Inverse-multiply operators assume orthonormal bases:
  - `vector * basis` = `basis.transposed() * vector`
  - `vector * transform` = `transform.inverse() * vector`
  - `vector * quaternion` = `quaternion.inverse() * vector`
  - With scale, use `basis.inverse() * v` or `transform.affine_inverse() * v`.
- `Vector3i` is 32-bit ints, the right key for voxel and grid cells (`smoke_voxels.gd` keys cubes by `Vector3i`).
  - `Vector3i(Vector3)` **truncates toward zero**, so -0.5 becomes 0. For cell indices use `Vector3i((p / cell).floor())`.
  - `%` uses truncated division (negative remainders). Use `posmod` for wrap-around.
  - `<` compares X, then Y, then Z (sortable).
- Planes from vectors (`vectors_advanced.rst`): distance from a point to plane `(N, D)` is `N.dot(p) - D`. The point on the plane closest to the origin is `N * D`. A convex solid is the set of points with `distance <= 0` against all its outward planes (the pattern `BrushVolume.contains()` uses). SAT overlap is sketched there too.

## Basis

Doc: `classes/class_basis.rst`, `tutorials/math/matrices_and_transforms.rst`

- A 3x3 matrix. The properties `x`, `y`, `z` are the **columns** (the local axes). `basis[i]` indexes columns in GDScript (in C++, `[]` is rows).
- The docs name the kinds: orthogonal, normalized, uniform, orthonormal (rotation only), conformal (orthogonal and uniform).
- Constructors:
  - `Basis()` is IDENTITY (in C# it's all zeros).
  - `Basis(axis: Vector3, angle: float)`: the axis must be normalized, the angle in radians.
  - `Basis(from: Quaternion)`.
  - `Basis(x_axis, y_axis, z_axis)`: columns.
- `Basis.from_euler(euler: Vector3, order: int = 2) static`:
  - `euler.x` is pitch (about X), `euler.y` is yaw (about Y), `euler.z` is roll (about Z), in radians.
  - The default order `2` is `EULER_ORDER_YXZ`, **intrinsic**: yaw first, then local pitch, then local roll. That's the FPS order the tutorial asks for.
  - `get_euler(order = 2)` decomposes, and the basis must be orthonormal for it.
  - `Node3D.rotation` uses `rotation_order`, default 2 (YXZ).
- `looking_at(target, up = Vector3.UP, use_model_front = false) static`: -Z points at `target` (+Z with `use_model_front`). The result is orthonormalized. `target` and `up` must be non-zero and not collinear.
- Methods and cautions:
  - `rotated(axis, angle)` rotates in the parent/global frame (`R * B`).
  - `scaled(scale)` scales rows (global). `scaled_local(scale)` scales columns (local).
  - `orthonormalized()` removes accumulated drift and **drops scale**.
  - `get_scale()` returns the column lengths (negative if `determinant() < 0`).
  - `get_rotation_quaternion()` works on a scaled basis. The `Quaternion(Basis)` constructor needs orthonormal input and **returns IDENTITY on failure**.
  - `slerp(to, weight)`: both must be rotations.
  - `inverse()` and `transposed()` (for an orthonormal basis, the transpose is the inverse and is cheaper).
  - `is_orthonormal()`, `is_conformal()`, `is_equal_approx()`, `is_finite()`, `determinant()`.
  - The constants `IDENTITY`, `FLIP_X`, `FLIP_Y`, `FLIP_Z`.
- `A * B` applies B then A (parent * child). Order matters.
- A basis is falsy when it equals IDENTITY.

## Transform3D

Doc: `classes/class_transform3d.rst`, `tutorials/3d/using_transforms.rst`, `tutorials/math/matrices_and_transforms.rst`

- A `basis: Basis` plus `origin: Vector3` (3x4). `Transform3D()` is IDENTITY. The constructors are `Transform3D(basis, origin)`, `Transform3D(x_axis, y_axis, z_axis, origin)` and `Transform3D(Projection)`, which drops the last row.
- `parent * child` is the child's world transform. `t * v` transforms a point. `t * aabb`, `t * plane` and `t * packed_vector3_array` also work, and the packed-array form is "much faster than transforming each Vector3 individually". The map importer bakes mesh faces with it.
- Inverses:
  - `inverse()` needs an orthonormal basis.
  - `affine_inverse()` handles scale and shear. It's slower, and needs `determinant() != 0`.
  - The world-to-local idiom is `node.global_transform.affine_inverse() * point` (or `Node3D.to_local(point)`; `to_global` is the reverse).
- Global versus local:
  - `rotated(axis, angle)` is `R * X`, global/parent frame. `rotated_local(axis, angle)` is `X * R`, local frame, and its axis is in local space (`Vector3.RIGHT` for local X).
  - `scaled` and `scaled_local`, `translated` and `translated_local` follow the same pattern.
- `looking_at(target, up = UP, use_model_front = false)` discards the existing rotation and scale.
- `orthonormalized()`: the docs recommend orthonormalizing a transform that is rotated every frame, since precision errors make it drift. Re-apply scale afterwards if needed.
- `interpolate_with(xform, weight)`: the docs call it linear interpolation between transforms. A weight outside 0 to 1 extrapolates. `interpolation.rst` says the transforms should have uniform or equal non-uniform scale. The ragdoll draws between ticks with it. (inferred) The rotation is interpolated spherically, not component-wise.
- `t * float` / `t / float` scale the **origin too**, not just the basis.
- `Node3D.top_level = true` makes a node ignore its parent's transform (so `global_transform == transform`). `Ragdoll` uses this.

## Quaternion

Doc: `classes/class_quaternion.rst`, `tutorials/3d/using_transforms.rst`

- Rotation only, Hamilton convention, 32-bit components. It must be normalized to represent a rotation, so after repeated operations call `normalized()`.
- The 4-float constructor is **`Quaternion(x, y, z, w)`, with w last**. The identity is `Quaternion(0, 0, 0, 1)`. In C#, `new Quaternion()` is all zeros.
- `Quaternion(axis, angle)`: the axis must be normalized. `Quaternion(arc_from, arc_to)` is the shortest arc between two directions (an "align this to that" rotation).
- `Quaternion(Basis)` fails and returns IDENTITY if the basis isn't orthonormal. Use `basis.get_rotation_quaternion()` for scaled bases.
- `slerp(to, weight)` takes the short path and needs both normalized. `slerpni` doesn't check for the short path.
- Other members: `spherical_cubic_interpolate(b, pre_a, post_b, weight)` and `spherical_cubic_interpolate_in_time(...)`; `angle_to` (the docs warn its float error is "abnormally high"); `get_axis()`; `get_angle()`; `inverse()` (the conjugate); `from_euler(euler) static` (always YXZ); `get_euler(order = 2)`.
- `q1 * q2` composes (q1 is the parent). `q * v` rotates a vector.
- The tutorial's use: convert both bases to quaternions, slerp, and convert back with `Basis(q)`. Scale is lost. `player_view.gd:283` does this for the death camera.

## AABB and Plane

Doc: `classes/class_aabb.rst`, `classes/class_plane.rst`, `tutorials/math/vectors_advanced.rst`

- **AABB**:
  - It's `position` (min corner) + `size`. `end` is `position + size`.
  - Negative sizes aren't supported, so call `abs()` first.
  - `has_point` excludes points exactly on the right, top and front faces. `intersects` excludes touching edges. `encloses` includes edges.
  - `intersects_ray(from, dir)` and `intersects_segment(from, to)` return the first hit `Vector3` or `null`, so check for `null` before using the result.
  - Other members: `grow(by)` (a negative value shrinks), `merge`, `expand(to_point)`, `intersection` (flat or empty on touch or miss), `get_support(dir)`, `get_endpoint(0..7)`, `get_center()`, `get_longest_axis*()`, `get_shortest_axis*()`, `has_volume()`, `has_surface()`.
  - `Transform3D * AABB` gives an axis-aligned box around the transformed box (inferred: it grows under rotation).
  - An AABB is falsy when both position and size are zero.
- **Plane**:
  - It's `normal` + `d` ("distance from the origin to the plane, in the direction of normal"). "Over"/"above" is the side the normal points to.
  - Constructors:
    - `Plane(normal)`
    - `Plane(normal, d)`
    - `Plane(normal, point)`: `normal` must be unit length.
    - `Plane(a, b, c, d)`
    - `Plane(p1, p2, p3)`: points "in clockwise order". (inferred) Check the resulting normal's direction in Godot's right-handed Y-up space before relying on it.
  - `distance_to(point)`: positive above, negative below.
  - Other members: `is_point_over`, `has_point(point, tolerance = 1e-05)`, `project(point)`, `intersects_ray(from, dir)`, `intersects_segment(from, to)`, `intersect_3(b, c)` (these three return `Vector3` or `null`), `normalized()` (returns `Plane(0,0,0,0)` for a zero normal), `get_center()`.
  - Negate both N and D to flip sides (unary `-`).

## Geometry3D and Projection

Doc: `classes/class_geometry3d.rst`, `classes/class_projection.rst`

- `Geometry3D` is a singleton: call `Geometry3D.method(...)`. Pure math, no physics space, safe anywhere. It's useful for testing against the project's own capsules without touching Jolt (the lag-compensation plan in `reference/performance.md` wants rewound rounds tested "in script, ray against capsule").
  - `get_closest_point_to_segment(point, s1, s2)` (clamped) and `get_closest_point_to_segment_uncapped`.
  - `get_closest_points_between_segments(p1, p2, q1, q2) -> PackedVector3Array [on_p, on_q]`: a capsule-versus-ray test is "distance between the ray segment and the capsule's axis segment <= radius" (inferred use).
  - `segment_intersects_sphere(from, to, sphere_position, sphere_radius)` and `segment_intersects_cylinder(from, to, height, radius)` (cylinder centred at the origin) return `[point, normal]`, or empty for a miss.
  - `segment_intersects_convex(from, to, planes: Array[Plane])` returns `[point, normal]` or empty.
  - `ray_intersects_triangle(from, dir, a, b, c)` and `segment_intersects_triangle(from, to, a, b, c)` return `Vector3` or `null`.
  - `get_triangle_barycentric_coords(point, a, b, c)`.
  - Builders and utilities: `build_box_planes(extents)` (half-size), `build_capsule_planes(radius, height, sides, lats, axis = 2)`, `build_cylinder_planes(...)`, `compute_convex_mesh_points(planes)`, `clip_polygon(points, plane)`, `tetrahedralize_delaunay(points)`.
- `Projection` is a 4x4 matrix of four `Vector4` columns (the camera's projection). Use `Transform3D` for anything affine: it's "more performant and requires less memory". Relevant members: `create_perspective(fovy, aspect, z_near, z_far, flip_fov = false) static`, `get_fov()`, `get_fovy(fovx, aspect) static` (for converting CS2's horizontal FOV), `get_z_near()`, `get_z_far()`, `get_projection_plane(plane)`, `inverse()`.

## Float precision and large world coordinates

Doc: `tutorials/physics/large_world_coordinates.rst`, `tutorials/3d/using_transforms.rst`

- Single precision represents every integer only within ±16,777,216.
- The step size doubles with each power of two. The docs' table:

| Range | Step |
|---|---|
| [1024; 2048] | about 0.0001 |
| [2048; 4096] | about 0.0002 |
| [4096; 8192] | about 0.0005 |
| [8192; 16384] | about 0.001 |
| [16384; 32768] | about 0.0019 |
| [32768; 65536] | about 0.0039 |

- The docs' recommended limits are in **units** (they write metres): up to 4096 for a first-person game "without rendering artifacts or physics glitches", and 32768 for any 3D game.
- (inferred) In this project a unit is an inch. dust2 spans a few thousand units from its origin, so positions sit in the [2048, 8192] band: about 0.0002 to 0.0005 inch steps, far below anything gameplay measures. The same numbers in metres would be 39 times coarser, but here they stay fine.
- Large world coordinates (`precision=double`) need a **custom-compiled** editor and export templates. The server and all clients must use the same build type, and GDExtensions must be rebuilt. The docs say you probably don't need it for levels under the limits above. The project doesn't use it, and CS maps don't need it (inferred).
- Precision traps that do matter here:
  - A long-lived vector accumulator loses bits. For example, adding `velocity * dt` into a position at 64 Hz is fine per tick, but summing tiny deltas into a large total isn't. Keep tick counts as `int` (as `SimClock` does).
  - A basis that is rotated repeatedly drifts off orthonormal. `orthonormalized()` it, or rebuild it from stored angles (the project rebuilds from yaw and pitch each time).
  - Exact equality on floats or vectors after math is unreliable. Use `is_equal_approx`, or compare against a tolerance scaled to inches (e.g. 0.01 u).
  - The engine's `is_equal_approx`/`is_zero_approx` use a small internal epsilon meant for about unit-sized values. For inch-scale positions in the thousands, write an explicit tolerance (inferred).
- Rendering precision (triplanar, world-space shader coordinates) only matters with double builds. See the rendering page.

## Interpolating between ticks

Doc: `tutorials/math/interpolation.rst`, `tutorials/physics/interpolation/physics_interpolation_introduction.rst`

- Linear interpolation: `a + (b - a) * t`. Use `lerp`, `Vector3.lerp`, `Transform3D.interpolate_with`, `Basis.slerp`, and `Quaternion.slerp` (never slerp Euler angles; `using_transforms.rst` shows why they take the long way round and gimbal-lock).
- For angles as floats use `lerp_angle(from, to, weight)`, and `angle_difference(from, to)` (returns a value in [-PI, PI]). For a yaw in degrees, wrap with `wrapf(value, -180.0, 180.0)` (min inclusive, max exclusive).
- The tick fraction for drawing is `DrawClock.fraction()` here: Godot's `Engine.get_physics_interpolation_fraction()` taken on by the wall clock to when the frame is drawn (see `main-loop.md`). Interpolating between the previous and current tick shows the world 1 to 2 ticks in the past, which the physics interpolation intro says outright.
- `lerp(current, target, k * delta)` "smoothing" is frame-rate dependent as written in the tutorial. Keep it to visual-only code (inferred: `1 - exp(-k * delta)` makes it frame-rate independent, which `Ragdoll` uses for joint friction).

## Class notes

**Vector3** (`classes/class_vector3.rst`)

`x`, `y`, `z` (float32); constants `ZERO`, `ONE`, `INF`, `UP`, `DOWN`, `LEFT`, `RIGHT`, `FORWARD (0,0,-1)`, `BACK (0,0,1)`, `MODEL_FRONT (0,0,1)`, `MODEL_REAR`, `MODEL_LEFT (1,0,0)`, `MODEL_RIGHT (-1,0,0)`, `MODEL_TOP`, `MODEL_BOTTOM`. Key methods: `dot`, `cross`, `length`, `length_squared`, `normalized`, `is_normalized`, `distance_to`, `distance_squared_to`, `direction_to`, `angle_to`, `signed_angle_to(to, axis)`, `project`, `slide(n)`, `bounce(n)`, `reflect(n)`, `rotated(axis, angle)`, `lerp`, `slerp`, `move_toward`, `limit_length`, `snapped`, `snappedf`, `floor`, `round`, `abs`, `sign`, `clamp`, `clampf`, `min`, `max`, `minf`, `maxf`, `is_equal_approx`, `is_zero_approx`, `is_finite`, `max_axis_index`, `outer(with) -> Basis`, `octahedron_encode()`, `octahedron_decode(uv) static`.

**Vector3i** (`classes/class_vector3i.rst`)

int32 components. `Vector3i(Vector3)` truncates toward zero. `%` uses truncated division. Ordering compares X, then Y, then Z.

**Basis** (`classes/class_basis.rst`)

Columns `x`, `y`, `z`; `from_euler(euler, order = 2) static`; `get_euler(order = 2)`; `looking_at(target, up, use_model_front) static`; `from_scale(scale) static`; `rotated`; `scaled`; `scaled_local`; `orthonormalized`; `inverse`; `transposed`; `determinant`; `get_scale`; `get_rotation_quaternion`; `slerp`; `is_orthonormal`; `is_conformal`; `IDENTITY`; `FLIP_X`, `FLIP_Y`, `FLIP_Z`. Stored row-major internally, exposed column-major.

**Transform3D** (`classes/class_transform3d.rst`)

`basis`, `origin`; `affine_inverse`, `inverse` (orthonormal only); `interpolate_with(xform, weight)`; `looking_at`; `orthonormalized`; `rotated`/`rotated_local`; `scaled`/`scaled_local`; `translated`/`translated_local`; operators `*` with Transform3D, Vector3, AABB, Plane and PackedVector3Array; `IDENTITY`; `FLIP_*`.

**Quaternion** (`classes/class_quaternion.rst`)

`Quaternion(x, y, z, w)`; `Quaternion(axis, angle)`; `Quaternion(arc_from, arc_to)`; `Quaternion(Basis)` (orthonormal, else IDENTITY); `slerp`, `slerpni`, `spherical_cubic_interpolate`; `normalized`; `inverse`; `get_axis`, `get_angle`; `get_euler`, `from_euler` (YXZ); `angle_to` (noisy); `dot`; `exp`, `log`.

**AABB** (`classes/class_aabb.rst`)

`position`, `size`, `end`; `abs`, `grow`, `merge`, `expand`, `intersection`, `intersects`, `encloses`, `has_point`, `intersects_ray`/`intersects_segment` (Vector3 or null), `intersects_plane`, `get_support`, `get_endpoint`, `get_center`, `get_volume`, `has_volume`, `has_surface`, `is_equal_approx`, `is_finite`.

**Plane** (`classes/class_plane.rst`)

`normal`, `d` (also `x`, `y`, `z`); constructors above; `distance_to`, `is_point_over`, `has_point`, `project`, `intersects_ray`/`intersects_segment`/`intersect_3` (Vector3 or null), `normalized`, `get_center`.

**Projection** (`classes/class_projection.rst`)

A 4x4 of `Vector4` columns; `create_perspective(...) static`, `get_fov`, `get_fovy(fovx, aspect) static`, `inverse`, `get_projection_plane`. The camera's projection, and nothing else here.

**Geometry3D** (`classes/class_geometry3d.rst`)

A singleton. Segment and ray tests against spheres, cylinders, triangles and convex planes, closest points between segments, plane builders. See above.

**Node3D (math-relevant members)** (`classes/class_node3d.rst`)

`transform`, `global_transform`, `basis`, `global_basis`, `position`, `global_position`, `quaternion`, `rotation` (Euler radians; avoid for gameplay), `rotation_degrees`, `rotation_order = 2` (YXZ), `scale`, `top_level`; `look_at(target, up = UP, use_model_front = false)` (global space; target must not equal the position, up must not be parallel to the direction); `look_at_from_position`; `rotate(axis, angle)` (parent space); `rotate_object_local(axis, angle)` (local); `rotate_x`, `rotate_y`, `rotate_z`; `translate_object_local`; `global_rotate`; `global_translate`; `orthonormalize()`; `to_local`, `to_global`; `get_global_transform_interpolated()`.

## Where the code already does this

- `src/map/source_entities.gd:75-87`: `to_game(v) = Vector3(v.y, v.z, v.x)` and `to_game_yaw(yaw) = wrapf(yaw + 180, -180, 180)`, checked by `tests/run_dust2_checks.gd` against dust2's spawns.
- `src/map/map_importer.gd:23`: `SOURCE2_VIEWER_SCALE := 1.0 / 0.0254` (glTF metres to inches). Lines 232 and 369 hold the optional `rotate_z_up_to_y_up` (-90 degrees about X).
- `src/player/player_input.gd:186-203`: `aim_direction(yaw, pitch)` and `angles_from_direction(dir)` (pitch positive up, yaw 0 at -Z).
- `src/player/player_view.gd:226`: `Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD`. Line 283 slerps quaternions for the death camera. Line 434 sets `body.rotation.y = PI + yaw` for a model facing +Z.
- `src/combat/ragdoll.gd`: builds joint frames with `Basis(limb, y, limb.cross(y))`, poses bones with `affine_inverse()` and `interpolate_with`, uses `top_level = true` and `1 - exp(-k * delta)`.
- `src/map/brush_volume.gd:31-42`: point-in-convex through `Plane.distance_to` against each solid's outward faces.
- `src/map/map_importer.gd:534`: `(to_body * mesh_instance.global_transform) * mesh.get_faces()` bakes transforms into a PackedVector3Array in one multiply.
- `src/game/dropped_item.gd:132` and `dropped_item_view.gd:91-100`: `Basis.slerp` then `orthonormalized()`.
- `src/effects/muzzle_flashes.gd:340`: `flash.muzzle.basis.inverse() * gravity` (the general inverse, correct for a possibly scaled basis).
- `src/sim/sim_clock.gd`: simulation time in integer microseconds, not in floats.

Looks at odds, or worth a second look (not verified):

- `src/map/map_importer.gd:232,369`: `rotate_z_up_to_y_up` maps Source `(x, y, z)` to `(x, z, -y)`, while `SourceEntities.to_game` uses `(y, z, x)`. The two differ by a 90-degree yaw, so (inferred) a map imported with the toggle on would put entities (spawns, bomb sites, buy zones) in the wrong place. The toggle is off by default, and the Source 2 Viewer export doesn't need it.
- `src/effects/muzzles.gd:60` names `METRE := 0.0254` (metres per inch), and `src/combat/bullet_impacts.gd:67` names `METRE := 39.37` (inches per metre). The same name holds reciprocal values in two files. The code may well be right in each place, but it's easy to copy the wrong one.

## Not covered here

- Béziers and curves: `tutorials/math/beziers_and_curves.rst`, `classes/class_curve3d.rst`.
- Random numbers (seeded spread and recoil need `RandomNumberGenerator` with an explicit seed for determinism): `tutorials/math/random_number_generation.rst`, `classes/class_randomnumbergenerator.rst`.
- 2D types: `Vector2`, `Transform2D`, `Rect2`.
- `Vector4`, `Vector4i`, and `Projection` in depth.
- Skeleton bone-pose math (`Skeleton3D.get_bone_global_pose`, `set_bone_global_pose`): see the animation page and `classes/class_skeleton3d.rst`.
- Camera ray projection (`Camera3D.project_ray_origin`, `project_ray_normal`, `unproject_position`): `classes/class_camera3d.rst`, `tutorials/physics/ray-casting.rst`.
- Shader-side world coordinates with double precision: `tutorials/physics/large_world_coordinates.rst` (Limitations).
- Import-time axis and scale settings for glTF: `tutorials/assets_pipeline/importing_3d_scenes/`.
