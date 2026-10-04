#include "hull_mover.h"

#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/animatable_body3d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/shape3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <limits>

namespace godot {

namespace {

// A script multiplies a vector by a float by narrowing the float first.
inline Vector3 times(const Vector3 &v, double s) {
	return v * (real_t)s;
}

inline Vector3 over(const Vector3 &v, double s) {
	return v / (real_t)s;
}

inline double minf(double a, double b) {
	return a < b ? a : b;
}

inline double maxf(double a, double b) {
	return a > b ? a : b;
}

inline double clampf(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

inline double signf(double v) {
	return v < 0.0 ? -1.0 : (v > 0.0 ? 1.0 : 0.0);
}

const Vector3 UP(0, 1, 0);
const Vector3 DOWN(0, -1, 0);
const Vector3 LEFT(-1, 0, 0);
const Vector3 RIGHT(1, 0, 0);
const Vector3 FORWARD(0, 0, -1);
const Vector3 BACK(0, 0, 1);
const Vector3 ZERO(0, 0, 0);
const Vector3 ONE(1, 1, 1);

inline Vector3 inf3() {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	return Vector3(inf, inf, inf);
}

bool is_player_body(Object *p_object) {
	if (p_object == nullptr) {
		return false;
	}
	static const StringName player_body("PlayerBody");
	Ref<Script> script = p_object->get_script();
	int depth = 0;
	while (script.is_valid() && depth < 16) {
		if (script->get_global_name() == player_body) {
			return true;
		}
		script = script->get_base_script();
		depth++;
	}
	return false;
}

// PlayerBody._is_world_ground: fixed authoring geometry is world; the
// AnimatableBody3D subclass represents a moving entity instead.
bool is_world_ground(Object *p_object) {
	return Object::cast_to<StaticBody3D>(p_object) != nullptr &&
		Object::cast_to<AnimatableBody3D>(p_object) == nullptr;
}

} // namespace

// The stamp comes from the build as a bare word (native/SConstruct), an "s"
// before it so that it is one whatever it begins with.
#ifndef CSGODOT_NATIVE_SOURCES
#define CSGODOT_NATIVE_SOURCES s
#endif
#define CSGODOT_WORD_OF(word) #word
#define CSGODOT_WORD(word) CSGODOT_WORD_OF(word)

String HullMover::get_sources() const {
	return String(CSGODOT_WORD(CSGODOT_NATIVE_SOURCES)).substr(1);
}

void HullMover::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_sources"), &HullMover::get_sources);
	ClassDB::bind_method(D_METHOD("step", "body", "world", "dt", "walkable_y"), &HullMover::step);
	ClassDB::bind_method(D_METHOD("get_casts"), &HullMover::get_casts);
	ClassDB::bind_method(D_METHOD("get_hits"), &HullMover::get_hits);
}

// --- The body, in and out ---------------------------------------------------

void HullMover::read_config(Object *p_config) {
	static const StringName gravity("gravity"), accelerate("accelerate"), air_accelerate("air_accelerate"),
			friction("friction"), stop_speed("stop_speed"), air_max_wishspeed("air_max_wishspeed"),
			max_speed("max_speed"), jump_impulse("jump_impulse"), cs2_jump("cs2_jump"),
			tick_rate_independent_jump("tick_rate_independent_jump"), non_jump_velocity("non_jump_velocity"),
			max_velocity("max_velocity"), auto_bunnyhop("auto_bunnyhop"),
			enable_bunnyhopping("enable_bunnyhopping"), bunnyhop_speed_cap("bunnyhop_speed_cap"),
			hull_width("hull_width"), stand_height("stand_height"), duck_height("duck_height"),
			duck_time("duck_time"), step_height("step_height"), step_move_velocity_min("step_move_velocity_min"),
			project_wish_dir_on_ground("project_wish_dir_on_ground"), stay_on_ground("stay_on_ground"),
			trace_epsilon("trace_epsilon"), source_deadstrafe("source_deadstrafe"),
			deadstrafe_friction("deadstrafe_friction"),
			deadstrafe_max_vertical_speed("deadstrafe_max_vertical_speed");
	cfg.gravity = p_config->get(gravity);
	cfg.accelerate = p_config->get(accelerate);
	cfg.air_accelerate = p_config->get(air_accelerate);
	cfg.friction = p_config->get(friction);
	cfg.stop_speed = p_config->get(stop_speed);
	cfg.air_max_wishspeed = p_config->get(air_max_wishspeed);
	cfg.max_speed = p_config->get(max_speed);
	cfg.jump_impulse = p_config->get(jump_impulse);
	cfg.cs2_jump = p_config->get(cs2_jump);
	cfg.tick_rate_independent_jump = p_config->get(tick_rate_independent_jump);
	cfg.non_jump_velocity = p_config->get(non_jump_velocity);
	cfg.max_velocity = p_config->get(max_velocity);
	cfg.auto_bunnyhop = p_config->get(auto_bunnyhop);
	cfg.enable_bunnyhopping = p_config->get(enable_bunnyhopping);
	cfg.bunnyhop_speed_cap = p_config->get(bunnyhop_speed_cap);
	cfg.hull_width = p_config->get(hull_width);
	cfg.stand_height = p_config->get(stand_height);
	cfg.duck_height = p_config->get(duck_height);
	cfg.duck_time = p_config->get(duck_time);
	cfg.step_height = p_config->get(step_height);
	cfg.step_move_velocity_min = p_config->get(step_move_velocity_min);
	cfg.project_wish_dir_on_ground = p_config->get(project_wish_dir_on_ground);
	cfg.stay_on_ground = p_config->get(stay_on_ground);
	cfg.trace_epsilon = p_config->get(trace_epsilon);
	cfg.source_deadstrafe = p_config->get(source_deadstrafe);
	cfg.deadstrafe_friction = p_config->get(deadstrafe_friction);
	cfg.deadstrafe_max_vertical_speed = p_config->get(deadstrafe_max_vertical_speed);
}

namespace names {
const StringName &global_position() { static const StringName n("global_position"); return n; }
const StringName &velocity() { static const StringName n("velocity"); return n; }
const StringName &move_acceleration() { static const StringName n("_move_acceleration"); return n; }
const StringName &deferred_velocity() { static const StringName n("_deferred_velocity"); return n; }
const StringName &friction_overshoot() { static const StringName n("_friction_overshoot"); return n; }
const StringName &on_ground() { static const StringName n("on_ground"); return n; }
const StringName &ground_normal() { static const StringName n("ground_normal"); return n; }
const StringName &ground_is_world() { static const StringName n("ground_is_world"); return n; }
const StringName &is_ducked() { static const StringName n("is_ducked"); return n; }
const StringName &duck_progress() { static const StringName n("duck_progress"); return n; }
const StringName &wish_dir() { static const StringName n("wish_dir"); return n; }
const StringName &wish_speed() { static const StringName n("wish_speed"); return n; }
const StringName &acceleration_speed() { static const StringName n("acceleration_speed"); return n; }
const StringName &movement_speed_limit() { static const StringName n("movement_speed_limit"); return n; }
const StringName &walk_acceleration_limit() { static const StringName n("walk_acceleration_limit"); return n; }
const StringName &wants_jump() { static const StringName n("wants_jump"); return n; }
const StringName &wants_duck() { static const StringName n("wants_duck"); return n; }
const StringName &jump_held() { static const StringName n("_jump_held_last_tick"); return n; }
const StringName &jumped() { static const StringName n("_jumped"); return n; }
const StringName &looked_from() { static const StringName n("_looked_from"); return n; }
const StringName &looked_with() { static const StringName n("_looked_with"); return n; }
const StringName &hull_height() { static const StringName n("_hull_height"); return n; }
const StringName &floor_at() { static const StringName n("_floor_at"); return n; }
const StringName &floor_with() { static const StringName n("_floor_with"); return n; }
const StringName &floor_normal() { static const StringName n("_floor_normal"); return n; }
const StringName &floor_is_world() { static const StringName n("_floor_is_world"); return n; }
const StringName &quadrant_is_world() { static const StringName n("_quadrant_is_world"); return n; }
const StringName &recovery_direction() { static const StringName n("_native_recovery_direction"); return n; }
const StringName &last_recovery() { static const StringName n("_last_native_trace_recovery"); return n; }
const StringName &collision_mask() { static const StringName n("collision_mask"); return n; }
const StringName &safe_margin() { static const StringName n("safe_margin"); return n; }
const StringName &config() { static const StringName n("config"); return n; }
const StringName &traces() { static const StringName n("traces"); return n; }
const StringName &set_hull() { static const StringName n("_set_hull"); return n; }
const StringName &quadrants() { static const StringName n("_ground_normal_in_quadrants_at"); return n; }
const StringName &shape_cast_box() { static const StringName n("shape_cast_box"); return n; }
const StringName &source_id() { static const StringName n("source_id"); return n; }
const StringName &source_shape() { static const StringName n("source_shape"); return n; }
} // namespace names

void HullMover::read_body() {
	position = body->get(names::global_position());
	velocity = body->get(names::velocity());
	move_acceleration = body->get(names::move_acceleration());
	deferred_velocity = body->get(names::deferred_velocity());
	friction_overshoot = body->get(names::friction_overshoot());
	on_ground = body->get(names::on_ground());
	ground_normal = body->get(names::ground_normal());
	ground_is_world = body->get(names::ground_is_world());
	is_ducked = body->get(names::is_ducked());
	duck_progress = body->get(names::duck_progress());
	wish_dir = body->get(names::wish_dir());
	wish_speed = body->get(names::wish_speed());
	acceleration_speed = body->get(names::acceleration_speed());
	movement_speed_limit = body->get(names::movement_speed_limit());
	walk_acceleration_limit = body->get(names::walk_acceleration_limit());
	wants_jump = body->get(names::wants_jump());
	wants_duck = body->get(names::wants_duck());
	jump_held_last_tick = body->get(names::jump_held());
	jumped = body->get(names::jumped());
	looked_from = body->get(names::looked_from());
	looked_with = body->get(names::looked_with());
	hull_height = body->get(names::hull_height());
	floor_at = body->get(names::floor_at());
	floor_with = body->get(names::floor_with());
	floor_normal = body->get(names::floor_normal());
	floor_is_world = body->get(names::floor_is_world());
	quadrant_is_world = body->get(names::quadrant_is_world());
	recovery_direction = body->get(names::recovery_direction());
	last_trace_recovery = body->get(names::last_recovery());
	collision_mask = body->get(names::collision_mask());
	// PlayerBody._prepare_motion_query: the margin is kept by the query, whose
	// floats are single.
	const double safe_margin = body->get(names::safe_margin());
	query_margin = (double)(real_t)maxf(safe_margin, NATIVE_QUERY_MARGIN);
}

void HullMover::write_body(const Vector3 &p_position_before) {
	if (position != p_position_before) {
		body->set(names::global_position(), position);
	}
	body->set(names::velocity(), velocity);
	body->set(names::move_acceleration(), move_acceleration);
	body->set(names::deferred_velocity(), deferred_velocity);
	body->set(names::friction_overshoot(), friction_overshoot);
	body->set(names::on_ground(), on_ground);
	body->set(names::ground_normal(), ground_normal);
	body->set(names::ground_is_world(), ground_is_world);
	body->set(names::is_ducked(), is_ducked);
	body->set(names::duck_progress(), duck_progress);
	body->set(names::jumped(), jumped);
	body->set(names::looked_from(), looked_from);
	body->set(names::looked_with(), looked_with);
	body->set(names::floor_at(), floor_at);
	body->set(names::floor_with(), floor_with);
	body->set(names::floor_normal(), floor_normal);
	body->set(names::floor_is_world(), floor_is_world);
	body->set(names::quadrant_is_world(), quadrant_is_world);
	body->set(names::recovery_direction(), recovery_direction);
	body->set(names::last_recovery(), last_trace_recovery);
	if (casts != 0) {
		const int64_t traces = body->get(names::traces());
		body->set(names::traces(), traces + casts);
	}
}

bool HullMover::step(Object *p_body, Object *p_world, double p_dt, double p_walkable_y) {
	casts = 0;
	hits = 0;
	if (p_body == nullptr || p_world == nullptr) {
		return false;
	}
	// A call by name to what is not there says nothing and answers nothing,
	// which would read as a sweep that met nothing: asked once of a world.
	const uint64_t world_id = p_world->get_instance_id();
	if (world_id != world_known) {
		if (!p_world->has_method(names::shape_cast_box())) {
			return false;
		}
		world_known = world_id;
	}
	body = p_body;
	world = p_world;
	Object *config = body->get(names::config());
	if (config == nullptr) {
		body = nullptr;
		world = nullptr;
		return false;
	}
	read_config(config);
	cfg.walkable_y = p_walkable_y;
	read_body();
	// What the node was told last: its place is written when it has changed
	// from that (a hull resized writes it sooner, set_hull).
	written = position;
	simulate_step(p_dt);
	write_body(written);
	body = nullptr;
	world = nullptr;
	return true;
}

// --- MovementSolver ---------------------------------------------------------

bool HullMover::is_walkable(const Vector3 &normal) const {
	return (double)normal.y >= cfg.walkable_y;
}

Vector3 HullMover::clip_velocity(const Vector3 &p_velocity, const Vector3 &normal, double overbounce) {
	const double backoff = (double)p_velocity.dot(normal) * overbounce;
	Vector3 out = p_velocity - times(normal, backoff);
	const double adjust = out.dot(normal);
	if (adjust < 0.0) {
		out -= times(normal, adjust);
	}
	return out;
}

Vector3 HullMover::check_velocity(const Vector3 &p_velocity) const {
	const double limit = cfg.max_velocity;
	return Vector3(
			(real_t)clampf(p_velocity.x, -limit, limit),
			(real_t)clampf(p_velocity.y, -limit, limit),
			(real_t)clampf(p_velocity.z, -limit, limit));
}

Vector3 HullMover::apply_friction(const Vector3 &p_velocity, bool p_on_ground, double surface_friction, double dt) const {
	const double speed = p_velocity.length();
	if (speed < 0.1) {
		return p_velocity;
	}
	double drop = 0.0;
	if (p_on_ground) {
		const double f = cfg.friction * surface_friction;
		const double control = speed < cfg.stop_speed ? cfg.stop_speed : speed;
		drop = control * f * dt;
	}
	const double new_speed = maxf(speed - drop, 0.0);
	return times(p_velocity, new_speed / speed);
}

// MovementSolver.quantized_speed: this encoder's grid is offset, with an
// exact-zero encoding, rather than an ordinary 1/32-unit rounding.
double HullMover::quantized_speed(double speed) {
	if (speed == 0.0) {
		return 0.0;
	}
	const double value = clampf(speed, -16384.0, 16384.0);
	const double shifted = (real_t)(value + 16384.0);
	const int64_t code = (int64_t)(shifted * (1048575.0 / 32768.0) + 0.5);
	return (real_t)(code * (1.0 / 1048575.0) * 32768.0 - 16384.0);
}

double HullMover::friction_rate(double speed, double surface_friction) const {
	const double control_speed = quantized_speed(speed);
	if (control_speed < 0.1) {
		return 0.0;
	}
	return maxf(control_speed, cfg.stop_speed) * cfg.friction * surface_friction;
}

double HullMover::ground_acceleration_rate(const Vector3 &p_velocity, const Vector3 &p_wish_dir, double p_wish_speed, double accel, double surface_friction, double dt, double accel_from, double p_friction_overshoot) {
	if (dt <= 0.0) {
		return 0.0;
	}
	const double available = p_wish_speed - p_velocity.dot(p_wish_dir);
	if (available <= 0.0) {
		return 0.0;
	}
	const double scale = accel_from > 0.0 ? accel_from : p_wish_speed;
	return minf(maxf(scale * accel * surface_friction - p_friction_overshoot / dt, 0.0), available / dt);
}

// MovementSolver.accelerate: accel_from is PlayerBody.acceleration_speed.
Vector3 HullMover::accelerate(const Vector3 &p_velocity, const Vector3 &p_wish_dir, double p_wish_speed, double accel, double surface_friction, double dt, double accel_from) {
	const double current_speed = p_velocity.dot(p_wish_dir);
	const double add_speed = p_wish_speed - current_speed;
	if (add_speed <= 0.0) {
		return p_velocity;
	}
	const double scale = accel_from > 0.0 ? accel_from : p_wish_speed;
	double accel_speed = accel * dt * scale * surface_friction;
	if (accel_speed > add_speed) {
		accel_speed = add_speed;
	}
	return p_velocity + times(p_wish_dir, accel_speed);
}

Vector3 HullMover::air_accelerate(const Vector3 &p_velocity, const Vector3 &p_wish_dir, double p_wish_speed, double accel, double surface_friction, double dt) const {
	const double wish_spd = minf(p_wish_speed, cfg.air_max_wishspeed);
	const double current_speed = p_velocity.dot(p_wish_dir);
	const double add_speed = wish_spd - current_speed;
	if (add_speed <= 0.0) {
		return p_velocity;
	}
	double accel_speed = accel * p_wish_speed * dt * surface_friction;
	if (accel_speed > add_speed) {
		accel_speed = add_speed;
	}
	return p_velocity + times(p_wish_dir, accel_speed);
}

double HullMover::surface_friction_for(double vertical_velocity, bool p_on_ground) const {
	if (p_on_ground || !cfg.source_deadstrafe) {
		return 1.0;
	}
	if (vertical_velocity > 0.0 && vertical_velocity < cfg.deadstrafe_max_vertical_speed) {
		return cfg.deadstrafe_friction;
	}
	return 1.0;
}

Vector3 HullMover::clamp_bunnyhop(const Vector3 &p_velocity) const {
	if (cfg.enable_bunnyhopping) {
		return p_velocity;
	}
	const double cap = cfg.max_speed * cfg.bunnyhop_speed_cap;
	Vector3 horizontal(p_velocity.x, 0.0, p_velocity.z);
	const double speed = horizontal.length();
	if (speed <= cap) {
		return p_velocity;
	}
	horizontal = times(horizontal, cap / speed);
	return Vector3(horizontal.x, p_velocity.y, horizontal.z);
}

// --- PlayerBody -------------------------------------------------------------

void HullMover::simulate_step(double dt) {
	move_acceleration = ZERO;
	deferred_velocity = ZERO;
	friction_overshoot = 0.0;
	if (!ground_known()) {
		categorize_position();
	}
	update_duck(dt);

	const double surface_friction = surface_friction_for(velocity.y, on_ground);

	velocity = check_velocity(velocity);

	try_jump(dt);

	if (on_ground) {
		velocity.y = 0.0;
		apply_ground_friction(surface_friction, dt);
	}

	if (on_ground) {
		walk_move(surface_friction, dt);
	} else {
		air_move(surface_friction, dt);
	}

	categorize_position();

	if (on_ground) {
		velocity.y = 0.0;
		move_acceleration.y = 0.0;
		deferred_velocity.y = 0.0;
	}

	velocity = check_velocity(velocity);
}

void HullMover::apply_ground_friction(double surface_friction, double dt) {
	const double speed = velocity.length();
	const double rate = friction_rate(speed, surface_friction);
	if (speed <= 0.0 || dt <= 0.0 || rate <= 0.0) {
		return;
	}
	const double drop = rate * dt;
	friction_overshoot = maxf(drop - speed, 0.0);
	move_acceleration -= times(over(velocity, speed), minf(rate, speed / dt));
	velocity = times(velocity, maxf(speed - drop, 0.0) / speed);
}

void HullMover::defer_acceleration(double dt) {
	const Vector3 half = times(times(move_acceleration, dt), 0.5);
	velocity -= half;
	deferred_velocity += half;
}

void HullMover::stop_movement() {
	velocity = ZERO;
	move_acceleration = ZERO;
	deferred_velocity = ZERO;
}

bool HullMover::ground_known() const {
	return position == looked_from && hull_height == looked_with && (double)velocity.y <= cfg.non_jump_velocity;
}

void HullMover::update_duck(double dt) {
	const double rate = 1.0 / maxf(cfg.duck_time, 0.0001);

	if (wants_duck) {
		duck_progress = minf(duck_progress + rate * dt, 1.0);
		if (!is_ducked && (!on_ground || duck_progress >= 1.0)) {
			finish_duck();
		}
		return;
	}

	if (is_ducked) {
		if (!can_unduck()) {
			// Still under something. Stay ducked rather than clipping into it.
			duck_progress = 1.0;
			return;
		}
		finish_unduck();
	}

	duck_progress = maxf(duck_progress - rate * dt, 0.0);
}

double HullMover::duck_height_delta() const {
	return cfg.stand_height - cfg.duck_height;
}

void HullMover::finish_duck() {
	const double delta = duck_height_delta();
	const bool airborne = !on_ground;

	set_hull(cfg.duck_height);

	if (airborne) {
		trace(times(UP, delta));
		duck_progress = 1.0;
	}

	is_ducked = true;
}

void HullMover::finish_unduck() {
	const double delta = duck_height_delta();
	if (!on_ground) {
		trace(times(DOWN, delta));
		duck_progress = 0.0;
	}
	set_hull(cfg.stand_height);
	is_ducked = false;
}

bool HullMover::can_unduck() {
	const double delta = duck_height_delta();
	const Vector3 direction = on_ground ? UP : DOWN;
	return !trace(times(direction, delta), true).met;
}

void HullMover::set_hull(double height) {
	// The script resizes the hull where the body stands at that moment, and
	// tells the bridge, which reads the node's place: so the node is told
	// where the body is first.
	if (position != written) {
		body->set(names::global_position(), position);
		written = position;
	}
	body->call(names::set_hull(), height);
	hull_height = body->get(names::hull_height());
}

void HullMover::try_jump(double dt) {
	if (!wants_jump || !on_ground) {
		return;
	}
	if (!cfg.auto_bunnyhop && jump_held_last_tick) {
		return;
	}
	velocity = clamp_bunnyhop(velocity);
	velocity.y = (real_t)cfg.jump_impulse;
	jumped = true;
	if (cfg.cs2_jump) {
		velocity.y = (real_t)((double)velocity.y - cfg.gravity * 0.5 / 128.0);
	} else if (!cfg.tick_rate_independent_jump) {
		// Source 1 compatibility: the jump overwrote its leading gravity.
		velocity.y = (real_t)((double)velocity.y + cfg.gravity * 0.5 * dt);
	}
	on_ground = false;
	ground_is_world = false;
}

void HullMover::walk_move(double surface_friction, double dt) {
	Vector3 dir = wish_dir;
	if (cfg.project_wish_dir_on_ground && ground_normal != UP) {
		dir = clip_velocity(dir, ground_normal);
		if (dir.length_squared() > 0.0) {
			dir = dir.normalized();
		}
	}

	double accel = cfg.accelerate;
	if (walk_acceleration_limit > 0.0) {
		const double threshold = walk_acceleration_limit - 5.0;
		const double positive_speed = maxf(velocity.dot(dir), 0.0);
		if (positive_speed > threshold) {
			accel *= minf(maxf(1.0 - (positive_speed - threshold) / (walk_acceleration_limit - threshold), 0.0), 1.0);
		}
	}
	const double rate = ground_acceleration_rate(velocity, dir, wish_speed, accel, surface_friction, dt, acceleration_speed, friction_overshoot);
	move_acceleration += times(dir, rate);
	velocity += times(dir, rate * dt);
	velocity.y = 0.0;
	move_acceleration.y = 0.0;
	deferred_velocity.y = 0.0;
	const double speed = velocity.length();
	if (speed > movement_speed_limit) {
		const Vector3 before_cap = velocity;
		velocity = times(velocity, movement_speed_limit / speed);
		if (dt > 0.0) {
			move_acceleration += over(velocity - before_cap, dt);
		}
	}
	defer_acceleration(dt);
	const Vector3 predicted = velocity + times(move_acceleration, 1.0 / 64.0 - dt * 0.5);
	if (predicted.length() < 1.0) {
		stop_movement();
		return;
	}
	const Vector3 start = position;
	const Vector3 midpoint = velocity;
	if (!step_move(dt)) {
		const double midpoint_speed = midpoint.length();
		if (midpoint_speed > 0.0 && midpoint_speed < cfg.step_move_velocity_min && wish_dir != ZERO) {
			// The retry repeats only the raised path. Any hard-stop clearing
			// of acceleration and deferred velocity remains in effect.
			try_step(dt, start, times(midpoint, cfg.step_move_velocity_min / midpoint_speed));
		}
	}
	velocity += deferred_velocity;
	// PlayerBody._stay_on_ground, over native collision.
	if (cfg.stay_on_ground) {
		stay_on_native_ground();
	}
}

void HullMover::stay_on_native_ground() {
	if (floor_at == position && floor_with == hull_height) {
		return;
	}
	const Vector3 start = position;
	const Vector3 lift = times(UP, STAY_ON_GROUND_LIFT);
	const Vector3 motion = times(DOWN, STAY_ON_GROUND_LIFT + cfg.step_height);
	const Hit hit = cast_from(lift, motion);
	if (hit.empty) {
		// Nothing to stand on within a step.
		return;
	}
	Vector3 normal = hit.normal;
	bool world_ground = is_world_ground(hit.collider);
	Vector3 landing;
	if (normal.is_zero_approx()) {
		// Something over its head where it would start: from where it
		// stands, then, clear of what it stands in first.
		const Trace collision = trace(times(DOWN, cfg.step_height), true);
		if (!collision.met || !is_walkable(collision.normal)) {
			position = start + last_trace_recovery;
			return;
		}
		normal = collision.normal;
		world_ground = collision.is_world;
		landing = start + collision.travel;
	} else if (!is_walkable(normal)) {
		return;
	} else {
		landing = start + lift + times(motion, hit.fraction) + hit.offset;
	}
	position = landing;
	floor_at = position;
	floor_with = hull_height;
	floor_normal = normal;
	floor_is_world = world_ground;
}

void HullMover::air_move(double surface_friction, double dt) {
	const double available = minf(wish_speed, cfg.air_max_wishspeed) - velocity.dot(wish_dir);
	if (available > 0.0 && dt > 0.0) {
		const double half = wish_speed * cfg.air_accelerate * surface_friction * dt * 0.5;
		const double before = minf(available, half);
		const double after = minf(available - before, half);
		velocity += times(wish_dir, before);
		deferred_velocity += times(wish_dir, after);
	}
	velocity.y = (real_t)((double)velocity.y - cfg.gravity * dt);
	move_acceleration.y = (real_t)((double)move_acceleration.y - cfg.gravity);
	defer_acceleration(dt);
	try_player_move(dt);
	velocity += deferred_velocity;
}

bool HullMover::step_move(double dt) {
	const Vector3 start_position = position;
	const Vector3 start_velocity = velocity;

	if (!try_player_move(dt)) {
		return true;
	}
	return try_step(dt, start_position, start_velocity);
}

bool HullMover::try_step(double dt, const Vector3 &start_position, const Vector3 &start_velocity) {
	const Vector3 flat_position = position;
	const Vector3 flat_velocity = velocity;

	// PlayerBody._horizontal_distance: the differences are taken as script
	// floats and kept by a Vector2 as single ones.
	auto horizontal_distance = [](const Vector3 &a, const Vector3 &b) -> double {
		const real_t x = (real_t)((double)b.x - (double)a.x);
		const real_t z = (real_t)((double)b.z - (double)a.z);
		return (double)(real_t)std::sqrt(x * x + z * z);
	};

	const double flat_distance = horizontal_distance(start_position, flat_position);

	position = start_position;
	velocity = start_velocity;

	const double step = cfg.step_height + STAY_ON_GROUND_MIN_DELTA;
	trace(times(UP, step));
	try_player_move(dt);
	const Trace landing = trace(times(DOWN, step));

	const double step_distance = horizontal_distance(start_position, position);

	const bool landed_walkable = landing.met && (landing.travel - landing.recovery).dot(DOWN) > 0.0 && is_walkable(landing.normal);

	if (step_distance > flat_distance && landed_walkable) {
		velocity.y = flat_velocity.y;
		// The sweep down put it on this floor: nothing more to find.
		floor_at = position;
		floor_with = hull_height;
		floor_normal = landing.normal;
		floor_is_world = landing.is_world;
		return true;
	}
	position = flat_position;
	velocity = flat_velocity;
	// Source suppresses another retry after a valid landing even when the
	// flat candidate covered more horizontal ground.
	return landed_walkable;
}

bool HullMover::try_player_move(double dt) {
	const Vector3 primal_velocity = velocity;
	Vector3 original_velocity = velocity;
	Vector3 planes[MAX_CLIP_PLANES + 1];
	int plane_count = 0;
	double time_left = dt;
	double all_fraction = 0.0;
	bool met_something = false;

	for (int bump = 0; bump < MAX_BUMPS; bump++) {
		if (velocity.length_squared() == 0.0) {
			break;
		}

		const Vector3 motion = times(velocity, time_left);
		const Trace collision = trace(motion);

		if (!collision.met) {
			all_fraction += 1.0;
			break;
		}
		met_something = true;
		if (collision.travel == ZERO && collision.normal == ZERO) {
			break;
		}

		const double motion_length = motion.length();
		double fraction = 0.0;
		if (motion_length > 0.0) {
			fraction = clampf((double)(collision.travel - collision.recovery).length() / motion_length, 0.0, 1.0);
		}
		all_fraction += fraction;

		if (fraction > 0.0) {
			original_velocity = velocity;
			plane_count = 0;
		}

		time_left -= time_left * fraction;

		if (plane_count >= MAX_CLIP_PLANES) {
			stop_movement();
			break;
		}

		const Vector3 normal = collision.normal;
		planes[plane_count++] = normal;
		if (cfg.trace_epsilon != 0.0) {
			position += times(normal, cfg.trace_epsilon);
		}

		if (plane_count == 1 && !on_ground) {
			velocity = clip_velocity(original_velocity, planes[0]);
			original_velocity = velocity;
		} else {
			bool resolved = false;
			for (int i = 0; i < plane_count; i++) {
				const Vector3 candidate = clip_velocity(original_velocity, planes[i]);
				bool blocked = false;
				for (int j = 0; j < plane_count; j++) {
					if (j == i) {
						continue;
					}
					if ((double)candidate.dot(planes[j]) < 0.0) {
						blocked = true;
						break;
					}
				}
				if (!blocked) {
					velocity = candidate;
					resolved = true;
					break;
				}
			}

			if (!resolved) {
				if (plane_count != 2) {
					stop_movement();
					break;
				}
				Vector3 crease = planes[0].cross(planes[1]);
				if (crease.length_squared() == 0.0) {
					stop_movement();
					break;
				}
				crease = crease.normalized();
				velocity = times(crease, crease.dot(velocity));
			}

			if ((double)velocity.dot(primal_velocity) <= 0.0) {
				stop_movement();
				break;
			}
		}
	}

	if (all_fraction == 0.0 && met_something) {
		stop_movement();
	}
	return met_something;
}

void HullMover::categorize_position() {
	if ((double)velocity.y > cfg.non_jump_velocity) {
		on_ground = false;
		ground_is_world = false;
		ground_normal = UP;
		looked_from = inf3();
		floor_at = inf3();
		return;
	}
	if (floor_at == position && floor_with == hull_height) {
		on_ground = true;
		ground_normal = floor_normal;
		ground_is_world = floor_is_world;
		looked_from = position;
		looked_with = hull_height;
		floor_at = inf3();
		return;
	}
	floor_at = inf3();

	const Trace collision = trace(times(DOWN, GROUND_TRACE_DISTANCE), true);
	Vector3 normal = ZERO;
	bool world_ground = collision.met && collision.is_world;
	Vector3 travel = ZERO;
	if (collision.met) {
		normal = collision.normal;
		travel = collision.travel;
	}

	if (normal == ZERO || !is_walkable(normal)) {
		normal = ground_normal_in_quadrants();
		world_ground = quadrant_is_world;
		if (normal == ZERO) {
			on_ground = false;
			ground_is_world = false;
			ground_normal = UP;
			looked_from = position;
			looked_with = hull_height;
			return;
		}
	}

	on_ground = true;
	ground_normal = normal;
	ground_is_world = world_ground;
	if (collision.met) {
		position += travel;
	} else {
		trace(times(DOWN, GROUND_TRACE_DISTANCE));
	}
	looked_from = position;
	looked_with = hull_height;
}

Vector3 HullMover::hull_middle() const {
	// The hull's shape stands half its height over the body's feet
	// (PlayerBody._set_hull), kept as a single float.
	return Vector3(position.x, (real_t)(hull_height * 0.5) + position.y, position.z);
}

HullMover::Trace HullMover::trace(const Vector3 &motion, bool test_only) {
	last_trace_recovery = ZERO;
	query_origin = hull_middle();
	query_motion = motion;
	Hit hit = cast_hull();
	Vector3 recovery = ZERO;
	if (!hit.empty && hit.normal.is_zero_approx()) {
		Node3D *other = Object::cast_to<CharacterBody3D>(hit.collider);
		if (other != nullptr) {
			const Vector3 away = position - other->get_global_position();
			if (std::fabs((double)away.x) > std::fabs((double)away.z)) {
				recovery_direction = times(RIGHT, signf(away.x));
			} else if (std::fabs((double)away.z) > 0.000001) {
				recovery_direction = times(BACK, signf(away.z));
			}
		}
		if (!recovery_blocked_by_player(hit)) {
			recovery = recover_trace_start();
		}
		if (!recovery.is_zero_approx()) {
			query_origin += recovery;
			hit = cast_hull();
		}
	}
	if (!hit.empty && !hit.normal.is_zero_approx()) {
		if (!is_walkable(hit.normal)) {
			recovery_direction = hit.normal;
		}
	}
	recovery += hit.offset;
	last_trace_recovery = recovery;
	const Vector3 travel = recovery + times(motion, hit.fraction);
	if (!test_only) {
		position += travel;
	}
	Trace result;
	result.met = !hit.empty;
	result.travel = travel;
	result.normal = hit.normal;
	result.recovery = recovery;
	result.is_world = is_world_ground(hit.collider);
	return result;
}

HullMover::Hit HullMover::cast_from(const Vector3 &from, const Vector3 &motion) {
	query_origin = hull_middle() + from;
	query_motion = motion;
	return cast_hull();
}

// Box3DQueries.shape_cast_prepared over _native_cast, for an upright box, and
// _mapped for what it met.
HullMover::Hit HullMover::cast_hull() {
	casts++;
	Hit result;
	const Vector3 motion = query_motion;
	const double length = motion.length();
	const Vector3 direction = length > 0.0 ? over(motion, length) : ZERO;
	const Vector3 swept = length > 0.0 ? times(direction, length + CAST_REACH) : motion;

	// _native_cast: bodies, not areas.
	const int64_t mask = collision_mask & ~HITBOX_LAYER;
	const Vector3 from = times(query_origin, SCALE);
	const Vector3 to = times(query_origin + swept, SCALE);
	const Vector3 size((real_t)cfg.hull_width, (real_t)hull_height, (real_t)cfg.hull_width);
	const double inset = minf(CAST_INSET, minf(size.x, minf(size.y, size.z)) * 0.25);
	const Vector3 native_size = times(size - times(ONE, 2.0 * inset), SCALE);
	const Variant answer = world->call(names::shape_cast_box(), from, to, native_size, mask, QUERY_LAYER);
	if (answer.get_type() != Variant::DICTIONARY) {
		return result;
	}
	const Dictionary hit = answer;
	if (!bool(hit.get("hit", false))) {
		return result;
	}

	// _mapped.
	const Variant met = hit.get("collider", Variant());
	Object *native = met.get_type() == Variant::OBJECT ? met.get_validated_object() : nullptr;
	if (native == nullptr || Object::cast_to<Node3D>(native) == nullptr) {
		return result;
	}
	const int64_t id = native->get_meta(names::source_id(), 0);
	Object *found = id != 0 ? ObjectDB::get_instance((uint64_t)id) : nullptr;
	CollisionObject3D *source = Object::cast_to<CollisionObject3D>(found);
	if (source == nullptr) {
		return result;
	}
	Vector3 normal = hit.get("normal", ZERO);
	if (!normal.is_zero_approx()) {
		normal = normal.normalized();
	}

	const double clearance = maxf(query_margin, CAST_CLEARANCE) + inset;
	const double native_fraction = hit.get("fraction", 0.0);
	const double contact = length > 0.0 ? native_fraction * (length + CAST_REACH) : 0.0;
	double stop = contact;
	Vector3 offset = ZERO;
	if ((double)normal.length_squared() > 0.5) {
		const double approach = std::fabs((double)direction.dot(normal));
		double back = minf(minf(clearance / maxf(approach, 0.000001), CAST_BACK_OFF), contact);
		stop = contact - back;
		if (stop > length) {
			// The whole motion fits; what lies past its end is its back-off.
			stop = length;
			back = contact - length;
		}
		const double missing = clearance - back * approach;
		if (missing > 0.001) {
			offset = times(normal, missing);
		}
	} else {
		stop = 0.0;
	}
	if (stop >= length && length > 0.0 && offset == ZERO) {
		return result;
	}
	hits++;
	result.empty = false;
	result.fraction = length > 0.0 ? stop / length : 0.0;
	result.normal = normal;
	result.offset = offset;
	result.collider = source;
	result.shape = (int)(int64_t)native->get_meta(names::source_shape(), 0);
	return result;
}

bool HullMover::recovery_blocked_by_player(const Hit &hit) const {
	CollisionObject3D *other = Object::cast_to<CollisionObject3D>(hit.collider);
	const int index = hit.shape;
	if (other == nullptr || !is_player_body(other) || index < 0) {
		return false;
	}
	const PackedInt32Array owners = other->get_shape_owners();
	if (owners.size() != 1) {
		return false;
	}
	const uint32_t shape_owner = (uint32_t)owners[0];
	if (other->is_shape_owner_disabled(shape_owner) || other->shape_owner_get_shape_count(shape_owner) != 1 ||
			other->shape_owner_get_shape_index(shape_owner, 0) != index) {
		return false;
	}
	Ref<BoxShape3D> other_shape = other->shape_owner_get_shape(shape_owner, 0);
	if (other_shape.is_null()) {
		return false;
	}
	const Transform3D at(Basis(), query_origin);
	const Transform3D other_at = other->get_global_transform() * other->shape_owner_get_transform(shape_owner);
	const Vector3 own_scale = at.basis.get_scale();
	const Vector3 other_scale = other_at.basis.get_scale();
	if (at.basis != Basis::from_scale(own_scale) || other_at.basis != Basis::from_scale(other_scale) ||
			minf(own_scale.x, minf(own_scale.y, own_scale.z)) <= 0.0 ||
			minf(other_scale.x, minf(other_scale.y, other_scale.z)) <= 0.0) {
		return false;
	}
	const Vector3 size((real_t)cfg.hull_width, (real_t)hull_height, (real_t)cfg.hull_width);
	const Vector3 half_extents = times(size * own_scale + other_shape->get_size() * other_scale, 0.5);
	const Vector3 overlap = half_extents - (at.origin - other_at.origin).abs();
	const Vector3 reach = times(recovery_direction.abs().max(ONE), NATIVE_RECOVERY_REACH) + times(ONE, NATIVE_RECOVERY_PADDING);
	return overlap.x > reach.x && overlap.y > reach.y && overlap.z > reach.z;
}

Vector3 HullMover::recover_trace_start() {
	const Vector3 original = query_origin;
	// The script's list: the six, the last plane met taken out and put first,
	// then up and each way level.
	Vector3 directions[6 + 1 + 8];
	int count = 0;
	const Vector3 six[6] = { UP, LEFT, RIGHT, FORWARD, BACK, DOWN };
	directions[count++] = recovery_direction;
	bool taken = false;
	for (int i = 0; i < 6; i++) {
		// Array.erase takes out the first that equals it.
		if (!taken && six[i] == recovery_direction) {
			taken = true;
			continue;
		}
		directions[count++] = six[i];
	}
	const Vector3 level[8] = {
		LEFT, RIGHT, FORWARD, BACK,
		Vector3(-1.0, 0.0, -1.0), Vector3(-1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0),
	};
	for (int i = 0; i < 8; i++) {
		directions[count++] = UP + level[i];
	}
	auto blocked = [](const Hit &hit) -> bool {
		return !hit.empty && hit.normal.is_zero_approx();
	};
	for (int d = 0; d < count; d++) {
		const Vector3 direction = directions[d];
		const Vector3 offset = times(direction, NATIVE_RECOVERY_REACH);
		query_origin = original + offset;
		Hit hit = cast_hull();
		if (blocked(hit)) {
			continue;
		}
		double low = 0.0;
		double high = 1.0;
		const double step = NATIVE_RECOVERY_STEP / NATIVE_RECOVERY_REACH;
		query_origin = original + times(offset, step);
		hit = cast_hull();
		if (!blocked(hit)) {
			high = step;
		} else {
			low = step;
			for (int i = 0; i < 5; i++) {
				const double middle = (low + high) * 0.5;
				query_origin = original + times(offset, middle);
				hit = cast_hull();
				if (!blocked(hit)) {
					high = middle;
				} else {
					low = middle;
				}
			}
		}
		query_origin = original;
		return times(offset, high) + times(direction.normalized(), NATIVE_RECOVERY_PADDING);
	}
	query_origin = original;
	return ZERO;
}

Vector3 HullMover::ground_normal_in_quadrants() {
	// Four rays through the bridge, as the script asks them: from where the
	// body stands now.
	const Vector3 normal = body->call(names::quadrants(), position);
	quadrant_is_world = body->get(names::quadrant_is_world());
	return normal;
}

} // namespace godot
