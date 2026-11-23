extends "res://scripts/visual_mesh.gd"

const SilentEdge = preload("res://scripts/levels/silent_edge.gd")
const Expedition = preload("res://scripts/levels/edge_expedition.gd")
const BlindOrbit = preload("res://scripts/levels/blind_orbit.gd")

enum Mode { MENU, BRIEFING, PLAYING, PAUSED, INTERMISSION, WON, LOST, JOURNAL, UPGRADES }
enum Objective { REPAIR, RECOVER, DEFEND, ORBIT }

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
	"В записи с Ориона Надя Вейл оставила цепочку коротких импульсов. Обычная карта здесь бесполезна: радиошум заливает весь пояс. Лира сможет вычленять сигналы по одному, пока ты ведёшь «Кеплер» между обломками.",
	"Маршрут Вейл вывел нас к корпусу «Меридиана». Три сигнала идут от разнесённых обломков. Если удастся вытащить регистратор, блок отключения и навигационный пакет, мы узнаем, куда ушёл конвой и зачем экипаж обесточил сеть.",
	"В пакете «Меридиана» был резервный курс. На его частоте ответили три спасательные капсулы. Их передатчики меняют код на каждый запрос: это живой ответ. Проводи капсулы до приёмной зоны, пока дроны пытаются закрыть коридор.",
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

var expedition: Expedition
var blind_orbit: BlindOrbit
var orbit_start_score := 0
var archive_page := 0
var mouse_fire := false
var mode := Mode.MENU
var mission_index := 0
var lives := 3
var score := 0
var best_score := 0
var module_rank := 0
var objective_progress := 0
var objective_goal := 3
var objective_kind: int = Objective.REPAIR
var mission_clock := 0.0
var defense_time := 0.0
var dash_remaining := 0.0
var dash_cooldown := 0.0
var invulnerability := 0.0
var dash_direction := Vector3.FORWARD
var gate_active := false
var campaign_started := false
var campaign_completed := false
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
var comms: Label
var orbit: Node3D
var sound_player: AudioStreamPlayer
var tones: Dictionary = {}
var gate: Node3D
var gate_ring: MeshInstance3D
var archive_choice := true
var preview_path := ""
var preview_menu := false
var preview_mode := ""

func _ready() -> void:
	rng.randomize()
	expedition = Expedition.new()
	add_child(expedition)
	expedition.setup(self)
	_setup_window()
	_load_save()
	_build_world()
	_setup_audio()
	_build_ui()
	_show(Mode.MENU)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-preview="):
			preview_path = argument.trim_prefix("--capture-preview=")
		elif argument == "--capture-menu":
			preview_menu = true
		elif argument.begins_with("--capture-mode="):
			preview_mode = argument.trim_prefix("--capture-mode=")
	if not preview_path.is_empty():
		if not preview_menu:
			mission_index = {"navigation": 3, "towing": 4, "convoy": 5}.get(preview_mode, 0)
			_start_mission()
			if not preview_mode.is_empty():
				_configure_preview()
		call_deferred("_capture_preview")

func _exit_tree() -> void:
	if is_instance_valid(sound_player):
		sound_player.stop()

func _capture_preview() -> void:
	if is_instance_valid(blind_orbit):
		_capture_blind_orbit()
	if preview_mode in ["cargo", "combat", "uplink", "workshop", "archive"]:
		await _capture_expedition_demo()
	if preview_mode == "gameplay" and sound_enabled:
		var peak := -200.0
		for sample_index in range(25):
			await get_tree().create_timer(0.025).timeout
			peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(0, 0))
		print("Capture audio peak (dBFS): ", peak)
	if preview_mode != "combat":
		await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(preview_path)
	if result != OK:
		push_error("Could not save gameplay preview image to %s" % preview_path)
	if not preview_mode.is_empty():
		get_tree().quit(0 if result == OK else 1)

func _capture_expedition_demo() -> void:
	await get_tree().process_frame
	match preview_mode:
		"cargo":
			expedition.scan()
			var item: Area3D = expedition.cargo[0]
			player.position = item.position
			camera.reset_to(player.position)
			expedition.tick(0.016)
			expedition.scan()
			_update_hud()
		"combat":
			mission_index = 2
			_start_mission()
			var hunter: Area3D = enemies[0]["node"]
			hunter.position = Vector3(0, 0.5, -8)
			enemies[1]["node"].position = Vector3(5, 0.5, -7)
			expedition.update_enemy(enemies[0], 1.4)
			expedition.tick(0.016)
			expedition.fire()
			_update_hud()
		"uplink":
			var item: Area3D = expedition.cargo[0]
			player.position = item.position
			expedition.tick(0.016)
			player.position = targets[0].position
			expedition.scan()
			expedition.interact()
			expedition.interact()
			expedition.tick(0.1)
			camera.reset_to(player.position)
			_update_hud()
		"workshop":
			for item: Area3D in expedition.cargo.duplicate():
				if item.get_meta("kind") == "alloy":
					player.position = item.position
					expedition.tick(0.016)
					break
			player.position = Vector3.ZERO
			expedition.purchase(0)
			_show(Mode.UPGRADES)
		"archive":
			mission_index = 1
			_start_mission()
			player.position = cores[0].position
			_update_objectives()
			_show(Mode.JOURNAL)

