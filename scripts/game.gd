extends Node3D

enum Mode { MENU, BRIEFING, PLAYING, PAUSED, INTERMISSION, WON, LOST }
enum Objective { REPAIR, RECOVER, DEFEND }

const MISSION_COUNT := 15
const PLAYER_SPEED := 11.0
const DASH_SPEED := 26.0
const DASH_DURATION := 0.22
const DASH_COOLDOWN := 1.1
const SAVE_PATH := "user://campaign.cfg"
const CHAPTERS := ["Край тишины", "Слепая орбита", "Эхо экипажа", "Глубокий узел", "Последний свет"]
const TITLES := ["Нулевая частота", "Кристаллы памяти", "Маяк Орион", "Слепая орбита", "Поле обломков", "Погасший конвой", "Чужой голос", "Карантинный узел", "Эвакуационный коридор", "Глубокий узел", "Тихая буря", "Сердце сети", "Обратный сигнал", "Последний ретранслятор", "Домой"]
const BRIEFS := [
	"Лира: «Пять узлов пропали за один цикл. Начнём с внешнего маяка — там ещё теплится питание».",
	"В обломках найдены кристаллы памяти. Каждый хранит фрагмент последней передачи экипажа.",
	"Собери аварийный маяк. Ответ приходит не с Земли — он повторяет твой собственный сигнал.",
	"Орион выключили вручную. Кто-то оставил маршрут через слепой пояс.",
	"Корпус «Меридиана» разорван изнутри. Найди ячейки питания и не задерживайся у обломков.",
	"Защити эвакуационный коридор. Лира слышит капсулы, хотя датчики показывают пустоту.",
	"В журнале капитана Нади: «Мы выключили сеть сами. Не отвечайте голосу в канале».",
	"Охотники не атакуют маяк — они заслоняют его. Отключи карантинные узлы.",
	"В капсулах остались люди в анабиозе. Найди энергоячейки, пока защита станции держится.",
	"Лира узнаёт код сигнала. Он принадлежал её первой версии, списанной двадцать лет назад.",
	"Стабилизируй ядро сети. Помехи меняют направление прямо в полёте.",
	"Защити центральный узел от волны охотников, пока Лира отделяет заражённый канал.",
	"Источник сигнала — архивный маяк, который отвечает вместо погибших экипажей.",
	"Отключи последний ретранслятор. Лира предлагает сохранить копию голоса — выбор за тобой.",
	"Сеть снова молчит. В капсулах просыпаются спасённые, а в эфире впервые звучит живой ответ."
]
const PALETTE := [Color("#4be0cc"), Color("#7dcfff"), Color("#c69cff"), Color("#ffac82"), Color("#f4e28c")]

var mode := Mode.MENU
var mission_index := 0
var lives := 3
var score := 0
var best_score := 0
var objective_progress := 0
var objective_goal := 3
var objective_kind := Objective.REPAIR
var mission_clock := 0.0
var defense_time := 0.0
var dash_remaining := 0.0
var dash_cooldown := 0.0
var invulnerability := 0.0
var dash_direction := Vector3.FORWARD
var gate_active := false
var campaign_started := false
var sound_enabled := true
var rng := RandomNumberGenerator.new()
var pressed: Dictionary = {}
var enemies: Array[Dictionary] = []
var targets: Array[Area3D] = []
var cores: Array[Area3D] = []
var arena: Node3D
var player: CharacterBody3D
var ship: Node3D
var camera: Camera3D
var ui_panel: PanelContainer
var ui_title: Label
var ui_text: Label
var ui_hint: Label
var ui_button: Button
var hud: Label
var gate: Node3D

func _ready() -> void:
	rng.randomize()
	_setup_window()
	_load_save()
	_build_world()
	_build_ui()
	_show(Mode.MENU)

func _setup_window() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Lumen Drift — Сигнал сквозь тьму")
		DisplayServer.window_set_min_size(Vector2i(960, 600))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().focus_exited.connect(_on_focus_lost)

