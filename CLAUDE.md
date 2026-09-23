# Working on CSGODOT

CS2 recreated in Godot 4.7. Read by every agent that works on this repo:
Sid's local agents on his machine, and the cloud threads of his Claude
project. Both change the same files, often on the same day, so these are
the rules that let them do it without breaking each other's work. The
README says what the game is and how it is built.

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

Whoever lands an item marks it done where it is listed, in the same pull
request. Before starting one, check it against `main`: the other side may
have done it already.

## What the code holds to

- Source units (1 unit = 1 inch), a fixed 64 Hz tick, and the project's own
  collide-and-slide movement. Never `move_and_slide`.
- Every game system is server-side state from the start: it runs in the
  simulation on the tick, takes its input from `UserCmd`s, keeps time with
  `SimClock` (never the wall clock or Godot's `Input`), and what is drawn or
  heard only reads it.
- CS2's own numbers win wherever the game has them
  (`reference/weapons/vdata.csv`, generated from the game's files); anything
  measured by hand goes in `reference/` with how it was measured.
- `assets/` holds Valve's extracted content and is never committed.
- Pages the extraction scripts write (`reference/surfaces/`,
  `reference/animgraph/`, `reference/weapons/equipment.md` and the other
  tables they generate) are regenerated, not edited by hand.
