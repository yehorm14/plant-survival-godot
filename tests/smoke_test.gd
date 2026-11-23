# Deterministic gameplay smoke test (issue #4).
#
# Plays the real game scene headless with a shortened timer and checks:
#   1. the run does not start until the first seed is placed,
#   2. placing the first seed (through the real mouse-placement code) starts it,
#   3. harvests add seeds to the inventory while it runs,
#   4. game_over fires exactly once, as a win when the plant survives,
#   5. game_over fires exactly once, as a loss when all plants die.
#
# Run from the project root (after `godot --headless --import` on a fresh clone):
#   godot --headless --path . --script res://tests/smoke_test.gd
# Exits with status 1 on any failed check, and also on a hang (timeout).
extends SceneTree

const GAME_SCENE := "res://scenes/grass_map.tscn"
const DURATION := 3.0
const SEED_INTERVAL := 0.5
const RNG_SEED := 42
const TIMEOUT_SEC := 30.0

var _failures := 0
var _scene: Node
var _loop: Node
var _gs: Node
var _game_over_calls: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		printerr("FAIL: ", msg)
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Watchdog: a hang (e.g. game_over never fires) must fail the test, not stall CI.
	create_timer(TIMEOUT_SEC).timeout.connect(func():
		printerr("FAIL: timed out after %ss" % TIMEOUT_SEC)
		quit(1))

	print("--- scenario: survive until the timer ends (win)")
	await _load_game()
	await _start_run()
	await _wait_for_game_over()
	_check(_game_over_calls == [true], "game_over fired exactly once, with won=true (got %s)" % [_game_over_calls])
	_check(_total_seeds() >= 4, "harvests added seeds to the inventory (total %d)" % _total_seeds())
	_check(_scene.get_node("HUD/YouScored").visible and _scene.get_node("HUD/YouScored").text.begins_with("YOU WON"),
		"end screen says YOU WON")
	# No further emissions after the end.
	for i in 30:
		await process_frame
	_check(_game_over_calls.size() == 1, "game_over did not fire again afterwards")

	print("--- scenario: every plant dies (loss)")
	await _load_game()
	await _start_run()
	for p in _scene.get_node("Plants").get_children():
		p.free()
	await _wait_for_game_over()
	_check(_game_over_calls == [false], "game_over fired exactly once, with won=false (got %s)" % [_game_over_calls])
	_check(_scene.get_node("HUD/YouScored").text.begins_with("YOU LOST"), "end screen says YOU LOST")
	for i in 30:
		await process_frame
	_check(_game_over_calls.size() == 1, "game_over did not fire again afterwards")

	quit(1 if _failures > 0 else 0)


func _load_game() -> void:
	if _scene:
		_scene.queue_free()
		await process_frame
	_game_over_calls = []
	# change_scene sets current_scene before _ready, which the game's scripts rely on.
	change_scene_to_file(GAME_SCENE)
	await process_frame
	await process_frame
	_scene = current_scene
	_loop = _scene.get_node("GameLoop")
	_gs = _scene.get_node("GameState")
	# Shorten the run and make randomness reproducible.
	_loop.game_duration_seconds = int(DURATION)
	_loop._time_left = DURATION
	_loop.seed_interval = SEED_INTERVAL
	_loop._rng.seed = RNG_SEED
	_loop.game_over.connect(func(won): _game_over_calls.append(won))


# Selects the first inventory slot and places it with real mouse input, then
# checks the run started. Also checks that it had not started before.
func _start_run() -> void:
	for i in 10:
		await process_frame
	_check(not _loop._game_started, "run has not started before the first seed is placed")
	_check(is_equal_approx(_loop._time_left, DURATION), "timer is frozen before the first seed")
	_check(_scene.get_node("Plants").get_child_count() == 0, "no plants yet")

	var tile := _find_placeable_tile()
	_check(tile != Vector2i(-1, -1), "found a placeable tile")
	_gs.seed_selected(_gs.inventory.slots[0].seed, 0)
	var pos := Vector2(tile * 16) + Vector2(8, 8)
	_mouse_move(pos)
	await process_frame
	_mouse_button(pos, true)
	await process_frame
	await process_frame
	_mouse_button(pos, false)
	await process_frame

	_check(_scene.get_node("Plants").get_child_count() == 1, "first seed was placed")
	_check(_gs.inventory.slots[0].amount == 0, "placing consumed the seed")
	for i in 5:
		await process_frame
	_check(_loop._game_started, "run started after the first seed")
	_check(_loop._time_left < DURATION, "timer is running (%.2fs left)" % _loop._time_left)


func _wait_for_game_over() -> void:
	while _game_over_calls.is_empty():
		await process_frame


func _find_placeable_tile() -> Vector2i:
	for t in _gs.bgLayer.get_used_cells():
		if _gs.can_place_at(Vector2(t)):
			return t
	return Vector2i(-1, -1)


func _total_seeds() -> int:
	var n := 0
	for s in _gs.inventory.slots:
		n += s.amount
	return n


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)
