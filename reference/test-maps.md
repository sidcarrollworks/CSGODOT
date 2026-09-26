# The test maps

Two scenes where movement and shooting get tuned in flat grey rooms before
they meet a real map: the movement course (`maps/test_movement/test_movement.tscn`)
and the test range (`maps/test_range/test_range.tscn`). Both work without any
extracted assets. Keys follow `reference/binds.md`: CS2's defaults, with test
keys only on keys CS2 leaves unbound (the moves the table plans are listed
there).

On every map, the readout in the top left is the tuning instrument: current
speed, vertical speed, peak speed, and speed gained over the last jump. Speed
gained per jump is the number that tells you whether air acceleration is
right. F3 hides it.

## The movement course

Everything on it is a measurement, not decoration:

- **Strafe lane**, markers every 128 units, brighter every 512. How far a
  strafe jump actually carried you.
- **Stairs**, eight 16-unit steps you should walk up without jumping, ending in
  a 24-unit lip you should not (step height is 18).
- **Ramps** at 20°, 35°, 44° and 50°. The 44° one is walkable and the 50° one
  is not, which is the threshold that makes surfing possible.
- **Stairs**, which are also the ground-adhesion test: running down them should
  never leave the ground and should hold full run speed. See
  `reference/movement_constants.md` on `StayOnGround`.
- **Surf lane**, two opposing 55° ramps with a drop-in platform. If
  collide-and-slide is right you ride these and gain speed. If it is wrong you
  stick or stutter. This is the clearest single test of the port.
- **Jump gauges** at 32, 48, 56, 64 and 72 units. The grey ones are reachable
  standing; the blue ones need a crouch jump.

The surf lane cannot yet reproduce the one open movement complaint:
launching off the end of a ramp. Its channel runs into the floor, so there is
no ramp end to leave. That geometry is the next thing the course needs.

## The test range

`maps/test_range/test_range.tscn`. A flat wall 512 units away to spray at,
ruled in degrees, beside it a lane with a dummy in it to check damage
against, and off to the left a bot that shoots you when you tell it to.

| Key | |
|---|---|
| `1` to `5`, `Q`, `G` | as everywhere: the AK-47, the Glock, the knife, the grenades, the bomb; the last thing held; drop it |
| `R` | reload |
| `P` | export the spray you just fired |
| `O` | clear the impact markers, the log and the guns on the ground, stand the dummy up, and hand you the bomb again |
| `H` | draw or hide the dummy's hitboxes |
| `K` | the dummy's armour: kevlar and helmet, kevlar, none |
| `N` | the dummy's distance: 256, 512, 1024, 2048 units |
| `[` | the dummy never dies: a kill is logged and it is refilled, so a whole spray registers |
| `M` | a wall in front of the dummy to shoot it through: a wooden door, a crate, sheet and solid metal, plaster, thin and thick concrete, none |
| `I` | the shooter fires at you, or holds its fire |
| `U` | the shooter's weapon: AK-47, M4A1-S, MP9 |
| `Y` | your armour: kevlar and helmet, kevlar, none |
| `J` | you never die: a kill refills you |
| `T` | a window on your own body and hitboxes: from the front, from the side, off |
| `B` | the buy menu, in the green zone round the spawn ($16,000, filled again by `O`) |
| `5`, then `Mouse 1` on site A | plant the bomb, behind the spawn; `E` looking at it defuses, `L` puts the kit on or off, and `O` gives you another |
| `4`, then the mouse | throw a grenade: the range keeps you in an HE, a flash, a smoke and a molotov |

Every bullet leaves a mark: dark on the wall, red on the dummy. The readout
shows the current shot index in the pattern and the size of the inaccuracy cone
right now, which is the number that moves when you walk, crouch or jump.

**The wall** is ruled at every degree from the spawn's eye, bold every five and
numbered: up and down from the aim line, left and right from the centre. A
spray fired from the spawn reads off in degrees, and so does a CS2 spray fired
at a wall from the same distance (496 units to the wall's face), so the two can
be compared without knowing either's scale.

**The dummy** is a bot that stands still and does not shoot back: the same
body and hitboxes the bots on dust2 wear, CS2's nineteen capsules on its bones
where the characters have been extracted, the four standard boxes where they
have not. Fire at it from the yellow spot to the right of the spawn, where
nothing stands between you at any distance. Its hitboxes are drawn over it,
coloured by zone, and the one a round goes into lights up. Each round shows
the damage it did beside where it landed (red for the head), and the readout
at the top right keeps a log: what each round did, to which part, from how
far, what it carried before the armour, and the health left; and for a kill,
the damage in how many hits and the time from the first to the last. The readout also says which
hitboxes it wears, and when they are the stand-in boxes on an extracted
character, why the game's are missing. It starts
in kevlar and a helmet, as an opponent in a rifle round would be. Killed, it
falls as a ragdoll, knocked the way the round was going, drops the M4A1-S it
holds as anyone does, and two and a half seconds later stands up again where
it was, whole. `[` makes it never die instead.

**Walls to shoot through.** M stands a wall across the dummy's lane just in
front of it, one of CS2's surfaces at a thickness, and steps through them.
A round goes through a wall when it has the power to (the game's
penetration power for the weapon, against the game's own numbers for the
surface and how thick the wall is), and comes out with less damage; the log
says what each wall let through, and a wall too thick or too hard stops it
at the face. dust2's walls work the same way, by the surface the hull names
for each part.

**The shooter** is a dust2 bot on the red spot left of the wall, armed and
facing the spawn, holding its fire. I sets it on you: it turns, and fires
in bursts with its weapon's own spread and recoil and a bot's aim error.
Each hit tags you (the readout in the bottom left gives the share of your
top speed you have left and how fast you are going, so run while it fires),
throws your aim (the flinch, in degrees), and puts a red arc round the
crosshair on its side. U swaps its weapon: the rifles tag to 40%, the MP9
(the game's own numbers for it on the AK-47's spray, which is not measured
for it) stops you. Y takes your armour off a piece at a time, for the
flinch with and without it; J keeps you alive for as long as you want to be
shot. T opens a window in the bottom right on your own body and hitboxes,
which your camera never shows: the capsules the bots' rounds meet, from in
front of you or from your side, to check them against how you stand,
crouch, strafe and jump. Without the character extracted it shows the four
stand-in boxes.

`P` turns the marks you just made back into a spray pattern file in the same
format the weapons read, so a pattern can be adjusted by eye against a CS2
screenshot and exported without converting anything by hand. See
`reference/spray_patterns/README.md`.
