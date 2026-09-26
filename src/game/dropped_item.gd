class_name DroppedItem
extends SimEntity

## An item lying in the world, or thrown to it: a gun with its ammo (its own
## Weapon, from the Inventory.Entry that was carried), a grenade, the Zeus,
## the kit. Its entity class is the item's (weapon_ak47, item_defuser). The
## C4 on the ground is the bomb's own entity, not one of these.
##
## It leaves the hand where the gun was held and pointing the way it was
## held (drop_from), flies under gravity turning as it was thrown, meets the
## world as the body it is in CS2 and comes to rest, then lies there until a
## player picks it up (ItemDrops) or a round's start clears the map.
##
## The body is the item's own physics hull from CS2's files (ItemPhysics):
## position is its centre of mass, not the model's origin, and basis the
## model's turn, so it spins about the centre of mass as a thrown gun does.
## Each tick it turns, finds what it touches (collide_shape: every contact
## the hull has, with the surface's normal), steps out of anything the turn
## took it into, answers each contact with an impulse at that point
## (restitution and friction from both surfaces, the inertia from the hull),
## and moves, its hull swept along the move (cast_motion, then get_rest_info
## for what it met), never a point. A gun that lands on its muzzle tumbles
## about its centre of mass and falls flat; on a slope it lies along the
## slope. Once it has stayed put for a while it sleeps: a resting item
## takes no queries at all. Its queries are counted (queries) as the
## player's traces are.
##
## Nothing cleans it up sooner: CS2's weapon_auto_cleanup_time and
## weapon_max_before_cleanup are both 0. Bullets pass through it, as
## mp_shoot_dropped_grenades is false. What blasts do to a gun on the ground
## is for later (the playtest page's issue 2, plan step 9). How CS2 combines
## two surfaces, when its bodies sleep and whether dropped guns meet player
## clips are in no file (measure; each is a named constant below).

## sv_gravity, as MovementConfig has it.
const GRAVITY := 800.0
## Who dropped it cannot take it straight back, so a gun thrown forward is
## not picked up again as it leaves the hand: CS2's
## mp_weapon_prev_owner_touch_time, 1.5 s.
const PREV_OWNER_TOUCH_USEC := 1_500_000
## Anyone else waits too: CS2's mp_weapon_next_owner_touch_time, 1.3 s. The
## convar has no description; that it is anyone else's wait, for every
## drop and a death's too, is read from its name (measure).
const NEXT_OWNER_TOUCH_USEC := 1_300_000
## How near a surface the hull counts as touching it, and how far off a
## surface it is kept after stepping out of it, so the next sweep does not
## start in it (a shape the sweep starts in is not met at all).
const CONTACT_MARGIN := 0.25
const SKIN := 0.05
## Under this speed into a surface nothing bounces: the project's own Jolt
## bounce_velocity_threshold (1 m/s, project.godot). CS2's is in no file
## (measure).
const BOUNCE_SPEED := 39.37
## How two surfaces combine, in no file (measure): the product of the
## elasticities, so a gun (weapon, 0.95) on concrete (0.2) keeps 0.19 of
## its speed into the floor, and the geometric mean of the frictions.
const RESTITUTION_RULE := "product"
const FRICTION_RULE := "geometric mean"
## How many passes the contacts' impulses get each tick.
const SOLVER_PASSES := 8
## Most contacts read in a tick (collide_shape gives them in pairs).
const MOST_CONTACTS := 16
## How many sweeps a tick's move may take: one, and one more for each
## surface met in it.
const MOST_SWEEPS := 3
## It sleeps once it has touched something every tick for this long and in
## that time stayed within SLEEP_DRIFT units of where it was and
## SLEEP_TURN radians of how it lay. Where it is, not how fast it goes: a
## gun lying on the floor takes a tick's gravity before its contacts take
## it back out, and rocks by a hair between them, so its speed at any one
## tick says little. CS2's thresholds are in no file (measure).
const SLEEP_USEC := 250_000
const SLEEP_DRIFT := 0.25
const SLEEP_TURN := 0.035
## The fastest it turns, in radians a second: about two turns a second.
## CS2's is in no file. Sid watched guns land in CS2 (2026-09-26): most
## bounce once, a small one sometimes a second time by an inch or two, a
## Glock thrown right up to 6 to 8 inches, and they feel heavy. With
## Jolt's own default (max_angular_velocity, 15 turns a second) a gun
## landing on an edge or an end spun up to it and cartwheeled and rolled
## along the floor, hopping a dozen times; at this it bounces once, rocks
## and lies down, as the checks measure.
const MOST_SPIN := 12.0
## However it moves, it sleeps this long after the drop, so a body caught
## rocking in a corner does not cost queries for the rest of the round.
const MOST_MOVING_USEC := 8_000_000

