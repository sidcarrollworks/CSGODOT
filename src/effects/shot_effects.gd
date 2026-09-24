class_name ShotEffects
extends Node3D

## What is seen of a shot: its tracer and its muzzle flash, as CS2 draws
## them (Tracers, MuzzleFlashes), from the game's events.
##
## A round is fire_bullets (where it left, which way, with what), then its
## bullet_impacts (each wall it went into, then where it stopped), in that
## order within the tick; this takes them as they are handed out and draws
## on the next frame, never inside the tick. The tracer runs from the drawn
## muzzle (Muzzles: the first-person gun's for your own rounds, as it
## appears on screen, the gun in the hand for everyone else's) to the first
## surface the round met, or as far as the gun reaches if it met none, and
## on through a wall as CS2's fainter wallbang streak. The flash is at the
## same muzzle, riding the gun.
##
## Each is as old as the simulation time since its round was fired, at the
## time the frame falls at (between the last two ticks), so a tracer that
## lives 24 ms (an AK's across 500 units) looks the same at any frame rate
## rather than by how many frames happen to land in it.

## Whose eyes: the player this machine plays as, and their view.
var listener_id: int = GameEvents.NOBODY
var you: PlayerController
var game: GameSystems

var quads: EffectQuads
var flashes := MuzzleFlashes.new()

## Rounds handed out since the last frame, each {"fields", "impacts"}.
var _pending: Array[Dictionary] = []
## The round each shooter fired last, which their next impacts belong to.
var _open := {}
## Rounds each shooter has fired, for which draw a tracer.
var _fired := {}
var _trails: Array[Tracers.Trail] = []
var _ropes: Array[Tracers.Rope] = []
var _rng := RandomNumberGenerator.new()

## The trails' two looks, baked once from CS2's textures (_bake).
var _core_texture: Texture2D
var _glow_texture: Texture2D
var _wallbang_glow_texture: Texture2D


## Listens to a game's shots, for listener's eyes.
func watch(p_game: GameSystems, listener: int, p_you: PlayerController = null) -> void:
	game = p_game
	listener_id = listener
	you = p_you
	game.events.listen(&"fire_bullets", _on_fire_bullets)
	game.events.listen(&"bullet_impact", _on_bullet_impact)


func _ready() -> void:
	quads = EffectQuads.new()
	quads.name = "Quads"
	add_child(quads)
	flashes.name = "Flashes"
	add_child(flashes)
	flashes.quads = quads
	_bake()
	prepare()


## Reads every texture the tracers and flashes draw with, as the map loads:
## the flames' sheets are 4096 by 2048, and the first flash of a fight
## reading one from the disk held up its frame by 12 ms.
static func prepare() -> void:
	for kind: StringName in Tracers.ROPES:
		SpriteSheet.named(Tracers.ROPES[kind]["texture"])
	for name: String in FlashTable.LAYERS:
		var layer: Dictionary = FlashTable.LAYERS[name]
		if layer.has("tex"):
			SpriteSheet.named(MuzzleFlashes.texture_path(String(layer["tex"])))


func _exit_tree() -> void:
	if game != null:
		game.events.unlisten(&"fire_bullets", _on_fire_bullets)
		game.events.unlisten(&"bullet_impact", _on_bullet_impact)


func _on_fire_bullets(event: GameEvent) -> void:
	var round := {"fields": event.fields, "impacts": [], "at_usec": event.at_usec}
	_pending.append(round)
	_open[event.fields["userid"]] = round


func _on_bullet_impact(event: GameEvent) -> void:
	var round: Dictionary = _open.get(event.fields["userid"], {})
	if not round.is_empty():
		(round["impacts"] as Array).append(Vector3(event.fields["x"], event.fields["y"], event.fields["z"]))


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		_pending.clear()
		return
	var eye := camera.global_transform
	for round in _pending:
		_start(round, eye)
	_pending.clear()
	_open.clear()

	var now := draw_usec()
	quads.begin()
	_draw_trails(now, camera)
	_draw_ropes(now, eye)
	flashes.advance(now, eye)
	quads.finish()


## The simulation time a frame falls at: between the last two ticks.
static func draw_usec() -> int:
	var tick := SimClock.tick_usec()
	return SimClock.now_usec() - tick + int(clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0) * tick)


