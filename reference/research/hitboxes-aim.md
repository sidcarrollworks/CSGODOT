# How CS2 bends the body, and its hitboxes, with the aim

Research on whether, and how far, CS2 turns a player's spine and head when
they look up or down, and so moves their hitboxes. Written 2026-09-24 for
Sid's "have a couple agents research those as well" (the research-gaps
list, item 4: hitboxes following aim pitch). Docs only: no code, systems
page or roadmap changes with it. `combat.md` beside it already covers how
CS2 records and rewinds hitboxes for lag compensation; this page covers what
pose those hitboxes are in.

**Sources, newest first, and how each claim is marked.** Sid asked for the
most up-to-date primary sources wherever they exist (2026-09-24), so each
claim says which it rests on:

- *Read*: read directly from CS2's current files as SteamDatabase's
  GameTracking-CS2 publishes them, at commit `d45f52d` (2026-09-23 23:10
  UTC). That is CS2 1.41.8.3, build 2000915, dated 23 Sep 2026
  (`game/csgo/steam.inf`), the newest commit on 2026-09-24 when this was
  checked.
- *Read, 1.41.8.2*: read from this repo's generated graph pages
  (`reference/animgraph/`), which the local agent wrote from CS2 1.41.8.2's
  graphs. **These are one update old.** 1.41.8.3 changed
  `animation/graphs/worldmodel/worldmodel.vnmgraph_c` (CRC `0079dc42ae` to
  `007953aa79` in `game/csgo/pak01_dir.txt`), while the skeleton is the same
  as 1.41.8.2's. The compiled graph is not in GameTracking-CS2, so only a
  re-extraction on Sid's machine can say what changed (section 7).
- *Valve, via search*: Valve's own update notes. counter-strike.net, Steam
  and the Steam news API all refuse connections from the cloud, so the
  wording comes from search summaries of those pages; the Valve URLs are in
  Sources for Sid to check.
- *Community*: third-party articles and forum posts, again from search
  summaries (secondary).
- *Inferred*: a reasoned guess from the above.

Nothing here comes from Valve's leaked CS:GO source. The one CS:GO-era
comparison is marked as such.

## The short version

