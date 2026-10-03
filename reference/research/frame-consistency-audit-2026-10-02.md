# Where the slow frames come from, and what to cut: 2 October 2026

Sid's target is every frame under 6 ms with nine bots, every second. On
main at 8414b1b the mean is 5.07 ms and no second of play has every frame
under 6 ms. This page finds which frames are slow and why, then ranks
what to cut. It is an audit: nothing in the game is changed by it. The one
change it makes is to `scripts/profile_worst_ticks.gd`, which overstated a
kill's tick (below).

Godot 4.7.2, Vulkan Forward+, an AMD Ryzen 7 7800X3D and an RTX 4070 Ti.
"Measured" means one of the runs below. "Estimated" means the operations
in the code were counted; those figures need a measurement before anyone
relies on them.

## What was measured

- **Sid playing** competitive dust2 with nine bots at 1080p, 2 October
  2026, through `scripts/watch_game.gd`: 200 seconds, 38,090 frames, with
  every frame split into its parts (`reference/performance.md`, "Where the
  rest of a frame goes"). The seconds cover warmup, freeze time, live
  rounds and round ends.
- **Headless, by system:** `scripts/profile_dust2.gd -- 5 6 round --physics
  box3d --skip-single-operations`, six five-second windows through a
  round.
- **The worst ticks:** `scripts/profile_worst_ticks.gd`, the seeded match,
  run once as it was and then twice with a stopwatch in the shot's path
  (`PlayerSim._try_shoot`, `Hitscan.fire_as`, the victim's hit and death).
  The stopwatch was not committed.
- **The code:** four read-only reviews, one each for the bodies and their
  animation, the effects, HUD and audio, the tick, and hitches and the
  draw. Their findings are below, ranked against the measurements.

## Quiet play is steady; events make the slow frames

With nothing happening, a frame is steady at about 4.6 ms. Frames that
hold a tick run the tick (1.6 to 1.8 ms) and skip the bodies nobody sees.
Frames without a tick step those bodies (about 2 ms of scripts and 0.9 ms
of skeletons). Both kinds come out the same.

The slow frames come with shots, deaths, spawns and buys. Each second of
Sid's play, grouped by what happened in it:

| Seconds | Count | Mean frame | Slowest frame, median | Slowest tick, median | Seconds with a frame of 8 ms or more |
|---|---|---|---|---|---|
| No shots, no deaths | 123 | 4.88 ms | 8.2 ms | 2.2 ms | 55% |
| Shots, no deaths | 47 | 6.06 ms | 10.6 ms | 2.8 ms | 85% |
| A death | 30 | 6.75 ms | 13.2 ms | 4.1 ms | 100% |
| Buying | 15 | 5.41 ms | 11.2 ms | 5.2 ms | 100% |
| Spawns | 20 | 5.97 ms | 12.6 ms | 5.5 ms | 100% |

Shooting raises the mean of a whole second by 1.2 ms, so it is a cost
that lasts, not only a spike.

In the 1,670 frames of 8 ms or more, the time over a normal frame was:

| Part of the frame | Excess over a normal frame, summed | Frames where it was the biggest excess |
|---|---|---|
| The frame's scripts | 4,107 ms | 923 |
| The tick | 2,782 ms | 613 |
| The draw's CPU | 1,006 ms | 89 |
| Deferred calls | 501 ms | 23 |
| Skeletons fitted | 125 ms | 0 |

A slow frame without a tick still runs about 5 ms of scripts, against
1.6 ms normally. This happens even with nobody in view.

## The frame's scripts in a fight

Headless, in the window with five bot shots, these were the largest calls:

| What | Mean a frame | Largest call |
|---|---|---|
| `hit_effects.gd` | 0.25 ms | 4.56 ms |
| `shot_effects.gd` | 0.05 ms | 1.27 ms |
| `game_hud.gd` | 0.19 ms, every frame, plus 0.035 ms a tick | 0.55 ms |
| `player_model.gd` | 0.65 to 0.71 ms | 0.59 ms |
| The skeletons posed | 0.66 ms | 0.42 ms |

The HUD was 0.08 ms a frame on 23 September and is now 0.19 ms. The hit
particles are a GDScript interpreter. It costs 2.5 ms a frame at eight hit
pairs a second ([the hit-effects page](hit-effects-performance-2026-10-02.md)),
about 18 µs per live particle.

## A shot and a kill on the tick

In the seeded match, timed inside the shot:

| Span | Calls | Mean | Largest |
|---|---|---|---|
| The trace, meeting no body | 42 | 0.25 ms | 0.64 ms |
| The trace, meeting a body | 16 | 0.45 ms | 1.90 ms |
| Damage dealt, the victim living | 12 | 0.04 ms | 0.05 ms |
| Damage dealt, the victim dying | 4 | 0.69 ms | 0.87 ms |
| of it, the death (`PlayerSim._on_hit_target_died`) | 4 | 0.60 ms | 0.78 ms |
| `weapon.fire`, the events sent, the shot's listeners | each | 0.01 to 0.03 ms | |

A trace pays for the hitbox sets being brought up to date at its first
ray that can meet a hitbox. That was 112 µs in the same match, against
51 µs for the same ray again and 12 µs for a ray that meets only the
world. A wall it goes through adds more rays.

`profile_worst_ticks.gd` runs no frames. So the bodies players die into,
which the game makes ahead on frames (`GameWorld._process`), were built on
the tick at each death, and a death measured 2.0 ms. It now makes them
before each tick, out of the tick's time, as the game does. A kill's run is
then 1.1 to 1.6 ms, as it was after
[the death's fix](death-on-the-tick-2026-09-29.md). Kills have not got
worse since 29 September.

## What to cut, in order

The order weighs what Sid's play showed (fights and spawns) over what is
cheapest. The first column says whether the work needs Sid's machine
(**Local**: the game drawn, or Sid's eyes) or can be done by a cloud
thread with headless checks (**Remote**).

### In fights: the frame

1. **Hit particles evaluated wherever they are.** Remote, then Local to
   see it.
   - **Where:** `src/effects/hit_particles.gd`, `HitParticles.draw` (lines
     192-257).
   - **What happens:** every live particle is evaluated every frame,
     anywhere on the map. The authored `max_distance` is only checked after
     the position is worked out, and most child layers have none. The
     batches' AABB is huge, so the GPU culls nothing either.
   - **The fix:** at spawn, give each effect a bounding sphere from its
     speed, gravity and life. Test it against the camera's frustum once per
     effect per frame (`PlayerView.any_box_in_view` does the same test), and
     apply the root's `max_distance`. Keep advancing every particle, so
     what lands is unchanged. Never cull screen effects.
   - **Expected:** most of the cost of fights away from you. That share is
     unmeasured; count live and drawn particles in `watch_game.gd` first.
2. **The particle interpreter itself.** Remote.
   - **Where:** `hit_particles.gd` and `hit_quads.gd`.
   - **What happens:** about 18 µs per particle (measured). About 60% is the
     per-renderer card building and batch lookup by string key, and about
     25% is the attribute operations, matched by String each time.
   - **The fix:** port drawing and spawning into the native library, as the
     movement's step was, with the script kept as the reference and a check
     holding the two to the same card buffers.
   - **Expected:** about 0.3 to 0.5 µs per particle-renderer (estimated), so
     2.5 ms at eight pairs a second becomes about 0.1 ms.
   - **A smaller step first, in GDScript:** typed particles, int enums for
     the operations, curve tables, and the batch held directly rather than
     found by key, for about half the cost (estimated). Spawning can also
     stop scanning every key of the layer per particle for array-valued
     curves: one layer of 95 has one.
3. **Every decal's fade set every frame.** Remote.
   - **Where:** `src/combat/bullet_impacts.gd:148-160` sets `modulate` on every
     visible hole (up to 96) every frame. `src/effects/hit_effects.gd:285-296`
     does the same on every splat (64), hidden ones included.
   - **What happens:** each set is a RenderingServer call. That is free
     headless and real when drawn, which fits the new code costing more drawn
     than headless.
   - **The fix:** touch only decals inside their fade window, and only when
     their alpha changes.
   - **Expected:** 0.3 to 0.5 ms a frame once the pools fill (estimated).
4. **The MultiMeshes' bounds worked out on every upload.** Remote.
   - **Where:** `effect_quads.gd:160`, `hit_quads.gd:95`, `hit_models.gd:42`
     and `grenade_view.gd:264` set `GeometryInstance3D.custom_aabb` on the
     node.
   - **What happens:** the MultiMesh docs say only the resource's own
     `custom_aabb` "prevents costly runtime AABB recalculations". So every
     `buffer =` recomputes over the whole capacity.
   - **The fix:** one line each, `multimesh.custom_aabb = ...`. Also correct
     `reference/godot/rendering.md`, which says either property avoids it.
5. **Body wounds and sound voices made and freed per hit.** Remote.
   - **Wounds** (`src/effects/body_wounds.gd`):
     - a Decal is made per hit;
     - `find_children` searches each model per pellet;
     - every mark is placed again every frame, and again at every skeleton
       fit.
     - **Fix:** pool 48 decals, hang each under its body's skeleton, and
       cache each model's receiver.
   - **Voices** (`src/audio/sound_events.gd:400-422, 488-499`):
     - an AudioStreamPlayer is made and freed per voice.
     - **Fix:** pool them, as `WeaponSounds` and `BulletImpacts` already do.
   - **Expected:** 0.1 to 0.6 ms a frame in fights, and 30 to 300 µs per
     hit (estimated).

### Spawns, buys and round starts: the tick

6. **A respawn poses its body on the tick, from scratch.** Remote.
   - **What happens:** a death turns the body's AnimationTree off
     (`PlayerModel.set_animating`, `player_model.gd:1373-1383`). The respawn
     turns it on and steps it once (`pose_again`). That step is 2 to 3 ms a
     body (`reference/godot/animation.md`, Skeleton3D).
   - **When:** in warmup, every respawn's tick. At a round start, every dead
     player's in one tick. Sid's seconds with spawns had a median slowest
     tick of 5.5 ms.
   - **The fix:**
     - (a) the hand-stepped tree stays active through the death, with
       `is_animating` kept on a flag of the model's own;
     - or (b) pose the waiting bodies on frames during freeze time, one a
       frame, when nobody can fire.
     - First confirm with a stopwatch round `pose_again` whether the cost is
       the reactivation or a new item's clips.
   - **Determinism:** (b) leaves every tick's hitboxes as they are; (a) may
     change clip phases after a respawn.
7. **The first step after a body takes a new kind of item.** Remote.
   - **What happens:** `PlayerModel._add_set` adds the item's clips to the
     body's library on the tick. The next step rebuilds the tree's caches,
     2 to 3 ms a body (the same page). Bots buying on one tick put several
     in one frame. Sid's seconds with buys had a median slowest tick of
     5.2 ms.
   - **The fix:** add every set the body's side can hold when the body is
     built (`prepare_holding` has them ready), so the library never changes
     in play. Then measure whether the larger library costs every step.
8. **A trace brings every hitbox set up to date.** Remote.
   - **What happens:** the trace costs 0.25 ms when it meets no body and
     0.45 ms when it meets one (measured, above). Most of it is the sets'
     19 hitboxes each put through the generic object sync, every set
     scanned through string-keyed records, and the exclude list rebuilt
     (`src/physics/box3d_queries.gd:295-346`).
   - **The fix:** bring up to date only the sets whose box the ray's segment
     passes; hold the sets in typed arrays; write each hitbox's place
     straight from `SkinnedHitboxes.follow`; keep the shooter's exclude list
     per body.
   - **Checks:** the `check_sets` oracle holds what is met.
9. **The use prompt searches every dropped item every tick.** Remote.
   - **What happens:** `src/ui/game_hud.gd:216-219` goes through
     `src/game/use_search.gd`, about nine box tests per item. Warmup leaves
     every death's items on the ground, so it grows: about 0.5 ms with 20
     items (estimated).
   - **The fix:** drop items more than about 160 units from the eyes before
     the tests. The result is identical, since nothing further can be
     picked or block a pick.
10. **Ragdolls stepped on the tick.** Remote.
    - **What happens:** a falling body adds floor rays and the shared native
      step's four collision steps to every tick for 2 to 3 s. Nothing the
      simulation asks meets a ragdoll (layer 16, world-only mask); only the
      death camera reads one.
    - **The fix:** a Box3D world of their own, stepped from frames.
    - **Determinism:** guns and ragdoll parts cannot touch, so where guns
      land should not change. Confirm with the seeded match.
11. **Freeze time ends with every bot asking for a path.** Remote.
    - **What happens:** two paths are given out a tick, at about 0.5 ms
      each, for roughly five ticks.
    - **The fix:** let bots search during freeze, when they don't move.
12. **The side swap rebuilds every body in one tick.** Remote.
    - **What happens:** about 30 to 55 ms, twice a match (estimated, from
      2.6 ms a body).
    - **The fix:** build each player's other-side body ahead, one a frame,
      during the half's last round, and swap it in at the tick.

### Frames, everywhere

13. **The map's visibility on a cluster change.** Remote, then Local to
    count.
    - **What happens:** `src/map/world_visibility.gd:249-276` marks every
      mesh again when the camera enters another cluster. It costs 0.4 to
      2.9 ms of script (`reference/performance.md`), plus the draw's update
      of every instance it flips. Standing on a cluster's edge flips it
      back and forth.
    - **The fix:**
      - keep a count per mesh of the visible clusters that hold it;
      - walk only the clusters whose bit changed;
      - flip only meshes whose count crosses zero;
      - optionally, hold hides a few frames.
    - **Measure first:** count cluster changes in `watch_game.gd` and line
      them up with the slow frames that hold no tick.
14. **Bodies off screen still twist, aim their eyes, relight and move
    wounds.** Remote.
    - **Where:** `twist_modifier.gd:103-118`, `rig_model.gd:343-345`, and
      `bot.gd:358-359` with `rig_model.gd:381-395`.
    - **The fix:** gate them on `PlayerModel.is_seen()`.
    - **Expected:** 0.15 to 0.25 ms a frame (estimated).
15. **Seen bodies far away animated every frame.** Local, a look call.
    - **What happens:** a body on screen steps and fits in every frame,
      ticks included: about 165 µs each.
    - **The fix:** below about 60 to 80 pixels tall, step as unseen bodies
      do, skipping frames that hold a tick.
16. **The skeleton modifiers look bones up by name every fit.** Remote.
    - **What happens:** about 1,300 fits a second. FootPlant and HandGrip
      call `find_bone` about 27 times a fit.
    - **The fix:** cache the indices against `Skeleton3D.get_version()`;
      later, port the modifiers to native code. They move hitboxes, so the
      port would hold to the bit, as the movement does.
17. **The HUD.** Remote.
    - **Team counter:** `src/ui/team_counter.gd:207-257` builds ten Cards
      every frame and redraws everything when the clock changes, once a
      second, which lands in every second's slowest frame.
    - **What the HUD gathers:** `game_hud.gd:222-279` gathers its state every
      frame, though it changes only on ticks.
    - **Kill feed:** its rows are laid out three times per redraw while they
      fade.
    - **Fixes:** give the clock its own surface; gather only when the tick
      or the second changes; cache each row's layout.
18. **A smoke's cloud rebuilt every frame.** Remote.
    - **What happens:** `src/grenades/grenade_view.gd:143-163` runs up to
      1,600 voxels and uploads 77 KB a frame for 18 s.
    - **The fix:** rebuild only when `SmokeVoxels` changes.
    - Bots throw nothing yet, so only Sid's smokes cost this today.

### To measure before choosing

- **Decal atlas.** Whether Godot rebuilds its decal atlas when a texture
  comes back into use (engine source, unverified). An A/B with every decal
  texture held by a hidden decal from load would settle it, with render
  time in the slow frames compared.
- **More in `watch_game.gd`.** Count live and drawn particles, decals
  touched, cluster changes, and fits made at a tick's start. Name
  `bullet_impact` and `player_hurt` in the slow frames' lines, which
  `UNTOLD` leaves out.
- **`scripts/profile_hits.gd`.** Add a phase with full hole, splat and
  wound pools, and one with the impacts off screen.

## Found in passing

Your own hitbox body never grips its gun. `PlayerModel.show_held` is
called for the bots' bodies (`bot.gd:357`) and your shadow
(`player_view.gd:560`), never for `PlayerSim.model`. So its `held_weapon`
stays empty, `grips_gun()` is false, and its arm hitboxes are posed
without HandGrip, unlike every bot's.