var entry: Inventory.Entry
## Its centre of mass's velocity.
var velocity := Vector3.ZERO
## Which way it points: the model's +Z is its muzzle, +Y its top, as a gun
## is held (PlayerSim.held_transform). And the tick before's, for drawing
## between the two. position is the centre of mass (ItemPhysics.Hull
## places the model from the two).
var basis := Basis.IDENTITY
var previous_basis := Basis.IDENTITY
## How it turns, in radians a second about the world's axes.
var angular_velocity := Vector3.ZERO
var resting: bool = false
## Simulation time it came to rest at; -1 while it moves.
var rested_usec: int = -1
## Simulation time it was dropped at.
var dropped_usec: int = 0
## When ItemDrops next looks for someone standing on it: first when anyone
## may take it, then every pickup check period.
var next_pickup_check_usec: int = 0
## Since when it has been touching something and staying put, and where
## it was and how it lay then; -1 while it is not.
var slow_since_usec: int = -1
var slow_from := Vector3.ZERO
var slow_basis := Basis.IDENTITY
## The last surface it touched, as the world's normal there (zero if none
## yet): what it lies on once at rest.
var ground_normal := Vector3.ZERO
## Physics queries it has made, all told: two a tick in flight, three a
## tick touching something and one more for each surface a move meets,
## none at rest.
var queries: int = 0


func _init(p_entry: Inventory.Entry = null, p_owner_id: int = GameEvents.NOBODY, p_position := Vector3.ZERO, p_velocity := Vector3.ZERO) -> void:
	super(p_entry.item.item_class if p_entry != null else "", p_owner_id, p_position)
	entry = p_entry
	velocity = p_velocity


## Puts entry on the ground from the player userid's middle, let fall with
## velocity: what a gun a purchase replaced does. The entity, already
## spawned into game.entities. It announces nothing: whoever took the item
## out of the inventory sends item_remove, once.
static func drop(game: GameSystems, userid: int, p_entry: Inventory.Entry, p_velocity := Vector3.ZERO) -> DroppedItem:
	var node := game.roster.player(userid)
	var from := node.global_position + Vector3.UP * 36.0 if node != null else Vector3.ZERO
	return drop_from(game, userid, p_entry, Transform3D(Basis.IDENTITY, from), p_velocity)


## Puts entry in the world as held at from (the model's root bone, where
## the hand held it, and which way it pointed: HeldPose), its centre of
## mass thrown with velocity and turning with spin.
static func drop_from(
	game: GameSystems, userid: int, p_entry: Inventory.Entry, from: Transform3D,
	p_velocity := Vector3.ZERO, spin := Vector3.ZERO
) -> DroppedItem:
	var item := DroppedItem.new(p_entry, userid, Vector3.ZERO, p_velocity)
	var body := item.physics().body_of(item.physics().model_held_at(Transform3D(from.basis.orthonormalized(), from.origin)))
	item.position = body.origin
	item.previous_position = body.origin
	item.basis = body.basis.orthonormalized()
	item.previous_basis = item.basis
	item.angular_velocity = spin
	item.dropped_usec = game.now_usec()
	item.next_pickup_check_usec = item.dropped_usec + mini(PREV_OWNER_TOUCH_USEC, NEXT_OWNER_TOUCH_USEC)
	game.entities.spawn(item)
	return item


## Its body: the item's hull, centre of mass, mass and inertia.
func physics() -> ItemPhysics.Hull:
	return ItemPhysics.of(entity_class)


## Where its model is: origin and turn.
func model_transform() -> Transform3D:
	return physics().model_of(Transform3D(basis, position))


## Whether userid may pick it up at now_usec.
func can_be_taken_by(userid: int, now_usec: int) -> bool:
	var wait := PREV_OWNER_TOUCH_USEC if userid == owner_id else NEXT_OWNER_TOUCH_USEC
	return now_usec >= dropped_usec + wait


