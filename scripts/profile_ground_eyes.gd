extends "res://scripts/profile_box3d_match.gd"

## Isolate the terrain sampler in the seeded, ten-player Dust2 fixture.
## Run each in its own otherwise idle process; repeat in reversed order:
## godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native
## godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native --without-terrain
## The control disables update() after warmup; it is not a main-branch run.
## Inherited timing includes GameWorld.step(), excluding render/audio/UI.
## Query counters and endpoint collection are outside the timed interval.
var terrain_counts: Array[int] = []


class DisabledEyes extends GroundEyes:
	func update(_body: PlayerBody, _dt: float) -> void:
		pass


func _load_match(backend: String) -> void:
	await super(backend)
	if ClassDB.class_exists(&"HullMover"):
		var native_mover: Object = ClassDB.instantiate(&"HullMover")
		print("TERRAIN MATCH stamp=", native_mover.call(&"get_sources"))
	var disabled := "--without-terrain" in OS.get_cmdline_user_args()
	if disabled:
		for player in world.players:
			player.ground_eyes = DisabledEyes.new()
	print("TERRAIN MATCH sampler=", "disabled" if disabled else "active", " players=", world.players.size())


func _tick() -> void:
	var before := _terrain_queries()
	super()
	terrain_counts.append(_terrain_queries() - before)


func _terrain_queries() -> int:
	var count := 0
	for player in world.players:
		count += player.ground_eyes.queries
	return count


func _report_costs(label: String) -> void:
	super(label)
	var total := 0
	var most := 0
	for count in terrain_counts:
		total += count
		most = maxi(most, count)
	var endpoints := []
	for player in world.players:
		endpoints.append({"team": player.team, "position": var_to_str(player.position), "velocity": var_to_str(player.velocity)})
	print("TERRAIN MATCH ", JSON.stringify({"terrain_casts": total, "most_per_tick": most,
		"mean_per_tick": float(total) / terrain_counts.size(), "endpoints": endpoints}))
