# Hitboxes for shots (2026-09-28, built 2026-09-29)

What a round pays for the hitboxes before it is traced, and what was done
about it without changing what any round meets. Sid chose this as the next
work toward every frame under 6 ms with nine bots
(`box3d-walking-hitch-2026-09-28.md`, "The worst ticks are shots").

**Nothing covered this as a design before.** The project's pages had the
measurement and two ideas in a paragraph each, the older plan for
hitboxes posed by the tick and kept as history (`systemization.md`, finding
8 and step 3.3), and what CS2 does (`combat.md` section 4,
`hitboxes-aim.md`). This page is the research and the design; it changes
nothing about where or when a body is posed, which stays step 3.3's.

## What a round cost, inside the tick

Measured with a stopwatch put into the code for the measuring and taken
out again, headless, in dust2's seeded match (nine bots with money, fifty
seconds, the second play), the bots thinking in turn. 30 of the players'
runs fired a round.

| A player's run that fires a round, on main | A run | Each |
|---|---:|---:|
| The whole run | 1,545 us (95th 2,972, worst 4,140) | |
| A run that fires none | 112 us | |
| Hitboxes looked over before a ray that can meet one (1.2 such rays a run) | 1,002 us | 835 us a ray |
| The native rays: the nearest, what holds the start, every hit | 45 us | 5, 6 and 19 us |
| The gun fired: spread, recoil | 46 us | |
| Those told of the round: the hole, the body's kick | 31 us | |
| The damage dealt, a round in every 2.5 meeting someone | 229 us | 573 us |
| The damage dealt when it kills | | 1,766 to 3,147 us |

Of 190 hitboxes a ray with three dead compared 176 on average and moved
131 of them (the dead are passed over before they are compared): 4 us for
each one moved, 1 us for each one not.

| The tick's end | |
|---|---:|
| Nothing fired | 351 us |
| A round fired | 381 us |
| A death | 1,435 us (worst 1,846) |

So two thirds of a round was the hitboxes looked over. A round's own rays
are 45 us: the longer way a ray takes when it starts inside the shooter's
own head is 25 us, not worth a design. And a kill is 2 to 3 ms in the
shooter's run and 1.1 ms more at the tick's end, which is more than the
hitboxes and is the next work after this.

## How it was

- A player's 19 capsules are `Hitbox` areas under a `SkinnedHitboxes`
  node, a child of the player. They are put where the bones are by
  `SkinnedHitboxes.follow`, on the skeleton's update, which is a frame's
  and not the tick's. Between two of those they ride the player's node:
  the player never turns (the model does), so they move by what the hull
  moves and no other way.
- Their layer goes to 0 at a death (`HitTarget.set_active`) and back at a
  revival. A side swap takes them out of the tree and builds others.
- The bridge keeps a proxy for each and, for every ray with the hitbox
  layer in its mask, compared every hitbox's place and layer with what it
  last put, and moved those that differed (`Box3DQueries._sync_group`).
  Nothing told it of a change; it found them all by looking.
- Only a round asks (`Hitscan.trace`: its ray, and one through each wall
  it goes into). Rounds are fired in a player's run, after its move, in
  the open tick and outside any scope.

## What was built

**A body's hitboxes are a set, and the bridge brings a set up to date only
for a ray that could meet it** (`Box3DQueries._sync_sets`).

1. **A set counts its changes.** `SkinnedHitboxes.changes` goes up by one
   whenever its capsules are put somewhere (`follow`), one goes on or off
   its layer, or the set is built or cleared. It also keeps how many of
   its capsules are on their layer (`on_layer`). A hitbox's layer is set
   through `Hitbox.set_on_layer` and nowhere else, which tells its set;
   `HitTarget.set_active` and `SkinnedHitboxes.set_active` go through it.
2. **The bridge knows each hitbox's set**: the `SkinnedHitboxes` it is a
   child of, found when the hitbox is registered. A hitbox with none (the
   four stand-in boxes a body wears without the extracted model, a bare
   `HitTarget` in a check) is looked over by every ray, as all were.
3. **For each set the bridge keeps** what it last put: the set's count
   then, where the set's node was then, whether any of it was on its
   layer, and the box that holds the proxies where it put them.
