# Hitboxes for shots (2026-09-28)

What a round pays for the hitboxes before it is traced, and the design
that takes it down without changing what any round meets. Sid chose this
as the next work toward every frame under 6 ms with nine bots
(`box3d-walking-hitch-2026-09-28.md`, "The worst ticks are shots").

**Nothing covered this as a design before.** The project's pages had the
measurement and two ideas in a paragraph each, the older plan for
hitboxes posed by the tick and kept as history (`systemization.md`, finding
8 and step 3.3), and what CS2 does (`combat.md` section 4,
`hitboxes-aim.md`). This page is the research and the design; it changes
nothing about where or when a body is posed, which stays step 3.3's.

## What a round costs, inside the tick

Measured with a stopwatch put into the code for the measuring and taken
out again, headless, in dust2's seeded match (nine bots with money, fifty
seconds, the second play), the bots thinking in turn. 30 runs fired a
round.

| A player's run that fires a round | A run | Each |
|---|---:|---:|
| The whole run | 1,545 us (95th 2,972, worst 4,140) | |
| A run that fires none | 112 us | |
| Hitboxes looked over before a ray that can meet one (1.2 such rays a run) | 1,002 us | 835 us |
| of them compared, and moved | 211 and 157 | |
| The native rays: the nearest, what holds the start, every hit | 45 us | 5, 6 and 19 us |
| The gun fired: spread, recoil | 46 us | |
| Those told of the round: the hole, the body's kick | 31 us | |
| The damage dealt, a round in every 2.5 meeting someone | 229 us | 573 us |
| The damage dealt when it kills | | 1,766 to 3,147 us |

| The tick's end | |
|---|---:|
| Nothing fired | 351 us |
| A round fired | 381 us |
| A death | 1,435 us (worst 1,846) |

So two thirds of a round is the hitboxes looked over, 4 us for each one
moved and 1 us for each one not. A round's own rays are 45 us: the longer
way a ray takes when it starts inside the shooter's own head is 25 us, not
worth a design. And a kill is 2 to 3 ms in the shooter's run and 1.1 ms
more at the tick's end, which is more than the hitboxes and is the next
work after this ("What a death costs", to be measured apart).

The figures in the worst-ticks profiler (843 us, 202 us again) were of a
ray asked after the tick; these are of rounds in it.

## How it is now

- A player's 19 capsules are `Hitbox` areas under a `SkinnedHitboxes`
  node, a child of the player. They are put where the bones are by
  `SkinnedHitboxes.follow`, on the skeleton's update, which is a frame's
  and not the tick's. Between two of those they ride the player's node:
  the player never turns (the model does), so they move by what the hull
  moves and no other way.
- Their layer goes to 0 at a death (`HitTarget.set_active`) and back at a
  revival. A side swap frees them and builds others.
- The bridge keeps a proxy for each and, for every ray with the hitbox
  layer in its mask, compares every hitbox's place and layer with what it
  last put, and moves those that differ (`Box3DQueries._sync_group`).
  Nothing tells it of a change; it finds them all by looking.
- Only a round asks (`Hitscan.trace`: its ray, and one through each wall
  it goes into). Rounds are fired in a player's run, after its move, in
  the open tick and outside any scope.

## The design

**A body's hitboxes are a set, and the bridge brings a set up to date only
for a ray that could meet it.**

1. **A set counts its changes.** `SkinnedHitboxes.changes` goes up by one
   whenever its capsules are put somewhere (`follow`), go on or off their
   layer, or are built or cleared. A hitbox's layer is set through
   `Hitbox.set_on_layer`, which tells its set; `HitTarget.set_active` and
   `SkinnedHitboxes.set_active` both go through it.
2. **The bridge knows each hitbox's set**: the `SkinnedHitboxes` it is a
   child of, found when the hitbox is registered. A hitbox with none (the
   four stand-in boxes, a bare `HitTarget` in a check) is looked over as
   now.
3. **For each set the bridge keeps** what it last put: the set's count of
   changes then, where the set's node was then, and the box that holds
   the proxies where it put them.
