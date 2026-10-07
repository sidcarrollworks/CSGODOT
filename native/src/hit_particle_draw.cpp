#include "hit_particle_draw.h"

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <cmath>
#include <cstring>
#include <limits>
#include <unordered_map>

namespace godot {

namespace {

// HitParticles.DRAG_STEP.
constexpr double DRAG_STEP = 1.0 / 30.0;

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

inline double maxd(double a, double b) {
	return a > b ? a : b;
}

inline double mind(double a, double b) {
	return a < b ? a : b;
}

// A script multiplies a vector by a float by narrowing the float first.
inline Vector3 times(const Vector3 &v, double s) {
	return v * (real_t)s;
}

double number(const Variant &p_value, double p_default) {
	switch (p_value.get_type()) {
		case Variant::FLOAT:
		case Variant::INT:
		case Variant::BOOL:
			return (double)p_value;
		default:
			return p_default;
	}
}

const String &key_of(const char *p_name) {
	// Made once a name: the dictionaries' keys are Strings. A map's entries
	// stay where they are as it grows.
	static std::unordered_map<const char *, String> keys;
	auto found = keys.find(p_name);
	if (found == keys.end()) {
		found = keys.emplace(p_name, String(p_name)).first;
	}
	return found->second;
}

inline Variant field(const Dictionary &p_dictionary, const char *p_key, const Variant &p_default = Variant()) {
	return p_dictionary.get(key_of(p_key), p_default);
}

const char *const ATTRIBUTE_NAMES[] = { "half", "alpha", "roll", "trail", "frame" };
const char *const RENDER_NAMES[] = { "radius_scale", "overbright", "max_length", "frame_rate", "alpha_threshold" };

// The record's fixed part (HitParticleDraw::build_record).
enum Slot {
	S_LAYER,
	S_BORN,
	S_LIFE,
	S_ORIGIN,
	S_VELOCITY = S_ORIGIN + 3,
	S_GRAVITY = S_VELOCITY + 3,
	S_DRAG_K = S_GRAVITY + 3,
	S_HALF,
	S_ALPHA,
	S_COLOR,
	S_ROLL = S_COLOR + 3,
	S_SPIN,
	S_TRAIL,
	S_FRAME,
	S_SEQ,
	S_INDEX,
	S_NORMAL,
	S_HAS_FADE_ENTER = S_NORMAL + 3,
	S_FADE_ENTER,
	S_FADE_LEAVE,
	S_FADE_IN,
	S_FADE_OUT,
	S_AT,
	S_BASIS = S_AT + 3,
	S_SCREEN = S_BASIS + 9,
	S_SPEED,
	S_CONSTANTS,
	S_VARIABLE = S_CONSTANTS + 5,
};

} // namespace

void HitParticleDraw::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_quad_batch", "sheet", "threshold", "most"), &HitParticleDraw::add_quad_batch);
	ClassDB::bind_method(D_METHOD("add_model_group", "variants", "capacity"), &HitParticleDraw::add_model_group);
	ClassDB::bind_method(D_METHOD("add_layer", "layer", "targets", "fps"), &HitParticleDraw::add_layer);
	ClassDB::bind_method(D_METHOD("draw", "live", "eye", "now", "height_at_unit"), &HitParticleDraw::draw);
	ClassDB::bind_method(D_METHOD("quad_cards"), &HitParticleDraw::quad_cards);
	ClassDB::bind_method(D_METHOD("model_cards"), &HitParticleDraw::model_cards);
}

// --- What is set up once ----------------------------------------------------

int HitParticleDraw::add_quad_batch(Object *p_sheet, double p_threshold, int p_most) {
	QuadBatch batch;
	batch.threshold = p_threshold;
	batch.most = p_most;
	if (p_sheet != nullptr) {
		const Array sequences = p_sheet->get("sequences");
		const Array clamped = p_sheet->get("clamped");
		const Array times = p_sheet->get("times");
		const PackedInt32Array offsets = p_sheet->get("_frame_offsets");
		const PackedFloat32Array seconds = p_sheet->get("_sequence_seconds");
		const Array ends = p_sheet->get("_frame_ends");
		for (int s = 0; s < sequences.size(); s++) {
			batch.counts.push_back((int)((Array)sequences[s]).size());
			batch.offsets.push_back(s < offsets.size() ? offsets[s] : 0);
			batch.clamped.push_back(s < clamped.size() ? (bool)clamped[s] : false);
			std::vector<float> shown;
			if (s < times.size()) {
				const PackedFloat32Array row = times[s];
				for (int i = 0; i < row.size(); i++) {
					shown.push_back(row[i]);
				}
			}
			batch.times.push_back(shown);
			batch.seconds.push_back(s < seconds.size() ? seconds[s] : 0.0f);
			std::vector<double> frame_ends;
			if (s < ends.size()) {
				const PackedFloat64Array row = ends[s];
				for (int i = 0; i < row.size(); i++) {
					frame_ends.push_back(row[i]);
				}
			}
			batch.ends.push_back(frame_ends);
		}
	}
	quad_batches.push_back(batch);
	return (int)quad_batches.size() - 1;
}

int HitParticleDraw::add_model_group(int p_variants, int p_capacity) {
	ModelGroup group;
	group.capacity = p_capacity;
	group.data.resize(p_variants > 0 ? p_variants : 0);
	group.counts.resize(p_variants > 0 ? p_variants : 0, 0);
	model_groups.push_back(group);
	return (int)model_groups.size() - 1;
}

