# Godot 4.7: audio

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: changing `SoundBank`, `WeaponSounds`, `HitSounds`, `Footsteps`, `BulletImpacts` or `C4View`, adding a bus layout, mix layers, reverb zones, occlusion or flash deafness, importing sounds, or testing audio headless.

What CS2 does (sound events, curves, mixgroups, ducking, reverb, occlusion, HRTF) and the proposed mapping onto Godot is in `reference/research/audio-engine.md` (section 6 is the mapping; section 7 lists where the code differs). The per-sound numbers are in `audio-gameplay.md`, `audio-round.md` and `footsteps.md`. This page adds the engine facts that mapping needs and does not repeat it.

## Rules for this project

- Distances are inches. `AudioStreamPlayer3D.unit_size` (default 10.0) and `max_distance` are in world units, and Godot's defaults assume metres, so every default distance is about 39x too short here. Multiply metre figures by 39.37, as the code's `METRE` constant does, or better, give distances in units taken from CS2's curves (`classes/class_audiostreamplayer3d.rst`).
- Start sounds from the `GameWorld`'s events in `_process`, never from inside the tick. Sounds are views (CLAUDE.md), and `--headless` runs on the `Dummy` audio driver (`classes/class_audioserver.rst`), so a test can never hear a sound; test the event instead.
- `AudioStreamPlayer3D.play()` "Queues the audio to play on the next physics frame"; `AudioStreamPlayer.play()` "Plays a sound from the beginning". A 3D sound started in `_process` therefore waits for the next 64 Hz step: up to 15.6 ms more than a non-positional one (inferred from the two descriptions). Keep that in mind when comparing the local gun (flat) with others' (3D), and when timing a sound to a frame.
- Name buses, never index them: players and areas refer to buses by name, a renamed bus silently sends its players to `Master` ("If this given name can't be resolved at runtime, it will fall back to "Master""), and `AudioServer` calls take indices that change when buses move. Resolve with `AudioServer.get_bus_index(name)` once, after the layout loads.
- The bus layout is `res://default_bus_layout.tres` (`audio/buses/default_bus_layout`, Godot's default path, so `project.godot` does not name it), committed and generated with the sound event table by `scripts/sound_events.sh`: one bus per CS2 mixgroup the events use, at `Default_Mix`'s level, each sending to `Master`. Regenerate it rather than editing it in the editor. Headless runs load it too, so a check can read the buses through `AudioServer`.
- Keep Doppler off (the default on both players and listener). Its speed of sound is not documented, and if it is in metres per second it is 39x wrong in inches (inferred).
- Do not rely on the automatic low-pass for distance. `attenuation_filter_cutoff_hz` = 5000 and `attenuation_filter_db` = -24 apply to every `AudioStreamPlayer3D` "for greater realism". Set `attenuation_filter_cutoff_hz = 20500` to switch it off where CS2's own filter (occlusion, distance) is modelled instead.
- An area only reroutes a player whose `area_mask` includes the area's layer. `AudioStreamPlayer3D.area_mask` defaults to **0** in 4.7, which means no area affects it until set (inferred from "Determines which Area3D layers affect the sound").
- Load streams before the round, never on first play (as `SoundBank.load_sets` does). `load()` of an audio file reads the disk.

## Units and attenuation

`classes/class_audiostreamplayer3d.rst`, `tutorials/audio/audio_streams.rst`, `classes/class_projectsettings.rst`; the gain formulas were read from the engine source in `reference/research/audio-engine.md` section 6.

- `attenuation_model`: `ATTENUATION_INVERSE_DISTANCE` 0 (**default**, gain `unit_size / d`), `ATTENUATION_INVERSE_SQUARE_DISTANCE` 1, `ATTENUATION_LOGARITHMIC` 2, `ATTENUATION_DISABLED` 3 ("still be heard positionally", that is, panned).
- `unit_size` = 10.0: "Higher values make the sound audible over a larger distance". Under the inverse model it is the distance of 0 dB. Closer than that the gain rises, capped by `max_db` = 3.0.
- `max_distance` = 0.0 (off): "the distance past which the sound can no longer be heard at all". It "always works in a linear fashion" alongside `unit_size`, and past it the player needs no mixing, which "saves CPU". `ATTENUATION_DISABLED` plus `max_distance > 0` gives a plain linear fade to zero at `max_distance`.
- For CS2's hand-drawn curves (the research's proposal): use `ATTENUATION_DISABLED`, keep or zero `max_distance`, and set `volume_db` (or `volume_linear`, new in 4.x: the same thing in linear) per frame from the curve at the listener distance. The panning still works, and the automatic low-pass does not apply because the distance gain stays 1 (inferred from the gain-driven filter in the research's reading).
- Panning: `ProjectSettings.audio/general/3d_panning_strength` = 0.5 × the player's `panning_strength` = 1.0. The product 0 means no panning, and 1 mutes the far ear for a sound exactly to one side. Stereo uses the WebAudio StereoPanner law ("cosine of half the azimuth angle"); 5.1 and 7.1 use SPCAP. There is no HRTF.
- Directivity: `emission_angle_enabled` = false, `emission_angle_degrees` = 45, `emission_angle_filter_attenuation_db` = -12. Nothing in CS2's gameplay sounds needs it.
- Worked conversions (inches): Godot's default `unit_size` 10 is 10 units, less than a player's width. The code's footsteps use `10 * 39.37 = 393.7`, guns `20 * 39.37 = 787.4` with `max_distance` `300 * 39.37 = 11811`, and impacts `4 * 39.37 = 157.5` with 3150.

## Players and streams

`tutorials/audio/audio_streams.rst`, `classes/class_audiostreamplayer.rst`, `classes/class_audiostreamplayer3d.rst`, `classes/class_audiostreamrandomizer.rst`, `classes/class_audiostreampolyphonic.rst`, `classes/class_audiostreamplaybackpolyphonic.rst`

- `AudioStreamPlayer` (non-positional; `mix_target` STEREO 0, SURROUND 1, CENTER 2) and `AudioStreamPlayer3D` (positional, a `Node3D`, so it must sit where the sound is: under a plain `Node` it plays from the world origin).
- `max_polyphony` = 1 on both: "Playing additional sounds after this value is reached will cut off the oldest sounds." So CS2's `instance_limit 1` with oldest-stopped is `max_polyphony = 1`, without CS2's 0.2 s fade.
- `pitch_scale` changes pitch and tempo together. `stream_paused`. `playing` is true while playing "or queued to be played". Signal `finished` is not emitted by looping streams. Hiding a 3D player does not silence it: set `volume_db` to about -100 or stop it.
- `get_playback_position()` goes up in mix-sized chunks. Add `AudioServer.get_time_since_last_mix()` for precision (`tutorials/audio/sync_with_audio.rst`).
- `playback_type` is experimental: Sample playback is used on the web only and does not support bus effects. Leave it at the default.
- `AudioStreamRandomizer`: `playback_mode` = `PLAYBACK_RANDOM_NO_REPEATS` 0 (RANDOM 1, SEQUENTIAL 2); `random_pitch` = 1.0, a multiplier picked between `1/random_pitch` and `random_pitch` (1.05 is about ±0.84 semitones); `random_pitch_semitones` = 0 (setting either sets the other); `random_volume_offset_db` = 0 (± that many dB); `add_stream(index, stream, weight = 1.0)` (index < 0 appends), `set_stream_probability_weight`, `streams_count`. The pick and the pitch are made per `play()`, so one randomizer on a player with `max_polyphony > 1` gives overlapping, varied shots (what `SoundBank` does). CS2's pitch and volume ranges are additive offsets; convert with `pitch = 1 + offset` (inferred).
- `AudioStreamPolyphonic` (`polyphony` = 32): set it as a player's `stream`, `play()`, then `get_stream_playback()` returns an `AudioStreamPlaybackPolyphonic`. `play_stream(stream, from_offset = 0, volume_db = 0, pitch_scale = 1.0, playback_type = 0, bus = &"Master") -> int` starts at once and returns an id (`INVALID_ID` -1 when full), with `set_stream_volume(id, db)`, `set_stream_pitch_scale(id, p)`, `stop_stream(id)` and `is_stream_playing(id)`. One 3D player can then hold every layer of an event with its own volume, pitch and bus: CS2's multi-layer hit feedback, without a player per layer (a design option).
- `AudioStreamSynchronized` plays sub-streams starting together; `AudioStreamPlaylist` plays them in sequence (`shuffle`); `AudioStreamInteractive` switches clips with a transition table (for music kits: `bpm`, `beat_count` and `bar_beats` come from the Ogg/MP3 import).
- `AudioStreamWAV`: `format` 8_BITS 0, 16_BITS 1, IMA_ADPCM 2, QOA 3; `mix_rate` = 44100; `stereo` = false; `loop_mode` DISABLED/FORWARD/PINGPONG/BACKWARD with `loop_begin`/`loop_end` in samples; `data`; `tags`. Static `load_from_file(path, options = {})` and `load_from_buffer(bytes, options = {})` take the `ResourceImporterWAV` option names, which makes it possible to load a sound from outside `res://` without importing it. `AudioStreamOggVorbis.load_from_file(path)` and `load_from_buffer(bytes)` do the same for Ogg; `.ogg` files that hold Opus or Theora will not load.

## Buses and the mix

`tutorials/audio/audio_buses.rst`, `classes/class_audioserver.rst`, `classes/class_audiobuslayout.rst`, `classes/class_projectsettings.rst`

- Bus 0 is `Master`. The others each send to a bus further left (lower index), which rules out loops. Effects on a bus apply in order. A player's `bus` names its bus (default `&"Master"`).
- A bus silent below `audio/buses/channel_disable_threshold_db` = -60 dB for `audio/buses/channel_disable_time` = 2.0 s is disabled with its effects: a dozen mixgroup buses cost nothing while quiet.
- The layout is an `AudioBusLayout` resource ("position, muting, solo, bypass, effects, effect position, volume, and the connections"), loaded from `audio/buses/default_bus_layout` = `res://default_bus_layout.tres`. At runtime: `AudioServer.set_bus_layout(layout)`, `generate_bus_layout()`.
- Building buses in code (for a generated layout or tests): `add_bus(at_position = -1)`, `set_bus_name(idx, name)`, `set_bus_send(idx, send_name)`, `set_bus_volume_db(idx, db)`/`set_bus_volume_linear`, `set_bus_mute`, `set_bus_solo`, `set_bus_bypass_effects`, `add_bus_effect(idx, effect, at_position = -1)`, `set_bus_effect_enabled(idx, effect_idx, on)`, `get_bus_effect(idx, effect_idx)`, `get_bus_effect_instance(idx, effect_idx, channel = 0)`, `move_bus`, `remove_bus`, `bus_count`. Signals `bus_layout_changed`, `bus_renamed`.
- Ducking (CS2's mix layers) is either a per-frame ramp of `set_bus_volume_db` on the ducked buses, as the research proposes, or an `AudioEffectCompressor` sidechained from another bus ("reduce the volume of one signal by using the volume of another audio bus"), (`AudioEffectCompressor.sidechain`, a bus name), which ducks by level rather than by event (`tutorials/audio/audio_effects.rst`).
- dB: 6 dB is double or half the amplitude, audibility ends around -60 to -80 dB, and the Master bus output must stay below 0 dB. An `AudioEffectHardLimiter` last on Master is the safeguard (`AudioEffectLimiter` is the deprecated old one).
- `AudioServer.playback_speed_scale` = 1.0 slows or speeds all audio, independent of `Engine.time_scale`.
- Latency: `audio/driver/output_latency` = 15 ms (overridable with `--audio-output-latency`), `audio/driver/mix_rate` = 44100. `get_output_latency()` gives the real value but "can be expensive; it is not recommended to call ... every frame". `get_time_to_next_mix()` and `get_time_since_last_mix()` are cheap.

## Areas: bus override and reverb

`tutorials/audio/audio_streams.rst` (Reverb buses), `classes/class_area3d.rst`, `classes/class_audiostreamplayer3d.rst`

- `Area3D.audio_bus_override` = false, `audio_bus_name` = `&"Master"`: sounds in the area go to that bus instead of their own.
- `Area3D.reverb_bus_enabled` = false, `reverb_bus_name` = `&"Master"`, `reverb_bus_amount` = 0.0 (0 to 1, 0.1 steps), `reverb_bus_uniformity` = 0.0 (0 to 1: how evenly the room rings wherever the source is, "like a warehouse"). A 3D stream that "enters" the area sends dry audio to its bus and wet audio to the reverb bus, which must hold an `AudioEffectReverb` configured for that room.
- Which areas count: `AudioStreamPlayer3D.area_mask` (default 0) against the areas' layers. `Area3D.priority` = 0 (higher first) orders overlapping areas (inferred to decide which area's bus wins). Areas need collision shapes like any `Area3D`, and a `ConcavePolygonShape3D` is hollow in an area ("may give unexpected results"): use boxes or convex shapes for room volumes. dust2's `env_cs_place` brushes (asset-pipeline.md) are closed convex solids, a ready source.
- This is source-based reverb (the room the sound starts in), like CS2's source DSP. A listener-room reverb (CS2's `RoomDSP`) has to be a bus effect whose wet level the listener's current room sets (a design option; research section 2.3).
- Area lookups are physics queries. They run in the audio or physics code, not in the game tick, but they add areas to the physics space: put reverb areas on a layer the game's traces never test (inferred).

