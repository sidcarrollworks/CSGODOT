// The hit particles' draw in native code: HitParticles._script_draw and what
// it calls (src/effects/hit_particles.gd), with the cards as HitQuads.card
// and HitModels.card write them and the frames as SpriteSheet's
// interpolation_data finds them.
//
// The script is the reference, and this is the same work in the same order:
// every live particle, every frame, its size, fade, turn and frame worked
// out from its spawn values and the camera, and a card written for each of
// its renderers. It is a view, so it is held to the script's cards within
// float precision rather than to the bit (HitParticles.draws_checked): sin,
// cos and exp may differ in their last bit between Godot's runtime and
// this library's, and exp and pow are asked of Godot's own to keep them
// the same.
//
// A particle's spawn values are read from its dictionary once, the first
// time it is drawn, and kept with it (its "_r"): one lookup a particle a
// frame after that.

#ifndef CSGODOT_HIT_PARTICLE_DRAW_H
#define CSGODOT_HIT_PARTICLE_DRAW_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class HitParticleDraw : public RefCounted {
	GDCLASS(HitParticleDraw, RefCounted)

public:
	// HitQuads.FLOATS and HitModels' sixteen.
	static constexpr int QUAD_FLOATS = 20;
	static constexpr int MODEL_FLOATS = 16;

	// A HitQuads batch: its sheet's frame tables (SpriteSheet: sequences,
	// clamped, times, _frame_offsets, _sequence_seconds, _frame_ends), its
	// threshold and the most cards it takes. Its index.
	int add_quad_batch(Object *p_sheet, double p_threshold, int p_most);
	// A HitModels group: its variants and how many cards each takes.
	int add_model_group(int p_variants, int p_capacity);
	// A prepared HitParticles layer (HitParticles.prepare), each renderer's
	// batch or model group (-1 for none) and, where it animates in frames a
	// second, its sheet's sequence seconds and frame counts. Its index,
	// which the layer keeps as "_native".
	int add_layer(const Dictionary &p_layer, const PackedInt32Array &p_targets, const Array &p_fps);
	// The cards of every live particle at now (usec) from eye;
	// height_at_unit is the script's 2 tan(fov / 2).
	void draw(const Array &p_live, const Transform3D &p_eye, int64_t p_now, double p_height_at_unit);
	// The last draw's cards, the batches that have any: [index, cards]
	// pairs, the cards a PackedFloat32Array; a model group's [group,
	// variant, cards].
	Array quad_cards() const;
	Array model_cards() const;

protected:
	static void _bind_methods();