HitParticleDraw::Descriptor HitParticleDraw::compile_descriptor(const Dictionary &p_descriptor) {
	Descriptor d;
	const String type = field(p_descriptor, "type", "");
	if (type == "PF_TYPE_CONTROL_POINT_COMPONENT") {
		d.input = IN_CONTROL_POINT;
		d.cp = (int)number(field(p_descriptor, "cp", 0), 0.0);
		d.component = (int)clampd((double)(int64_t)number(field(p_descriptor, "component", 0), 0.0), 0, 2);
	} else if (type == "PF_TYPE_PARTICLE_NUMBER") {
		d.input = IN_NUMBER;
	} else if (type == "PF_TYPE_PARTICLE_AGE" || type == "PF_TYPE_COLLECTION_AGE") {
		d.input = IN_AGE;
	} else if (type == "PF_TYPE_PARTICLE_AGE_NORMALIZED") {
		d.input = IN_AGE_NORMALIZED;
	} else if (type == "PF_TYPE_PARTICLE_FLOAT" || type == "PF_TYPE_PARTICLE_INITIAL_FLOAT") {
		d.input = IN_FIELD;
		switch ((int)number(field(p_descriptor, "attribute", 0), 0.0)) {
			case 1:
				d.field = F_LIFE;
				break;
			case 3:
				d.field = F_HALF;
				break;
			case 4:
				d.field = F_ROLL;
				break;
			case 7:
				d.field = F_ALPHA;
				break;
			case 10:
				d.field = F_TRAIL;
				break;
			case 38:
				d.field = F_FRAME;
				break;
			default:
				d.field = F_NONE;
				break;
		}
	} else if (type == "PF_TYPE_PARTICLE_SPEED") {
		d.input = IN_SPEED;
	} else {
		d.input = IN_NONE;
	}
	const Variant input = field(p_descriptor, "input");
	if (input.get_type() == Variant::ARRAY && ((Array)input).size() >= 2) {
		const Array range = input;
		d.in0 = number(range[0], 0.0);
		d.in1 = number(range[1], 1.0);
	}
	const Variant output = field(p_descriptor, "output");
	if (output.get_type() == Variant::ARRAY && ((Array)output).size() >= 2) {
		const Array range = output;
		d.out0 = number(range[0], 0.0);
		d.out1 = number(range[1], 1.0);
	}
	d.looped = String(field(p_descriptor, "input_mode", "")) == "PF_INPUT_MODE_LOOPED";
	const String map = field(p_descriptor, "map", "PF_MAP_TYPE_DIRECT");
	if (map == "PF_MAP_TYPE_MULT") {
		d.map = MAP_MULT;
	} else if (map == "PF_MAP_TYPE_REMAP") {
		d.map = MAP_REMAP;
	} else if (map == "PF_MAP_TYPE_REMAP_BIASED") {
		d.map = MAP_REMAP_BIASED;
	} else if (map == "PF_MAP_TYPE_CURVE") {
		d.map = MAP_CURVE;
	} else if (map == "PF_MAP_TYPE_NOTCHED") {
		d.map = MAP_NOTCHED;
	} else {
		d.map = MAP_DIRECT;
	}
	d.multiplier = number(field(p_descriptor, "multiplier", 1.0), 1.0);
	d.bias = number(field(p_descriptor, "bias", 0.0), 0.0);
	const String bias_type = field(p_descriptor, "bias_type", "PF_BIAS_TYPE_STANDARD");
	d.bias_type = bias_type == "PF_BIAS_TYPE_EXPONENTIAL" ? BIAS_EXPONENTIAL : (bias_type == "PF_BIAS_TYPE_GAIN" ? BIAS_GAIN : BIAS_STANDARD);
	const Variant curve = field(p_descriptor, "curve");
	if (curve.get_type() == Variant::ARRAY) {
		const Array points = curve;
		for (int i = 0; i < points.size(); i++) {
			const Array point = points[i];
			d.curve_x.push_back(number(point[0], 0.0));
			d.curve_y.push_back(number(point[1], 0.0));
		}
	}
	const Variant window = field(p_descriptor, "notched_range");
	if (window.get_type() == Variant::ARRAY && ((Array)window).size() >= 2) {
		d.notch_lo = number(((Array)window)[0], 0.0);
		d.notch_hi = number(((Array)window)[1], 1.0);
	}
	const Variant notches = field(p_descriptor, "notched_output");
	if (notches.get_type() == Variant::ARRAY && ((Array)notches).size() >= 2) {
		d.notch_out0 = number(((Array)notches)[0], 0.0);
		d.notch_out1 = number(((Array)notches)[1], 1.0);
	}
	return d;
}

HitParticleDraw::Scalar HitParticleDraw::compile_scalar(const Variant &p_value) {
	Scalar scalar;
	if (p_value.get_type() == Variant::DICTIONARY) {
		scalar.dynamic = true;
		scalar.descriptor = compile_descriptor(p_value);
	} else {
		scalar.constant = number(p_value, std::numeric_limits<double>::quiet_NaN());
	}
	return scalar;
}

