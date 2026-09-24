# How CS2's audio engine and mix work

Research for the Godot clone on what a CS2 sound is, how it is mixed, occluded,
spatialised and sent, and what that means for our build. Written 2026-09-24.
Research only: no code or other page changes with it. Footsteps are covered in
`reference/research/footsteps.md` and are not repeated here; gun ranges are in
`reference/research/combat.md` (R6).

**Sources and how each claim is marked.**

- *Read*: read directly from CS2's shipped files as SteamDatabase's
  GameTracking-CS2 publishes them, commit `d45f52d`, which is **CS2 build
  2000915, PatchVersion 1.41.8.3, dated Sep 23 2026** (`game/csgo/steam.inf`).
  Every *Read* claim is from that build unless it says otherwise. Paths below
  are in that repository.
- *Valve*: Valve's own CS2 release notes, read from the archive
  ckreisl/cs-updates-as-json at commit `656981c` (`data/cs2/updates_raw.json`,
  231 posts, 22 Mar 2023 to 22 Sep 2026), cited as *Valve* (release notes,
  date). The date is the post's date in that archive.
- *Community*: a web search summary (the pages refuse fetches from this
  container), with the URL and the date where the summary or the URL gives one.
- *SDK*: Source SDK 2013 (2013). A spec for where CS2 started, never proof of
  what CS2 does.
- *Inferred*: my reasoning from the above.

Nothing here comes from Valve's leaked CS:GO source.

| Short | File (build 2000915) |
|---|---|
| MEGA | `game/csgo/pak01_dir/soundstacks/soundstacks_csgo_mega.vsndstck` (the `csgo_mega` operator stack; not in the sparse checkout, fetched from the same commit) |
| STK | `game/csgo/pak01_dir/soundstacks/soundstacks_csgo_{core,music,ambient,surf}.vsndstck` |
| MIX | `game/csgo/pak01_dir/scripts/soundmixers.txt` |
| DMM | `game/csgo/pak01_dir/soundstacks/dsp_mix_modifiers.vdata` |
| DSP | `game/core/pak01_dir/scripts/dsp_presets.txt` |
| SAS | `game/csgo/pak01_dir/scripts/surfaceproperties_steamaudio.txt` |
| WPN, PLY, PHY, UI | `game/csgo/pak01_dir/soundevents/game_sounds_{weapons,player,physics,ui}.vsndevts` |
| CV | `DumpSource2/convars.txt` |
| SS, CS, SA, SND | `game/csgo/bin/win64/server_strings.txt`, `client_strings.txt`; `game/bin/win64/steamaudio_strings.txt`, `soundsystem_strings.txt` |
| SCH | `DumpSource2/schemas/` |
| PB | `Protobufs/` |
| MENU | `game/csgo/pak01_dir/panorama/layout/settings/settings_audio.xml`; strings in `game/csgo/pak01_dir/resource/csgo_english.txt` (LOC) |

The legacy `game/core/pak01_dir/scripts/sound_operator_stacks.txt` is the
Source 1 style stack file carried in core; it does **not** define
`csgo_mega` (*Read*: no match for the name in it). The CS2 stacks are the
`.vsndstck` files above (*Read*: `game/csgo/gameinfo.gi:209`
`snd_event_browser_default_stack "csgo_mega"`).

## The short version

| Question | CS2 (build 2000915) | Ours (main 3975eef) |
|---|---|---|
| What a sound is | A sound event: a name, a type (`csgo_mega` for almost all gameplay sounds) and fields the type's operator stack reads (*Read*, MEGA) | A file set played through one `AudioStreamRandomizer` (`sound_bank.gd:80-92`) |
| Loudness by distance | A hand-drawn curve per event, distance in units to volume factor; AK-47 1.0 to 176 units, 0.33 at 1288, 0.015 at 2500 (*Read*, WPN 20442) | Godot inverse distance with a 20 m reference and a linear fade to 300 m (`weapon_sounds.gd:56-68`) |
| Far away | A second, "distant" event started by the near one, in its own mixgroup; AK from 800 units, peak 0.54 at 2336 (*Read*, WPN 20536) | None |
| Mix | 60 mixgroups with fixed levels (weapons 0.6, footsteps 0.8, impacts 0.3, explosions 0.7, ambient 0.45), plus mix layers that duck groups while certain sounds play (*Read*, MIX) | No buses; a dB constant per script |
| Occlusion | A per-event filter; ray-traced at runtime, Steam Audio's baked occlusion is off by default (`snd_use_baked_occlusion 0`) (*Read*, MEGA, CV 9363) | None |
| Reverb | Listener room preset and per-source preset, scaled per mixgroup and by distance (*Read*, MEGA, DMM) | None |
| Spatialising | Steam Audio HRTF; very close sounds (your own gun, your own steps) play as plain stereo (*Read*, MEGA; *Inferred*) | Godot's stereo panner at the project's default 0.5 strength; the local player's gun is non-positional (`weapon_sounds.gd:66`) |
| One shot cuts the last | Yes for guns: `instance_limit 1` per entity, oldest stopped (*Read*, MEGA 1235, WPN) | No: four overlap (`weapon_sounds.gd:51`) |
| Silent reload | Since 22 Sep 2026: reload sounds at 0.07 volume and a fifth of the range while "stealthy" (*Read*, MEGA, WPN; *Valve*, 2026-09-22) | Not built |
| Who plays it | The server starts events and sends them (`CMsgSosStartSoundEvent`); shots of others come with the fire-bullets message; your own shot is predicted (*Read*, PB; *Inferred*) | Views play sounds from signals fired inside the tick |

## 1. What a CS2 sound event is

### 1.1 The event and its type

A sound event is a named block in a `.vsndevts` file (kv3 text in this
repository). Its `type` names an operator stack; the event's fields fill the
stack's `public` block, which holds the defaults (*Read*, MEGA 7-116). A `base`
field inherits from another event (*Read*, `footsteps.md` section 4 uses it).
Almost every gameplay event is `type = "csgo_mega"`; the other types are
`csgo_music`, `csgo_ambient`, `csgo_surf`, `csgo_voip`, `csgo_movie` (*Read*,
STK), and a few legacy `src1_3d` events such as `BaseExplosionEffect.Sound`
(*Read*, WPN).

The stack runs on the client's sound system, per playing sound, per sound
update (*Inferred*: it reads the listener's position,
`get_system_globals input_listener_index 0`, MEGA; its outputs are voice
volumes and filter inputs that only a playing voice uses). The server's part
is to decide that the event starts and send it (section 5).

### 1.2 Curves

Every `*_mapping_curve` is a list of points `[x, y, slope_in, slope_out,
mode_in, mode_out]` (*Read*, e.g. WPN 20469-20493). The engine's curve type
has tangent modes named `CURVE_TANGENT_SPLINE`, `_LINEAR`, `_FLAT`, `_FREE`,
`_MIRROR`, `_SINE` (*Read*, strings in `game/bin/win64/*_strings.txt`); which
number is which is not in the files. The stored slopes are close to the
straight line between points (AK-47: -0.000602 at 440 units against a secant
of -0.000476 to -0.001), so linear interpolation between points is within a
dB or two (*Inferred*). Past the last point the curve holds its last value
(*Inferred*: events that must go silent end on an explicit 0, like the
footsteps at 1100; Local check A2).

### 1.3 The csgo_mega stack, in the order it runs

From MEGA (operators named as in the file):

1. **Source and position.** `game_entity_info` gives the entity's position,
   or `public.position` for a world sound; a dormant entity uses the sent
   world position, a deleted one holds its last position
   (`use_world_position_if_dormant true`, `input_hold_position_on_deleted_entity
   true`). Then `position_offset` (world or entity-relative), an optional
   random offset (`randomize_position_min/max_radius`), a UI position
   relative to the listener's axes, or a soundscape position
   (`final_position`).
2. **Distance.** `distance_to_source` is the straight line from
   `final_position` to the listener; `multiplied_distance = distance *
   distance_multiplier` (default 1).
3. **Stealth.** `game_get_source_player_info.output_is_stealthy` OR
   `public.suppressed` gives `calc_is_suppressed`, only where
   `suppression_enable` is set. Then
   `distance_after_suppression = multiplied_distance / (suppressed ?
   suppression_falloff_multiplier : 1)` and a volume factor
   `suppressed ? suppression_volume_multiplier : 1` (MEGA 2089, 2222).
