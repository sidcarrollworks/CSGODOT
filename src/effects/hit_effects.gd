class_name HitEffects
extends Node3D

## What is seen of a round meeting a body: the blood that sprays from it,
## the blood it leaves on the wall and floor behind, and a helmet's sparks
## (reference/research/blood-and-impacts.md).
##
## It is drawn from the game's events, never inside the tick: player_hurt
## says how much the round took and where it landed, and the bullet_damage
## sent after it says where on the body and which way it was going. Both are
## noted as the tick hands them out, and the next frame starts what they
## call for (effect_for()), so everyone watching sees the same hit, the
## victim and spectators included, not only the shooter.
##
## Until CS2's own effects are extracted (blood_impact_*, impact_helmet_*
## and the Blood decal groups; the research page's Local list), what it
## draws is a stand-in, made here and plainly one: a spray of dark red cards
## flying on along the round, sparks for a helmet, and a dark red splat of
## its own making on the world behind. CS2 leaves those splats where its
## spray's particles land (its C_OP_GameDecalRenderer); here a few rays
## stand in for them, cast from the hit along the round within a cone and
## tilted down, and one straight down to the floor, as far as REACH (Source
## SDK 2013's bleed trace, a stand-in: CS2's number is in its effect files).
## The rays are only seen, so they run on the physics frame after the hit
## (the space is only safe there; reference/godot/physics.md), through
## PhysicsQueries, against the world alone, never the bodies.

## CS2's blood roots (client.dll's strings), and the helmet's.
const BLOOD_LOW := "blood_impact_low"
const BLOOD_MED := "blood_impact_med"
const BLOOD_HIGH := "blood_impact_high"
const BLOOD_HEADSHOT := "blood_impact_headshot"
const BLOOD_FRIENDLY := "blood_impact_friendly"
const BLOOD_LOCAL_FRONT := "blood_impact_localfrontenemy"
const BLOOD_LOCAL_REAR := "blood_impact_localrearhit"
const HELMET := "impact_helmet_headshot"
## Where the damage bands split: CS2's damage_impact_medium and
## damage_impact_heavy (client convars; that the blood follows them is
## inferred).
const MEDIUM_DAMAGE := 20
const HEAVY_DAMAGE := 40

## How far behind a hit its blood can land, and the cone its rays go out
## in about the round, tilted down: stand-ins until CS2's effect files say.
const REACH := 172.0
const CONE_DEGREES := 12.0
const TILT_DOWN := 0.25
## How far down under a hit the floor is looked for.
const FLOOR_REACH := 96.0
## Rays along the round by band: more blood the harder the hit.
const RAYS := {BLOOD_LOW: 1, BLOOD_MED: 2, BLOOD_HIGH: 3, BLOOD_HEADSHOT: 3, BLOOD_FRIENDLY: 1}
## A splat's size across, in units, and how deep its projection reaches.
const SPLAT_SIZE := 22.0
const SPLAT_DEPTH := 12.0
## A spray's cards: how many, how long they live, how far they fly.
const SPRAY_CARDS := 7
const SPRAY_SECONDS := 0.35
const SPRAY_TRAVEL := 18.0
const SPARK_CARDS := 6
const SPARK_SECONDS := 0.15
## CS2's blood decals start to fade at 30 s and are gone 3 s later
## (r_decals_default_start_fade, _fade_duration).
const DECAL_FADE_START := 30.0
const DECAL_FADE_SECONDS := 3.0

## Splats at once; the oldest goes when a new one is needed.
@export var max_splats: int = 64

var game: GameSystems
## Whose eyes (the player this machine plays as): their own hits are not
## sprayed in their face.
var listener_id: int = GameEvents.NOBODY
var quads: EffectQuads

