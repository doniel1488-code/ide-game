extends Node2D

const WORLD := Vector2(960.0, 600.0)
const BORDER := Rect2(30.0, 52.0, 900.0, 518.0)
const PLAYER_RADIUS := 11.0
const CORE_RADIUS := 8.0
const CORE_GOAL := 6
const SECTOR_COUNT := 5
const PLAYER_SPEED := 188.0
const DASH_SPEED := 650.0
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 1.15

enum Mode { MENU, PLAYING, PAUSED, SECTOR_CLEAR, WON, LOST }

var mode := Mode.MENU
var sector := 0
var score := 0
var best_score := 0
var lives := 3
var cores_collected := 0
var elapsed := 0.0
var player_position := WORLD / 2.0
var player_velocity := Vector2.ZERO
var player_facing := Vector2.RIGHT
var player_invulnerable := 0.0
var dash_remaining := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT
var dash_requested := false
var portal_position := Vector2(872.0, 311.0)
var cores: Array[Vector2] = []
var enemies: Array[Dictionary] = []
var walls: Array[Rect2] = []
var stars: Array[Vector4] = []
var particles: Array[Dictionary] = []
var pressed_keys: Dictionary = {}
var rng := RandomNumberGenerator.new()
var show_help := false
var sound_enabled := false
var hit_flash := 0.0
var screen_shake := 0.0
var toast := ""
var toast_remaining := 0.0
var sound_player: AudioStreamPlayer
var sound_playback: AudioStreamGeneratorPlayback
var tone_frequency := 0.0
var tone_duration := 0.0
var tone_remaining := 0.0
var tone_phase := 0.0

const INK := Color("#eaf4f1")
const MUTED := Color("#84999b")
const CYAN := Color("#8ce6d1")
const PALE := Color("#baf6e8")
const RED := Color("#f49a89")
const PURPLE := Color("#c59af1")
const DEEP := Color("#071018")


func _ready() -> void:
	rng.randomize()
	_display_setup()
	_load_record()
	for index in range(120):
		stars.append(Vector4(rng.randf_range(0.0, WORLD.x), rng.randf_range(0.0, WORLD.y), rng.randf_range(0.4, 1.8), rng.randf_range(0.1, 1.0)))
	_setup_audio()
	set_process(true)
	queue_redraw()


func _display_setup() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Lumen Drift — Сигнал сквозь тьму")
		DisplayServer.window_set_min_size(Vector2i(960, 600))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _setup_audio() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.25
	sound_player = AudioStreamPlayer.new()
	sound_player.stream = generator
	add_child(sound_player)
	sound_player.play()
	sound_playback = sound_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.PLAYING:
		_set_mode(Mode.PAUSED)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE:
				_toggle_pause()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				_activate_primary()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_SPACE:
				if mode == Mode.MENU or mode == Mode.SECTOR_CLEAR or mode == Mode.WON or mode == Mode.LOST:
					_activate_primary()
				else:
					dash_requested = true
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_M or key_event.physical_keycode == KEY_M:
				sound_enabled = not sound_enabled
				if sound_enabled:
					_play_tone(660.0, 0.09)
				get_viewport().set_input_as_handled()
				queue_redraw()
				return
			if key_event.keycode == KEY_I and mode == Mode.MENU:
				show_help = not show_help
				queue_redraw()
				return
		var physical := key_event.physical_keycode
		if physical != 0:
			pressed_keys[physical] = key_event.pressed
		if key_event.keycode != 0:
			pressed_keys[key_event.keycode] = key_event.pressed
		if not key_event.pressed:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_click(mouse_event.position)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	elapsed += dt
	hit_flash = maxf(0.0, hit_flash - dt)
	screen_shake = maxf(0.0, screen_shake - dt)
	if toast_remaining > 0.0:
		toast_remaining -= dt
		if toast_remaining <= 0.0:
			toast = ""
	if mode == Mode.PLAYING:
		_update_play(dt)
	_fill_audio_buffer()
	queue_redraw()