4. **Instance limit.** `soundevent_limiter` with `match_entity 1`,
   `match_this_event 1`, `input_max_events = instance_limit`, `stop_oldest 1`,
   run once at start and only when `instance_limit` is non-zero (MEGA 1235).
   So `instance_limit 1` on `Weapon_AK47.Single` means one AK shot per
   entity: each new shot stops the previous.
5. **Blocking.** `soundevent_block_test` (when `block_matching_events`) refuses
   the start if a block is set for this event, on this entity (when
   `block_match_entity`, else any entity) within `block_distance` units; then
   `soundevent_block` always sets a new block for `block_duration` seconds
   (MEGA 1439, 1448). Defaults: match on, entity on, **0.01 s, 12 units**.
   `block_other` blocks events whose names contain `block_other_name` for
   `block_other_duration` within `block_other_distance`.
6. **Children.** `soundeventdata_start` starts `soundevent_01` (a list) when
   `enable_child_events` is set, passing `public.position` down (MEGA 1534).
   This is how a gunshot's distant layer starts.
7. **Who hears it.** Both the file and the children start only when
   `is_local_player_slot(relevant_player)` is true (MEGA 1522); the default
   `relevant_player -1` means everyone (*Inferred*). Events tagged
   `metadata ["meta", "localplayeronly"]` (draws, inspects, silencer screws,
   `WeaponMove*`) are heard only by the player who makes them (*Inferred*
   from the tag; no stack operator reads it, so the game code filters).
8. **Random volume and pitch.** `volume + random(volume_random_min,
   volume_random_max)` and `pitch + random(pitch_random_min,
   pitch_random_max)`, drawn once at start (`execute_once`, MEGA 2037, 2051).
   Additive, not multiplicative. The file is picked with
   `array_selection_type random_exclusive` (no immediate repeat) (MEGA 1169).
9. **Volume.** The distance curve is read at `distance_after_suppression`
   (MEGA 2096), and the final gain is the product (MEGA 2240
   `math_accumulate12_float mult`):

   ```
   gain = mixgroup_volume
        * (volume + rand_v) * distance_curve(d_after_suppression)
        * fadetime_curve(time since stop) * time_curve(elapsed)
        * impact_speed_curve(impact_speed_input)
        * volume_convar (if use_volume_convar)
        * velocity_curve(velocity_magnitude) (if use_velocity_volume_curve)
        * surf ambient volume (surf servers only)
        * (suppressed ? suppression_volume_multiplier : 1)
   ```

   Each curve factor is 1 when its `use_*` flag is off.
   `use_distance_volume_mapping_curve` defaults on;
   `use_fadetime_volume_mapping_curve` defaults on but gunshots turn it off.
10. **Pitch.** `(pitch + rand_p) * distance_pitch_curve * doppler`. Doppler
    only with `use_doppler` (9 events, all bullet whizzes and molotov loops;
    *Read*, WPN), `input_doppler_observer_scale 0.05`.
11. **Speakers and L/R isolation.** `calc_spatialize_speakers` (radius 15,
    `snd_rear_stereo_scale 1`) gives a legacy per-speaker pan; the voice's
    speaker volumes are `lerp(flat, legacy_pan * gain * 1.5,
    snd_spatialize_lerp * distance_effect_mix)` (MEGA 2292). With the
    default `snd_spatialize_lerp 0` the stack sends the same gain to every
    channel and the positioning is left to the voice graph's Steam Audio
    HRTF, fed by `sos_set_voice_position` and the source angle `ang_y`
    (*Inferred* from the operator names; the voice graph `csgo_voice_main` is
    compiled and not in the repository).
12. **Close-up stereo.** `distance_unfiltered_stereo_mapping_curve` (off by
    default) is read at the distance and sent to the voice graph as
    `unfiltered_stereo` (MEGA 2505). Gunshots have 1.0 at 35 units falling to
    0 at 300 (*Read*, WPN 20510-20525); footsteps 1.0 at 50 to 0 at 59. A
    player's own gun (source 60 units above the feet, ears at 64) and own
    steps are inside the 1.0 zone. *Inferred:* 1.0 plays the file as its own
    stereo, unspatialised; 0 is fully HRTF-positioned, with a crossfade
    between. That is how "your own gun sounds flat" arises in CS2, with no
    special case.
13. **Occlusion.** Section 3.
14. **Reverb and routing.** Section 2.3.
15. **Culling and stopping.** A voice is culled while its distance curve is
    under `voice_culling_threshold 0.001`; looped voices recheck every
    `voice_looped_culling_update_time 0.5` s. A stopped voice fades over
    `voice_fade_out_time 0.2` s, or over the event's fadetime curve when that
    is on (MEGA 2405 `switch_fade_time`, *Inferred* from the switch's
    inputs). `self_destruct_time` stops an event after that many seconds.
16. **Mix layers from events.** `set_mixlayer_amount_enable` with
    `set_mixlayer_layer` drives a mix layer by `time_mixlayer_amount_curve`
    (default 1.0 for 1 s, 0 by 2 s) and keeps the event alive until the curve
    ends (MEGA 2535). Section 2.2 lists the layers.
17. **Mixgroup trigger.** Every event triggers its mixgroup with its final
    gain (`soundmixer_set_trigger`, MEGA 1662), which is what fires the mix
    layers' `Triggers`.

### 1.4 The gameplay events, with CS2's numbers

Volumes are the event's own; multiply by the mixgroup's (section 2.1). Curves
are `distance:volume`. All *Read*.

| Event (file:line) | Vol, pitch | Mixgroup | Limit, block | Occl. (baked flag) | Reverb wet / source wet / dist. effect | Distance curve | Stereo curve |
|---|---|---|---|---|---|---|---|
| `Weapon_AK47.Single` (WPN 20442) | 1.1, 1.0 | Weapons | 1; no block | 0.6 (on) | 1.0 / 1.0 / 1.0 | 25:0.8 30:1 176:1 440:0.735 1288:0.331 2500:0.015 | 35:1 300:0 |
| `Weapon_AK47.SingleDistant` (WPN 20536) | 0.5, 1.0 ±0.02 | WeaponsDistant | 2; entity, 0 s | 0.0 | 1.0 / 1.0 / 0.0; `restrict_source_reverb` | 800:0 2336:0.54 2869:0.096 | 60:1 81:0 |
| `Weapon_AWP.Single` (WPN 18583) | 1.0, 1.0 ±0.03 | Weapons | 1; entity, 0.3 s, 20 u | 0.6 (on) | 0 / 0 / 0 | 176:1 440:0.735 1288:0.331 2800:0.048 | 35:1 300:0 |
| `Weapon_USP.SilencedShot` (WPN 13122) | 0.6 | Weapons | 2 | 0.55 | 0.2 / 0.2 / 1.0 | 25:0.8 30:1 164:1 428:0.62 804:0.23 1300:0.05 1400:0 | 35:1 then 0 |
| `Weapon_M4A1.Silenced` (WPN 14263) | 0.8 | Weapons | 2 | 0.55 | 0.4 / 0.7 / 1.0 | as the USP-S, 25:0.7 | 30:1 35:0 |
| `Weapon_AK47.Clipout` (WPN 20811) | 1.0, +0 to 0.05 | Foley | block 0.1 s, 69 u | 0.4 | 1.0 / 1.0 / 0.5; stealth 0.07 vol, 0.2 falloff | 50:1 267:0.356 1100:0 | 30:1 35:0 |
| `Weapon_AK47.Draw` (WPN 20607) | 0.3 | Foley | 0.1 s | 0.4 | localplayeronly | 397:1 1107:0 | 30:1 35:0 |
| `Concrete.BulletImpact` (PHY 2391) | 1.0, 1.1 ±0.01 | BulletImpacts | 1; 0.1 s, 20 u | 0.8 | 0.5 / - / -; restrict source | 40:1 219:0.332 600:0 | - |
| `Flesh.BulletImpact` (PHY) | 0.7 | PlayerDamage | 1 | 0.8 | 0 | 40:1 249:0.46 600:0 | - |
| `FX_RicochetSound.Ricochet` (WPN 3) | 1.5 | BulletImpacts | 1 | 1.0 | 1.0 | 0:1 41:1 237:0 | 0 everywhere |
| `BulletBy.Supersonic.Crack` (WPN 33452) | 1.0, pitch 1.5 | PlayerDamage | - | 0 | 0; doppler | 0:1 1000:1 | 0 |
| `BaseGrenade.Explode` (HE, WPN 23133) | 1.0 | Explosions | 1 | 0.3 | 0.7 / 0.5 / 0; ducking bypass | 0:1 231:1 779:0.569 2700:0 | 100:1 500:0 |
| `BaseGrenade.ExplodeDistant` (WPN 23206) | 1.5 | ExplosionsDistant | block 0.02 s | 0 | 0.5 / 0.9 / 0 | 504:0 944:1 2800:0.343 | - |
| `Flashbang.Explode` (WPN 22232) | 0.4 | Explosions | - | 0.5 | 0.4 / 0.4 / 0; ducking bypass | 0:1 84:1 2740:0 | 44:1 270:0 |
| `Flashbang.Ring.Long` (WPN 32784) | 0.1 | Explosions | block 0.02 s | 1.0 | `dsp_bypass 1`; time curve 0.93 at 0.1 s, 0.29 at 1.2 s, 0 at 4.2 s | 0:1 2800:1 | 0:1 300:1 |
| `C4.PlantSound` (the beep, `c4_beep2`, WPN 24244) | 0.9 | Weapons | 1 | 0.2 | 0.1 / 1.0 | 0:1 1300:0 | 0 |
| `c4.explode` (WPN 24061) | 0.5 | Weapons | block 0.5 s, 40 u | 0 | 0 | 0:1 1100:1 | 60:1 300:1 |
| `c4.explode.close` (WPN 47043) | 1.0 | Explosions | as above | 0 | 0 | 233:1 1500:0 | 131:1 300:0.51 |
| `c4.shockwave.boom` (WPN 46793) | 1.0 | Explosions | as above; drives the `Shockwave` layer | 0 | 0 | 557:0 1435:1 | 0.73 |
| `Player.DamageBody.AttackerFeedback` (PLY 2677) | 1.0, 1.3 ±0.01 | PlayerAttackerFeedback | 3; 0.05 s | 0 | 0.5 / 0.5 / 0; drives `PlayerAttackerFeedbackLayer` for 0.14 s, gone by 0.31 s | 21:1 1066:0.215 | - |
| `Player.DamageBody.Victim` (PLY 3552) | 1.5, ±0.01, delay 0.05 s | PlayerVictim | 3 | 0 | 0 | 0:1 600:1 | 0.9 flat |