func tick(t: SimTick) -> void:
	previous_basis = basis
	if resting:
		return
	if t.space == null:
		# No world to fall onto: it stays where it was dropped.
		_rest(t.now_usec)
		return
	var hull := physics()
	var dt := t.dt
	velocity *= maxf(0.0, 1.0 - hull.linear_damping * dt)
	angular_velocity *= maxf(0.0, 1.0 - hull.angular_damping * dt)
	angular_velocity = angular_velocity.limit_length(MOST_SPIN)
	if angular_velocity != Vector3.ZERO:
		basis = (Basis(angular_velocity.normalized(), angular_velocity.length() * dt) * basis).orthonormalized()

	# What the turned hull touches, and out of anything it went into.
	var contacts := _contacts(t.space, hull)
	var touching := not contacts.is_empty()
	var start_velocity := velocity
	velocity.y -= GRAVITY * dt
	var motion := (start_velocity + velocity) * 0.5 * dt
	if touching:
		var surface := _surface_at(t.space, hull)
		_push_out(contacts)
		_resolve(contacts, hull, surface, dt)
		motion = velocity * dt

	# The move, the hull swept along it.
	for sweep in MOST_SWEEPS:
		if motion.length_squared() < 1e-8:
			break
		var hit := _sweep(t.space, hull, motion)
		var safe: float = hit["safe"]
		position += motion * safe
		if not hit.has("normal"):
			break
		var normal: Vector3 = hit["normal"]
		if touching:
			# Already answered this tick's contacts: only what is left of
			# the move into this surface stops.
			velocity -= normal * minf(velocity.dot(normal), 0.0)
		else:
			# A new impact, on the one point it lands on.
			_resolve([{"point": hit["point"], "normal": normal, "depth": 0.0}], hull, String(hit["surface"]), dt)
		touching = true
		position += normal * SKIN
		motion = velocity * dt * (1.0 - safe)

	_settle(t.now_usec, touching)


## Every point the hull touches or is in, at its pose now, as {point on
## the hull, normal out of the world, depth into it (less than zero: a
## gap)}. collide_shape finds the surfaces within CONTACT_MARGIN, but gives
## a full set of points only where the hull is in them; a hull lying a hair
## above a floor gets one or two, and would rock on them. So each surface
## found is taken as a plane, and every corner of the hull near that plane
## is a contact: a gun lying flat stands on all the corners it lies on.
func _contacts(space: PhysicsDirectSpaceState3D, hull: ItemPhysics.Hull) -> Array[Dictionary]:
	var query := _query(hull)
	query.margin = CONTACT_MARGIN
	queries += 1
	var pairs := space.collide_shape(query, MOST_CONTACTS)
	# In pairs: the point on the hull (grown by the margin), and the point
	# on the world; from the one to the other is the way out.
	var planes: Array[Dictionary] = []
	for i in range(0, pairs.size() - 1, 2):
		var out_of := pairs[i + 1] - pairs[i]
		var length := out_of.length()
		if length < 1e-5:
			continue
		var normal := out_of / length
		var same := false
		for plane in planes:
			if normal.dot(plane["normal"]) > 0.99 and absf((pairs[i + 1] - (plane["point"] as Vector3)).dot(normal)) < 0.1:
				same = true
				break
		if not same:
			planes.append({"point": pairs[i + 1], "normal": normal, "depth": length - CONTACT_MARGIN})
	var out: Array[Dictionary] = []
	if planes.is_empty():
		return out
	var body := Transform3D(basis, position)
	var corners := PackedVector3Array()
	for point in hull.points:
		corners.append(body * (point - hull.centre_of_mass))
	for plane in planes:
		var normal: Vector3 = plane["normal"]
		var found := 0
		for corner in corners:
			var height := (corner - (plane["point"] as Vector3)).dot(normal)
			if height < CONTACT_MARGIN:
				out.append({"point": corner, "normal": normal, "depth": -height})
				found += 1
		if found == 0:
			# An edge across an edge: no corner near, the one point it has.
			out.append(plane)
	return out


## The surface it touches most, by name (the hull part's), for how it
## bounces and slides.
func _surface_at(space: PhysicsDirectSpaceState3D, hull: ItemPhysics.Hull) -> String:
	var query := _query(hull)
	query.margin = CONTACT_MARGIN
	queries += 1
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		ground_normal = rest["normal"]
	return _surface_name(rest)