int HitParticleDraw::add_layer(const Dictionary &p_layer, const PackedInt32Array &p_targets, const Array &p_fps) {
	Layer layer;
	const Dictionary ops = field(p_layer, "_attribute_ops", Dictionary());
	for (int a = 0; a < ATTRIBUTES; a++) {
		const String name = ATTRIBUTE_NAMES[a];
		if (!ops.has(name)) {
			continue;
		}
		const Dictionary op = ops[name];
		AttributeOp &compiled = layer.ops[a];
		compiled.present = true;
		const String method = field(op, "method", "PARTICLE_SET_REPLACE_VALUE");
		if (method == "PARTICLE_SET_SCALE_INITIAL_VALUE") {
			compiled.method = SCALE_INITIAL;
		} else if (method == "PARTICLE_SET_ADD_TO_INITIAL_VALUE") {
			compiled.method = ADD_TO_INITIAL;
		} else if (method == "PARTICLE_SET_SCALE_CURRENT_VALUE") {
			compiled.method = SCALE_CURRENT;
		} else if (method == "PARTICLE_SET_ADD_TO_CURRENT_VALUE") {
			compiled.method = ADD_TO_CURRENT;
		} else {
			compiled.method = SET_REPLACE;
		}
		const Variant descriptor = field(op, "descriptor");
		if (descriptor.get_type() == Variant::DICTIONARY) {
			compiled.descriptor = compile_descriptor(descriptor);
		} else {
			// An Array descriptor reads the constant sampled at the spawn;
			// anything else is not one the script reads at all.
			compiled.sampled = true;
		}
	}
	const Vector4 growth = field(p_layer, "_growth", Vector4(1, 1, 0, 1));
	layer.grow_x = growth.x;
	layer.grow_y = growth.y;
	layer.grow_z = growth.z;
	layer.grow_w = growth.w;
	layer.grow_bias = number(field(p_layer, "_grow_bias", 0.5), 0.5);
	layer.grow_ease = (bool)field(p_layer, "_grow_ease", false);
	layer.fraction_fade = p_layer.has(key_of("fade_in_frac")) || p_layer.has(key_of("fade_out_frac"));
	layer.fade_in_start_frac = number(field(p_layer, "fade_in_start_frac", 0.0), 0.0);
	layer.fade_in_frac = number(field(p_layer, "fade_in_frac", 0.5), 0.5);
	layer.fade_out_frac = number(field(p_layer, "fade_out_frac", 0.5), 0.5);
	layer.fade_out_end_frac = number(field(p_layer, "fade_out_end_frac", 1.0), 1.0);
	layer.fade_in_start_alpha = number(field(p_layer, "fade_in_start_alpha", 1.0), 1.0);
	layer.fade_out_end_alpha = number(field(p_layer, "fade_out_end_alpha", 0.0), 0.0);
	layer.fade_proportional = (bool)field(p_layer, "fade_proportional", true);
	layer.fade_in_proportional = (bool)field(p_layer, "fade_in_proportional", layer.fade_proportional);
	layer.fade_out_ease = p_layer.has(key_of("_fade_out_ease")) ? (bool)field(p_layer, "_fade_out_ease") : (bool)field(p_layer, "fade_out_ease", true);
	layer.max_distance = number(field(p_layer, "max_distance", 0.0), 0.0);
	layer.drag = number(field(p_layer, "drag", 0.0), 0.0);
	const Array renderers = field(p_layer, "renderers", Array());
	for (int i = 0; i < renderers.size(); i++) {
		const Dictionary source = renderers[i];
		Renderer renderer;
		const String kind = field(source, "kind", "sprite");
		renderer.kind = (kind == "projected" || kind == "light") ? KIND_SKIP : (kind == "model" ? KIND_MODEL : (kind == "trail" ? KIND_TRAIL : KIND_SPRITE));
		renderer.target = i < p_targets.size() ? p_targets[i] : -1;
		renderer.orient_z = (bool)field(source, "orient_z", false);
		const String animation = field(source, "animation_type", "ANIMATION_TYPE_FIXED_RATE");
		renderer.animation = animation == "ANIMATION_TYPE_MANUAL_FRAMES" ? ANIM_MANUAL : (animation == "ANIMATION_TYPE_FIXED_RATE" ? ANIM_FIXED_RATE : ANIM_OTHER);
		renderer.frame_rate = number(field(source, "frame_rate", 0.1), 0.1);
		renderer.animate_in_fps = (bool)field(source, "animate_in_fps", false);
		if (renderer.animate_in_fps && i < p_fps.size()) {
			// [count, seconds..., frames...] of the renderer's own sheet.
			const PackedFloat64Array table = p_fps[i];
			const int count = table.size() > 0 ? (int)table[0] : 0;
			for (int s = 0; s < count && 1 + count + s < table.size(); s++) {
				renderer.fps_seconds.push_back(table[1 + s]);
				renderer.fps_frames.push_back((int)table[1 + count + s]);
			}
		}
		for (int k = 0; k < RENDER_KEYS; k++) {
			const Variant input = field(source, RENDER_NAMES[k]);
			if (input.get_type() == Variant::DICTIONARY) {
				renderer.dynamic[k] = true;
				renderer.descriptors[k] = compile_descriptor(input);
			}
		}
		const Variant fade = field(source, "screen_fade", Array());
		if (fade.get_type() == Variant::ARRAY && !((Array)fade).is_empty()) {
			const Array ends = fade;
			if (ends.size() < 2 || ((Variant)ends[0]).get_type() == Variant::ARRAY || ((Variant)ends[1]).get_type() == Variant::ARRAY) {
				// A random range drawn every frame: not one the native draw
				// takes on; the script draws for this one.
				return -1;
			}
			renderer.screen_fade = true;
			renderer.screen_fade_start = compile_scalar(ends[0]);
			renderer.screen_fade_end = compile_scalar(ends[1]);
		}
		layer.renderers.push_back(renderer);
	}
	layers.push_back(layer);
	return (int)layers.size() - 1;
}

// --- A particle's record ----------------------------------------------------