func _capture_blind_orbit() -> void:
	set_physics_process(false)
	match preview_mode:
		"navigation":
			blind_orbit.scan()
			blind_orbit.tick(0.0)
		"towing":
			player.position = blind_orbit.RECOVERY[0] + Vector3(2.4, 0, 0)
			ship.rotation.y = -PI / 2
			blind_orbit.scan()
			blind_orbit.interact()
			blind_orbit.tick(0.1)
		"convoy":
			player.position = Vector3(0, 0, -13)
			for frame in range(45):
				blind_orbit.tick(0.1)
	camera.reset_to(player.position)
	if preview_mode == "towing":
		camera.position = player.position + Vector3(1, 9, 9)
		camera.look_at(player.position + Vector3(-1.2, 0, 0))
	_update_hud()

func _configure_preview() -> void:
	get_window().size = Vector2i(1280, 800)
	if is_instance_valid(blind_orbit):
		return
	if preview_mode == "flight":
		pressed[KEY_W] = true
		pressed[KEY_D] = true
		player.position = Vector3(-10, 0, 7)
		camera.reset_to(player.position)
		return
	set_physics_process(false)
	expedition.tick(0.0)
	_update_hud()
	if preview_mode == "ship":
		camera.position = Vector3(4.0, 3.6, -6.2)
		camera.look_at(Vector3(0, 0.5, 0))
		hud.hide()
		comms.hide()
	elif preview_mode == "relay":
		var point: Vector3 = SilentEdge.RELAYS[0]
		camera.position = point + Vector3(5, 4, -7)
		camera.look_at(point + Vector3.UP * 1.4)
		hud.hide()
		comms.hide()
	elif preview_mode == "asteroids":
		camera.position = Vector3(-19, 6, 13)
		camera.look_at(Vector3(-12, 0, -7))
		hud.hide()
		comms.hide()
	elif preview_mode == "overview":
		camera.position = Vector3(0, 21, 28)
		camera.look_at(Vector3(0, 0, -8))
		hud.hide()
		comms.hide()
	_tone(520.0, 0.3)

func _setup_window() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Lumen Drift — Сигнал сквозь тьму")
		DisplayServer.window_set_min_size(Vector2i(960, 600))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().focus_exited.connect(_on_focus_lost)

func _setup_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)

func _tone(frequency: float, duration: float) -> void:
	if not sound_enabled or not is_instance_valid(sound_player):
		return
	var key := Vector2(frequency, duration)
	var stream := tones.get(key) as AudioStreamWAV
	if stream == null:
		const SAMPLE_RATE := 22050
		var frames := roundi(duration * SAMPLE_RATE)
		var samples := PackedByteArray()
		samples.resize(frames * 2)
		for i in range(frames):
			var time := float(i) / SAMPLE_RATE
			var envelope := minf(time / 0.008, 1.0) * (1.0 - time / duration)
			var sample := roundi(sin(TAU * frequency * time) * envelope * 5500.0)
			samples.encode_s16(i * 2, sample)
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = SAMPLE_RATE
		stream.data = samples
		tones[key] = stream
	sound_player.stream = stream
	sound_player.play()

func _build_world() -> void:
	orbit = preload("res://scenes/environment/orbit.tscn").instantiate()
	add_child(orbit)
	arena = Node3D.new()
	arena.name = "Sector"
	add_child(arena)
	_build_bounds()
	_build_player()
	camera = preload("res://scenes/gameplay/camera_rig.tscn").instantiate() as Camera3D
	add_child(camera)
	camera.reset_to(player.position)
	_build_gate()
	orbit.set_chapter(_chapter(), PALETTE[_chapter()])

func _build_bounds() -> void:
	for side in range(4):
		var wall := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(88, 8, 0.8) if side < 2 else Vector3(0.8, 8, 88)
		collider.shape = shape
		wall.add_child(collider)
		wall.position = Vector3(0, 1, -44.0 if side == 0 else 44.0) if side < 2 else Vector3(-44.0 if side == 2 else 44.0, 1, 0)
		wall.name = "Invisible navigation limit"
		add_child(wall)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Kepler Rescue Ship"
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.88
	capsule.height = 2.1
	collider.shape = capsule
	collider.position.y = 0.55
	player.add_child(collider)
	ship = preload("res://scenes/ships/kepler.tscn").instantiate() as Node3D
	player.add_child(ship)
	add_child(player)