- **Yes, CS2 bends the body with the aim, on the server, so the hitboxes
  move with it.** The third-person graph runs every pose through Valve's
  `AimCS` node, which takes the aim's pitch (`aim_angle_pitch`) and yaw
  (*Read*: the node's schema and the parameter names at 1.41.8.3; its place
  in the graph *Read, 1.41.8.2*). That node is compiled into the server DLL
  as well as the client's, from `src/game/shared/csgo/animgraph2/tasks/animtask_aim_cs.cpp`
  (*Read*), and the server's hitboxes are posed from the graph's result
  (*Inferred*: the server records posed hitboxes for lag compensation, and
  warns when its head hitbox strays from the client's, below).
- **How far it bends is in Valve's code, not in any data file.** `AimCS`
  has no clips and no angle settings: its only settings are three blend
  times. No aim-pose clips exist anywhere in the game's animation folders
  (*Read*). So the amount the spine, neck and head turn per degree of pitch,
  and whether it depends on the gun, crouching or defusing, can only be
  measured in CS2 (section 7).
- **This repo's bodies ignore pitch entirely.** `PlayerModel.update_motion`
  takes the velocity, yaw, crouch and ground, and no pitch
  (`src/player/player_model.gd:271`); `PlayerSim.run_command` calls it
  without one (`src/player/player_sim.gd:513`). Every player's hitboxes,
  the player's own hitboxes and the bots', stand as if looking level
  whatever the aim. What a shooter sees and what they hit still agree,
  because the drawn body is the same unpitched pose; what differs from CS2
  is where a head is when its owner looks up or down.
- **The yaw is the same kind of gap.** CS2's aim also takes a horizontal
  angle, so the torso twists toward the aim while the legs lag and turn on
  the spot (*Read* inputs, *Inferred* use); here the whole body turns with
  the aim at once (`player_model.gd:272`).
- **The newest build changed the third-person graph.** CS2 1.41.8.3 (23 Sep
  2026) replaced the compiled graph this repo's pages were generated from
  (*Read*, the file's CRC). The aim node's schema and strings above are read
  at 1.41.8.3; the graph's layer order is one update old until Sid
  re-extracts it.
- **What players ask for** (section 3): since AnimGraph 2 (April 2026) the
  complaints are the head bobbing on strafes and dipping on counter-strafes,
  and hits that looked right online not landing. None argues against
  bending the body with the aim; they argue for measuring the head's path
  against CS2's and keeping the drawn and hit poses one.

## 1. What CS2's files say

### The node

The third-person graph (`reference/animgraph/worldmodel.md:11-17`, *Read,
1.41.8.2*; the graph changed in 1.41.8.3, so recheck this order after the
next extraction) stacks, from the root:

1. `SnapWeapon`, 2. a layer blend with the flashed layer over
3. **`AimCS`**, over 4. `FootIK` on the ankles, over 5. a layer blend with the
weapon, defuse, body-additive, shooting and three flinch layers, over
6. the locomotion state machine.

So the aim is applied after the locomotion, the gun's hold, the shots and
the flinches, and before only the flashed reaction and the weapon snap.

`AimCS`'s inputs, from the graph and from its schema
(`DumpSource2/schemas/client/CNmAimCSNode__CDefinition.h`,
`DumpSource2/schemas/modtools/CNmGraphDocAimCSNode.h`, *Read*):

| Pin | Graph parameter |
|---|---|
| Vertical Aim Angle | `aim_angle_pitch` |
| Horizontal Aim Angle | `aim_angle_yaw` |
| Weapon Category | `weapon_category` |
| Weapon Type | `weapon_type` |
| Weapon Action | `action` |
| Weapon Drop | `weapon_drop_amount` |
| Crouch Weight | `move_crouch_amount` |
| Is Defusing | `is_defusing` |

Its only numbers are blend times: hand IK blends in over 0.3 s, a weapon
action over 0.4 s, planting over 0.2 s (*Read*). Its runtime task,
`CNmAimCSTask`, is a plain pose task with a `TrySetupSolverData` step
(*Read*, `server_strings.txt:12782`), so it solves something per pose,
probably the hands' IK onto the gun after turning the upper body
(*Inferred*).

`aim_angle_pitch` and `aim_angle_yaw` feed nothing else in any graph
(*Read, 1.41.8.2*: they appear only on `AimCS` in `reference/animgraph/`). Their
range is for the game's code to say (`parameters.md`).

### It runs on the server

- The server DLL's strings hold `CNmAimCSNode`, `CNmAimCSTask`,
  `CNmAimCSTask::TrySetupSolverData`, `aim_angle_pitch` and
  `aim_angle_yaw` (*Read*, `game/csgo/bin/win64/server_strings.txt:2361,
  7103-7104, 12782, 24609-24610`), and the source path
  `src\game\shared\csgo\animgraph2\tasks\animtask_aim_cs.cpp`
  (`:10611`); `shared` is Source's folder for code built into both DLLs.
  The schema dump lists the node under `client/` only, but the server
  carries the same class (*Read*).
- The pawn networks its eye angles, `m_angEyeAngles`
  (`DumpSource2/schemas/server/CCSPlayerPawn.h:109`, *Read*), which is where
  every machine gets the pitch that drives the aim (*Inferred*).
- `sv_csgo_shoot_lagcompensation_max_error 1`: "Warn if lag compensated
  head hitbox position doesn't match that on client" (*Read*,
  `convars.txt:9897`, development only). The head is the hitbox Valve checks
  between the two, and it could only disagree if pose inputs like the aim
  disagree (*Inferred*).
- `CCSUsrMsg_ShootInfo` carries `hitbox_transforms` with each shot
  (*Read*, `Protobufs/cstrike15_usermessages.proto:560-565`; `combat.md`
  has the rest).

### No clips

The game's world animations (`animation/anims/world/`, listed in
`game/csgo/pak01_dir.txt`) are locomotion, jumps, ladders, deaths, defuses,
flinches, flashed and the guns' own actions. None is an aim pose, up or
down; the only `aim` clips in the game are main-menu scenes (*Read*, the
1.41.8.3 listing). CS2's third-person aim is procedural (*Inferred* from the
missing clips and the solver). For contrast only: CS:GO blended hand-made
aim poses by a `body_pitch` value (CS:GO era, from memory, not checked
against any file here).