PackedFloat64Array HitParticleDraw::build_record(const Dictionary &p) {
	PackedFloat64Array r;
	r.resize(S_VARIABLE);
	const Dictionary layer = field(p, "layer", Dictionary());
	r.set(S_LAYER, number(field(layer, "_native", -1), -1.0));
	r.set(S_BORN, (double)(int64_t)number(field(p, "born", 0), 0.0));
	r.set(S_LIFE, number(field(p, "life", 0.0), 0.0));
	const Vector3 origin = field(p, "origin", Vector3());
	const Vector3 velocity = field(p, "velocity", Vector3());
	const Vector3 gravity = field(p, "gravity", Vector3());
	for (int c = 0; c < 3; c++) {
		r.set(S_ORIGIN + c, origin[c]);
		r.set(S_VELOCITY + c, velocity[c]);
		r.set(S_GRAVITY + c, gravity[c]);
	}
	r.set(S_DRAG_K, number(field(p, "drag_k", -1.0), -1.0));
	r.set(S_HALF, number(field(p, "half", 0.0), 0.0));
	r.set(S_ALPHA, number(field(p, "alpha", 0.0), 0.0));
	const Color color = field(p, "color", Color(1, 1, 1));
	r.set(S_COLOR, color.r);
	r.set(S_COLOR + 1, color.g);
	r.set(S_COLOR + 2, color.b);
	r.set(S_ROLL, number(field(p, "roll", 0.0), 0.0));
	r.set(S_SPIN, number(field(p, "spin", 0.0), 0.0));
	r.set(S_TRAIL, number(field(p, "trail", 0.0), 0.0));
	r.set(S_FRAME, number(field(p, "frame", 0.0), 0.0));
	r.set(S_SEQ, (double)(int64_t)number(field(p, "seq", 0), 0.0));
	r.set(S_INDEX, (double)(int64_t)number(field(p, "index", 0), 0.0));
	const Vector3 normal = field(p, "normal", Vector3());
	for (int c = 0; c < 3; c++) {
		r.set(S_NORMAL + c, normal[c]);
	}
	r.set(S_HAS_FADE_ENTER, p.has(key_of("fade_enter")) ? 1.0 : 0.0);
	r.set(S_FADE_ENTER, number(field(p, "fade_enter", 0.0), 0.0));
	r.set(S_FADE_LEAVE, number(field(p, "fade_leave", 0.0), 0.0));
	r.set(S_FADE_IN, number(field(p, "fade_in", 0.0), 0.0));
	r.set(S_FADE_OUT, number(field(p, "fade_out", 0.0), 0.0));
	const Dictionary context = field(p, "context", Dictionary());
	const Vector3 at = field(context, "at", Vector3());
	for (int c = 0; c < 3; c++) {
		r.set(S_AT + c, at[c]);
	}
	const Basis basis = field(context, "basis", Basis());
	for (int row = 0; row < 3; row++) {
		for (int column = 0; column < 3; column++) {
			r.set(S_BASIS + row * 3 + column, basis.rows[row][column]);
		}
	}
	r.set(S_SCREEN, (bool)field(context, "screen", false) ? 1.0 : 0.0);
	r.set(S_SPEED, (double)velocity.length());
	// The curve constants sampled at the spawn, by the layer's attribute ops.
	const Dictionary ops = field(layer, "_attribute_ops", Dictionary());
	const Dictionary constants = field(p, "curve_constants", Dictionary());
	for (int a = 0; a < ATTRIBUTES; a++) {
		double sampled = 0.0;
		const String name = ATTRIBUTE_NAMES[a];
		if (ops.has(name)) {
			const Dictionary op = ops[name];
			sampled = number(constants.get(field(op, "constant_key", ""), 0.0), 0.0);
		}
		r.set(S_CONSTANTS + a, sampled);
	}
	// The control points, as they stand: id, x, y, z each.
	const Dictionary cps = field(context, "cps", Dictionary());
	const Array ids = cps.keys();
	r.push_back(ids.size());
	for (int i = 0; i < ids.size(); i++) {
		const Vector3 point = cps[ids[i]];
		r.push_back(number(ids[i], 0.0));
		r.push_back(point.x);
		r.push_back(point.y);
		r.push_back(point.z);
	}
	// The distance remaps: cp, component, input and output ranges each.
	const Array ops_by_distance = field(context, "distance_ops", Array());
	r.push_back(ops_by_distance.size());
	for (int i = 0; i < ops_by_distance.size(); i++) {
		const Dictionary op = ops_by_distance[i];
		r.push_back(number(field(op, "cp", 0), 0.0));
		r.push_back(number(field(op, "output_component", 0), 0.0));
		const Variant input = field(op, "input");
		const Variant output = field(op, "output");
		const bool has_input = input.get_type() == Variant::ARRAY && ((Array)input).size() >= 2;
		const bool has_output = output.get_type() == Variant::ARRAY && ((Array)output).size() >= 2;
		r.push_back(has_input ? number(((Array)input)[0], 0.0) : 0.0);
		r.push_back(has_input ? number(((Array)input)[1], 128.0) : 128.0);
		r.push_back(has_output ? number(((Array)output)[0], 0.0) : 0.0);
		r.push_back(has_output ? number(((Array)output)[1], 1.0) : 1.0);
	}
	// The render values sampled at the spawn, five a renderer; NaN where
	// the renderer's is a descriptor, worked out each frame.
	const Array render_constants = field(p, "render_constants", Array());
	r.push_back(render_constants.size());
	for (int i = 0; i < render_constants.size(); i++) {
		const Dictionary samples = render_constants[i];
		for (int k = 0; k < RENDER_KEYS; k++) {
			const String name = RENDER_NAMES[k];
			r.push_back(samples.has(name) ? number(samples[name], 0.0) : std::numeric_limits<double>::quiet_NaN());
		}
	}
	return r;
}

bool HitParticleDraw::read_record(const PackedFloat64Array &p_record, Particle &r) const {
	const double *v = p_record.ptr();
	const int64_t size = p_record.size();
	if (size < S_VARIABLE) {
		return false;
	}
	const int layer = (int)v[S_LAYER];
	if (layer < 0 || layer >= (int)layers.size()) {
		return false;
	}
	r.layer = &layers[layer];
	r.born = v[S_BORN];
	r.life = v[S_LIFE];
	r.origin = Vector3((real_t)v[S_ORIGIN], (real_t)v[S_ORIGIN + 1], (real_t)v[S_ORIGIN + 2]);
	r.velocity = Vector3((real_t)v[S_VELOCITY], (real_t)v[S_VELOCITY + 1], (real_t)v[S_VELOCITY + 2]);
	r.gravity = Vector3((real_t)v[S_GRAVITY], (real_t)v[S_GRAVITY + 1], (real_t)v[S_GRAVITY + 2]);
	r.drag_k = v[S_DRAG_K];
	r.half = v[S_HALF];
	r.alpha = v[S_ALPHA];
	r.color_r = (float)v[S_COLOR];
	r.color_g = (float)v[S_COLOR + 1];
	r.color_b = (float)v[S_COLOR + 2];
	r.roll = v[S_ROLL];
	r.spin = v[S_SPIN];
	r.trail = v[S_TRAIL];
	r.frame = v[S_FRAME];
	r.seq = (int64_t)v[S_SEQ];
	r.index = (int64_t)v[S_INDEX];
	r.normal = Vector3((real_t)v[S_NORMAL], (real_t)v[S_NORMAL + 1], (real_t)v[S_NORMAL + 2]);
	r.has_fade_enter = v[S_HAS_FADE_ENTER] != 0.0;
	r.fade_enter = v[S_FADE_ENTER];
	r.fade_leave = v[S_FADE_LEAVE];
	r.fade_in = v[S_FADE_IN];
	r.fade_out = v[S_FADE_OUT];
	r.at = Vector3((real_t)v[S_AT], (real_t)v[S_AT + 1], (real_t)v[S_AT + 2]);
	for (int row = 0; row < 3; row++) {
		r.basis.rows[row] = Vector3((real_t)v[S_BASIS + row * 3], (real_t)v[S_BASIS + row * 3 + 1], (real_t)v[S_BASIS + row * 3 + 2]);
	}
	r.speed = v[S_SPEED];
	for (int a = 0; a < ATTRIBUTES; a++) {
		r.constants[a] = v[S_CONSTANTS + a];
	}
	int64_t at = S_VARIABLE;
	if (at >= size) {
		return false;
	}
	r.cp_count = (int)v[at++];
	r.cps = v + at;
	at += (int64_t)r.cp_count * 4;
	if (at >= size) {
		return false;
	}
	r.distance_op_count = (int)v[at++];
	r.distance_ops = v + at;
	at += (int64_t)r.distance_op_count * 6;
	if (at >= size) {
		return false;
	}
	r.render_constant_count = (int)v[at++];
	r.render_constants = v + at;
	at += (int64_t)r.render_constant_count * RENDER_KEYS;
	return at <= size;
}