func _build_gate() -> void:
	gate = Node3D.new()
	gate.name = "ExitGate"
	gate.position = Vector3(15.5, 0, 0)
	var ring := MeshInstance3D.new()
	gate_ring = ring
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
	comms = Label.new()
	comms.position = Vector2(28, 750)
	comms.custom_minimum_size = Vector2(1200, 28)
	comms.add_theme_font_size_override("font_size", 15)
	comms.add_theme_color_override("font_color", Color("#8de6d7"))
	root.add_child(comms)
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
	sound_button.text = "Звук: M — %s  ·  WASD/стрелки · Space рывок · Q скан · Ctrl огонь · F действие" % ("вкл" if sound_enabled else "выкл")
	sound_button.flat = true
	sound_button.pressed.connect(_toggle_sound)
	stack.add_child(sound_button)

func _show(next_mode: int) -> void:
	mode = next_mode
	if mode != Mode.PLAYING:
		mouse_fire = false
	ui_panel.visible = mode != Mode.PLAYING
	hud.visible = mode == Mode.PLAYING
	comms.visible = mode == Mode.PLAYING
	if mode == Mode.PLAYING:
		comms.text = "ЛИРА: «Держу маршрут. Следи за сигналом цели»"
	match mode:
		Mode.MENU:
			ui_title.text = "✳  LUMEN DRIFT"
			ui_text.text = "2189 год. Сеть маяков Lumen замолчала. Пилот спасательного корабля и бортовой ИИ Лира отправляются к пятнадцати узлам, чтобы узнать, кто отвечает из темноты."
			ui_hint.text = "5 ГЛАВ · 15 МИССИЙ · КОНТРОЛЬНЫЕ ТОЧКИ"
			ui_button.text = "ПОСМОТРЕТЬ ЭПИЛОГ" if campaign_completed else ("ПРОДОЛЖИТЬ КАМПАНИЮ" if campaign_started else "НАЧАТЬ КАМПАНИЮ")
		Mode.BRIEFING:
			ui_title.text = "%s · МИССИЯ %02d" % [CHAPTERS[_chapter()], mission_index + 1]
			ui_text.text = "%s\n\n%s\n\nЗадача: %s" % [TITLES[mission_index], BRIEFS[mission_index], _objective_text()]
			ui_hint.text = "1 — сохранить голос архива · 2 — удалить эхо" if mission_index == 13 else "После вылета ищи цель по свечению. Прогресс главы сохранится."
			if mission_index != 13:
				ui_hint.text = "МОДУЛЬ %d · ищи цель по свечению. Прогресс главы сохранится." % module_rank
			ui_button.text = "ВЫЛЕТЕТЬ"
		Mode.JOURNAL:
			ui_title.text = "АРХИВ «КЕПЛЕРА»"
			var entries := expedition.archive.duplicate()
			if is_instance_valid(blind_orbit):
				for index in blind_orbit.archive_entries():
					if index not in entries:
						entries.append(index)
			if entries.is_empty():
				ui_text.text = "В журнале пока нет записей. Ищи кристаллы памяти в секторе."
			else:
				archive_page = clampi(archive_page, 0, entries.size() - 1)
				ui_text.text = "ЗАПИСЬ %d/%d\n\n%s" % [archive_page + 1, entries.size(), Expedition.LOGS[entries[archive_page]]]
			ui_hint.text = "← / → листать · J / Esc закрыть"
			ui_button.text = "ВЕРНУТЬСЯ В ПОЛЁТ"
		Mode.UPGRADES:
			ui_title.text = "МАСТЕРСКАЯ «КЕПЛЕРА»"
			var details := ["Сплав: %d. Один модуль стоит 3.\n" % expedition.alloy]
			var gains := ["+1 к корпусу", "+1,15 к скорости", "+0,035 с рывка", "+1 к урону", "+4 м сканирования"]
			for i in range(5):
				details.append("%d · %s · %d/2 · %s за уровень" % [i + 1, Expedition.TITLES[i], expedition.modules[i], gains[i]])
			ui_text.text = "\n".join(details)
			ui_hint.text = "1–5 купить у старта · U / Esc закрыть"
			ui_button.text = "ВЕРНУТЬСЯ В ПОЛЁТ"
		Mode.PAUSED:
			ui_title.text = "ПАУЗА"
			ui_text.text = "%s\n\nГлава %d из 5 · Миссия %d из 15\nСчёт %d · Корпус %d / 3" % [TITLES[mission_index], _chapter() + 1, mission_index + 1, score, lives]
			ui_hint.text = "Esc — продолжить полёт"
			ui_button.text = "ПРОДОЛЖИТЬ"
		Mode.INTERMISSION:
			ui_title.text = "МИССИЯ ЗАВЕРШЕНА"
			ui_text.text = "%s\n\n%s\n\nЛира: «Передача сохранена. Я хочу услышать её ещё раз, когда мы будем в безопасности»." % [TITLES[mission_index], BRIEFS[mission_index]]
			ui_hint.text = "КОНТРОЛЬНАЯ ТОЧКА СОХРАНЕНА · НАГРАДА: +2 СПЛАВА" if _chapter() == 0 else "КОНТРОЛЬНАЯ ТОЧКА СОХРАНЕНА"
			ui_button.text = "СЛЕДУЮЩАЯ МИССИЯ"
		Mode.WON:
			ui_title.text = "СИГНАЛ ДОМА"
			var epilogue := "Лира сохранила голос архива. В нём слышен новый ответ." if archive_choice else "Лира стёрла эхо, чтобы оно больше не звало погибших. В эфире звучит живой ответ."
			ui_text.text = "Пять глав пройдены. В капсулах просыпаются спасённые.\n\n%s\n\nЛУЧШИЙ РЕЗУЛЬТАТ: %d" % [epilogue, best_score]
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
			if campaign_completed:
				_show(Mode.WON)
				return
			if not campaign_started:
				mission_index = 0
				score = 0
				campaign_started = true
			_show(Mode.BRIEFING)
		Mode.BRIEFING:
			_start_mission()
		Mode.PAUSED, Mode.JOURNAL, Mode.UPGRADES:
			_show(Mode.PLAYING)
		Mode.LOST:
			if _chapter() == 1:
				score = orbit_start_score
			if _chapter() == 0:
				var previous := ConfigFile.new()
				previous.load(SAVE_PATH)
				expedition.restore(previous)
			_start_mission()
		Mode.INTERMISSION:
			if mission_index % 3 == 2 and mission_index < MISSION_COUNT - 1:
				module_rank = mini(module_rank + 1, 5)
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
			module_rank = 0
			expedition.restore(ConfigFile.new())
			campaign_completed = false
			campaign_started = true
			_save(0)
			_show(Mode.BRIEFING)