## Steps it out of what it went into, a skin clear of each surface it
## touches.
func _push_out(contacts: Array[Dictionary]) -> void:
	var push := Vector3.ZERO
	for pass_number in 4:
		var moved := false
		for contact in contacts:
			var need: float = float(contact["depth"]) + SKIN - push.dot(contact["normal"])
			if float(contact["depth"]) + SKIN > 0.0 and need > 1e-4:
				push += (contact["normal"] as Vector3) * need
				moved = true
		if not moved:
			break
	position += push
	for contact in contacts:
		contact["depth"] = float(contact["depth"]) - push.dot(contact["normal"])


## Answers contacts with impulses at their points: nothing goes further
## into a surface than its gap allows, what hit it fast enough bounces off
## at the two surfaces' restitution, and friction takes what slides, up to
## the two surfaces' friction times the push. Per unit of mass: the mass
## cancels out against the unmoving world.
func _resolve(contacts: Array, hull: ItemPhysics.Hull, surface: String, dt: float) -> void:
	var restitution := combined_restitution(hull.surface, surface)
	var friction := combined_friction(hull.surface, surface)
	var world_inverse := basis * hull.inverse_inertia * basis.transposed()
	var targets := PackedFloat32Array()
	var pushed := PackedFloat32Array()
	var slid: Array[Vector3] = []
	for contact in contacts:
		var arm: Vector3 = (contact["point"] as Vector3) - position
		var normal: Vector3 = contact["normal"]
		var into := (velocity + angular_velocity.cross(arm)).dot(normal)
		var target := -restitution * into if into < -BOUNCE_SPEED else 0.0
		# A gap may close this tick: it is not stopped short of the surface.
		if target <= 0.0:
			# A gap may close this tick, down to the skin: it is not
			# stopped short of the surface.
			target = -maxf(-float(contact["depth"]) - SKIN, 0.0) / dt
		targets.append(target)
		pushed.append(0.0)
		slid.append(Vector3.ZERO)
	for pass_number in SOLVER_PASSES:
		for i in contacts.size():
			var contact: Dictionary = contacts[i]
			var arm: Vector3 = (contact["point"] as Vector3) - position
			var normal: Vector3 = contact["normal"]
			var at := velocity + angular_velocity.cross(arm)
			var k := _effective(world_inverse, arm, normal)
			var impulse := (targets[i] - at.dot(normal)) / k
			var total := maxf(pushed[i] + impulse, 0.0)
			impulse = total - pushed[i]
			pushed[i] = total
			_apply(world_inverse, arm, normal * impulse)
			# Friction, against what slides along the surface.
			at = velocity + angular_velocity.cross(arm)
			var along := at - normal * at.dot(normal)
			if along.length_squared() < 1e-10:
				continue
			var way := along.normalized()
			var wanted := slid[i] - way * along.length() / _effective(world_inverse, arm, way)
			var most := friction * pushed[i]
			if wanted.length() > most:
				wanted = wanted.normalized() * most
			_apply(world_inverse, arm, wanted - slid[i])
			slid[i] = wanted


## How much an impulse along way at arm changes the speed there, per unit
## of mass.
static func _effective(world_inverse: Basis, arm: Vector3, way: Vector3) -> float:
	return 1.0 + way.dot((world_inverse * arm.cross(way)).cross(arm))


func _apply(world_inverse: Basis, arm: Vector3, impulse: Vector3) -> void:
	velocity += impulse
	angular_velocity += world_inverse * arm.cross(impulse)


## Sweeps the hull from where it is along motion: how far it got (safe, 0
## to 1), and what it met there if anything (point, normal, surface).
func _sweep(space: PhysicsDirectSpaceState3D, hull: ItemPhysics.Hull, motion: Vector3) -> Dictionary:
	var query := _query(hull)
	query.motion = motion
	queries += 1
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return {"safe": 1.0}
	query.transform = Transform3D(basis, position + motion * fractions[1])
	query.motion = Vector3.ZERO
	queries += 1
	var rest := space.get_rest_info(query)
	if rest.is_empty():
		return {"safe": fractions[0]}
	var normal: Vector3 = rest["normal"]
	if normal.length_squared() < 1e-6:
		normal = -motion.normalized()
	ground_normal = normal.normalized()
	return {"safe": fractions[0], "point": rest["point"], "normal": ground_normal, "surface": _surface_name(rest)}