func _update_play(delta: float) -> void:
	player_invulnerable = maxf(0.0, player_invulnerable - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	dash_remaining = maxf(0.0, dash_remaining - delta)
	var direction := _movement_direction()
	if direction != Vector2.ZERO:
		player_facing = direction
	if dash_requested:
		dash_requested = false
		var requested_direction := direction if direction != Vector2.ZERO else player_facing
		if dash_cooldown <= 0.0:
			dash_direction = requested_direction
			player_velocity = requested_direction * DASH_SPEED
			dash_remaining = DASH_DURATION
			dash_cooldown = DASH_COOLDOWN
			player_invulnerable = maxf(player_invulnerable, 0.28)
			_emit_particles(player_position, CYAN, 10, 90.0)
			_play_tone(590.0, 0.11)
	if dash_remaining > 0.0:
		player_position = _move_body(player_position, dash_direction * DASH_SPEED * delta, PLAYER_RADIUS)
	else:
		var target_velocity := direction * PLAYER_SPEED
		player_velocity = player_velocity.move_toward(target_velocity, 1250.0 * delta)
		player_position = _move_body(player_position, player_velocity * delta, PLAYER_RADIUS)
	_update_cores()
	if mode != Mode.PLAYING:
		return
	_update_enemies(delta)
	if mode != Mode.PLAYING:
		return
	_update_particles(delta)
	if cores_collected >= CORE_GOAL and player_position.distance_to(portal_position) < PLAYER_RADIUS + 27.0:
		_enter_portal()


func _movement_direction() -> Vector2:
	var horizontal := float(_is_key_down(KEY_D) or _is_key_down(KEY_RIGHT)) - float(_is_key_down(KEY_A) or _is_key_down(KEY_LEFT))
	var vertical := float(_is_key_down(KEY_S) or _is_key_down(KEY_DOWN)) - float(_is_key_down(KEY_W) or _is_key_down(KEY_UP))
	return Vector2(horizontal, vertical).normalized()


func _is_key_down(key_code: int) -> bool:
	return bool(pressed_keys.get(key_code, false))


func _move_body(position: Vector2, movement: Vector2, radius: float) -> Vector2:
	var result := position
	var candidate := Vector2(position.x + movement.x, position.y)
	if candidate.x - radius >= BORDER.position.x and candidate.x + radius <= BORDER.end.x and not _touches_wall(candidate, radius):
		result.x = candidate.x
	candidate = Vector2(result.x, position.y + movement.y)
	if candidate.y - radius >= BORDER.position.y and candidate.y + radius <= BORDER.end.y and not _touches_wall(candidate, radius):
		result.y = candidate.y
	return result


func _touches_wall(position: Vector2, radius: float) -> bool:
	for wall in walls:
		var nearest := Vector2(clampf(position.x, wall.position.x, wall.end.x), clampf(position.y, wall.position.y, wall.end.y))
		if position.distance_squared_to(nearest) < radius * radius:
			return true
	return false


func _update_cores() -> void:
	for index in range(cores.size() - 1, -1, -1):
		if player_position.distance_to(cores[index]) <= PLAYER_RADIUS + CORE_RADIUS + 3.0:
			var collected_position: Vector2 = cores.pop_at(index)
			cores_collected += 1
			score += 100
			_emit_particles(collected_position, CYAN, 16, 110.0)
			_play_tone(470.0 + float(cores_collected) * 38.0, 0.11)
			if cores_collected == CORE_GOAL:
				_show_toast("ВСЕ ЯДРА СОБРАНЫ · ПОРТАЛ АКТИВЕН")
				_play_tone(830.0, 0.2)


func _update_enemies(delta: float) -> void:
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var position: Vector2 = enemy["position"]
		var speed: float = enemy["speed"]
		var movement := Vector2.ZERO
		if enemy["kind"] == "wisp":
			enemy["phase"] = float(enemy["phase"]) + delta
			movement = Vector2(cos(float(enemy["phase"]) * 1.3), sin(float(enemy["phase"]) * 1.8)) * speed * 0.42 * delta
		else:
			var to_player := player_position - position
			var distance := maxf(to_player.length(), 0.001)
			var chase_speed := speed if distance > 240.0 else speed * 0.78
			enemy["phase"] = float(enemy["phase"]) + delta
			movement = to_player / distance * chase_speed * delta
			movement += Vector2(cos(float(enemy["phase"]) * 1.5), sin(float(enemy["phase"]) * 1.5)) * 8.0 * delta
		enemy["position"] = _move_body(position, movement, float(enemy["radius"]))
		if player_position.distance_to(enemy["position"]) < PLAYER_RADIUS + float(enemy["radius"]):
			_take_hit()
			if mode != Mode.PLAYING:
				return


func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["position"] = particle["position"] + particle["velocity"] * delta
		particle["velocity"] = particle["velocity"] * maxf(0.0, 1.0 - delta * 2.4)
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			particles.remove_at(index)


func _take_hit() -> void:
	if player_invulnerable > 0.0 or mode != Mode.PLAYING:
		return
	lives -= 1
	player_invulnerable = 1.55
	hit_flash = 0.22
	screen_shake = 0.24
	var away := player_position - portal_position
	if away.length_squared() < 0.001:
		away = -player_facing
	player_velocity = away.normalized() * 185.0
	_emit_particles(player_position, RED, 18, 140.0)
	_play_tone(140.0, 0.24)
	if lives <= 0:
		_set_mode(Mode.LOST)
		toast = "СВЯЗЬ ПРЕРВАНА"
		toast_remaining = 2.0


func _enter_portal() -> void:
	score += 250 * (sector + 1)
	_emit_particles(portal_position, PALE, 30, 180.0)
	if sector < SECTOR_COUNT - 1:
		_set_mode(Mode.SECTOR_CLEAR)
		_play_tone(720.0, 0.28)
	else:
		_set_mode(Mode.WON)
		best_score = maxi(best_score, score)
		_save_record()
		_play_tone(880.0, 0.48)


func start_run() -> void:
	score = 0
	lives = 3
	sector = 0
	elapsed = 0.0
	_begin_sector()
	_set_mode(Mode.PLAYING)
	_play_tone(520.0, 0.14)


func _begin_sector() -> void:
	cores_collected = 0
	player_position = WORLD / 2.0
	player_velocity = Vector2.ZERO
	player_facing = Vector2.RIGHT
	player_invulnerable = 1.1
	dash_remaining = 0.0
	dash_cooldown = 0.0
	portal_position = Vector2(WORLD.x - 72.0, WORLD.y / 2.0 + 11.0)
	cores.clear()
	enemies.clear()
	walls.clear()
	particles.clear()
	var obstacle_count := 3 + sector
	for index in range(obstacle_count):
		var horizontal := rng.randf() < 0.5
		var position := Vector2(rng.randf_range(160.0, 780.0), rng.randf_range(112.0, 510.0))
		var size := Vector2(rng.randf_range(95.0, 178.0), rng.randf_range(13.0, 19.0)) if horizontal else Vector2(rng.randf_range(13.0, 19.0), rng.randf_range(82.0, 165.0))
		var obstacle := Rect2(position, size)
		var safe_center := obstacle.get_center()
		if safe_center.distance_to(WORLD / 2.0) > 150.0 and safe_center.distance_to(portal_position) > 120.0 and not obstacle.grow(PLAYER_RADIUS + 3.0).has_point(WORLD / 2.0):
			walls.append(obstacle)
	for index in range(CORE_GOAL):
		cores.append(_find_open_position(105.0, 80.0))
	var enemy_count := mini(2 + sector, 6)
	for index in range(enemy_count):
		var enemy_pos := _find_open_position(186.0, 60.0)
		enemies.append({"position": enemy_pos, "kind": "wisp" if index % 3 == 2 else "hunter", "radius": 12.0, "speed": rng.randf_range(38.0, 50.0) + sector * 4.5, "phase": rng.randf_range(0.0, TAU)})


func _find_open_position(player_clearance: float, portal_clearance: float) -> Vector2:
	for attempt in range(140):
		var candidate := Vector2(rng.randf_range(70.0, 870.0), rng.randf_range(78.0, 536.0))
		if candidate.distance_to(player_position) < player_clearance or candidate.distance_to(portal_position) < portal_clearance:
			continue
		if _touches_wall(candidate, 22.0):
			continue
		var overlaps_core := false
		for existing in cores:
			if candidate.distance_to(existing) < 84.0:
				overlaps_core = true
				break
		if not overlaps_core:
			return candidate
	return Vector2(rng.randf_range(85.0, 850.0), rng.randf_range(85.0, 530.0))


func _set_mode(new_mode: int) -> void:
	mode = new_mode
	pressed_keys.clear()
	dash_requested = false
	queue_redraw()


func _toggle_pause() -> void:
	if mode == Mode.PLAYING:
		_set_mode(Mode.PAUSED)
	elif mode == Mode.PAUSED:
		_set_mode(Mode.PLAYING)


func _activate_primary() -> void:
	match mode:
		Mode.MENU:
			if show_help:
				show_help = false
			else:
				start_run()
		Mode.PAUSED:
			_set_mode(Mode.PLAYING)
		Mode.SECTOR_CLEAR:
			if sector < SECTOR_COUNT - 1:
				sector += 1
				_begin_sector()
				_set_mode(Mode.PLAYING)
				_show_toast("СЕКТОР %02d · СИГНАЛ ОБНАРУЖЕН" % (sector + 1))
				_play_tone(560.0, 0.22)
		Mode.WON, Mode.LOST:
			start_run()
	queue_redraw()


func _handle_click(position: Vector2) -> void:
	if Rect2(WORLD.x - 158.0, 14.0, 112.0, 36.0).has_point(position):
		sound_enabled = not sound_enabled
		if sound_enabled:
			_play_tone(660.0, 0.09)
		queue_redraw()
		return
	if mode == Mode.PLAYING and Rect2(WORLD.x - 47.0, 13.0, 36.0, 36.0).has_point(position):
		_set_mode(Mode.PAUSED)
		return
	if mode == Mode.MENU:
		if show_help:
			if Rect2(352.0, 424.0, 256.0, 48.0).has_point(position):
				show_help = false
		else:
			if Rect2(340.0, 380.0, 280.0, 52.0).has_point(position):
				start_run()
			elif Rect2(352.0, 446.0, 256.0, 42.0).has_point(position):
				show_help = true
	elif mode == Mode.PAUSED:
		if Rect2(340.0, 334.0, 280.0, 52.0).has_point(position):
			_activate_primary()
		elif Rect2(352.0, 402.0, 256.0, 42.0).has_point(position):
			start_run()
		elif Rect2(352.0, 450.0, 256.0, 38.0).has_point(position):
			_set_mode(Mode.MENU)
	elif mode == Mode.SECTOR_CLEAR:
		if Rect2(340.0, 358.0, 280.0, 52.0).has_point(position):
			_activate_primary()
	elif mode == Mode.WON or mode == Mode.LOST:
		if Rect2(340.0, 358.0, 280.0, 52.0).has_point(position):
			_activate_primary()
		elif Rect2(352.0, 424.0, 256.0, 42.0).has_point(position):
			_set_mode(Mode.MENU)
	queue_redraw()


func _show_toast(message: String) -> void:
	toast = message
	toast_remaining = 2.0


func _emit_particles(origin: Vector2, color: Color, count: int, speed: float) -> void:
	for index in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var velocity := Vector2(cos(angle), sin(angle)) * rng.randf_range(speed * 0.25, speed)
		particles.append({"position": origin, "velocity": velocity, "life": rng.randf_range(0.35, 0.8), "color": color, "radius": rng.randf_range(1.2, 2.8)})


func _play_tone(frequency: float, duration: float) -> void:
	if not sound_enabled:
		return
	tone_frequency = frequency
	tone_duration = duration
	tone_remaining = duration


func _fill_audio_buffer() -> void:
	if sound_playback == null:
		return
	var frames := sound_playback.get_frames_available()
	if frames <= 0:
		return
	var samples := PackedVector2Array()
	samples.resize(frames)
	for index in range(frames):
		var sample := 0.0
		if sound_enabled and tone_remaining > 0.0:
			var envelope := clampf(tone_remaining / tone_duration, 0.0, 1.0)
			sample = sin(tone_phase) * envelope * 0.065
			tone_phase += TAU * tone_frequency / 22050.0
			tone_remaining = maxf(0.0, tone_remaining - 1.0 / 22050.0)
		samples[index] = Vector2(sample, sample)
	sound_playback.push_buffer(samples)


func _load_record() -> void:
	var config := ConfigFile.new()
	if config.load("user://pilot.cfg") == OK:
		best_score = int(config.get_value("records", "best_score", 0))


func _save_record() -> void:
	var config := ConfigFile.new()
	config.set_value("records", "best_score", best_score)
	config.save("user://pilot.cfg")


func _draw() -> void:
	var offset := Vector2.ZERO
	if screen_shake > 0.0:
		offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * screen_shake * 30.0
	draw_set_transform(offset)
	_draw_backdrop()
	_draw_field()
	if mode == Mode.PLAYING or mode == Mode.PAUSED or mode == Mode.SECTOR_CLEAR or mode == Mode.WON or mode == Mode.LOST:
		_draw_world()
	if mode == Mode.PLAYING:
		_draw_hud()
	if not toast.is_empty() and toast_remaining > 0.0:
		_draw_toast()
	if mode == Mode.MENU:
		_draw_menu()
	elif mode == Mode.PAUSED:
		_draw_pause()
	elif mode == Mode.SECTOR_CLEAR:
		_draw_sector_clear()
	elif mode == Mode.WON:
		_draw_end(true)
	elif mode == Mode.LOST:
		_draw_end(false)
	draw_set_transform(Vector2.ZERO)


func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD), DEEP)
	draw_rect(Rect2(0.0, 0.0, WORLD.x, WORLD.y), Color("#0b1920"))
	for index in range(18):
		var alpha := 0.012 + float(index) * 0.0015
		var radius := 115.0 + float(index) * 23.0
		draw_circle(Vector2(470.0, 303.0), radius, Color(0.19, 0.48, 0.43, alpha))
	for star in stars:
		var twinkle := 0.62 + 0.38 * sin(elapsed * 1.2 + star.w)
		var color := Color(0.63, 0.86, 0.81, star.w * twinkle * 0.72)
		draw_circle(Vector2(star.x, star.y), star.z, color)
	for x in range(56, 930, 44):
		draw_line(Vector2(x, 56), Vector2(x, 568), Color(0.21, 0.37, 0.39, 0.12), 1.0)
	for y in range(70, 568, 44):
		draw_line(Vector2(32, y), Vector2(928, y), Color(0.21, 0.37, 0.39, 0.10), 1.0)
	if mode == Mode.MENU and not show_help:
		_draw_menu_beacon()