func _start_mission() -> void:
	lives = expedition.hull()
	objective_progress = 0
	mission_clock = 0
	rng.seed = 218900 + mission_index * 7919
	defense_time = 0
	dash_cooldown = 0
	dash_remaining = 0
	invulnerability = 1
	gate_active = false
	player.position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	camera.reset_to(player.position)
	objective_kind = Objective.ORBIT if _chapter() == 1 else mission_index % 3
	objective_goal = 6 if objective_kind == Objective.RECOVER else (90 if objective_kind == Objective.DEFEND else 3 + _chapter())
	if mission_index == 2:
		objective_goal = 1
	_clear_arena()
	orbit.set_chapter(_chapter(), PALETTE[_chapter()])
	if _chapter() == 1:
		orbit_start_score = score
		blind_orbit = BlindOrbit.new()
		arena.add_child(blind_orbit)
		blind_orbit.setup(self, mission_index - 3)
	else:
		_spawn_landmarks()
		_spawn_obstacles(8 + _chapter() * 2)
		_spawn_objectives()
		_spawn_enemies(2 + _chapter())
	if _chapter() == 0:
		expedition.start_sector()
	_show(Mode.PLAYING)
	if is_instance_valid(blind_orbit):
		blind_orbit.intro()
	if _chapter() == 0:
		comms.text = ["ЛИРА: Q сканирует сектор. Ищи ячейки, чтобы запитать три маяка.", "ЛИРА: собери шесть записей. J откроет архив. Сигнал капсулы — дополнительная цель.", "ЛИРА: Hunter готовит залп, Wisp глушит связь. Ctrl — выстрел по курсу, Space — уклонение."][mission_index]

func _clear_arena() -> void:
	blind_orbit = null
	for node in arena.get_children():
		arena.remove_child(node)
		node.queue_free()
	enemies.clear()
	targets.clear()
	cores.clear()
	_build_gate()

