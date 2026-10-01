extends "res://tests/check_suite.gd"

## Checks what is seen of a round meeting a body (HitEffects;
## reference/research/blood-and-impacts.md): which of CS2's effects a hit
## calls for, the rays that look for where its blood lands, a view noting
## hits from the game's player_hurt and bullet_damage and starting them on
## the next frame, and the blood splats it leaves on the world, never on a
## body, from a pool that recycles.
##
##   godot --headless --path . --script tests/run_hit_effect_checks.gd
##
## Needs nothing extracted: what it draws is its own stand-in until CS2's
## effects are.


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_choice()
	_test_the_rays()
	await _test_the_view_notes_hits()
	await _test_the_splats()
	_finish("hit-effects")


func _test_the_choice() -> void:
	var head := DamageInfo.HITGROUP_HEAD
	var chest := DamageInfo.HITGROUP_CHEST
	_check_equal(HitEffects.effect_for(head, 0, 20, false, false), HitEffects.HELMET, "a head in a helmet that took it: the helmet's sparks")
	_check_equal(HitEffects.effect_for(head, 100, 0, false, false), HitEffects.BLOOD_HEADSHOT, "a bare head: headshot blood")
	_check_equal(HitEffects.effect_for(chest, 10, 5, false, false), HitEffects.BLOOD_LOW, "under 20 taken: light blood")
	_check_equal(HitEffects.effect_for(chest, 20, 5, false, false), HitEffects.BLOOD_MED, "20 to 39: medium")
	_check_equal(HitEffects.effect_for(chest, 40, 0, false, false), HitEffects.BLOOD_HIGH, "40 or more: heavy")
	_check_equal(HitEffects.effect_for(chest, 27, 0, true, false), HitEffects.BLOOD_FRIENDLY, "a teammate: the friendly blood")
	_check_equal(HitEffects.effect_for(chest, 27, 0, false, true, true), HitEffects.BLOOD_LOCAL_FRONT, "your own, from in front: the local set")
	_check_equal(HitEffects.effect_for(chest, 27, 0, false, true, false), HitEffects.BLOOD_LOCAL_REAR, "and from behind")
	_check_equal(HitEffects.effect_for(head, 0, 20, false, true), HitEffects.HELMET, "your own helmet sparks too")
	_check(HitEffects.bleeds(HitEffects.BLOOD_HIGH) and not HitEffects.bleeds(HitEffects.HELMET), "a helmet's sparks leave no blood behind")


func _test_the_rays() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var at := Vector3(10, 64, -5)
	var along := Vector3(1, 0, 0)
	var rays := HitEffects.blood_rays(at, along, 3, rng)
	_check_equal(rays.size(), 4, "three rays along the round and one down to the floor")
	var within := true
	for i in 3:
		var ray := rays[i]
		var way := ray[1] - ray[0]
		within = within and ray[0] == at and is_equal_approx(way.length(), HitEffects.REACH)
		var most := deg_to_rad(HitEffects.CONE_DEGREES) * 1.5 + atan(HitEffects.TILT_DOWN) + 0.01
		within = within and way.normalized().angle_to(along) <= most and way.y < 0.0
	_check(within, "each from the hit, as far as the reach, within the cone and tilted down")
	var down := rays[3][1] - rays[3][0]
	_check(down.normalized().is_equal_approx(Vector3.DOWN) and is_equal_approx(down.length(), HitEffects.FLOOR_REACH),
		"the last straight down, to the floor's reach")