## Effects used for CS2's mix

`tutorials/audio/audio_effects.rst`, `classes/class_audioeffectreverb.rst`, `classes/class_audioeffectfilter.rst`, `classes/class_audioeffectlowpassfilter.rst`

- `AudioEffectReverb`: `room_size` = 0.8, `damping` = 0.5, `spread` = 1.0, `hipass` = 0.0, `dry` = 1.0, `wet` = 0.5, `predelay_msec` = 150 (20 to 500), `predelay_feedback` = 0.4. All are 0 to 1 except the predelay. For a send-style reverb bus (area reverb), set `dry` to 0 so the dry signal is not doubled (inferred).
- `AudioEffectLowPassFilter` (an `AudioEffectFilter`): `cutoff_hz` = 2000 (1 to 20500), `resonance` = 0.5, `db` = FILTER_6DB 0 (12, 18 or 24 dB per octave: 1, 2, 3). It is for occlusion and flash deafness (a bus per occlusion level, or a filter on the game buses ramped by flash strength). Shelves (`AudioEffectLowShelfFilter`/`HighShelfFilter`) also take `gain` 0 to 4.
- `AudioEffectEQ6`/`EQ10`/`EQ21` for CS2's EQ profiles; `AudioEffectCompressor` (sidechain) for level-based ducking; `AudioEffectHardLimiter` for Master; `AudioEffectCapture` and `SpectrumAnalyzer` read a bus without changing it (useful for a Local check that measures levels).
- Web-only caveat: effects are unsupported with Sample playback (irrelevant on desktop).