func _spawn_landmarks() -> void:
	var accent: Color = PALETTE[_chapter()]
	if _chapter() == 0:
		_build_relay_silhouette(arena, SilentEdge.OUTER_RELAY, accent, true)
		_build_derelict_wreck(arena, SilentEdge.WRECK)
		return
	for i in range(4):
		var x := -13.0 + float(i) * 8.5
		match _chapter():
			1:
				_build_derelict_wreck(arena, Vector3(x, 1.0, -17))
			2:
				_build_relay_silhouette(arena, Vector3(x, 0, -17), accent, false)
			3:
				_build_relay_silhouette(arena, Vector3(x, 0, -17), accent, true)
			4:
				_build_relay_silhouette(arena, Vector3(x, 0, -17), accent, true)

func _build_relay_silhouette(parent: Node3D, position: Vector3, accent: Color, flagship: bool) -> void:
	var relay = preload("res://scenes/environment/relay.tscn").instantiate()
	relay.position = position
	relay.accent = accent
	relay.flagship = flagship
	parent.add_child(relay)

func _build_derelict_wreck(parent: Node3D, position: Vector3) -> void:
	var wreck := preload("res://scenes/environment/wreck.tscn").instantiate() as Node3D
	wreck.position = position
	wreck.rotation = Vector3(0.0, -0.48, -0.16)
	parent.add_child(wreck)

func _spawn_obstacles(count: int) -> void:
	for i in range(count):
		var radius := rng.randf_range(0.9, 1.7)
		var rock := StaticBody3D.new()
		rock.name = "Faceted basalt fragment"
		var visual = preload("res://scenes/environment/asteroid.tscn").instantiate()
		visual.seed_value = 218900 + _chapter() * 100 + i
		visual.tint = rng.randf_range(0.05, 0.42)
		visual.dimensions = Vector3(radius * rng.randf_range(0.82, 1.2), radius, radius * rng.randf_range(0.82, 1.25))
		rock.add_child(visual)
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius * 0.82
		collision.shape = sphere
		rock.add_child(collision)
		if _chapter() == 0 and i < SilentEdge.ROCKS.size():
			rock.position = SilentEdge.ROCKS[i]
		else:
			rock.position = Vector3(rng.randf_range(-17, 17), rng.randf_range(0.7, 2.8), rng.randf_range(-16, 16))
			if rock.position.length() < 5 or rock.position.distance_to(Vector3(15.5, 0, 0)) < 4:
				rock.position.x += 8
		rock.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5))
		arena.add_child(rock)

func _spawn_objectives() -> void:
	if objective_kind == Objective.RECOVER:
		for i in range(objective_goal):
			var pos := SilentEdge.MEMORIES[i] if _chapter() == 0 else Vector3(rng.randf_range(-15, 14), 0.8, rng.randf_range(-14, 14))
			var core := _area("MemoryCore", pos, 0.85)
			var crystal = preload("res://scenes/environment/memory_shard.tscn").instantiate()
			crystal.accent = PALETTE[_chapter()]
			crystal.rotation_degrees = Vector3(12, float(i) * 37.0, 18)
			core.add_child(crystal)
			core.set_meta("log", i)
			cores.append(core)
	elif objective_kind == Objective.REPAIR or mission_index == 2:
		for i in range(objective_goal):
			var pos := SilentEdge.RELAYS[i] if _chapter() == 0 else Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			if pos.length() < 5:
				pos.x += 9
			var target := _area("RelayNode", pos, 1.15)
			_build_relay_silhouette(target, Vector3.ZERO, PALETTE[_chapter()], false)
			if _chapter() == 0:
				_relay_marker(target, i)
				if mission_index == 0:
					target.get_node("RelayMarker").hide()
				else:
					target.get_node("RelayMarker").text = "ОРИОН · канал заглушён"
			targets.append(target)

