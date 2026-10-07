extends "res://tests/check_suite.gd"

class ReactionModel extends PlayerModel:
	var reactions: Array[Array] = []
	func _ready() -> void:
		set_process(false)
	func flinch(zone: StringName, side: StringName, direction: Vector3, at_usec: int = -1) -> void:
		reactions.append([zone, side, direction, at_usec])

class ReactionBody extends PlayerController:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class ReactionView extends PlayerView:
	func _ready() -> void:
		set_process(false)

## Per-pellet dispatch, bounded authored sprays, parent-death ground traces,
## real projected materials and individual decal lifetimes.
func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_choices()
	_test_helmet_axis()
	_test_motion_and_death()
	await _test_events()
	await _test_flinch_dispatch()
	await _test_ground_and_pool()
	_finish("hit-effects")


func _test_choices() -> void:
	var head := DamageInfo.HITGROUP_HEAD
	var chest := DamageInfo.HITGROUP_CHEST
	_check_equal(HitEffects.effect_for(head, 0, 20, false, false), HitEffects.HELMET, "armor-only head hits spark")
	_check_equal(HitEffects.effect_for(head, 50, 20, false, false), HitEffects.BLOOD_HEADSHOT, "health damage can bleed through a helmet")
	_check_equal(HitEffects.effect_for(chest, 0, 0, false, false), "", "zero damage creates no blood")
	_check_equal(HitEffects.effect_for(chest, 10, 5, false, false), HitEffects.BLOOD_LOW, "light damage")
	_check_equal(HitEffects.effect_for(chest, 20, 5, false, false), HitEffects.BLOOD_MED, "medium threshold")
	_check_equal(HitEffects.effect_for(chest, 40, 0, false, false), HitEffects.BLOOD_HIGH, "heavy threshold")
	_check_equal(HitEffects.effect_for(chest, 27, 0, true, false), HitEffects.BLOOD_FRIENDLY, "friendly damage")
	_check_equal(HitEffects.effect_for(chest, 27, 0, false, true), HitEffects.BLOOD_LOCAL_FRONT, "current front simple effect")
	_check_equal(HitEffects.effect_for(chest, 27, 0, false, true, false), HitEffects.BLOOD_LOCAL_REAR, "rear damage")


func _test_helmet_axis() -> void:
	var view := HitEffects.new()
	var hit := {"effect":HitEffects.HELMET, "helmet":true, "born":1000000,
		"at":Vector3(20,60,0), "normal":Vector3.RIGHT, "direction":Vector3.FORWARD,
		"victim":4, "damage":0.0, "killed":true}
	view._start(hit, Vector3.ZERO)
	var armor_only := view.particles.live.filter(func(p: Dictionary) -> bool: return p.name.begins_with("impact_helmet"))
	_check(not armor_only.is_empty(), "armor-only helmet hit emits sparks")
	_check(armor_only.all(func(p: Dictionary) -> bool: return p.context.basis.x.is_equal_approx(Vector3.RIGHT)), "armor-only helmet sparks use contact normal")
	view.particles.live.clear()
	hit.effect = HitEffects.BLOOD_HEADSHOT
	view._start(hit, Vector3.ZERO)
	var with_blood := view.particles.live.filter(func(p: Dictionary) -> bool: return p.name.begins_with("impact_helmet"))
	_check_equal(with_blood.size(), armor_only.size(), "coexisting flesh/helmet reaction emits the helmet graph once")
	_check(with_blood.all(func(p: Dictionary) -> bool: return p.context.basis.x.is_equal_approx(Vector3.RIGHT)), "helmet sparks keep the same axis when flesh also bleeds")
	view.particles.live.clear()
	hit.effect = HitEffects.HELMET
	hit.normal = Vector3.ZERO
	view._start(hit, Vector3.ZERO)
	_check(view.particles.live.all(func(p: Dictionary) -> bool: return p.context.basis.x.is_equal_approx(Vector3.BACK)), "missing contact normal falls back against incoming bullet")
	view.free()


