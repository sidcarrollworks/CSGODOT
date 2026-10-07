class_name HitEffects
extends Node3D

## Per-pellet snapshots dispatch blood, helmet sparks, wounds and additive
## flinches. Events queue values; rendering runs on draw frames, traces in
## physics. CS2's closed game-side root/CP selection remains inferred.
const BLOOD_LOW := "blood_impact_low"
const BLOOD_MED := "blood_impact_med"
const BLOOD_HIGH := "blood_impact_high"
const BLOOD_HEADSHOT := "blood_impact_light_headshot"
const BLOOD_FRIENDLY := "blood_impact_friendly"
const BLOOD_LOCAL_FRONT := "blood_impact_localfrontsimple"
const BLOOD_LOCAL_REAR := "blood_impact_localrearhit"
const HELMET := "impact_helmet_headshot"
const MEDIUM_DAMAGE := 20
const HEAVY_DAMAGE := 40
const LIMIT_PENDING := 128
## Wall marks are separate from authored parent-death ground splashes.
## This reach and trace approximate the unverified client wall-mark path.
const WALL_REACH := 172.0
const DECAL_FADE_START := 30.0
const DECAL_FADE_SECONDS := 3.0
@export var max_splats := 64
var game: GameSystems
var listener_id := GameEvents.NOBODY
var quads: HitQuads
var models: HitModels
var wounds: BodyWounds
var particles := HitParticles.new()
var _pending: Array[Dictionary] = []
var _rays: Array[Dictionary] = []
var _splats: Array[Decal] = []
var _splat_state: Array[Dictionary] = []
var _next_splat := 0
var _rng := RandomNumberGenerator.new()
var _materials := {}
## Optional instrumentation for profile_hits, disabled during normal play.
var profile := false
var costs_usec := {}


func watch(p_game: GameSystems, listener: int) -> void:
	_unwatch()
	game = p_game
	listener_id = listener
	game.events.listen(&"bullet_damage", _on_bullet_damage)
	game.events.listen(&"player_spawn", _on_spawn)


func _ready() -> void:
	add_to_group(&"hit_effects")
	quads = HitQuads.new()
	add_child(quads)
	models = HitModels.new()
	add_child(models)
	wounds = BodyWounds.new()
	add_child(wounds)
	for layer: Dictionary in HitEffectTable.LAYERS.values():
		for renderer: Dictionary in layer.get("renderers", []):
			quads.prepare(renderer)
			models.prepare(renderer)
	for material: String in HitEffectTable.MATERIALS:
		if material.contains("/blood/"):
			_material(material)


func _exit_tree() -> void:
	_unwatch()


func _unwatch() -> void:
	if game != null:
		game.events.unlisten(&"bullet_damage", _on_bullet_damage)
		game.events.unlisten(&"player_spawn", _on_spawn)


func _on_spawn(event: GameEvent) -> void:
	_append({"clear": int(event.fields.userid)})


func _on_bullet_damage(event: GameEvent) -> void:
	var f := event.fields
	var victim := int(f.victim)
	var direction := Vector3(f.damage_dir_x, f.damage_dir_y, f.damage_dir_z).normalized()
	var own := victim == listener_id and victim != GameEvents.NOBODY
	var effect := effect_for(int(f.hitgroup), int(f.dmg_health), int(f.dmg_armor),
		_same_team(victim, int(f.attacker)), own, _from_front(victim, direction))
	_append({"effect": effect, "at": Vector3(f.x, f.y, f.z), "direction": direction,
		"normal": Vector3(f.normal_x, f.normal_y, f.normal_z), "victim": victim,
		"zone": StringName(f.zone), "side": StringName(f.side), "bone": StringName(f.bone),
		"health": float(f.health), "killed": bool(f.killed), "damage": float(f.dmg_health), "born": event.at_usec,
		"helmet": int(f.hitgroup) == DamageInfo.HITGROUP_HEAD and float(f.dmg_armor) > 0, "screen": own})


func _append(hit: Dictionary) -> void:
	if _pending.size() < LIMIT_PENDING:
		_pending.append(hit)


## Armor-only helmet hits spark; a helmet hit taking health can also bleed.
## A blanket blood/spark mutual exclusion is not established by the files.
static func effect_for(hitgroup: int, dmg_health: int, dmg_armor: int, same_team: bool, own_view: bool, from_front: bool = true) -> String:
	if hitgroup == DamageInfo.HITGROUP_HEAD and dmg_armor > 0 and dmg_health <= 0:
		return HELMET
	if dmg_health <= 0:
		return ""
	if own_view:
		return BLOOD_LOCAL_FRONT if from_front else BLOOD_LOCAL_REAR
	if same_team:
		return BLOOD_FRIENDLY
	if hitgroup == DamageInfo.HITGROUP_HEAD:
		return BLOOD_HEADSHOT
	return BLOOD_HIGH if dmg_health >= HEAVY_DAMAGE else (BLOOD_MED if dmg_health >= MEDIUM_DAMAGE else BLOOD_LOW)