## A round's flash and tracer, from where its gun is drawn.
func _start(round: Dictionary, eye: Transform3D) -> void:
	var fields: Dictionary = round["fields"]
	var fired: int = round["at_usec"]
	var userid: int = fields["userid"]
	var weapon_class := String(fields["weapon"])
	var mode := int(fields["mode"])
	var nth: int = _fired.get(userid, 0)
	_fired[userid] = nth + 1
	var origin := Vector3(fields["x"], fields["y"], fields["z"])
	var direction := PlayerInput.aim_direction(float(fields["yaw"]), float(fields["pitch"]))
	var first_person := _in_first_person(userid)
	var gun := _gun(userid, first_person)
	# The Berettas take turns, right then left, as their clips do.
	var second := mode == 1 or (weapon_class == "weapon_elite" and nth % 2 == 1)
	var muzzle: Variant = null
	if gun is ViewModel:
		muzzle = Muzzles.in_view(gun, weapon_class, second)
	elif gun is PlayerModel:
		muzzle = Muzzles.in_hand(gun, weapon_class, second)

	if muzzle != null:
		flashes.fire(weapon_class, mode, nth, first_person, gun, second, fired, _rng)

	if not Tracers.draws(weapon_class, mode, nth):
		return
	var start := origin
	if muzzle != null:
		start = (muzzle as Transform3D).origin
		if first_person:
			start = Muzzles.as_drawn(eye, start)
	var impacts: Array = round["impacts"]
	var stop: Vector3 = impacts[0] if not impacts.is_empty() \
		else origin + direction * WeaponVData.number(weapon_class, "m_flRange")
	# Pressed against a wall, the muzzle can be past where the round stopped:
	# no tracer, rather than one run back to the wall.
	if (stop - origin).dot(direction) <= (start - origin).dot(direction):
		return
	var reach := Tracers.reach(weapon_class, float(fields["inaccuracy"]), start.distance_to(stop))
	if reach < start.distance_to(stop):
		stop = start + (stop - start).normalized() * reach
	elif impacts.size() > 1:
		var went_on := Tracers.Trail.make(&"wallbang", impacts[0], impacts[impacts.size() - 1], false, _rng)
		if went_on != null:
			went_on.fired_usec = fired
			_trails.append(went_on)
	var kind := Tracers.kind_of(weapon_class)
	if Tracers.TRAILS.has(kind):
		var trail := Tracers.Trail.make(kind, start, stop, first_person, _rng)
		if trail != null:
			trail.fired_usec = fired
			_trails.append(trail)
	else:
		var rope := Tracers.Rope.make(kind, start, stop)
		if rope != null:
			rope.fired_usec = fired
			_ropes.append(rope)


## Whether userid's rounds are seen from the first-person gun: yours, while
## you are alive and your arms are drawn.
func _in_first_person(userid: int) -> bool:
	return userid == listener_id and you != null and is_instance_valid(you) and you.alive \
		and you.view_model != null and you.view_model.is_visible_in_tree()


## The drawn gun a player's rounds come from: the view model in first
## person, the body's otherwise; null when nothing of them is drawn.
func _gun(userid: int, first_person: bool) -> Node3D:
	if first_person:
		return you.view_model
	var node := game.roster.player(userid) if game != null else null
	if node is PlayerSim and (node as PlayerSim).model != null:
		return (node as PlayerSim).model
	return null


func _draw_trails(now_usec: int, camera: Camera3D) -> void:
	var eye := camera.global_transform
	# The screen's height at a unit's distance, for the trails' size limits.
	var height_at_unit := 2.0 * tan(deg_to_rad(camera.fov) * 0.5)
	var kept: Array[Tracers.Trail] = []
	for trail in _trails:
		trail.age = maxf(float(now_usec - trail.fired_usec) / 1_000_000.0, 0.0)
		if not trail.alive():
			continue
		kept.append(trail)
		var alpha := trail.alpha_at()
		var head := trail.head()
		var distance := maxf(eye.origin.distance_to(head), 1.0)
		if alpha <= 0.0 or distance > float(trail.rules["draw"]):
			continue
		var screen: Array = trail.rules["screen"]
		var fade_size: Array = trail.rules["fade_size"]
		var glow := _wallbang_glow_texture if trail.kind == &"wallbang" else _glow_texture
		for layer in [[trail.half_core, trail.grow_core, _core_texture, float(trail.rules["core_alpha"])], [trail.half_glow, trail.grow_glow, glow, 1.0]]:
			var share: float = layer[0] / (distance * height_at_unit)
			var shown := alpha * float(layer[3])
			if not fade_size.is_empty():
				shown *= clampf(inverse_lerp(fade_size[1], fade_size[0], share), 0.0, 1.0)
			var half := clampf(share, screen[0], screen[1]) * distance * height_at_unit
			var length := trail.length(layer[1])
			if shown <= 0.0 or length <= 0.0:
				continue
			var tint := trail.tint.srgb_to_linear() if MuzzleFlashes.DECODE_COLOURS else trail.tint
			quads.quad(layer[2], &"add", false, EffectQuads.streak(head - trail.direction * length, head, half, eye.origin),
				Rect2(0.0, 0.0, 1.0, 1.0), Color(tint.r, tint.g, tint.b, shown))
	_trails = kept