## Each victim's last player_hurt from each attacker in this flush, by
## "victim:attacker": its bullet_damage comes after it.
var _hurt := {}
## Hits to start on the next frame: {"effect", "at", "direction", "victim"}.
var _pending: Array[Dictionary] = []
## Rays to cast on the next physics frame: {"from", "to"}.
var _rays: Array[Dictionary] = []
## Live sprays and sparks: {"effect", "at", "direction", "born", "seed"}.
var _bursts: Array[Dictionary] = []
var _splats: Array[Decal] = []
var _splat_born: Array[int] = []
var _next_splat: int = 0
var _rng := RandomNumberGenerator.new()
static var _blood_texture: Texture2D
static var _card_texture: Texture2D


## Listens to a game's hits, for listener's eyes.
func watch(p_game: GameSystems, listener: int) -> void:
	game = p_game
	listener_id = listener
	game.events.listen(&"player_hurt", _on_player_hurt)
	game.events.listen(&"bullet_damage", _on_bullet_damage)


func _ready() -> void:
	quads = EffectQuads.new()
	quads.name = "Quads"
	add_child(quads)
	blood_texture()
	card_texture()


func _exit_tree() -> void:
	if game != null:
		game.events.unlisten(&"player_hurt", _on_player_hurt)
		game.events.unlisten(&"bullet_damage", _on_bullet_damage)


func _on_player_hurt(event: GameEvent) -> void:
	var fields := event.fields
	_hurt["%d:%d" % [fields["userid"], fields["attacker"]]] = fields


## A round met a living body: what it calls for, noted for the next frame.
func _on_bullet_damage(event: GameEvent) -> void:
	var fields := event.fields
	var victim: int = fields["victim"]
	var attacker: int = fields["attacker"]
	var hurt: Dictionary = _hurt.get("%d:%d" % [victim, attacker], {})
	_hurt.erase("%d:%d" % [victim, attacker])
	var direction := Vector3(fields["damage_dir_x"], fields["damage_dir_y"], fields["damage_dir_z"])
	var at := Vector3(fields["x"], fields["y"], fields["z"])
	var effect := effect_for(
		int(hurt.get("hitgroup", DamageInfo.HITGROUP_GENERIC)),
		int(hurt.get("dmg_health", 0)), int(hurt.get("dmg_armor", 0)),
		_same_team(victim, attacker), victim == listener_id and victim != GameEvents.NOBODY,
		_from_front(victim, direction)
	)
	_pending.append({"effect": effect, "at": at, "direction": direction.normalized(), "victim": victim})


## What CS2 plays for a round into a body (the effect's root name):
## - the head of someone in a helmet that took the round: the helmet's
##   sparks, and no blood (inferred from impact_helmet_headshot, which the
##   server names);
## - the victim's own view: the local set, front or rear by where the round
##   came from;
## - a teammate: the friendly blood;
## - the head: headshot blood;
## - anywhere else: low, medium or heavy blood by the health it took.
## Which plays when is inferred from their names and CS2's damage_impact
## convars: CS2's own choice is in its code, not its files.
static func effect_for(hitgroup: int, dmg_health: int, dmg_armor: int, same_team: bool, own_view: bool, from_front: bool = true) -> String:
	var head := hitgroup == DamageInfo.HITGROUP_HEAD
	if head and dmg_armor > 0:
		return HELMET
	if own_view:
		return BLOOD_LOCAL_FRONT if from_front else BLOOD_LOCAL_REAR
	if same_team:
		return BLOOD_FRIENDLY
	if head:
		return BLOOD_HEADSHOT
	if dmg_health >= HEAVY_DAMAGE:
		return BLOOD_HIGH
	if dmg_health >= MEDIUM_DAMAGE:
		return BLOOD_MED
	return BLOOD_LOW


## Whether an effect puts blood on the world behind.
static func bleeds(effect: String) -> bool:
	return RAYS.has(effect)


