extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
enum GameMode { MENU, PLAYING, PAUSED, SECTOR_CLEAR, WON, LOST }


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> bool:
	if not condition:
		push_error("FAIL: " + label)
		quit(1)
		return false
	print("PASS: " + label)
	return true


func _key(key_code: int, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key_code
	event.physical_keycode = key_code
	event.pressed = down
	return event


func _run() -> void:
	var game: Variant = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	if not _expect(game.mode == GameMode.MENU, "native project opens on its main menu"):
		return

	game.start_run()
	game.enemies.clear()
	if not _expect(game.mode == GameMode.PLAYING and game.lives == 3 and game.cores.size() == 6, "new run initializes lives, cores, and play state"):
		return
	game.player_invulnerable = 0.0
	game.enemies.append({"position": game.player_position, "kind": "hunter", "radius": 12.0, "speed": 40.0, "phase": 0.0})
	game._process(0.016)
	if not _expect(game.lives == 2 and game.player_invulnerable > 1.0, "enemy collision removes one life and grants recovery time"):
		return
	game.enemies.clear()
	game.player_velocity = Vector2.ZERO

	var start_x: float = game.player_position.x
	game._input(_key(KEY_D, true))
	game._process(0.05)
	game._input(_key(KEY_D, false))
	if not _expect(game.player_position.x > start_x, "keyboard movement changes player position"):
		return

	game._input(_key(KEY_SPACE, true))
	game._process(0.016)
	game._input(_key(KEY_SPACE, false))
	if not _expect(game.dash_cooldown > 1.0 and game.dash_remaining > 0.0, "dash activates with a visible cooldown window"):
		return

	game._input(_key(KEY_ESCAPE, true))
	game._input(_key(KEY_ESCAPE, false))
	if not _expect(game.mode == GameMode.PAUSED, "Escape pauses the native game"):
		return
	game._input(_key(KEY_ESCAPE, true))
	game._input(_key(KEY_ESCAPE, false))
	if not _expect(game.mode == GameMode.PLAYING, "Escape resumes the native game"):
		return
	game._input(_key(KEY_ESCAPE, true))
	game._input(_key(KEY_ESCAPE, false))
	game._handle_click(Vector2(400.0, 420.0))
	if not _expect(game.mode == GameMode.PLAYING and game.lives == 3 and game.score == 0, "pause menu restart resets the run"):
		return
	game.enemies.clear()

	game.player_position = game.portal_position
	game.player_velocity = Vector2.ZERO
	game._process(0.016)
	if not _expect(game.mode == GameMode.PLAYING, "inactive portal cannot skip the core objective"):
		return

	for target_sector in range(5):
		game.enemies.clear()
		for core_position in game.cores.duplicate():
			game.player_position = core_position
			game.player_velocity = Vector2.ZERO
			game._process(0.001)
		if not _expect(game.cores_collected == 6, "sector %d collects every core" % (target_sector + 1)):
			return
		game.player_position = game.portal_position
		game.player_velocity = Vector2.ZERO
		game._process(0.001)
		var expected_mode: int = GameMode.WON if target_sector == 4 else GameMode.SECTOR_CLEAR
		if not _expect(game.mode == expected_mode, "sector %d portal transition" % (target_sector + 1)):
			return
		if target_sector < 4:
			game._activate_primary()
			if not _expect(game.mode == GameMode.PLAYING and game.sector == target_sector + 1, "continue enters sector %d" % (target_sector + 2)):
				return

	if not _expect(game.best_score == game.score and game.score > 0, "victory records the completed run"):
		return

	game.start_run()
	game.enemies.clear()
	for hit in range(3):
		game.player_invulnerable = 0.0
		game.take_hit()
	if not _expect(game.mode == GameMode.LOST and game.lives == 0, "three collisions reach the loss screen"):
		return
	game._activate_primary()
	if not _expect(game.mode == GameMode.PLAYING and game.lives == 3 and game.sector == 0, "retry starts a clean run"):
		return

	game._input(_key(KEY_ESCAPE, true))
	game._input(_key(KEY_ESCAPE, false))
	game._handle_click(Vector2(380.0, 462.0))
	if not _expect(game.mode == GameMode.MENU, "pause menu returns to the title screen"):
		return
	print("All Lumen Drift native smoke checks passed.")
	quit(0)

