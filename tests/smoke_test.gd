extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
enum GameMode { MENU, BRIEFING, PLAYING, PAUSED, INTERMISSION, WON, LOST }

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> bool:
	if not condition:
		push_error("FAIL: " + label)
		quit(1)
		return false
	print("PASS: " + label)
	return true

func _run() -> void:
	var game: Node3D = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	if not _expect(game.mode == GameMode.MENU, "3D project opens at campaign menu"):
		return
	if not _expect(game.player is CharacterBody3D and game.camera is Camera3D, "pilot and follow camera use native 3D nodes"):
		return
	if not _expect(game.ship.get_child_count() >= 6, "ship is built from multiple 3D meshes"):
		return
	game._primary()
	if not _expect(game.mode == GameMode.BRIEFING, "campaign begins with story briefing"):
		return
	game._primary()
	if not _expect(game.mode == GameMode.PLAYING and game.lives == 3, "mission starts with three hull points"):
		return

	game.enemies.clear()
	game.invulnerability = 0.0
	var enemy := Area3D.new()
	enemy.position = game.player.position
	game.arena.add_child(enemy)
	game.enemies.append({"node": enemy, "speed": 0.0})
	game._update_enemies(0.0)
	if not _expect(game.lives == 2 and game.invulnerability > 1.0, "real enemy update applies collision damage"):
		return
	game._update_enemies(0.0)
	if not _expect(game.lives == 2, "invulnerability blocks repeat collision damage"):
		return

	game.enemies.clear()
	var old_position: Vector3 = game.player.position
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	game._unhandled_input(key)
	game._physics_process(0.12)
	key.pressed = false
	game._unhandled_input(key)
	if not _expect(game.player.position.x > old_position.x, "keyboard input pilots the 3D ship"):
		return

	game.pressed[KEY_SPACE] = true
	game._process(0.016)
	if not _expect(game.dash_remaining > 0.0 and game.dash_cooldown > 1.0, "space activates dash and cooldown"):
		return
	game.pressed[KEY_SPACE] = false

	game._show(GameMode.PAUSED)
	if not _expect(game.mode == GameMode.PAUSED, "pause overlay freezes the game state"):
		return
	game._primary()
	if not _expect(game.mode == GameMode.PLAYING, "pause overlay resumes the game"):
		return

	for mission in range(15):
		if mission > 0:
			game.mission_index = mission
			game._start_mission()
		game.enemies.clear()
		game.objective_progress = game.objective_goal
		game.gate_active = true
		game.player.position = game.gate.position
		game._physics_process(0.016)
		if not _expect(game.mode == GameMode.INTERMISSION, "mission %02d can complete through the exit gate" % (mission + 1)):
			return
		if mission < 14:
			game._primary()
			if not _expect(game.mode == GameMode.BRIEFING, "mission %02d advances to story briefing" % (mission + 1)):
				return
	game._primary()
	if not _expect(game.mode == GameMode.WON, "fifteen missions reach the campaign ending"):
		return
	if not _expect(game.module_rank == 4, "four chapter clears unlock four ship modules"):
		return
	var save_check := ConfigFile.new()
	if not _expect(save_check.load(game.SAVE_PATH) == OK and int(save_check.get_value("campaign", "module_rank", -1)) == 4, "ship module upgrades persist in the campaign save"):
		return

	game._show(GameMode.PLAYING)
	game.lives = 1
	game.invulnerability = 0.0
	game._take_hit()
	if not _expect(game.mode == GameMode.LOST, "zero hull enters checkpoint retry state"):
		return
	game._primary()
	if not _expect(game.mode == GameMode.PLAYING and game.lives == 3, "retry restores the current mission"):
		return

	print("All Lumen Drift 3D campaign smoke checks passed.")
	quit(0)
