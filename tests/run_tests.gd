extends SceneTree
## Headless tests for tutorial 11. From the repository root:
##   godot --headless --path godot/11-health-and-death -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.
## `-- --only=text` runs the tests whose name contains the text (for example `-- --only=hazard`).
## `-- --previous=/abs/dir` points the comparison with tutorial 10 at a copy of its project (default: the folder
## `../10-numbered-doors` next to this project); without either of them those tests are skipped and say so.
##
## Saves: every level the tests load gets its own temporary save file and its own settings file (OS temp dir), so a test run
## never reads or writes the real best_times.json or settings.json.
## What the tests prove is what the narration and the README claim; the video shows the game (series rule 33), the figures
## are measured here and printed (the lines that start with spaces under a PASS).

const Autopilot := preload("res://tools/autopilot.gd")
const Chain := preload("res://steps/step_04_one_revive_per_run/room_chain.gd") ## The finished chain: only its types and its constants are used.

const STEPS: Array[String] = [
	"step_00_start",
	"step_01_health",
	"step_02_a_hazard_that_hurts",
	"step_03_the_death_screen",
	"step_04_one_revive_per_run",
]
const FINAL_STEP := "step_04_one_revive_per_run"
const HEALTH_STEPS: Array[String] = ["step_01_health", "step_02_a_hazard_that_hurts", "step_03_the_death_screen", "step_04_one_revive_per_run"] ## The steps with a Health node.
const HAZARD_STEPS: Array[String] = ["step_02_a_hazard_that_hurts", "step_03_the_death_screen", "step_04_one_revive_per_run"] ## The steps with a hazard.
const DEATH_STEPS: Array[String] = ["step_03_the_death_screen", "step_04_one_revive_per_run"] ## The steps in which the run can end in death.
const HAZARD_STEP := "step_02_a_hazard_that_hurts" ## The step that brings the Live Wire.
const DEATH_STEP := "step_03_the_death_screen" ## The step that brings the death screen and the Broken Glass.
const THIS_FOLDER := "11-health-and-death"
const PREVIOUS_FOLDER := "10-numbered-doors" ## Tutorial 10, which sits next to this project in the repository.
const PREVIOUS_FINAL_STEP := "step_03_number_plate" ## Its last step is this tutorial's step 0.

## What each step changes against the one before (file names under the step folder; .uid files do not count).
const CHANGES: Dictionary[String, Dictionary] = {
	"step_01_health": {changed = ["hud.gd", "level.gd", "main.tscn", "player.tscn"], added = ["health.gd"]},
	"step_02_a_hazard_that_hurts": {changed = ["props/long_set.tres", "props/straight_set.tres", "props/wide_set.tres"], added = ["hazard.gd", "props/live_wire.tscn"]},
	"step_03_the_death_screen": {changed = ["hud.gd", "level.gd", "main.tscn", "props/turn_left_set.tres", "props/turn_right_set.tres", "props/wide_set.tres"], added = ["props/broken_glass.tscn"]},
	"step_04_one_revive_per_run": {changed = ["health.gd", "hud.gd", "level.gd", "main.tscn"], added = []},
}

## The labels of a step's HUD scene that step 0 does not have: by path below the HUD, with the text the scene holds.
const HUD_EXTRA: Dictionary[String, Dictionary] = {
	"step_00_start": {},
	"step_01_health": {"Stats/HealthLabel": "Health 100"},
	"step_02_a_hazard_that_hurts": {"Stats/HealthLabel": "Health 100"},
	"step_03_the_death_screen": {
		"Stats/HealthLabel": "Health 100",
		"DeathPanel/Rows/DeathTitle": "You died",
		"DeathPanel/Rows/DeathCause": "Hit by Live Wire",
		"DeathPanel/Rows/DeathHint": "R  run again    N  next seed    T  type a seed",
	},
	"step_04_one_revive_per_run": {
		"Stats/HealthLabel": "Health 100",
		"DeathPanel/Rows/DeathTitle": "You died",
		"DeathPanel/Rows/DeathCause": "Hit by Live Wire",
		"DeathPanel/Rows/DeathHint": "E  revive    R  run again",
	},
}

## The actions of tutorial 10 (this tutorial adds revive).
const ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "jump", "walk", "look_left", "look_right", "look_up", "look_down",
	"toggle_debug", "regenerate", "next_seed", "edit_seed", "copy_seed", "capture_mouse",
	"toggle_view", "toggle_gizmos", "toggle_watch", "step_generation", "open_settings",
	"revive",
]

const STATE_READY := 0 ## Level.State
const STATE_RUNNING := 1
const STATE_FINISHED := 2
const STATE_DEAD := 3 ## Steps 3 and 4 only.
const SPEED_UP := 4 ## The walking tests run this many times faster than real time.
const PLAN_SEEDS := 200 ## Seeds 1..200 for the comparisons between steps.
const SWEEP_SEEDS := 200 ## Seeds 1..200 of the finished game for the autopilot sweep.
const CONTENT_SEEDS := 200 ## Seeds 1..200 for the contents check of tutorial 05.
const SWEEP_WORKERS := 5 ## Processes the sweep is split over (tools/sweep_seeds.gd, 8 times real time each).
const GOAL_ROOM := 20 ## The goal room of the game, and of the numbers tests.
const REST_FOV := 75.0 ## Degrees, vertical: the camera's default.
const NUMBER_SEEDS := 60 ## Seeds 1..60 for the numbers of every door of a run.
const NODE_SEEDS := 10 ## Seeds 1..10 for the hazard nodes a level makes.
const WALKED_SEEDS: Array[int] = [42, 7, 141] ## The seeds the real player walks to the goal room.
const MOVEMENT_SEEDS: Array[int] = [42, 1000] ## The seeds whose runs are compared tick for tick.
const HIT_INTERVAL_TICKS := 30 ## The hazards' 0.5 s at 60 physics ticks a second.
const WIRE_START := Vector3(0.0, 0.0, -3.5) ## The player in the small test scene, looking along -z at the hazard 1.5 m ahead.
const WIRE_AT := Vector3(0.0, 0.0, -5.0) ## The hazard's origin: its box covers z -6 to -5, x -0.5 to 0.5, 0 to 0.6 m up.
const WIRE_MIDDLE_Z := -5.5 ## The middle of the box: standing here the player is inside it for good.

## Counts the errors the engine logs. A test that hits a script error stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var script_only := true ## false: warnings and errors of the engine count, too.
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if script_only and error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

## Calls its callback once per physics tick, before the player's own tick.
class Driver extends Node:
	signal finished
	var tick: Callable

	func _physics_process(_delta: float) -> void:
		if tick.is_valid() and tick.call():
			tick = Callable()
			finished.emit()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.
var _notes: Array[String] = [] ## The figures the running test measured: printed under its PASS or FAIL line.
var _skipped_whole := false ## The running test skipped itself completely: no PASS line for it.
var _save_dir := ""
var _save_counter := 0
var _plans_cache := {} ## "step:seed" -> the plans of that run up to the goal room: several tests read the same plans.

func _initialize() -> void:
	OS.add_logger(_script_errors)
	await process_frame
	var started := Time.get_ticks_msec()
	_save_dir = OS.get_temp_dir().path_join("phaix-godot-11-tests-%d" % OS.get_process_id()) # one folder per run: two runs at the same time must not wipe each other's save files
	_wipe_save_dir()

	await _run("code rules: no class_name, no global random, no wall clock, input only through named actions", test_code_rules)
	await _run("steps: each step changes only what its concept needs, everything else is copied forward", test_copy_forward)
	await _run("steps: every script has a .uid file, no two share one, step 0's are tutorial 10's", test_uid_files)
	await _run("step_00_start: the final state of tutorial 10, file for file (only the folder names differ)", test_step_zero_is_tutorial_10)
	await _run("steps: the usage comments in every step name this project, not tutorial 10", test_steps_name_this_project)
	await _run("project root: the figure, the sounds, the materials and the buses are tutorial 10's, byte for byte; project.godot differs in exactly five things", test_root_is_tutorial_10)
	await _run("project: Jolt, the actions of tutorial 10 and revive on E, the main scene is the final step", test_project_settings)
	await _run("hud: every step says what step 0 says, plus the health from step 1 and the death screen from step 3; the Input Map is tutorial 10's plus revive and the A button on ui_accept", test_hud_and_input_map)
	await _run("plans: all five steps plan the rooms, locks, keys and lamps of step 0 (seeds 1-%d); only the props differ from step 2 on" % PLAN_SEEDS, test_steps_plan_the_same)
	await _run("readme: the credits name the folders that stand in the project, every path the README names exists, every step is in it", test_readme_matches_folders)

	# Tutorial 11, step 1: health is a node of its own.
	for step in HEALTH_STEPS:
		await _run("health %s: hurt takes off the amount, never below 0, a hit of 0 or less does nothing, died goes out once with the last cause, reset fills" % step, test_health_node.bind(step))
		await _run("health %s: the player has one child named Health, the level keeps it, the HUD shows it and R fills it again" % step, test_health_in_the_scene.bind(step))
	await _run("health: health.gd is the same code in steps 1 to 3; step 4 adds only the grace (grace, safe_left, _physics_process, the check in hurt, protect)", test_health_code_is_the_same)
	await _run("health step 4: after protect() no hit counts for one second of physics time (grace 1.0), the first hit after it counts, without protect() a hit counts at once", test_health_grace)

	# Step 2: a hazard that hurts.
	await _run("hazard sets: the Live Wire is in the straight, long and wide room sets with the weights of the narration, the Broken Glass in the two turns and the wide room, no step before has either", test_hazards_in_the_prop_sets)
	for step in HAZARD_STEPS:
		await _run("hazard %s: the scenes are a box, a Timer in the physics step and a mask of layer 2 only; the Broken Glass is the same script with other values" % step, test_hazard_scenes.bind(step))
		await _run("hazard %s: a real player walks into the Live Wire: one hit on entering, one every 0.5 s while inside, four reach 0, stepping out stops them" % step, test_live_wire_hits.bind(step))
		await _run("hazard %s: a body without a Health child is ignored, a body of any kind with one is hurt, the walls and the floor are never reported" % step, test_hazard_looks_only_for_health.bind(step))
	for step in DEATH_STEPS:
		await _run("hazard %s: the Broken Glass takes 10 a hit, ten hits kill, and the cause is Broken Glass" % step, test_broken_glass_hits.bind(step))
	for step in HAZARD_STEPS:
		await _run("contents %s: tutorial 05's check passes with the hazards in (seeds 1-%d, both lock chances): none stands on the way through a room or to its key" % [step, CONTENT_SEEDS], test_contents.bind(step))
	await _run("contents: the check sees a hazard (its footprint is the whole box) and calls one that stands on the way through a room", test_contents_check_sees_the_hazard)
	await _run("how often: rooms with a Live Wire in step 2, with a Live Wire and a Broken Glass in step 3 (seeds 1-%d, goal room %d)" % [PLAN_SEEDS, GOAL_ROOM], test_how_often_hazards_come_up)
	await _run("hazard nodes: the level puts one hazard into a room for every one the plan holds, at its prop spot (seeds 1-%d)" % NODE_SEEDS, test_levels_make_the_planned_hazards)
	await _run("hazards: the point a run starts at and a revive puts the player on (1.5 m inside the entrance) is never inside a hazard (seeds 1-%d, steps 2 to 4)" % PLAN_SEEDS, test_spawn_point_is_clear_of_hazards)

	# Step 3: the death screen. Steps 1 and 2 have no death.
	await _run("death steps 1 and 2: nothing listens to died, there is no DEAD state, and the player walks on at 0 health", test_no_death_before_step_3)
	for step in DEATH_STEPS:
		await _run("death %s: health 0 sets DEAD, freezes the player, stops the clock and keeps the cause; the seed box does not unfreeze; R starts again at full health; the death screen shows only while DEAD" % step, test_death.bind(step))
	await _run("revive step 4: E while dead gives full health at the entrance of the room, keeps keys, rooms and clock, once per run; start refills it", test_revive)
	await _run("revive step 4: a revive is not hit again by the hazard the player died in, not even when E is pressed on the very tick the hazard hits (its list still holds the health until body_exited arrives): the grace of protect() keeps that hit off; with grace 0 the same tick takes the hit", test_revive_is_not_hit_again)

	# Tutorial 10, carried: every door says the room behind it.
	await _run("numbers %s: every door of %d runs says the number of the room behind it (1 to the goal), the goal room has no door, the door into it says the goal" % [FINAL_STEP, NUMBER_SEEDS], test_numbers_of_every_door.bind(FINAL_STEP))
	await _run("numbers %s: walking seeds %s to the goal, the door the player goes through says the number the HUD shows after it, with the rooms behind freed" % [FINAL_STEP, WALKED_SEEDS], test_numbers_walked.bind(FINAL_STEP))

	await _run("movement: the same inputs give the same run in every step, with the camera effects on and off: health and hazards move nothing (seeds %s, 900 ticks)" % [MOVEMENT_SEEDS], test_effects_change_no_movement)
	for step in STEPS:
		await _run("%s: a room stays until the door behind it has closed, nothing goes while it stands open" % step, test_rooms_wait_for_the_door.bind(step))
	await _run("full run: seed 42, goal room 20: the autopilot fetches every key and finishes", test_full_run)
	await _run("restart: R while running leaves the body standing in room 0, in Move, at blend position 0, with full health", test_restart)
	for step in STEPS:
		await _run("%s: main scene runs 30 frames" % step, test_scene_runs.bind(step))
	await _run("sweep: the autopilot walks seeds 1-%d of the finished game to the goal room, never held in place, never dead; every door said the number the HUD showed after it" % SWEEP_SEEDS, test_autopilot_seed_sweep)

	_wipe_save_dir()
	OS.remove_logger(_script_errors)
	await create_timer(0.3).timeout # the audio server lets go of the stopped sounds in its own thread
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if _failed > 0 else 0)

#region Source rules

func test_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var global_random := RegEx.create_from_string("(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize|pick_random)\\(")
	var wall_clock := RegEx.create_from_string("(Time\\.get_|OS\\.get_ticks|OS\\.get_unix|OS\\.delay)")
	var scripts := _files_in("res://steps", ".gd")
	_expect(failures, scripts.size() >= 100, "found only %d scripts under steps" % scripts.size())
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var where := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			_expect(failures, not line.begins_with("class_name"), "%s: class_name" % where)
			_expect(failures, global_random.search(line) == null, "%s: global random call" % where)
			_expect(failures, wall_clock.search(line) == null, "%s: reads the wall clock" % where)
			_expect(failures, not line.contains("Input.is_key_pressed") and not line.contains("Input.is_physical_key_pressed"), "%s: reads a key directly" % where)
			_expect(failures, not line.contains("event is InputEventKey") and not line.contains("event is InputEventJoypad"), "%s: reads a key or button event directly" % where)
	_note("%d scripts under steps/ read" % scripts.size())
	return failures