4. **A ray in an open tick, for each set:**
   - The count and the node's place as they were when the proxies were
     put: the proxies are where the capsules are. Nothing to do.
   - Else the box that holds the capsules now is wanted. It is measured
     from the capsules (each one's place, and a sphere of half its
     length) once for a count of changes, kept relative to the set's
     node, and moved with the node after that, which is exact since the
     node only moves.
   - If the ray's line passes the box the capsules are in now, or the box
     the proxies were put in, every hitbox of the set is brought up to
     date as now (`sync_object(hitbox, false)`), and the box and the
     count kept. If it passes neither, the set is left: none of its
     proxies is on the line, and none of its capsules would be.
   - A set never brought up to date in a tick, or one whose proxies the
     bridge moved by looking them all over, is brought up to date
     whatever the line.
5. **Outside a tick nothing is taken on trust**, as with the hulls: every
   hitbox is looked over as now, and every set is marked as not known.
   The checks that move a bone or a body by hand and fire do so outside
   a tick.
6. **Anything but a ray** that asks with the hitbox layer in an open tick
   brings every changed set up to date. Nothing in the game does today.
7. **While the bridge is reading** (the bots thinking on threads) nothing
   is brought up to date, as now; no round is fired then.

What it does not do: publish anything eagerly. Bringing 190 proxies up to
date every tick, or every frame from `follow`, was what the bridge did
until 26 September and was the largest saving when it stopped
(`box3d-performance-fixes-2026-09-26.md`); most ticks have no round in
them.

## Why a round meets what it met

A ray's answer is the nearest proxy on its line that is not left out. A
proxy is on the line only if the line passes the box its set's proxies
were put in, and then the set is brought up to date before the ray is
asked. A capsule that ought to be on the line is in the box its set's
capsules are in now, and then too the set is brought up to date. So
every proxy the ray can meet is where its capsule is, which is all the
look-over of 190 gave it.

What could break that, and what holds it:

| What | Held by |
|---|---|
| A capsule moved or put off its layer with its set not told | Everything that does goes through `follow`, `Hitbox.set_on_layer`, `build` or `clear`; the oracle below finds one that does not |
| The hull moved by hand in a tick (the range's dummy at its respawn, a bot to its route's start) | The set's node's place is compared at every ray |
| A body rebuilt in a tick (a side swap at the tick's end) | The new hitboxes are new to the bridge and in a new set, not known; the old are removed with their set |
| The box too small | It is measured from the capsules, not guessed from the hull: a revived body's capsules where its ragdoll left them, a bot's where it was drawn, a foot planted under the floor are all in it |
| A proxy a hair off its capsule (a proxy is moved only when it is not nearly where it should be) | As now; which of two near places it holds can differ with when it was last moved, by less than the comparison's own tolerance |

## How it is checked

- **An oracle, on in every check** (`Box3DQueries.check_sets`): for each
  ray in a tick that can meet a hitbox, what it met is compared with the
  nearest capsule on its line worked out in script from the hitbox nodes
  themselves, every one of them, the proxies not asked. A round that met
  a proxy where no capsule is, or passed a capsule it should have met,
  is counted, and a check file with any counted has failed. So every
  round fired in the suite, dust2's two matches with them, is held to
  what the capsules say.
- **The same match before and after**: dust2's seeded match, every player
  at every tick (where, facing, rounds fired, health, money, gun), written
  out on the code before and the code after, and compared.
- **New checks, in a tick, on the native world**: a round at someone who
  has run this tick and at someone who has not; at someone killed earlier
  in the tick, and at whoever stands behind them; at someone revived; at
  someone moved by hand; after a side swap; a set left alone while its
  body walks off, then shot where it was and where it is.
- **What it costs**, by the same stopwatch, and the worst ticks again.

## Left for after

- What a death costs (2 to 3 ms in the shooter's run, 1.1 ms at the
  tick's end): to be measured apart and taken down next.
- The shooter's own set is brought up to date for its own rounds, though
  what it meets of its own is passed over: 80 us a round that could be
  saved once it is known that the native list of every hit is nearest
  first, which today's longer way leans on.
- The box measured in `follow` rather than at the ray, if the 28 us a set
  it costs a tick's first round shows.
