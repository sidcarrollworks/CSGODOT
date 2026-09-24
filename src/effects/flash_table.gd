class_name FlashTable
extends RefCounted

## CS2's muzzle flashes, worked out for every gun and view, so MuzzleFlashes plays numbers and computes nothing from
## CS2's control points. Read 2026-09-24 from CS2 1.41.8.3: the .vpcf files decompiled with Source 2 Viewer
## (particles/unified_weapon_fx/*, particles/weapons/cs_weapon_fx/weapon_taser_glow), the first-person fire clips' events
## (viewmodel clip_data) and the third-person shoot clips' (animation/anims/world/*/shoot_*). Typed from the files, not
## generated at run time: a CS2 update that changes an effect needs them read again (reference/weapons/effects.md).
## Two readings were made, first person ("the fps report") and third ("the world report"); where they disagreed, the
## comments say which one the .vpcf bore out. The rifle, machine-gun and sniper entries were checked a second time
## against the files; the pistol, SMG and shotgun entries were not.
## Source units (1 u = 1 inch), seconds, colours 0-255. Local muzzle frame: +X down the barrel (fwd), +Y left (side), +Z up.
## Bloom-pass-only renderers (m_bOnlyRenderInEffectsBloomPass) are left out; give the additive layers HDR colour and let glow stand in.

## Keys (a missing key means the default in brackets):
##   kind: sprite | trail | spark | smoke | light. tex/tex_mv: SHEETS/TEXTURES short name (tex_mv = motion-vector sheet, same frame as tex).
##   tex_layers: [[short name, weight or [[collection age s, weight], ...]], ...] extra texture layers blended over tex. tex_v_scale: trail V scale.
##   seq: random sequence index range (inclusive); seq2: second-sequence range. frame: sheet position 0..1 at birth, random in range;
##   frame_by_index: per particle index, [at t=0, at t=1] of the burst's shared t; frame_rate: + per second; frame_age_bias b:
##   frame = (frame or 1) * pow(age/life, log(b)/log(0.5)) (inferred: Source's Bias()). blend: add | alpha | lighten (max). overbright multiplies colour (HDR).
##   tint: renderer colour scale; drawn colour = lerp(color_min, color_max, rand) * tint / 255 * overbright [tint white].
##   head/tail: trail colour scale at the head (particle) and tail; tail_taper/head_taper multiply the width there [1].
##   min_length/max_length: trail length clamp [0/none]. trail length = |velocity| * trail_time * length_scale [1].
##   passes (sparks): each entry is one main-pass trail over the same particles: length_scale, width (x half), tail_taper,
##   length_fade_in (s), max_length, max_screen. max_screen: largest screen fraction a sprite may cover; screen_fade [start, end]: fade out
##   when it covers that fraction. count: particles per shot, or [min, max] random (count_cap = most alive, per_frame = most emitted a frame).
##   delay: emission start (s). life: [min, max] s. bias: {key: PF_BIAS_TYPE_EXPONENTIAL parameter} for ranges CS2 draws skewed
##   (negative skews toward min; the exact curve is not in the files, uniform is the fallback). fade_out: [min, max] s window before
##   death (longer than life = fades from birth); fade_frac: same as a fraction of life; fade_ease: smoothstep [true]; fade_in_frac.
##   x/y/z: spawn offset ranges [0]; x_by_index / yz_by_index: per index [at t=0, at t=1] of ONE t drawn per burst (CS2's shared
##   InitFloatCollection), yz = offset added to both +Y and +Z; side: +- random Y and Z. sphere: spawn radius around CP0, sphere_bias
##   stretches the random direction, sphere_fwd_only takes |x|. ring: ring radius around the barrel (ring_pitch 90) or in CP0's XY
##   plane; star: [min, max] particles per orbit (even spacing, particle i at i * 360 / star degrees); vel_out: radial speed (negative = inward).
##   half: [min, max] half-width in u, renderer radius scale included; half_by_index: per index value or [min, max] drawn per particle;
##   half_shared * half_scale: one shared draw per burst times one per particle. grow: [start, end] radius multiplier over life,
##   grow_bias: bias of that ramp [0.5 = linear]. radius_rate: [[u/s, from s, to s], ...] added to the radius.
##   trail_time: seconds of travel the trail spans at birth (trail_time_shared: one per burst; trail_scale multiplies per particle);
##   trail_rate: + per second; trail_time_zero_at: fraction of life by which it reaches 0; trail_time_curve: [[age/life, s], ...].
##   length: derived, not a CS2 field: the trail's length range at birth, |velocity| * trail_time clamped by min/max_length.
##   alpha: [min, max]; alpha_curve: [[age/life, multiplier], ...]; alpha2 / alpha2_by_index: second alpha multiplier (field 16).
##   color_end over [color_end_from, color_end_to] of life; birth_tint: colour at birth, back to the particle colour by birth_tint_until.
##   roll: degrees, roll_flip: random sign. vel_*: local speeds u/s (vel_side +Y, vel_up +Z, vel_out radial); negative vel_fwd = back
##   toward the shooter, so a trail drawn behind the particle reaches forward. accel_fwd: local X u/s^2 (accel_frame spawn = the
##   muzzle frame frozen at the shot); gravity: world Z u/s^2; drag: CS2 fDrag (velocity x (1 - drag) per 1/30 s); force_*: u/s^2.
##   inherit_vel: fraction of the muzzle's velocity added at birth. follow: C_OP_PositionLock on (rides the muzzle with its rotation)
##   or off (stays where it spawned) [false]; follow_rot false = position only; follow_release: the lock starts letting go at this age (s).
##   world_pass: drawn as a world effect, not in the view-model pass, even in first person. Lights: range u, energy = CS2 intensity,
##   brightness = energy * alpha (inferred), offset (local), offset_side +- random Y. cull [fraction, from life fraction]: that share
##   of particles is killed from then on. age_start: particles start part-way through life (fraction).