func _draw_field() -> void:
	var border_color := Color(0.32, 0.54, 0.54, 0.8)
	draw_rect(BORDER, Color(0.025, 0.065, 0.075, 0.55), false, 1.2)
	draw_line(BORDER.position, Vector2(BORDER.position.x + 52.0, BORDER.position.y), CYAN, 2.0)
	draw_line(Vector2(BORDER.end.x - 52.0, BORDER.position.y), Vector2(BORDER.end.x, BORDER.position.y), border_color, 1.0)
	draw_line(Vector2(BORDER.position.x, BORDER.end.y), Vector2(BORDER.position.x + 52.0, BORDER.end.y), border_color, 1.0)
	draw_line(Vector2(BORDER.end.x - 52.0, BORDER.end.y), BORDER.end, border_color, 1.0)


func _draw_menu_beacon() -> void:
	var center := Vector2(480.0, 183.0)
	for ring in range(4):
		var radius := 37.0 + float(ring) * 17.0 + sin(elapsed * 1.1 + ring) * 2.0
		draw_arc(center, radius, elapsed * 0.18 + ring, elapsed * 0.18 + ring + TAU, 72, Color(0.55, 0.91, 0.82, 0.32 - ring * 0.045), 1.2)
	draw_circle(center, 7.0 + sin(elapsed * 2.0) * 1.5, Color(0.72, 1.0, 0.92, 0.95))
	var ship_points := PackedVector2Array([center + Vector2(20.0, 0.0), center + Vector2(-10.0, -8.0), center + Vector2(-6.0, 0.0), center + Vector2(-10.0, 8.0)])
	draw_colored_polygon(ship_points, Color("#b6f4e5"))