func _spawn_enemies(count: int) -> void:
	for i in range(count):
		var enemy := Area3D.new()
		enemy.name = "Hunter" if i % 2 == 0 else "Wisp"
		enemy.position = SilentEdge.DRONES[i] if _chapter() == 0 else Vector3(rng.randf_range(-15, 15), rng.randf_range(0.4, 1.2), rng.randf_range(-15, 15))
		if enemy.position.length() < 7:
			enemy.position.x += 11
		var collider := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.98
		collider.shape = sphere
		enemy.add_child(collider)
		var visual = preload("res://scenes/environment/drone.tscn").instantiate()
		visual.wisp = i % 2 == 1
		enemy.add_child(visual)
		arena.add_child(enemy)
		var record := {"node": enemy, "speed": 2.6 + float(_chapter()) * 0.5, "phase": rng.randf_range(0.0, TAU)}
		if _chapter() == 0:
			record.merge({"hp": 3 if i % 2 == 0 else 2, "attack": 1.2 + i * 0.7, "windup": 0.0})
			var threat := Label3D.new()
			threat.name = "Threat"
			threat.text = "%s · %d" % [enemy.name, record["hp"]]
			threat.position.y = 1.25
			threat.font_size = 26
			threat.pixel_size = 0.009
			threat.modulate = Color("#e1acff") if visual.wisp else Color("#ffb18a")
			threat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			enemy.add_child(threat)
		enemies.append(record)

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
	var speed := DASH_SPEED + float(module_rank) * 2.0 if dash_remaining > 0 else PLAYER_SPEED + float(module_rank) * 0.75 + float(expedition.modules[1]) * 1.15
	var towing := is_instance_valid(blind_orbit) and blind_orbit.towing()
	var acceleration := 19.0 if towing else 35.0
	if towing:
		speed *= 0.60
	player.velocity.x = move_toward(player.velocity.x, move.x * speed, acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, move.y * speed, acceleration * delta)
	if dash_remaining > 0:
		player.velocity.x = dash_direction.x * (DASH_SPEED + float(module_rank) * 2.0)
		player.velocity.z = dash_direction.z * (DASH_SPEED + float(module_rank) * 2.0)
	if _chapter() == 0:
		_soft_navigation_limit()
	player.move_and_slide()
	ship.set_thrust(player.velocity.length() / PLAYER_SPEED, dash_remaining > 0.0, delta)
	if player.velocity.length_squared() > 0.2:
		ship.rotation.y = lerp_angle(ship.rotation.y, atan2(-player.velocity.x, -player.velocity.z), 8.0 * delta)
	var lateral := player.velocity.dot(ship.basis.x.normalized())
	var forward := player.velocity.dot(-ship.basis.z.normalized())
	var bank := clampf(lateral * -0.075, -0.32, 0.32)
	ship.rotation.z = lerpf(ship.rotation.z, bank, 1.0 - exp(-7.0 * delta))
	ship.rotation.x = lerpf(ship.rotation.x, clampf(-forward * 0.009, -0.18, 0.18), 1.0 - exp(-6.0 * delta))
	camera.follow(player.position, player.velocity, delta)
	if is_instance_valid(blind_orbit):
		blind_orbit.tick(delta)
		if mode != Mode.PLAYING:
			return
		if _down(KEY_CTRL) or mouse_fire:
			blind_orbit.fire()
	else:
		_update_enemies(delta)
		_update_objectives()
	if _chapter() == 0:
		expedition.tick(delta)
		if _down(KEY_CTRL) or mouse_fire:
			expedition.fire()
	if objective_kind == Objective.DEFEND and mission_index != 2:
		defense_time += delta
		objective_progress = mini(int(defense_time), objective_goal)
		if defense_time >= objective_goal:
			_activate_gate()
	if gate_active and player.position.distance_to(gate.position) < 2.1:
		_finish_mission()
	_update_hud()

func _soft_navigation_limit() -> void:
	var radial := Vector3(player.position.x, 0, player.position.z)
	var distance := radial.length()
	var limit := SilentEdge.NAVIGATION_RADIUS
	if distance < limit - 6.0:
		return
	var outward := radial / distance
	var outward_speed := player.velocity.dot(outward)
	if outward_speed > 0.0:
		var braking := smoothstep(limit - 6.0, limit, distance)
		player.velocity -= outward * outward_speed * braking
	if distance > limit:
		player.position = Vector3(outward.x * limit, player.position.y, outward.z * limit)

func _relay_marker(target: Node3D, index: int) -> void:
	var marker := Label3D.new()
	marker.name = "RelayMarker"
	marker.text = "МАЯК %02d" % (index + 1)
	marker.position.y = 3.8
	marker.font_size = 32
	marker.pixel_size = 0.009
	marker.outline_size = 10
	marker.modulate = Color("#ffe0a7")
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target.add_child(marker)

func _process(_delta: float) -> void:
	if mode != Mode.PLAYING:
		return
	if _once(KEY_SPACE) and dash_cooldown <= 0 and not (is_instance_valid(blind_orbit) and blind_orbit.towing()):
		var move := Vector3(float(_down(KEY_D) or _down(KEY_RIGHT)) - float(_down(KEY_A) or _down(KEY_LEFT)), 0, float(_down(KEY_S) or _down(KEY_DOWN)) - float(_down(KEY_W) or _down(KEY_UP)))
		dash_direction = move.normalized() if move.length_squared() > 0.01 else Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
		dash_remaining = DASH_DURATION + float(expedition.modules[2]) * 0.035
		dash_cooldown = maxf(0.65, DASH_COOLDOWN - float(module_rank) * 0.1)
		_tone(590.0, 0.1)
		invulnerability = maxf(invulnerability, 0.3)
	if _chapter() == 0:
		if _once(KEY_Q):
			expedition.scan()
		if _once(KEY_R):
			expedition.repair()
		if _once(KEY_J):
			_show(Mode.JOURNAL)
			return
		if _once(KEY_U):
			_show(Mode.UPGRADES)
			return
	if is_instance_valid(blind_orbit):
		if _once(KEY_Q):
			blind_orbit.scan()
		if _once(KEY_J):
			_show(Mode.JOURNAL)
			return
	if _once(KEY_F):
		_interact()
	if _once(KEY_ESCAPE):
		_show(Mode.PAUSED)