func _build_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#050b13")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6395a4")
	env.ambient_light_energy = 0.65
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_color = Color("#9ccbc9")
	sun.light_energy = 1.3
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 10, 0)
	fill.light_color = PALETTE[0]
	fill.light_energy = 1.2
	fill.omni_range = 30
	add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(44, 44)
	floor.mesh = plane
	floor.material_override = _mat(Color("#0a1720"), 0.8)
	add_child(floor)
	arena = Node3D.new()
	arena.name = "Sector"
	add_child(arena)
	_build_stars()
	_build_bounds()
	_build_player()
	camera = Camera3D.new()
	camera.position = Vector3(0, 17, 20)
	camera.fov = 54
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	_build_gate()

func _build_stars() -> void:
	for i in range(100):
		var star := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		star.mesh = sphere
		star.position = Vector3(rng.randf_range(-28, 28), rng.randf_range(4, 23), rng.randf_range(-28, 28))
		star.material_override = _mat(Color("#80c6cf"), 0.2, 0, true)
		add_child(star)

func _build_bounds() -> void:
	for side in range(4):
		var wall := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(44, 4, 0.8) if side < 2 else Vector3(0.8, 4, 44)
		collider.shape = shape
		wall.add_child(collider)
		wall.position = Vector3(0, 1, -21.5 if side == 0 else 21.5) if side < 2 else Vector3(-21.5 if side == 2 else 21.5, 1, 0)
		add_child(wall)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "PilotShip"
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.72
	capsule.height = 1.4
	collider.shape = capsule
	collider.position.y = 0.45
	player.add_child(collider)
	ship = Node3D.new()
	player.add_child(ship)
	_box(ship, Vector3(0, 0.5, -0.15), Vector3(0.72, 0.42, 2.2), Color("#b9e7df"), 0.18)
	_box(ship, Vector3(-1.03, 0.23, 0.16), Vector3(1.38, 0.16, 1.38), Color("#587f8d"), 0.24)
	_box(ship, Vector3(1.03, 0.23, 0.16), Vector3(1.38, 0.16, 1.38), Color("#587f8d"), 0.24)
	_sphere(ship, Vector3(0, 0.88, -0.35), Vector3(0.3, 0.2, 0.46), Color("#67dfe0"), true)
	_cylinder(ship, Vector3(-0.36, 0.43, 1.12), 0.22, 0.78, Color("#1b303a"))
	_cylinder(ship, Vector3(0.36, 0.43, 1.12), 0.22, 0.78, Color("#1b303a"))
	_sphere(ship, Vector3(-0.36, 0.43, 1.55), Vector3(0.18, 0.16, 0.18), Color("#7ef4df"), true)
	_sphere(ship, Vector3(0.36, 0.43, 1.55), Vector3(0.18, 0.16, 0.18), Color("#7ef4df"), true)
	add_child(player)