## 2. What changed over CS2's life

Newest first. Valve's own notes are the primary source for each; none could
be fetched from the cloud, so each line says where its wording came from.

- 2026-09-23, 1.41.8.3: the third-person graph file changed (*Read*, the
  CRC above). What changed is unknown until it is re-extracted.
- 2026-04-21: AnimGraph 2's third person went live for everyone (*Valve,
  via search*: counter-strike.net and Steam's "Counter-Strike 2 Update";
  wording from HLTV and Insider Gaming summaries).
- 2026-04-14: the second AnimGraph 2 beta patch fixed "stuttering in
  third-person aiming", among other things (*Community*: Insider Gaming and
  thespike.gg summaries; Valve's own note not reached).
- 2026-04-02: "Animgraph 2 Beta": all third-person animations re-authored,
  and the CPU and network cost of animation cut (*Valve, via search*:
  counter-strike.net/newsentry/528750051218948816).
- 2023-11-30: "Improved character posing when aiming up and down" (*Valve,
  via search*: the Steam announcement, wording from counterstrike.fandom.com's
  copy). Older, and from the first animation system.
- 2023-10-10: "Fixed several hitbox alignment bugs", after players found
  hitboxes off the model when crouching and looking down, worst with a
  knife or the bomb in hand (*Community*: Dexerto, PC Gamer, Escorenews,
  ensigame). Older, and from the first animation system.

So anything from before April 2026 (videos, guides, the 2023 reports)
describes a system CS2 no longer runs.

## 3. What players criticise and ask for

Sid asked to track these (2026-09-24). All are *Community*, from search
summaries of forum posts and articles, since Reddit, Steam discussions and
HLTV refuse fetches from the cloud. Newest first, CS2-era only.

| When | What players say | Source | Does it apply to our hitboxes? |
|---|---|---|---|
| 2026-04-22 onward, after AnimGraph 2 went live | Headshots feel instant and holding an angle feels easier than swinging, but some still call hit registration "very bad" | Steam discussion "Animgraph 2 Hit Registration"; Shane the Gamer, white.market, gamermarkt.com summaries | Partly. Our shooter sees the same pose the server hits, so the "looked like a hit" class cannot happen offline. It returns with netcode (item 25), where `combat.md`'s lag-compensation options apply |
| 2026-04-22 | The model's head bobs up and down when strafing | Steam discussion, dated in the search summary | Yes, once the body's motion reaches the head. Our locomotion clips carry whatever bob CS2's do; the aim stage below must not add to it. Measurable: the head capsule's height over a strafe, ours against CS2's |
| 2026-04, beta feedback | The "head dip" when counter-strafing makes jigglers hard to track; Valve toned it down in steps | Shane the Gamer, white.market, skin.club summaries | Yes: it moves the head hitbox. Same check: the head's drop on a counter-strafe, ours against CS2's |
| 2026-04-14 | Third-person aim stuttered in the beta | Insider Gaming, thespike.gg summaries (Valve fixed it) | Yes, as a rule for us: the aim stage must be smooth from tick to tick, which interpolating the pitch between ticks (as `show_between` does the yaw) gives |
| 2025 to 2026, before AnimGraph 2 | Shots that land on a head on screen do no damage; a mix of position desync and animation mismatch | Steam discussions, sportskeeda, tradeit.gg, critfeed.com summaries | Not offline, as above. Online it argues for recording the posed capsules on the tick (systemization step 8) and rewinding to the tick and fraction |
| 2023-10 onward | Hitboxes off the model when crouching and looking down, worst with a knife or the bomb | Escorenews, ensigame, game-tournaments.com summaries | Yes, as a warning: the bend must be measured per crouch state and weapon category, not assumed from one standing rifle pose |
| Undated guides | The camera sits right of the head, so a right-hand peek shows less head than it sees | skin.club and steamanalyst.com peeking guides | Yes. Our eye is centred on the body; if CS2's is offset, a player looking down or peeking shows a different share of head than here. Worth a Local check (section 7) |

