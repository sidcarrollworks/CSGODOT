# Working on CSGODOT

CS2 recreated in Godot 4.7. Read by every agent that works on this repo:
Sid's local agents on his machine, and the cloud threads of his Claude
project. Both change the same files, often on the same day, so these are
the rules that let them do it without breaking each other's work. The
README says what the game is;
`reference/how-it-works.md` says how it is built.

## How work reaches main

- Never commit or push to `main`. Branch from a freshly pulled `origin/main`,
  push the branch, open a pull request; Sid merges.
- Keep a branch to one concern and short-lived. When it falls behind, merge
  `origin/main` into it; do not rebase or force-push a branch someone else
  may have checked out.
- Run `scripts/run_tests.sh` before opening the pull request, and add checks
  for what you change (a test file is `tests/run_*.gd`, extending
  `tests/check_suite.gd`). The same run happens on GitHub for every pull
  request (`.github/workflows/tests.yml`); a red run is not ready to merge.
- CI and the cloud threads have no extracted assets, so the checks that need
  them skip there. A change that touches models, the map, sounds or anything
  else under `assets/` also needs the run on Sid's machine; say in the pull
  request whether it had one.
- Say in the pull request which roadmap item or plan step it is, and mark it
  done in the same pull request (below).

## Where the plan is

- `reference/roadmap.md`: every item, in order, each marked **Local** (needs
  Sid's machine: CS2, Source 2 Viewer, the extracted `assets/`, or playing)
  or **Remote** (code and headless checks a cloud thread can do).
- `reference/weapons/TODO.md`: every gun, split the same way.
- `reference/cs2-systems.md`: CS2's rules and numbers for each system.
- `reference/systemization.md`: the shared systems the next items are built
  on, and in what order.
- `reference/performance.md`: what everything costs, and how to measure it
  again (`scripts/profile_dust2.gd`).
- `reference/rendering.md`: what a frame costs to draw, how to measure it
  (`scripts/profile_render.gd`, on a GPU), and the renderer's plan.

Whoever lands an item marks it done where it is listed, in the same pull
request. Before starting one, check it against `main`: the other side may
have done it already.

Before starting a feature, check for research on it: `reference/research/`
first, then `reference/cs2-systems.md`, `reference/weapons/` and
`reference/systems/`, and the open pull requests, since research pages often
wait there before they merge. Build to what the research found rather than
older guesses in the code or the systems pages, and take on the code fixes
and Local checks listed at the end of its page where they concern the
feature. When nothing covers the feature, say so in the plan or pull request
before building, so Sid can decide whether to have it researched first.

Before writing code against a Godot API, read `reference/godot/README.md`
and the page it names for the task: what the Godot 4.7 docs say about each
engine system this project uses, the classes' exact members, and the
mistakes the docs warn about (metre defaults in an inch-scaled world,
shared containers, querying physics outside the tick). Trust those pages
and the docs over memory of older Godot versions. For anything they leave
out, `scripts/godot_docs.sh` fetches the full docs into `.godot-docs/` to
search. When a change finds a page wrong or missing something, correct it
in the same pull request.

## What the code holds to

- Source units (1 unit = 1 inch), a fixed 64 Hz tick, and the project's own
  collide-and-slide movement. Never `move_and_slide`.
- Every game system is server-side state from the start: it runs in the
  simulation on the tick, takes its input from `UserCmd`s, keeps time with
  `SimClock` (never the wall clock or Godot's `Input`), and what is drawn or
  heard only reads it.
- One `GameWorld` (`src/sim/game_world.gd`) runs the tick: each player's
  command in the order they joined, then the match. Nothing that decides
  the game runs itself in a `_physics_process` of its own; a new system
  joins the world's tick, and what it gives out a tick (path searches, and
  later events) lives on the world.
- A server's cost comes first, since Sid chose 64 Hz to leave room for
  more players: nothing reads the disk during a tick; what is only seen or
  heard runs per frame, not per tick; a change to the movement counts the
  hull traces it adds per tick (`PlayerBody.traces`; `scripts/profile_dust2.gd`
  measures the rest); and a cache hands out copies, since an array,
  dictionary or packed array handed back is shared and a caller's append
  changes the cache.
- CS2 is the starting point, not the limit (Sid, 2026-09-23): take its rules
  and numbers by default, and where it has a known weakness (the
  interpolation delay at 64 Hz, the peeker's advantage) propose a measured
  improvement as an option rather than rule it out as unfaithful.
- CS2's own numbers win wherever the game has them
  (`reference/weapons/vdata.csv`, generated from the game's files); anything
  measured by hand goes in `reference/` with how it was measured.
- A key keeps CS2's default meaning everywhere, the test range included
  (Sid, 2026-09-24). A test or debug key goes only on a key CS2 leaves
  unbound; `reference/binds.md` lists them and the keys still to move.
- `assets/` holds Valve's extracted content and is never committed.
- Pages the extraction scripts write (`reference/surfaces/`,
  `reference/animgraph/`, `reference/weapons/equipment.md` and the other
  tables they generate) are regenerated, not edited by hand.
