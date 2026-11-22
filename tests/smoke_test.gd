extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
enum GameMode { MENU, BRIEFING, PLAYING, PAUSED, INTERMISSION, WON, LOST, JOURNAL, UPGRADES }

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> bool:
	if not condition:
		push_error("FAIL: " + label)
		quit(1)
		return false
	print("PASS: " + label)
	return true

func _press(game, code: int) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	game._unhandled_input(key)
	game._process(0.016)
	key.pressed = false
	game._unhandled_input(key)

func _exit_sector(game) -> void:
	game.player.position = game.gate.position
	game.player.velocity = Vector3.ZERO
	game._physics_process(0.016)

func _run() -> void:
	var game: Variant = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	if not _expect(game.mode == GameMode.MENU, "3D project opens at campaign menu"):
		return
	if not _expect(game.player is CharacterBody3D and game.camera is Camera3D, "pilot and follow camera use native 3D nodes"):
		return
	if not _expect(game.ship.get_node_or_null("Hull") is Node3D and game.ship.find_children("*", "MeshInstance3D", true, false).size() >= 3, "ship loads its GLB hull and separate exhaust geometry"):
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

	game.dash_remaining = 0.0
	game.pressed.clear()
	game.player.velocity = Vector3.ZERO
	var first_relay: Area3D = game.targets[0]
	game.player.position = first_relay.position
	_press(game, KEY_F)
	if not _expect(game.objective_progress == 0 and not first_relay.get_meta("scanned", false), "an unscanned relay cannot be activated"):
		return
	_press(game, KEY_Q)
	if not _expect(first_relay.get_meta("scanned", false) and first_relay.get_node("RelayMarker").visible, "Q detects a nearby relay"):
		return
	for item: Area3D in game.expedition.cargo.duplicate():
		game.player.position = item.position
		game._physics_process(0.016)
	if not _expect(game.expedition.alloy == 5 and game.expedition.cells == 4, "contact collects alloy and energy cells"):
		return
	_press(game, KEY_R)
	if not _expect(game.lives == 3 and game.expedition.alloy == 4, "repair uses one alloy and restores hull"):
		return
	game.player.position = Vector3.ZERO
	_press(game, KEY_U)
	_press(game, KEY_1)
	if not _expect(game.mode == GameMode.UPGRADES and game.lives == 4 and game.expedition.alloy == 1, "workshop buys and applies hull module"):
		return
	_press(game, KEY_U)

	for target: Area3D in game.targets.duplicate():
		game.player.position = target.position
		_press(game, KEY_Q)
		_press(game, KEY_F)
		if not _expect(target.get_meta("power", 0) == 1 and is_instance_valid(game.expedition.relay) == false, "energy powers relay before tuning"):
			return
		_press(game, KEY_F)
		var relay_origin := target.position
		game.player.position = Vector3.ZERO
		game._physics_process(0.2)
		if not _expect(is_equal_approx(game.expedition.uplink_time, 2.0), "relay pauses when the player leaves transmission radius"):
			return
		game.player.position = relay_origin
		for i in range(12):
			game._physics_process(0.2)
	if not _expect(game.gate_active and game.expedition.cells == 1, "three completed transmissions consume three cells and open the route"):
		return
	_exit_sector(game)
	if not _expect(game.mode == GameMode.INTERMISSION and game.expedition.alloy == 3, "first sector exit awards alloy and saves checkpoint"):
		return
	game._primary()
	game._primary()

	game.enemies.clear()
	for core: Area3D in game.cores.duplicate():
		game.player.position = core.position
		game._physics_process(0.016)
	if not _expect(game.gate_active and game.expedition.archive.size() == 6, "recovering all crew crystals opens the exit and stores six entries"):
		return
	_press(game, KEY_J)
	if not _expect(game.mode == GameMode.JOURNAL and game.ui_text.text.contains("ЗАПИСЬ 1/6"), "J opens the recovered journal"):
		return
	_press(game, KEY_RIGHT)
	if not _expect(game.ui_text.text.contains("ЗАПИСЬ 2/6"), "journal can turn to another recovered entry"):
		return
	_press(game, KEY_J)
	_exit_sector(game)
	if not _expect(game.mode == GameMode.INTERMISSION, "memory mission exits into intermission"):
		return

	game.free()
	game = GAME_SCENE.instantiate()
	root.add_child(game)
	if not _expect(game.mission_index == 2 and game.expedition.modules[0] == 1 and game.expedition.archive.size() == 6 and game.expedition.alloy == 5 and game.expedition.cells == 1, "reopening game restores checkpoint, module, logs and resources"):
		return
	game._primary()
	game._primary()
	var hunter: Dictionary = game.enemies[0]
	var wisp: Dictionary = game.enemies[1]
	hunter["node"].position = Vector3(0, 0.5, -7)
	game._update_enemies(1.4)
	if not _expect(hunter["windup"] > 0 and hunter["node"].get_node("Threat").text == "ЗАЛП!", "Hunter warns before firing"):
		return
	game._update_enemies(0.7)
	if not _expect(not game.expedition.shots.is_empty() and not game.expedition.shots[0]["jam"], "Hunter fires a projectile after the warning"):
		return
	_press(game, KEY_SPACE)
	if not _expect(game.invulnerability > 0.0 and game.dash_remaining > 0.0, "dash grants a short dodge window"):
		return
	game.dash_remaining = 0.0
	game.player.position = Vector3(0, 0, 6)
	wisp["node"].position = Vector3(4, 0.5, -3)
	game._update_enemies(2.1)
	game._update_enemies(0.85)
	var saw_jammer := false
	for shot: Dictionary in game.expedition.shots:
		saw_jammer = saw_jammer or shot["jam"]
	if not _expect(saw_jammer, "Wisp deploys a delayed interference field"):
		return
	game.player.position = Vector3.ZERO
	for record in [hunter, wisp]:
		var before: int = record["hp"]
		for i in range(before):
			record["node"].position = Vector3(0, 0.5, -5)
			game.ship.rotation.y = 0.0
			game.pressed[KEY_CTRL] = true
			game._physics_process(0.016)
			game.pressed[KEY_CTRL] = false
			if not _expect(record["hp"] == before - i - 1, "pulse cannon damages a drone along the aiming line"):
				return
			game.player.position = Vector3.ZERO
			for frame in range(4):
				game._physics_process(0.125)
	if not _expect(game.enemies.is_empty() and game.expedition.threats == 2, "combat destroys Hunter and Wisp"):
		return
	game.player.position = game.targets[0].position
	game.player.velocity = Vector3.ZERO
	_press(game, KEY_F)
	for i in range(50):
		game._physics_process(0.2)
	if not _expect(game.gate_active, "Orion transmits once both combat threats are gone (%.2f s, jam %.2f)" % [game.expedition.uplink_time, game.expedition.jam_time]):
		return
	_exit_sector(game)
	if not _expect(game.mode == GameMode.INTERMISSION, "leaving Orion completes Silent Edge"):
		return

	game._primary()
	for mission in range(3, 15):
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
	if not _expect(game.mode == GameMode.PLAYING and game.lives == game.expedition.hull(), "retry restores the current mission"):
		return

	print("All Lumen Drift 3D campaign smoke checks passed.")
	game.queue_free()
	await process_frame
	quit(0)