func _draw_world() -> void:
	for wall in walls:
		draw_rect(wall, Color("#10262d"))
		draw_rect(wall, Color("#28474d"), false, 1.0)
		var cap_end := Vector2(minf(wall.position.x + 28.0, wall.end.x), wall.position.y + 1.0)
		draw_line(wall.position + Vector2(1.0, 1.0), cap_end, Color(0.55, 0.91, 0.82, 0.6), 1.0)
	_draw_portal()
	for core_position in cores:
		_draw_core(core_position)
	for enemy in enemies:
		_draw_enemy(enemy)
	_draw_particles()
	_draw_player()


func _draw_portal() -> void:
	var active := cores_collected >= CORE_GOAL
	var pulse := sin(elapsed * 2.0) * 2.0
	var color := CYAN if active else Color("#557075")
	draw_arc(portal_position, 25.0 + pulse, elapsed * 0.4, elapsed * 0.4 + TAU, 64, color, 2.0)
	draw_arc(portal_position, 17.0, -elapsed * 0.55, -elapsed * 0.55 + TAU, 64, Color(color, 0.62), 1.2)
	draw_circle(portal_position, 6.0, Color(color, 0.35))
	if not active:
		_draw_text_centered("%d / %d" % [cores_collected, CORE_GOAL], portal_position.y + 4.0, 9, MUTED)


