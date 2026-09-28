class_name MusicRules
extends RefCounted

## How the music kit's cues give way to each other: CS2's csgo_music fields
## (reference/research/audio-round.md 1.2 and 3), as pure functions a check
## can call. SoundEvents asks them at every start of a csgo_music event.
##
## Read from the kit's .vsndevts, the meaning of each field inferred from
## its name, since no file says more:
## - A cue is refused while music of a higher priority plays (start round
##   and action 2, bomb and ten seconds 3, won and lost 4, MVP 5). A cue of
##   priority 0 (match start and end, the death camera) is outside the
##   ranking: it neither refuses nor is refused.
## - Its stop flags stop what they name as it starts: stop_music everything,
##   stop_music_except_mvp everything but the MVP anthem, stop_start_round
##   the start-round and action music, stop_tensec_count the round's ten
##   seconds, stop_bomb_planted the bomb's music, stop_won_mvp the won,
##   lost and MVP music, stop_match_end the match's end.
## - test_mvp_block: the won and lost music is refused while an anthem with
##   block_won_lost plays.
## - skip_if_muted: not started at all while its volume convar is 0.
## - loop_track plays it until it is stopped; stop_at_time stops it that
##   many seconds in; volume_fade_out_input_max is the seconds a stop fades
##   over.
## Not modelled: the sync points and queueing (should_queue_track waits for
## the playing track's next sync point), the fade in (volume_fade_initial_*)
## and a kit's second anthem.

## What each stop flag stops, as the cue names in Music.<cue>.<kit>.
const STOPS := {
	"stop_start_round": ["StartRound", "StartAction"],
	"stop_tensec_count": ["TenSecCount"],
	"stop_bomb_planted": ["BombPlanted"],
	"stop_won_mvp": ["WonRound", "LostRound", "MVPAnthem"],
	"stop_match_end": ["MatchEnd"],
}


## The cue in a music event's name: BombPlanted in
## Music.BombPlanted.valve_cs2_01; the name itself for any other.
static func cue_of(event_name: String) -> String:
	var parts := event_name.split(".")
	return parts[1] if parts.size() >= 3 and parts[0] == "Music" else event_name


## Whether a music event may start while these play: refused by a higher
## priority, or by an anthem blocking the won and lost music, or muted.
static func refused(event: SoundEvent, playing: Array[SoundEvent], convar: float = 1.0) -> bool:
	if event.type != "csgo_music":
		return false
	if _flag(event, "skip_if_muted") and convar <= 0.0:
		return true
	var priority := priority_of(event)
	for other in playing:
		if other == event or other.type != "csgo_music":
			continue
		if _stops(event, other):
			continue
		if priority > 0 and priority_of(other) > priority:
			return true
		if _flag(event, "test_mvp_block") and _flag(other, "block_won_lost"):
			return true
	return false


## Which of the playing music a start stops: indexes into playing.
static func stopped_by(event: SoundEvent, playing: Array[SoundEvent]) -> Array[int]:
	var result: Array[int] = []
	if event.type != "csgo_music":
		return result
	for i in playing.size():
		var other := playing[i]
		if other != event and other.type == "csgo_music" and _stops(event, other):
			result.append(i)
	return result


static func priority_of(event: SoundEvent) -> int:
	return int(SoundEvent._number(event.fields, "priority", 0.0))


## Whether starting event stops other, by its flags.
static func _stops(event: SoundEvent, other: SoundEvent) -> bool:
	var cue := cue_of(other.name)
	if _flag(event, "stop_music"):
		return true
	if _flag(event, "stop_music_except_mvp") and cue != "MVPAnthem":
		return true
	for flag: String in STOPS:
		if _flag(event, flag) and cue in STOPS[flag]:
			return true
	return false


static func _flag(event: SoundEvent, field: String) -> bool:
	return SoundEvent._flag(event.fields, field)
