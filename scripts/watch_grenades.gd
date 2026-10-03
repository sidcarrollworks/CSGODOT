extends "res://scripts/watch_game.gd"

## The performance watcher plus exact grenade launch and contact records.
## godot --path . --script scripts/watch_grenades.gd -- --mode practice --map de_dust2 --window=1920x1080 --grenades=.godot/grenade-throws.jsonl
## Each record is flushed to disk during play. Only launches and contacts
## are recorded; flight, collision masks and movement are unchanged.
## --lineup=mid-door uses Sid's October 3 CS2 horizontal position and aim.
## Keep the verified local floor height; plain getpos gives camera position.
const MID_DOOR_FEET := Vector3(-660.031250, 89.8, -344.002014)
const MID_DOOR_YAW := 272.595718
const MID_DOOR_PITCH := 15.030418

var _grenade_log: FileAccess
var _grenade_world: GameWorld
var _contact_ticks := {}
var _tracked_grenades := {}
var _prepare_mid_door := false


func _initialize() -> void:
	var path := "res://.godot/grenade-throws.jsonl"
	_prepare_mid_door = OS.get_cmdline_user_args().has("--lineup=mid-door")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--grenades="):
			path = argument.trim_prefix("--grenades=")
	_grenade_log = FileAccess.open(path, FileAccess.WRITE)
	if _grenade_log == null:
		push_error("Cannot write grenade records to %s: %s" % [path, FileAccess.get_open_error()])
		quit(1)
		return
	_write_grenade({"event": "run", "arguments": Array(OS.get_cmdline_user_args()),
		"grenade_mask": GrenadeRules.COLLIDE_MASK, "sky_layer": MapImporter.SKY_LAYER})
	print("GRENADE launch/contact records: ", ProjectSettings.globalize_path(path))
	super._initialize()


func _find_world(now: int) -> void:
	super._find_world(now)
	if not is_instance_valid(_world):
		return
	if _world != _grenade_world:
		_grenade_world = _world
		_contact_ticks.clear()
		_tracked_grenades.clear()
		_world.game.entities.spawned.connect(_on_grenade_spawned)
		_world.game.entities.removed.connect(_on_grenade_removed)
	if _prepare_mid_door:
		for player in _world.players:
			if player is PlayerController:
				player.place(MID_DOOR_FEET, MID_DOOR_YAW)
				player.velocity = Vector3.ZERO
				player.pitch_degrees = MID_DOOR_PITCH
				player.previous_pitch_degrees = MID_DOOR_PITCH
				player.input.pitch_degrees = MID_DOOR_PITCH
				player.inventory.add(GrenadeRules.SMOKE)
				player.inventory.select_slot(ItemDef.Slot.GRENADE)
				_prepare_mid_door = false
				print("GRENADE mid-door setup: feet ", MID_DOOR_FEET, ", yaw ", MID_DOOR_YAW, ", pitch ", MID_DOOR_PITCH)
				break


func _on_grenade_spawned(entity: SimEntity) -> void:
	var grenade := entity as GrenadeEntity
	if grenade == null:
		return
	_tracked_grenades[grenade.id] = grenade
	var record := {"event": "launch", "entityid": grenade.id, "userid": grenade.owner_id,
		"weapon": grenade.weapon_class, "thrown_usec": grenade.thrown_usec,
		"position": _vector(grenade.flight.position), "velocity": _vector(grenade.flight.velocity),
		"blocked_start": grenade.flight.blocked_start}
	var player := _world.game.roster.player(grenade.owner_id) as PlayerSim
	if player != null:
		var state := player.grenade_throw
		var parameters := player.grenade_parameters(grenade.thrown_usec)
		record.merge({"feet": _vector(player.global_position), "on_ground": player.on_ground,
			"noclip": player.noclip, "live_velocity": _vector(player.velocity),
			"live_yaw": player.yaw_degrees, "live_pitch": player.pitch_degrees,
			"strength": GrenadeRules.launch_strength(state.strength),
			"snapshot_used": not state.snapshot.is_empty() and state.jump_eligible(grenade.thrown_usec),
			"stash_usec": state.stash_usec, "jump_throw": state.jump_throw,
			"eye": _vector(parameters.eye), "center": _vector(parameters.center),
			"yaw": parameters.yaw, "pitch": parameters.pitch,
			"thrower_velocity": _vector(parameters.velocity)})
	_write_grenade(record)


func _on_event(event: GameEvent) -> void:
	super._on_event(event)
	if event.name == &"grenade_bounce":
		_record_contacts(event)
	elif event.name in [&"smokegrenade_detonate", &"hegrenade_detonate",
		&"flashbang_detonate", &"decoy_started", &"molotov_detonate"]:
		_write_grenade({"event": String(event.name), "tick": event.tick,
			"at_usec": event.at_usec, "fields": event.fields})


func _record_contacts(event: GameEvent) -> void:
	var at := GrenadeSystem.position_of(event.fields)
	for grenade: GrenadeEntity in _tracked_grenades.values():
		if grenade.owner_id != int(event.fields.userid):
			continue
		if int(_contact_ticks.get(grenade.id, -1)) == event.tick:
			continue
		var matches := false
		for touch in grenade.flight.touches:
			if (touch.position as Vector3).distance_squared_to(at) < 0.01:
				matches = true
		if not matches:
			continue
		_contact_ticks[grenade.id] = event.tick
		for touch in grenade.flight.touches:
			_write_grenade({"event": "contact", "entityid": grenade.id, "tick": event.tick,
				"at_usec": event.at_usec, "age_seconds": grenade.age(event.at_usec),
				"position": _vector(touch.position), "normal": _vector(touch.normal),
				"surface": touch.surface, "player": touch.player,
				"end_of_tick_velocity": _vector(grenade.flight.velocity),
				"blocked_start": grenade.flight.blocked_start, "at_rest": grenade.flight.at_rest})


func _on_grenade_removed(entity: SimEntity) -> void:
	if entity is GrenadeEntity:
		# Events flush after removal; retain the final tick's contacts until
		# its listeners have read them, including immediate fire impacts.
		_forget_grenade.call_deferred(entity)


func _forget_grenade(grenade: GrenadeEntity) -> void:
	if _tracked_grenades.get(grenade.id) == grenade:
		_tracked_grenades.erase(grenade.id)
		_contact_ticks.erase(grenade.id)


func _write_grenade(record: Dictionary) -> void:
	_grenade_log.store_line(JSON.stringify(record))
	_grenade_log.flush()


static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