4. **A ray in an open tick, for each set:**
   - A set the ray leaves out whole (its shooter's own) is left as it is.
   - The count and the node's place as they were when the proxies were
     put: the proxies are where the capsules are. Nothing to do.
   - None of its capsules on their layer, and its proxies put off theirs:
     nothing of it can be met. Nothing to do, and nothing measured, though
     a dead body's count goes up every frame its ragdoll poses it.
   - If the line passes the box its proxies were put in, and any of them
     is on its layer, the set is brought up to date.
   - Else, if any capsule is on its layer, the box the capsules are in
     now is measured: from each of the set's hitboxes as the bridge has
     them, its place and a ball about it that holds all its shapes (half
     a capsule's whole height), grown by half a unit (`SET_MARGIN`). It is
     measured once for a count, kept from the set's node's place, and
     carried with the node after, which only moves. If the line passes
     it, the set is brought up to date.
   - A set is brought up to date by each of its hitboxes being compared
     and moved as the look-over did (`sync_object(hitbox, false)`), those
     off their layer and put so passed over as it passed them.
5. **What was put of a set is not known** when the bridge has never put
   it, when it gains a hitbox, when a shape of it changes, and whenever
   any of its hitboxes is put other than as part of the set: by a scan
   (the world's statics taken in again, which the range does when its
   cover changes), by a node taken in from those waiting, by a hitbox
   published by hand, by the look-over outside a tick. A set not known
   is brought up to date whatever the line.
6. **Outside a tick nothing is taken on trust**, as with the hulls: every
   hitbox is looked over. The checks that move a bone or a body by hand
   and fire do so outside a tick.
7. **Anything but a ray** that asks with the hitbox layer in an open tick
   brings every changed set up to date. Nothing in the game does.
8. **While the bridge is reading** (the bots thinking on threads) nothing
   is brought up to date, as before; no round is fired then.
9. **A hitbox's proxy stands just where its capsule does.** A proxy used
   to be left where it was when that was nearly where it should be (the
   comparison's tolerance, 0.015 units at 1,500 from the map's middle), so
   where it stood depended on which rays had moved it. With fewer rays
   moving it that would have differed from before; now it depends on the
   capsule alone. The hulls' and the world's proxies are as they were.

What it does not do is publish anything eagerly. Bringing 190 proxies up
to date every tick, or every frame from `follow`, was what the bridge did
until 26 September and was the largest saving when it stopped
(`box3d-performance-fixes-2026-09-26.md`); most ticks have no round in
them.

## Why a round meets what it met

A ray's answer is the nearest proxy on its line that is on its layer and
not left out. While a set is known, only its own bringing up to date moves
its proxies. A proxy on its layer is on the line only if the line passes
the box its set's proxies were put in, and then the set is brought up to
date before the ray is asked. A capsule that ought to be on the line is in
the box its set's capsules are in now, and then too the set is brought up
to date. So every proxy the ray can meet is where its capsule is, which is
all the look-over of 190 gave it.

| What could break that | Held by |
|---|---|
| A capsule moved or put off its layer with its set not told | Everything in the game that does goes through `follow`, `Hitbox.set_on_layer`, `build` or `clear`; the oracle below finds one that does not |
| The hull moved by hand in a tick (the range's dummy at its respawn, a bot to its route's start) | The set's node's place is compared at every ray |
| A body rebuilt in a tick (a side swap at the tick's end) | The old hitboxes leave the tree and their proxies go at once; the new are new to the bridge, in a new set, not known |
| The world scanned again in a tick | Point 5: the set is not known |
| The box too small | It is measured from the capsules, not guessed from the hull: a revived body's capsules where its ragdoll left them, a bot's where it was drawn, a foot planted under the floor are all in it; and it is half a unit larger all round than they are, for the native world's single precision |
| The shooter's own set not brought up to date | What the ray meets of it is passed over, and Box3D's list of every hit on a ray is nearest first (v0.4.3: 40 lists of 8 to 12 hits, the shapes made in no order), so what is met after it is what would have been |

Two things are not as they were, both under what a player could tell.
A hitbox's proxy stands where its capsule is and no longer within 0.015
units of it (point 9). And of two proxies met at the same single-precision
fraction of a ray, which one Box3D gives is settled by the order of its
tree, which follows every move made of every proxy and so is not what it
was with 190 moved at every ray; the hulls' sweeps share that tree. Neither
changed anything in 308 rounds written out and compared (below).

## How it is checked

- **An oracle, on in every check file** (`Box3DQueries.check_sets`, turned
  on by `tests/check_suite.gd`): for each ray in a tick that can meet a
  hitbox, what it met is compared with the nearest capsule, box or ball
  on its line worked out in script from the hitboxes' own nodes, every
  one of them, the proxies not asked. A hitbox met where none is, or one
  passed that was on the line before what was met, is counted, and a
  check file with any counted has failed. It allows a twentieth of a unit
  either way, and says nothing of a ray that begins on a hitbox's skin.
  On main's code, before anything was changed, it bore out every one of
  the 326 rays of the bots' fight. In the whole suite it holds 546 rays
  in 12 files.
- **The same games before and after**: dust2's seeded match at five a side
  (30 rounds) and at ten (115), and the bots' fight (163), written out on
  main and on this: every player at every tick (where, facing, rounds
  fired, health, money, gun, the view's kick) and every round with what it
  met, where, through how many walls and how far. The same, byte for byte,
  all three.
- **`tests/run_hitbox_set_checks.gd`**, in a tick, on the native world,
  bodies made of a hull, two bones and a capsule on each: a body moved by
  hand is met where it stands and not where it stood; one no round comes
  near is left as it was put; someone killed in the tick is passed and
  whoever stands behind is met, and revived is met again; bones followed
  in the tick; a side swap's new set; the shooter's own set left as it was
  and met by the next shooter; the world scanned again. And that the
  oracle holds the rule: a capsule moved with its set not told is met
  where it was, and is counted, both ways.
- The whole suite with the extracted assets: 4,409 checks in 60 files, all passed.

## What it saves

main and this timed by the same script, alternated, in dust2's seeded
match, headless, nothing put into the code (the second play of each run).

| Five a side, three runs of each | main | With the sets |
|---|---:|---:|
| A player's run that fires a round, mean | 1.43, 1.60, 1.49 ms | 0.92, 0.75, 0.77 ms |
| its median | 1.18, 1.26, 1.25 ms | 0.56, 0.49, 0.50 ms |
| A tick with a round in it | 3.30, 3.48, 3.40 ms | 2.87, 2.61, 2.59 ms |
| The tick, mean and 99th | 1.67 and 2.92 ms | 1.69 and 2.80 ms |
| Ticks over 6 ms, of 3,200 | 1 | 1 or 2 |

| Ten a side, two runs of each | main | With the sets |
|---|---:|---:|
| A player's run that fires a round, mean | 2.17, 2.56 ms | 0.83, 0.97 ms |
| A tick with a round in it | 6.20, 6.85 ms | 4.89, 5.30 ms |
| The tick's 95th and 99th | 5.35 and 6.48, 5.69 and 7.25 ms | 5.03 and 5.75, 5.38 and 6.31 ms |
| Ticks over 6 ms, of 3,200 | 62, 113 | 16, 49 |

An earlier pair of runs at ten a side, of the code before the last two
changes, had 170 and 85 ticks over 6 ms on main and 18 and 18 with the
sets. The machine's state moves these by a tenth between runs; the
difference between the columns is what holds.

By the stopwatch, with the sets, on a machine a fifth slower that hour (a
run that fired none was 146 us): the hitboxes brought up to date are 305
us of a run that fires where they were 1,002, of which the boxes measured
are 83 (8 sets at 10 us) and the one set put 170. The worst-ticks profiler
asks its rays in the tick now: 116 us the first that can meet a hitbox,
51 us the same again, 12 us one that meets the world alone.

A round fired is 0.6 to 0.7 ms less with ten players and 1.3 to 1.6 ms
less with twenty, since what is looked over no longer grows with the
players. The ticks over 6 ms with ten players are the kills, which this
does not touch.

## What a review of the design found

Three reviewers, one for what a round meets, one for everything that
changes a hitbox and when, one for the cost and the checks, each claim
then tried against the code by another (2026-09-29; 21 claims, 10 held).

| Held | What was done |
|---|---|
| A proxy left where it was when that is nearly right makes its place depend on which rays moved it | Point 9 |
| The boxes need a margin: a proxy may stand a hair from its capsule | `SET_MARGIN`, half a unit, which covers the tolerance to 1,270 m from the middle |
| A scan puts hitboxes outside their set's bringing up to date (found by two) | Point 5, and a check |
| Equal fractions are settled by the tree's order | Written down above; not to be had without redoing every move |
| A dead body's set would be measured every tick (found by two) | Point 4's third case |
| The measuring harness does not pose the dead | True of every harness here; a dead set costs a comparison either way |
| The cost profiler's bridge would count the sets' work as the ray's | `scripts/profile_box3d_costs.gd` counts and times the sets |
| The worst-ticks profiler asked its rays after the tick | It asks them in it |
| The table's 211 and 157 had no unit | Given above |

## Left for after

- **What a death costs** (2 to 3 ms in the shooter's run, 1.1 ms at the
  tick's end): to be measured apart and taken down next. It is what the
  ticks over 6 ms are.
- The sets looked at for a ray that changes nothing are 4 us each (51 us
  a ray with ten): a list in place of a dictionary's values, if it shows.
- The box measured in `follow` rather than at the ray, if the 10 us a set
  it costs a tick's first round shows; it would cost every frame.
- Hitboxes posed by the tick and kept as history (systemization step
  3.3), which will replace the hitbox node as where a capsule is: a set's
  count and box are of whatever puts the capsules.