func _draw_core(position: Vector2) -> void:
	var pulse := 1.0 + sin(elapsed * 3.2 + position.x * 0.05) * 0.12
	var points := PackedVector2Array([position + Vector2(0.0, -9.0 * pulse), position + Vector2(7.0 * pulse, 0.0), position + Vector2(0.0, 9.0 * pulse), position + Vector2(-7.0 * pulse, 0.0)])
	draw_circle(position, 15.0 * pulse, Color(0.31, 0.86, 0.73, 0.08))
	draw_colored_polygon(points, PALE)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0.87, 1.0, 0.95, 0.9), 1.0)


func _draw_enemy(enemy: Dictionary) -> void:
	var position: Vector2 = enemy["position"]
	var is_wisp: bool = enemy["kind"] == "wisp"
	var color := PURPLE if is_wisp else RED
	var radius: float = enemy["radius"]
	draw_circle(position, radius + 8.0, Color(color, 0.075))
	draw_circle(position, radius, color)
	draw_circle(position + Vector2(-3.0, -2.0), 1.7, Color("#3b2634"))
	draw_circle(position + Vector2(3.0, -2.0), 1.7, Color("#3b2634"))
	if is_wisp:
		draw_arc(position, radius + 3.0, elapsed * 1.2, elapsed * 1.2 + TAU, 32, Color(color, 0.65), 1.0)


