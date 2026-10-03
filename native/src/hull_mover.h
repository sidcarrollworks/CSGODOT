// The movement's step in native code: PlayerBody._simulate_step and all it
// calls (src/movement/player_body.gd), with the hull's sweep as the bridge
// answers it (Box3DQueries.shape_cast_prepared, src/physics/box3d_queries.gd).
//
// The script is the reference. This is the same code in the same order with
// the same arithmetic, so that the two give the same body to the last bit
// (tests/run_native_movement_checks.gd holds them to it): a script float is
// a double and a vector's parts are single floats, and every expression here
// is widened and narrowed where the script's is.
//
// It takes the body's state from the body, runs the step on its own copy, and
// puts the state back: the body's place is written once, where the script
// writes it at every trace.

#ifndef CSGODOT_HULL_MOVER_H
#define CSGODOT_HULL_MOVER_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class HullMover : public RefCounted {
	GDCLASS(HullMover, RefCounted)

public:
	// PlayerBody's constants.
	static constexpr int MAX_BUMPS = 4;
	static constexpr int MAX_CLIP_PLANES = 5;
	static constexpr double GROUND_TRACE_DISTANCE = 2.0;
	static constexpr double STAY_ON_GROUND_MIN_DELTA = 0.03;
	static constexpr double STAY_ON_GROUND_LIFT = 1.0;
	static constexpr double NATIVE_QUERY_MARGIN = 0.06;
	static constexpr double NATIVE_RECOVERY_REACH = 0.5;
	static constexpr double NATIVE_RECOVERY_PADDING = 0.01;
	static constexpr double NATIVE_RECOVERY_STEP = 0.125;
	// Box3DQueries' constants.
	static constexpr double SCALE = 0.0254;
	static constexpr int64_t QUERY_LAYER = int64_t(1) << 30;
	static constexpr double CAST_CLEARANCE = 0.06;
	static constexpr double CAST_REACH = 0.75;
	static constexpr double CAST_BACK_OFF = 0.5;
	static constexpr double CAST_INSET = 0.125;
	// Hitbox.LAYER: a hull's sweep meets bodies, not areas.
	static constexpr int64_t HITBOX_LAYER = 4;

	// How many hull casts the last step made.
	int get_casts() const { return casts; }
	// And how many of them met something: the bridge remembers the last
	// sweep that did (Box3DQueries.forget_cast).
	int get_hits() const { return hits; }

	// What this library was built from: the stamp native/SConstruct worked
	// out of the sources and of the scripts they copy. The script works out
	// the same of what it finds (PlayerBody.native_sources), and runs the
	// step itself where the two differ.
	String get_sources() const;

	// One step of `body` (a PlayerBody inside its own tick's scope) against
	// `world` (the bridge's Box3DWorld). walkable_y is the least a floor's
	// normal may rise by and be walked on: the script's
	// cos(deg_to_rad(max_ground_angle_deg)), worked out there so that both
	// use the one value. False, with nothing moved, where the step could not
	// be run: no body, no config, or a world that has no sweep to ask for.
	bool step(Object *p_body, Object *p_world, double p_dt, double p_walkable_y);

protected:
	static void _bind_methods();