// --- HitParticles' arithmetic -----------------------------------------------

double HitParticleDraw::biased(double p_x, double p_bias) {
	if (p_bias <= 0.0) {
		return 0.0;
	}
	if (p_bias >= 1.0) {
		return 1.0;
	}
	const double x = clampd(p_x, 0.0, 1.0);
	return x / ((1.0 - x) * (1.0 / p_bias - 2.0) + 1.0);
}

double HitParticleDraw::parameter_bias(double p_x, double p_parameter, BiasType p_type) {
	if (p_type == BIAS_EXPONENTIAL) {
		const double exponent = p_parameter >= 0.0 ? 1.0 - clampd(p_parameter, 0, 1) : 20.0 - clampd(p_parameter + 1.0, 0, 1) * 19.0;
		return exponent <= 0.0 ? 1.0 : UtilityFunctions::pow(clampd(p_x, 0, 1), exponent);
	}
	const double bias = clampd((p_parameter + 1.0) * 0.5, 0, 1);
	if (p_type == BIAS_GAIN) {
		return p_x < 0.5 ? biased(p_x * 2.0, bias) * 0.5 : 1.0 - biased(2.0 - p_x * 2.0, bias) * 0.5;
	}
	return biased(p_x, bias);
}

double HitParticleDraw::remapped(double p_x, double p_in0, double p_in1, double p_out0, double p_out1) {
	if (p_in0 == p_in1) {
		return p_x >= p_in1 ? p_out1 : p_out0;
	}
	return Math::lerp(p_out0, p_out1, clampd(Math::inverse_lerp(p_in0, p_in1, p_x), 0, 1));
}

double HitParticleDraw::curve_at(const std::vector<double> &p_x, const std::vector<double> &p_y, double p_at) {
	if (p_x.empty()) {
		return 0.0;
	}
	if (p_at <= p_x[0]) {
		return p_y[0];
	}
	for (size_t i = 1; i < p_x.size(); i++) {
		if (p_at <= p_x[i]) {
			return Math::lerp(p_y[i - 1], p_y[i], Math::inverse_lerp(p_x[i - 1], p_x[i], p_at));
		}
	}
	return p_y.back();
}

double HitParticleDraw::mapped(const Descriptor &d, double p_x) {
	double x = p_x;
	if (d.looped && d.in1 != 0.0) {
		x = Math::fposmod(x, d.in1);
	}
	switch (d.map) {
		case MAP_MULT:
			return x * d.multiplier;
		case MAP_REMAP:
			return remapped(x, d.in0, d.in1, d.out0, d.out1);
		case MAP_REMAP_BIASED: {
			const double t = d.in0 != d.in1 ? clampd(Math::inverse_lerp(d.in0, d.in1, x), 0, 1) : (x >= d.in1 ? 1.0 : 0.0);
			return Math::lerp(d.out0, d.out1, parameter_bias(t, d.bias, d.bias_type));
		}
		case MAP_CURVE:
			return curve_at(d.curve_x, d.curve_y, x);
		case MAP_NOTCHED:
			return x >= d.notch_lo && x <= d.notch_hi ? d.notch_out1 : d.notch_out0;
		default:
			return x;
	}
}

double HitParticleDraw::value(const Descriptor &d, const Particle &p, double p_age) const {
	double x = 0.0;
	switch (d.input) {
		case IN_CONTROL_POINT: {
			for (size_t i = 0; i + 3 < p.frame_cps.size(); i += 4) {
				if ((int)p.frame_cps[i] == d.cp) {
					x = p.frame_cps[i + 1 + d.component];
					break;
				}
			}
		} break;
		case IN_NUMBER:
			x = (double)p.index;
			break;
		case IN_AGE:
			x = p_age;
			break;
		case IN_AGE_NORMALIZED:
			x = p_age / p.life;
			break;
		case IN_FIELD:
			switch (d.field) {
				case F_LIFE:
					x = p.life;
					break;
				case F_HALF:
					x = p.half;
					break;
				case F_ROLL:
					x = p.roll;
					break;
				case F_ALPHA:
					x = p.alpha;
					break;
				case F_TRAIL:
					x = p.trail;
					break;
				case F_FRAME:
					x = p.frame;
					break;
				default:
					x = 0.0;
					break;
			}
			break;
		case IN_SPEED:
			x = p.speed;
			break;
		default:
			x = 0.0;
			break;
	}
	return mapped(d, x);
}

double HitParticleDraw::scalar(const Scalar &p_scalar, const Particle &p, double p_age) const {
	return p_scalar.dynamic ? value(p_scalar.descriptor, p, p_age) : p_scalar.constant;
}