func _draw_player() -> void:
	var alpha := 1.0
	if player_invulnerable > 0.0 and int(elapsed * 16.0) % 2 == 0:
		alpha = 0.42
	var direction := player_facing.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var nose := player_position + direction * 15.0
	var rear := player_position - direction * 10.0
	var points := PackedVector2Array([nose, rear + perpendicular * 9.0, player_position - direction * 4.0, rear - perpendicular * 9.0])
	draw_circle(player_position, 23.0, Color(CYAN, 0.08 * alpha))
	draw_colored_polygon(points, Color(CYAN, alpha))
	draw_circle(player_position + direction * 1.0, 3.0, Color("#effff9", alpha))
	if dash_remaining > 0.0:
		draw_line(player_position - dash_direction * 10.0, player_position - dash_direction * 32.0, Color(PALE, 0.65), 2.0)


func _draw_particles() -> void:
	for particle in particles:
		var fade: float = clampf(float(particle["life"]) / 0.8, 0.0, 1.0)
		draw_circle(particle["position"], float(particle["radius"]) * fade, Color(particle["color"], fade))


func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, WORLD.x, 53.0), Color(0.025, 0.055, 0.067, 0.9))
	_draw_text("СЕКТОР %02d  /  %02d" % [sector + 1, SECTOR_COUNT], Vector2(36.0, 31.0), 12, Color("#b8d1cc"))
	draw_line(Vector2(196.0, 14.0), Vector2(196.0, 39.0), Color("#304b50"), 1.0)
	_draw_text("СЧЁТ  %s" % str(score).pad_zeros(5), Vector2(218.0, 31.0), 12, Color("#d8e9e3"))
	_draw_text("ЯДРА  %02d / %02d" % [cores_collected, CORE_GOAL], Vector2(390.0, 31.0), 12, CYAN if cores_collected == CORE_GOAL else MUTED)
	var hearts := "♥  ".repeat(lives).strip_edges()
	_draw_text(hearts if not hearts.is_empty() else "—", Vector2(665.0, 32.0), 16, Color("#eaa29a"))
	_draw_sound_button()
	_draw_button("Ⅱ", Rect2(WORLD.x - 47.0, 13.0, 36.0, 36.0), false, 14)
	draw_rect(BORDER, Color(0.34, 0.57, 0.56, 0.76), false, 1.0)
	var goal := "КОСНИСЬ ПОРТАЛА" if cores_collected >= CORE_GOAL else "СОБЕРИ ЯДРА  ·  ИЗБЕГАЙ ОХОТНИКОВ"
	_draw_text_centered(goal, 590.0, 10, Color("#8fa9a8"))
	var bar_width := 108.0
	draw_rect(Rect2(420.0, 48.0, bar_width, 2.0), Color("#294247"))
	if dash_cooldown <= 0.0:
		draw_rect(Rect2(420.0, 48.0, bar_width, 2.0), CYAN)
	else:
		draw_rect(Rect2(420.0, 48.0, bar_width * (1.0 - dash_cooldown / DASH_COOLDOWN), 2.0), Color("#6e9690"))