private:
	struct Config {
		double gravity = 800.0;
		double accelerate = 5.5;
		double air_accelerate = 12.0;
		double friction = 5.2;
		double stop_speed = 80.0;
		double air_max_wishspeed = 30.0;
		double max_speed = 250.0;
		double jump_impulse = 301.993;
		bool cs2_jump = true;
		bool tick_rate_independent_jump = false;
		double non_jump_velocity = 140.0;
		double max_velocity = 3500.0;
		bool auto_bunnyhop = false;
		bool enable_bunnyhopping = false;
		double bunnyhop_speed_cap = 1.1;
		double hull_width = 32.0;
		double stand_height = 72.0;
		double duck_height = 54.0;
		double duck_time = 0.4;
		double step_height = 18.0;
		bool project_wish_dir_on_ground = false;
		bool stay_on_ground = true;
		double trace_epsilon = 0.0;
		bool source_deadstrafe = true;
		double deadstrafe_friction = 0.25;
		double deadstrafe_max_vertical_speed = 140.0;
		double walkable_y = 0.7;
	};

	// What a sweep met: PlayerBody.TraceResult, and null is `met` false.
	struct Trace {
		bool met = false;
		Vector3 travel;
		Vector3 normal;
		Vector3 recovery;
	};

	// What the bridge hands back for a sweep: its dictionary's parts.
	struct Hit {
		bool empty = true;
		double fraction = 1.0;
		Vector3 normal;
		Vector3 offset;
		Object *collider = nullptr; // the body it met, as the game has it
		int shape = -1;
	};

	Config cfg;
	Object *body = nullptr;
	Object *world = nullptr;
	// The world last found to have the sweep, by its instance.
	uint64_t world_known = 0;
	int casts = 0;
	int hits = 0;

	// The body's state, as the step has it.
	Vector3 position;
	// Where the node was last told the body is.
	Vector3 written;
	Vector3 velocity;
	bool on_ground = false;
	Vector3 ground_normal = Vector3(0, 1, 0);
	bool is_ducked = false;
	double duck_progress = 0.0;
	Vector3 wish_dir;
	double wish_speed = 0.0;
	double acceleration_speed = 0.0;
	bool wants_jump = false;
	bool wants_duck = false;
	bool jump_held_last_tick = false;
	bool jumped = false;
	Vector3 looked_from;
	double looked_with = 0.0;
	double hull_height = 0.0;
	Vector3 floor_at;
	double floor_with = 0.0;
	Vector3 floor_normal = Vector3(0, 1, 0);
	Vector3 recovery_direction = Vector3(0, 1, 0);
	Vector3 last_trace_recovery;
	int64_t collision_mask = 0;
	double query_margin = 0.06;

	// The sweep being asked: where the hull's middle starts and how it moves.
	Vector3 query_origin;
	Vector3 query_motion;

	void read_config(Object *p_config);
	void read_body();
	void write_body(const Vector3 &p_position_before);

	void simulate_step(double dt);
	bool ground_known() const;
	void update_duck(double dt);
	double duck_height_delta() const;
	void finish_duck();
	void finish_unduck();
	bool can_unduck();
	void set_hull(double height);
	void try_jump(double dt);
	void walk_move(double surface_friction, double dt);
	void stay_on_native_ground();
	void air_move(double surface_friction, double dt);
	void step_move(double dt);
	bool try_player_move(double dt);
	void categorize_position();
	Trace trace(const Vector3 &motion, bool test_only = false);
	Hit cast_from(const Vector3 &from, const Vector3 &motion);
	Hit cast_hull();
	bool recovery_blocked_by_player(const Hit &hit) const;
	Vector3 recover_trace_start();
	Vector3 ground_normal_in_quadrants();
	Vector3 hull_middle() const;

	bool is_walkable(const Vector3 &normal) const;
	static Vector3 clip_velocity(const Vector3 &velocity, const Vector3 &normal, double overbounce = 1.0);
	Vector3 check_velocity(const Vector3 &velocity) const;
	Vector3 apply_friction(const Vector3 &velocity, bool on_ground, double surface_friction, double dt) const;
	static Vector3 accelerate(const Vector3 &velocity, const Vector3 &wish_dir, double wish_speed, double accel, double surface_friction, double dt, double accel_from = 0.0);
	Vector3 air_accelerate(const Vector3 &velocity, const Vector3 &wish_dir, double wish_speed, double accel, double surface_friction, double dt) const;
	double surface_friction_for(double vertical_velocity, bool on_ground) const;
	Vector3 clamp_bunnyhop(const Vector3 &velocity) const;
};

} // namespace godot

#endif