double HitParticleDraw::attribute(const Particle &p, Attribute p_key, double p_age, double p_current) const {
	const AttributeOp &op = p.layer->ops[p_key];
	if (!op.present) {
		return p_current;
	}
	double sample = op.sampled ? p.constants[p_key] : value(op.descriptor, p, p_age);
	if (p_key == A_ROLL && op.method != SCALE_INITIAL && op.method != SCALE_CURRENT) {
		sample = Math::deg_to_rad(sample);
	}
	double initial = 0.0;
	switch (p_key) {
		case A_HALF:
			initial = p.half;
			break;
		case A_ALPHA:
			initial = p.alpha;
			break;
		case A_ROLL:
			initial = p.roll;
			break;
		case A_TRAIL:
			initial = p.trail;
			break;
		case A_FRAME:
			initial = p.frame;
			break;
	}
	switch (op.method) {
		case SCALE_INITIAL:
			return initial * sample;
		case ADD_TO_INITIAL:
			return initial + sample;
		case SCALE_CURRENT:
			return p_current * sample;
		case ADD_TO_CURRENT:
			return p_current + sample;
		default:
			return sample;
	}
}

double HitParticleDraw::render_value(const Renderer &p_renderer, int p_index, RenderKey p_key, const Particle &p, double p_age) const {
	if (!p_renderer.dynamic[p_key] && p_index < p.render_constant_count) {
		return p.render_constants[p_index * RENDER_KEYS + p_key];
	}
	if (p_renderer.dynamic[p_key]) {
		return value(p_renderer.descriptors[p_key], p, p_age);
	}
	return p_renderer.fallbacks[p_key];
}

Vector3 HitParticleDraw::position(const Particle &p, double p_age) {
	double k = p.drag_k;
	if (k < 0.0) {
		const double drag = clampd(p.layer->drag, 0.0, 0.9999);
		k = drag > 0.0 ? -UtilityFunctions::log(1.0 - drag) / DRAG_STEP : 0.0;
	}
	if (k <= 0.0) {
		return p.origin + times(p.velocity, p_age) + times(p.gravity, 0.5 * p_age * p_age);
	}
	const double integral = (1.0 - UtilityFunctions::exp(-k * p_age)) / k;
	return p.origin + times(p.velocity, integral) + times(p.gravity, (p_age - integral) / k);
}

double HitParticleDraw::growth(const Layer &l, double p_through) {
	if (l.grow_w <= l.grow_z) {
		return 1.0;
	}
	if (p_through < l.grow_z) {
		return 1.0;
	}
	double t = clampd(Math::inverse_lerp(l.grow_z, l.grow_w, p_through), 0, 1);
	t = l.grow_ease ? Math::smoothstep(0.0, 1.0, t) : biased(t, l.grow_bias == 0.0 ? 0.5 : l.grow_bias);
	return Math::lerp(l.grow_x, l.grow_y, t);
}

double HitParticleDraw::fade(const Particle &p, double p_age) {
	if (p_age < 0.0 || p_age >= p.life) {
		return 0.0;
	}
	const Layer &l = *p.layer;
	if (l.fraction_fade) {
		const double through = p_age / p.life;
		double alpha = 1.0;
		if (through < l.fade_in_frac && l.fade_in_frac > l.fade_in_start_frac) {
			alpha = Math::lerp(l.fade_in_start_alpha, 1.0, Math::smoothstep(l.fade_in_start_frac, l.fade_in_frac, through));
		}
		if (through >= l.fade_out_frac && l.fade_out_end_frac > l.fade_out_frac) {
			alpha = Math::lerp(1.0, l.fade_out_end_alpha, Math::smoothstep(l.fade_out_frac, l.fade_out_end_frac, through));
		}
		return alpha;
	}
	double enter;
	double leave;
	if (p.has_fade_enter) {
		enter = p.fade_enter;
		leave = p.fade_leave;
	} else {
		enter = p.fade_in * (l.fade_in_proportional ? p.life : 1.0);
		leave = p.fade_out * (l.fade_proportional ? p.life : 1.0);
	}
	const double a = enter > 0 ? Math::smoothstep(0.0, enter, p_age) : 1.0;
	double out = leave > 0 ? clampd((p.life - p_age) / leave, 0, 1) : 1.0;
	if (l.fade_out_ease) {
		out = Math::smoothstep(0.0, 1.0, out);
	}
	return a * out;
}

double HitParticleDraw::animation_passes(const Renderer &p_renderer, const Particle &p, double p_time, double p_rate) {
	double passes = p_time * (p_rate >= 0.0 ? p_rate : p_renderer.frame_rate);
	if (p_renderer.animate_in_fps && !p_renderer.fps_seconds.empty()) {
		const int64_t count = (int64_t)p_renderer.fps_seconds.size();
		const int64_t sequence = Math::posmod(p.seq, count);
		const double seconds = p_renderer.fps_seconds[sequence];
		passes /= seconds > 0.0 ? seconds : maxd((double)p_renderer.fps_frames[sequence], 1.0);
	}
	return passes;
}