func _draw_menu() -> void:
	_draw_brand()
	_draw_text_centered("ПОСЛЕДНИЙ СИГНАЛ  ·  2189", 127.0, 11, CYAN)
	if show_help:
		_draw_text_centered("ПРОТОКОЛ ПИЛОТА", 204.0, 11, CYAN)
		_draw_text_centered("СОБИРАЙ.  УКЛОНЯЙСЯ.  ЗАЖГИ МАЯК.", 254.0, 25, INK)
		_draw_text_centered("WASD ИЛИ СТРЕЛКИ  ·  ДВИЖЕНИЕ", 319.0, 13, Color("#b4c9c5"))
		_draw_text_centered("ПРОБЕЛ  ·  РЫВОК С НЕУЯЗВИМОСТЬЮ", 349.0, 13, Color("#b4c9c5"))
		_draw_text_centered("ESC  ·  ПАУЗА     M  ·  ЗВУК", 379.0, 13, Color("#b4c9c5"))
		_draw_button("НАЗАД", Rect2(352.0, 424.0, 256.0, 48.0), false)
	else:
		_draw_text_centered("Зажги маяк.", 306.0, 42, INK)
		_draw_text_centered("Собери шесть световых ядер в каждом секторе.", 338.0, 13, Color("#a4b8b5"))
		_draw_text_centered("Пройди пять затерянных секторов и верни сигнал домой.", 359.0, 12, Color("#879c9c"))
		_draw_button("НАЧАТЬ ПОЛЁТ", Rect2(340.0, 380.0, 280.0, 52.0), true)
		_draw_button("УПРАВЛЕНИЕ И ЦЕЛЬ  ·  I", Rect2(352.0, 446.0, 256.0, 42.0), false)
		if best_score > 0:
			_draw_text_centered("ЛУЧШИЙ РЕЗУЛЬТАТ  ·  %s" % str(best_score).pad_zeros(5), 526.0, 10, Color("#68817f"))
	_draw_footer()


func _draw_pause() -> void:
	_draw_panel()
	_draw_text_centered("ПАУЗА  ·  СИГНАЛ СОХРАНЁН", 221.0, 10, CYAN)
	_draw_text_centered("Передышка.", 274.0, 36, INK)
	_draw_text_centered("СЕКТОР %02d  ·  ЯДРА %d / %d  ·  СЧЁТ %s" % [sector + 1, cores_collected, CORE_GOAL, str(score).pad_zeros(5)], 310.0, 11, MUTED)
	_draw_button("ПРОДОЛЖИТЬ", Rect2(340.0, 334.0, 280.0, 52.0), true)
	_draw_button("НАЧАТЬ ЗАНОВО", Rect2(352.0, 402.0, 256.0, 42.0), false)
	_draw_button("В ГЛАВНОЕ МЕНЮ", Rect2(352.0, 450.0, 256.0, 38.0), false)


func _draw_sector_clear() -> void:
	_draw_panel()
	_draw_text_centered("СЕКТОР %02d  ·  ОЧИЩЕН" % [sector + 1], 226.0, 10, CYAN)
	_draw_text_centered("Свет возвращается.", 281.0, 33, INK)
	_draw_text_centered("Ядра стабилизированы. Маяк уже близко.", 318.0, 13, MUTED)
	_draw_button("СЛЕДУЮЩИЙ СЕКТОР", Rect2(340.0, 358.0, 280.0, 52.0), true)
	_draw_text_centered("СЧЁТ  %s" % str(score).pad_zeros(5), 444.0, 10, Color("#799390"))