func _build_gate() -> void:
	gate = Node3D.new()
	gate.name = "ExitGate"
	gate.position = Vector3(15.5, 0, 0)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.3
	torus.outer_radius = 1.52
	ring.mesh = torus
	ring.rotation_degrees.x = 90
	ring.material_override = _mat(PALETTE[_chapter()], 0.2, 0, true)
	gate.add_child(ring)
	var light := OmniLight3D.new()
	light.position.y = 1
	light.light_color = PALETTE[_chapter()]
	light.light_energy = 1.2
	light.omni_range = 5
	gate.add_child(light)
	arena.add_child(gate)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_color", Color("#d7eeeb"))
	root.add_child(hud)
	ui_panel = PanelContainer.new()
	ui_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui_panel.position = Vector2(-280, -220)
	ui_panel.size = Vector2(560, 440)
	ui_panel.custom_minimum_size = Vector2(560, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0a151df2")
	style.border_color = Color("#387f7b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	ui_panel.add_theme_stylebox_override("panel", style)
	root.add_child(ui_panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 15)
	ui_panel.add_child(stack)
	ui_title = Label.new()
	ui_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_title.add_theme_font_size_override("font_size", 28)
	ui_title.add_theme_color_override("font_color", Color("#dffaf4"))
	stack.add_child(ui_title)
	ui_text = Label.new()
	ui_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_text.add_theme_font_size_override("font_size", 16)
	ui_text.add_theme_color_override("font_color", Color("#a6c0c1"))
	ui_text.custom_minimum_size.y = 190
	stack.add_child(ui_text)
	ui_hint = Label.new()
	ui_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_hint.add_theme_font_size_override("font_size", 13)
	ui_hint.add_theme_color_override("font_color", Color("#66dcca"))
	stack.add_child(ui_hint)
	ui_button = Button.new()
	ui_button.custom_minimum_size.y = 48
	ui_button.add_theme_font_size_override("font_size", 16)
	ui_button.pressed.connect(_primary)
	stack.add_child(ui_button)
	var sound_button := Button.new()
	sound_button.text = "Звук: M — %s  ·  WASD/стрелки · Space рывок · F действие · Esc пауза" % ("вкл" if sound_enabled else "выкл")
	sound_button.flat = true
	sound_button.pressed.connect(_toggle_sound)
	stack.add_child(sound_button)

func _show(next_mode: int) -> void:
	mode = next_mode
	ui_panel.visible = mode != Mode.PLAYING
	hud.visible = mode == Mode.PLAYING
	match mode:
		Mode.MENU:
			ui_title.text = "✳  LUMEN DRIFT"
			ui_text.text = "2189 год. Сеть маяков Lumen замолчала. Пилот спасательного корабля и бортовой ИИ Лира отправляются к пятнадцати узлам, чтобы узнать, кто отвечает из темноты."
			ui_hint.text = "5 ГЛАВ · 15 МИССИЙ · КОНТРОЛЬНЫЕ ТОЧКИ"
			ui_button.text = "ПРОДОЛЖИТЬ КАМПАНИЮ" if campaign_started else "НАЧАТЬ КАМПАНИЮ"
		Mode.BRIEFING:
			ui_title.text = "%s · МИССИЯ %02d" % [CHAPTERS[_chapter()], mission_index + 1]
			ui_text.text = "%s\n\n%s\n\nЗадача: %s" % [TITLES[mission_index], BRIEFS[mission_index], _objective_text()]
			ui_hint.text = "После вылета ищи цель по свечению. Прогресс главы сохранится."
			ui_button.text = "ВЫЛЕТЕТЬ"
		Mode.PAUSED:
			ui_title.text = "ПАУЗА"
			ui_text.text = "%s\n\nГлава %d из 5 · Миссия %d из 15\nСчёт %d · Корпус %d / 3" % [TITLES[mission_index], _chapter() + 1, mission_index + 1, score, lives]
			ui_hint.text = "Esc — продолжить полёт"
			ui_button.text = "ПРОДОЛЖИТЬ"
		Mode.INTERMISSION:
			ui_title.text = "МИССИЯ ЗАВЕРШЕНА"
			ui_text.text = "%s\n\n%s\n\nЛира: «Передача сохранена. Я хочу услышать её ещё раз, когда мы будем в безопасности»." % [TITLES[mission_index], BRIEFS[mission_index]]
			ui_hint.text = "КОНТРОЛЬНАЯ ТОЧКА СОХРАНЕНА"
			ui_button.text = "СЛЕДУЮЩАЯ МИССИЯ"
		Mode.WON:
			ui_title.text = "СИГНАЛ ДОМА"
			ui_text.text = "Пять глав пройдены. В капсулах просыпаются спасённые.\n\nЛира: «Это не архив. Кто-то услышал нас и ответил».\n\nЛУЧШИЙ РЕЗУЛЬТАТ: %d" % best_score
			ui_hint.text = "КАМПАНИЯ ЗАВЕРШЕНА"
			ui_button.text = "НОВАЯ КАМПАНИЯ"
		Mode.LOST:
			ui_title.text = "СВЯЗЬ ПРЕРВАНА"
			ui_text.text = "Корабль потерял управление в миссии «%s».\n\nКонтрольная точка сохранена. Повтори миссию, не начиная кампанию заново." % TITLES[mission_index]
			ui_hint.text = "ЛИРА: «Я удерживаю последний маршрут»"
			ui_button.text = "ПОВТОРИТЬ МИССИЮ"

func _primary() -> void:
	match mode:
		Mode.MENU:
			if not campaign_started:
				mission_index = 0
				score = 0
				campaign_started = true
			_show(Mode.BRIEFING)
		Mode.BRIEFING:
			_start_mission()
		Mode.PAUSED:
			_show(Mode.PLAYING)
		Mode.LOST:
			_start_mission()
		Mode.INTERMISSION:
			if mission_index == MISSION_COUNT - 1:
				best_score = maxi(best_score, score)
				_save(MISSION_COUNT)
				_show(Mode.WON)
			else:
				mission_index += 1
				_save(mission_index)
				_show(Mode.BRIEFING)
		Mode.WON:
			mission_index = 0
			score = 0
			campaign_started = true
			_save(0)
			_show(Mode.BRIEFING)

func _start_mission() -> void:
	lives = 3
	objective_progress = 0
	mission_clock = 0
	defense_time = 0
	dash_cooldown = 0
	dash_remaining = 0
	invulnerability = 1
	gate_active = false
	player.position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	objective_kind = Objective(mission_index % 3)
	objective_goal = 6 if objective_kind == Objective.RECOVER else (90 if objective_kind == Objective.DEFEND else 3 + _chapter())
	_clear_arena()
	_spawn_obstacles(8 + _chapter() * 2)
	_spawn_objectives()
	_spawn_enemies(2 + _chapter())
	_show(Mode.PLAYING)

func _clear_arena() -> void:
	for node in arena.get_children():
		node.queue_free()
	enemies.clear()
	targets.clear()
	cores.clear()
	_build_gate()

func _spawn_obstacles(count: int) -> void:
	for i in range(count):
		var rock := StaticBody3D.new()
		var mesh_node := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.7, 1.7)
		mesh.height = mesh.radius * 1.7
		mesh_node.mesh = mesh
		mesh_node.material_override = _mat(Color("#263c47"), 0.92, 0.04)
		rock.add_child(mesh_node)
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = mesh.radius * 0.75
		collision.shape = sphere
		rock.add_child(collision)
		rock.position = Vector3(rng.randf_range(-17, 17), mesh.radius * 0.7, rng.randf_range(-16, 16))
		if rock.position.length() < 5 or rock.position.distance_to(Vector3(15.5, 0, 0)) < 4:
			rock.position.x += 8
		rock.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.75, 1.2), rng.randf_range(0.8, 1.35))
		arena.add_child(rock)

