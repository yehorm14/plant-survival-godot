# Deterministic check of the bamboo harvest bonus (issue #3).
#
# Run headless from the project root:
#   godot --headless --path . --script res://tests/bamboo_harvest_test.gd
# Exits with status 1 if any check fails.
extends SceneTree

const SEED := 12345
const BAMBOO_SLOT := 7  # index of bamboo.tscn in GameState.INVENTORY_SLOT_ITEMS

var _failures := 0
var _scene: Node
var _loop: Node
var _gs: Node


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		printerr("FAIL: ", msg)
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# change_scene sets current_scene before _ready, which the game's scripts rely on.
	change_scene_to_file("res://scenes/grass_map.tscn")
	await process_frame
	await process_frame
	_scene = current_scene
	_loop = _scene.get_node("GameLoop")
	_gs = _scene.get_node("GameState")
	# Drive harvests by hand instead of by the real-time timer.
	_loop.set_process(false)
	_check(_gs.INVENTORY_SLOT_ITEMS[BAMBOO_SLOT] == "bamboo.tscn", "bamboo is inventory slot %d" % BAMBOO_SLOT)

	var base := await _harvest(0, true)
	var immature := await _harvest(2, false)
	var one := await _harvest(1, true)
	var three := await _harvest(3, true)

	_check(base.score == immature.score and base.score == one.score and base.score == three.score,
		"bamboo does not change score (%d)" % base.score)
	_check(immature.slots == base.slots, "no bamboo bonus from immature bamboo")
	_check(_delta(one.slots, base.slots) == _only_bamboo(1), "one mature bamboo adds 1 bamboo seed")
	_check(_delta(three.slots, base.slots) == _only_bamboo(3), "three mature bamboo add 3 bamboo seeds")

	# Tooltip, HUD and reward agree: the tooltip promises a seed, the HUD says seeds.
	var bamboo: Plant = load("res://plants/bamboo.tscn").instantiate()
	_check(bamboo.item_description.to_lower().contains("extra bamboo seed"), "tooltip promises a seed")
	bamboo.free()
	var hud_bamboo: Node = load("res://plants/bamboo.tscn").instantiate()
	_scene.get_node("Plants").add_child(hud_bamboo)
	await process_frame
	_loop._update_score_stuff()
	var hud: String = _scene.get_node("HUD/ScoreAndTimer2").text
	_check(hud.contains("+(1) BAMBOO SEED PER HARVEST"), "HUD shows the bonus as seeds: " + hud.replace("\n", " | "))
	_check(not hud.contains("BAMBOO SCORE"), "HUD no longer calls it score")

	_scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


# Plants `n` bamboo (mature or not), runs one harvest with a fixed RNG seed and
# returns the resulting inventory amounts and score. Plants are removed again.
func _harvest(n: int, mature: bool) -> Dictionary:
	var plants: Node = _scene.get_node("Plants")
	var added: Array[Node] = []
	for i in n:
		var b: Node = load("res://plants/bamboo.tscn").instantiate()
		plants.add_child(b)
		added.append(b)
	await process_frame
	for b in added:
		b.is_fully_grown = mature
	_loop._rng.seed = SEED
	_loop.score = 0
	for slot in _gs.inventory.slots:
		slot.amount = 0
	_loop._give_random_seed()
	var result := {
		"score": _loop.score,
		"slots": _gs.inventory.slots.map(func(s): return s.amount),
	}
	for b in added:
		plants.remove_child(b)
		b.free()
	return result


func _delta(a: Array, b: Array) -> Array:
	var d := []
	for i in a.size():
		d.append(a[i] - b[i])
	return d


func _only_bamboo(n: int) -> Array:
	var d := []
	for i in _gs.INVENTORY_SLOT_ITEMS.size():
		d.append(n if i == BAMBOO_SLOT else 0)
	return d