What the table says for a clone (*Inferred* from it):

- **A gunshot is two events.** The near layer (full volume to 176 units, then
  falling to near silence at 2500) and the distant layer (nothing under 800,
  peaking at 2300 to 2350, still 0.096 past 2869). Through the mixgroups an
  AK is -3.6 dB at 50 units, -8.6 dB at 800, -11.4 dB at 1288 (the two
  layers together), -17.7 dB at 2500 and about -28 dB anywhere beyond 2869,
  if the curve holds its end (linear interpolation, mixgroups Weapons 0.6 and
  WeaponsDistant 0.6).
- **The AWP has no reverb at all** (`reverb_wet 0`) and a 0.3 s entity block;
  the AK has full reverb.
- **Your own shot has no pitch randomness** on the AK (only the AWP ±0.03 and
  the distant layers ±0.02 have it).
- **Reloads are Foley**, heard to 1100 units, and their volume is by part
  (clip out 1.0, clip in 0.3, add ammo 1.2, bolt 1.0 on the AK).
- **Bullet impacts are short-range**: silent at 600 units, and a third as
  loud at 219.

## 2. The mixer

### 2.1 Mixgroups and their levels

`MixGroups` defines 60 groups, each with a `parent` (`All`, `UI`, `Ambient`,
`Explosions`, `PlayerDamage`), and every legacy ducking field inert:
`is_ducked 0`, `causes_ducking 0`, `duck_to_percent 100` on all of them
(*Read*, MIX 1-900). `SoundMixers.Default_Mix` (MIX 903) sets each group's
`vol` (volume), `lvl` and `dsp`. The stack multiplies the per-source reverb
by `lvl` and the listener-room reverb by `dsp` (*Read*, MEGA
`mult_source_wet` and `mult_wet`, which read `mixer.output_level` and
`mixer.output_dsp`).

| Mixgroup | vol | lvl (source reverb) | dsp (room reverb) | Used by |
|---|---|---|---|---|
| All | 1.0 | 0.8 | 0.8 | parent of all |
| Weapons | **0.6** | 0.3 | 1.0 | gunshots' near layer, C4 beeps and blast |
| WeaponsDistant | 0.6 | 0.0 | 0.0 | gunshots' distant layer |
| Footsteps | **0.8** | 0.5 | 1.0 | steps and landings |
| Foley | 1.0 | 1.0 | 1.0 | reloads, draws, zooms, inferno |
| Physics | 0.8 | 1.0 | 1.0 | props, grenade bounces |
| BulletImpacts | **0.3** | 1.0 | 1.0 | impacts, ricochets |
| Explosions | **0.7** | 0.3 | 1.0 | HE, flash, C4 close blast |
| ExplosionsDistant | 0.7 | 0.3 | 1.0 | distant layers |
| C4Shockwave | 1.0 | 1.0 | 0.0 | (child of Explosions) |
| PlayerDamage | 1.0 | 1.0 | 1.0 | hit sounds heard by onlookers, whizzes |
| PlayerAttackerFeedback | 1.0 | 1.0 | 1.0 | the shooter's hit confirmation |
| PlayerVictim | 1.0 | 1.0 | 1.0 | the victim's own hit sounds |
| World | 0.4 | 1.0 | 1.0 | map events |
| Ambient | 0.45 | 1.0 | 1.0 | map ambience; each map a child: Dust2 0.4, Inferno 0.402, Mirage 1.0, Nuke 0.15, Overpass 0.728, Vertigo 0.272, Anubis 0.522 |
| UI | 1.0 | 0.1 | 0.1 | menus, HUD beeps |
| VO | **0.34** | 1.0 | 0.0 | radio and agent voice lines |
| voip | 1.0 | 1.0 | 0.0 | other players' voice chat |
| Music, BuyMusic, SelectedMusic, DuckingMusic | 1.0 | 1.0 | 0.0 | music kits |
| KillCard | 1.0 | 0.0 | 0.0 | the kill card |

`MainMenu_Mix` (MIX 1418) is the menu's own: weapons 0.7, world 1.0,
footsteps 1.0, ambient 0.328, impacts 0.2, explosions 1.0, distant
explosions 1.6. `snd_soundmixer "Default_Mix"` (*Read*, CV 9282);
`snd_soundmixer_update_maximum_frame_rate 10`, so the mixer's layers update
at 10 Hz at most (*Read*, CV 9285; *Inferred* meaning).

### 2.2 Mix layers: the ducking

A mix layer multiplies groups' volumes while it is active; it is driven by a
`Trigger` mixgroup (any event in that group playing), by an event's
`set_mixlayer_layer`, or by code (*Read*, MIX 1550-2541, MEGA). The `vol`
column is the target multiplier at full amount (*Inferred*; the `lvl` and
`dsp` columns in layers are left out here, since what 0 means there is not
clear from the files).

| Layer (MIX line) | Driven by | Groups and multiplier | Attack / release |
|---|---|---|---|
| PlayerAttackerFeedbackLayer (2409) | every `*.AttackerFeedback` hit event (PLY) | Ambient, Physics, ExplosionsDistant, WeaponsDistant **0.0** | the event's curve: full for 0.14 s, off by 0.31 s (PLY 2710) |
| Shockwave (2463) | `c4.shockwave.boom` | Ambient, Weapons, World, Physics, Foley, Footsteps **0.0**; WeaponsDistant 0.5 | full to 0.39 s, off at 3.0 s (WPN 46853) |
| DeathFadeLayer (1726) | code: `cl_deathcam_audio_mix_phase1_fade_amount 0.15` over 2 s, then `phase2 0.5` over 0.4 s (*Read*, CV 1026-1036) | World, Physics, BulletImpacts, Ambient 0.01; Weapons, Footsteps, Foley, WeaponsDistant 0.5; Explosions 0.3 | as the convars |
| DuckingMusicLayer (2093) | trigger `DuckingMusic`, which only the music kits' `Music.DeathCam` use (*Read*, music files) | Weapons, World, Footsteps, Foley, Physics, BulletImpacts, Explosions, Ambient, WeaponsDistant, PlayerDamage 0.5; other music 0.1 | 0 / 0 |
| SelectedMusicLayer (1965) | trigger `SelectedMusic` (`Music.Selection`, `MatchStart`, `MatchEnd`) | Weapons, World, Footsteps, Foley, Explosions 0.5; Physics, BulletImpacts, Music 0.0 | 0 / 0.5 s |
| KillCardLayer (1845) | trigger `KillCard` and `UI.KillCard.*` (UI 10435) | Ambient 0; WeaponsDistant 0.2; ExplosionsDistant 0.1; Physics 0.3; Weapons, Explosions 0.7 | 0 / 0.5 s |
| PlayerDamageLayer (2246) | trigger `ArmsRace` (*Read*; looks like a copy slip, *Inferred*) | Ambient 0, World 0.2 | 0 / 0 |
| ArmsRaceLayer (2286) | trigger `ArmsRace` | Weapons 0.6, Ambient 0.3 | 0 / 0.23 s |
| Competitive/Casual/.../WarmupVol (2319-2394) | code, per game mode (`snd_vol_competitive 1` etc., CV 9372-9390) | All | - |

