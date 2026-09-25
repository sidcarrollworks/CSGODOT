class_name C4View
extends Node3D

## The bomb as it is seen and heard: lying on the ground when it is dropped
## or planted, its light blinking with each beep, the beeps closing in as
## the timer runs down, and the blast. It reads a C4 once a frame and never
## changes it, so it can be dropped from a server and put on a client.
##
## The model is CS2's (scripts/extract_assets.sh equipment); without the
## extraction it is a tan box of the bomb's size, and without the sounds it
## blinks in silence. The beeps are worked out here from how long the bomb
## has been down (C4.beep_interval), not sent by the simulation each tick:
## what is only heard runs per frame.

const MODEL_PATH := "res://assets/weapons/weapons/models/c4/weapon_c4.gltf"
## The bomb's sounds, as SoundBank stems. Guessed from CS:GO's file names,
## until the extraction's c4/ folder is listed in reference/weapons/sounds.md.
const BEEP_SOUND := "weapons/c4/c4_beep"
const EXPLODE_SOUND := "weapons/c4/c4_explode"
## About the bomb's size, for the box without the model.
const BOX_SIZE := Vector3(12.0, 4.0, 8.0)
## How long the light stays lit after a beep, and the blast stays on screen.
const BLINK_SECONDS := 0.08
const BLAST_SECONDS := 1.0

var bomb: C4

var _body: Node3D
var _light: OmniLight3D
var _lamp: MeshInstance3D
var _blast: MeshInstance3D
var _beep_player: AudioStreamPlayer3D
var _explode_player: AudioStreamPlayer3D
## The last plant this view saw, the time into it of the next beep, and
## when the light went on.
var _planted_usec: int = C4.NEVER
var _next_beep: float = 0.0
var _lit_at: float = -INF
var _blast_at: float = -INF
var _last_state: C4.State = C4.State.NONE


func _ready() -> void:
	_body = _build_body()
	add_child(_body)

	_lamp = MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.8
	bulb.height = 1.6
	_lamp.mesh = bulb
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.1, 0.05)
	_lamp.material_override = glow
	_lamp.position = Vector3(0.0, BOX_SIZE.y + 0.5, 0.0)
	add_child(_lamp)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.05)
	_light.omni_range = 48.0
	_light.light_energy = 2.0
	_light.position = _lamp.position
	add_child(_light)

	_blast = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	_blast.mesh = ball
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.albedo_color = Color(1.0, 0.55, 0.1, 0.8)
	_blast.material_override = fire
	_blast.top_level = true
	_blast.visible = false
	add_child(_blast)

	_beep_player = _sound(BEEP_SOUND, 10.0)
	_explode_player = _sound(EXPLODE_SOUND, 60.0)
	visible = false


func _process(_delta: float) -> void:
	if bomb == null:
		visible = false
		return
	var now := SimClock.now_usec()
	var seconds := float(now) / C4.SECOND_USEC
	var state := bomb.state
	var on_ground := state in [C4.State.DROPPED, C4.State.PLANTED, C4.State.DEFUSED, C4.State.EXPLODED]
	visible = on_ground or seconds - _blast_at < BLAST_SECONDS
	global_position = bomb.position
	_body.visible = on_ground and state != C4.State.EXPLODED
	if _body.visible:
		# Lit from the map's light probes where it lies, which hold the map's
		# shadow from the sun; the live shadow map no longer does.
		ProbeMaterials.light_model(_body, _body.global_position)

	if state == C4.State.PLANTED:
		if bomb.planted_usec != _planted_usec:
			_planted_usec = bomb.planted_usec
			_next_beep = 0.0
			# Seen for the first time well after the plant (a view made
			# late, a client joining): the beeps already gone are not played.
			var gone := bomb.seconds_planted(now) - BLINK_SECONDS
			while _next_beep < gone:
				_next_beep += C4.beep_interval(bomb.rules.timer_seconds - _next_beep, bomb.rules.timer_seconds)
		var down := bomb.seconds_planted(now)
		while down >= _next_beep:
			_beep(seconds - (down - _next_beep))
			_next_beep += C4.beep_interval(bomb.rules.timer_seconds - _next_beep, bomb.rules.timer_seconds)
	if state == C4.State.EXPLODED and _last_state != C4.State.EXPLODED:
		_blast_at = seconds
		if _explode_player != null:
			_explode_player.play()
	_last_state = state

	var lit := state == C4.State.PLANTED and seconds - _lit_at < BLINK_SECONDS
	_lamp.visible = lit
	_light.visible = lit

	var blast_age := seconds - _blast_at
	_blast.visible = blast_age >= 0.0 and blast_age < BLAST_SECONDS
	if _blast.visible:
		# Out to the blast's reach at a fraction of it, fading.
		var reach := bomb.rules.bomb_damage * bomb.rules.radius_scale
		var grow := sqrt(blast_age / BLAST_SECONDS)
		_blast.global_position = bomb.position
		_blast.scale = Vector3.ONE * maxf(reach * 0.15 * grow, 1.0)
		var fire := _blast.material_override as StandardMaterial3D
		fire.albedo_color.a = 0.8 * (1.0 - blast_age / BLAST_SECONDS)


func _beep(at_seconds: float) -> void:
	_lit_at = at_seconds
	if _beep_player != null:
		_beep_player.play()


func _build_body() -> Node3D:
	if ResourceLoader.exists(MODEL_PATH):
		var scene := load(MODEL_PATH) as PackedScene
		if scene != null:
			var model := scene.instantiate() as Node3D
			# The export is in metres; the world is in units. Lying flat, its
			# underside on the ground.
			model.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
			var laid := Node3D.new()
			laid.add_child(model)
			model.transform = DroppedItemView.lying(laid) * model.transform
			return laid
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = BOX_SIZE
	box.mesh = mesh
	box.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.55, 0.47, 0.33)
	box.material_override = paint
	var holder := Node3D.new()
	holder.add_child(box)
	return holder


func _sound(stem: String, metres: float) -> AudioStreamPlayer3D:
	if not SoundBank.available():
		return null
	var stream := SoundBank.randomizer(stem)
	if stream == null:
		return null
	var placed := AudioStreamPlayer3D.new()
	placed.stream = stream
	placed.unit_size = metres * WeaponSounds.METRE
	placed.max_distance = 300.0 * WeaponSounds.METRE
	placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(placed)
	return placed