func _update_enemies(delta: float) -> void:
	for record in enemies:
		var enemy: Area3D = record["node"]
		if not is_instance_valid(enemy):
			continue
		if _chapter() == 0 and record.has("hp"):
			expedition.update_enemy(record, delta)
			continue
		var toward := player.position - enemy.position
		if toward.length_squared() > 0.01:
			var steer := toward.normalized()
			if enemy.name == "Wisp":
				var phase := mission_clock * 1.6 + float(record["phase"])
				steer = (steer + Vector3(cos(phase), 0, sin(phase)) * 0.5).normalized()
			enemy.position += steer * float(record["speed"]) * delta
			enemy.rotation.y = atan2(-steer.x, -steer.z)
		if enemy.position.distance_to(player.position) < 1.35:
			_take_hit()

func _update_objectives() -> void:
	for i in range(cores.size() - 1, -1, -1):
		var core := cores[i]
		if is_instance_valid(core) and core.position.distance_to(player.position) < 1.25:
			if mission_index == 1:
				expedition.remember(int(core.get_meta("log", 0)))
				expedition.pulse(core.position, Color("#abefee"), 1.2)
			core.queue_free()
			cores.remove_at(i)
			objective_progress += 1
			score += 100
			_tone(470.0 + objective_progress * 35.0, 0.1)
			if mission_index != 1:
				comms.text = "ЛИРА: «Фрагмент памяти %d из %d. В записи слышно дыхание экипажа»" % [objective_progress, objective_goal]
	if objective_kind == Objective.RECOVER and objective_progress >= objective_goal:
		_activate_gate()
	if objective_kind == Objective.REPAIR and objective_progress >= objective_goal:
		_activate_gate()

func _interact() -> void:
	if is_instance_valid(blind_orbit):
		blind_orbit.interact()
		return
	if _chapter() == 0:
		expedition.interact()
		return
	if objective_kind != Objective.REPAIR:
		return
	for i in range(targets.size() - 1, -1, -1):
		var target := targets[i]
		if is_instance_valid(target) and target.position.distance_to(player.position) < 2.4:
			target.get_node("relay").activate()
			var marker := target.get_node_or_null("RelayMarker") as Label3D
			if marker:
				marker.text += " · СВЯЗЬ"
				marker.modulate = Color("#bbffd4")
			targets.remove_at(i)
			objective_progress += 1
			score += 150
			_tone(660.0, 0.14)
			comms.text = "ЛИРА: «Узел отвечает. Я записала последние слова дежурного»"
			break
	if objective_progress >= objective_goal:
		_activate_gate()

func _activate_gate() -> void:
	if gate_active:
		return
	gate_active = true
	gate.show()
	gate_ring.material_override = _mat(Color("#84f3d9"), 0.15, 0, true)

func _take_hit() -> void:
	if invulnerability > 0 or mode != Mode.PLAYING:
		return
	lives -= 1
	invulnerability = 1.4 + float(module_rank) * 0.1
	_tone(140.0, 0.2)
	comms.text = "ЛИРА: «Удар по корпусу. Я удержу управление, пока щит перезаряжается»"
	if player.position.length_squared() > 0.01:
		player.velocity = player.position.normalized() * 7.0
	if lives <= 0:
		if _chapter() > 1:
			_save(mission_index)
		_show(Mode.LOST)

func take_hit() -> void:
	_take_hit()

func _finish_mission() -> void:
	if mode != Mode.PLAYING:
		return
	score += 500 + int(maxf(0.0, 120.0 - mission_clock) * 4.0)
	if _chapter() == 0:
		expedition.alloy += 2
	if is_instance_valid(blind_orbit):
		blind_orbit.commit_archive()
	_save(mission_index + 1)
	_show(Mode.INTERMISSION)