func _spawn_objectives() -> void:
	if objective_kind == Objective.RECOVER:
		for i in range(objective_goal):
			var core := _area("MemoryCore", Vector3(rng.randf_range(-15, 14), 0.8, rng.randf_range(-14, 14)), 0.85)
			var gem := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.48
			mesh.height = 1.05
			gem.mesh = mesh
			gem.material_override = _mat(PALETTE[_chapter()], 0.15, 0, true)
			core.add_child(gem)
			cores.append(core)
	else:
		for i in range(objective_goal):
			var pos := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			if pos.length() < 5:
				pos.x += 9
			var target := _area("RelayNode", pos, 1.15)
			_box(target, Vector3(0, 1, 0), Vector3(0.7, 1.9, 0.7), Color("#52727b"))
			_sphere(target, Vector3(0, 2.15, 0), Vector3(0.36, 0.42, 0.36), PALETTE[_chapter()], true)
			targets.append(target)

func _spawn_enemies(count: int) -> void:
	for i in range(count):
		var enemy := Area3D.new()
		enemy.name = "Hunter" if i % 2 == 0 else "Wisp"
		enemy.position = Vector3(rng.randf_range(-15, 15), 0.5, rng.randf_range(-15, 15))
		if enemy.position.length() < 7:
			enemy.position.x += 11
		var collider := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.95
		collider.shape = sphere
		enemy.add_child(collider)
		_sphere(enemy, Vector3.ZERO, Vector3(0.8, 0.72, 0.8), Color("#c36f9f") if i % 2 else Color("#de826a"), true)
		_box(enemy, Vector3(0, 0, -0.95), Vector3(0.18, 0.12, 1.3), Color("#6b4264"))
		arena.add_child(enemy)
		enemies.append({"node": enemy, "speed": 2.6 + float(_chapter()) * 0.5})