func _test_motion_and_death() -> void:
	var runner := HitParticles.new()
	runner.spawn(HitEffects.BLOOD_MED, Vector3(0,80,0), Vector3.FORWARD, 1000000, Vector3(0,80,300))
	_check(not runner.live.is_empty(), "authored children generate particles")
	_check(runner.live.any(func(p: Dictionary) -> bool: return p.name == "blood_impact_low_forw_spray"), "medium includes Rush Hour's forward spray")
	_check(runner.ground.is_empty(), "no immediate floor decal")
	var saved := runner.live.duplicate(true)
	runner.advance(1000000)
	_check_equal(runner.live.size(), saved.size(), "particles survive their birth instant")
	var p := {"origin":Vector3.ZERO,"velocity":Vector3(100,0,0),"gravity":Vector3(0,-300,0),"layer":{"drag":0.0}}
	_check(HitParticles.position(p, 0.5).is_equal_approx(Vector3(50,-37.5,0)), "ballistic path uses Source units and world-down gravity")
	p.layer.drag = 0.1
	var later := HitParticles.position(p,0.5)
	_check(later.x > 0 and later.x < 50 and later.y < 0, "drag reduces travel while gravity still falls")
	runner.advance(4000000)
	_check_equal(runner.live.size(), 0, "expired sprites removed")
	_check(not runner.ground.is_empty(), "trail deaths produce projected children")
	_check(runner.ground.all(func(g: Dictionary) -> bool: return float(HitEffectTable.GROUND[g.effect].ground_trace) == 256), "each child uses its own verified 256-unit ground trace")
	_check(runner.ground.all(func(g: Dictionary) -> bool: return g.life >= 5 and g.life <= 20), "floor children keep their own 5–10 or 20-second lifetimes")
	var number := runner.ground.size()
	runner.advance(5000000)
	_check_equal(runner.ground.size(), number, "an expired parent cannot emit twice")
	for i in 100:
		runner.spawn(HitEffects.HELMET, Vector3.ZERO, Vector3.UP, i, Vector3.ZERO)
	_check(runner.live.size() <= HitParticles.LIMIT, "sustained hits respect the particle budget")


func _test_events() -> void:
	var game := GameSystems.new()
	var view := HitEffects.new()
	root.add_child(view)
	view.set_process(false)
	view.set_physics_process(false)
	view.watch(game, 9)
	await process_frame
	_hit(game, 4, 27, 0, 73, DamageInfo.HITGROUP_CHEST, 1000000)
	_hit(game, 4, 73, 20, 0, DamageInfo.HITGROUP_HEAD, 1000001)
	game.events.flush()
	var pending := view.pending_hits()
	_check_equal(pending.size(), 2, "two pellets stay two snapshots")
	_check_equal(pending[0].effect, HitEffects.BLOOD_MED, "first pellet preserves medium damage even after fatal pellet")
	_check_equal(pending[0].health, 73.0, "first pellet preserves surviving health")
	_check_equal(pending[1].health, 0.0, "second pellet preserves lethal health")
	_check_equal(pending[1].born, 1000001, "subtick time is preserved")
	view._process(0.0)
	_check(view.pending_hits().is_empty(), "draw frame consumes event queue")
	_check_equal(view.pending_rays(), 2, "one separate wall approximation per flesh hit, no immediate floor ray")
	_check(view.particles.live.any(func(p: Dictionary) -> bool: return p.name.begins_with("impact_helmet")), "helmet and lethal flesh effects can coexist")
	view.queue_world("solidmetal", Vector3.ZERO, Vector3.UP, Vector3.DOWN, 1000002)
	_check_equal(view.pending_hits()[0].effect, "impact_metal", "world material chooses its authored root")
	view.particles.live.clear()
	view.queue_world("concrete", Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, 1000002)
	view._start(view.pending_hits()[-1], Vector3.RIGHT * 128.0)
	var wall_dust := view.particles.live.filter(func(p: Dictionary) -> bool: return p.name == "impact_concrete_child_base")
	_check(not wall_dust.is_empty(), "queued wall impacts dispatch their authored dust child")
	for p in wall_dust:
		_check(p.velocity.normalized().is_equal_approx(Vector3.RIGHT), "world-event dispatch passes the surface-normal frame through to children")
	view.particles.live.clear()
	_hit(game, 9, 27, 0, 73, DamageInfo.HITGROUP_CHEST, 1000003)
	game.events.flush()
	view._start(view.pending_hits()[-1], Vector3.ZERO)
	_check(view.particles.live.is_empty(), "own damage does not place a blood sprite across the local camera")
	for i in 200:
		view.queue_world("concrete", Vector3.ZERO, Vector3.UP, Vector3.DOWN, i)
	_check_equal(view.pending_hits().size(), HitEffects.LIMIT_PENDING, "event flood is bounded")
	view.queue_free()
	await process_frame


func _hit(game: GameSystems, victim: int, health: int, armor: int, left: int, group: int, at_usec: int) -> void:
	game.events.send(&"bullet_damage", {"victim":victim,"attacker":1,"dmg_health":health,"dmg_armor":armor,"health":left,
		"hitgroup":group,"zone":"head" if group == 1 else "chest","damage_dir_z":-1.0,"y":60.0,"killed":left <= 0}, at_usec)