func _objective_text() -> String:
	match mission_index:
		0: return "просканируй сектор, найди ячейки, запитай маяки и удержи связь до окончания каждой передачи."
		1: return "извлеки записи экипажа из шести кристаллов. Отметь пропавшую капсулу, если увидишь её сигнал."
		2: return "сбей Hunter и Wisp, очисти канал «Ориона» и удержи связь шесть секунд."
		3: return "найди пять сигналов (Q) и пройди сквозь ворота по порядку."
		4: return "просканируй сектор (Q), зацепи каждую находку (F) и доставь её в док."
		5: return "держись рядом с конвоем и отбивай атаки (Ctrl или ЛКМ). Доставь хотя бы две капсулы."
	match objective_kind:
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
	if objective_kind == Objective.DEFEND and mission_index != 2:
		progress = "%02d:%02d" % [int(defense_time) / 60, int(defense_time) % 60]
	var goal := "ПОРТАЛ ОТКРЫТ" if gate_active else "ЦЕЛЬ %s" % progress
	if mission_index == 2 and not gate_active and expedition.threats < 2:
		goal = "ДРОНЫ %d/2" % expedition.threats
	hud.text = "ГЛАВА %d/5 · МИССИЯ %02d/15   %s   %s   КОРПУС %d/3   СЧЁТ %06d" % [_chapter() + 1, mission_index + 1, TITLES[mission_index], goal, lives, score]
	if _chapter() == 0:
		hud.text = hud.text.replace("КОРПУС %d/3" % lives, "КОРПУС %d/%d" % [lives, expedition.hull()]) + "\n" + expedition.hud_line()

	if is_instance_valid(blind_orbit):
		hud.text = hud.text.replace("КОРПУС %d/3" % lives, "КОРПУС %d/%d" % [lives, expedition.hull()]) + "\n" + blind_orbit.hud_line()

func _on_focus_lost() -> void:
	if preview_path.is_empty() and mode == Mode.PLAYING:
		pressed.clear()
		_show(Mode.PAUSED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_fire = mode == Mode.PLAYING and event.pressed
	if event is InputEventKey:
		var key := event as InputEventKey
		pressed[key.keycode] = key.pressed
		pressed[key.physical_keycode] = key.pressed
		if key.pressed and not key.echo:
			if mode == Mode.JOURNAL:
				if key.keycode == KEY_LEFT:
					archive_page -= 1
					_show(Mode.JOURNAL)
				elif key.keycode == KEY_RIGHT:
					archive_page += 1
					_show(Mode.JOURNAL)
				elif key.keycode == KEY_J or key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER:
					pressed.clear()
					_show(Mode.PLAYING)
				return
			if mode == Mode.UPGRADES:
				if key.keycode >= KEY_1 and key.keycode <= KEY_5:
					expedition.purchase(key.keycode - KEY_1)
					var result := comms.text
					_show(Mode.UPGRADES)
					ui_hint.text = result
				elif key.keycode == KEY_U or key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER:
					pressed.clear()
					_show(Mode.PLAYING)
				return
			if key.keycode == KEY_ESCAPE and mode == Mode.PLAYING:
				_show(Mode.PAUSED)
			elif key.keycode == KEY_ESCAPE and mode == Mode.PAUSED:
				_show(Mode.PLAYING)
			elif key.keycode == KEY_M:
				_toggle_sound()
			elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
				if mode != Mode.PLAYING:
					_primary()
			elif mode == Mode.BRIEFING and mission_index == 13 and (key.keycode == KEY_1 or key.keycode == KEY_KP_1 or key.keycode == KEY_2 or key.keycode == KEY_KP_2):
				archive_choice = key.keycode == KEY_1 or key.keycode == KEY_KP_1
				ui_hint.text = "Выбор: %s" % ("голос архива сохранён" if archive_choice else "эхо будет удалено")

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
	if sound_enabled:
		_tone(660.0, 0.1)

func _save(checkpoint: int) -> void:
	campaign_completed = checkpoint >= MISSION_COUNT
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "complete", campaign_completed)
	cfg.set_value("campaign", "checkpoint", clampi(checkpoint, 0, MISSION_COUNT))
	cfg.set_value("campaign", "score", score)
	cfg.set_value("campaign", "best_score", best_score)
	cfg.set_value("campaign", "module_rank", module_rank)
	expedition.save_to(cfg)
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		expedition.restore(cfg)
		campaign_completed = bool(cfg.get_value("campaign", "complete", false))
		mission_index = clampi(int(cfg.get_value("campaign", "checkpoint", 0)), 0, MISSION_COUNT - 1)
		score = int(cfg.get_value("campaign", "score", 0))
		best_score = int(cfg.get_value("campaign", "best_score", 0))
		module_rank = clampi(int(cfg.get_value("campaign", "module_rank", 0)), 0, 5)
		campaign_started = campaign_completed or mission_index > 0 or score > 0

func _chapter() -> int:
	return clampi(int(float(mission_index) / 3.0), 0, 4)