## player_hurt then bullet_damage, as a round hands them out, is one hit:
## noted as the tick hands them out, started on the next frame, with its
## rays waiting for the physics frame after.
func _test_the_view_notes_hits() -> void:
	var game := GameSystems.new()
	var view := HitEffects.new()
	root.add_child(view)
	view.set_process(false)
	view.set_physics_process(false)
	view.watch(game, 9)
	await process_frame
	_hit(game, 4, 1, DamageInfo.HITGROUP_CHEST, 27, 0, Vector3(0, 60, -300))
	_hit(game, 4, 1, DamageInfo.HITGROUP_HEAD, 0, 30, Vector3(0, 70, -300))
	_hit(game, 9, 1, DamageInfo.HITGROUP_STOMACH, 45, 0, Vector3(0, 40, -100))
	game.events.flush()
	var hits := view.pending_hits()
	_check_equal(hits.map(func(h: Dictionary) -> String: return h.effect),
		[HitEffects.BLOOD_MED, HitEffects.HELMET, HitEffects.BLOOD_LOCAL_FRONT],
		"a 27 to the chest, a helmet's, and the viewer's own")
	_check(hits.size() == 3 and (hits[0].at as Vector3).is_equal_approx(Vector3(0, 60, -300)), "each where on the body it landed")
	view._process(0.0)
	_check(view.pending_hits().is_empty(), "the next frame starts them")
	_check_equal(view.bursts(), 2, "a spray and the sparks; nothing sprayed in the viewer's own eyes")
	_check_equal(view.pending_rays(), 3 + 2, "the medium's two rays and a floor ray; the viewer's one and a floor ray; none for the helmet")
	# bullet_damage alone (no player_hurt before it) still bleeds.
	game.events.send(&"bullet_damage", {"victim": 5, "attacker": 1, "x": 1.0, "y": 2.0, "z": 3.0, "damage_dir_z": -1.0})
	game.events.flush()
	_check_equal(view.pending_hits().map(func(h: Dictionary) -> String: return h.effect), [HitEffects.BLOOD_LOW], "without its player_hurt, light blood")
	view.queue_free()
	await process_frame


func _hit(game: GameSystems, victim: int, attacker: int, hitgroup: int, health: int, armor: int, at: Vector3) -> void:
	game.events.send(&"player_hurt", {"userid": victim, "attacker": attacker, "dmg_health": health, "dmg_armor": armor, "hitgroup": hitgroup})
	game.events.send(&"bullet_damage", {
		"victim": victim, "attacker": attacker, "damage_dir_z": -1.0, "x": at.x, "y": at.y, "z": at.z,
	})


## In a world of its own (so no game's physics owns its space): a wall 100
## units behind a hit takes the blood, a body in front of it takes none, and
## the pool recycles its oldest.
func _test_the_splats() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var wall := StaticBody3D.new()
	wall.collision_layer = Hitscan.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 400, 8)
	shape.shape = box
	wall.add_child(shape)
	viewport.add_child(wall)
	wall.position = Vector3(0, 60, -104)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Hitscan.WORLD_LAYER
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(400, 8, 400)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	viewport.add_child(floor_body)
	floor_body.position = Vector3(0, -4, 0)
	var view := HitEffects.new()
	view.max_splats = 4
	viewport.add_child(view)
	view.set_process(false)
	await physics_frame
	await physics_frame
	var game := GameSystems.new()
	view.watch(game, 9)
	_hit(game, 4, 1, DamageInfo.HITGROUP_CHEST, 45, 0, Vector3(0, 60, 0))
	game.events.flush()
	view._process(0.0)
	await physics_frame
	await physics_frame
	var splats := view.splats()
	var on_wall := splats.filter(func(d: Decal) -> bool: return absf(d.global_position.z - -100.0) < 12.0)
	var on_floor := splats.filter(func(d: Decal) -> bool: return absf(d.global_position.y) < 12.0)
	_check(splats.size() == 4 and on_wall.size() == 3 and on_floor.size() == 1,
		"a heavy hit leaves three splats on the wall behind and one on the floor (%d, %d, %d)" % [splats.size(), on_wall.size(), on_floor.size()])
	_check(splats.all(func(d: Decal) -> bool: return d.cull_mask & RigModel.LAYER == 0), "none of them drawn on a body")
	_check(splats.all(func(d: Decal) -> bool: return d.texture_albedo != null), "each with the stand-in's blot")
	var first := splats[0]
	var again := view.splat(Vector3(50, 60, -100), Vector3(0, 0, 1))
	_check(again == first and view.splats().size() == 4, "past the pool's size the oldest is used again")
	_check(again.global_position.distance_to(Vector3(50, 60, -100)) < HitEffects.SPLAT_DEPTH, "where it is put now")
	view._fade_splats(DrawClock.usec() + int((HitEffects.DECAL_FADE_START + HitEffects.DECAL_FADE_SECONDS + 1.0) * 1_000_000.0))
	_check(view.splats().all(func(d: Decal) -> bool: return not d.visible), "after CS2's 30 s and its 3 s fade, all gone")
	viewport.queue_free()
	await process_frame