## The listener

`classes/class_audiolistener3d.rst`, `classes/class_camera3d.rst`

- By default sound is heard from the current `Camera3D`. An `AudioListener3D` overrides that once `make_current()` is called. `clear_current()` returns to the camera; `is_current()`; `get_listener_transform()`. If several are marked current, the last one made current wins.
- CS2 hears from the eyes. The first-person camera is at the eyes, so no listener is needed, except when the camera leaves the eyes (spectating, the hitbox camera, a death cam).
- `doppler_tracking` on `Camera3D`/`AudioListener3D` and on each `AudioStreamPlayer3D`: DISABLED 0 (default), IDLE_STEP 1, PHYSICS_STEP 2 (for objects moved in `_physics_process`). Both sides must track for a correct effect. Keep it off.

## Importing sounds

`tutorials/assets_pipeline/importing_audio_samples.rst`, `classes/class_resourceimporterwav.rst`, `classes/class_resourceimporteroggvorbis.rst`, `classes/class_resourceimportermp3.rst`; `.import` mechanics are in `import.md`.

- WAV is cheapest to play ("hundreds of simultaneous voices ... are fine"); Ogg is costliest; MP3 sits between. CS2's sounds come out as WAV (a few MP3).
- WAV import defaults: `compress/mode` = 2 (Quite OK Audio: lossy, "much less noticeable" than IMA ADPCM, slightly more CPU than PCM; 0 PCM, 1 IMA ADPCM), `edit/loop_mode` = 0 (loop points from the WAV's metadata), `edit/trim` = false (trims below -50 dB after normalisation, with 500-sample fades), `edit/normalize` = false (peak to 0 dB: leave off, or CS2's relative levels are lost), `force/mono` = false, `force/max_rate` = false, `force/8_bit` = false.
- CS2's looping sounds (the fire's loop, ambience) carry their loop in the WAV. Ogg and MP3 have only `loop` + `loop_offset` (seconds; loop-begin only, forward only).
- Every one of these is imported with defaults today (no `.import` settings are written for sounds). To keep samples bit-exact, `write_import_settings.gd` would need to write `compress/mode = 0` for `.wav` (a choice; QOA's loss is small).

## Class notes

**AudioServer**: see Buses. Plus `get_mix_rate()`, `get_speaker_mode()` (STEREO, SURROUND_31, _51, _71), `get_output_device_list()`/`output_device` = "Default", `get_driver_name()` ("Dummy" under `--headless`), `lock()`/`unlock()` around direct changes from other threads, `get_bus_peak_volume_left_db(bus, channel)`/`_right_db`, and `register_stream_as_sample` (experimental, web).

**AudioBusLayout**: a `Resource`; no members of its own. Edit it through `AudioServer` and `generate_bus_layout()`, or as the editor's `.tres`.

**AudioStreamPlayer**: `bus` = `&"Master"`, `volume_db` = 0, `volume_linear`, `pitch_scale` = 1, `max_polyphony` = 1, `mix_target` = 0, `autoplay` = false, `playback_type` = 0; `play(from_position = 0.0)`, `stop()`, `seek(to_position)`, `get_playback_position()`, `get_stream_playback()`, `has_stream_playback()`; signal `finished`.

**AudioStreamPlayer3D**: `unit_size` = 10.0, `max_distance` = 0.0, `max_db` = 3.0, `attenuation_model` = 0, `attenuation_filter_cutoff_hz` = 5000, `attenuation_filter_db` = -24, `panning_strength` = 1.0, `area_mask` = 0, `bus` = `&"Master"`, `max_polyphony` = 1, `doppler_tracking` = 0, `emission_angle_*`, `volume_db` = 0, `volume_linear`, `pitch_scale` = 1; `play(from_position = 0.0)` (queued to the next physics frame), `stop()`, `seek()`, `get_stream_playback()`.

**AudioStream**: `get_length()`, `is_monophonic()`, `instantiate_playback()`, `can_be_sampled()`, `generate_sample()`; virtuals `_instantiate_playback` (required), `_get_length`, `_get_bpm`, `_get_beat_count`, `_get_bar_beats`, `_has_loop`, `_is_monophonic`, `_get_stream_name`, `_get_tags`, `_get_parameter_list`.

**AudioStreamWAV**, **AudioStreamOggVorbis**, **AudioStreamRandomizer**, **AudioStreamPolyphonic**: see Players and streams. **AudioStreamInteractive / AudioStreamPlaylist / AudioStreamSynchronized**: music only; see their class pages.

**AudioListener3D**: see The listener.

**AudioEffectReverb**, **AudioEffectLowPassFilter**: see Effects.

**Area3D** (audio part): `audio_bus_override`, `audio_bus_name`, `reverb_bus_enabled`, `reverb_bus_name`, `reverb_bus_amount`, `reverb_bus_uniformity`, `priority`.

## Where the code already does this

- `src/audio/sound_bank.gd`: sets found by stem, loaded once, played through `AudioStreamRandomizer` (`PLAYBACK_RANDOM_NO_REPEATS`, `random_pitch = 1.05`, `add_stream(-1, stream)`, 107-115). `available()` caches the disk check because it was a quarter of the tick on dust2.
- `src/audio/weapon_sounds.gd`: bots' guns at `unit_size = 20 * METRE`, `max_distance = 300 * METRE`, inverse distance (205-211); the local player's are `AudioStreamPlayer` (213); `max_polyphony` 4 and 2 (`_ready`); shots played in `_process` from `weapon_fire` events (135-).
- `src/audio/hit_sounds.gd:105-117`: `ATTENUATION_DISABLED` 3D players with the event's curve applied in code, the pattern the research proposes.
- `src/audio/footsteps.gd:59-62`: `unit_size = 10 * METRE`, `max_distance = 80 * METRE`. `src/combat/bullet_impacts.gd:84-87`: 4 m and 80 m. `src/bomb/c4_view.gd:163-173`: a unit size per sound, 300 m.
- `src/audio/sound_events.gd` (`SoundEvents`, 2026-09-26): CS2's events from `reference/sounds/sound_events.json`, each on its mixgroup's bus, `ATTENUATION_DISABLED` with `volume_db` set per frame from the event's curve, `attenuation_filter_cutoff_hz = 20500`, `panning_strength` from the unfiltered-stereo curve, and a voice ended by its stream's length as well as `finished` (which a headless mix never sends). The older players (`WeaponSounds`, `HitSounds`, `Footsteps`, `BulletImpacts`, `C4View`) still play on `Master`. No `AudioListener3D` and no areas with audio settings.
- Looks at odds, not verified: `src/audio/footsteps.gd:85` steps in `_physics_process` and casts a ray per step (`surface_below`). The step is a sound (a view), which CLAUDE.md says runs per frame, not per tick, and it adds a trace per step on the tick. CS2 does decide steps on the server (they are sent to others), so the step event belongs on the `GameWorld` tick and its playing in `_process` (see `footsteps.md`).
- Looks at odds, not verified: none of the 3D players set `attenuation_filter_cutoff_hz`, so every bot's gun, step and impact also gets Godot's automatic distance low-pass (5000 Hz, up to -24 dB) on top of the volume; CS2 has no such filter outside occlusion. The research's section 7 covers the volumes, not this filter.
- Looks at odds, not verified: `weapon_sounds.gd` plays others' shots on `AudioStreamPlayer3D`, which starts on the next physics frame, and the shooter's own on `AudioStreamPlayer`, which starts at once. That is a 0 to 15.6 ms offset between the two kinds (inferred from the class descriptions).

## Not covered here

- Microphone recording and voice capture (`tutorials/audio/recording_with_microphone.rst`, `AudioEffectCapture`, `AudioStreamMicrophone`), needed for voice chat later.
- Text to speech (`tutorials/audio/text_to_speech.rst`).
- 2D audio (`AudioStreamPlayer2D`, `Area2D`), and web audio and Sample playback (`tutorials/export/exporting_for_web.rst`).
- Generating audio in code (`AudioStreamGenerator`, `AudioStreamGeneratorPlayback`), custom `AudioEffect`s and `AudioStreamPlayback` subclasses (`classes/`).
- The effects not listed above (Chorus, Delay, Distortion, Phaser, PitchShift, StereoEnhance, Panner, Record): `tutorials/audio/audio_effects.rst`.
- Steam Audio (HRTF, occlusion) as a GDExtension: `reference/research/audio-engine.md` section 6.