## LAYERS: every layer any flash uses, at scale 1: every control-point factor (GlobalScale, CP remaps, renderer CP scales) left at 1,
## so a layer here is the file's own numbers; where a control point sets a count or lifetime outright, the largest value its remap
## gives. FLASHES carries the resolved values. Read from the .vpcf named in each comment.
const LAYERS := {
	# uweapon_muzzleflash_pist_fire (renderer radius scale = CP3)
	"pist_fire": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "seq": [0, 3], "frame": [0.55, 0.66], "frame_rate": 10.0,
		"blend": "add", "overbright": 4.0, "tint": Color8(178, 176, 139),
		"count": 6,  # emits 8, m_nMaxParticles 6
		"life": [0.05, 0.05], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[0.0, 0.0], [1.114, 2.228], [2.091, 4.182], [2.999, 5.997], [3.931, 7.861], [5.0, 10.0]],  # x = 10*u*c(i), one u in [0.5, 1] per burst
		"half_by_index": [[2.212, 3.318], [3.673, 5.935], [2.867, 5.579], [2.255, 5.066], [2.167, 4.463], [2.167, 3.9]], "grow": [1.0, 2.0],
		"alpha": [0.1961, 0.3922], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-30.0, 120.0], "roll_flip": true,
		"inherit_vel": 1.0, "follow": true,
	},
	# uweapon_muzzleflash_pist_fire_alt (renderer radius scale = 2*CP3)
	"pist_fire_alt": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "seq": [0, 3], "frame_by_index": [[0.35, 0.35], [0.37, 0.45], [0.39, 0.55], [0.41, 0.65], [0.43, 0.75], [0.45, 0.85]],
		"frame_rate": 10.0,
		"blend": "add", "overbright": 4.0, "tint": Color8(194, 168, 142), "max_screen": 0.35,
		"count": 6, "life": [0.05, 0.075], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[0.0, 0.0], [0.52, 2.6], [1.04, 5.2], [1.56, 7.8], [2.08, 10.4], [2.6, 13.0]],  # position (13s, s, s), s = u*i/5, one u in [0.2, 1] per burst
		"yz_by_index": [[0.0, 0.0], [0.04, 0.2], [0.08, 0.4], [0.12, 0.6], [0.16, 0.8], [0.2, 1.0]],
		"half_by_index": [[1.792, 2.39], [2.042, 4.053], [2.31, 4.424], [2.434, 4.424], [1.788, 4.424], [1.283, 4.424]],
		"alpha": [0.1961, 0.3922], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-120.0, -60.0], "roll_flip": true,
		"inherit_vel": 1.0, "follow": true,
	},
	# uweapon_muzzleflash_pist_fire_revolver (main pass is the wispy_steam_burst_b renderer; the fire_gas_batch_b one is bloom-only)
	"rev_fire": {
		"kind": "sprite", "tex": "wispy_steam_burst_b", "seq": [0, 3], "frame_by_index": [[0.35, 0.35], [0.37, 0.45], [0.39, 0.55], [0.41, 0.65], [0.43, 0.75], [0.45, 0.85]],
		"frame_rate": 4.0,
		"blend": "add", "overbright": 4.0, "tint": Color8(205, 133, 63), "max_screen": 0.35,
		"count": 6, "life": [0.05, 0.1], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[0.0, 0.0], [0.52, 2.6], [1.04, 5.2], [1.56, 7.8], [2.08, 10.4], [2.6, 13.0]], "yz_by_index": [[0.0, 0.0], [0.04, 0.2], [0.08, 0.4], [0.12, 0.6], [0.16, 0.8], [0.2, 1.0]],
		"half_by_index": [[4.78, 9.559], [5.445, 16.213], [6.159, 17.696], [6.49, 17.696], [4.767, 17.696], [3.422, 17.696]],  # x remap(CP3 0..1 -> 1..0.5) per flash
		"grow": [0.5, 1.0],
		"alpha": [0.1961, 0.3922], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-120.0, -60.0], "roll_flip": true,
		"vel_fwd": [50.0, 250.0],
		"follow": true,  # PositionLock strength = CP3 (0 or 1 in every config used)
		"follow_release": 0.25,
	},
	# uweapon_muzflsh_deagle_primaryflash (the world Deagle flame; radius x remap(CP3 0..1 -> 2..1), alpha x remap(CP3 -> 0.25..0))
	"deagle_fire": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "tex_mv": "fire_small_sim_b_top_mv", "seq": [0, 3], "frame": [0.58, 0.62], "frame_rate": 2.0,
		"blend": "add", "overbright": 4.0,
		"count": 8,  # m_nInitialParticles 8, no emitter
		"life": [0.056, 0.075], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[15.0, 15.0], [17.785, 19.456], [20.227, 23.363], [22.496, 26.994], [24.827, 30.723], [27.5, 35.0], [27.5, 35.0], [27.5, 35.0]],  # x = 15 + 25*u*c(i), one u in [0.5, 0.8] per burst; indices 5-7 share c = 1
		"half_by_index": [[8.0, 8.0], [3.992, 6.11], [3.59, 3.851], [3.555, 3.634], [3.555, 3.681], [3.586, 3.718], [3.586, 3.718], [3.586, 3.718]], "grow": [1.0, 1.5],
		"alpha": [0.7059, 0.7843], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-180.0, -120.0],
		"vel_fwd": [60.0, 60.0], "follow": true,
	},
	# uweapon_muzflsh_deagle_primaryflash_fps (first-person Deagle flame; radius x remap(CP3 0..1 -> 2..0.75))
	"deagle_fire_fp": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "tex_mv": "fire_small_sim_b_top_mv",
		"tex_layers": [["particle_ring_wave_8", 1.0]],  # inferred: third texture layer has no blend parameters; weight 1 assumed
		"seq": [0, 3], "frame": [0.58, 0.62], "frame_rate": 2.0,
		"blend": "add", "overbright": 4.0,
		"count": 8, "life": [0.056, 0.075], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[15.0, 15.0], [17.785, 19.456], [20.227, 23.363], [22.496, 26.994], [24.827, 30.723], [27.5, 35.0], [27.5, 35.0], [27.5, 35.0]],
		"half_by_index": [[8.0, 8.0], [3.992, 6.11], [3.59, 3.851], [3.555, 3.634], [3.555, 3.681], [3.586, 3.718], [3.586, 3.718], [3.586, 3.718]], "grow": [1.0, 1.5],
		"alpha": [0.1765, 0.1961],  # 0.7059..0.7843 x renderer alpha scale 0.25
		"color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-180.0, -120.0],
		"vel_fwd": [60.0, 60.0], "follow": true, "follow_release": 0.25,
	},
	# uweapon_muzzleflash_subm_fire (radius and alpha2 x remap(CP3 0..1 -> 1..0.5))
	"subm_fire": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "seq": [0, 3], "frame": [0.55, 0.66], "frame_rate": 10.0,
		"blend": "add", "overbright": 2.0,
		"count": 6, "life": [0.05, 0.075], "bias": {"life": -0.0526}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[3.0, 3.0], [3.78, 4.56], [4.464, 5.927], [5.099, 7.198], [5.751, 8.503], [6.5, 10.0]],
		"half_by_index": [[1.914, 2.871], [3.619, 5.924], [2.678, 5.509], [1.964, 4.911], [1.862, 4.206], [1.862, 3.55]],  # renderer radius scale 0.5 applied
		"grow": [1.0, 2.0],
		"alpha": [0.3529, 0.3922],  # 0.7059..0.7843 x renderer alpha scale 0.5
		"alpha2": 1.0,  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-30.0, 120.0], "roll_flip": true,
		"inherit_vel": 1.0, "follow": true,
	},
	# uweapon_muzzleflash_subm_fire_alt (its wispy_steam_burst layer is off in the main pass)
	"subm_fire_alt": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "seq": [0, 3], "frame_by_index": [[0.35, 0.35], [0.36, 0.45], [0.37, 0.55], [0.38, 0.65], [0.39, 0.75], [0.4, 0.85]],
		"frame_rate": 10.0,
		"blend": "add", "overbright": 4.0, "tint": Color8(205, 133, 63), "max_screen": 0.35,
		"count": 6,  # emits 8, m_nMaxParticles 6
		"life": [0.052, 0.075], "bias": {"life": -0.2105}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[0.0, 0.0], [0.3, 3.0], [0.6, 6.0], [0.9, 9.0], [1.2, 12.0], [1.5, 15.0]], "yz_by_index": [[0.0, 0.0], [0.02, 0.2], [0.04, 0.4], [0.06, 0.6], [0.08, 0.8], [0.1, 1.0]],
		"half_by_index": [[2.574, 3.432], [3.217, 7.514], [3.936, 7.514], [3.534, 7.514], [2.645, 7.514], [1.683, 7.514]],
		"alpha": [0.3529, 0.3922],  # 0.7059..0.7843 x renderer alpha scale 0.5
		"alpha2": 1.0,  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-120.0, -60.0], "roll_flip": true,
		"inherit_vel": 1.0, "follow": true,
	},
	# uweapon_muzflsh_ak47_primaryflash = uweapon_muzflsh_shot_primaryflash (GlobalScale CP5, shotgun copy CP1)
	"rifle_fire": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "seq": [0, 3], "frame": [0.55, 0.66], "frame_rate": 5.0,
		"blend": "add", "overbright": 4.0,
		"count": 6,  # emits 8, m_nMaxParticles 6; the shotgun copy emits remap(CP1 0.5..1 -> 1..4)
		"life": [0.05, 0.05], "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[3.0, 3.0], [4.894, 6.788], [6.554, 10.109], [8.098, 13.195], [9.682, 16.364], [11.5, 20.0]],
		"half_by_index": [[2.318, 3.477], [4.504, 7.629], [4.286, 7.629], [3.239, 7.33], [2.284, 6.633], [1.373, 5.831]],
		"alpha": [0.2353, 0.5882], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216),
		"roll": [-30.0, 120.0],  # the file: RANDOM_UNIFORM -30..120 with sign flip (fps report right; world report's -120..120 is wrong)
		"roll_flip": true,
		"vel_fwd": [100.0, 150.0], "inherit_vel": 1.0, "drag": 0.2, "follow": true,
	},
	# uweapon_muzflsh_ak47_primaryflash_alt = mach_/shot_primaryflash_alt (GlobalScale CP5; mach/shot CP1)
	"rifle_fire_alt": {
		"kind": "sprite", "tex": "wispy_steam_burst_b", "seq": [0, 3], "frame_by_index": [[0.35, 0.35], [0.36, 0.45], [0.37, 0.55], [0.38, 0.65], [0.39, 0.75], [0.4, 0.85]],
		"frame_rate": 9.0,
		"blend": "add", "overbright": 4.0, "tint": Color8(205, 133, 63), "max_screen": 0.35,
		"count": 6,  # emits 8, m_nMaxParticles 6; mach/shot copies emit remap(CP1 0.5..1 -> 1..8), still capped at 6
		"life": [0.05, 0.095], "bias": {"life": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x_by_index": [[0.0, 0.0], [0.3, 3.0], [0.6, 6.0], [0.9, 9.0], [1.2, 12.0], [1.5, 15.0]], "yz_by_index": [[0.0, 0.0], [0.02, 0.2], [0.04, 0.4], [0.06, 0.6], [0.08, 0.8], [0.1, 1.0]],
		"half_by_index": [[2.574, 3.432], [3.217, 7.514], [3.936, 7.514], [3.534, 7.514], [2.645, 7.514], [1.683, 7.514]],
		"alpha": [0.7059, 0.7843], "color_min": Color8(198, 131, 80), "color_max": Color8(216, 216, 216), "roll": [-120.0, -60.0], "roll_flip": true,
		"vel_fwd": [50.0, 50.0],  # inferred: the reports disagree (fps 550, world 50); the .vpcf authors 500 on the sphere, then RemapScalarToVector re-sets the position and only the later VelocityRandom 50 is kept, as in the world report
		"inherit_vel": 1.0, "drag": 0.2, "follow": true,
	},
	# uweapon_muzflsh_aug_primaryflash (GlobalScale CP5; radius x remap(CP3 0..1 -> 1..0.5))
	"aug_fire": {
		"kind": "sprite", "tex": "fire_small_sim_b", "seq": [0, 3],
		"frame": [0.55, 0.6],  # 0.55..0.6 at birth then +3/s (world report's 0.55..0.72 is the end of life, not the start)
		"frame_rate": 3.0,
		"blend": "add", "overbright": 2.0, "tint": Color8(138, 138, 138),
		"count": 12, "life": [0.056, 0.056], "fade_frac": [0.5, 0.5], "fade_ease": true,
		"x_by_index": [[3.0, 3.0], [3.61, 4.22], [4.219, 5.438], [4.785, 6.57], [5.306, 7.612], [5.809, 8.618], [6.303, 9.605], [6.796, 10.593], [7.3, 11.6], [7.826, 12.652], [8.406, 13.812], [9.0, 15.0]],
		"half_by_index": [[3.327, 4.991], [6.901, 10.603], [6.424, 10.597], [5.728, 10.302], [5.195, 9.784], [4.645, 9.227], [4.112, 8.781], [3.62, 8.426], [3.2, 8.04], [2.849, 7.619], [2.514, 7.143], [2.164, 6.654]],
		"grow": [0.75, 1.2], "grow_bias": 0.65,
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(216, 216, 216), "roll": [-30.0, 120.0], "roll_flip": true,
		"follow": true,
	},
	# uweapon_muzflsh_awp_primaryflash (radius x remap(CP1 0..1 -> 0.85..0.3))
	"snip_fire": {
		"kind": "sprite", "tex": "fire_gas_batch_b_top", "tex_layers": [["particle_ring_wave_8", 0.5]], "seq": [0, 2],
		"frame": [0.85, 0.95],  # frame = frame * Bias(age/life, 0.83)
		"frame_age_bias": 0.83,
		"blend": "add", "overbright": 4.0, "tint": Color8(157, 157, 157), "feather": 30.0, "screen_fade": [0.1, 0.15],
		"count": 4, "life": [0.15, 0.2], "bias": {"life": -0.1053}, "fade_frac": [0.8, 1.0], "fade_ease": true,
		"x": [1.0, 1.0],  # sphere radius 1 biased fully onto +X, then offset (0, 0..1, -1..1): the fps report is right, the world report's x -1..1 is not
		"y": [0.0, 1.0], "z": [-1.0, 1.0],
		"half_by_index": [9.3, 9.958, 5.873, 5.478],  # curve at index 0..3 read exactly (fps report right; world report's 9.7/6.3/5.8 are off)
		"grow": [0.5, 1.5], "grow_bias": 0.8,
		"alpha": [0.4706, 0.7059],
		"alpha2_by_index": [1.0, 0.5883, 0.5972, 0.8162],  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255), "color_end": Color8(252, 163, 111), "color_end_from": 0.0, "color_end_to": 1.0,
		"roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd_by_index": [100.0, 233.3, 366.7, 500.0],  # inferred: VelocityFromNormal sets v = normal * 10, normal scaled lerp(10, 50, i/3) (world report right; fps report's 10 u/s misses the normal scaling); replaces the sphere's -50..10 radial speed
		"accel_fwd": -100.0, "gravity": -90.0, "drag": 0.3, "follow": true, "follow_release": 0.5,
	},
	# weapons/cs_weapon_fx/weapon_taser_glow
	"taser_glow": {
		"kind": "sprite", "tex": "particle_glow_04",
		"blend": "add", "overbright": 1.0, "max_dist": 1000.0,
		"count": 3,  # continuous 30/s for 0.1 s
		"emit_rate": 30.0, "emit_for": 0.1, "life": [0.1, 0.2], "fade_out": [0.1, 0.1], "fade_ease": true,
		"sphere": 2.0,
		"half": [1.0, 2.0], "grow": [0.25, 12.0],
		"alpha": [1.0, 1.0], "color_min": Color8(89, 105, 255), "color_max": Color8(89, 105, 255), "roll": [0.0, 360.0], "roll_flip": true,
		"follow": true, "follow_rot": false,
	},
	# uweapon_muzzleflash_pist_beam (radius x remap(CP3 0.25..0.5 -> 0.5..1), trail x remap(CP3 0.25..0.5 -> 0.55..1))
	"pist_beam": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.212, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 3.0, "max_length": 60.0,
		"count": 1, "delay": 0.0075, "life": [0.025, 0.055], "bias": {"life": -0.1053, "half": -0.1579, "trail_time": -0.025}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [-2.0, -2.0], "ring": 0.1, "star": [5, 5], "ring_pitch": 90.0,
		"half": [1.0, 3.0], "grow": [0.5, 1.0], "grow_bias": 0.8,
		"trail_time_shared": [0.1, 0.15],  # one value per burst (InitFloatCollection replaces the per-particle 0.1..0.2)
		"trail_rate": 4.0, "length": [6.0, 13.5],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-90.0, -60.0], "follow": true,
	},
	# uweapon_muzsilenced_subm_beam
	"sil_beam": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.212, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 3.0, "max_length": 60.0,
		"count": 4, "delay": 0.0075, "life": [0.025, 0.055], "bias": {"life": -0.1053, "half": -0.1579, "trail_time": -0.025}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [-2.0, -2.0], "ring": 0.1, "star": [5, 5], "ring_pitch": 90.0,
		"half": [1.0, 2.0],
		"grow": [0.5, 0.5],  # InterpolateRadius 0.5 -> 0.5: drawn at half its radius all life
		"trail_time_shared": [0.2, 0.45], "trail_rate": 4.0, "length": [6.0, 27.0],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-60.0, -30.0], "follow": true,
	},
	# uweapon_muzzleflash_subm_beam (radius x remap(CP3 0..1 -> 1..0.75), trail x remap(CP3 -> 1..0.3))
	"subm_beam": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.212, 0.302], "frame_rate": 8.0,
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 3.0, "min_length": 5.0, "max_length": 30.0,
		"count": 4, "delay": 0.0075, "life": [0.025, 0.055], "bias": {"life": -0.1053, "half": -0.1579, "trail_time": -0.025}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [-2.0, -2.0], "ring": 0.1, "star": [5, 5], "ring_pitch": 90.0,
		"half": [2.0, 5.0], "grow": [0.5, 1.0], "grow_bias": 0.8, "trail_time_shared": [0.2, 0.45], "trail_rate": 4.0, "length": [9.22, 24.34],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-30.0, -10.0], "vel_out": [-45.0, -45.0], "follow": true,
	},
	# uweapon_muzflsh_aug_primarybeam (GlobalScale CP5) = mach_/shot_primarybeam (count remap(CP1 0.5..1 -> 1..3), no delay, no GlobalScale; the shot copy has no PositionLock)
	"beam3": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 2.0,
		"count": 3, "delay": 0.0075, "life": [0.055, 0.056], "bias": {"trail_time": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [0.0, 0.0],
		"half": [1.0, 1.0], "grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.1, 0.25], "trail_rate": 2.0, "length": [8.5, 26.25],
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-105.0, -85.0],  # sphere LocalCoordinateSystemSpeed -75 plus VelocityRandom -30..-10
		"follow": true,
	},
	# uweapon_muzflsh_gen_beam (Deagle; beam3 with life 0.025..0.055 and PositionLock strength = CP3)
	"gen_beam": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 2.0,
		"count": 3, "delay": 0.0075, "life": [0.025, 0.055], "bias": {"trail_time": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [0.0, 0.0],
		"half": [1.0, 1.0], "grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.1, 0.25], "trail_rate": 2.0, "length": [8.5, 26.25],
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-105.0, -85.0], "follow": true, "follow_release": 0.25,
	},
	# uweapon_muzflsh_ak47_compensator_flash = mach_/shot_compensator_flash (GlobalScale CP5; mach/shot CP1, ring 2..4 per orbit)
	"comp_side": {
		"kind": "trail", "tex": "wispy_steam_set",
		"tex_v_scale": -1.5,  # texture V scale -1.5, offset 1
		"seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 3.0, "head": Color8(0, 0, 0), "tail": Color8(234, 144, 48), "tail_taper": 20.0, "head_taper": 5.0, "max_length": 20.0,
		"count": 2, "delay": 0.0075, "life": [0.05, 0.05], "bias": {"trail_time": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [0.0, 0.0], "ring": 0.1, "star": [3, 4], "ring_pitch": 90.0,
		"half_by_index": [0.0, 1.0],  # the last radius initializer writes the particle index (0, 1): only the second streak shows
		"grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.4, 0.6], "trail_rate": 4.0, "length": [8.94, 20.0],
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-30.0, -10.0], "vel_out": [-25.0, -20.0], "follow": true,
	},
	# uweapon_muzflsh_deagle_compensator_flash (count remap(CP3 0..1 -> 2..0), PositionLock strength = CP3)
	"deagle_comp": {
		"kind": "trail", "tex": "wispy_steam_set", "tex_v_scale": -1.5, "seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 3.0, "head": Color8(0, 0, 0), "tail": Color8(234, 144, 48), "tail_taper": 20.0, "head_taper": 5.0, "max_length": 20.0,
		"count": 2, "delay": 0.0075, "life": [0.055, 0.075], "bias": {"trail_time": -0.1579},
		"fade_out": [0.015, 0.25],  # FadeOut min 0.015, max left at the 0.25 default, not proportional: longer than life, so it fades from birth
		"fade_ease": true,
		"x": [0.0, 0.0], "ring": 0.1, "star": [3, 4], "ring_pitch": -45.0,
		"half_by_index": [0.0, 1.0], "grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.4, 0.6], "trail_rate": 4.0, "length": [18.44, 20.0],
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-50.0, -30.0], "vel_out": [-45.0, -35.0], "follow": true, "follow_release": 0.25,
	},
	# uweapon_muzflsh_aug_compensator_flash (GlobalScale CP5)
	"aug_comp": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 2.0,
		"count": 5, "delay": 0.0075, "life": [0.055, 0.075], "bias": {"half": -0.1579, "trail_time": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [-2.0, -2.0], "ring": 0.1, "star": [5, 5], "ring_pitch": 90.0,
		"half": [1.0, 3.0], "grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.2, 0.35], "trail_rate": 2.0, "length": [4.47, 13.67],
		"alpha": [0.7059, 0.7843], "color_min": Color8(219, 186, 141), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-30.0, -10.0], "vel_out": [-25.0, -20.0], "follow": true,
	},
	# uweapon_muzzleflash_rifl_break (GlobalScale CP5)
	"rifl_break": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.212, 0.302],
		"blend": "add", "overbright": 4.0, "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "max_length": 30.0,
		"count": 4, "delay": 0.0075, "life": [0.055, 0.055], "bias": {"half_shared": -0.025, "trail_time_shared": -0.025}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [-2.0, -2.0], "ring": 0.1, "star": [4, 5], "ring_pitch": 90.0,
		"half_shared": [2.0, 5.0],  # half = shared(one per burst) * half_scale(per particle); likewise trail_time
		"half_scale": [0.26, 0.344],  # RANDOM_UNIFORM 0.5..1.2 remapped 0..5 -> 0.2..0.8
		"grow": [0.5, 1.25], "grow_bias": 0.8, "trail_time_shared": [0.2, 0.4], "trail_scale": [0.29, 0.38], "trail_rate": 4.0, "length": [1.3, 5.94],
		"alpha": [1.0, 1.0], "color_min": Color8(217, 230, 238), "color_max": Color8(240, 242, 243),
		"vel_fwd": [-30.0, -10.0], "vel_out": [-25.0, -20.0], "follow": true,
	},
	# weapon_muzzleflash_awp_flare
	"awp_flare": {
		"kind": "trail", "tex": "wispy_steam_set", "seq": [0, 3], "frame": [0.278, 0.302],
		"blend": "add", "overbright": 4.0, "screen_fade": [0.05, 0.1], "head": Color8(65, 65, 65), "tail": Color8(255, 165, 0), "tail_taper": 2.0,
		"count": 2, "delay": 0.0075, "life": [0.025, 0.055], "bias": {"half": -0.1579, "trail_time": -0.1579}, "fade_out": [0.015, 0.015], "fade_ease": true,
		"x": [0.0, 0.0], "ring": 0.1, "star": [3, 3], "ring_pitch": 90.0,
		"half": [2.0, 5.0], "grow": [0.0, 1.0], "grow_bias": 0.8, "trail_time": [0.1, 0.15], "trail_rate": 4.0, "length": [2.24, 5.86],
		"alpha": [0.7059, 0.7843], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"vel_fwd": [-30.0, -10.0], "vel_out": [-25.0, -20.0], "follow": true,
	},
	# uweapon_muzzleflash_pist_spark (life x remap(CP1 0..1 -> 1..0.5))
	"spark_pist": {
		"kind": "spark", "tex": "spark",
		"blend": "add", "overbright": 4.0, "passes": [{"length_scale": 3.0, "width": 5.0, "tail_taper": 0.5, "length_fade_in": 0.5, "max_length": 10.0, "max_screen": 0.0075}],
		"count": [8, 16], "count_cap": 12, "per_frame": 2, "life": [0.1, 0.25], "bias": {"life": -0.6053},
		"sphere": 1.5, "sphere_bias": Vector3(1.0, 0.5, 0.5), "sphere_fwd_only": true,
		"half": [0.125, 0.25], "grow": [10.0, 1.0], "trail_time": [0.025, 0.025],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 140, 0), "color_max": Color8(178, 34, 34), "color_end": Color8(0, 0, 0), "color_end_from": 0.25, "color_end_to": 1.0,
		"vel_fwd": [300.0, 551.0],  # sphere speed 100..150 plus velocity noise 200..401 (noise taken as uniform: inferred)
		"vel_side": [-300.0, 200.0],  # noise -300..200 left, -300..150 up: not symmetric (fps report right; world report's +-300 is not)
		"vel_up": [-300.0, 150.0], "gravity": -500.0, "drag": 0.1, "cull": [0.6, 0.5],
	},
	# uweapon_muzzleflash_subm_spark (life x remap(CP1 0..1 -> 1..0.25))
	"spark_subm": {
		"kind": "spark", "tex": "spark",
		"blend": "add", "overbright": 4.0, "passes": [{"length_scale": 3.0, "width": 5.0, "tail_taper": 0.5, "length_fade_in": 0.5, "max_length": 10.0, "max_screen": 0.01}],
		"count": [5, 12], "count_cap": 12, "per_frame": 2, "life": [0.05, 0.4], "bias": {"life": -0.6053},
		"sphere": 1.5, "sphere_bias": Vector3(1.0, 0.5, 0.5), "sphere_fwd_only": true,
		"half": [0.125, 0.25], "trail_time": [0.025, 0.025],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 140, 0), "color_max": Color8(178, 34, 34), "color_end": Color8(0, 0, 0), "color_end_from": 0.25, "color_end_to": 1.0,
		"vel_fwd": [300.0, 501.0], "vel_side": [-300.0, 200.0], "vel_up": [-300.0, 150.0], "gravity": -200.0, "drag": 0.1,
		"turbulence": [[6.0, 1000.0], [1.0, 2000.0]],  # C_OP_TurbulenceForce: [noise coord scale, amount] x2
		"cull": [0.6, 0.5],
	},
	# uweapon_muzflsh_gen_spark = uweapon_muzflsh_mach_spark
	"spark_rifle": {
		"kind": "spark", "tex": "spark",
		"blend": "add", "overbright": 4.0,
		"passes": [{"length_scale": 2.0, "width": 1.0, "length_fade_in": 0.1}, {"length_scale": 3.0, "width": 5.0, "tail_taper": 0.5, "length_fade_in": 0.5}],  # both trail renderers are main-pass (world report kept only one)
		"count": [4, 12], "count_cap": 12, "life": [0.05, 0.65],
		"age_start": [0.0, 0.8],  # inferred: C_INIT_AgeNoise read as a start age of 0..0.8 of life
		"bias": {"life": -0.6053},
		"sphere": 1.5, "sphere_bias": Vector3(1.0, 0.5, 0.5), "sphere_fwd_only": true,
		"half": [0.125, 0.25], "trail_time": [0.009, 0.016], "trail_time_zero_at": 0.65,
		"alpha": [1.0, 1.0], "color_min": Color8(255, 140, 0), "color_max": Color8(178, 34, 34), "color_end": Color8(0, 0, 0), "color_end_from": 0.25, "color_end_to": 1.0,
		"vel_fwd": [200.0, 401.0], "vel_side": [-300.0, 300.0], "vel_up": [-300.0, 300.0], "gravity": -500.0, "drag": 0.2, "cull": [0.6, 0.5],
	},
	# uweapon_muzflsh_shot_spark
	"spark_shot": {
		"kind": "spark", "tex": "spark",
		"blend": "add", "overbright": 4.0, "passes": [{"length_scale": 2.0, "width": 1.0, "length_fade_in": 0.1, "max_length": 10.0}, {"length_scale": 3.0, "width": 5.0, "tail_taper": 0.5, "length_fade_in": 0.1, "max_length": 10.0}],
		"count": [8, 12], "count_cap": 12, "life": [0.05, 0.25], "bias": {"life": -0.0953},
		"sphere": 1.5, "sphere_bias": Vector3(1.0, 0.5, 0.5), "sphere_fwd_only": true,
		"half": [0.125, 0.5], "trail_time": [0.01, 0.02],
		"alpha": [1.0, 1.0], "color_min": Color8(255, 140, 0), "color_max": Color8(178, 34, 34), "color_end": Color8(0, 0, 0), "color_end_from": 0.25, "color_end_to": 1.0,
		"vel_fwd": [200.0, 551.0], "vel_side": [-300.0, 300.0], "vel_up": [-300.0, 300.0], "gravity": -500.0, "drag": 0.2, "curl_freq": 0.15,
	},
	# weapon_muzzleflash_awp_spark
	"spark_awp": {
		"kind": "spark", "tex": "spark",
		"blend": "add", "overbright": 4.0, "passes": [{"length_scale": 1.0, "width": 1.0, "max_length": 10.0}, {"length_scale": 3.0, "width": 5.0, "tail_taper": 0.5, "max_length": 10.0}],
		"count": [9, 12], "count_cap": 12, "per_frame": 12, "life": [0.15, 0.4],
		"age_start": [0.0, 0.8],  # inferred: C_INIT_AgeNoise read as a start age of 0..0.8 of life
		"bias": {"life": -0.0526},
		"sphere": 1.5, "sphere_bias": Vector3(1.0, 0.5, 0.5), "sphere_fwd_only": true,
		"half": [0.125, 0.25],
		"trail_time_curve": [[0.0, 0.0], [0.2, 0.0013], [0.4, 0.0029], [0.5, 0.0087], [0.5828, 0.0178], [0.62, 0.0304], [0.66, 0.0556], [0.7, 0.0844], [0.7243, 0.1], [1.0, 0.1]],  # [age/life, trail seconds], CS2 spline sampled
		"alpha": [1.0, 1.0], "color_min": Color8(255, 140, 0), "color_max": Color8(255, 255, 255), "color_end": Color8(0, 0, 0), "color_end_from": 0.25, "color_end_to": 1.0,
		"vel_fwd": [300.0, 600.0], "vel_side": [-150.0, 150.0], "vel_up": [-150.0, 150.0], "gravity": 0.0, "drag": 0.2, "cull": [0.6, 0.5],
	},
	# uweapon_muzzleflash_pist_smoke (life x remap(CP3 0.25..0.5 -> 0..0.5))
	"smoke_pist": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "seq": [0, 1], "seq2": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.15, "shadows": true, "feather": true, "max_screen": 0.5, "screen_fade": [0.1, 0.5],
		"count": 3,
		"life_by_index": [0.2343, 0.7068, 0.3717],  # curve at normalized index -1/0/1: 0.2343, 0.7068, 0.3717 (fps report right; world report's 0.676 is off)
		"sphere": 0.5, "sphere_bias": Vector3(4.0, 1.0, 1.0),
		"half_by_index": [3.0, 5.0, 7.0],  # inferred: PARTICLE_NUMBER_NORMALIZED divides the index by (emitted count - 1), here 3/5/7
		"radius_rate": [[60.0, 0.0, 0.15], [30.0, 0.0, 1000.0]],
		"alpha": [0.2353, 0.4706], "alpha_curve": [[0.0, 0.0], [0.1, 0.3333], [0.2338, 0.8807], [0.35, 0.7347], [0.45, 0.4522], [0.5478, 0.2424], [0.7, 0.1075], [0.85, 0.0359], [1.0, 0.0]],
		"color_min": Color8(146, 140, 140), "color_max": Color8(111, 110, 110), "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd_by_index": [[100.0, 200.0], [400.0, 500.0], [700.0, 800.0]],  # sphere speed 50/350/650 by index plus VelocityRandom 50..150; MaxVelocity then caps all at 150
		"vel_side": [-60.0, 60.0], "vel_up": [-60.0, 60.0], "max_speed": 150.0, "gravity": 40.0, "drag": 0.25, "curl": 150.0, "wind": 35.0,
	},
	# uweapon_muzzleflash_revolver_smoke
	"smoke_rev": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "seq": [0, 1], "seq2": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": true, "screen_fade": [0.3, 0.4],
		"count": 4,  # inferred: highest particle detail (LOD3); count_by_detail lists LOD0..3
		"count_by_detail": [2, 2, 4, 4], "life": [0.5, 1.0], "bias": {"life": -0.1053}, "fade_out": [0.8, 1.0], "fade_ease": false,
		"x_by_index": [0.0, 5.0, 10.0, 15.0],
		"half": [4.0, 9.0],  # C_INIT_CreationNoise 4..9 (spatial noise, drawn as uniform)
		"grow": [1.0, 5.0], "grow_bias": 0.8,
		"alpha": [0.2353, 0.4706], "color_min": Color8(211, 201, 201), "color_max": Color8(173, 173, 173),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end < start read as a birth tint fading back by 10% of life
		"birth_tint_until": 0.1, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd": [150.0, 500.0], "max_speed": 250.0, "gravity": 40.0, "drag": 0.2, "wind": 35.0,
	},
	# uweapon_muzsilenced_subm_smoke (life x remap(CP1 0..1 -> 0.5..1))
	"smoke_sil": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix",
		"tex_layers": [["wispy_steam_set", [[0.0, 0.5725], [0.1, 0.696], [0.2638, 0.8075], [0.5, 0.6056], [0.75, 0.3036], [1.0, 0.0]]]],  # [texture, blend curve [collection age s, weight]], MIX_A
		"seq": [0, 3],  # the sheet has 2 sequences; CS2 draws 0..3 (inferred: wraps)
		"frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": true, "screen_fade": [0.1, 0.65],
		"count": 1, "life": [0.3, 0.85], "bias": {"life": -0.2105}, "fade_out": [0.8, 1.0], "fade_ease": false,
		"x": [0.0, 4.0],  # inferred: sphere 0.5 (bias 4,1,1) warped x1..2 then offset 1..3 / +-1 (the reports gave 1..3 and 1..6)
		"side": 1.25,
		"half": [8.0, 16.0],
		"radius_add_curve": [[0.0, 0.0], [0.25, 4.0723], [0.5, 8.1479], [0.7491, 14.9074], [1.0, 23.6459], [1.5, 37.7972], [2.0, 44.7228]],  # [age s, units added to the particle radius]; drawn half = half + 2 * curve(age). The later SetFloat ADD_TO_INITIAL overwrites InterpolateRadius x1->x3, so the world report is right and the fps report's x3 growth is not drawn
		"alpha": [0.4706, 0.9412], "color_min": Color8(211, 222, 232), "color_max": Color8(168, 168, 168),
		"birth_tint": Color8(226, 226, 226),  # inferred: ColorInterpolate with end time 0 before start 0.50 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.5, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd": [100.0, 150.0], "max_speed": 100.0, "gravity": -60.0, "drag": 0.15, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzzleflash_subm_smoke
	"smoke_subm": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", [[0.0, 1.0], [0.1, 0.9642], [0.2244, 0.8646], [0.35, 0.5927], [0.5, 0.202]]]],
		"seq": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": true, "screen_fade": [0.3, 0.65],
		"count": 4,  # inferred: highest particle detail (LOD3); count_by_detail lists LOD0..3
		"count_by_detail": [1, 2, 3, 4], "life": [0.2, 1.0], "bias": {"life": -0.454}, "fade_out": [0.8, 1.0], "fade_ease": false,
		"x": [0.0, 4.0],  # inferred: sphere 0.5 warped then offset 1..3 / +-1
		"side": 1.25,
		"half": [3.0, 8.0], "grow": [1.0, 4.0], "grow_bias": 0.85,
		"alpha": [0.2353, 0.6], "color_min": Color8(184, 196, 199), "color_max": Color8(111, 110, 110), "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd": [150.0, 450.0], "inherit_vel": 1.0, "max_speed": 200.0, "gravity": 40.0, "drag": 0.15, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzflsh_gen_smoke (GlobalScale CP5; life x remap(CP3 0..1 -> 1..0.5); alpha2 = remap(CP3 -> 1..0.25))
	"smoke_rifle": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", [[0.0, 1.0], [0.1, 0.9642], [0.2244, 0.8646], [0.35, 0.5927], [0.5, 0.202]]]],
		"seq": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.0, "shadows": true, "shadow_density": 2.0, "feather": true, "screen_fade": [0.1, 0.65],
		"count": 2,
		"life": [0.2, 0.5],  # C_OP_Decay runs at a random strength 0.35..1, which may keep some puffs a little past their life (not modelled)
		"bias": {"life": -0.1053}, "fade_frac": [0.8, 1.0], "fade_ease": true,
		"x": [0.0, 4.0],  # inferred: sphere 0.5 warped then offset 1..3 / +-1 (world report's 1..6 is off)
		"side": 1.25,
		"half": [4.0, 7.0], "grow": [2.0, 4.0], "grow_bias": 0.95,
		"alpha": [0.15, 0.3],
		"alpha2": 1.0,  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end time 0 before start 0.30 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.3, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd": [100.0, 450.0],  # sphere 50..100 plus VelocityRandom 50..350
		"max_speed": 450.0, "gravity": 40.0, "drag": 0.35, "force_fwd": [112.5, 450.0],
		"force_side": [-450.0, -112.5],  # PerParticleForce (450, -450, 0) x U(0.25, 1): forward and to the right
		"curl": 150.0,
	},
	# uweapon_muzflsh_deagle_gen_smoke (life = remap(CP3 0..1 -> 1..0.2), replacing its own 0.5..0.75)
	"smoke_deagle": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix",
		"tex_layers": [["wispy_steam_burst_b", 0.5], ["particle_ring_wave_8", [[0.2, 0.0], [0.5, 1.0]]]],  # wispy blend is a literal 0.5 (its leftover flat curve is not applied to a literal: inferred); ring_wave MIX_A_RGBALPHA blended in over collection age 0.2..0.5 s
		"seq": [0, 1], "seq2": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": 30.0, "screen_fade": [0.3, 0.5],
		"count": 3,  # emits 4, m_nMaxParticles 3
		"life": [1.0, 1.0], "fade_frac": [0.8, 1.0], "fade_ease": true,
		"x": [1.0, 1.0],
		"half_by_index": [4.101, 6.347, 10.152],  # curve at index 0..2 read exactly: 4.10 / 6.35 / 10.15 (fps report right; world report's 6.5 / 10.1 are off)
		"grow": [0.0, 4.0], "grow_bias": 0.85,
		"alpha": [0.4706, 0.4706],
		"alpha2_by_index": [0.1212, 0.3315, 0.5885],  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end time 0 before start 0.20 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.2, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd_by_index": [200.0, 400.0, 400.0],  # inferred: VelocityFromNormal 20 on a normal scaled lerp(10, 50, i/3), capped by MaxVelocity 400 (world report right; fps report's 20 + 10 u/s misses the normal scaling)
		"max_speed": 400.0, "gravity": 40.0, "drag": 0.2, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzzleflash_rifl_smoke (life x CP5)
	"smoke_rifle_lrg": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "seq": [0, 1], "seq2": [0, 3], "frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": true, "screen_fade": [0.1, 0.65],
		"count": 2, "life": [0.35, 0.65], "bias": {"life": -0.1053}, "fade_out": [0.8, 1.0], "fade_ease": false,
		"x_by_index": [0.0, 10.0],
		"half": [4.0, 9.0], "grow": [1.0, 3.0], "grow_bias": 0.8,
		"alpha": [0.2353, 0.4706], "color_min": Color8(146, 140, 140), "color_max": Color8(111, 110, 110), "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd": [250.0, 500.0], "max_speed": 250.0, "gravity": 40.0, "drag": 0.15, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzflsh_shot_smoke (count remap(CP1 0.75..1 -> 3..4); life = curve(CP1); GlobalScale CP1; alpha2 = remap(CP3 0..1 -> 0.75..1))
	"smoke_shot": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc", "tex_mv": "smokeloop_i_0_flwmix", "seq": [0, 3], "seq2": [0, 3], "frame_age_bias": 0.815,
		"blend": "alpha", "self_illum": 0.0, "feather": true, "screen_fade": [0.3, 0.65],
		"count": 4,
		"life": [1.0, 1.0],  # C_OP_Decay runs at a random strength 0.35..1 (not modelled); life = curve(CP1) replaces the per-index lifetime
		"bias": {"alpha": -0.17},
		"sphere": 0.5, "sphere_bias": Vector3(4.0, 1.0, 1.0),
		"half_by_index": [5.0, 8.333, 11.667, 15.0],  # remap(normalized index -> 5..15) x GlobalScale; inferred: normalized by (count - 1)
		"radius_rate": [[50.0, 0.0, 0.15], [30.0, 0.0, 1000.0]],
		"alpha": [0.3, 0.6], "alpha_curve": [[0.0, 1.0], [0.05, 0.8421], [0.1462, 0.3635], [0.25, 0.273], [0.4, 0.2572], [0.5478, 0.2424], [0.7, 0.156], [0.85, 0.06], [1.0, 0.0]],
		"alpha2": 1.0,  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end time 0 before start 0.15 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.15, "roll": [0.0, 360.0], "roll_flip": true, "roll_rate": 5.0,
		"vel_fwd_by_index": [[200.0, 300.0], [366.67, 466.67], [533.33, 633.33], [700.0, 800.0]],  # sphere speed 150..650 by normalized index plus VelocityRandom 50..150, x GlobalScale
		"vel_side": [-60.0, 60.0], "vel_up": [-60.0, 60.0], "gravity": -40.0, "drag": 0.25, "curl": 150.0, "wind": 10.0,
	},
	# uweapon_muzflsh_ssg08_leftbreak (radius and life x remap(CP1 0..1 -> 0.5..1.5); m_nViewModelEffect FALSE)
	"smoke_brake_l": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", 0.75]], "seq": [0, 1], "seq2": [0, 3],
		"frame_age_bias": 0.705,
		"blend": "alpha", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": 30.0, "screen_fade": [0.1, 0.2],
		"world_pass": true,  # drawn as a world effect even in first person
		"count": 4, "per_frame": 4, "life": [0.5, 1.0], "bias": {"life": -0.1053}, "fade_frac": [1.0, 1.0], "fade_ease": true,
		"x": [0.0, 0.0],
		"y": [1.0, 2.0],  # sphere radius 1 fully on +Y (left) / -Y (right), plus offset 0..1 left
		"z": [-1.0, 1.0],
		"half_by_index": [4.101, 8.407, 11.08, 14.056],  # curve at index 0..3 read exactly
		"grow": [0.0, 3.0], "grow_bias": 0.85,
		"alpha": [0.4706, 0.7059],
		"alpha2_by_index": [0.1212, 0.3315, 0.5885, 0.825],  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255), "roll": [0.0, 360.0], "roll_flip": true,
		"vel_side_by_index": [100.0, 233.3, 366.7, 400.0],  # inferred: VelocityFromNormal 10 on the +-Y normal scaled lerp(10, 50, i/3), capped 400 (world report right; fps report's 10 u/s misses the scaling)
		"max_speed": 400.0, "accel_fwd": [-250.0, -150.0],
		"accel_frame": "spawn",  # acceleration along CP3 = CP0's frame frozen at the shot
		"gravity": -90.0, "drag": 0.25, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzflsh_ssg08n_rightbreak (as the left one, thrown right, LIGHTEN blend)
	"smoke_brake_r": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", 0.75]], "seq": [0, 1], "seq2": [0, 3],
		"frame_age_bias": 0.705,
		"blend": "lighten", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": 30.0, "screen_fade": [0.1, 0.5],
		"world_pass": true,  # drawn as a world effect even in first person
		"count": 4, "per_frame": 3, "life": [0.5, 1.0], "bias": {"life": -0.1053}, "fade_frac": [1.0, 1.0], "fade_ease": true,
		"x": [0.0, 0.0],
		"y": [-1.0, 0.0],  # sphere radius 1 fully on +Y (left) / -Y (right), plus offset 0..1 left
		"z": [-1.0, 1.0],
		"half_by_index": [4.101, 9.127, 11.717, 13.557],  # curve at index 0..3 read exactly
		"grow": [0.0, 3.0], "grow_bias": 0.85,
		"alpha": [0.4706, 0.7059],
		"alpha2_by_index": [0.1212, 0.3315, 0.5885, 0.825],  # inferred: the renderer multiplies alpha by alpha2 (field 16)
		"color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end time 0 before start 0.15 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.15, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_side_by_index": [-100.0, -233.3, -366.7, -400.0],  # inferred: VelocityFromNormal 10 on the +-Y normal scaled lerp(10, 50, i/3), capped 400 (world report right; fps report's 10 u/s misses the scaling)
		"max_speed": 400.0, "accel_fwd": [-250.0, -150.0],
		"accel_frame": "spawn",  # acceleration along CP3 = CP0's frame frozen at the shot
		"gravity": -90.0, "drag": 0.25, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzflsh_g3sg1_smoke (count remap(CP1 0.5..1 -> 1..3); radius x remap(CP1 0..1 -> 1..1.5); life x remap(CP1 0.5..1 -> 0.25..1))
	"smoke_g3sg1": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", 0.75]], "seq": [0, 1], "seq2": [0, 3],
		"frame_age_bias": 0.705,
		"blend": "lighten", "self_illum": 0.0, "shadows": true, "shadow_density": 2.0, "feather": 30.0, "max_screen": 1.0, "screen_fade": [0.1, 0.65],
		"count": 3, "per_frame": 3, "life": [0.5, 1.0], "bias": {"life": -0.1053}, "fade_frac": [0.8, 1.0], "fade_ease": true,
		"x": [1.0, 1.0], "y": [0.0, 1.0], "z": [-1.0, 1.0],
		"half_by_index": [4.101, 9.127, 11.717], "grow": [0.0, 3.0], "grow_bias": 0.85,
		"alpha": [0.4706, 0.7059], "alpha2_by_index": [0.1212, 0.3315, 0.5885], "color_min": Color8(255, 255, 255), "color_max": Color8(255, 255, 255),
		"birth_tint": Color8(252, 186, 112),  # inferred: ColorInterpolate with end time 0 before start 0.15 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.15, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_fwd_by_index": [197.0, 298.0, 399.0],  # inferred: VelocityFromNormal 10 on the +X normal scaled lerp(10, 50, 0.2424 + 0.2525*i)
		"max_speed": 400.0, "accel_fwd": [150.0, 250.0], "gravity": -90.0, "drag": 0.25,
	},
	# uweapon_muzflsh_ground_smoke (count remap(CP5 0..1 -> 8..0); radius x remap(CP1 0..1 -> 1..1.75))
	"smoke_ground": {
		"kind": "smoke", "tex": "smokeloop_i_0_sc_hardedge", "tex_mv": "smokeloop_i_0_flwmix", "tex_layers": [["wispy_steam_burst_b", 0.75]], "seq": [0, 1], "seq2": [0, 3],
		"frame_age_bias": 0.385,
		"blend": "lighten", "self_illum": 0.1, "shadows": true, "shadow_density": 2.0, "feather": 30.0, "max_screen": 1.0, "screen_fade": [0.3, 0.65],
		"count": 8, "per_frame": 4, "life": [0.2, 2.0], "bias": {"life": -0.0603}, "fade_frac": [0.5, 0.5], "fade_in_frac": 0.1, "fade_ease": true,
		"x": [-10.0, 10.0], "y": [-5.0, 5.0], "z": [-1.0, 1.0], "ring": 30.0, "star": [16, 16],
		"ring_yaw": -90.0,  # ring in CP0's XY plane (level with the barrel), start angle -90
		"on_ground": 64.0,  # PositionPlaceOnGround: trace down up to 64 u, kill the particle on a miss
		"on_ground_radius_offset": -0.1,  # m_flOffsetByRadiusFactor with m_bOffsetonColOnly: on a hit the particle is set 0.1 x its spawn radius into the ground
		"half_by_index": [13.87, 12.018, 10.914, 11.155, 11.899, 12.699, 13.422, 14.211],  # curve at index 0..7 read exactly (world report's 12.3 / 11.6 are off; the fps report gave only the range)
		"grow": [1.0, 3.0], "grow_bias": 0.35,
		"alpha": [0.3922, 0.7059], "color_min": Color8(192, 192, 192), "color_max": Color8(255, 228, 181),
		"birth_tint": Color8(249, 222, 194),  # inferred: ColorInterpolate with end time 0 before start 0.15 read as a birth tint that returns to the particle colour
		"birth_tint_until": 0.15, "roll": [0.0, 360.0], "roll_flip": true,
		"vel_up": [100.0, 150.0],
		"vel_out_by_index": [-75.0, -46.88, -18.75, 9.38, 37.5, 65.62, 93.75, 121.88],  # inferred: VelocityFromNormal 3 on the ring's radial normal scaled lerp(-25, 50, i/8), replacing the ring's own 30..90
		"max_speed": 400.0, "accel_fwd": [450.0, 500.0], "gravity": -90.0, "drag": 0.25, "force_fwd": [37.5, 150.0], "curl": 250.0, "wind": 35.0,
	},
	# uweapon_muzzleflash_pist_fakelight (radius 80 x remap(CP1 0..1 -> 1..2))
	"light_pist": {
		"kind": "light",
		"life": 0.05,
		"offset": Vector3(-5.0, 0.0, 3.0),
		"alpha": [0.3529, 0.4706], "color_min": Color8(162, 87, 44), "color_max": Color8(177, 144, 118), "color": Color8(170, 116, 81),
		"range": 40.0,  # inferred: range = particle radius x flRadiusMultiplier 0.5
		"energy": 0.1,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
	# uweapon_muzzleflash_subm_fakelight (radius 160 x remap(CP1 0..1 -> 1..2))
	"light_subm": {
		"kind": "light",
		"life": 0.052,
		"offset": Vector3(0.0, 0.0, 0.0),
		"alpha": [0.7059, 0.7843], "color_min": Color8(175, 64, 12), "color_max": Color8(191, 106, 31), "color": Color8(183, 85, 22),
		"range": 80.0,  # inferred: range = radius x 0.5; the CP1 remap is in this file too, so both reports are right for their configs (fp CP1 0 -> 80, tp CP1 0.75 -> 140)
		"energy": 0.2,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
	# uweapon_muzflsh_fakelight (radius 160 x remap(CP1 0..1 -> 1..2))
	"light_rifle": {
		"kind": "light",
		"life": 0.05,
		"offset": Vector3(-2.0, 0.0, 2.0), "offset_side": 2.0,
		"alpha": [0.7059, 0.7843], "color_min": Color8(175, 64, 12), "color_max": Color8(191, 106, 31), "color": Color8(183, 85, 22),
		"range": 80.0,  # inferred: range = particle radius x flRadiusMultiplier 0.5
		"energy": 0.2,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
	# uweapon_muzflsh_deagle_fakelight (radius 200)
	"light_deagle": {
		"kind": "light",
		"life": 0.025,
		"offset": Vector3(0.0, 0.0, 0.0),
		"alpha": [1.0, 1.0], "color_min": Color8(175, 64, 12), "color_max": Color8(191, 106, 31), "color": Color8(183, 85, 22),
		"range": 100.0,  # inferred: range = particle radius x flRadiusMultiplier 0.5
		"energy": 0.5,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
	# uweapon_muzflsh_fakelight_ironsight (radius 160 x remap(CP1 0..1 -> 1..2))
	"light_ironsight": {
		"kind": "light",
		"life": 0.05,
		"offset": Vector3(10.0, 2.0, -3.0),
		"alpha": [0.7059, 0.7843], "color_min": Color8(186, 73, 15), "color_max": Color8(191, 106, 31), "color": Color8(188, 90, 23),
		"range": 80.0,  # inferred: range = particle radius x flRadiusMultiplier 0.5
		"energy": 0.2,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
	# uweapon_muzflsh_fakelight_64 (radius 64)
	"light_snip": {
		"kind": "light",
		"life": 0.025,
		"offset": Vector3(0.0, 0.0, 0.0),
		"alpha": [0.7059, 0.7843], "color_min": Color8(175, 64, 12), "color_max": Color8(191, 106, 31), "color": Color8(183, 85, 22),
		"range": 32.0,  # inferred: range = particle radius x flRadiusMultiplier 0.5
		"energy": 0.2,  # C_OP_RenderStandardLight flIntensity; inferred: brightness = energy x alpha
		"follow": true,
	},
}

## FLASHES: every (effect, view, config) a gun plays, keyed "<created .vpcf>/<fp|tp>/<config>". always: play every entry; pick1: choose
## one entry per shot (a repeat doubles its chance, "" draws nothing); pick2: choose two different entries. An entry is a LAYERS
## name, [name, overrides] (apply over LAYERS to get what CS2 draws at that config), or {"group": [...]} (every entry plays).
## cp0_fwd: CP0 moved this far along the muzzle's +X; fixed: CP0 is placed at the attachment once and does not follow it;
## world_origin: CP0 is the map origin (0, 0, 0) in world axes, not the attachment [false].
## Resolved from the configs in each root .vpcf (m_controlPointConfigurations; an unset CP reads 0, inferred) and the clip events.
const FLASHES := {
	# Glock, P2000, P250, Five-SeveN, CZ75, USP-S unsilenced: CP1 0, CP3 0.25, CP6 0
	"uweapon_muzzleflash_pist_fps/fp/fps_view": {
		"always": [  # pist_smoke life x remap(CP3 0.25 -> 0) = 0: no smoke at this config
			["pist_fire", {"half_by_index": [[0.553, 0.83], [0.918, 1.484], [0.717, 1.395], [0.564, 1.267], [0.542, 1.116], [0.542, 0.975]]}],
			["pist_beam", {"half": [0.5, 1.5], "trail_time_shared": [0.055, 0.0825], "length": [3.3, 7.43]}],
			"spark_pist",
			"light_pist",
		],
		"pick1": [
			"",
			["pist_fire_alt", {"half_by_index": [[0.896, 1.195], [1.021, 2.027], [1.155, 2.212], [1.217, 2.212], [0.894, 2.212], [0.642, 2.212]]}],
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Tec-9, Dual Berettas right gun: CP1 0, CP3 0.75
	"uweapon_muzzleflash_pist_fps/fp/primary_fps": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858]}],
			["pist_fire", {"half_by_index": [[1.659, 2.489], [2.755, 4.451], [2.15, 4.184], [1.691, 3.8], [1.626, 3.347], [1.626, 2.925]]}],
			"pist_beam",
			"spark_pist",
			"light_pist",
		],
		"pick1": [
			"",
			["pist_fire_alt", {"half_by_index": [[2.688, 3.585], [3.063, 6.08], [3.465, 6.636], [3.651, 6.636], [2.681, 6.636], [1.925, 6.636]]}],
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Dual Berettas left gun (muzzle_flash2): CP1 0, CP3 1.0
	"uweapon_muzzleflash_pist_fps/fp/alternate_fps": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858]}],
			"pist_fire",
			"pist_beam",
			"spark_pist",
			"light_pist",
		],
		"pick1": [
			"",
			["pist_fire_alt", {"half_by_index": [[3.585, 4.78], [4.083, 8.107], [4.62, 8.848], [4.868, 8.848], [3.575, 8.848], [2.567, 8.848]]}],
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# R8 alt-fire (the world system, not an _fps wrapper): CP1 0, CP3 0.75
	"uweapon_muzzleflash_pist/fp/fps_view": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858], "world_pass": true}],
			["pist_fire", {"half_by_index": [[1.659, 2.489], [2.755, 4.451], [2.15, 4.184], [1.691, 3.8], [1.626, 3.347], [1.626, 2.925]], "world_pass": true}],
			["pist_beam", {"world_pass": true}],
			["spark_pist", {"world_pass": true}],
			["light_pist", {"world_pass": true}],
		],
		"pick1": [
			"",
			["pist_fire_alt", {"half_by_index": [[2.688, 3.585], [3.063, 6.08], [3.465, 6.636], [3.651, 6.636], [2.681, 6.636], [1.925, 6.636]], "world_pass": true}],
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,  # the world system itself: m_nViewModelEffect is not set, so it draws in the world pass
	},
	# R8 primary: CP1 0, CP3 1
	"uweapon_muzzleflash_pist_revolver_fps/fp/fps_view": {
		"always": [  # group 1 = {pist_fire_revolver x2}, pick 1: always one rev_fire
			"smoke_rev",
			"light_pist",
			["rev_fire", {"half_by_index": [[2.39, 4.78], [2.722, 8.107], [3.08, 8.848], [3.245, 8.848], [2.383, 8.848], [1.711, 8.848]]}],
		],
		"pick1": [],
		"pick2": [
			"",
			"pist_beam",
			"spark_pist",
		],
		"cp0_fwd": 2.0,  # inferred: SetSingleControlPointPosition moves CP0 2 u along its own forward axis
		"fixed": false,
	},
	# USP-S silenced: plain Create at muzzle_flash2, PATTACH_POINT, no config (all CPs 0)
	"uweapon_muzsilenced_subm_fps/fp/create": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			["smoke_sil", {"life": [0.15, 0.425]}],
			"spark_subm",
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": true,
	},
	# MP5-SD: CP1 0
	"uweapon_muzsilenced_subm_fps/fp/fps_view": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			["smoke_sil", {"life": [0.15, 0.425]}],
			"spark_subm",
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,  # inferred: the event names PATTACH_POINT but the config drives CP0 POINT_FOLLOW; the config is taken to win
	},
	# M4A1-S silenced (muzzle_flash2): CP1 0
	"uweapon_muzsilenced_rif_fps/fp/fps_view": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			["smoke_sil", {"life": [0.15, 0.425]}],
			"spark_subm",
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 2.0,  # inferred: SetSingleControlPointPosition moves CP0 2 u along its own forward axis
		"fixed": false,
	},
	# Desert Eagle: CP3 1
	"uweapon_muzflsh_deagle_fps/fp/fps_view": {
		"always": [  # deagle_primaryflash alpha x remap(CP3 1 -> 0) = 0: not drawn; the _fps wrapper's deagle_fire_fp replaces it
			["smoke_deagle", {"life": [0.2, 0.2]}],
			"light_deagle",
			"gen_beam",
			["deagle_fire_fp", {"half_by_index": [[6.0, 6.0], [2.994, 4.583], [2.693, 2.889], [2.666, 2.725], [2.666, 2.761], [2.689, 2.789], [2.689, 2.789], [2.689, 2.789]]}],
		],
		"pick1": [],
		"pick2": [  # deagle_compensator_flash emits remap(CP3 1 -> 0) = 0 particles: ''
			"",
			"",
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# MAC-10, MP9, MP7, P90, PP-Bizon: CP1 0, CP3 1, CP5 1, CP6 0
	"uweapon_muzzleflash_subm_fps/fp/fps_view": {
		"always": [
			"smoke_subm",
			"light_subm",
		],
		"pick1": [
			"",
			["subm_fire", {"half_by_index": [[0.957, 1.435], [1.81, 2.962], [1.339, 2.755], [0.982, 2.455], [0.931, 2.103], [0.931, 1.775]], "alpha2": 0.5}],
			["subm_fire_alt", {"half_by_index": [[1.287, 1.716], [1.608, 3.757], [1.968, 3.757], [1.767, 3.757], [1.323, 3.757], [0.842, 3.757]], "alpha2": 0.5}],
		],
		"pick2": [
			["subm_beam", {"half": [1.5, 3.75], "trail_time_shared": [0.06, 0.135], "length": [5.0, 7.3]}],
			"spark_subm",
			"beam3",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AK-47, M4A1-S unsilenced: CP1 0, CP3 0, CP5 0.35, CP6 0
	"uweapon_muzflsh_ak47_fps/fp/game": {
		"always": [
			["smoke_rifle", {"x": [0.0, 1.4], "side": 0.4375, "half": [1.4, 2.45], "vel_fwd": [35.0, 157.5]}],
			"light_rifle",
		],
		"pick1": [  # the {group} is uweapon_muzflsh_gen_empty_gp1: no flame, a 3-streak beam and a second smoke
			["rifle_fire", {"x_by_index": [[1.05, 1.05], [1.713, 2.376], [2.294, 3.538], [2.834, 4.618], [3.389, 5.727], [4.025, 7.0]], "half_by_index": [[0.811, 1.217], [1.576, 2.67], [1.5, 2.67], [1.134, 2.565], [0.799, 2.322], [0.48, 2.041]], "vel_fwd": [35.0, 52.5], "inherit_vel": 0.35}],
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.105, 1.05], [0.21, 2.1], [0.315, 3.15], [0.42, 4.2], [0.525, 5.25]], "yz_by_index": [[0.0, 0.0], [0.007, 0.07], [0.014, 0.14], [0.021, 0.21], [0.028, 0.28], [0.035, 0.35]], "half_by_index": [[0.901, 1.201], [1.126, 2.63], [1.378, 2.63], [1.237, 2.63], [0.926, 2.63], [0.589, 2.63]], "vel_fwd": [17.5, 17.5], "inherit_vel": 0.35}],
			{"group": [["beam3", {"half": [0.35, 0.35], "vel_fwd": [-36.75, -29.75], "length": [2.98, 9.19]}], ["smoke_rifle", {"x": [0.0, 1.4], "side": 0.4375, "half": [1.4, 2.45], "vel_fwd": [35.0, 157.5]}]]},
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.105, 1.05], [0.21, 2.1], [0.315, 3.15], [0.42, 4.2], [0.525, 5.25]], "yz_by_index": [[0.0, 0.0], [0.007, 0.07], [0.014, 0.14], [0.021, 0.21], [0.028, 0.28], [0.035, 0.35]], "half_by_index": [[0.901, 1.201], [1.126, 2.63], [1.378, 2.63], [1.237, 2.63], [0.926, 2.63], [0.589, 2.63]], "vel_fwd": [17.5, 17.5], "inherit_vel": 0.35}],
		],
		"pick2": [
			"",
			["comp_side", {"ring": 0.035, "vel_out": [-8.75, -7.0], "half_by_index": [0.0, 0.35], "vel_fwd": [-10.5, -3.5], "length": [3.13, 8.2]}],
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# M4A4, FAMAS, UMP-45: CP1 0, CP3 1, CP5 0.5
	"uweapon_muzflsh_riffle_fps/fp/fps_view": {
		"always": [  # group 2 = {gen_empty, gen_spark}, pick 2: the spark always plays; there is no compensator flash
			["smoke_rifle", {"life": [0.1, 0.25], "x": [0.0, 2.0], "side": 0.625, "half": [2.0, 3.5], "alpha2": 0.25, "vel_fwd": [50.0, 225.0]}],
			"light_rifle",
			"spark_rifle",
		],
		"pick1": [
			["rifle_fire", {"x_by_index": [[1.5, 1.5], [2.447, 3.394], [3.277, 5.054], [4.049, 6.598], [4.841, 8.182], [5.75, 10.0]], "half_by_index": [[1.159, 1.739], [2.252, 3.814], [2.143, 3.814], [1.62, 3.665], [1.142, 3.317], [0.686, 2.915]], "vel_fwd": [50.0, 75.0], "inherit_vel": 0.5}],
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.15, 1.5], [0.3, 3.0], [0.45, 4.5], [0.6, 6.0], [0.75, 7.5]], "yz_by_index": [[0.0, 0.0], [0.01, 0.1], [0.02, 0.2], [0.03, 0.3], [0.04, 0.4], [0.05, 0.5]], "half_by_index": [[1.287, 1.716], [1.608, 3.757], [1.968, 3.757], [1.767, 3.757], [1.323, 3.757], [0.842, 3.757]], "vel_fwd": [25.0, 25.0], "inherit_vel": 0.5}],
			{"group": [["beam3", {"half": [0.5, 0.5], "vel_fwd": [-52.5, -42.5], "length": [4.25, 13.12]}], ["smoke_rifle", {"life": [0.1, 0.25], "x": [0.0, 2.0], "side": 0.625, "half": [2.0, 3.5], "alpha2": 0.25, "vel_fwd": [50.0, 225.0]}]]},
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.15, 1.5], [0.3, 3.0], [0.45, 4.5], [0.6, 6.0], [0.75, 7.5]], "yz_by_index": [[0.0, 0.0], [0.01, 0.1], [0.02, 0.2], [0.03, 0.3], [0.04, 0.4], [0.05, 0.5]], "half_by_index": [[1.287, 1.716], [1.608, 3.757], [1.968, 3.757], [1.767, 3.757], [1.323, 3.757], [0.842, 3.757]], "vel_fwd": [25.0, 25.0], "inherit_vel": 0.5}],
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Galil AR, SG 553 hip: CP1 0, CP5 0.75
	"uweapon_muzflsh_riffle_lrg_fps/fp/game": {
		"always": [
			["rifl_break", {"ring": 0.075, "vel_out": [-18.75, -15.0], "x": [-1.5, -1.5], "half_shared": [1.5, 3.75], "vel_fwd": [-22.5, -7.5], "length": [0.97, 4.45]}],
			"light_rifle",
		],
		"pick1": [
			["rifle_fire", {"x_by_index": [[2.25, 2.25], [3.67, 5.091], [4.916, 7.582], [6.073, 9.896], [7.262, 12.273], [8.625, 15.0]], "half_by_index": [[1.739, 2.608], [3.378, 5.722], [3.214, 5.722], [2.43, 5.497], [1.713, 4.975], [1.029, 4.373]], "vel_fwd": [75.0, 112.5], "inherit_vel": 0.75}],
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0], [1.125, 11.25]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6], [0.075, 0.75]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635], [1.262, 5.635]], "vel_fwd": [37.5, 37.5], "inherit_vel": 0.75}],
			{"group": [["beam3", {"half": [0.75, 0.75], "vel_fwd": [-78.75, -63.75], "length": [6.38, 19.69]}], ["smoke_rifle", {"x": [0.0, 3.0], "side": 0.9375, "half": [3.0, 5.25], "vel_fwd": [75.0, 337.5]}]]},
			["rifle_fire_alt", {"x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0], [1.125, 11.25]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6], [0.075, 0.75]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635], [1.262, 5.635]], "vel_fwd": [37.5, 37.5], "inherit_vel": 0.75}],
		],
		"pick2": [
			"",
			["smoke_rifle_lrg", {"life": [0.2625, 0.4875]}],
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AUG hip: CP1 0, CP3 0, CP5 0.75
	"uweapon_muzflsh_aug_fps/fp/fps_view": {
		"always": [  # no ChooseRandom ops: every child plays
			["aug_fire", {"x_by_index": [[2.25, 2.25], [2.708, 3.165], [3.164, 4.078], [3.589, 4.927], [3.98, 5.709], [4.357, 6.463], [4.727, 7.204], [5.097, 7.945], [5.475, 8.7], [5.869, 9.489], [6.305, 10.359], [6.75, 11.25]], "half_by_index": [[2.495, 3.743], [5.176, 7.953], [4.818, 7.948], [4.296, 7.727], [3.896, 7.338], [3.484, 6.92], [3.084, 6.586], [2.715, 6.32], [2.4, 6.03], [2.137, 5.714], [1.886, 5.357], [1.623, 4.991]]}],
			["aug_comp", {"ring": 0.075, "vel_out": [-18.75, -15.0], "x": [-1.5, -1.5], "half": [0.75, 2.25], "vel_fwd": [-22.5, -7.5], "length": [3.35, 10.25]}],
			["beam3", {"half": [0.75, 0.75], "vel_fwd": [-78.75, -63.75], "length": [6.38, 19.69]}],
			"light_rifle",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AUG scoped: CP1 0, CP3 1, CP5 0.35, CP6 0
	"uweapon_muzflsh_aug_fps_ironsight/fp/ironsight": {
		"always": [  # no ChooseRandom ops: every child plays
			["aug_fire", {"x_by_index": [[1.05, 1.05], [1.264, 1.477], [1.477, 1.903], [1.675, 2.299], [1.857, 2.664], [2.033, 3.016], [2.206, 3.362], [2.379, 3.708], [2.555, 4.06], [2.739, 4.428], [2.942, 4.834], [3.15, 5.25]], "half_by_index": [[0.582, 0.873], [1.208, 1.856], [1.124, 1.854], [1.002, 1.803], [0.909, 1.712], [0.813, 1.615], [0.72, 1.537], [0.633, 1.475], [0.56, 1.407], [0.499, 1.333], [0.44, 1.25], [0.379, 1.164]]}],
			["aug_comp", {"ring": 0.035, "vel_out": [-8.75, -7.0], "x": [-0.7, -0.7], "half": [0.35, 1.05], "vel_fwd": [-10.5, -3.5], "length": [1.57, 4.78]}],
			["beam3", {"half": [0.35, 0.35], "vel_fwd": [-36.75, -29.75], "length": [2.98, 9.19]}],
			"light_ironsight",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# SG 553 scoped: CP1 0, CP3 1, CP5 0.5, CP6 0
	"uweapon_muzflsh_sg_fps_ironsight/fp/ironsight": {
		"always": [  # no ChooseRandom ops: every child plays
			["aug_fire", {"x_by_index": [[1.5, 1.5], [1.805, 2.11], [2.109, 2.719], [2.392, 3.285], [2.653, 3.806], [2.904, 4.309], [3.151, 4.803], [3.398, 5.296], [3.65, 5.8], [3.913, 6.326], [4.203, 6.906], [4.5, 7.5]], "half_by_index": [[0.832, 1.248], [1.725, 2.651], [1.606, 2.649], [1.432, 2.576], [1.299, 2.446], [1.161, 2.307], [1.028, 2.195], [0.905, 2.107], [0.8, 2.01], [0.712, 1.905], [0.629, 1.786], [0.541, 1.664]]}],
			["aug_comp", {"ring": 0.05, "vel_out": [-12.5, -10.0], "x": [-1.0, -1.0], "half": [0.5, 1.5], "vel_fwd": [-15.0, -5.0], "length": [2.24, 6.83]}],
			["beam3", {"half": [0.5, 0.5], "vel_fwd": [-52.5, -42.5], "length": [4.25, 13.12]}],
			"light_ironsight",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# M249, Negev: CP1 0.75, CP0 PATTACH_POINT
	"uweapon_muzflsh_mach_fps/fp/fps_fire": {
		"always": [
			["light_rifle", {"range": 140.0}],
		],
		"pick1": [  # mach_primaryflash_alt count remap(CP1 0.5..1 -> 1..8) capped at 6; mach_empty_gp1 = mach_primarybeam, count remap(CP1 -> 1..3), no GlobalScale (the fps report scaled it); inferred: 4.5 rounds half up to 5 (PF_ROUND_TYPE_NEAREST)
			["rifle_fire_alt", {"count": 5, "x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635]], "vel_fwd": [37.5, 37.5], "inherit_vel": 0.75}],
			{"group": [["beam3", {"count": 2, "delay": 0.0}]]},
			["rifle_fire_alt", {"count": 5, "x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635]], "vel_fwd": [37.5, 37.5], "inherit_vel": 0.75}],
		],
		"pick2": [
			["comp_side", {"ring": 0.075, "star": [2, 4], "vel_out": [-18.75, -15.0], "half_by_index": [0.0, 0.75], "vel_fwd": [-22.5, -7.5], "length": [6.71, 17.57]}],
			"spark_rifle",
			"",
		],
		"cp0_fwd": 0.0,
		"fixed": true,  # CP0 is PATTACH_POINT: the flash stays where it was fired
	},
	# Nova, XM1014, MAG-7, Sawed-Off: CP1 0.75, CP3 0.5
	"uweapon_muzflsh_shot_fps/fp/fps_fire": {
		"always": [
			["smoke_shot", {"count": 3, "life": [0.3875, 0.3875], "sphere": 0.375, "half_by_index": [3.75, 7.5, 11.25], "alpha2": 0.875, "vel_fwd_by_index": [[150.0, 225.0], [337.5, 412.5], [525.0, 600.0]], "vel_side": [-45.0, 45.0], "vel_up": [-45.0, 45.0]}],
			["light_rifle", {"range": 140.0}],
		],
		"pick1": [  # shot_primaryflash count remap(CP1 0.5..1 -> 1..4), alt remap(-> 1..8) capped 6; shot_primarybeam has no PositionLock and no GlobalScale; inferred: 2.5 and 4.5 round half up (PF_ROUND_TYPE_NEAREST)
			["rifle_fire", {"count": 3, "x_by_index": [[2.25, 2.25], [3.67, 5.091], [4.916, 7.582]], "half_by_index": [[1.739, 2.608], [3.378, 5.722], [3.214, 5.722]], "vel_fwd": [75.0, 112.5]}],
			["rifle_fire_alt", {"count": 5, "x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635]], "vel_fwd": [37.5, 37.5]}],
			{"group": [["beam3", {"count": 2, "delay": 0.0, "follow": false}]]},
			["rifle_fire_alt", {"count": 5, "x_by_index": [[0.0, 0.0], [0.225, 2.25], [0.45, 4.5], [0.675, 6.75], [0.9, 9.0]], "yz_by_index": [[0.0, 0.0], [0.015, 0.15], [0.03, 0.3], [0.045, 0.45], [0.06, 0.6]], "half_by_index": [[1.931, 2.574], [2.413, 5.635], [2.952, 5.635], [2.65, 5.635], [1.984, 5.635]], "vel_fwd": [37.5, 37.5]}],
		],
		"pick2": [  # inferred: shot_compensator_flash's GlobalScale centres on CP1 (m_nControlPointNumber 1), a world-origin point, so at scale 0.75 CS2 pulls the streaks a quarter of the way to the map origin: nothing near the gun (the fps report built it as a normal compensator)
			"",
			"",
			"",
			"spark_shot",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AWP: CP1 0.5, CP5 1, CP6 0, CP0 +3 forward
	"weapon_muzzleflash_snip_fps/fp/fps_view": {
		"always": [  # no ChooseRandom ops: every child plays; ground_smoke emits 8*(1 - CP5) = 0 here
			"smoke_brake_l",
			"awp_flare",
			"spark_awp",
			"light_snip",
			"smoke_brake_r",
			["snip_fire", {"half_by_index": [5.348, 5.726, 3.377, 3.15]}],
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 3.0,  # the config drives CP0 at the attachment offset (3, 0, 0)
		"fixed": false,
	},
	# SSG 08: CP1 0, CP5 1
	"weapon_muzzleflash_snip_fps/fp/ssg08": {
		"always": [  # no ChooseRandom ops: every child plays; ground_smoke emits 8*(1 - CP5) = 0 here
			["smoke_brake_l", {"life": [0.25, 0.5], "half_by_index": [2.05, 4.204, 5.54, 7.028]}],
			"awp_flare",
			"spark_awp",
			"light_snip",
			["smoke_brake_r", {"life": [0.25, 0.5], "half_by_index": [2.05, 4.564, 5.858, 6.779]}],
			["snip_fire", {"half_by_index": [7.905, 8.464, 4.992, 4.656]}],
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# G3SG1, SCAR-20: CP1 0.5, CP5 1, CP6 0
	"weapon_muzzleflash_snip_ar_fps/fp/scar_fps": {
		"always": [  # no ChooseRandom ops: every child plays; ground_smoke emits 8*(1 - CP5) = 0 here
			"awp_flare",
			"spark_awp",
			["light_rifle", {"range": 120.0}],
			["snip_fire", {"half_by_index": [5.348, 5.726, 3.377, 3.15]}],
			["smoke_g3sg1", {"count": 1, "life": [0.125, 0.25], "half_by_index": [5.126], "alpha2_by_index": [0.1212], "vel_fwd_by_index": [197.0]}],
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Zeus x27: CP0 on muzzle_flash
	"weapon_taser_glow/fp/fps_view": {
		"always": [  # weapon_taser_glow is not an _fps wrapper and does not set m_nViewModelEffect: read as the R8 alt-fire entry, it draws in the world pass (inferred)
			["taser_glow", {"world_pass": true}],
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,  # inferred: the event names PATTACH_POINT but its fps_view config drives CP0 POINT_FOLLOW; the config is taken to win
	},
	# AWP's second first-person event (see note)
	"uweapon_muzflsh_ground_smoke/fp/none": {
		"always": [  # inferred: the AWP clip's second event (Create_CFG, no config, no attachment); ground_smoke's own configs put CP0 at the world origin, so CS2 spawns this ring at the map origin, not at the gun, and a missed 64 u ground trace kills it
			["smoke_ground", {"world_pass": true}],  # a root that does not set m_nViewModelEffect, as the R8 alt-fire entry
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": true,
		"world_origin": true,  # CP0 at the map origin (0, 0, 0), not on the attachment: without this the renderer would put the ring at the gun
	},
	# Glock, P2000, P250, Five-SeveN, CZ75, Tec-9, USP-S unsilenced: CP1 0.75, CP3 0.5
	"uweapon_muzzleflash_pist/tp/thirdperson": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858]}],
			["pist_fire", {"half_by_index": [[1.106, 1.659], [1.837, 2.967], [1.434, 2.79], [1.127, 2.533], [1.084, 2.231], [1.084, 1.95]]}],
			"pist_beam",
			["spark_pist", {"life": [0.0625, 0.1562]}],
			["light_pist", {"range": 70.0}],
		],
		"pick1": [
			"",
			"pist_fire_alt",
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Dual Berettas right gun: CP1 0, CP3 0.5
	"uweapon_muzzleflash_pist/tp/primary": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858]}],
			["pist_fire", {"half_by_index": [[1.106, 1.659], [1.837, 2.967], [1.434, 2.79], [1.127, 2.533], [1.084, 2.231], [1.084, 1.95]]}],
			"pist_beam",
			"spark_pist",
			"light_pist",
		],
		"pick1": [
			"",
			"pist_fire_alt",
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Dual Berettas left gun (muzzle_flash2): CP1 0, CP3 0.5
	"uweapon_muzzleflash_pist/tp/alternate": {
		"always": [
			["smoke_pist", {"life_by_index": [0.1172, 0.3534, 0.1858]}],
			["pist_fire", {"half_by_index": [[1.106, 1.659], [1.837, 2.967], [1.434, 2.79], [1.127, 2.533], [1.084, 2.231], [1.084, 1.95]]}],
			"pist_beam",
			"spark_pist",
			"light_pist",
		],
		"pick1": [
			"",
			"pist_fire_alt",
		],
		"pick2": [],  # group 2 = {pist_beam, pist_spark} and two are picked, so both always play (moved to always)
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# R8, both fire modes: CP1 0.75, CP3 unset (0)
	"uweapon_muzzleflash_pist_revolver/tp/thirdperson": {
		"always": [  # group 1 = {pist_fire_revolver x2}, pick 1: always one rev_fire
			"smoke_rev",
			["light_pist", {"range": 70.0}],
			["rev_fire", {"follow": false}],
		],
		"pick1": [],
		"pick2": [
			"",
			["pist_beam", {"half": [0.5, 1.5], "trail_time_shared": [0.055, 0.0825], "length": [3.3, 7.43]}],
			["spark_pist", {"life": [0.0625, 0.1562]}],
		],
		"cp0_fwd": 2.0,  # inferred: SetSingleControlPointPosition moves CP0 2 u along its own forward axis
		"fixed": false,
	},
	# USP-S silenced: plain Create at muzzle_flash2, PATTACH_POINT, CP1 unset (0)
	"uweapon_muzsilenced_subm/tp/create": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			["smoke_sil", {"life": [0.15, 0.425]}],
			"spark_subm",
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": true,
	},
	# MP5-SD: CP1 1
	"uweapon_muzsilenced_subm/tp/thirdperson": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			"smoke_sil",
			["spark_subm", {"life": [0.0125, 0.1]}],
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,  # inferred: the event names PATTACH_POINT but the config drives CP0 POINT_FOLLOW; the config is taken to win
	},
	# M4A1-S silenced (muzzle_flash2): CP1 1
	"uweapon_muzsilenced_rif/tp/thirdperson": {
		"always": [  # group 2 = {smoke, spark}, pick 2: both always; no fire sprite and no light
			"smoke_sil",
			["spark_subm", {"life": [0.0125, 0.1]}],
		],
		"pick1": [
			"",
			"sil_beam",
		],
		"pick2": [],
		"cp0_fwd": 2.0,  # inferred: SetSingleControlPointPosition moves CP0 2 u along its own forward axis
		"fixed": false,
	},
	# Desert Eagle: the clip names a 'thirdperson' config the file lacks, so CP3 reads 0 (inferred)
	"uweapon_muzflsh_deagle/tp/thirdperson": {
		"always": [
			"smoke_deagle",
			"light_deagle",
			["gen_beam", {"follow": false}],
			["deagle_fire", {"half_by_index": [[16.0, 16.0], [7.985, 12.221], [7.181, 7.703], [7.11, 7.267], [7.11, 7.362], [7.172, 7.437], [7.172, 7.437], [7.172, 7.437]], "alpha": [0.1765, 0.1961], "follow": false}],
		],
		"pick1": [],
		"pick2": [
			"",
			["deagle_comp", {"follow": false}],
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# MAC-10, MP9, MP7, P90, PP-Bizon: CP1 0.75, CP3 0, CP5 unset (0)
	"uweapon_muzzleflash_subm/tp/thirdperson": {
		"always": [
			"smoke_subm",
			["light_subm", {"range": 140.0}],
		],
		"pick1": [
			"",
			"subm_fire",
			"subm_fire_alt",
		],
		"pick2": [  # inferred: this config leaves CP5 unset (0), so aug_primarybeam's GlobalScale x0 draws nothing (the world report drew it at full size)
			"subm_beam",
			["spark_subm", {"life": [0.0219, 0.175]}],
			"",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AK-47, M4A1-S unsilenced: CP1 0, CP3 0, CP5 1
	"uweapon_muzflsh_ak47/tp/game": {
		"always": [
			"smoke_rifle",
			"light_rifle",
		],
		"pick1": [  # the {group} is uweapon_muzflsh_gen_empty_gp1: no flame, a 3-streak beam and a second smoke
			"rifle_fire",
			"rifle_fire_alt",
			{"group": ["beam3", "smoke_rifle"]},
			"rifle_fire_alt",
		],
		"pick2": [
			"",
			"comp_side",
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# M4A4, FAMAS, UMP-45: CP1 0, CP3 0, CP5 1
	"uweapon_muzflsh_riffle/tp/game": {
		"always": [  # group 2 = {gen_empty, gen_spark}, pick 2: the spark always plays; there is no compensator flash
			"smoke_rifle",
			"light_rifle",
			"spark_rifle",
		],
		"pick1": [
			"rifle_fire",
			"rifle_fire_alt",
			{"group": ["beam3", "smoke_rifle"]},
			"rifle_fire_alt",
		],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Galil AR, SG 553: CP1 0, CP5 1, CP3 unset (0)
	"uweapon_muzflsh_riffle_lrg/tp/game": {
		"always": [
			"rifl_break",
			"light_rifle",
		],
		"pick1": [
			"rifle_fire",
			"rifle_fire_alt",
			{"group": ["beam3", "smoke_rifle"]},
			"rifle_fire_alt",
		],
		"pick2": [
			"",
			"smoke_rifle_lrg",
			"spark_rifle",
		],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# AUG: CP1 0, CP3 0, CP5 1
	"uweapon_muzflsh_aug/tp/game": {
		"always": [  # no ChooseRandom ops: every child plays
			"aug_fire",
			"aug_comp",
			"beam3",
			"light_rifle",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# M249, Negev: CP1 1, CP0 PATTACH_POINT
	"uweapon_muzflsh_mach/tp/thirdperson": {
		"always": [
			["light_rifle", {"range": 160.0}],
		],
		"pick1": [  # mach_primaryflash_alt count remap(CP1 0.5..1 -> 1..8) capped at 6; mach_empty_gp1 = mach_primarybeam, count remap(CP1 -> 1..3), no GlobalScale (the fps report scaled it)
			"rifle_fire_alt",
			{"group": [["beam3", {"delay": 0.0}]]},
			"rifle_fire_alt",
		],
		"pick2": [
			["comp_side", {"star": [2, 4]}],
			"spark_rifle",
			"",
		],
		"cp0_fwd": 0.0,
		"fixed": true,  # CP0 is PATTACH_POINT: the flash stays where it was fired
	},
	# Nova, XM1014, MAG-7, Sawed-Off: CP1 1, CP3 0.5, CP0 PATTACH_POINT
	"uweapon_muzflsh_shot/tp/thirdperson": {
		"always": [
			["smoke_shot", {"alpha2": 0.875}],
			["light_rifle", {"range": 160.0}],
		],
		"pick1": [  # shot_primaryflash count remap(CP1 0.5..1 -> 1..4), alt remap(-> 1..8) capped 6; shot_primarybeam has no PositionLock and no GlobalScale
			["rifle_fire", {"count": 4, "x_by_index": [[3.0, 3.0], [4.894, 6.788], [6.554, 10.109], [8.098, 13.195]], "half_by_index": [[2.318, 3.477], [4.504, 7.629], [4.286, 7.629], [3.239, 7.33]]}],
			"rifle_fire_alt",
			{"group": [["beam3", {"delay": 0.0, "follow": false}]]},
			"rifle_fire_alt",
		],
		"pick2": [
			"",
			"",
			["comp_side", {"star": [2, 4]}],
			"spark_shot",
		],
		"cp0_fwd": 0.0,
		"fixed": true,  # CP0 is PATTACH_POINT: the flash stays where it was fired
	},
	# AWP, SSG 08: CP1 0, CP5 0
	"weapon_muzzleflash_snip/tp/thirdperson": {
		"always": [  # no ChooseRandom ops: every child plays
			["smoke_brake_l", {"life": [0.25, 0.5], "half_by_index": [2.05, 4.204, 5.54, 7.028]}],
			"awp_flare",
			"spark_awp",
			"light_snip",
			["smoke_brake_r", {"life": [0.25, 0.5], "half_by_index": [2.05, 4.564, 5.858, 6.779]}],
			["snip_fire", {"half_by_index": [7.905, 8.464, 4.992, 4.656]}],
			"smoke_ground",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# G3SG1, SCAR-20: CP1 0, CP5 0.5
	"weapon_muzzleflash_snip_ar/tp/scar": {
		"always": [  # no ChooseRandom ops: every child plays
			"awp_flare",
			"spark_awp",
			"light_rifle",
			["snip_fire", {"half_by_index": [7.905, 8.464, 4.992, 4.656]}],
			["smoke_g3sg1", {"count": 1, "life": [0.125, 0.25], "half_by_index": [4.101], "alpha2_by_index": [0.1212], "vel_fwd_by_index": [197.0]}],
			["smoke_ground", {"count": 4, "half_by_index": [13.87, 12.018, 10.914, 11.155], "vel_out_by_index": [-75.0, -46.88, -18.75, 9.38]}],
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": false,
	},
	# Zeus x27: plain Create at muzzle_flash, PATTACH_POINT
	"weapon_taser_glow/tp/create": {
		"always": [
			"taser_glow",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": true,  # inferred: a plain Create uses the event's PATTACH_POINT at muzzle_flash, not the fps_view config it also names
	},
	# AWP's second third-person event (see note)
	"uweapon_muzflsh_ground_smoke/tp/none": {
		"always": [  # inferred: the AWP clip's second event (Create_CFG, no config, no attachment); ground_smoke's own configs put CP0 at the world origin, so CS2 spawns this ring at the map origin, not at the gun, and a missed 64 u ground trace kills it
			"smoke_ground",
		],
		"pick1": [],
		"pick2": [],
		"cp0_fwd": 0.0,
		"fixed": true,
		"world_origin": true,  # CP0 at the map origin (0, 0, 0), not on the attachment: without this the renderer would put the ring at the gun
	},
}

## GUNS: which flash each gun class plays (the 34 guns of reference/weapons/vdata.csv plus weapon_taser), read from the clips'
## CNmParticleEvents (first person: viewmodel shoot clips; third person: animation/anims/world/*/shoot_*). attach: the model
## attachment CP0 rides; *_silenced: silencer on; *_left: Dual Berettas left gun; *_alt: R8 alt-fire; fp_scoped: the scoped clip.
const GUNS := {
	"weapon_glock": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_hkp2000": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_usp_silencer": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash", "fp_silenced": "uweapon_muzsilenced_subm_fps/fp/create", "tp_silenced": "uweapon_muzsilenced_subm/tp/create", "attach_silenced": "muzzle_flash2"},  # the clips carry both flashes, tagged 'muzzleflash silenced' / 'unsilenced'; inferred: the game plays the one matching the silencer
	"weapon_elite": {"fp": "uweapon_muzzleflash_pist_fps/fp/primary_fps", "tp": "uweapon_muzzleflash_pist/tp/primary", "attach": "muzzle_flash", "fp_left": "uweapon_muzzleflash_pist_fps/fp/alternate_fps", "tp_left": "uweapon_muzzleflash_pist/tp/alternate", "attach_left": "muzzle_flash2"},
	"weapon_p250": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_tec9": {"fp": "uweapon_muzzleflash_pist_fps/fp/primary_fps", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_fiveseven": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_cz75a": {"fp": "uweapon_muzzleflash_pist_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_deagle": {"fp": "uweapon_muzflsh_deagle_fps/fp/fps_view", "tp": "uweapon_muzflsh_deagle/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_revolver": {"fp": "uweapon_muzzleflash_pist_revolver_fps/fp/fps_view", "tp": "uweapon_muzzleflash_pist_revolver/tp/thirdperson", "attach": "muzzle_flash", "fp_alt": "uweapon_muzzleflash_pist/fp/fps_view", "tp_alt": "uweapon_muzzleflash_pist_revolver/tp/thirdperson"},  # third person plays the same revolver flash for both fire modes
	"weapon_nova": {"fp": "uweapon_muzflsh_shot_fps/fp/fps_fire", "tp": "uweapon_muzflsh_shot/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_xm1014": {"fp": "uweapon_muzflsh_shot_fps/fp/fps_fire", "tp": "uweapon_muzflsh_shot/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_sawedoff": {"fp": "uweapon_muzflsh_shot_fps/fp/fps_fire", "tp": "uweapon_muzflsh_shot/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_mag7": {"fp": "uweapon_muzflsh_shot_fps/fp/fps_fire", "tp": "uweapon_muzflsh_shot/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_mac10": {"fp": "uweapon_muzzleflash_subm_fps/fp/fps_view", "tp": "uweapon_muzzleflash_subm/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_mp9": {"fp": "uweapon_muzzleflash_subm_fps/fp/fps_view", "tp": "uweapon_muzzleflash_subm/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_mp7": {"fp": "uweapon_muzzleflash_subm_fps/fp/fps_view", "tp": "uweapon_muzzleflash_subm/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_mp5sd": {"fp": "uweapon_muzsilenced_subm_fps/fp/fps_view", "tp": "uweapon_muzsilenced_subm/tp/thirdperson", "attach": "muzzle_flash"},  # fp and tp events name muzzle_flash with PATTACH_POINT, but the config drives CP0 POINT_FOLLOW: inferred the config wins
	"weapon_ump45": {"fp": "uweapon_muzflsh_riffle_fps/fp/fps_view", "tp": "uweapon_muzflsh_riffle/tp/game", "attach": "muzzle_flash"},
	"weapon_p90": {"fp": "uweapon_muzzleflash_subm_fps/fp/fps_view", "tp": "uweapon_muzzleflash_subm/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_bizon": {"fp": "uweapon_muzzleflash_subm_fps/fp/fps_view", "tp": "uweapon_muzzleflash_subm/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_galilar": {"fp": "uweapon_muzflsh_riffle_lrg_fps/fp/game", "tp": "uweapon_muzflsh_riffle_lrg/tp/game", "attach": "muzzle_flash"},
	"weapon_famas": {"fp": "uweapon_muzflsh_riffle_fps/fp/fps_view", "tp": "uweapon_muzflsh_riffle/tp/game", "attach": "muzzle_flash"},
	"weapon_ak47": {"fp": "uweapon_muzflsh_ak47_fps/fp/game", "tp": "uweapon_muzflsh_ak47/tp/game", "attach": "muzzle_flash"},
	"weapon_m4a1": {"fp": "uweapon_muzflsh_riffle_fps/fp/fps_view", "tp": "uweapon_muzflsh_riffle/tp/game", "attach": "muzzle_flash"},
	"weapon_m4a1_silencer": {"fp": "uweapon_muzflsh_ak47_fps/fp/game", "tp": "uweapon_muzflsh_ak47/tp/game", "attach": "muzzle_flash", "fp_silenced": "uweapon_muzsilenced_rif_fps/fp/fps_view", "tp_silenced": "uweapon_muzsilenced_rif/tp/thirdperson", "attach_silenced": "muzzle_flash2"},  # as the USP-S: both events in one clip, chosen by tag (inferred)
	"weapon_sg556": {"fp": "uweapon_muzflsh_riffle_lrg_fps/fp/game", "tp": "uweapon_muzflsh_riffle_lrg/tp/game", "attach": "muzzle_flash", "fp_scoped": "uweapon_muzflsh_sg_fps_ironsight/fp/ironsight"},
	"weapon_aug": {"fp": "uweapon_muzflsh_aug_fps/fp/fps_view", "tp": "uweapon_muzflsh_aug/tp/game", "attach": "muzzle_flash", "fp_scoped": "uweapon_muzflsh_aug_fps_ironsight/fp/ironsight"},
	"weapon_m249": {"fp": "uweapon_muzflsh_mach_fps/fp/fps_fire", "tp": "uweapon_muzflsh_mach/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_negev": {"fp": "uweapon_muzflsh_mach_fps/fp/fps_fire", "tp": "uweapon_muzflsh_mach/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_ssg08": {"fp": "weapon_muzzleflash_snip_fps/fp/ssg08", "tp": "weapon_muzzleflash_snip/tp/thirdperson", "attach": "muzzle_flash"},
	"weapon_awp": {"fp": "weapon_muzzleflash_snip_fps/fp/fps_view", "tp": "weapon_muzzleflash_snip/tp/thirdperson", "attach": "muzzle_flash", "fp_extra": "uweapon_muzflsh_ground_smoke/fp/none", "tp_extra": "uweapon_muzflsh_ground_smoke/tp/none"},  # fp_extra / tp_extra: the clips' second event; inferred to spawn at the map origin, so it shows nothing at the gun
	"weapon_g3sg1": {"fp": "weapon_muzzleflash_snip_ar_fps/fp/scar_fps", "tp": "weapon_muzzleflash_snip_ar/tp/scar", "attach": "muzzle_flash"},
	"weapon_scar20": {"fp": "weapon_muzzleflash_snip_ar_fps/fp/scar_fps", "tp": "weapon_muzzleflash_snip_ar/tp/scar", "attach": "muzzle_flash"},
	"weapon_taser": {"fp": "weapon_taser_glow/fp/fps_view", "tp": "weapon_taser_glow/tp/create", "attach": "muzzle_flash"},
}

## SHEETS: every sprite-sheet texture a main-pass layer uses: archive path and frames per sequence (from each .vtex_c DATA block,
## assets/effects/<path>.sheet.json has the frame rects). clamp: the sequence holds its last frame instead of looping.
const SHEETS := {
	"fire_gas_batch_b_top": {"path": "materials/particle/fire_gas/fire_gas_batch_b_top.vtex", "frames": [34, 35, 34, 34], "clamp": true},
	"fire_small_sim_b": {"path": "materials/particle/fire_small_sim/fire_small_sim_b.vtex", "frames": [32, 33, 33, 33], "clamp": true},
	"fire_small_sim_b_top_mv": {"path": "materials/particle/fire_small_sim/fire_small_sim_b_top_mv.vtex", "frames": [33, 34, 31, 31], "clamp": true},  # motion vectors
	"wispy_steam_burst_b": {"path": "materials/particle/simulated/steam/wispy_steam_burst_b.vtex", "frames": [26, 26, 26, 26], "clamp": true, "total_time": 25.0},  # each sequence's frame 25 has display time 0 (m_flTotalTime 25): sheet position p shows frame floor(p * 25), frame 25 only at p = 1 (every other sheet here has total time = frames)
	"wispy_steam_set": {"path": "materials/particle/simulated/steam/wispy_steam_set.vtex", "frames": [23, 23, 23, 23], "clamp": false},
	"smokeloop_i_0_sc_hardedge": {"path": "materials/particle/smoke/smokeburst/smokeloop_i_0_sc_hardedge.vtex", "frames": [64, 64], "clamp": false},  # two images per frame, the same rectangle
	"smokeloop_i_0_sc": {"path": "materials/particle/smoke/smokeburst/smokeloop_i_0_sc.vtex", "frames": [64], "clamp": false},  # two images per frame, the same rectangle
	"smokeloop_i_0_flwmix": {"path": "materials/particle/smoke/smokeburst/smokeloop_i_0_flwmix.vtex", "frames": [64], "clamp": false},  # two images per frame, the same rectangle; motion vectors
}

## TEXTURES: every texture path (materials/... .vtex) a main-pass layer uses, including motion-vector sheets and the single-frame
## ones; particle_ring_wave_8 is in game/core/pak01_dir.vpk, the rest in game/csgo/pak01_dir.vpk (checked by both reports).
const TEXTURES := [
	"materials/effects/spark.vtex",
	"materials/particle/fire_gas/fire_gas_batch_b_top.vtex",
	"materials/particle/fire_small_sim/fire_small_sim_b.vtex",
	"materials/particle/fire_small_sim/fire_small_sim_b_top_mv.vtex",
	"materials/particle/particle_glow_04.vtex",
	"materials/particle/particle_ring_wave_8.vtex",
	"materials/particle/simulated/steam/wispy_steam_burst_b.vtex",
	"materials/particle/simulated/steam/wispy_steam_set.vtex",
	"materials/particle/smoke/smokeburst/smokeloop_i_0_flwmix.vtex",
	"materials/particle/smoke/smokeburst/smokeloop_i_0_sc.vtex",
	"materials/particle/smoke/smokeburst/smokeloop_i_0_sc_hardedge.vtex",
]