func _draw_end(victory: bool) -> void:
	_draw_panel()
	if victory:
		_draw_text_centered("МАЯК СНОВА СЛЫШЕН", 218.0, 10, CYAN)
		_draw_text_centered("Ты вернул свет домой.", 273.0, 31, INK)
		_draw_text_centered("Пять секторов пройдены. Кто-то ответил на сигнал.", 310.0, 12, MUTED)
		_draw_text_centered("РЕЗУЛЬТАТ  %s  ·  ЛУЧШИЙ  %s" % [str(score).pad_zeros(5), str(best_score).pad_zeros(5)], 336.0, 10, Color("#9dc3ba"))
	else:
		_draw_text_centered("СВЯЗЬ ПРЕРВАНА", 218.0, 10, RED)
		_draw_text_centered("Тьма победила.", 273.0, 34, INK)
		_draw_text_centered("Ты добрался до сектора %02d. Попробуй ещё раз." % [sector + 1], 310.0, 12, MUTED)
		_draw_text_centered("СОБРАНО ЯДЕР  %02d" % [sector * CORE_GOAL + cores_collected], 336.0, 10, Color("#9dc3ba"))
	_draw_button("ПОВТОРИТЬ ПОЛЁТ", Rect2(340.0, 358.0, 280.0, 52.0), true)
	_draw_button("В ГЛАВНОЕ МЕНЮ", Rect2(352.0, 424.0, 256.0, 42.0), false)


func _draw_panel() -> void:
	draw_rect(Rect2(0.0, 0.0, WORLD.x, WORLD.y), Color(0.015, 0.035, 0.045, 0.7))
	draw_rect(Rect2(240.0, 160.0, 480.0, 330.0), Color("#0c1b21"))
	draw_rect(Rect2(240.0, 160.0, 480.0, 330.0), Color(0.29, 0.47, 0.49, 0.85), false, 1.0)
	draw_line(Vector2(240.0, 160.0), Vector2(310.0, 160.0), CYAN, 2.0)


func _draw_brand() -> void:
	_draw_text_centered("✳  LUMEN DRIFT", 79.0, 14, Color("#d7ebe5"))


func _draw_footer() -> void:
	_draw_text("© 2189  LUMEN RESEARCH DIVISION", Vector2(34.0, 582.0), 9, Color("#50686c"))
	_draw_text("ОДИН ПИЛОТ  ·  ОДИН ПОСЛЕДНИЙ СИГНАЛ", Vector2(568.0, 582.0), 9, Color("#50686c"))


func _draw_sound_button() -> void:
	_draw_button("♫  ЗВУК %s" % ("ВКЛ" if sound_enabled else "ВЫКЛ"), Rect2(WORLD.x - 158.0, 14.0, 112.0, 36.0), false, 9)


func _draw_button(label: String, rect: Rect2, primary: bool, font_size: int = 10) -> void:
	var hovered := rect.has_point(get_global_mouse_position())
	if primary:
		var fill := Color("#a9f0df") if hovered else CYAN
		draw_rect(rect, fill)
		_draw_text_centered_in(label, rect, font_size, Color("#09201e"))
	else:
		var border := Color("#638b84") if hovered else Color("#38555b")
		draw_rect(rect, Color("#102329", 0.8))
		draw_rect(rect, border, false, 1.0)
		_draw_text_centered_in(label, rect, font_size, Color("#b8cfca") if hovered else Color("#91a9a6"))


func _draw_text_centered_in(label: String, rect: Rect2, size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	_draw_text(label, Vector2(rect.position.x + (rect.size.x - measured.x) * 0.5, rect.position.y + (rect.size.y + size * 0.7) * 0.5), size, color)


func _draw_text_centered(label: String, y: float, size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	_draw_text(label, Vector2((WORLD.x - measured.x) * 0.5, y), size, color)


func _draw_text(label: String, position: Vector2, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _draw_toast() -> void:
	var rect := Rect2(270.0, WORLD.y - 62.0, 420.0, 34.0)
	draw_rect(rect, Color("#10272b"))
	draw_rect(rect, Color(0.36, 0.63, 0.58, 0.9), false, 1.0)
	_draw_text_centered(toast, rect.position.y + 22.0, 9, PALE)