Vector3 HitParticleDraw::interpolation_data(const QuadBatch &b, int64_t p_sequence, double p_fraction) {
	if (b.counts.empty()) {
		return Vector3();
	}
	const int64_t s = Math::posmod(p_sequence, (int64_t)b.counts.size());
	const int64_t count = b.counts[s];
	if (count == 0) {
		return Vector3();
	}
	const int64_t offset = b.offsets[s];
	const std::vector<float> &shown = b.times[s];
	const bool clamped = b.clamped[s];
	if (shown.empty()) {
		const double at = clamped ? maxd(p_fraction, 0.0) * count : p_fraction * count;
		if (clamped && at >= count - 1) {
			return Vector3((real_t)(offset + count - 1), (real_t)(offset + count - 1), 0);
		}
		const int64_t frame_index = (int64_t)Math::floor(at);
		const int64_t index = clamped ? (frame_index < 0 ? 0 : (frame_index > count - 1 ? count - 1 : frame_index)) : Math::posmod(frame_index, count);
		return Vector3((real_t)(offset + index), (real_t)(offset + (index + 1) % count), (real_t)(at - Math::floor(at)));
	}
	const double total = b.seconds[s];
	double into = clamped ? maxd(p_fraction, 0.0) * total : p_fraction * total;
	if (total <= 0.0 || (clamped && into >= total)) {
		return Vector3((real_t)(offset + count - 1), (real_t)(offset + count - 1), 0);
	}
	if (!clamped) {
		into = Math::fposmod(into, total);
	}
	const std::vector<double> &ends = b.ends[s];
	int64_t low = 0;
	int64_t high = count;
	while (low < high) {
		const int64_t middle = (low + high) >> 1;
		if (ends[middle] <= into) {
			low = middle + 1;
		} else {
			high = middle;
		}
	}
	if (low >= count) {
		return Vector3((real_t)(offset + count - 1), (real_t)(offset + count - 1), 0);
	}
	const double before = low > 0 ? ends[low - 1] : 0.0;
	const int64_t next = clamped ? (low + 1 < count - 1 ? low + 1 : count - 1) : (low + 1) % count;
	return Vector3((real_t)(offset + low), (real_t)(offset + next), (real_t)((into - before) / maxd((double)shown[low], 0.00000001)));
}

Basis HitParticleDraw::impact_basis(const Vector3 &p_direction) {
	const Vector3 forward = p_direction.length_squared() > 1e-8 ? p_direction.normalized() : Vector3(0, 0, -1);
	const Vector3 side = forward.cross(std::fabs((double)forward.y) < 0.99 ? Vector3(0, 1, 0) : Vector3(1, 0, 0)).normalized();
	return Basis(forward, side, side.cross(forward).normalized());
}

Basis HitParticleDraw::model_basis(const Basis &p_impact, bool p_orient_z, double p_roll) {
	const Basis frame = p_impact.rotated(p_impact.get_column(0), (real_t)p_roll);
	if (p_orient_z) {
		return Basis(frame.get_column(1), frame.get_column(0), -frame.get_column(2));
	}
	return Basis(frame.get_column(1), frame.get_column(2), frame.get_column(0));
}

Transform3D HitParticleDraw::sprite(const Vector3 &p_centre, double p_half, double p_roll, const Transform3D &p_eye) {
	const Vector3 z = p_eye.basis.get_column(2);
	const Vector3 right = p_eye.basis.get_column(0).rotated(z, (real_t)p_roll);
	const Vector3 up = p_eye.basis.get_column(1).rotated(z, (real_t)p_roll);
	return Transform3D(Basis(times(times(right, p_half), 2.0), times(times(up, p_half), 2.0), z), p_centre);
}

Transform3D HitParticleDraw::streak(const Vector3 &p_tail, const Vector3 &p_head, double p_half_width, const Vector3 &p_eye_position) {
	const Vector3 along = p_head - p_tail;
	const Vector3 middle = times(p_head + p_tail, 0.5);
	Vector3 across = along.cross(p_eye_position - middle);
	if ((double)across.length_squared() < 1e-8) {
		across = along.cross(std::fabs((double)along.normalized().y) < 0.99 ? Vector3(0, 1, 0) : Vector3(1, 0, 0));
	}
	across = times(times(across.normalized(), p_half_width), 2.0);
	Vector3 facing = across.cross(along);
	facing = (double)facing.length_squared() > 1e-12 ? facing.normalized() : Vector3(0, 0, 1);
	return Transform3D(Basis(across, along, facing), middle);
}

void HitParticleDraw::update_control_points(Particle &p, double p_distance) const {
	p.frame_cps.assign(p.cps, p.cps + (size_t)p.cp_count * 4);
	for (int i = 0; i < p.distance_op_count; i++) {
		const double *op = p.distance_ops + i * 6;
		const int cp = (int)op[0];
		const int component = (int)clampd((double)(int64_t)op[1], 0, 2);
		size_t slot = p.frame_cps.size();
		for (size_t j = 0; j + 3 < p.frame_cps.size(); j += 4) {
			if ((int)p.frame_cps[j] == cp) {
				slot = j;
				break;
			}
		}
		if (slot == p.frame_cps.size()) {
			p.frame_cps.push_back(cp);
			p.frame_cps.push_back(0.0);
			p.frame_cps.push_back(0.0);
			p.frame_cps.push_back(0.0);
		}
		// A Vector3's part: the remap narrowed to single precision.
		p.frame_cps[slot + 1 + component] = (double)(real_t)remapped(p_distance, op[2], op[3], op[4], op[5]);
	}
}

// --- The draw ---------------------------------------------------------------