What would improve on CS2 here, following `CLAUDE.md` (CS2 is the starting
point, not the limit): nothing in the aim itself. The complaints are about
the head moving more than players expect (bob, dip) and about the drawn
body and the hit body parting online. Our design already keeps one pose for
both offline. The measurable options are a cap on how far the aim stage and
the locomotion together may move the head per tick, off by default and
compared against CS2's measured head path, and recording the capsules on
the tick for the rewind. Neither adds a trace; the first is a few bone
reads per body per tick.

## 4. What this repo does

| Where | What | Against CS2 |
|---|---|---|
| `src/player/player_model.gd:271-280` | `update_motion(velocity, yaw, crouch, on_ground)` sets the body's yaw and the locomotion; no pitch | CS2 turns the upper body by pitch (and part of yaw) |
| `src/player/player_model.gd:282-294` | `_apply()` sets the locomotion, crouch, air and hold; nothing like `AimCS` | The aim is a stage of its own, after the layers |
| `src/player/player_sim.gd:513` | Poses every player's sim body each tick, the player's own and each bot's, with no pitch | The server poses with the command's view angles |
| `src/player/player_view.gd:402` | The first-person body and shadow, the same call | Drawn only; follows whatever the sim does |
| `src/combat/skinned_hitboxes.gd` `follow()` | Capsules follow their bones on `skeleton_updated` | Right: once the bones carry the aim, the capsules do too |
| `src/player/player_input.gd:97` | Pitch clamped to 89 | CS2's `cl_pitchup` and `cl_pitchdown` are 89 (*Read*, `convars.txt:1660, 1666`) |
| `src/bots/bot.gd:212` | Bots aim at feet plus 48 | A chest point, so the aim's bend barely matters to it |

The eye stays where it is either way: the camera is at the body's origin
plus the eye height (`player_sim.gd:661`, `movement_config.gd:108-109`),
as in CS2, where the view comes from the pawn's view offset and not from
the head bone (*Inferred* from Source 1's convention, an older engine; not
checked in CS2's files, and the peeking guides in section 3 say CS2's view
also sits right of the head). So once the body bends, the head hitbox and
the eye are no longer one point: when this repo adds the aim stage, a player
looking down off a ledge will show their head where CS2 puts it, not at
their eyes.

## 5. What it means for fairness

- **Within this game, nothing is unfair today.** The shooter sees the same
  unpitched body the hitboxes ride.
