class_name GrenadeTrail
extends Node3D

## A practice overlay of the actual flight, including its contact points.
## Reads tick results only; it never predicts or advances the grenade.
const KEEP_SECONDS := 8.0
const FADE_SECONDS := 2.0
const MAX_POINTS := 2048
const TRAIL_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;
uniform float opacity = 1.0;
void vertex() {
	vec4 at = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 offset;
	if (UV2.x > 0.5) {
		offset = UV * 8.0 / VIEWPORT_SIZE;
	} else {
		vec4 along = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + NORMAL, 1.0);
		vec2 direction = (along.xy / max(along.w, 0.01) - at.xy / max(at.w, 0.01)) * VIEWPORT_SIZE;
		vec2 side = vec2(-direction.y, direction.x) / max(length(direction), 0.001);
		offset = side * UV.x * 2.5 / VIEWPORT_SIZE;
	}
	at.xy += offset * max(at.w, 0.0);
	POSITION = at;
}
void fragment() {
	if (UV2.x > 0.5 && dot(UV, UV) > 1.0) { discard; }
	ALBEDO = UV2.x > 0.5 ? vec3(1.0, 0.35, 0.05) : vec3(0.25, 1.0, 0.35);
	ALPHA = opacity;
}
"""

var _grenade: GrenadeEntity
var _points := PackedVector3Array()
var _contacts := PackedVector3Array()
var _pending := PackedVector3Array()
var _pending_contacts := PackedVector3Array()
var _last_tick := -1
var _expires_usec := -1
var _dirty := false
var _path := ImmediateMesh.new()
var _tip := ImmediateMesh.new()
var _material := ShaderMaterial.new()
static var _shader: Shader


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = TRAIL_SHADER
	_material.shader = _shader
	for mesh in [_path, _tip]:
		var drawn := MeshInstance3D.new()
		drawn.mesh = mesh
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drawn.ignore_occlusion_culling = true
		# The overlay can be seen through the map, including when the camera
		# cannot see a small part of the trajectory's world-space bounds.
		drawn.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
		add_child(drawn)
	process_physics_priority = 1000 # After GameWorld's -1000 simulation.


func watch(grenade: GrenadeEntity) -> void:
	_grenade = grenade
	_points.append(grenade.position)


func _physics_process(_delta: float) -> void:
	if _grenade == null:
		return
	_sample()
	if _grenade.removed or _grenade.flight.at_rest or _grenade.phase != GrenadeEntity.Phase.FLYING:
		finish_flight()


func _sample() -> void:
	var tick := SimClock.current_tick()
	if tick == _last_tick:
		return
	_last_tick = tick
	_flush_pending()
	for touch in _grenade.flight.touches:
		_pending.append(touch.position)
		_pending_contacts.append(touch.position)
	_pending.append(_grenade.position)


func _flush_pending() -> void:
	for point in _pending:
		if _points[-1].distance_squared_to(point) > 0.0001:
			if _points.size() >= MAX_POINTS:
				_points.remove_at(0)
			_points.append(point)
			_dirty = true
	_contacts.append_array(_pending_contacts)
	_dirty = _dirty or not _pending_contacts.is_empty()
	_pending.clear()
	_pending_contacts.clear()


func finish_flight() -> void:
	if _grenade == null:
		return
	_sample()
	_flush_pending()
	_grenade = null
	_tip.clear_surfaces()
	_expires_usec = Time.get_ticks_usec() + int(KEEP_SECONDS * 1_000_000.0)
	set_physics_process(false)


func _process(_delta: float) -> void:
	if _dirty:
		_rebuild()
		_dirty = false
	if _grenade != null:
		# Completed segments stay put. Only the tip follows the same
		# interpolation as GrenadeView, so it meets the drawn grenade.
		_tip.clear_surfaces()
		var at := _grenade.previous_position.lerp(_grenade.position, DrawClock.fraction())
		if _points[-1].distance_squared_to(at) > 0.0001:
			_tip.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			_segment(_tip, _points[-1], at)
			_tip.surface_end()
	elif _expires_usec >= 0:
		var left := float(_expires_usec - Time.get_ticks_usec()) / 1_000_000.0
		if left <= 0.0:
			queue_free()
		else:
			_material.set_shader_parameter("opacity", minf(left / FADE_SECONDS, 1.0))


func _rebuild() -> void:
	_path.clear_surfaces()
	if _points.size() < 2 and _contacts.is_empty():
		return
	_path.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i in range(1, _points.size()):
		_segment(_path, _points[i - 1], _points[i])
	for point in _contacts:
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1),
			Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1)]:
			_vertex(_path, point, Vector3.UP, corner, true)
	_path.surface_end()


func _segment(mesh: ImmediateMesh, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	_vertex(mesh, from, direction, Vector2(-1, 0), false)
	_vertex(mesh, from, direction, Vector2(1, 0), false)
	_vertex(mesh, to, direction, Vector2(1, 0), false)
	_vertex(mesh, from, direction, Vector2(-1, 0), false)
	_vertex(mesh, to, direction, Vector2(1, 0), false)
	_vertex(mesh, to, direction, Vector2(-1, 0), false)


func _vertex(mesh: ImmediateMesh, at: Vector3, direction: Vector3, corner: Vector2, contact: bool) -> void:
	mesh.surface_set_normal(direction)
	mesh.surface_set_uv(corner)
	mesh.surface_set_uv2(Vector2(1.0 if contact else 0.0, 0.0))
	mesh.surface_add_vertex(at)