void HitParticleDraw::draw(const Array &p_live, const Transform3D &p_eye, int64_t p_now, double p_height_at_unit) {
	for (QuadBatch &batch : quad_batches) {
		batch.data.clear();
		batch.count = 0;
	}
	for (ModelGroup &group : model_groups) {
		for (size_t v = 0; v < group.data.size(); v++) {
			group.data[v].clear();
			group.counts[v] = 0;
		}
	}
	static const String RECORD = "_r";
	Particle p;
	for (int64_t i = 0; i < p_live.size(); i++) {
		Dictionary source = p_live[i];
		Variant cached = source.get(RECORD, Variant());
		PackedFloat64Array record;
		if (cached.get_type() == Variant::PACKED_FLOAT64_ARRAY) {
			record = cached;
		} else {
			record = build_record(source);
			source[RECORD] = record;
		}
		if (!read_record(record, p)) {
			continue;
		}
		const double age = (double)(p_now - (int64_t)p.born) / 1e6;
		if (age < 0.0 || age >= p.life) {
			continue;
		}
		if (record[S_SCREEN] != 0.0) {
			continue;
		}
		update_control_points(p, (double)p_eye.origin.distance_to(p.at));
		const Layer &layer = *p.layer;
		const double through = clampd(age / p.life, 0.0, 1.0);
		const Vector3 centre = position(p, age);
		if (layer.max_distance > 0.0 && (double)p_eye.origin.distance_to(centre) > layer.max_distance) {
			continue;
		}
		const double radius = attribute(p, A_HALF, age, p.half * growth(layer, through));
		const double alpha = attribute(p, A_ALPHA, age, p.alpha * fade(p, age));
		const double roll = attribute(p, A_ROLL, age, p.roll + Math::deg_to_rad(p.spin) * age);
		const double trail = attribute(p, A_TRAIL, age, p.trail);
		const double frame = attribute(p, A_FRAME, age, p.frame);
		for (int r = 0; r < (int)layer.renderers.size(); r++) {
			const Renderer &renderer = layer.renderers[r];
			if (renderer.kind == KIND_SKIP) {
				continue;
			}
			const double half = radius * render_value(renderer, r, R_RADIUS_SCALE, p, age);
			double a = alpha;
			if (renderer.screen_fade) {
				const double share = 2.0 * half / maxd((double)p_eye.origin.distance_to(centre) * p_height_at_unit, 1.0);
				const double fade_start = scalar(renderer.screen_fade_start, p, age);
				const double fade_end = scalar(renderer.screen_fade_end, p, age);
				a *= fade_end != fade_start ? clampd(Math::inverse_lerp(fade_end, fade_start, share), 0.0, 1.0) : (share <= fade_start ? 1.0 : 0.0);
			}
			const double bright = render_value(renderer, r, R_OVERBRIGHT, p, age);
			const Color shade((float)(p.color_r * bright), (float)(p.color_g * bright), (float)(p.color_b * bright), (float)a);
			if (a <= 0.0 || half <= 0.0) {
				continue;
			}
			if (renderer.kind == KIND_MODEL) {
				const double scale = half * 39.3700787;
				const Basis frame_basis = renderer.orient_z ? impact_basis(p.normal) : p.basis;
				const Transform3D xform(model_basis(frame_basis, renderer.orient_z, roll).scaled(times(Vector3(1, 1, 1), scale)), centre);
				if (renderer.target < 0 || renderer.target >= (int)model_groups.size()) {
					continue;
				}
				ModelGroup &group = model_groups[renderer.target];
				if (group.data.empty()) {
					continue;
				}
				const int64_t variant = Math::posmod(p.seq, (int64_t)group.data.size());
				if (group.counts[variant] >= group.capacity) {
					continue;
				}
				const Basis &b = xform.basis;
				const Vector3 &o = xform.origin;
				std::vector<float> &data = group.data[variant];
				const float card[MODEL_FLOATS] = {
					b.rows[0][0], b.rows[0][1], b.rows[0][2], o.x,
					b.rows[1][0], b.rows[1][1], b.rows[1][2], o.y,
					b.rows[2][0], b.rows[2][1], b.rows[2][2], o.z,
					shade.r, shade.g, shade.b, shade.a
				};
				data.insert(data.end(), card, card + MODEL_FLOATS);
				group.counts[variant]++;
				continue;
			}
			Transform3D xform;
			if (renderer.kind == KIND_TRAIL) {
				Vector3 tail = position(p, maxd(age - trail, 0.0));
				const double max_length = render_value(renderer, r, R_MAX_LENGTH, p, age);
				if ((double)tail.distance_to(centre) > max_length) {
					tail = centre + times((tail - centre).normalized(), max_length);
				}
				if ((double)tail.distance_squared_to(centre) < 0.0001) {
					continue;
				}
				xform = streak(tail, centre, half, p_eye.origin);
			} else {
				xform = sprite(centre, half, roll, p_eye);
			}
			const double threshold = render_value(renderer, r, R_ALPHA_THRESHOLD, p, age);
			const double rate = render_value(renderer, r, R_FRAME_RATE, p, age);
			double frame_at;
			switch (renderer.animation) {
				case ANIM_MANUAL:
					frame_at = frame;
					break;
				case ANIM_FIXED_RATE:
					frame_at = animation_passes(renderer, p, age, rate);
					break;
				default:
					frame_at = animation_passes(renderer, p, age / p.life, rate);
					break;
			}
			if (renderer.target < 0 || renderer.target >= (int)quad_batches.size()) {
				continue;
			}
			QuadBatch &batch = quad_batches[renderer.target];
			if (batch.count >= batch.most) {
				continue;
			}
			const Vector3 animation = interpolation_data(batch, p.seq, frame_at);
			const double kept = threshold < 0.0 ? batch.threshold : clampd(threshold, 0.0, 0.99999);
			const Basis &b = xform.basis;
			const Vector3 &o = xform.origin;
			const float card[QUAD_FLOATS] = {
				b.rows[0][0], b.rows[0][1], b.rows[0][2], o.x,
				b.rows[1][0], b.rows[1][1], b.rows[1][2], o.y,
				b.rows[2][0], b.rows[2][1], b.rows[2][2], o.z,
				shade.r, shade.g, shade.b, shade.a,
				animation.x, animation.y, animation.z, (float)kept
			};
			batch.data.insert(batch.data.end(), card, card + QUAD_FLOATS);
			batch.count++;
		}
	}
}

Array HitParticleDraw::quad_cards() const {
	Array out;
	for (size_t i = 0; i < quad_batches.size(); i++) {
		const std::vector<float> &cards = quad_batches[i].data;
		if (cards.empty()) {
			continue;
		}
		PackedFloat32Array data;
		data.resize((int64_t)cards.size());
		memcpy(data.ptrw(), cards.data(), cards.size() * sizeof(float));
		out.push_back((int64_t)i);
		out.push_back(data);
	}
	return out;
}

Array HitParticleDraw::model_cards() const {
	Array out;
	for (size_t g = 0; g < model_groups.size(); g++) {
		for (size_t v = 0; v < model_groups[g].data.size(); v++) {
			const std::vector<float> &cards = model_groups[g].data[v];
			if (cards.empty()) {
				continue;
			}
			PackedFloat32Array data;
			data.resize((int64_t)cards.size());
			memcpy(data.ptrw(), cards.data(), cards.size() * sizeof(float));
			out.push_back((int64_t)g);
			out.push_back((int64_t)v);
			out.push_back(data);
		}
	}
	return out;
}

} // namespace godot
