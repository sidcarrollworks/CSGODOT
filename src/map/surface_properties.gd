class_name SurfaceProperties
extends RefCounted

## CS2's surfaces, from the game's own files: reference/surfaces/surfaces.csv,
## written by scripts/surface_tables.gd from surfaceproperties.vsurf and
## surfaceproperties_game.txt (scripts/extract_assets.sh surfaces). 164 of
## them, each with its parent, its physics and the game's values: the
## material letter, the jump and speed factors, and the two a round going
## through it uses (Penetration). reference/surfaces/surfaces.md lists them
## resolved.
##
## A surface gives only what differs from its parent, and default is where
## every chain ends, so value() walks up the parents: Wood_Plank takes its
## damage modifier from Wood_Box, which takes it from Wood.
##
## Surfaces are keyed by lower-case name, as the collision hull spells them
## (physics_group_wood_plank); spelling() gives the game's own.

const PATH := "res://reference/surfaces/surfaces.csv"
const ROOT := "default"

## How far a chain of parents is followed: CS2's longest is four
## (slidingrubbertire_jalopyfront to dirt).
const MOST_PARENTS := 16

static var _rows := {}


## Every surface's row, by lower-case name: the columns of surfaces.csv as
## strings, empty where the surface takes its parent's.
static func rows() -> Dictionary:
	if _rows.is_empty():
		_rows = _load(PATH)
	return _rows


static func has(surface: String) -> bool:
	return rows().has(surface.to_lower())


## Every surface, by lower-case name.
static func names() -> PackedStringArray:
	return PackedStringArray(rows().keys())


## The game's own spelling of a surface (Wood_Plank), default's for one it
## does not have.
static func spelling(surface: String) -> String:
	return String((rows().get(surface.to_lower(), rows().get(ROOT, {})) as Dictionary).get("name", ROOT))


## A surface's parent, by lower-case name; empty for one without.
static func parent(surface: String) -> String:
	return String((rows().get(surface.to_lower(), {}) as Dictionary).get("parent", "")).to_lower()


## A value as the surface has it: its own, else its parent's, and so on up to
## default's. Empty where not even default gives it.
static func text(surface: String, column: String) -> String:
	var at := surface.to_lower() if has(surface) else ROOT
	for i in MOST_PARENTS:
		var row: Dictionary = rows().get(at, {})
		var own := String(row.get(column, ""))
		if not own.is_empty():
			return own
		at = String(row.get("parent", "")).to_lower()
		if at.is_empty():
			break
	return String((rows().get(ROOT, {}) as Dictionary).get(column, ""))


## text() as a number: NAN where it is not one.
static func value(surface: String, column: String) -> float:
	var found := text(surface, column)
	return found.to_float() if found.is_valid_float() else NAN


## The friction a player walking on the surface gets, as a share of the
## usual: its physics friction times 1.25, at most 1, so default's 0.8 is 1
## and ice's 0.1 is 0.125. Source scales ground friction and acceleration by
## it (CGameMovement::CategorizeGroundSurface, gamemovement.cpp in the
## Source SDK 2013). Of the surfaces dust2's hull is made of, all give a
## player the whole of it but glass (0.625) and pottery (0.5).
static func player_friction(surface: String) -> float:
	var friction := value(surface, "friction")
	return 1.0 if is_nan(friction) else minf(friction * 1.25, 1.0)


static func _load(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No surfaces at %s (scripts/extract_assets.sh surfaces)" % path)
		return out
	var columns := file.get_csv_line()
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() != columns.size():
			continue
		var row := {}
		for i in columns.size():
			row[columns[i]] = cells[i]
		out[String(row["name"]).to_lower()] = row
	return out
