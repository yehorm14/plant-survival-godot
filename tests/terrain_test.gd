# Deterministic check that flooding and volcano placement use the effective
# terrain (ActiveLayer tile if present, otherwise the BackgroundLayer tile).
#
# Run headless from the project root:
#   godot --headless --path . --script res://tests/terrain_test.gd
# Exits with status 1 if any check fails.
extends SceneTree

const GRASS := Vector2i(0, 0)
const WATER := Vector2i(1, 0)
const ROCK := Vector2i(2, 0)

var _failures := 0
var _scene: Node
var _loop: Node
var _active: TileMapLayer
var _bg: TileMapLayer


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		printerr("FAIL: ", msg)
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/grass_map.tscn")
	await process_frame
	await process_frame
	_scene = current_scene
	_loop = _scene.get_node("GameLoop")
	_loop.set_process(false)
	_active = _scene.get_node("ActiveLayer")
	_bg = _scene.get_node("BackgroundLayer")
	_loop._rng.seed = 7

	var vp: Vector2 = _loop.get_viewport().get_visible_rect().size
	var tw := int(vp.x / 16)
	var th := int(vp.y / 16)

	# Fixture: bare background grass everywhere, nothing on the ActiveLayer.
	_clear(tw, th)
	_check(_active.get_used_cells().is_empty(), "fixture: ActiveLayer is empty")

	# Flooding: water on the ActiveLayer spreads onto plain background grass.
	var start := Vector2i(10, 10)
	_active.set_cell(start, 0, WATER, 0)
	_loop._spread_water_from(start, 1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_check(_active.get_cell_atlas_coords(start + d) == WATER, "background grass at %s floods" % [start + d])
	_check(_active.get_cell_source_id(start + Vector2i(1, 1)) == -1, "diagonal tile is not flooded in one step")

	# Blocked terrain: an ActiveLayer rock over background grass stays rock.
	_clear(tw, th)
	_active.set_cell(start, 0, WATER, 0)
	_active.set_cell(start + Vector2i(1, 0), 0, ROCK, 0)
	_loop._spread_water_from(start, 1)
	_check(_active.get_cell_atlas_coords(start + Vector2i(1, 0)) == ROCK, "rock over grass is not flooded")
	_check(_active.get_cell_atlas_coords(start + Vector2i(-1, 0)) == WATER, "open grass beside the rock still floods")

	# Map bounds: tiles outside the map (no cell on either layer) are not flooded.
	_clear(tw, th)
	var edge := Vector2i(0, 0)
	_bg.erase_cell(Vector2i(-1, 0))
	_active.set_cell(edge, 0, WATER, 0)
	_loop._spread_water_from(edge, 1)
	_check(_active.get_cell_source_id(Vector2i(-1, 0)) == -1, "no flooding outside the map")
	_check(_active.get_cell_atlas_coords(Vector2i(1, 0)) == WATER, "in-map neighbour still floods")

	# Volcano: a 4x4 rect of background grass is placeable; rock or a hole is not.
	_clear(tw, th)
	var tl := Vector2i(8, 8)
	_check(_loop._rect_placeable(tl, 4, 4), "4x4 background grass is placeable")
	_check(_loop._find_volcano_spot() != null, "volcano finds a spawn on background grass")
	_active.set_cell(tl + Vector2i(2, 2), 0, ROCK, 0)
	_check(not _loop._rect_placeable(tl, 4, 4), "ActiveLayer rock blocks the rect")
	_active.erase_cell(tl + Vector2i(2, 2))
	_active.set_cell(tl + Vector2i(1, 1), 0, WATER, 0)
	_check(not _loop._rect_placeable(tl, 4, 4), "ActiveLayer water blocks the rect")
	_active.erase_cell(tl + Vector2i(1, 1))
	_bg.erase_cell(tl + Vector2i(3, 3))
	_check(not _loop._rect_placeable(tl, 4, 4), "a tile outside the map blocks the rect")

	# Occupied: a plant on the only candidate area blocks it; fully blocked terrain gives no spot.
	_clear(tw, th)
	var plant: Node = load("res://plants/bamboo.tscn").instantiate()
	_scene.get_node("Plants").add_child(plant)
	plant.global_position = _active.to_global(_active.map_to_local(tl + Vector2i(1, 1)))
	_check(_loop._rect_has_plant(tl, 4, 4), "a plant occupies the rect")
	_scene.get_node("Plants").remove_child(plant)
	plant.free()
	for y in th:
		for x in tw:
			_active.set_cell(Vector2i(x, y), 0, ROCK, 0)
	_check(_loop._find_volcano_spot() == null, "no volcano spot when all terrain is blocked")

	_scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


# Bare background grass over the whole viewport area, empty ActiveLayer.
func _clear(tw: int, th: int) -> void:
	_active.clear()
	_bg.clear()
	for y in th:
		for x in tw:
			_bg.set_cell(Vector2i(x, y), 0, GRASS, 0)