## The rays that look for where a hit's blood lands: count of them along
## the round from at, each turned within the cone and tilted down, as far as
## REACH, and one straight down to the floor. Each is [from, to].
static func blood_rays(at: Vector3, direction: Vector3, count: int, rng: RandomNumberGenerator) -> Array[PackedVector3Array]:
	var rays: Array[PackedVector3Array] = []
	var along := direction.normalized()
	if along.length_squared() < 1e-6:
		along = Vector3.FORWARD
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(along).normalized()
	var spread := tan(deg_to_rad(CONE_DEGREES))
	for i in count:
		var way := along + side * rng.randf_range(-spread, spread) + up * rng.randf_range(-spread, spread)
		way = (way.normalized() + Vector3.DOWN * TILT_DOWN).normalized()
		rays.append(PackedVector3Array([at, at + way * REACH]))
	rays.append(PackedVector3Array([at, at + Vector3.DOWN * FLOOR_REACH]))
	return rays


func _process(_delta: float) -> void:
	var now := DrawClock.usec()
	for hit in _pending:
		_start(hit, now)
	_pending.clear()
	_hurt.clear()
	_fade_splats(now)
	_bursts = _bursts.filter(func(burst: Dictionary) -> bool: return _age(burst, now) <= _lifetime(burst))
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	quads.begin()
	_draw_bursts(now, camera.global_transform)
	quads.finish()


func _physics_process(_delta: float) -> void:
	if _rays.is_empty() or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	for ray in _rays:
		var query := PhysicsRayQueryParameters3D.create(ray["from"], ray["to"], Hitscan.WORLD_LAYER)
		var hit := PhysicsQueries.intersect_ray(space, query)
		if not hit.is_empty():
			splat(hit["position"], hit["normal"])
	_rays.clear()


func _start(hit: Dictionary, now: int) -> void:
	var effect: String = hit["effect"]
	# Your own hits are CS2's local set, on your screen; nothing is sprayed
	# in front of your own eyes.
	if effect != BLOOD_LOCAL_FRONT and effect != BLOOD_LOCAL_REAR:
		_bursts.append({"effect": effect, "at": hit["at"], "direction": hit["direction"], "born": now, "seed": _rng.randi()})
	var count: int = RAYS.get(effect, 0)
	if effect == BLOOD_LOCAL_FRONT or effect == BLOOD_LOCAL_REAR:
		count = 1
	if count <= 0:
		return
	for ray in blood_rays(hit["at"], hit["direction"], count, _rng):
		_rays.append({"from": ray[0], "to": ray[1]})


## The rays waiting for the next physics frame.
func pending_rays() -> int:
	return _rays.size()


## The hits noted and not started yet, as a copy.
func pending_hits() -> Array[Dictionary]:
	return _pending.duplicate()


## The sprays and sparks being drawn.
func bursts() -> int:
	return _bursts.size()


## The splats on the world.
func splats() -> Array[Decal]:
	return _splats.duplicate()


## A blood splat on the world at at, facing out along normal: the next of
## the pool, the oldest going when it is full. Never on a body (the decal
## leaves RigModel.LAYER out, as CS2's m_bNoDecalsOnOwner does).
func splat(at: Vector3, normal: Vector3) -> Decal:
	var decal: Decal
	if _splats.size() < max_splats:
		decal = Decal.new()
		decal.cull_mask = 0xFFFFF & ~RigModel.LAYER
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.normal_fade = BulletImpacts.NORMAL_FADE
		decal.texture_albedo = blood_texture()
		add_child(decal)
		_splats.append(decal)
		_splat_born.append(0)
	else:
		decal = _splats[_next_splat]
	var index := _splats.find(decal)
	_next_splat = (index + 1) % max_splats
	_splat_born[index] = DrawClock.usec()
	var scale_by := _rng.randf_range(0.7, 1.3)
	decal.size = Vector3(SPLAT_SIZE * scale_by, SPLAT_DEPTH, SPLAT_SIZE * scale_by)
	decal.modulate = Color(1, 1, 1, 1)
	decal.visible = true
	var up := normal.normalized()
	var spin := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	var centre := at + up * (SPLAT_DEPTH * 0.25)
	if decal.is_inside_tree():
		decal.global_transform = Transform3D(BulletImpacts._basis_facing(-up) * spin, centre)
	else:
		decal.transform = Transform3D(BulletImpacts._basis_facing(-up) * spin, centre)
	return decal