- **Against CS2, heads are in the wrong place whenever someone looks away
  from level:** anyone holding an angle down a ramp or from above (dust2's
  catwalk, A site from long, the tunnels' stairs) and anyone looking up at
  a ledge. How far wrong is the number section 7 measures.
- **It interacts with lag compensation.** The rewound record must hold the
  capsules after the aim is applied, so the aim belongs before the hitboxes
  are recorded on the tick (systemization step 8, `combat.md`'s option 1).

## 6. How it could be built here (Inferred)

A proposal for the item that follows the measurement, not a decision:

1. **An aim stage in `PlayerModel`, applied after the animation and before
   the hitboxes follow.** Take the pitch (and later the yaw offset) with
   the other motion values, and after the tree's pose rotate the spine
   bones above `spine_0`, `neck_0` and `head_0` about the body's right axis,
   each by its share of the pitch. The arms and the gun hang off the upper
   spine, so they come along without IK; hand IK is only needed if the
   measured shares move the gun off the hands.
2. **The shares come from the measurement**, one table per crouch state (and
   per weapon category if CS2's differ), interpolated by pitch. Until then
   the stage is off, so nothing changes on a guess.
3. **Run it on the tick.** Systemization step 8 wants the trees stepped by
   hand on the tick; the aim stage goes right after that step and before
   `SkinnedHitboxes.follow()`. A `SkeletonModifier3D` is the other way to
   apply it, but the asset pipeline found a modifier losing to a clip's
   track in 4.7's update order (`reference/asset-pipeline.md:34`), so
   setting the bone poses directly after the manual step is the safer
   start.
4. **Cost.** A handful of bone rotations per body per tick, against the
   0.1 ms the tree and posing already cost (`performance.md`); no traces.
5. **Hooks.** `player_sim.gd:513` has to pass the pitch; that file is the
   local agent's, so the change there is theirs.

CS2 has no known weakness here to improve on: pitch reaches every machine
through the networked eye angles, so the server and clients pose alike
(*Inferred*). Copying CS2's numbers is the goal.

## 7. What only a Local measurement can settle

On Sid's machine, a local server with `sv_cheats 1`, one bot, and these
commands (all *Read* from `DumpSource2/commands.txt` and `convars.txt`):
`bot_mimic 1` (the bot uses your commands, pitch included),
`bot_mimic_yaw_offset` (180 by default: it faces you; 90 turns it side-on),
`setang <pitch> <yaw>` and `setang_exact` (snap your view),
`bot_stop 1`, `ent_hitbox` (the server's hitboxes on what you look at),
`cl_ent_hitbox` (the client's), `ent_skeleton`, and
`sv_showhitregistration 1` (the lag-compensated hitboxes each shot used).

The catch is that the bot copies the pitch you are looking with, so you
cannot look at it level while it looks down. Two ways round it:

- **A demo.** `record aimtest`; with `bot_mimic 1` and
  `bot_mimic_yaw_offset 90`, sweep your pitch slowly from 89 up to -89
  standing, then crouched, with an AK, a Glock, a knife and the bomb;
  `stop`. Play it back, pause, free-fly beside the bot and draw its hitboxes
  with `cl_ent_hitbox`, screenshotting side-on. demoparser2 (MIT) reads
  `m_angEyeAngles` per tick to name the pitch in each frame.
- **Or freeze it**, if CS2 lets a stopped bot keep its last angles: `bot_stop
  1`, `bot_mimic 1`, `setang 60 0`, `bot_mimic 0`, look at it, `ent_hitbox`,
  and shoot it once with `sv_showhitregistration 1`.

| Question | How |
|---|---|
| How far the head capsule moves at pitch -89, -45, 0, 45, 89 (up is negative) | Side-on screenshots against a grid, or `ent_hitbox` beside a known-size prop; forward and down offset of the head's centre in units |
| How the bend is shared between spine, neck and head | `ent_skeleton` side-on at 0 and 89; each bone's angle |
| Whether crouching changes it | The same sweep crouched (`AimCS` takes the crouch weight) |
| Whether the weapon changes it | AK, Glock, knife and bomb at 89 (it takes the weapon's category and type) |
| Whether defusing switches it off | Defuse while the mimicking bot looks down |
| How far the torso twists before the legs turn | Turn slowly in place with `bot_mimic 1`; the yaw at which the feet step round |
| Whether server and client agree | `ent_hitbox` and `cl_ent_hitbox` together at 89 |
| The extracted character's spine bones | Read from the glTF on Sid's machine; the cloud has no model |
| What 1.41.8.3 changed in the third-person graph | Re-extract and regenerate `reference/animgraph/` (`scripts/animgraph_tables.gd`), then diff; the `AimCS` line and the layer order are what this page leans on |
| Where the eye sits against the head | `cl_ent_hitbox` on a mimicking bot with `setang 0 0`, seen from above: is its view point left or right of the head capsule's centre, and by how much |

## 8. Corrections other docs and code need

Not made here; for whoever takes the item.

- `reference/roadmap.md:194-196` says a bot's round meets your head
  "where your head is" crouched, jumping or mid-strafe. True, but not
  looking up or down: the player's own hitboxes, and every bot's, ignore
  pitch.
- `reference/roadmap.md` has no item for the aim's bend. It wants one: a
  Local measurement (section 7), then a Remote item to add the aim stage
  (section 6), after systemization step 8.
- `reference/animgraph2.md:135-137` says the files give `AimCS`'s inputs,
  not what it does. Add: it runs on the server as well, has no clips, and
  its only settings are three blend times, so its amounts are measured.
- `reference/systemization.md` step 8 (posing on the tick) should name the
  aim stage as part of the pose that is recorded.
- `reference/research/combat.md`, lag compensation: the rewound hitboxes are
  in the aim's pose.
- `reference/animgraph/`: generated from 1.41.8.2; the third-person graph
  changed in 1.41.8.3, so it wants regenerating on Sid's machine.
- `src/player/player_model.gd:271` (`update_motion`) takes no pitch, and
  `src/player/player_sim.gd:513` passes none (the local agent's file: the
  hook is theirs).
- `reference/performance.md`: the aim stage's bone rotations, once built.

## Sources

- SteamDatabase, GameTracking-CS2, commit `d45f52d` (2026-09-23 23:10 UTC,
  CS2 1.41.8.3, build 2000915), and for the graph's CRC history commits
  `98da94f` and `10f3693` (1.41.8.2) and `d8e2c7a` (1.41.8.1):
  `DumpSource2/schemas/client/CNmAimCSNode__CDefinition.h`,
  `DumpSource2/schemas/client/CNmAimCSTask.h`,
  `DumpSource2/schemas/modtools/CNmGraphDocAimCSNode.h`,
  `DumpSource2/schemas/server/CCSPlayerPawn.h`,
  `DumpSource2/convars.txt`, `DumpSource2/commands.txt`,
  `game/csgo/bin/win64/server_strings.txt`,
  `game/csgo/bin/win64/client_strings.txt`, `game/csgo/pak01_dir.txt`,
  `Protobufs/cstrike15_usermessages.proto`
  (github.com/SteamDatabase/GameTracking-CS2).
- This repo's generated graph pages: `reference/animgraph/worldmodel.md`,
  `reference/animgraph/parameters.md` (CS2 1.41.8.2, one update old).
- Valve's own notes, not reachable from the cloud (read through search
  summaries): counter-strike.net/news/updates;
  counter-strike.net/newsentry/528750051218948816 ("Animgraph 2 Beta",
  2026-04-02); store.steampowered.com/news/app/730 (the 2023-11-30 and
  2026-04-21 "Counter-Strike 2 Update" posts).
- Players' critiques, search summaries (2026-04 onward unless dated):
  Steam discussions "Animgraph 2 Hit Registration" and "The AnimGraph 2
  Revolution"; Shane the Gamer, "CS2 Finally Feels Like CSGO Again After
  AnimGraph 2 Goes Live" and "AnimGraph 2 Beta Gets Another Patch"
  (2026-04-18); white.market, "CS2 Animgraph 2 Update Guide"; gamermarkt.com,
  "CS2 AnimGraph 2 Update"; community.skin.club, "Valve CS2 AnimGraph 2
  Update Sparks Demand for Full Release"; thespike.gg, "Valve introduced
  Animgraph 2"; sportskeeda, "missed shot however i still get headshot";
  tradeit.gg, "What Happened to CS2 Hitboxes?"; critfeed.com, "CS2 Hitboxes
  Explained"; community.skin.club and steamanalyst.com peeking guides.
- Other search summaries: Dexerto, "Counter-Strike 2 October 9 patch notes";
  PC Gamer, "Counter-Strike 2 fixes hitbox issues with crouchers";
  Escorenews and game-tournaments.com, "CS2 has major hitbox issues when
  crouching and looking down"; ensigame, "A mismatch between hitbox and
  player model is found in CS2"; counterstrike.fandom.com, "Counter-Strike 2
  patches/November 30, 2023"; HLTV, "AnimGraph2 goes live in latest CS2
  update"; Insider Gaming, "Animgraph 2 goes Live in Counter-Strike 2";
  dust2.us, "Valve release Animgraph 2 third-person animation beta";
  cs2news.com, "CS2 AnimGraph 2 Update Goes Live".