func _area(label: String, pos: Vector3, radius: float) -> Area3D:
	var area := Area3D.new()
	area.name = label
	area.position = pos
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collider.shape = sphere
	area.add_child(collider)
	arena.add_child(area)
	return area

func _physics_process(delta: float) -> void:
	if mode != Mode.PLAYING:
		return
	mission_clock += delta
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	dash_remaining = maxf(0.0, dash_remaining - delta)
	invulnerability = maxf(0.0, invulnerability - delta)
	var move := Vector2(float(_down(KEY_D) or _down(KEY_RIGHT)) - float(_down(KEY_A) or _down(KEY_LEFT)), float(_down(KEY_S) or _down(KEY_DOWN)) - float(_down(KEY_W) or _down(KEY_UP))).normalized()
	var speed := DASH_SPEED if dash_remaining > 0 else PLAYER_SPEED
	player.velocity.x = move_toward(player.velocity.x, move.x * speed, 35.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, move.y * speed, 35.0 * delta)
	if dash_remaining > 0:
		player.velocity.x = dash_direction.x * DASH_SPEED
		player.velocity.z = dash_direction.z * DASH_SPEED
	player.move_and_slide()
	if player.velocity.length_squared() > 0.2:
		ship.rotation.y = lerp_angle(ship.rotation.y, atan2(-player.velocity.x, -player.velocity.z), 8.0 * delta)
	camera.position = camera.position.lerp(player.position + Vector3(0, 17, 20), 4.0 * delta)
	camera.look_at(player.position + Vector3(0, 0, -1), Vector3.UP)
	_update_enemies(delta)
	_update_objectives()
	if objective_kind == Objective.DEFEND:
		defense_time += delta
		objective_progress = mini(int(defense_time), objective_goal)
		if defense_time >= objective_goal:
			_activate_gate()
	if gate_active and player.position.distance_to(gate.position) < 2.1:
		_finish_mission()
	_update_hud()

func _process(_delta: float) -> void:
	if mode != Mode.PLAYING:
		return
	if _once(KEY_SPACE) and dash_cooldown <= 0:
		var move := Vector3(float(_down(KEY_D) or _down(KEY_RIGHT)) - float(_down(KEY_A) or _down(KEY_LEFT)), 0, float(_down(KEY_S) or _down(KEY_DOWN)) - float(_down(KEY_W) or _down(KEY_UP)))
		dash_direction = move.normalized() if move.length_squared() > 0.01 else Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
		dash_remaining = DASH_DURATION
		dash_cooldown = DASH_COOLDOWN
		invulnerability = maxf(invulnerability, 0.3)
	if _once(KEY_F):
		_interact()
	if _once(KEY_ESCAPE):
		_show(Mode.PAUSED)

func _update_enemies(delta: float) -> void:
	for record in enemies:
		var enemy: Area3D = record["node"]
		if not is_instance_valid(enemy):
			continue
		var toward := player.position - enemy.position
		if toward.length_squared() > 0.01:
			enemy.position += toward.normalized() * float(record["speed"]) * delta
		if enemy.position.distance_to(player.position) < 1.35:
			_take_hit()

func _update_objectives() -> void:
	for i in range(cores.size() - 1, -1, -1):
		var core := cores[i]
		if is_instance_valid(core) and core.position.distance_to(player.position) < 1.25:
			core.queue_free()
			cores.remove_at(i)
			objective_progress += 1
			score += 100
	if objective_kind == Objective.RECOVER and objective_progress >= objective_goal:
		_activate_gate()
	if objective_kind == Objective.REPAIR and objective_progress >= objective_goal:
		_activate_gate()