## Splats past CS2's 30 s fade out over its 3 s, then go.
func _fade_splats(now: int) -> void:
	for i in _splats.size():
		var decal := _splats[i]
		if not decal.visible:
			continue
		var age := float(now - _splat_born[i]) / 1_000_000.0
		var left := 1.0 - clampf((age - DECAL_FADE_START) / DECAL_FADE_SECONDS, 0.0, 1.0)
		decal.modulate.a = left
		if left <= 0.0:
			decal.visible = false


static func _age(burst: Dictionary, now: int) -> float:
	return float(now - int(burst["born"])) / 1_000_000.0


static func _lifetime(burst: Dictionary) -> float:
	return SPARK_SECONDS if burst["effect"] == HELMET else SPRAY_SECONDS


func _draw_bursts(now: int, eye: Transform3D) -> void:
	for burst in _bursts:
		var helmet: bool = burst["effect"] == HELMET
		var share := clampf(_age(burst, now) / _lifetime(burst), 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(burst["seed"])
		var along: Vector3 = burst["direction"]
		var at: Vector3 = burst["at"]
		var cards := SPARK_CARDS if helmet else SPRAY_CARDS
		if burst["effect"] == BLOOD_HEADSHOT or burst["effect"] == BLOOD_HIGH:
			cards += 4
		for i in cards:
			var way := (along + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
			if helmet:
				# Sparks glance back off the helmet.
				way = (-along + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 0.8), rng.randf_range(-0.8, 0.8))).normalized()
			var travel := SPRAY_TRAVEL * rng.randf_range(0.4, 1.0) * sqrt(share)
			var centre := at + way * travel + Vector3.DOWN * 20.0 * share * share
			var half := (0.6 if helmet else 1.5 + 3.5 * share) * rng.randf_range(0.7, 1.3)
			var fade := 1.0 - share
			var color := Color(3.0, 2.2, 1.2, fade) if helmet else Color(0.22, 0.01, 0.01, 0.85 * fade)
			quads.quad(card_texture(), &"add" if helmet else &"mix", false,
				EffectQuads.sprite(centre, half, rng.randf_range(0.0, TAU), eye), Rect2(0, 0, 1, 1), color)


func _same_team(victim: int, attacker: int) -> bool:
	if game == null or victim == attacker:
		return false
	var a := game.roster.team_of(victim)
	return not a.is_empty() and a == game.roster.team_of(attacker)


## Whether a round going along direction met victim from in front.
func _from_front(victim: int, direction: Vector3) -> bool:
	var body := game.roster.player(victim) if game != null else null
	if body == null:
		return true
	if not body is PlayerSim:
		return true
	var facing := PlayerInput.aim_direction((body as PlayerSim).yaw_degrees, 0.0)
	return Vector2(facing.x, facing.z).dot(Vector2(direction.x, direction.z)) < 0.0


## The splats' stand-in: a dark red blot, ragged at its edge, made once.
static func blood_texture() -> Texture2D:
	if _blood_texture != null:
		return _blood_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.12
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var edge := 0.62 + 0.3 * noise.get_noise_2d(x, y)
			var a := clampf((edge - d) * 6.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.28, 0.02, 0.02, a * 0.9))
	image.generate_mipmaps()
	_blood_texture = ImageTexture.create_from_image(image)
	return _blood_texture


## The cards' stand-in: a soft round blot, white, tinted per card.
static func card_texture() -> Texture2D:
	if _card_texture != null:
		return _card_texture
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	image.generate_mipmaps()
	_card_texture = ImageTexture.create_from_image(image)
	return _card_texture