func _test_flinch_dispatch() -> void:
	var game := GameSystems.new()
	var body := ReactionBody.new()
	body.model = ReactionModel.new()
	body.view = ReactionView.new(body)
	body.view.body_model = ReactionModel.new()
	body.view.body_shadow = ReactionModel.new()
	body.add_child(body.model)
	body.add_child(body.view)
	body.view.add_child(body.view.body_model)
	body.view.add_child(body.view.body_shadow)
	root.add_child(body)
	var userid := game.add_player(body)
	var effects := HitEffects.new()
	root.add_child(effects)
	effects.set_process(false)
	effects.set_physics_process(false)
	effects.watch(game, userid)
	var hit := {"effect":"", "born":123456, "at":Vector3.ZERO, "direction":Vector3.FORWARD,
		"victim":userid, "health":0.0, "killed":false, "damage":0.0,"zone":&"arm","side":&"left","bone":&""}
	effects._start(hit, Vector3.ZERO)
	var drawn := effects.drawn_models(userid)
	_check_equal(drawn.size(), 3, "flinches reach authority, visible local body and its shadow")
	for model in drawn:
		_check_equal(model.reactions, [[&"arm",&"left",Vector3.FORWARD,123456]], "the surviving/immortal hit preserves zone, side, direction and subtick on each copy")
	hit.killed = true
	effects._start(hit, Vector3.ZERO)
	_check(drawn.all(func(m: ReactionModel) -> bool: return m.reactions.size() == 1), "a fatal hit lets death/ragdoll own the pose")
	effects.queue_free()
	body.queue_free()
	await process_frame


func _test_ground_and_pool() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Hitscan.WORLD_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1024,8,1024)
	collision.shape = shape
	floor_body.add_child(collision)
	viewport.add_child(floor_body)
	floor_body.position.y = -4
	var view := HitEffects.new()
	view.max_splats = 2
	viewport.add_child(view)
	view.set_process(false)
	await physics_frame
	await physics_frame
	var ground := {"effect":"blood_impact_med_ground_decalaltb","at":Vector3(0,64,0),"born":1000000,
		"half":35.0,"life":20.0,"fade_in":0.15,"fade_out":0.1,"roll":0.0}
	view._rays.append(ground)
	await physics_frame
	await physics_frame
	if view._material(HitEffectTable.GROUND[ground.effect].material).color != null:
		_check_equal(view.splats().size(), 1, "authored downward trace reaches the world floor")
		var decal := view.splats()[0]
		_check(absf(decal.global_position.y) < 1, "projection lies on floor")
		_check_equal(decal.size.x, 70.0, "particle radius sets projected diameter")
		_check(decal.cull_mask & RigModel.LAYER == 0, "world blood never projects onto character layer")
		_check(decal.cull_mask & DroppedItemView.LAYER == 0, "nor onto what lies on the ground")
		var next_hole := BulletImpacts.next_decal_order()
		_check(decal.sorting_offset > 0.0 and next_hole - decal.sorting_offset >= BulletImpacts.DECAL_ORDER_STEP,
			"blood on the world takes its turn in the marks' order: a hole after it sorts above it")
		view._fade_splats(1100000)
		_check(decal.modulate.a > 0 and decal.modulate.a < 1, "authored fade-in")
		view._fade_splats(20000000)
		_check(decal.modulate.a > 0 and decal.modulate.a < 1, "20-second child's final 10 percent fades")
		view._fade_splats(22000000)
		_check(not decal.visible, "child expires by its own lifetime")
		var params := ground.duplicate()
		view.queue_spark(Vector3(1, 2, 3), Vector3.UP, Vector3.FORWARD, 777)
		var spark: Dictionary = view._pending[view._pending.size() - 1]
		_check(spark.effect == HitEffects.HELMET and spark.world and spark.normal == Vector3.UP and spark.born == 777,
			"a round through a dropped gun sparks as a helmet does, at the spot, outward")
		view._pending.pop_back()
		params.material = HitEffectTable.GROUND[ground.effect].material
		view.splat(Vector3(20,0,0),Vector3.UP,params)
		var reused := view.splat(Vector3(40,0,0),Vector3.UP,params)
		_check(reused == decal and view.splats().size() == 2, "oldest node recycles at pool cap")
	else:
		print("ground texture pixel/material checks: assets not extracted")
	viewport.queue_free()
	await process_frame