So CS2's ducking is event-driven and short. **No layer ducks music under
gunfire, and nothing ducks the game under voice chat** in these files. When
you land a hit, distant gunfire and ambience drop out for about a third of a
second, which clears the hit confirmation (*Inferred*).

**A second ducker in the voice graph.** Every `csgo_mega` voice is sent to
the `AllVoices` and `reverb` submixes, or, with `ducking_bypass 1`, to
`ducking_bypass_voices` and `ducking_bypass_reverb` instead, as an
equal-power crossfade (*Read*, MEGA 1786-1800 and the four
`vmix_mixgraph_send` operators). 389 events set `ducking_bypass 1`: 387 UI
sounds, `Flashbang.Explode` and `BaseGrenade.Explode` (*Read*, grep of the
event files). *Inferred:* the compiled mix graph ducks `AllVoices` from some
side-chain, and the UI and the two grenade blasts are kept out of it; the
legacy ducker convars (`snd_duckerattacktime 0.5`, `snd_duckerreleasetime
2.5`, `snd_duckerthreshold 0.15`, `snd_ducktovolume 0.55`, CV 8799-8808) may
be its settings or leftovers. What drives it is not in the repository (Local
check A5).

### 2.3 Reverb

- **Two reverbs per sound.** The listener's room (`RoomDSP`, from the map's
  soundscapes) and the source's own (`soundmixer_get_source_dsp_preset` by
  the source's mixgroup and distance, blended by `dsp_blend`) (*Read*, MEGA
  1705-1745). `restrict_source_reverb` swaps the source's preset for
  `reverb_0_null`; `override_dsp_preset` with `dsp_preset` forces the room's
  (UI sounds use `reverb_29_UI`, one player event `reverb_24_largeBathroom`;
  *Read*, UI 13635, PLY 5549).
- **The amounts.** Source wet = preset mix * `reverb_source_wet` * mixgroup
  `lvl`. Room wet = `reverb_wet` * DMM modifier(room preset, mixgroup,
  distance) * mixgroup `dsp`; the event's dry and wet then split by an
  equal-power crossfade (*Read*, MEGA).
- **The per-room table** (DMM, 27 presets, `reverb_0_null` to
  `reverb_25_massiveHanger` and `reverb_29_UI`) scales each mixgroup's room
  reverb from `m_flModifierMin` (at the near blend distance) to
  `m_flModifier` (far) (*Read*; schema `soundsystem/CDSPMixgroupModifier.h`
  describes the two ends). Examples: `reverb_22_outsideOpen` is 0 for every
  gameplay group (open air, no room reverb); `reverb_6_largeRoom` gives
  Weapons 0.4, Footsteps 0.2 to 0.5; `reverb_13_largeBright` gives Weapons 0.5
  near to 0.05 far. *Inferred:* the blend distances are `snd_dsp_distance_min
  20` and `snd_dsp_distance_max 2000` (CV 8793-8796).
- **Steam Audio's own reverb is off**: `snd_steamaudio_enable_reverb 0`,
  `snd_steamaudio_reverb_level_db -3` (*Read*, CV 9306, 9318).

### 2.4 Flashbang and HE deafness

- The server DLL names four controls, `control.deafenHE`,
  `control.deafenLong`, `control.deafenMedium`, `control.deafenShort` (*Read*,
  SS 25827-25830), next to the events `Flashbang.Ring.Long/Medium/Short`
  (*Read*, SS 16279-16281). *Inferred:* the server picks the strength by how
  flashed the player is (or HE for a close blast) and the client's mix graph
  muffles the mix for it; the ring itself is played with `dsp_bypass 1`, so it
  goes around that muffling (MEGA `submix_dsp_bypass_send`).
- **The ring's shape** (*Read*, WPN 32784-33020): `explosion_ring.vsnd` at
  volume 0.1 (Explosions 0.7), a time curve rising to 0.93 at 0.1 s and
  gone by 4.18 s (Long), 3.0 s (Medium), 2.0 s (Short); its distance curve is
  flat to 2800, so it does not fade with distance.