func _draw_ropes(now_usec: int, eye: Transform3D) -> void:
	var kept: Array[Tracers.Rope] = []
	for rope in _ropes:
		rope.age = maxf(float(now_usec - rope.fired_usec) / 1_000_000.0, 0.0)
		if not rope.alive():
			continue
		kept.append(rope)
		var span := rope.span()
		if span.y <= span.x:
			continue
		var sheet := SpriteSheet.named(rope.rules["texture"])
		if sheet == null:
			continue
		var along := span.y - span.x
		var at := (span.x + span.y) * 0.5 / maxf(rope.distance, 1.0)
		var half := lerpf(rope.rules["half"][0], rope.rules["half"][1], at)
		# Only the part of the streak on the beam: its texture cut to match,
		# the head (the texture's foot) at the streak's leading end.
		var full := Tracers.ROPE_STREAK
		var head_v := 1.0 - (float(rope.rules["scroll"]) * rope.age - span.y) / full
		var tail_v := head_v - along / full
		var u := 0.5 / Tracers.ROPE_TEXTURE_SCALE_U
		var color := (rope.color_at().srgb_to_linear() if MuzzleFlashes.DECODE_COLOURS else rope.color_at()) * float(rope.rules["overbright"])
		quads.quad(sheet.texture, &"add", false,
			EffectQuads.streak(rope.start + rope.direction * span.x, rope.start + rope.direction * span.y, half, eye.origin),
			Rect2(0.5 - u, head_v, 2.0 * u, tail_v - head_v), Color(color.r, color.g, color.b, 1.0))
	_ropes = kept


## The trails' core and glow, baked from CS2's textures as the renderers
## show them: the spark streak's middle fifth across (U scaled 5), its
## length flipped so its white end is the head and shown at 1 / 1.5 (V
## scaled -1.5), recoloured through the core's gradient by its brightness,
## which is also its alpha; the glow the sparks sheet's soft teardrop the
## same way through its own. How the UV scales and offsets read is inferred
## (the spritecard shader could not be read); a Local check compares a
## frozen tracer up close.
func _bake() -> void:
	var spark := _image(Tracers.CORE_TEXTURE, 0)
	var drop := _image(Tracers.GLOW_TEXTURE, 4)
	var residual := _image(Tracers.GLOW_TEXTURE, 7)
	if spark != null:
		_core_texture = ImageTexture.create_from_image(bake_trail(spark, Tracers.CORE_GRADIENT, 1.5))
	if drop != null:
		_glow_texture = ImageTexture.create_from_image(bake_trail(drop, Tracers.GLOW_GRADIENT, 1.3))
	if residual != null:
		_wallbang_glow_texture = ImageTexture.create_from_image(bake_trail(residual, Tracers.WALLBANG_GLOW_GRADIENT, 1.5))
	if _wallbang_glow_texture == null:
		_wallbang_glow_texture = _glow_texture


## A texture (or one sequence of a sheet) as an image, read from the
## extracted PNG; null when it is not there.
static func _image(vtex_path: String, sequence: int) -> Image:
	var file := SpriteSheet.DIR.path_join(vtex_path.get_basename()) + ".png"
	if not FileAccess.file_exists(file):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(file))
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	var sheet := SpriteSheet.named(vtex_path)
	if sheet != null and not sheet.sequences.is_empty():
		var rect := sheet.frame(sequence, 0.0)
		var size := Vector2(image.get_size())
		image = image.get_region(Rect2i(Vector2i((rect.position * size).round()), Vector2i((rect.size * size).round())))
	return image


## A trail's look from a streak texture: across, its middle fifth; along,
## head (the card's top) at the texture's foot, shown at 1 / length_scale;
## coloured through gradient by brightness, which is its alpha.
static func bake_trail(source: Image, stops: Array, length_scale: float) -> Image:
	var out := Image.create_empty(16, 64, false, Image.FORMAT_RGBA8)
	var size := source.get_size()
	for y in out.get_height():
		var along := (y + 0.5) / out.get_height()
		var v := clampf(0.5 + (0.5 - along) / length_scale, 0.0, 1.0)
		for x in out.get_width():
			var u := 0.5 + ((x + 0.5) / out.get_width() - 0.5) / 5.0
			var texel := source.get_pixel(clampi(int(u * size.x), 0, size.x - 1), clampi(int(v * size.y), 0, size.y - 1))
			var brightness := maxf(texel.r, maxf(texel.g, texel.b)) * texel.a
			var color := Tracers.gradient(stops, brightness)
			out.set_pixel(x, y, Color(color.r, color.g, color.b, brightness))
	return out