## Every file of a folder and its sub folders that ends with the suffix.
func _files_in(dir_path: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		found.append_array(_files_in(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			found.append(dir_path.path_join(file))
	return found

func test_copy_forward() -> Array[String]:
	var failures: Array[String] = []
	for i in range(1, STEPS.size()):
		var before := STEPS[i - 1]
		var after := STEPS[i]
		var before_files := _step_files(before)
		var after_files := _step_files(after)
		var changed: Array[String] = []
		var added: Array[String] = []
		for file in before_files:
			if not after_files.has(file):
				failures.append("%s lost %s" % [after, file])
			elif _step_text(before, file) != _step_text(after, file):
				changed.append(file)
		for file in after_files:
			if not before_files.has(file):
				added.append(file)
		changed.sort()
		added.sort()
		var expected: Dictionary = CHANGES[after]
		var expected_changed: Array = expected.changed.duplicate()
		var expected_added: Array = expected.added.duplicate()
		expected_changed.sort()
		expected_added.sort()
		_expect(failures, changed == expected_changed, "%s changes %s, expected %s" % [after, changed, expected_changed])
		_expect(failures, added == expected_added, "%s adds %s, expected %s" % [after, added, expected_added])
		_note("%s changes %s and adds %s" % [after, changed, added])
	return failures

func _step_files(step: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if not file.ends_with(".uid"):
			files.append(file)
	if DirAccess.dir_exists_absolute("res://steps/%s/props" % step):
		for file in DirAccess.get_files_at("res://steps/%s/props" % step):
			if not file.ends_with(".uid"):
				files.append("props/" + file)
	return files

## The file's text with the step folder name blanked out, so copies compare equal.
func _step_text(step: String, file: String) -> String:
	return FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).replace(step, "STEP")

## The editor writes a .uid file beside every script. They are never compared by text between steps (a copy gets its own), but
## every script has one and no two files of the project share one: a shared uid makes the engine warn and pick one.
func test_uid_files() -> Array[String]:
	var failures: Array[String] = []
	var seen := {}
	var scripts := 0
	var tools_without: Array[String] = []
	for path in _files_in("res://steps", ".gd") + _files_in("res://tools", ".gd"):
		var in_steps := path.begins_with("res://steps/")
		if not FileAccess.file_exists(path + ".uid"):
			if in_steps:
				failures.append("%s has no .uid file" % path.trim_prefix("res://"))
			else:
				tools_without.append(path.trim_prefix("res://"))
			continue
		scripts += 1
		var uid := FileAccess.get_file_as_string(path + ".uid").strip_edges()
		_expect(failures, uid.begins_with("uid://") and uid.length() > 8, "%s.uid says \"%s\"" % [path.trim_prefix("res://"), uid])
		if seen.has(uid):
			failures.append("%s and %s share %s" % [path.trim_prefix("res://"), String(seen[uid]).trim_prefix("res://"), uid])
		seen[uid] = path
	_note("%d scripts under steps/ and tools/ have a .uid file, none shares it with another%s" % [scripts, "; without one in tools/ (not a step): %s" % [tools_without] if not tools_without.is_empty() else ""])
	var tutorial := _tutorial_10()
	var original := tutorial.path_join("steps/" + PREVIOUS_FINAL_STEP)
	if tutorial.is_empty() or not DirAccess.dir_exists_absolute(original):
		_skip("uid files: step_00_start has tutorial 10's", "tutorial 10 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER, false)
		return failures
	var same := 0
	for file in DirAccess.get_files_at(original):
		if file.ends_with(".uid"):
			same += 1
			_expect(failures, FileAccess.file_exists("res://steps/step_00_start/" + file) and FileAccess.get_file_as_string(original.path_join(file)) == FileAccess.get_file_as_string("res://steps/step_00_start/" + file), "step_00_start/%s is not tutorial 10's .uid file" % file)
	_expect(failures, same > 20, "found only %d .uid files in the last step of tutorial 10" % same)
	_note("%d .uid files of step_00_start are the ones of tutorial 10's last step" % same)
	return failures

## The project folder of tutorial 10: the folder `--previous=` names, else the one next to this project. Empty if there is none.
func _tutorial_10() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--previous="):
			var given := argument.trim_prefix("--previous=")
			return given if DirAccess.dir_exists_absolute(given) else ""
	var folder := ProjectSettings.globalize_path("res://").path_join("../" + PREVIOUS_FOLDER).simplify_path()
	return folder if DirAccess.dir_exists_absolute(folder) else ""

## Step 0 is the last step of tutorial 10, copied. When that tutorial is not next to this project the test skips.
func test_step_zero_is_tutorial_10() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_10()
	var original := tutorial.path_join("steps/" + PREVIOUS_FINAL_STEP)
	if tutorial.is_empty() or not DirAccess.dir_exists_absolute(original):
		_skip("step_00_start equals the last step of tutorial 10", "tutorial 10 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER)
		return failures
	var original_files: Array[String] = []
	for file in DirAccess.get_files_at(original):
		if not file.ends_with(".uid"):
			original_files.append(file)
	for file in DirAccess.get_files_at(original.path_join("props")):
		if not file.ends_with(".uid"):
			original_files.append("props/" + file)
	_expect(failures, original_files.size() > 40, "found only %d files in the last step of tutorial 10" % original_files.size())
	for file in original_files:
		if not FileAccess.file_exists("res://steps/step_00_start/" + file):
			failures.append("step_00_start has no %s" % file)
			continue
		var theirs := _without_project_names(FileAccess.get_file_as_string(original.path_join(file)))
		var ours := _without_project_names(FileAccess.get_file_as_string("res://steps/step_00_start/" + file))
		_expect(failures, theirs == ours, "%s differs from the last step of tutorial 10" % file)
	_expect(failures, original_files.size() == _step_files("step_00_start").size(), "step_00_start has %d files, the last step of tutorial 10 has %d" % [_step_files("step_00_start").size(), original_files.size()])
	_note("%d files of %s/steps/%s compared with step_00_start (compared at %s)" % [original_files.size(), PREVIOUS_FOLDER, PREVIOUS_FINAL_STEP, tutorial])
	return failures

## The files of tutorial 10 point at one of its step folders, the copies here at the start folder; the usage comments name a
## project folder (test_steps_name_this_project checks that it is this one).
func _without_step_names(text: String) -> String:
	return RegEx.create_from_string("step_\\d\\d_[a-z_]+").sub(text, "STEP", true)

func _without_project_names(text: String) -> String:
	return _without_step_names(text).replace("godot/" + PREVIOUS_FOLDER, "godot/PROJECT").replace("godot/" + THIS_FOLDER, "godot/PROJECT")

## The usage comments of the scripts (`godot --headless --path godot/<project> -s res://steps/<step>/check_echo.gd`) name this
## project: a step copied from tutorial 10 that still says `godot/10-numbered-doors` sends the viewer to a folder
## where the step does not exist.
func test_steps_name_this_project() -> Array[String]:
	var failures: Array[String] = []
	var stale: Array[String] = []
	var named := 0
	for path in _files_in("res://steps", ".gd") + _files_in("res://steps", ".tscn") + _files_in("res://steps", ".tres"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("godot/" + THIS_FOLDER):
			named += 1
		if text.contains(PREVIOUS_FOLDER) or text.contains("phaix-godot-10"):
			stale.append(path.trim_prefix("res://steps/"))
	_expect(failures, stale.is_empty(), "%d files under steps/ name %s, this project is %s: %s" % [stale.size(), PREVIOUS_FOLDER, THIS_FOLDER, stale.slice(0, 5)])
	_expect(failures, named >= 20, "only %d files under steps/ name godot/%s in a usage comment" % [named, THIS_FOLDER])
	_note("%d files under steps/ name godot/%s in a usage comment, %d name %s" % [named, THIS_FOLDER, stale.size(), PREVIOUS_FOLDER])
	return failures

## Everything that is not a step is tutorial 10's too: the buses, the figure, the sounds, the materials, and project.godot with
## exactly five differences: its name, its main scene, its user dir, the revive action (E), and ui_accept with the A button next to its
## three default keys (the settings box turns an effect on or off with Enter or A; Godot's default ui_accept has keys only).
func test_root_is_tutorial_10() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_10()
	if tutorial.is_empty():
		_skip("the root of the project equals the root of tutorial 10", "tutorial 10 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER)
		return failures
	var skipped_lines := ["config/name=", "run/main_scene=", "config/custom_user_dir_name="]
	var theirs_text := FileAccess.get_file_as_string(tutorial.path_join("project.godot"))
	var ours_text := FileAccess.get_file_as_string("res://project.godot")
	for prefix: String in skipped_lines:
		_expect(failures, _count_lines(theirs_text, prefix) == 1 and _count_lines(ours_text, prefix) == 1, "%s is not in both project files exactly once" % prefix)
	_expect(failures, ours_text.count("\nrevive={") == 1 and not theirs_text.contains("revive={"), "project.godot has the revive action %d times, tutorial 10's has it %d times" % [ours_text.count("\nrevive={"), theirs_text.count("revive={")])
	var theirs := _without_lines(theirs_text, skipped_lines)
	_expect(failures, ours_text.count("\nui_accept={") == 1 and not theirs_text.contains("ui_accept={"), "project.godot has ui_accept %d times, tutorial 10's has it %d times" % [ours_text.count("\nui_accept={"), theirs_text.count("ui_accept={")])
	var accept := ours_text.substr(ours_text.find("\nui_accept={"), ours_text.find("\n}", ours_text.find("\nui_accept={")) - ours_text.find("\nui_accept={"))
	_expect(failures, accept.contains("\"keycode\":4194309,") and accept.contains("\"keycode\":4194310,") and accept.contains("\"keycode\":32,") and accept.contains("InputEventJoypadButton") and accept.contains("\"button_index\":0,"), "ui_accept is not Enter, KP Enter, Space and the A button")
	var ours := _without_lines(_without_action(_without_action(ours_text, "revive"), "ui_accept"), skipped_lines)
	_expect(failures, theirs.length() > 1000 and theirs == ours, "project.godot differs from tutorial 10's besides its name, its main scene, its user dir, the revive action and ui_accept")
	_expect(failures, ours_text.contains("config/name=\"Phaix Godot 11 - Health and Death\"") and ours_text.contains("run/main_scene=\"res://steps/%s/main.tscn\"" % FINAL_STEP) and ours_text.contains("config/custom_user_dir_name=\"phaix-godot-11\""), "the name, the main scene or the user dir of project.godot is not this tutorial's")
	var compared := 1
	for file: String in ["default_bus_layout.tres"]:
		_expect(failures, FileAccess.file_exists(tutorial.path_join(file)) and FileAccess.get_sha256(tutorial.path_join(file)) == FileAccess.get_sha256("res://" + file), "%s differs from tutorial 10's" % file)
		compared += 1
	for folder: String in ["character", "sounds", "materials"]:
		var theirs_files := _files_below(tutorial.path_join(folder), folder)
		var ours_files := _files_below(ProjectSettings.globalize_path("res://" + folder), folder)
		_expect(failures, theirs_files.size() > 5 and theirs_files == ours_files, "%s/ holds %d files, tutorial 10's holds %d (or other names)" % [folder, ours_files.size(), theirs_files.size()])
		for file in theirs_files:
			if FileAccess.file_exists("res://" + file):
				_expect(failures, FileAccess.get_sha256(tutorial.path_join(file)) == FileAccess.get_sha256("res://" + file), "%s differs from tutorial 10's" % file)
				compared += 1
	_note("project.godot (name, main scene, user dir, revive and ui_accept are the five differences), the bus layout and %d more files compared byte for byte" % (compared - 2))
	return failures

func _count_lines(text: String, prefix: String) -> int:
	var count := 0
	for line in text.split("\n"):
		if line.begins_with(prefix):
			count += 1
	return count

func _without_lines(text: String, prefixes: Array) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var skip := false
		for prefix: String in prefixes:
			skip = skip or line.begins_with(prefix)
		if not skip:
			kept.append(line)
	return "\n".join(kept)

## A project.godot without one action: from the line "<action>={" to the closing brace.
func _without_action(text: String, action: String) -> String:
	var start := text.find("\n%s={" % action)
	if start < 0:
		return text
	var end := text.find("\n}", start)
	return text.substr(0, start) + text.substr(end + 2)

## The files below a folder as "folder/sub/file" paths, sorted; .import and .uid files (the editor writes them) do not count.
func _files_below(absolute: String, relative: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(absolute)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_files_below(absolute.path_join(sub), relative.path_join(sub)))
	for file in dir.get_files():
		if not file.ends_with(".import") and not file.ends_with(".uid"):
			found.append(relative.path_join(file))
	found.sort()
	return found

func test_project_settings() -> Array[String]:
	var failures: Array[String] = []
	for action in ACTIONS:
		_expect(failures, ProjectSettings.has_setting("input/" + action), "no %s action" % action)
	_expect(failures, ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "the physics engine is not Jolt")
	_expect(failures, _physical_keys("toggle_gizmos") == ["F3"], "toggle_gizmos is %s, expected F3" % [_physical_keys("toggle_gizmos")])
	_expect(failures, _physical_keys("toggle_watch") == ["F4"], "toggle_watch is %s, expected F4" % [_physical_keys("toggle_watch")])
	_expect(failures, _physical_keys("open_settings") == ["O"], "open_settings has the keys %s, expected O" % [_physical_keys("open_settings")])
	_expect(failures, _physical_keys("revive") == ["E"], "revive has the keys %s, expected E" % [_physical_keys("revive")])
	_expect(failures, InputMap.action_get_events("revive").size() == 1, "revive has %d events, expected the one key" % InputMap.action_get_events("revive").size())
	_expect(failures, ProjectSettings.get_setting("layer_names/3d_render/layer_3") == "Body", "render layer 3 is not named Body")
	_expect(failures, ProjectSettings.get_setting("layer_names/3d_physics/layer_1") == "world" and ProjectSettings.get_setting("layer_names/3d_physics/layer_2") == "player", "physics layers 1 and 2 are not named world and player: the hazards' mask of layer 2 is the player's layer")
	_expect(failures, ProjectSettings.get_setting("application/run/main_scene") == "res://steps/%s/main.tscn" % FINAL_STEP, "the main scene is not the final step")
	_expect(failures, ProjectSettings.get_setting("application/config/name") == "Phaix Godot 11 - Health and Death", "the project is named '%s'" % ProjectSettings.get_setting("application/config/name"))
	_expect(failures, ProjectSettings.get_setting("application/config/custom_user_dir_name") == "phaix-godot-11", "the user dir is '%s'" % ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	return failures

## The text on the screen: every step says what step 0 says; step 1 adds the health line, step 3 the death screen. The
## Input Map is tutorial 10's, with the revive action added.
func test_hud_and_input_map() -> Array[String]:
	var failures: Array[String] = []
	var reference := _hud_texts(STEPS[0])
	var hint := reference.get("Stats/DebugHint", "") as String
	_expect(failures, hint == "F3  gizmos      F4  watch it plan", "step 0 says '%s' as its debug hint" % hint)
	_expect(failures, reference.get("Stats/SettingsHint") == "O  settings", "step 0 says '%s' as its settings hint" % reference.get("Stats/SettingsHint"))
	_expect(failures, reference.size() >= 10, "found only %d labels in the HUD of step 0" % reference.size())
	for step in STEPS:
		var texts := _hud_texts(step)
		for label_path: String in reference:
			_expect(failures, texts.get(label_path) == reference[label_path], "%s: %s says '%s' in the HUD scene, step 0 says '%s'" % [step, label_path, texts.get(label_path), reference[label_path]])
		var extra := {}
		for label_path: String in texts:
			if not reference.has(label_path):
				extra[label_path] = texts[label_path]
		_expect(failures, extra == HUD_EXTRA[step], "%s: the HUD scene has the extra labels %s, expected %s" % [step, extra, HUD_EXTRA[step]])
		var main := await _load_step(step, false)
		await _wait_physics(5)
		var label := main.get_node_or_null("HUD/Stats/DebugHint") as Label
		_expect(failures, label != null and label.text == hint, "%s: the hint on the screen says '%s', step 0 says '%s'" % [step, label.text if label != null else "no label", hint])
		var health_label := main.get_node_or_null("HUD/Stats/HealthLabel") as Label
		_expect(failures, (health_label == null) == (step == STEPS[0]) and (health_label == null or health_label.text == "Health 100"), "%s: the health line on the screen says '%s'" % [step, health_label.text if health_label != null else "(none)"])
		await _unload(main)
	_note("%d labels in the HUD of every step; step 1 adds %s, step 3 adds the death screen (%s)" % [reference.size(), HUD_EXTRA[STEPS[1]], HUD_EXTRA[DEATH_STEP].keys().slice(1)])
	var tutorial := _tutorial_10()
	if tutorial.is_empty():
		_skip("hud: the Input Map is the one of tutorial 10", "tutorial 10 is not next to this project (no ../%s, and no --previous=<its project folder>)" % PREVIOUS_FOLDER, false)
		return failures
	var theirs := _input_section(tutorial.path_join("project.godot"))
	var ours := _without_action(_without_action(_input_section(ProjectSettings.globalize_path("res://project.godot")), "revive"), "ui_accept")
	_expect(failures, theirs.length() > 1000, "found no [input] section in the project.godot of tutorial 10")
	_expect(failures, theirs == ours, "the [input] section of project.godot is not the one of tutorial 10 plus revive and ui_accept")
	return failures

## The text of every label of a step's HUD scene, by its path below the HUD.
func _hud_texts(step: String) -> Dictionary:
	var texts := {}
	var main := (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	var hud := main.get_node("HUD")
	for label: Node in hud.find_children("*", "Label", true, false):
		texts[str(hud.get_path_to(label))] = (label as Label).text
	main.free()
	return texts

## Everything from the line "[input]" to the end of a project.godot.
func _input_section(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("\n[input]")
	return text.substr(start) if start >= 0 else ""

## The README is the public text of the episode: its credits name the folders that stand in the project (the figure, the
## sounds, with the files that carry the licences), every step folder is named, and every project path it names in backticks exists.
## In the public repo the README is the short one for viewers ("Project files for tutorial NN ...": the steps, the tests command,
## the credits of the licences), so it is checked for what it says; the project's own long README has the full list.
func test_readme_matches_folders() -> Array[String]:
	var failures: Array[String] = []
	var readme := FileAccess.get_file_as_string("res://README.md")
	var viewers := readme.contains("Project files for tutorial")
	_expect(failures, readme.length() > (1000 if viewers else 2000), "README.md is missing or has only %d characters" % readme.length())
	var musts: Array[String] = ["Animated Characters Protagonists", "character/License.txt", "RPG Audio", "sounds/CREDITS.md", "Kenney", "CC0", "run_tests.gd"]
	if not viewers:
		musts.append_array(["`character/`", "`sounds/`", "--only=", "Health 100", "revive", "Live Wire", "Broken Glass", "check_contents.gd"])
	for must: String in musts:
		_expect(failures, readme.contains(must), "README.md does not say \"%s\"" % must)
	if not viewers:
		for step in STEPS:
			_expect(failures, readme.contains("`%s`" % step), "README.md does not name the step folder `%s`" % step)
	for forbidden: String in ["Blender", "kit_", "capture.gd", "capture.tscn", "check_coverage", "make_materials", "tools/variants"]:
		_expect(failures, not readme.contains(forbidden), "README.md still says \"%s\"" % forbidden)
	_expect(failures, FileAccess.get_file_as_string("res://character/License.txt").contains("CC0") and FileAccess.get_file_as_string("res://sounds/CREDITS.md").contains("CC0"), "character/License.txt or sounds/CREDITS.md does not say CC0")
	var named := RegEx.create_from_string("`((?:tools|tests|steps|materials|sounds|character)/[A-Za-z0-9_./-]*)`")
	var checked := 0
	var seen: Array[String] = []
	for found in named.search_all(readme):
		var path := found.get_string(1)
		if seen.has(path) or path.contains("NN_") or path.contains("<"):
			continue
		seen.append(path)
		checked += 1
		_expect(failures, FileAccess.file_exists("res://" + path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + path)), "README.md names `%s`, which does not exist" % path)
	_expect(failures, checked >= (4 if viewers else 12), "README.md names only %d project paths" % checked)
	_note("%d paths named in the README exist" % checked)
	return failures

#endregion

#region Chains (pure data, no scene)

## A chain of any step's script.
func _new_chain(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.0) -> RefCounted:
	return chain_script.new(chain_seed, goal_room, chance)

## The room_chain.gd of a step.
func _chain_script(step: String) -> GDScript:
	return load("res://steps/%s/room_chain.gd" % step) as GDScript

## What the chain's Type enum calls the goal room.
func _goal_type(chain_script: GDScript) -> int:
	return (chain_script.get_script_constant_map()["Type"] as Dictionary)["GOAL"]

func _same_plans(a: Array, b: Array, with_props := true) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same_plan(a[i], b[i], with_props):
			return false
	return true

## One plan against another: the room, its lock and its lamp, and with_props also its props.
func _same_plan(a: Object, b: Object, with_props := true) -> bool:
	if a.index != b.index or a.type != b.type or a.transform != b.transform or a.bounds != b.bounds:
		return false
	if with_props and a.props != b.props:
		return false
	return a.locked == b.locked and a.key_spot == b.key_spot and a.props.size() == b.props.size() and a.lamp == b.lamp

## All plans of a chain up to and including its goal room (at most `limit` plans).
func _plans_to_goal(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.4, limit := 400) -> RefCounted:
	var chain := _new_chain(chain_script, chain_seed, goal_room, chance)
	while chain.plans.size() < limit:
		var plan: Object = chain.next_plan()
		if plan.type == _goal_type(chain_script):
			break
	return chain

## The plans of the run of a seed in a step, to the goal room (lock chance 0.4, the level's default). Made once, then kept.
func _run_plans(step: String, chain_seed: int) -> Array:
	var key := "%s:%d" % [step, chain_seed]
	if not _plans_cache.has(key):
		_plans_cache[key] = _plans_to_goal(_chain_script(step), chain_seed, GOAL_ROOM).plans
	return _plans_cache[key]

## The prop sets of a step, in the order of the room types.
func _prop_sets(step: String) -> Array:
	return _chain_script(step).get_script_constant_map()["PROP_SETS"]

## The hazards a room's plan puts down: x Live Wires, y Broken Glass.
func _hazards_in(plan: Object, prop_sets: Array) -> Vector2i:
	var wires := 0
	var glass := 0
	for prop: int in plan.props:
		if prop == Chain.NO_PROP:
			continue
		var file := ((prop_sets[plan.type].scenes[prop]) as PackedScene).resource_path.get_file()
		wires += 1 if file == "live_wire.tscn" else 0
		glass += 1 if file == "broken_glass.tscn" else 0
	return Vector2i(wires, glass)

## Every step plans the rooms, locks, keys and lamps of step 0 for every seed: health, a hazard and a death never touch the
## generator. The props are the one thing that moves, from step 2: a hazard is a prop with a weight in a prop set.
func test_steps_plan_the_same() -> Array[String]:
	var failures: Array[String] = []
	var rooms := 0
	var differ: Dictionary[String, int] = {}
	for step in STEPS:
		differ[step] = 0
	for chain_seed in range(1, PLAN_SEEDS + 1):
		if chain_seed % 20 == 0:
			await process_frame
		var base: Array = _run_plans(STEPS[0], chain_seed)
		rooms += base.size()
		for i in range(1, STEPS.size()):
			var other: Array = _run_plans(STEPS[i], chain_seed)
			_expect(failures, _same_plans(base, other, false), "seed %d: %s plans other rooms, locks, keys or lamps than %s" % [chain_seed, STEPS[i], STEPS[0]])
			for plan_index in mini(base.size(), other.size()):
				if base[plan_index].props != other[plan_index].props:
					differ[STEPS[i]] += 1
			if i == 1:
				_expect(failures, _same_plans(base, other), "seed %d: %s plans other props than %s: a health node moves no prop" % [chain_seed, STEPS[i], STEPS[0]])
		_expect(failures, _same_plans(_run_plans(STEPS[3], chain_seed), _run_plans(STEPS[4], chain_seed)), "seed %d: step 4 plans another run than step 3, props included: a revive changes no plan" % chain_seed)
		if failures.size() > 8:
			return failures
	_expect(failures, differ[STEPS[1]] == 0, "step 1 changes the props of %d plans" % differ[STEPS[1]])
	for step in HAZARD_STEPS:
		_expect(failures, differ[step] > 0, "%s puts a hazard into no prop set that comes up: its props are the props of step 0" % step)
	_note("%d seeds, %d plans each step: the types, places, locks, keys and lamp tints of all %d steps are step 0's" % [PLAN_SEEDS, rooms, STEPS.size()])
	_note("plans that differ from step 0 in their props: step 1 %d, step 2 %d, step 3 %d, step 4 %d of %d (step 4 plans exactly step 3's props)" % [differ[STEPS[1]], differ[STEPS[2]], differ[STEPS[3]], differ[STEPS[4]], rooms])
	return failures

#endregion

#region Walking the real player

## Runs tick once per physics tick until it returns true. (With Engine.time_scale above 1
## several ticks happen per frame, and `await physics_frame` would only see one of them.)
func _drive(tick: Callable) -> void:
	var driver := Driver.new()
	driver.process_priority = -100
	driver.tick = tick
	root.add_child(driver)
	await driver.finished
	root.remove_child(driver)
	driver.queue_free()

## This many physics ticks, at any speed.
func _ticks(count: int) -> void:
	var state := {"left": count}
	await _drive(func() -> bool:
		state["left"] -= 1
		return state["left"] <= 0)

## Physics ticks until the condition holds (checked before the player's own tick), at most `budget`. Returns whether it held.
func _until(condition: Callable, budget: int) -> bool:
	var state := {"left": budget, "met": false}
	await _drive(func() -> bool:
		state["met"] = condition.call()
		state["left"] -= 1
		return state["met"] or state["left"] <= 0)
	return state["met"]

## Walks until the player is in room `goal`. dawdle: ticks of standing still at the start and at every new door.
func _walk(level: Node3D, pilot: RefCounted, goal: int, dawdle: int, on_tick: Callable) -> bool:
	var state := {"budget": 1500 * goal, "wait": dawdle, "target": pilot.door_index}
	await _drive(func() -> bool:
		if state["wait"] > 0:
			state["wait"] -= 1
		else:
			pilot.physics_step()
			if pilot.door_index != state["target"]:
				state["target"] = pilot.door_index
				state["wait"] = dawdle
				pilot.release()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.current >= goal or level.state == STATE_DEAD or state["budget"] <= 0)
	pilot.release()
	return level.current >= goal

## Walks until the run is finished (the player stands on the goal pad), the player is dead or the budget of ticks is gone.
func _walk_to_finish(level: Node3D, pilot: RefCounted, budget: int, on_tick: Callable) -> bool:
	var state := {"budget": budget}
	await _drive(func() -> bool:
		pilot.physics_step()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.state == STATE_FINISHED or level.state == STATE_DEAD or state["budget"] <= 0)
	pilot.release()
	return level.state == STATE_FINISHED

#endregion

#region Health: a node of its own (step 1)

## The health node alone, as a viewer builds it: a Node with the script. The signals are written down in the order they come.
func test_health_node(step: String) -> Array[String]:
	var failures: Array[String] = []
	var health := (load("res://steps/%s/health.gd" % step) as GDScript).new() as Node
	var events: Array[String] = []
	health.connect("changed", func(value: int) -> void: events.append("changed %d" % value))
	health.connect("died", func(cause: String) -> void: events.append("died %s" % cause))
	_expect(failures, health.max_health == 100, "max_health is %d, expected 100" % health.max_health)
	var exported := false
	for property: Dictionary in health.get_property_list():
		exported = exported or (property["name"] == "max_health" and (int(property["usage"]) & PROPERTY_USAGE_EDITOR) != 0)
	_expect(failures, exported, "max_health is not an export: the inspector cannot change it")
	root.add_child(health) # _ready: the node starts full
	_expect(failures, health.health == 100 and not health.dead and events == ["changed 100"], "after _ready: health %d, dead %s, events %s; expected full health and one changed(100)" % [health.health, health.dead, events])
	events.clear()
	health.hurt(30, "Spike")
	_expect(failures, health.health == 70 and not health.dead and events == ["changed 70"], "hurt(30): health %d, dead %s, events %s" % [health.health, health.dead, events])
	events.clear()
	health.hurt(0, "Nothing")
	health.hurt(-25, "Healing")
	_expect(failures, health.health == 70 and events.is_empty(), "a hit of 0 or less changed something: health %d, events %s" % [health.health, events])
	health.hurt(20, "Spike")
	health.hurt(20, "Spike")
	_expect(failures, health.health == 30 and events == ["changed 50", "changed 30"], "two hits of 20: health %d, events %s; changed must come after every hit" % [health.health, events])
	events.clear()
	health.hurt(500, "Crush")
	_expect(failures, health.health == 0 and health.dead and events == ["changed 0", "died Crush"], "hurt(500): health %d, dead %s, events %s; expected 0 (never below), changed(0), then died(Crush)" % [health.health, health.dead, events])
	events.clear()
	health.hurt(10, "After")
	health.hurt(1, "After")
	_expect(failures, health.health == 0 and events.is_empty(), "a dead body took another hit: health %d, events %s" % [health.health, events])
	health.reset()
	_expect(failures, health.health == 100 and not health.dead and events == ["changed 100"], "reset(): health %d, dead %s, events %s; expected full, alive, one changed(100)" % [health.health, health.dead, events])
	events.clear()
	health.hurt(60, "First")
	health.hurt(60, "Last")
	health.hurt(60, "Never")
	var died := events.filter(func(event: String) -> bool: return event.begins_with("died"))
	_expect(failures, events == ["changed 40", "changed 0", "died Last"] and died.size() == 1, "two hits of 60 and one more: events %s; expected died exactly once, with the cause of the hit that reached 0" % [events])
	events.clear()
	health.reset()
	events.clear()
	health.hurt(100, "Exactly")
	_expect(failures, health.health == 0 and health.dead and events == ["changed 0", "died Exactly"], "a hit of exactly the health: health %d, events %s" % [health.health, events])
	health.max_health = 50
	health.reset()
	_expect(failures, health.health == 50, "reset() with max_health 50 gave %d" % health.health)
	events.clear()
	for hit in 5:
		health.hurt(10, "Tick")
	_expect(failures, events == ["changed 40", "changed 30", "changed 20", "changed 10", "changed 0", "died Tick"], "five hits of 10 from 50: events %s" % [events])
	_note("max_health 100 (an export); hurt(30) 100 -> 70; hurt(0) and hurt(-25) do nothing; hurt(500) -> 0 with changed(0) then died once; a dead node takes no hit; reset() -> 100; two hits of 60 -> died once with the cause of the second")
	root.remove_child(health)
	health.free()
	return failures

## The node in the player scene, the level that keeps it, the HUD that shows it, and start() that fills it.
func test_health_in_the_scene(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var healths := player.get_children().filter(func(child: Node) -> bool: return child.name == &"Health")
	_expect(failures, healths.size() == 1, "the player has %d children named Health, expected one" % healths.size())
	var health: Node = player.get_node_or_null("Health")
	_expect(failures, health != null and (health.get_script() as Script).resource_path == "res://steps/%s/health.gd" % step and health.get_class() == "Node", "the Health child is %s" % [health])
	_expect(failures, level.health == health, "the level keeps another health than the player's")
	_expect(failures, player.collision_layer == 2, "the player is on layer %d: the hazards look for layer 2" % player.collision_layer)
	var label := main.get_node("HUD/Stats/HealthLabel") as Label
	_expect(failures, label.text == "Health 100" and health.health == 100, "the HUD says '%s' for %d health at the start" % [label.text, health.health])
	health.hurt(25, "Test")
	_expect(failures, label.text == "Health 75", "after a hit of 25 the HUD says '%s'" % label.text)
	health.hurt(15, "Test")
	_expect(failures, label.text == "Health 60", "after a hit of 15 more the HUD says '%s'" % label.text)
	await _action("regenerate")
	_expect(failures, health.health == 100 and not health.dead and label.text == "Health 100", "R left %d health, dead %s, the HUD says '%s'" % [health.health, health.dead, label.text])
	var died_listeners := health.get_signal_connection_list("died").size()
	_expect(failures, died_listeners == (1 if DEATH_STEPS.has(step) else 0), "%d listeners on died, expected %d (the level listens from step 3 on)" % [died_listeners, 1 if DEATH_STEPS.has(step) else 0])
	_note("one Node child named Health on the player (layer %d), kept by the level, shown by the HUD (Health 100, 75, 60), refilled by R; %d listener(s) on died" % [player.collision_layer, died_listeners])
	await _unload(main)
	return failures

## The lines step 4 adds to health.gd for the grace after a revive, and the one line of hurt it changes.
const GRACE_LINES: Array[String] = ["@export var grace := 1.0", "var safe_left := 0.0", "func _physics_process(delta: float) -> void:",
	"safe_left = maxf(safe_left - delta, 0.0)", "func protect() -> void:", "safe_left = grace"]
const HURT_CHECK_BEFORE := "if dead or amount <= 0:"
const HURT_CHECK_GRACE := "if dead or amount <= 0 or safe_left > 0.0:"

func test_health_code_is_the_same() -> Array[String]:
	var failures: Array[String] = []
	var base := _code_lines("res://steps/%s/health.gd" % HEALTH_STEPS[0])
	for step in HEALTH_STEPS:
		if step == FINAL_STEP:
			continue
		_expect(failures, _code_lines("res://steps/%s/health.gd" % step) == base, "%s/health.gd has other code than step 1's (comments aside)" % step)
	var last := _code_lines("res://steps/%s/health.gd" % FINAL_STEP)
	var added: Array[String] = []
	for line in last:
		if not base.has(line) and line != HURT_CHECK_GRACE:
			added.append(line)
	var removed: Array[String] = []
	for line in base:
		if not last.has(line) and line != HURT_CHECK_BEFORE:
			removed.append(line)
	_expect(failures, added == GRACE_LINES and removed.is_empty() and last.has(HURT_CHECK_GRACE) and not last.has(HURT_CHECK_BEFORE), "step 4's health.gd against step 1's: added %s (expected %s), removed %s, the check in hurt %s" % [added, GRACE_LINES, removed, "with the grace" if last.has(HURT_CHECK_GRACE) else "without the grace"])
	_note("%d lines of code in health.gd, the same in steps 1 to 3; step 4 adds the %d lines of the grace and the grace check in hurt" % [base.size(), GRACE_LINES.size()])
	return failures

## The grace on its own, as step 4's health.gd has it: a Health in the tree (it counts down in its own _physics_process), protect(),
## then one hurt(1) a tick until one counts. The ticks are physics ticks at 60 a second: one second is 60 of them.
func test_health_grace() -> Array[String]:
	var failures: Array[String] = []
	var health := (load("res://steps/%s/health.gd" % FINAL_STEP) as GDScript).new() as Node
	root.add_child(health)
	await _ticks(1)
	_expect(failures, is_equal_approx(health.grace, 1.0) and health.safe_left == 0.0, "grace %.2f s, safe_left %.2f at the start; expected 1.0 and 0" % [health.grace, health.safe_left])
	health.hurt(10, "Test")
	_expect(failures, health.health == 90, "without protect() a hit counts at once: health %d, expected 90" % health.health)
	health.protect()
	health.hurt(50, "Test")
	_expect(failures, health.health == 90, "a hit right after protect() counted: health %d, expected 90" % health.health)
	var counted_at := -1
	for tick in 3 * Engine.physics_ticks_per_second:
		await _ticks(1)
		health.hurt(1, "Test")
		if health.health < 90:
			counted_at = tick + 1
			break
	var hz := Engine.physics_ticks_per_second
	_expect(failures, counted_at >= hz and counted_at <= hz + 1, "the first hit after protect() counted on tick %d, expected tick %d or %d (one second)" % [counted_at, hz, hz + 1])
	_expect(failures, health.health == 89 and not health.dead, "after the grace one hit of 1 counted: health %d, expected 89" % health.health)
	health.protect()
	health.hurt(1000, "Test")
	_expect(failures, health.health == 89 and not health.dead, "a deadly hit inside the grace counted: health %d, dead %s" % [health.health, health.dead])
	_note("protect(): hits on ticks 1 to %d did not count, the hit on tick %d (%.3f s) did; a deadly hit inside the grace does nothing" % [counted_at - 1, counted_at, float(counted_at) / hz])
	root.remove_child(health)
	health.free()
	return failures

func _code_lines(path: String) -> Array[String]:
	var lines: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := line.split("##")[0].strip_edges()
		if not code.is_empty() and not code.begins_with("#"):
			lines.append(code)
	return lines

#endregion

#region Hazards (steps 2 and 3)

func _prop_scene_file(step: String, set_name: String) -> Array[String]:
	var set_data := load("res://steps/%s/props/%s_set.tres" % [step, set_name]) as Resource
	var files: Array[String] = []
	for scene: PackedScene in set_data.scenes:
		files.append(scene.resource_path.get_file())
	return files

## The narration's weights: the Live Wire gets 2 in the straight room and 1.5 in the long and the wide room; the Broken Glass
## 1.5 in both turning rooms and the wide room.
func test_hazards_in_the_prop_sets() -> Array[String]:
	var failures: Array[String] = []
	var live_wire := {"straight": 2.0, "long": 1.5, "wide": 1.5}
	var glass := {"turn_left": 1.5, "turn_right": 1.5, "wide": 1.5}
	var sets := ["straight", "long", "turn_left", "turn_right", "wide", "vault"]
	for step in STEPS:
		var expect_wire := HAZARD_STEPS.has(step)
		var expect_glass := DEATH_STEPS.has(step)
		for set_name: String in sets:
			var set_data := load("res://steps/%s/props/%s_set.tres" % [step, set_name]) as Resource
			var files := _prop_scene_file(step, set_name)
			var weights: Array = set_data.weights
			_expect(failures, files.size() == weights.size(), "%s %s_set: %d scenes, %d weights" % [step, set_name, files.size(), weights.size()])
			var wire_at := files.find("live_wire.tscn")
			var glass_at := files.find("broken_glass.tscn")
			_expect(failures, (wire_at >= 0) == (expect_wire and live_wire.has(set_name)), "%s %s_set: the Live Wire is %s" % [step, set_name, "in it" if wire_at >= 0 else "not in it"])
			_expect(failures, (glass_at >= 0) == (expect_glass and glass.has(set_name)), "%s %s_set: the Broken Glass is %s" % [step, set_name, "in it" if glass_at >= 0 else "not in it"])
			if wire_at >= 0 and live_wire.has(set_name):
				_expect(failures, is_equal_approx(weights[wire_at], live_wire[set_name]), "%s %s_set: the Live Wire weighs %s, the narration says %s" % [step, set_name, weights[wire_at], live_wire[set_name]])
			if glass_at >= 0 and glass.has(set_name):
				_expect(failures, is_equal_approx(weights[glass_at], glass[set_name]), "%s %s_set: the Broken Glass weighs %s, the narration says %s" % [step, set_name, weights[glass_at], glass[set_name]])
	_note("Live Wire (steps 2 to 4): straight 2, long 1.5, wide 1.5; Broken Glass (steps 3 and 4): turn_left 1.5, turn_right 1.5, wide 1.5; the vault holds neither; steps 0 and 1 hold none")
	return failures

## The scenes of the hazards: an Area3D with the step's hazard script, a box and a Timer, a mask of layer 2 and nothing else.
func test_hazard_scenes(step: String) -> Array[String]:
	var failures: Array[String] = []
	var specs := {"live_wire": {cause = "Live Wire", damage = 25}, "broken_glass": {cause = "Broken Glass", damage = 10}}
	for hazard_name: String in specs:
		if not FileAccess.file_exists("res://steps/%s/props/%s.tscn" % [step, hazard_name]):
			_expect(failures, step == HAZARD_STEP and hazard_name == "broken_glass", "%s has no props/%s.tscn" % [step, hazard_name])
			continue
		var wire := (load("res://steps/%s/props/%s.tscn" % [step, hazard_name]) as PackedScene).instantiate() as Area3D
		var spec: Dictionary = specs[hazard_name]
		_expect(failures, (wire.get_script() as Script).resource_path == "res://steps/%s/hazard.gd" % step, "%s: the hazard's script is %s: a new hazard needs no new code" % [hazard_name, (wire.get_script() as Script).resource_path])
		_expect(failures, wire.cause == spec.cause and wire.damage == spec.damage and is_equal_approx(wire.interval, 0.5), "%s: cause '%s', damage %d, interval %s; expected '%s', %d, 0.5" % [hazard_name, wire.cause, wire.damage, wire.interval, spec.cause, spec.damage])
		_expect(failures, wire.collision_layer == 0 and wire.collision_mask == 2 and wire.get_collision_mask_value(2) and not wire.get_collision_mask_value(1), "%s: layer %d, mask %d; expected layer 0 and a mask of layer 2 only" % [hazard_name, wire.collision_layer, wire.collision_mask])
		var shapes := wire.find_children("*", "CollisionShape3D", false, false)
		var timers := wire.find_children("*", "Timer", false, false)
		_expect(failures, shapes.size() == 1 and (shapes[0] as CollisionShape3D).shape is BoxShape3D, "%s: %d collision shapes, expected one box" % [hazard_name, shapes.size()])
		_expect(failures, timers.size() == 1 and timers[0].name == &"Timer", "%s: %d timers, expected one named Timer" % [hazard_name, timers.size()])
		var meshes := wire.find_children("*", "MeshInstance3D", false, false)
		_expect(failures, wire.get_child_count() == 2 + meshes.size() and meshes.size() >= 3, "%s: %d children, %d of them meshes: expected the box, the Timer and the pictures on top" % [hazard_name, wire.get_child_count(), meshes.size()])
		var timer := timers[0] as Timer
		_expect(failures, timer.process_callback == Timer.TIMER_PROCESS_PHYSICS, "%s: the Timer runs in %d (physics is %d)" % [hazard_name, timer.process_callback, Timer.TIMER_PROCESS_PHYSICS])
		_expect(failures, not timer.one_shot and not timer.autostart, "%s: the Timer is one shot %s or starts alone %s" % [hazard_name, timer.one_shot, timer.autostart])
		wire.interval = 0.2
		root.add_child(wire) # _ready copies the interval into the Timer's wait time
		await process_frame
		_expect(failures, is_equal_approx(timer.wait_time, 0.2) and timer.is_stopped() and wire.inside.is_empty(), "%s: wait time %s for an interval of 0.2, stopped %s, %d inside" % [hazard_name, timer.wait_time, timer.is_stopped(), wire.inside.size()])
		var box := (shapes[0] as CollisionShape3D)
		if hazard_name == "live_wire":
			_note("%s: Area3D with %s, layer %d, mask %d (layer 2 only), one BoxShape3D %s at %s, a Timer in the physics step (its wait time comes from the interval), %d pictures on top; Broken Glass is the same script with its own cause and 10" % [step, (wire.get_script() as Script).resource_path.get_file(), wire.collision_layer, wire.collision_mask, (box.shape as BoxShape3D).size, box.position, meshes.size()])
		root.remove_child(wire)
		wire.free()
	return failures

## A floor, the real player of the step on it and a hazard scene of the step 1.5 m ahead of the player, who looks along -z.
## The floor is layer 1 (the world), the player layer 2.
func _arena(step: String, hazard_scene: String, with_player := true) -> Dictionary:
	var arena := Node3D.new()
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	arena.add_child(floor_body)
	var wire := (load("res://steps/%s/props/%s.tscn" % [step, hazard_scene]) as PackedScene).instantiate() as Area3D
	wire.position = WIRE_AT
	arena.add_child(wire)
	var player: CharacterBody3D = null
	if with_player:
		player = (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate() as CharacterBody3D
		player.position = WIRE_START
		arena.add_child(player)
	root.add_child(arena)
	return {arena = arena, wire = wire, player = player}

## Writes down every change of a health: the physics frame, the health after it and where the body was; and every death.
func _record(health: Node) -> Dictionary:
	var rec := {hits = [] as Array[Vector2i], zs = [] as Array[float], died = [] as Array[String]}
	var body := health.get_parent() as Node3D
	health.connect("changed", func(value: int) -> void:
		(rec["hits"] as Array[Vector2i]).append(Vector2i(Engine.get_physics_frames(), value))
		(rec["zs"] as Array[float]).append(body.global_position.z))
	health.connect("died", func(cause: String) -> void: (rec["died"] as Array[String]).append(cause))
	return rec

## The real player walks 1.5 m into a hazard, stands in the middle of it until it is dead and then 2 s longer.
func _walk_in_and_stay(step: String, hazard_scene: String) -> Dictionary:
	_fast_forward(true)
	var arena := _arena(step, hazard_scene)
	var player: CharacterBody3D = arena.player
	var health: Node = player.get_node("Health")
	var rec := _record(health)
	await _ticks(10)
	var quiet: bool = (rec.hits as Array).is_empty() and health.health == 100
	Input.action_press("move_forward")
	await _until(func() -> bool: return player.global_position.z <= WIRE_MIDDLE_Z, 300)
	Input.action_release("move_forward")
	await _until(func() -> bool: return health.dead, 800)
	await _ticks(120)
	var result := {hits = rec.hits, zs = rec.zs, died = rec.died, quiet = quiet, health = health.health, stopped = player.global_position.z}
	_fast_forward(false)
	await _unload(arena.arena)
	return result

## The sentences about the Live Wire, with a real player in a small scene, in physics frames (60 a second): one hit the moment
## the body steps in, one more every half second while it stays, four hits from 100 reach 0 (1.5 s), no hit after death; stepping
## out stops the hits and stepping in again hits at once.
func test_live_wire_hits(step: String) -> Array[String]:
	var failures: Array[String] = []
	var live := await _walk_in_and_stay(step, "live_wire")
	var hits: Array = live.hits
	_expect(failures, live.quiet, "a hit came while the player stood 1.5 m from the wire")
	var values: Array[int] = []
	var frames: Array[int] = []
	for hit: Vector2i in hits:
		frames.append(hit.x)
		values.append(hit.y)
	_expect(failures, values == [75, 50, 25, 0], "the health after each hit is %s, expected [75, 50, 25, 0]: four hits of 25, and no hit after 0" % [values])
	_expect(failures, live.died == ["Live Wire"], "died went out %s, expected once with Live Wire" % [live.died])
	if frames.size() == 4:
		var gaps: Array[int] = []
		for i in range(1, frames.size()):
			gaps.append(frames[i] - frames[i - 1])
			_expect(failures, gaps[-1] >= HIT_INTERVAL_TICKS - 1 and gaps[-1] <= HIT_INTERVAL_TICKS + 1, "hits %d and %d are %d physics ticks apart, expected 30 (0.5 s)" % [i, i + 1, gaps[-1]])
		var span := frames[3] - frames[0]
		_expect(failures, span >= 3 * HIT_INTERVAL_TICKS - 3 and span <= 3 * HIT_INTERVAL_TICKS + 3, "the first hit to the fourth took %d ticks (%.2f s), expected about 90 (1.5 s)" % [span, span / 60.0])
		_expect(failures, absf(float(live.zs[0]) - (WIRE_AT.z + 0.4)) < 0.2, "the first hit came with the player at z %.2f; the capsule (radius 0.4) reaches the wire's edge (z %.1f) at %.2f" % [live.zs[0], WIRE_AT.z, WIRE_AT.z + 0.4])
		_note("%s: walking in, hits at physics ticks %s, the health after them %s: %s ticks apart (%.2f s each), %.2f s from the first hit to 0; the first hit with the player at z %.2f (the wire's edge is at %.1f, the capsule's radius 0.4)" % [step, frames.map(func(frame: int) -> int: return frame - frames[0]), values, gaps, gaps[0] / 60.0, (frames[3] - frames[0]) / 60.0, live.zs[0], WIRE_AT.z])
	_expect(failures, hits.size() == 4 and live.health == 0, "after 2 s more in the wire there were %d hits, the health is %d" % [hits.size(), live.health])
	_note("%s: standing dead in the wire for 2 s took no further hit (%d hits in all, health %d)" % [step, hits.size(), live.health])
	# Stepping out stops the hits, stepping in again hits at once.
	_fast_forward(true)
	var arena := _arena(step, "live_wire")
	var player: CharacterBody3D = arena.player
	var wire: Area3D = arena.wire
	var health: Node = player.get_node("Health")
	var rec := _record(health)
	await _ticks(10)
	Input.action_press("move_forward")
	await _until(func() -> bool: return player.global_position.z <= WIRE_MIDDLE_Z, 300)
	Input.action_release("move_forward")
	await _until(func() -> bool: return (rec.hits as Array).size() >= 2, 120)
	_expect(failures, health.health == 50 and wire.inside.size() == 1 and not wire.timer.is_stopped(), "two hits in: health %d, %d inside, timer stopped %s" % [health.health, wire.inside.size(), wire.timer.is_stopped()])
	Input.action_press("move_back")
	var left := await _until(func() -> bool: return wire.inside.is_empty(), 120)
	Input.action_release("move_back")
	await _ticks(2 * HIT_INTERVAL_TICKS + 15) # more than two intervals: a third hit would have come
	_expect(failures, left and health.health == 50 and (rec.hits as Array).size() == 2, "after stepping out: left %s, health %d, %d hits in all; expected 50 and two" % [left, health.health, (rec.hits as Array).size()])
	_expect(failures, wire.timer.is_stopped() and wire.inside.is_empty(), "after stepping out the Timer is stopped %s, %d still inside" % [wire.timer.is_stopped(), wire.inside.size()])
	Input.action_press("move_forward")
	await _until(func() -> bool: return not wire.inside.is_empty(), 120)
	Input.action_release("move_forward")
	_expect(failures, health.health == 25 and (rec.hits as Array).size() == 3 and not wire.timer.is_stopped(), "stepping in again: health %d, %d hits in all, Timer stopped %s; expected 25, three, running" % [health.health, (rec.hits as Array).size(), wire.timer.is_stopped()])
	_note("%s: two hits (50), then stepping out: no hit in %d ticks (%.1f s) and the Timer stopped; stepping in again hit at once (25) and the Timer runs" % [step, 2 * HIT_INTERVAL_TICKS + 15, (2 * HIT_INTERVAL_TICKS + 15) / 60.0])
	_fast_forward(false)
	await _unload(arena.arena)
	return failures

## What a hazard reports and what it hurts: bodies of its mask only, and of them only the ones with a child named Health.
func test_hazard_looks_only_for_health(step: String) -> Array[String]:
	var failures: Array[String] = []
	_fast_forward(true)
	var arena := _arena(step, "live_wire", false)
	var wire: Area3D = arena.wire
	var health_script := load("res://steps/%s/health.gd" % step) as GDScript
	var middle := Vector3(WIRE_AT.x, 0.3, WIRE_MIDDLE_Z)
	# The world: a wall on layer 1 right in the box, and the floor under it. Nothing of that is reported.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.4, 0.4, 0.4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = middle
	arena.arena.add_child(wall)
	var mover := _dummy_body(RigidBody3D.new(), middle + Vector3(0.0, 0.0, 0.3), 1) # a body of the world that is not static: a control for what the mask keeps out
	arena.arena.add_child(mover)
	await _ticks(6)
	var reported: Array = wire.get_overlapping_bodies()
	_expect(failures, reported.is_empty() and wire.inside.is_empty() and wire.timer.is_stopped(), "the wire reports %s (a wall and a body on layer 1 are in it and the floor under it)" % [reported])
	wire.collision_mask = 3 # the control: with layer 1 in the mask the body of the world is reported, so the check above can see
	await _ticks(6)
	var with_world: Array = wire.get_overlapping_bodies()
	_expect(failures, with_world.has(mover), "with layer 1 in the mask the wire does not report a body of layer 1 that stands in it: the test cannot see the world")
	wire.collision_mask = 2
	await _ticks(6)
	_expect(failures, wire.get_overlapping_bodies().is_empty(), "back at layer 2 the wire still reports %s" % [wire.get_overlapping_bodies()])
	wall.free()
	mover.free()
	# A body of the player's layer without a Health child: seen (it is in the mask), never hurt, never put on the list.
	var plain := _dummy_body(RigidBody3D.new(), middle)
	arena.arena.add_child(plain)
	await _ticks(6)
	_expect(failures, wire.get_overlapping_bodies().has(plain) and wire.inside.is_empty() and wire.timer.is_stopped(), "a body without a Health child: reported %s, %d on the list, Timer stopped %s" % [wire.get_overlapping_bodies().has(plain), wire.inside.size(), wire.timer.is_stopped()])
	plain.global_position = middle + Vector3(10.0, 0.0, 0.0)
	await _ticks(6)
	_expect(failures, wire.get_overlapping_bodies().is_empty() and wire.inside.is_empty() and wire.timer.is_stopped(), "after the body without Health left: %d on the list, Timer stopped %s" % [wire.inside.size(), wire.timer.is_stopped()])
	plain.free()
	# A Health under another name: not found, not hurt.
	var misnamed := _dummy_body(RigidBody3D.new(), middle)
	var hitpoints := health_script.new() as Node
	hitpoints.name = &"Hitpoints"
	misnamed.add_child(hitpoints)
	arena.arena.add_child(misnamed)
	await _ticks(6)
	_expect(failures, wire.get_overlapping_bodies().has(misnamed) and wire.inside.is_empty() and hitpoints.health == 100, "a health node named Hitpoints: on the list %d, health %d; the hazard looks for the name Health only" % [wire.inside.size(), hitpoints.health])
	misnamed.free()
	# Another kind of body with a child named Health: hurt at once, then on the timer. The hazard never asks what the body is.
	var crate := _dummy_body(RigidBody3D.new(), middle)
	var crate_health := health_script.new() as Node
	crate_health.name = &"Health"
	crate.add_child(crate_health)
	arena.arena.add_child(crate)
	var rec := _record(crate_health) # after the node is in the tree: its _ready sent changed(100) already
	await _until(func() -> bool: return (rec.hits as Array).size() >= 2, 90)
	var crate_hits: Array = rec.hits
	_expect(failures, crate_hits.size() == 2 and wire.inside.size() == 1 and crate_health.health == 50, "a RigidBody3D with a Health child: %d hits, %d on the list, health %d; expected two, one, 50" % [crate_hits.size(), wire.inside.size(), crate_health.health])
	if crate_hits.size() == 2:
		var gap: int = crate_hits[1].x - crate_hits[0].x
		_expect(failures, gap >= HIT_INTERVAL_TICKS - 1 and gap <= HIT_INTERVAL_TICKS + 1, "the two hits are %d ticks apart" % gap)
	# Two bodies inside at once: both are hit, the timer keeps going until the last one leaves.
	var second := _dummy_body(RigidBody3D.new(), middle + Vector3(0.2, 0.0, 0.0))
	var second_health := health_script.new() as Node
	second_health.name = &"Health"
	second.add_child(second_health)
	arena.arena.add_child(second)
	await _until(func() -> bool: return second_health.health < 100, 20)
	_expect(failures, wire.inside.size() == 2 and second_health.health == 75, "a second body stepped in: %d on the list, its health %d; expected two and 75" % [wire.inside.size(), second_health.health])
	await _until(func() -> bool: return crate_health.health <= 25, 60)
	_expect(failures, crate_health.health == 25 and second_health.health == 50, "on the next hit both are hurt: %d and %d, expected 25 and 50" % [crate_health.health, second_health.health])
	crate.global_position = middle + Vector3(10.0, 0.0, 0.0)
	await _ticks(6)
	_expect(failures, wire.inside.size() == 1 and not wire.timer.is_stopped(), "one body left: %d on the list, Timer stopped %s; the Timer must run for the one that stays" % [wire.inside.size(), wire.timer.is_stopped()])
	second.global_position = middle + Vector3(-10.0, 0.0, 0.0)
	await _ticks(6)
	_expect(failures, wire.inside.is_empty() and wire.timer.is_stopped(), "both left: %d on the list, Timer stopped %s" % [wire.inside.size(), wire.timer.is_stopped()])
	_note("%s: a wall, the floor and a moving body of layer 1 are not reported (with layer 1 added to the mask the moving body is, as a control; Jolt's areas leave static bodies out anyway); a body of layer 2 without a Health child is seen and ignored; a node named Hitpoints is ignored; a RigidBody3D with a child named Health is hurt on entering and every half second; two bodies are hit together and the Timer stops when the last one leaves" % step)
	_fast_forward(false)
	await _unload(arena.arena)
	return failures

## A rigid body with a small sphere shape, placed at a point, on the player's layer unless told otherwise. It collides with nothing
## (mask 0), feels no gravity and never sleeps: Jolt's areas only see bodies that are awake.
func _dummy_body(body: RigidBody3D, place: Vector3, layer := 2) -> RigidBody3D:
	body.collision_layer = layer
	body.collision_mask = 0
	body.gravity_scale = 0.0
	body.can_sleep = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	body.add_child(shape)
	body.position = place
	return body

## The Broken Glass is the same script with 10 a hit: ten hits from 100 kill, half a second apart, and the cause is its own.
func test_broken_glass_hits(step: String) -> Array[String]:
	var failures: Array[String] = []
	var glass := await _walk_in_and_stay(step, "broken_glass")
	var hits: Array = glass.hits
	var values: Array[int] = []
	var frames: Array[int] = []
	for hit: Vector2i in hits:
		frames.append(hit.x)
		values.append(hit.y)
	_expect(failures, glass.quiet, "a hit came while the player stood 1.5 m from the glass")
	_expect(failures, values == [90, 80, 70, 60, 50, 40, 30, 20, 10, 0], "the health after each hit is %s, expected 90 down to 0 in tens" % [values])
	_expect(failures, glass.died == ["Broken Glass"], "died went out %s, expected once with Broken Glass" % [glass.died])
	if frames.size() == 10:
		var worst := 0
		for i in range(1, frames.size()):
			worst = maxi(worst, absi(frames[i] - frames[i - 1] - HIT_INTERVAL_TICKS))
		_expect(failures, worst <= 1, "the hits are up to %d ticks off the 30 of half a second" % worst)
		var span := frames[-1] - frames[0]
		_expect(failures, span >= 9 * HIT_INTERVAL_TICKS - 4 and span <= 9 * HIT_INTERVAL_TICKS + 4, "the first hit to the tenth took %d ticks, expected about 270" % span)
		_note("%s: Broken Glass: ten hits of 10, %d ticks (%.2f s) from the first to the last, at most %d tick off the half second; died with '%s'" % [step, span, span / 60.0, worst, glass.died[0] if not (glass.died as Array).is_empty() else ""])
	return failures

#endregion

#region Contents of the rooms: tutorial 05's check

## Tutorial 05's check_contents.gd, the copy of this step, over seeds 1 to 200 and both lock chances (the level's 0.4 and the worst
## case 1.0), with the hazards in the prop sets: no prop of the sets, hazard or not, stands in the corridor from the entrance to the
## exit, within 1 m of a key, on the way to a key, in a door or on a pillar of the room. This proves the narration's sentence
## "the contents check of tutorial five still passes".
func test_contents(step: String) -> Array[String]:
	var failures: Array[String] = []
	var contents := load("res://steps/%s/check_contents.gd" % step) as GDScript
	var solvable := load("res://steps/%s/check_solvable.gd" % step) as GDScript
	var chances: Array = contents.get_script_constant_map()["LOCK_CHANCES"]
	var layouts: Array = contents.call("read_layouts")
	var prop_sets := _prop_sets(step)
	var rooms := 0
	var props := 0
	var spots := 0
	var wires := 0
	var glass := 0
	var wire_rooms := 0
	var glass_rooms := 0
	var bad_seeds := 0
	for chance: float in chances:
		for chain_seed in range(1, CONTENT_SEEDS + 1):
			if chain_seed % 20 == 0:
				await process_frame
			var chain: RefCounted = solvable.call("build", chain_seed, GOAL_ROOM, chance)
			var bare: RefCounted = contents.call("build_without_props", chain_seed, GOAL_ROOM, chance)
			var problems: Array = contents.call("problems_of", chain, bare, layouts)
			problems.append_array(solvable.call("problems_of", chain, solvable.call("build", chain_seed, GOAL_ROOM, 0.0)))
			for plan: Object in chain.plans:
				rooms += 1
				spots += plan.props.size()
				var here := _hazards_in(plan, prop_sets)
				wires += here.x
				glass += here.y
				wire_rooms += 1 if here.x > 0 else 0
				glass_rooms += 1 if here.y > 0 else 0
				for prop: int in plan.props:
					props += 1 if prop != Chain.NO_PROP else 0
			if not problems.is_empty():
				bad_seeds += 1
				if bad_seeds <= 6:
					failures.append("seed %d, lock chance %.1f: %s" % [chain_seed, chance, problems.slice(0, 2)])
	_expect(failures, bad_seeds == 0, "%d seeds of %d fail the contents check of tutorial 05 (step %s)" % [bad_seeds, CONTENT_SEEDS * chances.size(), step])
	_expect(failures, wires > 0 and (glass > 0) == DEATH_STEPS.has(step), "%d Live Wires and %d Broken Glass in the plans checked: the check proves nothing without the hazards in them" % [wires, glass])
	_note("%s: seeds 1-%d, lock chances %s: %d rooms, %d props on %d prop spots, %d Live Wires in %d rooms, %d Broken Glass in %d rooms, %d seeds with problems" % [step, CONTENT_SEEDS, chances, rooms, props, spots, wires, wire_rooms, glass, glass_rooms, bad_seeds])
	return failures

## The check passes only if it can see a hazard. The footprint is read from the box of the Area3D (1 x 1 m), and a Live Wire put
## on the way through a room is called.
func test_contents_check_sees_the_hazard() -> Array[String]:
	var failures: Array[String] = []
	var step := HAZARD_STEP
	var contents := load("res://steps/%s/check_contents.gd" % step) as GDScript
	var solvable := load("res://steps/%s/check_solvable.gd" % step) as GDScript
	var wire_scene := load("res://steps/%s/props/live_wire.tscn" % step) as PackedScene
	var foot: Rect2 = contents.call("footprint", wire_scene, Transform3D.IDENTITY)
	_expect(failures, foot.position.is_equal_approx(Vector2(-0.5, -1.0)) and foot.size.is_equal_approx(Vector2(1.0, 1.0)), "the footprint of the Live Wire is %s, expected the box: x -0.5 to 0.5, z -1 to 0" % foot)
	var layouts: Array = contents.call("read_layouts")
	var layout: Object = layouts[Chain.Type.STRAIGHT]
	var corridor: PackedVector2Array = layout.corridor
	var middle := (corridor[0] + corridor[2]) / 2.0
	layout.prop_spots[0] = Transform3D(Basis.IDENTITY, Vector3(middle.x, 0.0, middle.y + 0.5)) # prop spot 0 of the straight room now lies in the corridor
	var wire_index := _prop_scene_file(step, "straight").find("live_wire.tscn")
	_expect(failures, wire_index >= 0, "the straight room's set has no Live Wire")
	var found: Array[String] = []
	for chain_seed in range(1, 40):
		var chain: RefCounted = solvable.call("build", chain_seed, GOAL_ROOM, 0.4)
		var bare: RefCounted = contents.call("build_without_props", chain_seed, GOAL_ROOM, 0.4)
		var straight: Object = null
		for plan: Object in chain.plans:
			if plan.type == Chain.Type.STRAIGHT and plan.props.size() > 0:
				straight = plan
				break
		if straight == null:
			continue
		straight.props[0] = wire_index
		for problem: String in contents.call("problems_of", chain, bare, layouts):
			if problem.contains("live_wire") and problem.contains("corridor"):
				found.append(problem)
		if not found.is_empty():
			break
	_expect(failures, not found.is_empty(), "a Live Wire put into the corridor of a straight room was not called by the contents check")
	_note("the Live Wire's footprint is the box: %s; with its prop spot moved into the straight room's corridor the check says: %s" % [foot, found[0] if not found.is_empty() else "(nothing)"])
	return failures

## How often the hazards come up: the plans of seeds 1 to 200 up to the goal room 20, counted by room.
func test_how_often_hazards_come_up() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [HAZARD_STEP, DEATH_STEP]:
		var prop_sets := _prop_sets(step)
		var rooms := 0
		var with_props := 0
		var wire_rooms := 0
		var glass_rooms := 0
		var both_rooms := 0
		var any_rooms := 0
		var wires := 0
		var glass := 0
		var runs_without := 0
		var per_run_least := 1000
		var per_run_most := 0
		var by_type: Dictionary[String, Vector3i] = {}
		for chain_seed in range(1, PLAN_SEEDS + 1):
			if chain_seed % 20 == 0:
				await process_frame
			var in_run := 0
			for plan: Object in _run_plans(step, chain_seed):
				rooms += 1
				if plan.props.size() == 0:
					continue
				with_props += 1
				var here := _hazards_in(plan, prop_sets)
				wires += here.x
				glass += here.y
				wire_rooms += 1 if here.x > 0 else 0
				glass_rooms += 1 if here.y > 0 else 0
				both_rooms += 1 if here.x > 0 and here.y > 0 else 0
				any_rooms += 1 if here.x + here.y > 0 else 0
				in_run += 1 if here.x + here.y > 0 else 0
				var type_name: String = Chain.Type.keys()[plan.type]
				var seen: Vector3i = by_type.get(type_name, Vector3i.ZERO)
				by_type[type_name] = Vector3i(seen.x + 1, seen.y + (1 if here.x > 0 else 0), seen.z + (1 if here.y > 0 else 0))
			runs_without += 1 if in_run == 0 else 0
			per_run_least = mini(per_run_least, in_run)
			per_run_most = maxi(per_run_most, in_run)
		_expect(failures, wire_rooms > 0, "%s: no room of %d holds a Live Wire" % [step, rooms])
		_expect(failures, (glass_rooms > 0) == (step == DEATH_STEP), "%s: %d rooms hold a Broken Glass" % [step, glass_rooms])
		var types: Array[String] = []
		for type_name: String in by_type:
			types.append("%s %d of %d" % [type_name.to_lower(), by_type[type_name].y, by_type[type_name].x] + (", glass %d" % by_type[type_name].z if step == DEATH_STEP else ""))
		if step == HAZARD_STEP:
			_note("step 2, seeds 1-%d, goal room %d: %d rooms (%d with prop spots); a Live Wire in %d of them (%.1f %%), %d wires in all; %.1f rooms with a wire per run (least %d, most %d), %d runs without one; by room type: %s" % [PLAN_SEEDS, GOAL_ROOM, rooms, with_props, wire_rooms, 100.0 * wire_rooms / with_props, wires, float(any_rooms) / PLAN_SEEDS, per_run_least, per_run_most, runs_without, "; ".join(types)])
		else:
			_note("step 3, seeds 1-%d, goal room %d: %d rooms (%d with prop spots); a Live Wire in %d (%.1f %%), a Broken Glass in %d (%.1f %%), both in one room in %d, either in %d (%.1f %%); %d wires and %d pieces of glass; %.1f hazard rooms per run (least %d, most %d), %d runs without one; by room type: %s" % [PLAN_SEEDS, GOAL_ROOM, rooms, with_props, wire_rooms, 100.0 * wire_rooms / with_props, glass_rooms, 100.0 * glass_rooms / with_props, both_rooms, any_rooms, 100.0 * any_rooms / with_props, wires, glass, float(any_rooms) / PLAN_SEEDS, per_run_least, per_run_most, runs_without, "; ".join(types)])
	return failures

## The level makes what the plan holds: one hazard node in a room for every hazard prop of its plan, at the prop spot, with the
## step's script.
func test_levels_make_the_planned_hazards() -> Array[String]:
	var failures: Array[String] = []
	var made := 0
	for step in HAZARD_STEPS:
		var prop_sets := _prop_sets(step)
		for chain_seed in range(1, NODE_SEEDS + 1):
			var main := await _load_step(step, false, {"goal_room": GOAL_ROOM, "chain_seed": chain_seed})
			var level: Node3D = main.get_node("Level")
			_open_every_door(level)
			for index: int in level.rooms:
				var room: Node3D = level.rooms[index]
				var plan: Object = level.chain.plans[index]
				var nodes: Array[Node] = []
				for child in room.get_children():
					if child is Area3D and child.get_script() != null and (child.get_script() as Script).resource_path == "res://steps/%s/hazard.gd" % step:
						nodes.append(child)
				var planned := _hazards_in(plan, prop_sets)
				_expect(failures, nodes.size() == planned.x + planned.y, "%s seed %d room %d: %d hazard nodes, the plan holds %d" % [step, chain_seed, index, nodes.size(), planned.x + planned.y])
				for node in nodes:
					made += 1
					_expect(failures, (node as Area3D).collision_mask == 2 and (node as Area3D).collision_layer == 0, "%s seed %d room %d: a hazard with mask %d" % [step, chain_seed, index, (node as Area3D).collision_mask])
			await _unload(main)
			if failures.size() > 8:
				return failures
	_expect(failures, made > 0, "no hazard node was made in %d runs" % NODE_SEEDS)
	_note("%d hazard nodes made in seeds 1-%d of steps 2, 3 and 4 (every room opened), each as many as its plan holds, each on mask 2" % [made, NODE_SEEDS])
	return failures

## The point a run starts at is 1.5 m inside the entrance of room 0, and a revive puts the player on the same point of the room it died
## in. A hazard that reaches it would hurt the player the moment it appears. So no hazard of any plan may come within the capsule's
## radius of that point: its footprint is read from the box of the scene, the point from the room scene's entrance marker.
func test_spawn_point_is_clear_of_hazards() -> Array[String]:
	var failures: Array[String] = []
	var depth: float = (load("res://steps/%s/level.gd" % FINAL_STEP) as GDScript).get_script_constant_map()["SPAWN_DEPTH"]
	var player := (load("res://steps/%s/player.tscn" % FINAL_STEP) as PackedScene).instantiate()
	var radius: float = ((player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).radius
	player.free()
	var nearest := INF
	var checked := 0
	var where := ""
	for step in HAZARD_STEPS:
		var contents := load("res://steps/%s/check_contents.gd" % step) as GDScript
		var layouts: Array = contents.call("read_layouts")
		var prop_sets := _prop_sets(step)
		var scenes: Array = _chain_script(step).get_script_constant_map()["SCENES"]
		var spawns: Array[Vector2] = []
		for scene: PackedScene in scenes:
			var room := scene.instantiate()
			var point := (room.get_node("Entrance") as Marker3D).transform * Vector3(0.0, 0.0, -depth)
			spawns.append(Vector2(point.x, point.z))
			room.free()
		for chain_seed in range(1, PLAN_SEEDS + 1):
			if chain_seed % 20 == 0:
				await process_frame
			for plan: Object in _run_plans(step, chain_seed):
				var layout: Object = layouts[plan.type]
				for spot: int in plan.props.size():
					var prop: int = plan.props[spot]
					if prop == Chain.NO_PROP:
						continue
					var scene := prop_sets[plan.type].scenes[prop] as PackedScene
					var file := scene.resource_path.get_file()
					if file != "live_wire.tscn" and file != "broken_glass.tscn":
						continue
					var foot: Rect2 = contents.call("footprint", scene, layout.prop_spots[spot])
					var distance := _distance_to_rect(spawns[plan.type], foot)
					checked += 1
					if distance < nearest:
						nearest = distance
						where = "%s seed %d room %d (%s) spot %d" % [step, chain_seed, plan.index, Chain.Type.keys()[plan.type].to_lower(), spot]
					_expect(failures, distance >= radius, "%s seed %d room %d spot %d: the %s is %.2f m from the point a player starts or revives at, the capsule is %.1f m wide" % [step, chain_seed, plan.index, spot, file.get_basename(), distance, radius * 2.0])
	_expect(failures, checked > 1000, "only %d hazards were checked" % checked)
	_note("%d hazards of steps 2, 3 and 4 over seeds 1-%d: the nearest one is %.2f m from the point %.1f m inside the entrance (%s), the capsule's radius is %.1f m" % [checked, PLAN_SEEDS, nearest, depth, where, radius])
	return failures

## The distance from a point to a rectangle on the floor, 0 inside it.
func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var outside := Vector2(maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x), maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y))
	return outside.length()

#endregion

#region Death and revive (steps 3 and 4)

## A hazard of the step on the spot where the player stands, in the room the player is in (it goes with the room).
func _hazard_under(level: Node3D, step: String, hazard_scene := "live_wire") -> Area3D:
	var wire := (load("res://steps/%s/props/%s.tscn" % [step, hazard_scene]) as PackedScene).instantiate() as Area3D
	(level.rooms[level.current] as Node3D).add_child(wire)
	wire.global_transform = Transform3D(Basis.IDENTITY, (level.player as Node3D).global_position + Vector3(0.0, 0.0, 0.5)) # the box's middle is 0.5 m in front of its origin
	return wire

## Steps 1 and 2 know no death: there is no DEAD state and nothing listens to died, so a player at 0 health walks on.
func test_no_death_before_step_3() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [HEALTH_STEPS[0], HAZARD_STEP]:
		var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
		var level: Node3D = main.get_node("Level")
		var player: CharacterBody3D = level.player
		var health: Node = level.health
		var states: Dictionary = (level.get_script() as GDScript).get_script_constant_map()["State"]
		_expect(failures, states.keys() == ["READY", "RUNNING", "FINISHED"], "%s: the states are %s, expected READY, RUNNING, FINISHED" % [step, states.keys()])
		_expect(failures, health.get_signal_connection_list("died").is_empty(), "%s: %d listeners on died; the narration says nothing listens to it yet" % [step, health.get_signal_connection_list("died").size()])
		_expect(failures, main.get_node_or_null("HUD/DeathPanel") == null, "%s: the HUD has a death screen" % step)
		_fast_forward(true)
		var state_before: int = level.state
		if step == HAZARD_STEP:
			_hazard_under(level, step)
			var dead := await _until(func() -> bool: return health.dead, 300)
			_expect(failures, dead, "%s: four hits of the Live Wire did not bring the health to 0 (it is %d)" % [step, health.health])
		else:
			health.hurt(100, "Test")
		await _ticks(10)
		_expect(failures, health.health == 0 and health.dead, "%s: health %d, dead %s" % [step, health.health, health.dead])
		_expect(failures, level.state == state_before and not player.frozen, "%s: state %d (was %d), frozen %s: a player at 0 health must carry on" % [step, level.state, state_before, player.frozen])
		var label := main.get_node("HUD/Stats/HealthLabel") as Label
		_expect(failures, label.text == "Health 0", "%s: the HUD says '%s' at 0 health" % [step, label.text])
		var before := player.global_position
		Input.action_press("move_left") # sideways: the wire is ahead
		await _ticks(20)
		Input.action_release("move_left")
		var moved := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
		_expect(failures, moved > 0.5, "%s: the player at 0 health moved %.2f m in 20 ticks, expected it to walk on" % [step, moved])
		_note("%s: states %s, no listener on died; at 0 health the player still walked %.1f m in 20 ticks (state %d, HUD '%s')" % [step, states.keys(), moved, level.state, label.text])
		_fast_forward(false)
		await _unload(main)
	return failures

## Steps 3 and 4: the run ends in DEAD. A real Live Wire under the player in the real level.
func test_death(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	var hud := main.get_node("HUD")
	var player: CharacterBody3D = level.player
	var health: Node = level.health
	var panel := hud.get_node("DeathPanel") as PanelContainer
	var cause_label := hud.get_node("DeathPanel/Rows/DeathCause") as Label
	var title_label := hud.get_node("DeathPanel/Rows/DeathTitle") as Label
	var seed_box := hud.get_node("SeedEntry")
	var shown: Array[bool] = [panel.visible] # whether the death screen shows, in each state of this test
	var states: Dictionary = (level.get_script() as GDScript).get_script_constant_map()["State"]
	_expect(failures, states.keys() == ["READY", "RUNNING", "FINISHED", "DEAD"] and states["DEAD"] == STATE_DEAD, "the states are %s, expected READY, RUNNING, FINISHED, DEAD" % [states])
	_expect(failures, health.get_signal_connection_list("died").size() == 1, "%d listeners on died, expected the level's one" % health.get_signal_connection_list("died").size())
	_expect(failures, level.state == STATE_READY and not player.frozen and not panel.visible and health.health == 100, "at the start: state %d, frozen %s, death screen %s, health %d" % [level.state, player.frozen, panel.visible, health.health])
	_fast_forward(true)
	level.rooms[0].door.open() # the run starts: the clock runs
	await _ticks(60)
	shown.append(panel.visible)
	_expect(failures, level.state == STATE_RUNNING and level.run_time > 0.5, "the run did not start: state %d, %.2f s" % [level.state, level.run_time])
	# A hit that leaves some health is no death.
	health.hurt(30, "Test")
	_expect(failures, level.state == STATE_RUNNING and not player.frozen and not panel.visible, "a hit of 30 changed the run: state %d, frozen %s, death screen %s" % [level.state, player.frozen, panel.visible])
	health.reset()
	# Alive, the seed box takes the controls and gives them back.
	seed_box.call("open")
	_expect(failures, level.typing and player.frozen, "the seed box is up: typing %s, frozen %s" % [level.typing, player.frozen])
	seed_box.call("close")
	_expect(failures, not level.typing and not player.frozen, "alive, closing the seed box gave no controls back (typing %s, frozen %s)" % [level.typing, player.frozen])
	# The real hazard kills.
	var died_log: Array[String] = []
	health.connect("died", func(cause: String) -> void: died_log.append(cause))
	_hazard_under(level, step)
	var killed := await _until(func() -> bool: return level.state == STATE_DEAD, 400)
	shown.append(panel.visible)
	_expect(failures, killed and health.health == 0 and health.dead, "the Live Wire did not end the run: state %d, health %d" % [level.state, health.health])
	_expect(failures, died_log == ["Live Wire"] and level.death_cause == "Live Wire", "died went out %s, the level keeps '%s'; expected once, Live Wire" % [died_log, level.death_cause])
	_expect(failures, player.frozen, "the dead player is not frozen")
	_expect(failures, panel.visible and cause_label.text == "Hit by Live Wire" and title_label.text == "You died", "the death screen shows %s with '%s' and '%s'" % [panel.visible, title_label.text, cause_label.text])
	_expect(failures, not (hud.get_node("FinishPanel") as Control).visible, "the finish panel shows with the death screen")
	# The clock stops by itself.
	var stopped_at: float = level.run_time
	await _ticks(90)
	_expect(failures, level.run_time == stopped_at, "the clock went on after death: %.3f s, then %.3f s" % [stopped_at, level.run_time])
	# The dead player does not walk.
	var spot := player.global_position
	Input.action_press("move_forward")
	await _ticks(40)
	Input.action_release("move_forward")
	var walked := Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
	_expect(failures, walked < 0.001, "the dead player walked %.3f m" % walked)
	# Opening and closing the seed box while dead leaves the player frozen.
	seed_box.call("open")
	_expect(failures, level.typing and player.frozen and level.state == STATE_DEAD, "seed box up while dead: typing %s, frozen %s, state %d" % [level.typing, player.frozen, level.state])
	seed_box.call("close")
	_expect(failures, not level.typing and player.frozen and level.state == STATE_DEAD, "closing the seed box gave the dead player the controls back: typing %s, frozen %s, state %d" % [level.typing, player.frozen, level.state])
	Input.action_press("move_forward")
	await _ticks(40)
	Input.action_release("move_forward")
	walked = Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
	_expect(failures, walked < 0.001, "after the seed box closed the dead player walked %.3f m" % walked)
	# Step 3 has no revive: E does nothing. (Step 4's revive is tested on its own.)
	if step == DEATH_STEP:
		await _action("revive")
		_expect(failures, level.state == STATE_DEAD and health.health == 0 and player.frozen, "E in step 3 changed the dead run: state %d, health %d" % [level.state, health.health])
	# R: a new run at full health.
	await _action("regenerate")
	shown.append(panel.visible)
	_expect(failures, level.state == STATE_READY and health.health == 100 and not health.dead and not player.frozen and level.run_time == 0.0, "R after death: state %d, health %d, dead %s, frozen %s, clock %.2f" % [level.state, health.health, health.dead, player.frozen, level.run_time])
	_expect(failures, (hud.get_node("Stats/HealthLabel") as Label).text == "Health 100" and not panel.visible, "R after death: the HUD says '%s', death screen %s" % [(hud.get_node("Stats/HealthLabel") as Label).text, panel.visible])
	var fresh := player.global_position
	Input.action_press("move_left")
	await _ticks(20)
	Input.action_release("move_left")
	_expect(failures, Vector2(player.global_position.x - fresh.x, player.global_position.z - fresh.z).length() > 0.5, "the player does not walk after R")
	# The other cause: Broken Glass, ten hits.
	level.rooms[0].door.open()
	_hazard_under(level, step, "broken_glass")
	killed = await _until(func() -> bool: return level.state == STATE_DEAD, 800)
	_expect(failures, killed and level.death_cause == "Broken Glass" and cause_label.text == "Hit by Broken Glass" and panel.visible, "the Broken Glass did not end the run with its cause: state %d, cause '%s', the screen says '%s'" % [level.state, level.death_cause, cause_label.text])
	await _action("regenerate")
	shown.append(panel.visible)
	_expect(failures, shown == [false, false, true, false, false], "the death screen showed %s over ready, running, dead, ready after R, ready after R again; expected only while dead" % [shown])
	_note("%s: a Live Wire under the player ended the run in DEAD (health 0, cause 'Live Wire', the screen 'You died' / 'Hit by Live Wire'); the clock stopped at %.2f s and stayed; the dead player walked %.3f m; the seed box opened and closed left it frozen; R gave READY, 100 health, a walking player; the Broken Glass gave 'Hit by Broken Glass'; the death screen showed in %s of ready, running, dead, ready: only while dead" % [step, stopped_at, walked, shown.slice(0, 4)])
	_fast_forward(false)
	await _unload(main)
	return failures

## Step 4: one revive per run, in the room the player died in.
func test_revive() -> Array[String]:
	var failures: Array[String] = []
	var step := FINAL_STEP
	var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	var hud := main.get_node("HUD")
	var player: CharacterBody3D = level.player
	var health: Node = level.health
	var panel := hud.get_node("DeathPanel") as PanelContainer
	var hint := hud.get_node("DeathPanel/Rows/DeathHint") as Label
	var health_label := hud.get_node("Stats/HealthLabel") as Label
	var constants: Dictionary = (level.get_script() as GDScript).get_script_constant_map()
	var spawn_depth: float = constants["SPAWN_DEPTH"]
	_expect(failures, constants["REVIVES_PER_RUN"] == 1 and level.revives == 1, "revives per run %s, left %d; expected one" % [constants["REVIVES_PER_RUN"], level.revives])
	_expect(failures, hint.text == "E  revive    R  run again", "the hint says '%s' with a revive left" % hint.text)
	# Alive: E does nothing at all (no refill either).
	health.hurt(40, "Test")
	var standing := player.global_position
	await _action("revive")
	_expect(failures, health.health == 60 and level.revives == 1 and level.state == STATE_READY and player.global_position.distance_to(standing) < 0.01, "E while alive: health %d (was 60), revives %d, state %d, moved %.3f m" % [health.health, level.revives, level.state, player.global_position.distance_to(standing)])
	health.reset()
	# To room 3 with the real autopilot; the run is RUNNING and has a clock.
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var arrived := await _walk(level, pilot, 3, 0, Callable())
	await _ticks(10)
	_expect(failures, arrived and level.current == 3 and level.state == STATE_RUNNING and level.run_time > 3.0, "the walk to room 3: arrived %s, room %d, state %d, %.1f s, health %d" % [arrived, level.current, level.state, level.run_time, health.health])
	if not arrived or level.state != STATE_RUNNING:
		_fast_forward(false)
		await _unload(main)
		return failures
	health.reset()
	level.keys += 2 # keys in hand: a revive must not take them
	var room: Node3D = level.rooms[level.current]
	var entrance := room.get("entrance") as Marker3D
	var spawn := entrance.global_transform.translated_local(Vector3(0.0, 0.0, -spawn_depth))
	# The player stands 3 m inside the room, in a Live Wire.
	player.global_transform = entrance.global_transform.translated_local(Vector3(0.0, 0.0, -3.0))
	player.velocity = Vector3.ZERO
	await _ticks(5)
	var wire := _hazard_under(level, step)
	var killed := await _until(func() -> bool: return level.state == STATE_DEAD, 400)
	_expect(failures, killed and health.health == 0, "the wire did not end the run: state %d, health %d" % [level.state, health.health])
	var death_spot := player.global_position
	var rooms_at_death: Array = level.rooms.keys()
	var room_at_death: int = level.current
	var keys_at_death: int = level.keys
	var time_at_death: float = level.run_time
	_expect(failures, panel.visible and hint.text == "E  revive    R  run again", "the death screen shows %s with the hint '%s'" % [panel.visible, hint.text])
	# The control: without moving the player a full health alone is not a revive, the puddle hits again.
	health.reset()
	await _ticks(HIT_INTERVAL_TICKS + 5)
	_expect(failures, health.health < 100, "full health again, but the player still in the wire was not hit within 35 ticks (health %d): the sentence about getting up in the puddle proves nothing" % health.health)
	await _until(func() -> bool: return health.dead, 200)
	_expect(failures, level.state == STATE_DEAD and health.dead, "the control did not kill the player again (state %d, health %d)" % [level.state, health.health])
	# E: the revive.
	await _action("revive")
	var landed := Vector2(player.global_position.x - spawn.origin.x, player.global_position.z - spawn.origin.z).length()
	_expect(failures, health.health == 100 and not health.dead and health_label.text == "Health 100", "E while dead: health %d, dead %s, the HUD says '%s'" % [health.health, health.dead, health_label.text])
	_expect(failures, landed < 0.05, "the player is %.3f m from the point %.1f m inside the entrance of room %d" % [landed, spawn_depth, room_at_death])
	_expect(failures, death_spot.distance_to(spawn.origin) > 1.0, "the player died %.2f m from where the revive puts it: the test cannot tell the move from standing still" % death_spot.distance_to(spawn.origin))
	_expect(failures, level.revives == 0 and level.current == room_at_death and level.rooms.keys() == rooms_at_death and level.keys == keys_at_death, "after the revive: revives %d, room %d (was %d), rooms %s (were %s), keys %d (were %d)" % [level.revives, level.current, room_at_death, level.rooms.keys(), rooms_at_death, level.keys, keys_at_death])
	_expect(failures, level.state == STATE_RUNNING and not player.frozen and not panel.visible and player.velocity.length() < 0.5, "after the revive: state %d (RUNNING is %d), frozen %s, death screen %s, velocity %s" % [level.state, STATE_RUNNING, player.frozen, panel.visible, player.velocity])
	_expect(failures, absf(level.run_time - time_at_death) < 0.3, "the clock is at %.2f s after the revive, it stopped at %.2f s" % [level.run_time, time_at_death])
	await _ticks(HIT_INTERVAL_TICKS * 3)
	var clock_running_on: float = level.run_time
	_expect(failures, clock_running_on > time_at_death + 1.4 and health.health == 100 and wire.inside.is_empty(), "1.5 s after the revive: clock %.2f s (stopped at %.2f), health %d, %d in the wire; the clock goes on and the player is out of the puddle" % [clock_running_on, time_at_death, health.health, wire.inside.size()])
	var revived_at := player.global_position
	Input.action_press("move_left")
	await _ticks(15)
	Input.action_release("move_left")
	var walked := Vector2(player.global_position.x - revived_at.x, player.global_position.z - revived_at.z).length()
	_expect(failures, walked > 0.5, "the revived player walked %.2f m in 15 ticks, expected it to have the controls back" % walked)
	# The second death: no revive left, E does nothing.
	health.hurt(100, "Broken Glass")
	_expect(failures, level.state == STATE_DEAD and panel.visible and hint.text == "No revive left    R  run again", "second death: state %d, death screen %s, hint '%s'" % [level.state, panel.visible, hint.text])
	var second_spot := player.global_position
	await _action("revive")
	_expect(failures, level.state == STATE_DEAD and health.health == 0 and level.revives == 0 and player.frozen and panel.visible and player.global_position.distance_to(second_spot) < 0.01, "E with no revive left: state %d, health %d, revives %d, frozen %s, moved %.3f m" % [level.state, health.health, level.revives, player.frozen, player.global_position.distance_to(second_spot)])
	_expect(failures, hint.text == "No revive left    R  run again" and (hud.get_node("DeathPanel/Rows/DeathCause") as Label).text == "Hit by Broken Glass", "the second death screen says '%s' and '%s'" % [hint.text, (hud.get_node("DeathPanel/Rows/DeathCause") as Label).text])
	# R fills the revive again.
	await _action("regenerate")
	_expect(failures, level.revives == 1 and level.state == STATE_READY and health.health == 100 and hint.text == "E  revive    R  run again", "R: revives %d, state %d, health %d, hint '%s'" % [level.revives, level.state, health.health, hint.text])
	# A death before the first door opened: the revive goes back to READY, the clock never ran.
	health.hurt(100, "Live Wire")
	_expect(failures, level.state == STATE_DEAD and level.run_time == 0.0, "a death in room 0 before the first door: state %d, clock %.2f" % [level.state, level.run_time])
	await _action("revive")
	var ready_spawn := (level.rooms[0].entrance as Marker3D).global_transform.translated_local(Vector3(0.0, 0.0, -spawn_depth))
	_expect(failures, level.state == STATE_READY and level.run_time == 0.0 and health.health == 100 and level.revives == 0 and level.keys == 0 and not player.frozen, "revive before the clock ran: state %d (READY is %d), clock %.2f, health %d, revives %d, keys %d, frozen %s" % [level.state, STATE_READY, level.run_time, health.health, level.revives, level.keys, player.frozen])
	_expect(failures, Vector2(player.global_position.x - ready_spawn.origin.x, player.global_position.z - ready_spawn.origin.z).length() < 0.05 and level.current == 0, "revive in room 0: the player is %.3f m from the entrance point" % Vector2(player.global_position.x - ready_spawn.origin.x, player.global_position.z - ready_spawn.origin.z).length())
	level.rooms[0].door.open()
	await _ticks(30)
	_expect(failures, level.state == STATE_RUNNING and level.run_time > 0.3, "the run does not go on after a revive in READY: state %d, clock %.2f" % [level.state, level.run_time])
	_note("room 3, %d keys, clock stopped at %.2f s: died %.1f m from the revive point; E gave 100 health, state RUNNING, the player %.3f m from the point %.1f m inside the entrance, keys, room and rooms unchanged, the clock at %.2f s 1.5 s later, controls back (walked %.1f m); without the move, a full health alone was hit again within 35 ticks" % [keys_at_death, time_at_death, death_spot.distance_to(spawn.origin), landed, spawn_depth, clock_running_on, walked])
	_note("the second death says 'No revive left    R  run again' and E does nothing; R gives the revive back; a revive before the clock ran goes to READY with the clock at 0; E while alive changed nothing (health stayed 60)")
	_fast_forward(false)
	await _unload(main)
	return failures

## The player dies in a hazard and stays on its list: the hazard drops a Health only when body_exited arrives, which is one physics
## step after the physics step that sees the player gone. The hazard's Timer hits every 30 ticks, so a revive on the very tick of a
## hit moves the player and then still gets the hit in that tick: without the grace of protect(), 75 health at the entrance of the room,
## where there is no hazard, not the full health the revive promises. One tick of thirty. The test presses E (calls revive()) on that tick (the Timer has less
## than 0.01 s left), and, as the control, on the tick before it (0.0167 s left); the player died 3 m inside the room in a Live Wire
## that is nowhere near the revive point.
func test_revive_is_not_hit_again() -> Array[String]:
	var failures: Array[String] = []
	var due := await _revive_on_timer_phase(-1.0, 0.01, -1.0)
	var before := await _revive_on_timer_phase(0.012, 0.02, -1.0)
	var no_grace := await _revive_on_timer_phase(-1.0, 0.01, 0.0)
	_expect(failures, due.pressed and before.pressed and due.state == STATE_READY and before.state == STATE_READY, "the revive was not pressed or did not work (states %d and %d)" % [due.state, before.state])
	_expect(failures, due.distance < 0.1 and before.distance < 0.1 and due.inside == 0 and before.inside == 0, "after the revive the player is %.2f and %.2f m from the revive point, %d and %d on the hazard's list" % [due.distance, before.distance, due.inside, before.inside])
	_expect(failures, before.after_three == 100 and before.final == 100, "E pressed one tick before the hit was due (%.4f s left): health %d three ticks later and %d a second after that, expected 100" % [before.left, before.after_three, before.final])
	_expect(failures, due.after_three == 100 and due.final == 100, "E pressed on the tick the hazard's Timer was due (%.4f s left): health %d three ticks later and %d a second after that, a hit of 25 came after the revive at the entrance, expected 100: the hazard still held the player's health on its list" % [due.left, due.after_three, due.final])
	_expect(failures, no_grace.pressed and no_grace.after_three == 75, "the control with grace 0, E on the same tick (%.4f s left): health %d three ticks later, expected 75 (the hit the grace keeps off); without it the test does not pin the tick" % [no_grace.left, no_grace.after_three])
	_note("revive on the tick the hazard's Timer had %.4f s left (its hit was due in that tick): health %d three ticks later, %d one second after that, the player %.2f m from the revive point, %d on the list" % [due.left, due.after_three, due.final, due.distance, due.inside])
	_note("the control, one tick earlier (%.4f s left): health %d three ticks later, %d one second after that" % [before.left, before.after_three, before.final])
	_note("the control with grace 0 on the due tick (%.4f s left): health %d three ticks later: the hit the grace keeps off" % [no_grace.left, no_grace.after_three])
	return failures

## Runs one level: the player 3 m inside room 0 dies in a Live Wire, then E (revive()) is pressed on the first tick the wire's Timer has
## a time left in [low, high). grace: the Health's grace for this run (below 0: the scene's own). Returns what the revive made of it.
func _revive_on_timer_phase(low: float, high: float, grace: float) -> Dictionary:
	var main := await _load_step(FINAL_STEP, true, {"goal_room": GOAL_ROOM, "chain_seed": 42})
	var level: Node3D = main.get_node("Level")
	var health: Node = level.health
	if grace >= 0.0:
		health.grace = grace
	var player: CharacterBody3D = level.player
	var entrance := (level.rooms[0] as Node3D).get("entrance") as Marker3D
	player.global_transform = entrance.global_transform.translated_local(Vector3(0.0, 0.0, -3.0))
	player.velocity = Vector3.ZERO
	var revive_point := entrance.global_transform.translated_local(Vector3(0.0, 0.0, -1.5)).origin
	_fast_forward(true)
	await _ticks(5)
	var wire := _hazard_under(level, FINAL_STEP)
	await _until(func() -> bool: return level.state == STATE_DEAD, 400)
	var left := {"value": -1.0}
	var revive_now := func() -> bool:
		var time_left: float = wire.timer.time_left
		if time_left < low or time_left >= high:
			return false
		left["value"] = time_left
		level.revive()
		return true
	var pressed := await _until(revive_now, 100)
	await _ticks(3)
	var after_three: int = health.health
	await _ticks(2 * HIT_INTERVAL_TICKS)
	var result := {pressed = pressed, state = level.state, left = left["value"], after_three = after_three, final = health.health, inside = wire.inside.size(), distance = Vector2(player.global_position.x - revive_point.x, player.global_position.z - revive_point.z).length()}
	_fast_forward(false)
	await _unload(main)
	return result

#endregion

#region Tutorial 10, carried: a number on every door

func _label_of(door: Node) -> Label3D:
	return door.get_node_or_null("Hinge/Number") as Label3D

## What the number on a door says: four digits, zeros in front (0005).
func _number_text(number: int) -> String:
	return "%04d" % number

## What a door's number should be, for the doors that are in the level now: the plan's index and one, on the door of that room.
func _door_number_problems(level: Node3D) -> Array[String]:
	var problems: Array[String] = []
	for index: int in level.rooms:
		var room: Node3D = level.rooms[index]
		var door := room.get("door") as Node3D
		if door == null:
			continue
		var label := _label_of(door)
		var plan_index: int = level.chain.plans[index].index
		if label == null or label.text != _number_text(plan_index + 1):
			problems.append("room %d: the door says \"%s\", the plan says %s" % [index, label.text if label != null else "(no label)", _number_text(plan_index + 1)])
		if door.get_parent() != room or label == null or not label.is_visible_in_tree():
			problems.append("room %d: its number is not on its own door, or is hidden" % index)
	return problems

## Opens the newest door of a level again and again until the goal room stands: every door a run makes, none walked through.
func _open_every_door(level: Node3D) -> void:
	while level.chain.plans.size() <= level.chain.goal_index:
		var newest: Node3D = level.rooms[level.chain.plans.size() - 1]
		(newest.get("door") as Node3D).call("open")

func test_numbers_of_every_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var goal_numbers := 0
	var doors := 0
	for chain_seed in range(1, NUMBER_SEEDS + 1):
		var main := await _load_step(step, false, {"goal_room": GOAL_ROOM, "chain_seed": chain_seed})
		var level: Node3D = main.get_node("Level")
		_open_every_door(level)
		var plans: Array = level.chain.plans
		_expect(failures, plans.size() == level.chain.goal_index + 1 and plans[-1].type == Chain.Type.GOAL, "seed %d: the run does not end in the goal room" % chain_seed)
		var problems := _door_number_problems(level)
		for problem in problems:
			failures.append("seed %d: %s" % [chain_seed, problem])
		var seen: Array[int] = []
		for index: int in level.rooms:
			var door := (level.rooms[index] as Node3D).get("door") as Node3D
			if index == plans.size() - 1:
				_expect(failures, door == null and (level.rooms[index] as Node3D).find_children("*", "Label3D", true, false).is_empty(), "seed %d: the goal room has a door or a number" % chain_seed)
			else:
				_expect(failures, door != null and (door.find_children("*", "Label3D", true, false)).size() == 1, "seed %d room %d: a door without exactly one number" % [chain_seed, index])
				seen.append(_label_of(door).text.to_int())
		doors += seen.size()
		seen.sort()
		_expect(failures, seen == range(1, plans.size()), "seed %d: the numbers on the doors are %s, expected 1 to %d" % [chain_seed, seen, plans.size() - 1])
		# The door into the goal says the goal's number, and every other door has a room behind it.
		var last := (level.rooms[plans.size() - 2] as Node3D).get("door") as Node3D
		_expect(failures, _label_of(last).text == _number_text(level.chain.goal_index), "seed %d: the door into the goal room says \"%s\", the goal is room %d" % [chain_seed, _label_of(last).text, level.chain.goal_index])
		goal_numbers += 1 if _label_of(last).text == _number_text(level.chain.goal_index) else 0
		await _unload(main)
		if failures.size() > 8:
			break
	_expect(failures, goal_numbers == NUMBER_SEEDS or failures.size() > 8, "the door into the goal room said the goal number in %d of %d seeds" % [goal_numbers, NUMBER_SEEDS])
	_note("%d runs of seeds 1-%d to goal room %d: %d doors, each said the plan's index plus one (as \"%s\" for room 5), the door into the goal said %s in %d runs" % [NUMBER_SEEDS, NUMBER_SEEDS, GOAL_ROOM, doors, _number_text(5), _number_text(GOAL_ROOM), goal_numbers])
	return failures

## Walking: the number on the door the player goes through is the number the HUD shows on the other side, for a whole run,
## while the rooms behind are freed.
func test_numbers_walked(step: String) -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in WALKED_SEEDS:
		var main := await _load_step(step, true, {"goal_room": GOAL_ROOM, "chain_seed": chain_seed})
		var level: Node3D = main.get_node("Level")
		var room_label := main.get_node("HUD/Stats/RoomLabel") as Label
		var state := {"current": 0, "doors": 0, "freed": 0, "most_alive": 0, "ticks": 0, "ticks_at_most": 0, "first_most": "", "wrong": [] as Array[String], "lowest": 100}
		level.health.changed.connect(func(value: int) -> void: state["lowest"] = mini(state["lowest"], value))
		var pilot := Autopilot.new(level)
		_fast_forward(true)
		var finished := await _walk_to_finish(level, pilot, 40000, func() -> void:
			var wrong: Array[String] = state["wrong"]
			if level.current != state["current"]:
				var passed := (level.rooms.get(level.current - 1) as Node3D).get("door") as Node3D
				var said := _label_of(passed).text
				if said != _number_text(level.current) or room_label.text != "Room %d / %d" % [level.current, level.chain.goal_index]:
					wrong.append("through the door that said \"%s\" the HUD says \"%s\" (room %d)" % [said, room_label.text, level.current])
				state["current"] = level.current
				state["doors"] += 1
			state["freed"] = maxi(state["freed"], level.chain.plans.size() - level.rooms.size())
			state["ticks"] += 1
			if level.rooms.size() > state["most_alive"]:
				state["most_alive"] = level.rooms.size()
				state["ticks_at_most"] = 0
				state["first_most"] = "rooms %s, the player in room %d, doors open %s" % [level.rooms.keys(), level.current, level.rooms.keys().filter(func(index: int) -> bool: return level.rooms[index].door != null and level.rooms[index].door.is_open)]
			if level.rooms.size() == state["most_alive"]:
				state["ticks_at_most"] += 1
			wrong.append_array(_door_number_problems(level).slice(0, 2)))
		_fast_forward(false)
		var wrong_here: Array[String] = state["wrong"]
		_expect(failures, finished, "seed %d: the run did not finish (state %d, room %d, health %d)" % [chain_seed, level.state, level.current, level.health.health])
		_expect(failures, wrong_here.is_empty(), "seed %d: %s" % [chain_seed, wrong_here.slice(0, 3)])
		_expect(failures, state["doors"] == level.chain.goal_index and state["freed"] >= level.chain.goal_index - 3 and state["most_alive"] <= 4, "seed %d: %d doors walked through, rooms freed up to %d, at most %d rooms alive" % [chain_seed, state["doors"], state["freed"], state["most_alive"]])
		_note("seed %d: %d doors walked through to goal room %d, each said the number the HUD showed after it; at most %d rooms alive at once (%d of %d ticks; first time: %s), %d freed; the lowest health on the way %d" % [chain_seed, state["doors"], level.chain.goal_index, state["most_alive"], state["ticks_at_most"], state["ticks"], state["first_most"], state["freed"], state["lowest"]])
		await _unload(main)
	return failures

#endregion

#region The game underneath (tutorial 10's final state, with health, hazards, death and a revive)

func _run_snapshot(level: Node3D) -> Array:
	return [level.state, level.current, level.keys, level.run_time, level.player.global_position, level.player.rotation, level.rooms.keys(), level.chain.plans.size(), level.seed_text]

## Everything the plans say, rejected rooms included; with_props: the props, too.
func _plan_summary(plans: Array, with_props := true) -> Array:
	var summary: Array = []
	for plan: Object in plans:
		var rejected: Array = []
		var turned_down: Variant = plan.get("rejected")
		if turned_down != null:
			for r: Object in turned_down:
				rejected.append([r.type, r.reason, r.transform, r.bounds, r.hit])
		summary.append([plan.index, plan.type, plan.transform, plan.bounds, plan.locked, plan.key_spot, plan.props if with_props else plan.props.size(), plan.get("lamp"), rejected])
	return summary

## One run of a seed, `ticks` long, with the autopilot. effects: the camera's head bob and FOV kick.
func _feel_run(step: String, chain_seed: int, effects: bool, ticks: int) -> Dictionary:
	var main := await _load_step(step, true, {"goal_room": 8, "chain_seed": chain_seed})
	var level: Node3D = main.get_node("Level")
	var camera := level.player.get_node("Head/Camera3D") as Camera3D
	camera.set("head_bob", effects)
	camera.set("fov_kick", effects)
	var lowest := {"value": 100}
	var health: Node = level.get("health") as Node
	if health != null:
		health.connect("changed", func(value: int) -> void: lowest["value"] = mini(lowest["value"], value))
	await _wait_physics(30)
	var pilot := Autopilot.new(level)
	var snapshots: Array = []
	var state := {"ticks": 0, "dip": 0.0, "widest": camera.fov}
	_fast_forward(true)
	await _drive(func() -> bool:
		pilot.physics_step()
		state["ticks"] += 1
		state["dip"] = maxf(state["dip"], -camera.position.y)
		state["widest"] = maxf(state["widest"], camera.fov)
		if state["ticks"] % 30 == 0:
			snapshots.append(_run_snapshot(level) + [(level.player.get_node("Head") as Node3D).transform])
		return state["ticks"] >= ticks or level.state == STATE_FINISHED)
	pilot.release()
	_fast_forward(false)
	snapshots.append(_run_snapshot(level) + [(level.player.get_node("Head") as Node3D).transform])
	var feet: Node = level.player.get_node_or_null("Footsteps")
	var result := {snapshots = snapshots, plans = _plan_summary(level.chain.plans, false), dip = state["dip"], widest = state["widest"], steps = feet.get("steps") if feet != null else 0, lowest = lowest["value"]}
	await _unload(main)
	return result

## Health, a hazard, a death and a revive are for the run's rules and the eye, not for the walking: the same inputs give the
## same run, tick for tick, in step 0 (no health) and in every later step, with the camera effects on and off (positions,
## rotations, the head, rooms, keys, time, the plans without their props). No hit comes in these runs, so no step ends one.
func test_effects_change_no_movement() -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in MOVEMENT_SEEDS:
		var start := await _feel_run(STEPS[0], chain_seed, true, 900)
		_expect(failures, start.dip > 0.01 and start.widest > REST_FOV + 1.0 and start.steps > 10, "seed %d: the effects did not run (dip %.3f m, widest %.2f degrees, %d steps): the comparison would prove nothing" % [chain_seed, start.dip, start.widest, start.steps])
		var lowest := 100
		for step: String in STEPS.slice(1):
			var on := await _feel_run(step, chain_seed, true, 900)
			lowest = mini(lowest, on.lowest)
			_expect(failures, on.snapshots == start.snapshots, "seed %d: the run of %s differs from step 0's" % [chain_seed, step])
			_expect(failures, on.plans == start.plans, "seed %d: the plans of %s differ from step 0's" % [chain_seed, step])
		var off := await _feel_run(FINAL_STEP, chain_seed, false, 900)
		_expect(failures, off.dip == 0.0 and off.widest == REST_FOV, "seed %d: with the effects off the camera still moved (dip %.3f m, widest %.2f)" % [chain_seed, off.dip, off.widest])
		_expect(failures, off.snapshots == start.snapshots, "seed %d: the run of the finished step with the effects off differs from step 0's" % chain_seed)
		_expect(failures, off.plans == start.plans, "seed %d: the plans with the effects off differ" % chain_seed)
		_note("seed %d: %d snapshots (every 30 ticks of 900) equal in step 0 and in steps 1 to 4, with the camera effects on and off (dip %.3f m, widest %.2f degrees, %d steps), the player in room %d; the lowest health in steps 1 to 4: %d" % [chain_seed, start.snapshots.size(), start.dip, start.widest, start.steps, start.snapshots[-1][1], lowest])
	return failures

#endregion

#region The game underneath (tutorial 10's final state)

## Room 2 entered: the door of room 1 starts to close behind the player, room 0 is the oldest room.
func _door_closing_behind_room_2(step: String) -> Node:
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	level.rooms[0].door.open() # builds room 1
	level._on_room_entered(level.player, 1)
	await _wait_physics(45)
	level.rooms[1].door.open() # builds room 2
	await _wait_physics(45)
	level._on_room_entered(level.player, 2)
	return main

## Through the door behind the player the picture goes along the room just left, to the doorway of the one before it.
func test_rooms_wait_for_the_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _door_closing_behind_room_2(step)
	var level: Node3D = main.get_node("Level")
	_expect(failures, level.rooms.has(0), "room 0 went while the door behind the player stood open")
	await _wait_physics(45)
	_expect(failures, not level.rooms.has(0), "room 0 is still there behind the shut door")
	_expect(failures, level.rooms.has(1), "the room just left went with room 0")
	_expect(failures, not level.rooms[1].get_node("Shell/WallEntrance/Opening").visible, "the room just left has no wall at its entrance")
	await _unload(main)
	main = await _door_closing_behind_room_2(step)
	level = main.get_node("Level")
	await _wait_physics(10)
	level.rooms[1].door.open() # the player turned around while the leaf still swings
	await _wait_physics(45)
	_expect(failures, level.rooms.has(0), "room 0 went while the door stood open again")
	level.start()
	if level.has_method("_on_door_closed"):
		level._on_door_closed(2) # a restart is faster than the door of the old run
		_expect(failures, level.rooms.has(0), "the door of the old run took room 0 of the new one")
	else:
		_expect(failures, false, "level.gd has no _on_door_closed")
	await _unload(main)
	return failures

func test_full_run() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var room_label := main.get_node("HUD/Stats/RoomLabel") as Label
	var lowest := {"value": 100}
	level.health.changed.connect(func(value: int) -> void: lowest["value"] = mini(lowest["value"], value))
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var finished := await _walk_to_finish(level, pilot, 60 * 60 * 5, Callable())
	_fast_forward(false)
	_expect(failures, finished, "the run did not finish (room %d, %.1f s, state %d, health %d)" % [level.current, level.run_time, level.state, level.health.health])
	_expect(failures, level.current == GOAL_ROOM, "finished in room %d" % level.current)
	_expect(failures, room_label.text == "Room %d / %d" % [GOAL_ROOM, GOAL_ROOM], "the HUD says '%s' in the goal room" % room_label.text)
	_expect(failures, level.run_time > 30.0 and level.run_time < 150.0, "the run took %.1f s" % level.run_time)
	_note("full run, seed 42: finished in room %d, %.2f s of game time, %d rooms made, %d alive at the end; the lowest health on the way %d, %d revives left" % [level.current, level.run_time, level.chain.plans.size(), level.rooms.size(), lowest["value"], level.revives])
	await _unload(main)
	return failures

func _state(player: CharacterBody3D) -> String:
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	return (tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).get_current_node()

func test_restart() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	level.health.hurt(35, "Test")
	Input.action_press("move_forward")
	await _wait_physics(30)
	Input.action_release("move_forward")
	await _action("regenerate")
	await _wait_physics(40)
	_expect(failures, player.global_position.distance_to(Vector3(0.0, 0.0, 3.5)) < 0.05, "the player is at %s" % player.global_position)
	_expect(failures, _state(player) == "Move", "the tree is in %s" % _state(player))
	_expect(failures, is_zero_approx(tree.get("parameters/Move/blend_position")), "blend position %.2f" % tree.get("parameters/Move/blend_position"))
	_expect(failures, level.health.health == 100 and level.state == STATE_READY, "R left %d health in state %d" % [level.health.health, level.state])
	await _unload(main)
	return failures

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

## The autopilot walks the finished game from the first door to the goal for seeds 1-200. It has no eyes and never steers around
## anything, so a place where the player can be held for good shows up as a run that stops moving (this is how the end of the open
## door leaf was found once), and a hazard on its way as a hit or a death. A run is about 3600 physics ticks, so the seeds are split
## over SWEEP_WORKERS processes (tools/sweep_seeds.gd), each at 8 times real time (the engine's limit of 8 physics steps per
## frame; faster, Jolt warns about running out of jobs). A seed walks the same way in any of them. Every door the run goes through
## says the number the HUD shows after it.
func test_autopilot_seed_sweep() -> Array[String]:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var per_worker := ceili(float(SWEEP_SEEDS) / SWEEP_WORKERS)
	var workers: Array[Dictionary] = []
	for index in SWEEP_WORKERS:
		var first := index * per_worker + 1
		var last := mini(first + per_worker - 1, SWEEP_SEEDS)
		if first > last:
			continue
		var out := _save_dir.path_join("sweep_%d.txt" % index)
		DirAccess.remove_absolute(out)
		var arguments := ["--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/sweep_seeds.gd", "--", "--from=%d" % first, "--to=%d" % last, "--out=%s" % out]
		var pid := OS.create_process(OS.get_executable_path(), arguments)
		_expect(failures, pid > 0, "could not start the sweep for seeds %d-%d" % [first, last])
		workers.append({"pid": pid, "out": out, "first": first, "last": last})
	while workers.any(func(worker: Dictionary) -> bool: return worker["pid"] > 0 and OS.is_process_running(worker["pid"])):
		await create_timer(1.0).timeout
	var held: Array[String] = []
	var dead: Array[String] = []
	var wrong: Array[String] = []
	var hit_lines: Array[String] = []
	var walked := 0
	var doors := 0
	var longest := 0
	var hits := 0
	var seeds_hit := 0
	for worker in workers:
		var text := FileAccess.get_file_as_string(worker["out"])
		var lines := text.strip_edges().split("\n", false)
		_expect(failures, lines.size() > 0 and lines[-1] == "done", "the sweep for seeds %d-%d did not finish (%d lines in %s)" % [worker["first"], worker["last"], lines.size(), worker["out"]])
		for line in lines:
			var parts := line.split(" ")
			if parts[0] == "ok":
				walked += 1
				longest = maxi(longest, int(parts[2]))
				doors += int(parts[3])
				hits += int(parts[4])
				seeds_hit += 1 if int(parts[4]) > 0 else 0
			elif parts[0] == "numbers":
				wrong.append("seed %s, room %s: %s" % [parts[1], parts[2], " ".join(parts.slice(3))])
			elif parts[0] == "hit":
				hit_lines.append("seed %s room %s health %s" % [parts[1], parts[2], parts[3]])
			elif parts[0] == "died":
				walked += 1
				hits += int(parts[4])
				seeds_hit += 1
				dead.append("seed %s: died in room %s of %s after %s ticks (%s hits)" % [parts[1], parts[2], " ".join(parts.slice(5)), parts[3], parts[4]])
			elif parts[0] == "held":
				walked += 1
				hits += int(parts[4])
				held.append("seed %s: held in room %s at %s after %s ticks" % [parts[1], parts[2], " ".join(parts.slice(5)), parts[3]])
		DirAccess.remove_absolute(worker["out"])
	_expect(failures, walked == SWEEP_SEEDS, "%d of %d seeds were walked" % [walked, SWEEP_SEEDS])
	_expect(failures, dead.is_empty(), "%d of %d runs ended in death: %s" % [dead.size(), SWEEP_SEEDS, dead.slice(0, 4)])
	_expect(failures, held.is_empty(), "%d of %d seeds did not reach the goal: %s" % [held.size(), SWEEP_SEEDS, held.slice(0, 4)])
	_expect(failures, wrong.is_empty(), "%d doors said a number other than the plan's or the HUD's: %s" % [wrong.size(), wrong.slice(0, 4)])
	_expect(failures, doors == (SWEEP_SEEDS - dead.size() - held.size()) * GOAL_ROOM, "%d doors were gone through in %d finished runs, expected %d: the number check does not cover every door" % [doors, SWEEP_SEEDS - dead.size() - held.size(), (SWEEP_SEEDS - dead.size() - held.size()) * GOAL_ROOM])
	_note("seeds 1-%d to goal room %d: %d of %d runs reached the goal (the longest took %d ticks, %.1f s of game time); the autopilot took %d hits in all, in %d runs (%s); %d died; %d doors gone through, each said the number the HUD showed after it; %d wrong" % [SWEEP_SEEDS, GOAL_ROOM, walked - held.size() - dead.size(), SWEEP_SEEDS, longest, longest / 60.0, hits, seeds_hit, "none" if hit_lines.is_empty() else "; ".join(hit_lines.slice(0, 6)), dead.size(), doors, wrong.size()])
	return failures

#endregion

#region Harness

func _run(test_name: String, test: Callable) -> void:
	if not _selected(test_name):
		return
	await process_frame # the engine empties its message queue between tests: the chain tests build thousands of room scenes
	_notes.clear()
	_skipped_whole = false
	var failures: Array[String] = await test.call()
	_report(test_name, failures)

func _selected(test_name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only=") and not test_name.contains(argument.trim_prefix("--only=")):
			return false
	return true

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty() and _skipped_whole:
		return
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		for note in _notes:
			print("        ", note)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))
	for note in _notes:
		print("        (measured) ", note)

## whole: the test stops here, so it is neither a pass nor a fail; false: the rest of the test ran and passes.
func _skip(test_name: String, reason: String, whole := true) -> void:
	_skipped += 1
	_skipped_whole = _skipped_whole or whole
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## A figure the running test measured: printed under its PASS line, for the plan's "Measured" and the voice.
func _note(text: String) -> void:
	_notes.append(text)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
## props are set on the Level before it enters the tree (goal_room, seed_text, lock_chance ...; "chain_seed" is the
## text of the seed's digits). "settings_path" is the file of the settings box.
## Every level gets a fresh temporary save file unless props bring one, and so does the settings box.
func _load_step(step: String, settle := true, props := {}) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	var level := main.get_node("Level")
	if not props.has("save_path"):
		level.set("save_path", _fresh_save_path())
	for key: String in props:
		if key == "settings_path":
			continue
		if key == "chain_seed":
			level.set("seed_text", str(props[key]))
		else:
			level.set(key, props[key])
	var menu := main.get_node_or_null("HUD/Settings")
	if menu != null: # the settings box reads and writes a file of its own
		menu.set("save_path", props.get("settings_path", _fresh_settings_path()))
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "jump", "walk"]:
		Input.action_release(action)
	for sound: Node in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.call("stop") # a sound that still plays when its player is freed is reported as leaked at exit (Godot issue 76745)
	root.remove_child(main)
	main.free()
	await process_frame

## A path in the temporary test folder that no file exists at.
func _fresh_save_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("best_times_%d.json" % _save_counter)

func _fresh_settings_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("settings_%d.json" % _save_counter)

func _wipe_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		return
	for file in DirAccess.get_files_at(_save_dir):
		DirAccess.remove_absolute(_save_dir.path_join(file))
	DirAccess.remove_absolute(_save_dir)

## Runs the simulation faster than real time with the same 1/60 s steps: the engine ticks
## SPEED_UP times as often and hands out SPEED_UP times the delta of each (smaller) tick.
func _fast_forward(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEED_UP if on else 1)
	Engine.time_scale = float(SPEED_UP) if on else 1.0

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

## Presses an action once, as a key would, and lets it go again.
func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame
	Input.action_release(action)

## The names of an action's keyboard keys ("F3"), by physical key.
func _physical_keys(action: StringName) -> Array[String]:
	var keys: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
	return keys

#endregion
