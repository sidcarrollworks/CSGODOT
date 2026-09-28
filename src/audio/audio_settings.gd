class_name AudioSettings
extends Resource

## The music volumes a player sets, as CS2's audio settings have them: one
## slider a cue, each a convar the kit's sound events name as their
## volume_convar (reference/research/audio-round.md 1.1). Every default is
## competitive's, from the game's convar dump (build 2000915): round-start
## and action music are off, and the bomb and ten-second cues are low.
## Ready for the settings menu (roadmap item 26) to show and change; until
## it lands, a player turns the music up here.

## Master Music Volume (snd_musicvolume): every music cue is also scaled by
## it (inferred from the kit's default convar and use_mode_music_volume).
@export_range(0.0, 1.0) var music_volume: float = 1.0
## Round Start Volume (snd_roundstart_volume): freeze time's music.
@export_range(0.0, 1.0) var round_start: float = 0.0
## Round Action Volume (snd_roundaction_volume): the music as freeze ends.
@export_range(0.0, 1.0) var round_action: float = 0.0
## Round End Volume (snd_roundend_volume): won and lost.
@export_range(0.0, 1.0) var round_end: float = 0.16
## MVP Volume (snd_mvp_volume).
@export_range(0.0, 1.0) var mvp: float = 0.16
## Bomb/Hostage Volume (snd_mapobjective_volume): the bomb's music.
@export_range(0.0, 1.0) var map_objective: float = 0.04
## Ten Second Warning Volume (snd_tensecondwarning_volume): the round's and
## the bomb's last ten seconds.
@export_range(0.0, 1.0) var ten_second_warning: float = 0.04
## Death Camera Volume (snd_deathcamera_volume).
@export_range(0.0, 1.0) var death_camera: float = 0.16
## Main Menu Volume (snd_menumusic_volume): also the match's start and end.
@export_range(0.0, 1.0) var menu_music: float = 0.04


## The convars as SoundEvents.convars takes them: each cue's own slider
## times the master music volume, and the master itself.
func convars() -> Dictionary:
	return {
		"snd_musicvolume": music_volume,
		"snd_roundstart_volume": round_start * music_volume,
		"snd_roundaction_volume": round_action * music_volume,
		"snd_roundend_volume": round_end * music_volume,
		"snd_mvp_volume": mvp * music_volume,
		"snd_mapobjective_volume": map_objective * music_volume,
		"snd_tensecondwarning_volume": ten_second_warning * music_volume,
		"snd_deathcamera_volume": death_camera * music_volume,
		"snd_menumusic_volume": menu_music * music_volume,
	}