func _query(hull: ItemPhysics.Hull) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = Transform3D(basis, position)
	query.collision_mask = Hitscan.WORLD_LAYER
	return query


## The surface a shape query met: the hull part's node name, as
## Penetration names surfaces.
static func _surface_name(rest: Dictionary) -> String:
	var collider := instance_from_id(int(rest.get("collider_id", 0))) if not rest.is_empty() else null
	if collider is CollisionObject3D and rest.has("shape"):
		var owner_id: int = (collider as CollisionObject3D).shape_find_owner(int(rest["shape"]))
		var shape_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if shape_node != null:
			return Penetration.surface_for(shape_node.name)
	return SurfaceProperties.ROOT


## RESTITUTION_RULE: the product of the two surfaces' elasticities.
static func combined_restitution(own: String, other: String) -> float:
	return _surface_value(own, "elasticity", 0.25) * _surface_value(other, "elasticity", 0.25)


## FRICTION_RULE: the geometric mean of the two surfaces' frictions.
static func combined_friction(own: String, other: String) -> float:
	return sqrt(_surface_value(own, "friction", 0.8) * _surface_value(other, "friction", 0.8))


static func _surface_value(surface: String, column: String, fallback: float) -> float:
	var value := SurfaceProperties.value(surface, column)
	return fallback if is_nan(value) else value


## Asleep once it has touched something and stayed put for SLEEP_USEC, or
## once MOST_MOVING_USEC have gone by.
func _settle(now_usec: int, touching: bool) -> void:
	if not touching:
		slow_since_usec = -1
	elif slow_since_usec < 0 or position.distance_to(slow_from) > SLEEP_DRIFT \
			or (slow_basis.inverse() * basis).get_rotation_quaternion().get_angle() > SLEEP_TURN:
		slow_since_usec = now_usec
		slow_from = position
		slow_basis = basis
	if (slow_since_usec >= 0 and now_usec - slow_since_usec >= SLEEP_USEC) or now_usec - dropped_usec >= MOST_MOVING_USEC:
		_rest(now_usec)


func _rest(now_usec: int) -> void:
	resting = true
	rested_usec = now_usec
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func save_state() -> Dictionary:
	var state := super()
	state["item"] = entry.item.item_class if entry != null else ""
	state["ammo"] = entry.weapon.ammo if entry != null and entry.weapon != null else 0
	state["reserve"] = entry.weapon.reserve if entry != null and entry.weapon != null else 0
	state["count"] = entry.count if entry != null else 0
	state["velocity"] = velocity
	state["basis"] = basis
	state["previous_basis"] = previous_basis
	state["angular_velocity"] = angular_velocity
	state["resting"] = resting
	state["rested_usec"] = rested_usec
	state["dropped_usec"] = dropped_usec
	state["next_pickup_check_usec"] = next_pickup_check_usec
	state["slow_since_usec"] = slow_since_usec
	state["slow_from"] = slow_from
	state["slow_basis"] = slow_basis
	state["ground_normal"] = ground_normal
	return state


func load_state(state: Dictionary) -> void:
	super(state)
	velocity = state.get("velocity", velocity)
	basis = state.get("basis", basis)
	previous_basis = state.get("previous_basis", previous_basis)
	angular_velocity = state.get("angular_velocity", angular_velocity)
	resting = state.get("resting", resting)
	rested_usec = state.get("rested_usec", rested_usec)
	dropped_usec = state.get("dropped_usec", dropped_usec)
	next_pickup_check_usec = state.get("next_pickup_check_usec", next_pickup_check_usec)
	slow_since_usec = state.get("slow_since_usec", slow_since_usec)
	slow_from = state.get("slow_from", slow_from)
	slow_basis = state.get("slow_basis", slow_basis)
	ground_normal = state.get("ground_normal", ground_normal)
	var def := ItemRegistry.item(state.get("item", ""))
	if def == null:
		return
	var weapon: Weapon = null
	if def.is_gun:
		weapon = Weapon.new(ItemRegistry.weapon_data(def.item_class))
		weapon.ammo = state.get("ammo", weapon.ammo)
		weapon.reserve = state.get("reserve", weapon.reserve)
	entry = Inventory.Entry.new(def, weapon, state.get("count", 1))