func _interact() -> void:
	if objective_kind != Objective.REPAIR:
		return
	for i in range(targets.size() - 1, -1, -1):
		var target := targets[i]
		if is_instance_valid(target) and target.position.distance_to(player.position) < 2.4:
			target.queue_free()
			targets.remove_at(i)
			objective_progress += 1
			score += 150
			break
	if objective_progress >= objective_goal:
		_activate_gate()

func _activate_gate() -> void:
	gate_active = true
	var mesh := gate.get_child(0) as MeshInstance3D
	mesh.material_override = _mat(Color("#84f3d9"), 0.15, 0, true)

func _take_hit() -> void:
	if invulnerability > 0 or mode != Mode.PLAYING:
		return
	lives -= 1
	invulnerability = 1.4
	if player.position.length_squared() > 0.01:
		player.velocity = player.position.normalized() * 7.0
	if lives <= 0:
		_save(mission_index)
		_show(Mode.LOST)

func take_hit() -> void:
	_take_hit()

func _finish_mission() -> void:
	if mode != Mode.PLAYING:
		return
	score += 500 + int(maxf(0.0, 120.0 - mission_clock) * 4.0)
	_save(mission_index + 1)
	_show(Mode.INTERMISSION)

func _objective_text() -> String:
	match Objective(mission_index % 3):
		Objective.REPAIR:
			return "найди и активируй %d узла (F рядом с узлом), затем долети до портала" % (3 + _chapter())
		Objective.RECOVER:
			return "собери шесть кристаллов памяти и вернись к порталу"
		Objective.DEFEND:
			return "удерживай позицию 90 секунд, переживи атаку и долети до портала"
	return "выполни задачу"

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	var progress := "%d/%d" % [objective_progress, objective_goal]
	if objective_kind == Objective.DEFEND:
		progress = "%02d:%02d" % [int(defense_time) / 60, int(defense_time) % 60]
	var goal := "ПОРТАЛ ОТКРЫТ" if gate_active else "ЦЕЛЬ %s" % progress
	hud.text = "ГЛАВА %d/5 · МИССИЯ %02d/15   %s   %s   КОРПУС %d/3   СЧЁТ %06d" % [_chapter() + 1, mission_index + 1, TITLES[mission_index], goal, lives, score]

func _on_focus_lost() -> void:
	if mode == Mode.PLAYING:
		_show(Mode.PAUSED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		pressed[key.keycode] = key.pressed
		pressed[key.physical_keycode] = key.pressed
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE and mode == Mode.PLAYING:
				_show(Mode.PAUSED)
			elif key.keycode == KEY_ESCAPE and mode == Mode.PAUSED:
				_show(Mode.PLAYING)
			elif key.keycode == KEY_M:
				_toggle_sound()

func _down(key: int) -> bool:
	return bool(pressed.get(key, false))

func _once(key: int) -> bool:
	if not _down(key):
		return false
	pressed[key] = false
	return true

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if ui_hint:
		ui_hint.text = "ЗВУК: %s" % ("ВКЛ" if sound_enabled else "ВЫКЛ")

func _save(checkpoint: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "checkpoint", clampi(checkpoint, 0, MISSION_COUNT))
	cfg.set_value("campaign", "score", score)
	cfg.set_value("campaign", "best_score", best_score)
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		mission_index = clampi(int(cfg.get_value("campaign", "checkpoint", 0)), 0, MISSION_COUNT - 1)
		score = int(cfg.get_value("campaign", "score", 0))
		best_score = int(cfg.get_value("campaign", "best_score", 0))
		campaign_started = mission_index > 0 or score > 0

func _chapter() -> int:
	return clampi(int(float(mission_index) / 3.0), 0, 4)

func _mat(color: Color, roughness: float, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
	return material

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = _mat(color, 0.32, metallic)
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	instance.mesh = mesh
	instance.position = pos
	instance.scale = size
	instance.material_override = _mat(color, 0.24, 0.0, glow)
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.8
	mesh.height = height
	instance.mesh = mesh
	instance.position = pos
	instance.rotation_degrees.x = 90.0
	instance.material_override = _mat(color, 0.35, 0.35)
	parent.add_child(instance)
	return instance