- **The legacy presets** in core's DSP: `core.flashbang.muffle.long/medium/
  short` (presets 134-136; 5.5 s, 1.4 s, 0.7 s; a diffusor and a 3000 Hz sine
  at gain 0.05) and `core.grenade.shock.ring1-3` (137-139; low-pass at 4000,
  2000, 1000 Hz with a 3000 Hz tone, 1 s, 1.5 s, 3 s) (*Read*, DSP 953-1025).
  The client DLL still has `dsp_player` (*Read*, CS 32257). Whether CS2's
  deafen controls use these numbers is unknown (Local check A6).

### 2.5 Voice, voice lines and music

- **Voice chat is not positional.** The `csgo_voip` stack has no position and
  sends one flat gain to every speaker, mixgroup `voip`, submix `VOIP` (*Read*,
  STK core). `snd_voipvolume 1` (0 to 2) (*Read*, CV 9369). LOC still has
  "Other Player Voice Positionality" but the menu has no such control (*Read*,
  LOC 44663, MENU).
- **Radio and agent lines** are mixgroup `VO` at 0.34 (*Read*, MIX; 14,623 VO
  events). `snd_gamevoicevolume 1` (*Read*, CV 8868).
- **Music** volumes by moment, competitive defaults (*Read*, CV 8760-9351):
  menu 0.04, round start **0**, round action **0**, round end 0.16, MVP
  0.16, bomb planted 0.04, ten-second warning 0.04, death camera 0.16. Each
  has casual, deathmatch, arms race and rush copies. `snd_musicvolume 1`.

## 3. Occlusion and transmission

- **Per event.** `occlusion_intensity` (default 0) turns occlusion on and sets
  how strongly it applies; `occlusion_frequency_scale` (default 1) scales the
  filter; `occlusion_interval` (default 1 s) only paces the baked lookup
  (*Read*, MEGA 781-832, 1593-1660).
- **What the stack does with it.** `calc_occlusion_info` runs whenever
  `occlusion_intensity` is non-zero, from the source to the listener. Its
  output * `occlusion_frequency_scale` is sent to the voice graph as
  `eq_occlusion`, and `occlusion_intensity` (or 1 when the product exceeds 1)
  as `eq_occlusion_mix` (*Read*, MEGA 2463-2476). *Inferred:* occlusion is a
  filter (an EQ, darker as occlusion rises) mixed in at the event's
  intensity, not a plain volume cut. Gunshots 0.6, silenced shots 0.55,
  reloads and draws 0.4, footsteps 0.375 (`footsteps.md`), impacts 0.8,
  deaths 0.9, HE 0.3, the C4 beep 0.2, distant layers 0, the C4 blast 0.
- **Baked occlusion is off.** `use_baked_occlusion` on an event only counts
  when `snd_use_baked_occlusion` is 1 (`math_float and`, MEGA 1598), and the
  convar is **0**, `replicated cheat release` (*Read*, CV 9363). So the
  `use_baked_occlusion true` on gunshots and steps does nothing in a normal
  match, and the `occlusion_path_curve` (a curve over `1 / (1 - baked
  occlusion)`, fed as `input_indirect_override`) is unused.
- **The runtime method.** The sound system's strings describe it (*Read*,
  SND): "path from ... encountered one wall. surface = %s (occlusion =
  %0.2f), thickness = %.2f"; "occlusion factor %.2f based on direct path;
  indirect ratio of %.2f based on finding %.2f paths lerped between %.2f and
  %.2f"; "Occluded by audio blocker". Its convars (*Read*, CV 8997-9027):
  `snd_occlusion_rays 4`, `snd_occlusion_bounces 1`,
  `snd_occlusion_min_wall_thickness 4`, `snd_occlusion_indirect_radius 120`,
  `snd_occlusion_indirect_min 0.01`, `snd_occlusion_indirect_max 0.7`.
  *Inferred:* one direct ray gives a factor from each wall's surface
  (`occlusionFactor`, a field of every physics surface, schema
  `modellib/CPhysSurfacePropertiesAudio.h`) and thickness (walls under 4
  units ignored); four rays within 120 units look for indirect paths, and the
  share that get through, mapped into 0.01 to 0.7, softens the result. The
  per-surface `occlusionFactor` values are in the compiled physics surface
  list, not in this repository (Local check A3).
- **Steam Audio's surface table** (SAS, 45 surfaces, 11 bands each of
  scattering, absorption and transmission) is for the baked data and Steam
  Audio's own simulation; with baking and Steam Audio reverb off it does not
  shape a normal match (*Inferred*). Its transmission, lowest band first
  (*Read*):

  | Surface | Transmission, band 1 / 2 / 3 / 5 / 11 |
  |---|---|
  | concrete, plaster, tile, rock | 0.001 / 0.001 / 0.001 / 0 / 0 |
  | solidmetal | 0 everywhere |
  | default | 0.015 / 0.002 / 0.001 / 0.002 / 0.002 |
  | Wood | 0.95 / 0.35 / 0.11 / 0.02 / 0 |
  | glass | 0.98 / 0.25 / 0.06 / 0.001 / 0 |
  | sheetrock | 0.3 / 0.4 / 0.5 / 0.01 / 0 |
  | cardboard | 0.99 / 0.98 / 0.95 / 0.8 / 0.01 |
  | player | 0.95 / 0.9 / 0.8 / 0.5 / 0.01 |
  | chainlink, metalgrate | 0.1 / 0.05 / 0.01 / 0.01 / 0 |
  | audioblocker | 0, absorbs 1.0 |

  Band frequencies are not in the file. The pattern is the useful part: wood,
  glass and thin walls pass the lows only; concrete and metal pass nothing.
- **Client or server.** The occlusion convars are `replicated` (the server's
  value is enforced on clients) and `cheat` (*Read*, CV). The operator runs
  in the client's sound stack. *Inferred:* occlusion is computed on the
  client only, per playing voice; the server never traces for sound. Bots'
  hearing is separate (`footsteps.md` section 6).
- **History.** "Lowered occlusion and distance effects for gunfire,
  footsteps and reloads" (*Valve*, release notes, 13 Sep 2023), then
  "Improved occlusion filter quality" (*Valve*, 9 Nov 2023) and "Further
  reduced occlusion effects" (*Valve*, 7 Feb 2024). Vertical occlusion has
  its own map layer: "Added unique audio occlusion layer to help with
  vertical sound positioning in Nuke" (*Valve*, 30 Jun 2023), and "Vertical
  occlusion is now more gradual at the edges of transition points in Nuke
  and Vertigo" (*Valve*, 1 Apr 2026). The steady lowering fits the moderate
  intensities above. An earlier draft of this page cited a "slight increase
  to stereo spread" from a search summary; Valve's archived notes have no
  such line, so it is dropped. Full dated list in section 8.

## 4. HRTF, spatialisation and the audio settings

- **HRTF is always on.** The HRTF is Steam Audio's, inside the voice graph
  (schema `soundsystem_lowlevel/CVMixSteamAudioHRTFProcessorDesc.h`: position
  X/Y/Z, interpolation, direct mix level, **perspective correction**,
  relative position, left and right delay) (*Read*). The menu has no HRTF
  switch (*Read*, MENU), and two custom HRTFs ship for testing,
  `dev/hrtfs/d1_44k.sofa` (-7.5 dB) and `h12_44k.sofa` (-16.5 dB) (*Read*,
  `custom_hrtfs.txt`); `snd_steamaudio_enable_custom_hrtf` and
  `snd_steamaudio_active_hrtf` exist (*Read*, SA 7531-7556). Community
  guides agree there is no HRTF toggle (*Community*, csdb.gg/guides/audio-guide/,
  undated).
- **Vertical.** An HRTF encodes elevation, which a stereo panner cannot
  (*Inferred*). `snd_hrtf_distance_behind 0` "HRTF calculations will
  calculate the player as being this far behind the camera" (*Read*, CV
  8895).
- **The settings menu** (*Read*, MENU; tooltips from LOC 44580-44725;
  defaults from CV unless marked):

  | Setting | Convar | Values | Default |
  |---|---|---|---|
  | Master Volume | `volume` | 0 to 1 | 1 |
  | Main Menu Ambience Volume | `snd_menumap_volume` | 0 to 1 | 1 |
  | Audio Device | `sound_device_override` | device list | "" |
  | EQ Profile | `snd_headphone_eq` | 0 Natural, 1 Crisp, 2 Smooth | 0 |
  | L/R Isolation | `snd_spatialize_lerp` | 0 to 100 % | 0 ("Physically Accurate (default)") |
  | Perspective Correction | `snd_steamaudio_enable_perspective_correction` | Yes / No | Yes (tooltip says default; the convar lives in `steamaudio.dll`, not in CV) |
  | Play Audio When Game In Background | `snd_mute_losefocus` | Yes = 0 | 1 (muted) |
  | Other Player Voice Volume | `snd_voipvolume` | 0 to 1 in the menu (0 to 2 by convar) | 1 |
  | Enable Voice | (code) | Disabled, Push to Talk, Open Mic | - |
  | Microphone threshold | `voice_threshold` | -120 to 0 dB | -120 |
  | Music: master, and eight moments per mode | `snd_musicvolume`, section 2.5 | 0 to 1 | section 2.5 |
  | Mute MVP music while players are alive | `snd_mute_mvp_music_live_players` | Yes / No | 0 |
  | EQ per game mode (Advanced) | `snd_eq_competitive`, `_casual`, `_deathmatch`, `_arms_race` | -1 (use EQ Profile), 0, 1, 2 | -1 |

- **What they mean, in Valve's words** (*Read*, LOC 44593, 44673, 44675):
  Crisp "Enhances mid and high frequency bands. Can help with sound
  localization and reduce muffling"; Smooth "Reduces mid to high frequencies.
  Can help reduce harshness, volume spikes, and ear fatigue". L/R Isolation
  100 %: "Sound emitters that are directly to the side of the player will be
  hard panned with minimal blending into the opposite L/R channel ... For
  players who prefer legacy sound panning behaviour." Perspective Correction
  Yes: sounds "rendered accurately with respect to your field of view as you
  look at the pc screen. Sound emitters that are on the edge of your field of
  view will sound slightly in front of you"; No: they "sound strongly panned".
  `snd_steamaudio_perspective_correction_front_only true` limits it to the
  front (*Read*, CV 9315); `snd_steamaudio_perspective_correction_factor`
  exists (*Read*, SA 7592).
- **How L/R Isolation works** (*Read*, MEGA 2292; *Inferred* reading): it
  crossfades each sound from the HRTF-only path to the legacy speaker pan
  (scaled 1.5), by `snd_spatialize_lerp * distance_effect_mix`. So sounds with
  `distance_effect_mix 0` (distant layers, grenades, the AWP, hit feedback)
  never get the legacy pan, whatever the slider says.
- **When.** EQ Profile, L/R Isolation and Perspective Correction appeared at
  CS2's launch; a player posted them as new on 27 Sep 2023 (*Community*,
  https://x.com/ThourCS2/status/1707137324210094464, date from the post's id).
  A survey of 35 pros on 1 Nov 2023 found Natural, 0 % and Yes most common
  (*Community*, https://x.com/ThourCS2/status/1719693299500384554). The
  speaker-configuration menu ("Audio Output Configuration") is gone from the
  menu; its strings and `speaker_config -1` remain (*Read*, LOC 44604, CV
  9510).

## 5. How sounds reach clients

- **Sound events on the wire** (*Read*, PB `gameevents.proto`):
  `CMsgSosStartSoundEvent` (game event 208) carries `soundevent_guid`,
  `soundevent_hash` (the name's hash), `source_entity_index`, `seed`,
  `packed_params` (the public fields set by code, such as a position) and
  `start_time`; `CMsgSosStopSoundEvent` (209), `CMsgSosStopSoundEventHash`
  (212), `CMsgSosSetSoundEventParams` (210). Both DLLs have
  `StartSoundEventReliable`/`Unreliable` and `...FromPosition...` (*Read*, SS
  21786-21791, CS 25991-25996). *Inferred:* the seed makes every client pick
  the same file and random pitch; one-shots like shots are unreliable,
  state-like sounds reliable.
- **Gunshots of others.** `CMsgTEFireBullets` (CS game event 452) carries the
  shooter, origin, angles, weapon, `seed`, `sound_type`,
  `sound_dsp_effect`, `ent_origin`, `player_inair`, `player_scoped`, `tick`
  (*Read*, PB `cs_gameevents.proto`), and both DLLs have `FX_FireBullets`
  (*Read*, SS 16043, CS 18561). *Inferred:* each client plays other players'
  shots, tracers and impacts from this one message; the shooter's own client
  plays its own shot, impacts included, from prediction when it fires, and the
  server leaves the shooter out of the message. The `Single` event's
  `broadcast_distance_override 9000` is read by the server (*Read*, SS 31492
  `public.broadcast_distance_override`; WPN on 38 gunshots); *Inferred:* the
  server sends a shot to clients within 9000 units, most of any map.
- **Weapon sounds by message.** `CCSUsrMsg_WeaponSound` (user message 369):
  `entidx`, origin, `sound` (the event name), `game_timestamp`,
  `source_soundscapeid`, and `stealth` (*Read*, PB `cstrike15_usermessages.proto`
  236-244). The weapon networks `m_bStealthy`,
  `m_bInSilentReloadSection`, `m_flStealthHoldStartTime` (*Read*, SCH
  `server/CCSWeaponBase.h`). *Inferred:* reload and handling sounds reach
  others this way, with `stealth` set during a silent reload so the stack's
  suppression (section 1.3, step 3) applies.
- **Silent reload** (22 Sep 2026, "Rush Hour" update: hold Reload for a
  slower, silent reload; unscoping is now silent) (*Valve*, release notes,
  22 Sep 2026: "Players can now reload silently (but slowly) by pressing
  and holding the reload key" and "Un-scoping a sniper weapon no longer
  produces a sound"). In this build 154
  weapon events have `suppression_enable true`, `suppression_volume_multiplier
  0.07`, `suppression_falloff_multiplier 0.2` (*Read*, WPN). So a stealthy
  AK clip-out plays at 0.07 of its volume (-23 dB) and reaches the silence at
  1100 / 5 = **220 units**: silent to anyone but the reloader (*Inferred*).
  The reload clip marks the silent stretch: `WPN_RELOAD_SILENT` from 0 to
  1.9 s of the AK's 2.43 s clip, 2.07 s of the M4A1-S's 3.07 s (*Read*, this
  repo's `reference/weapons/timings.csv:890, 941`, from 1.41.8.2).
- **Footsteps** are sent by the server, up to `sv_max_distance_transmit_footsteps
  1250` (`footsteps.md` section 4). No other `sv_max_distance_transmit_*`
  convar exists (*Read*, CV).
- **Legacy paths** remain: `svc_Sounds` (`CSVCMsg_Sounds`, with
  `sound_level`) and `CUserMessageSendAudio` (*Read*, PB `netmessages.proto`
  248, `usermessages.proto` 225). The explosion temp entity carries a
  `sound_name` (*Read*, PB `te.proto` 184).
- **Bullet whizzes** are client-side: the event names are only in the client
  DLL (*Read*, CS 13260-13263); the trigger distance is in `combat.md` (R4).

## 6. What this means for our Godot build

Godot's `AudioStreamPlayer3D` (read from `godotengine/godot` master,
`scene/3d/audio_stream_player_3d.cpp`): attenuation is inverse
(`unit_size / d`), inverse square, logarithmic or disabled, capped at
`max_db` (+3 dB); with `max_distance` set it is also multiplied by
`1 - d / max_distance`; and a low-pass (`attenuation_filter_cutoff_hz` 5000,
`attenuation_filter_db` -24) deepens as the gain falls,
`(1 - gain) * -24 dB` (*Read*, that file 235-250 and 473-489). Panning is
stereo, scaled by the project's `audio/general/3d_panning_strength` (default
0.5) times the player's `panning_strength`. `Area3D` can route sounds that
start inside it to a reverb bus. There is no HRTF and no occlusion.

| CS2 feature | Godot mapping | Where it runs and its cost |
|---|---|---|
| Sound event data | A resource per event (volume, pitch and random ranges, mixgroup, curves as point lists, limits, blocks, child events, occlusion and reverb amounts, stereo curve), generated from the `.vsndevts` text by a script into `reference/` like the other generated tables | Loaded once; nothing at play time |
| Distance curve | `ATTENUATION_DISABLED`, and `volume_db` set from the curve by the listener distance each frame (or once at start for sounds under half a second) | Per frame on the client, one distance and one curve lookup per playing sound; nothing on the server |
| Distant layer | A second player started with the first, its own curve and mixgroup | Client only |
| Mixgroups | One Godot bus per gameplay group (Weapons, WeaponsDistant, Footsteps, Foley, Physics, BulletImpacts, Explosions, PlayerDamage, UI, VO, Music, Ambient), bus volume = CS2's `vol` | Client only; buses cost a mix each, a dozen is nothing |
| Mix layers | A small table: layer, groups, multipliers, attack and release; the view that starts a hit-feedback or shockwave event ramps the bus volumes | Client only, per frame |
| Instance limit, blocking | Per entity and event, a count and a last-start time checked before playing | Client only; a dictionary lookup per start |
| Random pitch, volume | Per event ranges, additive, drawn once; CS2's seed if two clients must agree | Client only |
| Close-up stereo | For a source within the curve's 1.0 zone, a plain `AudioStreamPlayer`; between, lower `panning_strength` by the curve | Client only |
| L/R Isolation | Our panner is already the "legacy" kind; the slider could map to `panning_strength` (0 % to today's 0.5, 100 % to 1.0) | A setting |
| Occlusion | At start and every 100 ms, one ray from listener to source on the world layer; hull part names give the surface as footsteps do; the result picks the sound's bus among a few low-passed copies (for example clear, light, heavy) at the event's `occlusion_intensity` | Client only, per frame budget: with 20 sounds playing, 200 rays a second, about the cost of a few footsteps' surface checks. Never on the server tick |
| Reverb | Per room zone an `Area3D` with a reverb bus (source-based, like CS2's source DSP); the listener's zone sets a global reverb send (like `RoomDSP`); per mixgroup wet from DMM | Client only |
| EQ profiles | An `AudioEffectEQ` on the master bus with three presets | Client only |
| Flash and HE deafness | A low-pass and volume dip on the game buses by flash strength, with the ring on a bus outside it (as `dsp_bypass`) | The strength is game state already (flash duration); the effect is client only |
| Steam Audio | The `godot-steam-audio` GDExtension (HRTF, occlusion and transmission, ray-traced reverb; alpha, Godot 4.4, forks built for 4.7) (*Community*, https://github.com/stechyo/godot-steam-audio, undated) | Client only, but a native dependency; a measured option, not a first step |
| Sending | Game events on the `GameWorld` tick: shot (as fire-bullets), reload part with `stealth`, footstep, explosion; a client plays them per frame | Server: one event append per sound per tick; when networked, a squared-distance check per event per client for the 1250 (steps) and 9000 (shots) culls |

The rule that follows from `CLAUDE.md`: what decides the game (a shot, a
step, a reload being stealthy, a flash's strength) is state on the tick; what
is heard (curves, occlusion, reverb, mix layers) is a view, per frame, on the
client. None of section 6 adds hull traces to the tick.

## 7. Where ours differs (main 3975eef)

| Ours | CS2 | Change |
|---|---|---|
| `weapon_sounds.gd:56-68`: bots' guns at inverse distance, `unit_size` 20 m (787 units), `max_distance` 300 m, and Godot's automatic low-pass | Per-event curve; near layer 1.0 to 176 units, 0.015 at 2500; distant layer 800 to 2869 | Curve-driven `volume_db`, `ATTENUATION_DISABLED`, and the distant event |
| `weapon_sounds.gd:34`: `FIRE_DB -6` | AK 1.1 * Weapons 0.6 = -3.6 dB; AWP 0.6 = -4.4 dB | Per-event volume times mixgroup |
| `weapon_sounds.gd:51`: fire polyphony 4, shots overlap | `instance_limit 1` per entity, oldest stopped with a 0.2 s fade (AK, AWP); 2 for silenced | Max polyphony 1 (2 for silenced), relying on Godot's stop |
| `sound_bank.gd:88`: `random_pitch 1.05` for every set | AK shot no pitch variance; AWP ±0.03; distant ±0.02; reload parts +0 to +0.05 | Per-event ranges |
| `weapon_sounds.gd:21`: AK fire stem `ak47_0` takes `ak47_01..04` | `Weapon_AK47.Single` plays `ak47_01`, `_02`, `_04` only (WPN 20487-20491) | Drop `_03` (the event lists the files) |
| `weapon_sounds.gd:23`: AK reload at 0.45 s clip-out, 1.35 s `ak47_addammo_02`, 2.0 s `ak47_boltpull_0*` | Clip events: Clipout 0.367 s, Clipin 1.067 s (`weapons/magazine_slide_01`), AddAmmo 1.1 s (`ak47_addammo_02`), BoltPull 1.6 s (`ak47_boltpull_01` only) (`timings.csv:892-898`) | Take times and files from the clip and the events |
| `weapon_sounds.gd:27`: M4A1-S reload 0.55, 1.6, 2.25, 2.6 s | Clipout 0.433, Clipin 1.167, AddAmmo 1.367, ClipHit 2.0 s (`timings.csv:942-947`) | As above |
| `bot.gd:150` via `weapon_sounds.gd:75`: a bot's draw plays in the world | `*.Draw` is `localplayeronly` | Play draws for the local player only |
| `bot.gd:392-394`: a bot's reload is silent | Reload parts heard to 1100 units (Foley) | Play bots' reloads spatially |
| `weapon_sounds.gd:108-115`, `HIT_DB -3`: one hit sound for the shooter | Three views of a hit: AttackerFeedback (ducks distant sounds 0.3 s), Onlooker, Victim, each with its own volume and range (PLY 2677-4108) | Split when hit sounds are rebuilt |
| `bullet_impacts.gd:70, 85-86`: -20 dB, inverse from 4 m, cut at 80 m (3150 units) | Impacts 1.0 * BulletImpacts 0.3 (-10.5 dB), 0.33 at 219 units, **silent at 600**; one per surface event at a time, 0.1 s block within 20 units | Curve and cut at 600 |
| `c4_view.gd:18-19, 80-81`: stems `c4_beep` (takes every `c4_beepN`), `c4_explode`; inverse distance from 10 m and 60 m, to 300 m | Beep = `C4.PlantSound`, `c4_beep2` only, 0.9 * 0.6, linear to 0 at 1300 units; blast = `c4.explode` (`c4_explode1`, 0.5, flat to 1100) + `c4.explode.close` + `c4.shockwave.*` with the Shockwave duck | Name the files; curves; the blast's layers |
| `footsteps.gd:60-62` | see `footsteps.md` section 4 | - |
| Views start sounds from `shot_traced`, a signal fired inside the tick (`player_sim.gd:138`, `player_view.gd:157-160`, `bot.gd:381-384`) | The server sends events; clients play them | The tick emits events on the `GameWorld`; views play them in `_process` |
| No buses (no bus layout in the project) | 60 mixgroups, layers | Add the bus layout |

## 8. Dated history from Valve's release notes

Every line below is *Valve* (release notes, the date given), from the
archive named in the source key. It shows which parts of the design above
are recent and which have been stable since launch. The file state in
sections 1 to 5 is build 2000915 (23 Sep 2026), so it already includes all
of these.

**Mix and ducking**

| Date | Valve's line | What it means for this page |
|---|---|---|
| 24 Mar 2023 | "Lowered volume of flashbang ringing and volume ducking effect" | Deafness ducking has been tuned down since the limited test |
| 30 Jun 2023 | "Added distance effects to all positional sound sources"; "Improvements to 3d sound processing"; "Fixed a bug where some sounds would be slightly louder or quieter depending on the listeners orientation" | The distance-effect and spatial paths in section 1.3 date from here |
| 15 Aug to 13 Sep 2023 | "Audio mix tweaks and adjustments" (15 Aug, 18 Aug, 8 Sep); "Audio mix changes and tweaks" (13 Sep) | Mixgroup levels moved often before release; only build 2000915's numbers should be copied |
| 9 Nov 2023 | "Changed jump land sounds to have the same maximum audible distance as footstep sounds"; "Changed volume falloff curve of jump landing sounds to better convey distance"; "Reduced the maximum audible distance of grenade bounce sounds" | Landings share the footstep range |
| 7 Feb 2024 | "Minor mix adjustments"; "Fixed an issue where some player-centric sounds were being perceived as originating from slightly behind the player"; "Replaced the M249 fire sound effect" | |
| 7 May 2025 | "Removed snd_setmixer, snd_setmixlayer, snd_soundmixer_setmixlayer_amount, and snd_soundmixer_set_trigger_factor console commands" | Players can no longer change the mix from the console; the mix is Valve's only |
| 15 May 2025 | "Body shot impact sounds from the attacker perspective will momentarily reduce the volume of weapon fire and ambience to help ensure feedback remains audible"; "Shortened front end of the AK-47 fire sound" | Confirms the PlayerAttackerFeedbackLayer in section 2 (the file mutes WeaponsDistant, Ambient, Physics and ExplosionsDistant for about 0.3 s) |
| 1 Apr 2026 | "Mix adjustments to help accentuate jump landing sounds during combat"; "Mix tweaks while taking damage"; "Fixed bug where DeathCam music cue was causing volume ducking for too long"; "Minor adjustments to ambient sound levels" | The DuckingMusic trigger from `Music.DeathCam` (section 2) was shortened here |
| 28 Apr 2026 | "Minor mix changes and adjustments" | |
| 22 Sep 2026 | "Players can now adjust music volume per game-mode" | In build 2000915 the menu has a `snd_music_settings_mode` dropdown (Competitive, Casual, Arms Race, Deathmatch, Rush) and per-mode copies of each music slider, such as `snd_roundstart_volume_casual` and `snd_mvp_volume_rush` (*Read*, MENU 156-309). Music only; the game mix is the same in every mode |

**Occlusion**

| Date | Valve's line |
|---|---|
| 30 Jun 2023 | "Fixed bug where sometimes sounds would not respect the occlusion values of surrounding geometry resulting in sources appearing closer than what they were"; "Added unique audio occlusion layer to help with vertical sound positioning in Nuke" |
| 13 Sep 2023 | "Lowered occlusion and distance effects for gunfire, footsteps and reloads" |
| 16 Sep 2023 | "Tuned the vertical audio occlusion of grenade sounds in Nuke and Vertigo" |
| 17 Oct 2023 | "Various tweaks and bug fixes around occlusion filters and footstep clarity" |
| 9 Nov 2023 | "Improved occlusion filter quality" |
| 7 Feb 2024 | "Further reduced occlusion effects" |
| 1 Apr 2026 | "Vertical occlusion is now more gradual at the edges of transition points in Nuke and Vertigo" |

*Inferred:* the per-map vertical layers for Nuke and Vertigo are map data,
not the runtime ray traces of section 3; they are a Local check (open
Nuke's sound data in Source 2 Viewer). For our build, Valve's direction
since 2023 is less occlusion, applied as a filter, which is what section 6
recommends.

**Spatialisation, latency and settings**

| Date | Valve's line |
|---|---|
| 6 Jun 2023 | "Player's own footstep sounds are now predicted on the client for a latency-independent experience" |
| 13 Sep 2023 | "Allow adjusting individual player voice volumes" |
| 28 Sep 2023 | "Weapon sounds will no longer sound like they come from the spot you are zoomed into" |
| 9 Nov 2023 | "The visual and audio feedback from sub-tick input ... will now always render on the next frame" |
| 13 Nov 2024 | "Added damage prediction settings. Damage prediction allows clients to immediately play the audio/visual effects of inflicting damage without waiting for confirmation from the server" |
| 7 May 2025 | "Added "Main Menu Ambience Volume" setting" |
| 29 Oct 2025 | "Added scope in/out sound prediction to play immediately for local player" |
| 21 Jan 2026 | "Reduced audio output latency"; "Ambient sounds no longer restart from the beginning when transitioning between zones"; "Weapon, knife and utility draw sounds no longer overlap when switching quickly between them" |

The archived notes have no line announcing Steam Audio, HRTF, EQ Profile,
L/R Isolation or Perspective Correction. They shipped with CS2's release
(27 Sep 2023) without a note, so their date rests on the *Community* posts
in section 4; no primary dated source exists for them.

**Footsteps and the stealth rules** (for `footsteps.md`)

| Date | Valve's line |
|---|---|
| 2 Oct 2024 | "Fixed an issue where step sounds would play for the local player but fail to broadcast to other players and vice-versa" |
| 1 Oct 2025 | "Keychains will now slightly jolt when a player makes an audible footstep sound" |
| 20 May 2026 | "Adjusted material blending to improve accuracy of footstep sounds" |
| 22 Sep 2026 | Silent reload and silent unscoping (section 5) |

## 9. What players criticise and want

Most forum pages refuse fetches, so these are search summaries, CS2-era
unless marked. Each with what it could mean for us.

| Complaint or wish | Source and date | For our build |
|---|---|---|
| Gunfire and grenades far louder than footsteps; turning up to hear steps makes shots painful; players use Windows loudness equalisation or third-party compressors | *Community*, https://steamcommunity.com/app/730/discussions/0/1700542332320128702/ (undated in the summary); https://centerpointgaming.com/soundv2.html (2026 guide) | CS2's own numbers already put steps (0.8 * 0.9 = 0.72) near a close AK (0.66), so the complaint is about peaks. **Option:** a master-bus compressor/limiter preset ("night mode"), measured by the peak-to-step ratio at fixed distances. Client only, zero server cost |
| Separate volume sliders (guns vs steps) | *Community*, https://csgo-guides.com/gameplay/sound (2025) and centerpointgaming (2026) | Our buses make this a slider per bus. Client only. Competitive fairness: it changes nothing a player could not do with an EQ |
| Muffled, "underwater" sound; the forced 3D processing | *Community*, https://steamcommunity.com/app/730/discussions/0/3881597531956789677 (2023-2024 per the summary) | Godot has no HRTF, so we start clear. **Option:** occlusion strength as a measured setting, and Steam Audio's HRTF only as an opt-in |
| Misleading direction: steps heard from the wrong angle; players turn Perspective Correction off or set L/R Isolation to 50-100 % | *Community*, same thread; https://x.com/ThourCS2/status/1709531273125920784 (4 Oct 2023: Crisp, 50-65 %, No); pro survey 1 Nov 2023 (Natural, 0 %, Yes) | Offer the L/R slider as panning strength; measure localisation error with a blind test (direction guessed vs true) per setting |
| Up versus down is hard to tell | *Community*, https://dovesonic.com/guides/cs2-audio-settings (2026) and Steam threads (undated) | A stereo panner cannot encode elevation. **Option:** a small, measured cue by height difference (a gentle low-pass for sources below, or a level offset), tested blind like the above; client only |
| Sound through walls that is not believable | *Community*, https://steamcommunity.com/app/730/discussions/0/1480982971182909333/ (thread title "Valve need to fix this new occlusion sounds!!!", undated) | Keep occlusion a filter, never a big cut, as CS2 does since Sep 2023; tune per surface with the numbers in section 3 |
| Loud reloads give positions away (answered by Valve with silent reload, 22 Sep 2026) | *Valve*, release notes, 22 Sep 2026 | Copy it: the stealth flag is tick state from the reload's `WPN_RELOAD_SILENT` window and the held key; the sound side is two multipliers |
| Surround (5.1) users lose rear channels; no speaker menu | *Community*, the muffled-sound thread above (2023-2024) | Out of scope; Godot supports 5.1 output if ever wanted |

## 10. Corrections for other docs and code

Not made here; each belongs to whoever owns the file.

- `src/audio/weapon_sounds.gd:56-68`: guns fall off by CS2's per-event curve
  (section 1.4) with the distant layer, not inverse distance to 300 m.
- `src/audio/weapon_sounds.gd:34-36`: `FIRE_DB`, `HANDLING_DB`, `HIT_DB`
  become each event's volume times its mixgroup's (section 2.1).
- `src/audio/weapon_sounds.gd:51`: fire polyphony 1 for unsilenced guns, 2
  for silenced (`instance_limit`).
- `src/audio/weapon_sounds.gd:21`: the AK's shot set is `ak47_01`, `_02`,
  `_04` (WPN 20487-20491).
- `src/audio/weapon_sounds.gd:23, 27`: reload times and files from the clip
  events (`reference/weapons/timings.csv:892-898, 942-947`) and the events'
  files (clip-in is `weapons/magazine_slide_01` for the AK).
- `src/audio/sound_bank.gd:88`: `random_pitch 1.05` for all sets; CS2's
  ranges are per event (none on the AK shot).
- `src/bots/bot.gd:150` (with `weapon_sounds.gd:75`): no world draw sound;
  `bot.gd:392-394`: bots' reloads should be heard.
- `src/combat/bullet_impacts.gd:70, 85-86`: CS2's impact curve, silent at 600
  units, at 0.3 group volume.
- `src/bomb/c4_view.gd:16-19`: the beep is `c4_beep2` (and `c4_beep3` for
  `C4.PlantSoundB`), the blast `c4_explode1` plus the close and shockwave
  layers; the comment "Guessed from CS:GO's file names" can go. `:80-81`,
  `:163-174`: curves (beep linear to 0 at 1300 units).
- `src/player/player_view.gd:157-160`, `src/bots/bot.gd:381-384`: sounds are
  started from a signal inside the tick; they should come from events on the
  `GameWorld` and be played by the view per frame (`CLAUDE.md`, "What the code
  holds to"). Done for shots (2026-09-24): `WeaponSounds` hears its
  shooter's `weapon_fire` and plays it on the next frame. The reload and the
  shooter's hit feedback still start from `reload_started` and `shot_traced`.
- `reference/asset-pipeline.md:51`: "The sound event definitions ... are not
  fetched; those are by ear" and "bright ticks ... fading over 80 m": the
  definitions are readable in GameTracking-CS2 (this page has the gameplay
  ones), and impacts are silent at 600 units in CS2.
- `reference/cs2-systems.md:450-451` (S2): S2 is Remote now; the numbers are
  in this page and `footsteps.md`. Only the compiled parts (the voice and mix
  graphs, the surfaces' `occlusionFactor`) still need Sid's machine.
- `reference/research/combat.md:331-333` (R6 "Sound"): add that the distant
  layer holds 0.096 past 2869 if the curve holds its end (Local check A2), so
  "heard to 2500" is the near layer only.
- `reference/research/footsteps.md:196-199`: "past 59 units a step is
  positioned by the engine's 3D audio rather than played as a plain stereo
  file" is confirmed by the stack (`unfiltered_stereo`, section 1.3 step 12
  here); and its line 190 `use_baked_occlusion true` has no effect in a
  normal match (`snd_use_baked_occlusion 0`).

## 11. Local checks

Each needs CS2 on Sid's machine (build 2000915 or later).

| Check | What to do | What it settles |
|---|---|---|
| A1. The voice and mix graphs | Open `csgo_voice_main` and the csgo mix graph (`.vmix_c`) in Source 2 Viewer | What `eq_occlusion`, `distance_effect_mix`, `unfiltered_stereo` do exactly; the ducker on `AllVoices` and its side-chain |
| A2. Curve ends and tangents | On a private server, `snd_sos_show_operator_updates 1` with `snd_sos_show_operator_filter distance_volume_mapping_curve`; stand 3000 and 5000 units from a bot firing an AK | Whether curves hold their last value (the distant AK at 0.096) and how the tangent modes shape a curve |
| A3. Surface occlusion | Decompile the physics surface list (`surfaceproperties.vsurf_c`) for `occlusionFactor`; `snd_occlusion_debug 1` while a bot fires behind wood, concrete, metal | The per-surface factors and the ray method |
| A4. EQ profiles | Record the game's output (loopback) of one steady sound in Natural, Crisp, Smooth; compare spectra | The three EQ curves, to copy |
| A5. What ducks | Record a steady ambience while a teammate talks, a flash goes off, an HE blows up; watch `snd_sos_show_soundevent_start 1` | Whether voice or blasts duck the game, by how much and for how long |
| A6. Deafness | `snd_sos_show_soundevent_start 1` while flashed at full, half, and by an HE at 200 units; record the mix | Which `control.deafen*` and ring play, and the filter's cutoff and length |
| A7. Silent reload | Two clients: one reloads holding R; the other stands at 100, 220, 500 units | The 0.07 volume and 220-unit reach |
| A8. Network culling | Demo with a player firing from 9500 units; check whether the other client gets the shot | The 9000 broadcast distance |