private:
	// Where a descriptor reads its input (HitParticles.value).
	enum InputType {
		IN_CONTROL_POINT,
		IN_NUMBER,
		IN_AGE,
		IN_AGE_NORMALIZED,
		IN_FIELD,
		IN_SPEED,
		IN_NONE,
	};
	enum MapType {
		MAP_DIRECT,
		MAP_MULT,
		MAP_REMAP,
		MAP_REMAP_BIASED,
		MAP_CURVE,
		MAP_NOTCHED,
	};
	enum BiasType {
		BIAS_STANDARD,
		BIAS_GAIN,
		BIAS_EXPONENTIAL,
	};
	enum Method {
		SET_REPLACE,
		SCALE_INITIAL,
		ADD_TO_INITIAL,
		SCALE_CURRENT,
		ADD_TO_CURRENT,
	};
	enum Kind {
		KIND_SPRITE,
		KIND_TRAIL,
		KIND_MODEL,
		KIND_SKIP,
	};
	enum Animation {
		ANIM_MANUAL,
		ANIM_FIXED_RATE,
		ANIM_OTHER,
	};

	// A particle field a descriptor may read (value's attribute map), in
	// the record's order of them.
	enum Field {
		F_LIFE,
		F_HALF,
		F_ROLL,
		F_ALPHA,
		F_TRAIL,
		F_FRAME,
		F_NONE,
	};

	struct Descriptor {
		InputType input = IN_NONE;
		int cp = 0;
		int component = 0;
		Field field = F_NONE;
		double in0 = 0.0;
		double in1 = 1.0;
		double out0 = 0.0;
		double out1 = 1.0;
		bool looped = false;
		MapType map = MAP_DIRECT;
		double multiplier = 1.0;
		double bias = 0.0;
		BiasType bias_type = BIAS_STANDARD;
		std::vector<double> curve_x;
		std::vector<double> curve_y;
		double notch_lo = 0.0;
		double notch_hi = 1.0;
		double notch_out0 = 0.0;
		double notch_out1 = 1.0;
	};

	// A number, or a descriptor worked out each frame.
	struct Scalar {
		bool dynamic = false;
		double constant = 0.0;
		Descriptor descriptor;
	};

	struct AttributeOp {
		bool present = false;
		Method method = SET_REPLACE;
		// An Array descriptor reads the constant sampled at the spawn.
		bool sampled = false;
		Descriptor descriptor;
	};

	// The eight render values a renderer may have (HitParticles.RENDER_DEFAULTS),
	// in the record's order.
	static constexpr int RENDER_KEYS = 8;
	enum RenderKey {
		R_RADIUS_SCALE,
		R_OVERBRIGHT,
		R_MAX_LENGTH,
		R_FRAME_RATE,
		R_ALPHA_THRESHOLD,
		R_RENDER_ALPHA,
		R_MIN_SCREEN,
		R_MAX_SCREEN,
	};

	struct Renderer {
		Kind kind = KIND_SPRITE;
		int target = -1;
		bool orient_z = false;
		Animation animation = ANIM_FIXED_RATE;
		double frame_rate = 0.1;
		bool animate_in_fps = false;
		std::vector<double> fps_seconds;
		std::vector<int> fps_frames;
		bool dynamic[RENDER_KEYS] = { false, false, false, false, false, false, false, false };
		Descriptor descriptors[RENDER_KEYS];
		double fallbacks[RENDER_KEYS] = { 1.0, 1.0, 500.0, 0.1, 0.0, 1.0, 0.0, 5000.0 };
		// The renderer's colour, linear, as HitParticles keeps it (_color_scale).
		Color color_scale = Color(1, 1, 1, 1);
		bool screen_fade = false;
		Scalar screen_fade_start;
		Scalar screen_fade_end;
	};

	static constexpr int ATTRIBUTES = 5;
	enum Attribute {
		A_HALF,
		A_ALPHA,
		A_ROLL,
		A_TRAIL,
		A_FRAME,
	};

	struct Layer {
		AttributeOp ops[ATTRIBUTES];
		double grow_x = 1.0;
		double grow_y = 1.0;
		double grow_z = 0.0;
		double grow_w = 1.0;
		double grow_bias = 0.5;
		bool grow_ease = false;
		bool fraction_fade = false;
		double fade_in_start_frac = 0.0;
		double fade_in_frac = 0.5;
		double fade_out_frac = 0.5;
		double fade_out_end_frac = 1.0;
		double fade_in_start_alpha = 1.0;
		double fade_out_end_alpha = 0.0;
		bool fade_proportional = true;
		bool fade_in_proportional = true;
		bool fade_out_ease = true;
		double max_distance = 0.0;
		double drag = 0.0;
		std::vector<Renderer> renderers;
	};

	struct QuadBatch {
		std::vector<int> counts;
		std::vector<int> offsets;
		std::vector<bool> clamped;
		std::vector<std::vector<float>> times;
		std::vector<float> seconds;
		std::vector<std::vector<double>> ends;
		double threshold = 0.0;
		int most = 4096;
		std::vector<float> data;
		int count = 0;
	};

	struct ModelGroup {
		int capacity = 64;
		std::vector<std::vector<float>> data;
		std::vector<int> counts;
	};

	// A particle as drawn: its spawn values, from its record.
	struct Particle {
		const Layer *layer = nullptr;
		double born = 0.0;
		double life = 0.0;
		Vector3 origin;
		Vector3 velocity;
		Vector3 gravity;
		bool has_drag_k = false;
		double drag_k = 0.0;
		double half = 0.0;
		double alpha = 0.0;
		float color_r = 1.0f;
		float color_g = 1.0f;
		float color_b = 1.0f;
		double roll = 0.0;
		double spin = 0.0;
		double trail = 0.0;
		double frame = 0.0;
		int64_t seq = 0;
		int64_t index = 0;
		Vector3 normal;
		bool has_fade_enter = false;
		double fade_enter = 0.0;
		double fade_leave = 0.0;
		double fade_in = 0.0;
		double fade_out = 0.0;
		Vector3 at;
		Basis basis;
		double speed = 0.0;
		double constants[ATTRIBUTES] = { 0.0, 0.0, 0.0, 0.0, 0.0 };
		const double *cps = nullptr;
		int cp_count = 0;
		const double *distance_ops = nullptr;
		int distance_op_count = 0;
		const double *render_constants = nullptr;
		int render_constant_count = 0;
		// This frame's control points: id, x, y, z.
		std::vector<double> frame_cps;
	};

	std::vector<Layer> layers;
	std::vector<QuadBatch> quad_batches;
	std::vector<ModelGroup> model_groups;

	static Descriptor compile_descriptor(const Dictionary &p_descriptor);
	static Scalar compile_scalar(const Variant &p_value);
	static PackedFloat64Array build_record(const Dictionary &p_particle);
	bool read_record(const PackedFloat64Array &p_record, Particle &r_particle) const;

	static double biased(double p_x, double p_bias);
	static double parameter_bias(double p_x, double p_parameter, BiasType p_type);
	static double remapped(double p_x, double p_in0, double p_in1, double p_out0, double p_out1);
	static double curve_at(const std::vector<double> &p_x, const std::vector<double> &p_y, double p_at);
	static double mapped(const Descriptor &p_descriptor, double p_x);
	double value(const Descriptor &p_descriptor, const Particle &p_particle, double p_age) const;
	double scalar(const Scalar &p_scalar, const Particle &p_particle, double p_age) const;
	double attribute(const Particle &p_particle, Attribute p_key, double p_age, double p_current) const;
	double render_value(const Renderer &p_renderer, int p_index, RenderKey p_key, const Particle &p_particle, double p_age) const;
	static Vector3 position(const Particle &p_particle, double p_age);
	static double growth(const Layer &p_layer, double p_through);
	static double fade(const Particle &p_particle, double p_age);
	static double animation_passes(const Renderer &p_renderer, const Particle &p_particle, double p_time, double p_rate);
	static Vector3 interpolation_data(const QuadBatch &p_batch, int64_t p_sequence, double p_fraction);
	static Basis impact_basis(const Vector3 &p_direction);
	static Basis model_basis(const Basis &p_impact, bool p_orient_z, double p_roll);
	static Transform3D sprite(const Vector3 &p_centre, double p_half, double p_roll, const Transform3D &p_eye);
	static Transform3D streak(const Vector3 &p_tail, const Vector3 &p_head, double p_half_width, const Vector3 &p_eye_position);
	void update_control_points(Particle &r_particle, double p_distance) const;
};

} // namespace godot

#endif