func queue_world(surface: String, at: Vector3, normal: Vector3, direction: Vector3, at_usec: int) -> void:
	var properties := BulletImpacts.impact_for(surface)
	var name := String(properties.get("effect", "impact_concrete")).get_file().get_basename()
	if not name.is_empty():
		_append({"effect": name, "at": at + normal * 0.1, "direction": normal,
			"incoming": direction, "born": at_usec, "world": true})


## A round through a gun on the ground: sparks where it met it, the helmet's
## as an armoured head's (Sid, 2026-10-06), outward along its surface.
func queue_spark(at: Vector3, normal: Vector3, direction: Vector3, at_usec: int) -> void:
	_append({"effect": HELMET, "at": at, "normal": normal, "direction": direction,
		"born": at_usec, "world": true})


func _process(_dt: float) -> void:
	var measured := Time.get_ticks_usec() if profile else 0
	if profile:
		costs_usec.clear()
	var now := DrawClock.usec()
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_transform if camera != null else Transform3D.IDENTITY
	for hit in _pending:
		if hit.has("clear"):
			wounds.clear_player(int(hit.clear))
		else:
			_start(hit, eye.origin)
	_pending.clear()
	if profile:
		measured = _measure(measured, "spawn")
	particles.advance(now)
	for request in particles.ground:
		if _rays.size() < LIMIT_PENDING:
			_rays.append(request)
	particles.ground.clear()
	if profile:
		measured = _measure(measured, "advance")
	quads.begin()
	models.begin()
	particles.draw(quads, models, eye, now, camera.fov if camera != null else 90.0)
	if profile:
		measured = _measure(measured, "draw")
	quads.finish()
	models.finish()
	if profile:
		measured = _measure(measured, "submit")
	wounds.update_marks()
	_fade_splats(now)
	if profile:
		_measure(measured, "marks")


func _measure(since: int, key: String) -> int:
	var now := Time.get_ticks_usec()
	costs_usec[key] = now - since
	return now


func _start(hit: Dictionary, eye: Vector3) -> void:
	var effect := String(hit.effect)
	var born := int(hit.born)
	var at: Vector3 = hit.at
	var direction: Vector3 = hit.direction
	var local_hit := bool(hit.get("screen", false))
	# The local CP placement is not recovered. The former camera-plane
	# approximation put an opaque red sprite over the crosshair. Local
	# damage is shown by DamageIndicator; other players retain their blood.
	if not local_hit and (bool(hit.get("helmet", false)) or effect == HELMET):
		var outward: Vector3 = hit.get("normal", Vector3.ZERO)
		if outward.length_squared() < 1e-8:
			outward = -direction
		particles.spawn(HELMET, at, outward, born, eye)
	if not local_hit and not effect.is_empty() and effect != HELMET:
		particles.spawn(effect, at, direction, born, eye, float(hit.get("damage", 30)), bool(hit.get("screen", false)), bool(hit.get("world", false)))
	if bool(hit.get("world", false)):
		return
	var bodies := drawn_models(int(hit.victim))
	if not bool(hit.get("killed", false)):
		for body in bodies:
			body.flinch(hit.zone, hit.side, direction, born)
	if float(hit.damage) > 0.0:
		var normal: Vector3 = hit.normal
		if normal.length_squared() < 1e-8:
			normal = -direction
		wounds.mark(int(hit.victim), bodies, hit.bone, at, normal)
		if _rays.size() < LIMIT_PENDING:
			_rays.append({"wall": true, "at": at + direction, "to": at + direction * WALL_REACH, "born": born})


func drawn_models(userid: int) -> Array[PlayerModel]:
	var out: Array[PlayerModel] = []
	var body := game.roster.player(userid) if game != null else null
	if body is PlayerSim and is_instance_valid(body.model):
		out.append(body.model)
	var viewer := body as PlayerController
	if viewer == null and body is PlayerSim:
		viewer = body.controlled_by as PlayerController
	if is_instance_valid(viewer) and is_instance_valid(viewer.view) and viewer.pawn() == body:
		for model: PlayerModel in [viewer.view.body_model, viewer.view.body_shadow]:
			if is_instance_valid(model) and not out.has(model):
				out.append(model)
	return out


func _physics_process(_dt: float) -> void:
	for request in _rays:
		var at: Vector3 = request.at
		var wall := bool(request.get("wall", false))
		var to: Vector3 = request.to if wall else at + Vector3.DOWN * float(HitEffectTable.GROUND[request.effect].get("ground_trace", 256.0))
		var query := PhysicsRayQueryParameters3D.create(at, to, Hitscan.WORLD_LAYER)
		var contact := PhysicsQueries.intersect_ray(get_world_3d().direct_space_state, query)
		if contact.is_empty():
			continue
		if wall:
			var groups: Array = HitEffectTable.DECAL_GROUPS.get("Blood", [])
			if not groups.is_empty():
				_rng.seed = hash([at, request.born])
				var material := String(groups[_rng.randi_range(0, groups.size() - 1)].material)
				var authored: Dictionary = HitEffectTable.MATERIALS.get(material, {}).get("params", {})
				var fade_start := float(authored.get("DecalFadeStartTime", DECAL_FADE_START))
				var fade_duration := float(authored.get("DecalFadeDuration", DECAL_FADE_SECONDS))
				splat(contact.position, contact.normal, {"material": material, "born": request.born,
					"life": fade_start + fade_duration, "fade_in": 0.0, "fade_out": fade_duration, "persistent": true})
		else:
			var params := request.duplicate()
			params["material"] = HitEffectTable.GROUND[request.effect].material
			var layer: Dictionary = HitEffectTable.GROUND[request.effect]
			params["depth"] = float(layer.get("projection_max", 5)) - float(layer.get("projection_min", -15))
			splat(contact.position, contact.normal, params)
	_rays.clear()


func splat(at: Vector3, normal: Vector3, params: Dictionary) -> Decal:
	var material := _material(String(params.material))
	if material.is_empty() or material.color == null or max_splats <= 0:
		return null
	var decal: Decal
	var index: int
	if _splats.size() < max_splats:
		decal = Decal.new()
		add_child(decal)
		index = _splats.size()
		_splats.append(decal)
		_splat_state.append({})
	else:
		index = _next_splat
		decal = _splats[index]
		_next_splat = (_next_splat + 1) % max_splats
	var half := float(params.get("half", float(material.width) * 0.5))
	var height := half * 2.0 if params.has("half") else float(material.height)
	decal.size = Vector3(half * 2.0, maxf(float(params.get("depth", material.depth)), 1.0), height)
	decal.texture_albedo = material.color
	decal.texture_normal = material.normal
	decal.cull_mask = 0xFFFFF & ~(RigModel.LAYER | DroppedItemView.LAYER)
	decal.albedo_mix = 1.0
	# Above every mark before it, holes too (BulletImpacts.next_decal_order).
	decal.sorting_offset = BulletImpacts.next_decal_order()
	var direction := normal.normalized()
	var basis := Basis.looking_at(-direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP)
	basis = basis.rotated(basis.x, PI * 0.5)
	basis = basis.rotated(direction, float(params.get("roll", 0.0)))
	decal.global_transform = Transform3D(basis, at + direction * 0.05)
	decal.visible = true
	_splat_state[index] = params
	return decal


func _material(path: String) -> Dictionary:
	if _materials.has(path):
		return _materials[path]
	var data: Dictionary = HitEffectTable.MATERIALS.get(path, {})
	var textures: Dictionary = data.get("textures", {})
	var values: Dictionary = data.get("params", {})
	var color := SpriteSheet.named(String(textures.get("g_tColor", "")))
	var ao := SpriteSheet.named(String(textures.get("g_tAmbientOcclusion", "")))
	var normal := SpriteSheet.named(String(textures.get("g_tNormal", "")))
	var albedo: Texture2D = null
	if color != null:
		albedo = ImageTexture.create_from_image(BulletImpacts.occluded(color.texture.get_image(), ao.texture.get_image() if ao != null else null))
	var out := {"color": albedo, "normal": normal.texture if normal != null else null,
		"width": float(values.get("DecalWorldWidth", 35.6)), "height": float(values.get("DecalWorldHeight", 35.6)), "depth": float(values.get("DecalDepth", 15.0))}
	_materials[path] = out
	return out


func _fade_splats(now: int) -> void:
	for i in _splats.size():
		var state := _splat_state[i]
		var age := maxf(float(now - int(state.born)) / 1e6, 0.0)
		var life := float(state.life)
		var leave := float(state.fade_out) * (1.0 if bool(state.get("persistent", false)) else life)
		var alpha := clampf((life - age) / maxf(leave, 0.001), 0.0, 1.0)
		var enter := float(state.fade_in)
		if enter > 0.0:
			alpha *= clampf(age / enter, 0.0, 1.0)
		_splats[i].modulate.a = alpha
		_splats[i].visible = alpha > 0.0


func _same_team(victim: int, attacker: int) -> bool:
	if game == null or victim == attacker:
		return false
	var a := game.roster.team_of(victim)
	return not a.is_empty() and a == game.roster.team_of(attacker)


func _from_front(victim: int, direction: Vector3) -> bool:
	var body := game.roster.player(victim) if game != null else null
	if not body is PlayerSim:
		return true
	var facing := PlayerInput.aim_direction(body.yaw_degrees, 0.0)
	return Vector2(facing.x, facing.z).dot(Vector2(direction.x, direction.z)) < 0.0


func pending_hits() -> Array[Dictionary]:
	return _pending.duplicate()


func pending_rays() -> int:
	return _rays.size()


func splats() -> Array[Decal]:
	return _splats.duplicate()
