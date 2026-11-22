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
var world_environment: WorldEnvironment
var space_sky_material: PanoramaSkyMaterial
var planet_surface: MeshInstance3D
var planet_atmosphere: MeshInstance3D
var planet_material: StandardMaterial3D
var current_sky_chapter := -1
var sound_player: AudioStreamPlayer
var sound_playback: AudioStreamGeneratorPlayback
var tone_frequency := 0.0
var tone_duration := 0.0
var tone_remaining := 0.0
var tone_phase := 0.0
var gate: Node3D
var archive_choice := true
var preview_path := ""
var preview_menu := false

func _ready() -> void:
	rng.randomize()
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
	if not preview_path.is_empty():
		if not preview_menu:
			_start_mission()
		call_deferred("_capture_preview")

func _exit_tree() -> void:
	if is_instance_valid(sound_player):
		sound_player.stop()
	sound_playback = null

func _capture_preview() -> void:
	await get_tree().create_timer(2.0).timeout
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(preview_path)
	if result != OK:
		push_error("Could not save gameplay preview image to %s" % preview_path)

func _setup_window() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Lumen Drift — Сигнал сквозь тьму")
		DisplayServer.window_set_min_size(Vector2i(960, 600))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().focus_exited.connect(_on_focus_lost)

func _build_world() -> void:
	world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	space_sky_material = PanoramaSkyMaterial.new()
	space_sky_material.filter = true
	sky.sky_material = space_sky_material
	env.sky = sky
	env.background_energy_multiplier = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#7584a5")
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color("#c4d4ff")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)

	arena = Node3D.new()
	arena.name = "Sector"
	add_child(arena)
	_build_stars()
	_build_planet()
	_build_bounds()
	_build_player()
	camera = Camera3D.new()
	camera.position = Vector3(0, 21, 22)
	camera.fov = 52
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	_build_gate()
	_update_chapter_backdrop()

func _make_space_panorama(chapter: int) -> Texture2D:
	var width := 512
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var base := Color("#030713")
	var nebula_tint: Color = PALETTE[chapter].lerp(Color("#8370bd"), 0.28)
	for y in range(height):
		var v := float(y) / float(height)
		for x in range(width):
			var u := float(x) / float(width)
			var band_center := 0.50 + 0.10 * sin(u * TAU * 1.7 + sin(u * TAU * 3.0) * 0.4)
			var broad_cloud := exp(-pow((v - band_center) / 0.16, 2.0))
			var wisp := 0.5 + 0.5 * sin(u * TAU * 5.0 + v * 17.0 + sin(v * 21.0))
			var dark_lane := 0.5 + 0.5 * sin(u * TAU * 2.4 - v * 11.0)
			var cloud := clampf(broad_cloud * (0.26 + wisp * 0.48 + dark_lane * 0.16), 0.0, 0.72)
			var pixel := base.lerp(Color("#111a31"), cloud * 0.62)
			pixel = pixel.lerp(nebula_tint, cloud * 0.42)
			image.set_pixel(x, y, pixel)
	var sky_rng := RandomNumberGenerator.new()
	sky_rng.seed = 6619 + chapter * 103
	for i in range(1450):
		var sx := sky_rng.randi_range(0, width - 1)
		var sy := sky_rng.randi_range(0, height - 1)
		var brightness := sky_rng.randf_range(0.36, 0.96)
		var tint := Color("#dce7ff").lerp(Color("#9bc9dc"), sky_rng.randf() * 0.65)
		image.set_pixel(sx, sy, tint * brightness)
		if i % 55 == 0:
			image.set_pixel((sx + 1) % width, sy, tint * brightness * 0.32)
	return ImageTexture.create_from_image(image)

func _make_planet_texture(chapter: int) -> Texture2D:
	var width := 512
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 93017 + chapter * 187
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	for y in range(height):
		var v := float(y) / float(height)
		var latitude_band := sin(v * TAU * 13.0 + sin(v * TAU * 3.0) * 0.55)
		for x in range(width):
			var u := float(x) / float(width)
			var cloud := noise.get_noise_2d(float(x), float(y) * 1.25)
			var bands := latitude_band * 0.22 + cloud * 0.62
			var color := Color("#273d55").lerp(Color("#73859a"), clampf(0.46 + bands, 0.0, 1.0))
			color = color.lerp(PALETTE[chapter].darkened(0.12), clampf(cloud * 0.20, 0.0, 0.20))
			var polar := clampf(absf(v - 0.5) * 2.0, 0.0, 1.0)
			color = color.lerp(Color("#a9c4d1"), smoothstep(0.80, 0.99, polar) * 0.72)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _update_chapter_backdrop() -> void:
	var chapter := _chapter()
	if chapter == current_sky_chapter:
		return
	current_sky_chapter = chapter
	space_sky_material.panorama = _make_space_panorama(chapter)
	planet_material.albedo_texture = _make_planet_texture(chapter)
	var accent: Color = PALETTE[chapter]
	var atmosphere_material := planet_atmosphere.material_override as StandardMaterial3D
	atmosphere_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.16)
	atmosphere_material.emission_color = accent.lightened(0.25)

func _build_stars() -> void:
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.045
	star_mesh.height = 0.09
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = star_mesh
	instances.instance_count = 360
	for i in range(instances.instance_count):
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.01:
			direction = Vector3.UP
		direction = direction.normalized()
		var distance := rng.randf_range(62.0, 118.0)
		var scale := rng.randf_range(0.65, 1.8)
		instances.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), direction * distance))
	var starfield := MultiMeshInstance3D.new()
	starfield.name = "NearStarfield"
	starfield.multimesh = instances
	starfield.material_override = _mat(Color("#a9c9e8"), 0.2, 0, true)
	add_child(starfield)

func _build_planet() -> void:
	var planet := Node3D.new()
	planet.name = "Nacre — distant moon"
	planet.position = Vector3(27, -34, -92)
	add_child(planet)
	planet_surface = MeshInstance3D.new()
	var globe := SphereMesh.new()
	globe.radius = 20.0
	globe.height = 40.0
	globe.radial_segments = 48
	globe.rings = 32
	planet_surface.mesh = globe
	planet_surface.name = "BandedOcean"
	planet_material = StandardMaterial3D.new()
	planet_material.albedo_color = Color("#537189")
	planet_material.roughness = 0.9
	planet_material.metallic = 0.04
	planet_material.emission_enabled = true
	planet_material.emission = Color("#243750")
	planet_material.emission_energy_multiplier = 0.16
	planet_material.albedo_texture = _make_planet_texture(0)
	planet_surface.material_override = planet_material
	planet.add_child(planet_surface)
	planet_atmosphere = MeshInstance3D.new()
	var halo := SphereMesh.new()
	halo.radius = 20.8
	halo.height = 41.6
	halo.radial_segments = 48
	halo.rings = 32
	planet_atmosphere.mesh = halo
	planet_atmosphere.name = "BlueAtmosphere"
	var atmosphere_material := StandardMaterial3D.new()
	atmosphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	atmosphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmosphere_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	atmosphere_material.albedo_color = Color("#79bce9", 0.16)
	atmosphere_material.emission_enabled = true
	atmosphere_material.emission = Color("#427eb2")
	atmosphere_material.emission_energy_multiplier = 0.34
	planet_atmosphere.material_override = atmosphere_material
	planet.add_child(planet_atmosphere)

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
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = 0.55
	player.add_child(collider)
	ship = Node3D.new()
	ship.name = "Kepler"
	player.add_child(ship)
	_add_kepler_hull(ship)
	var ivory := _mat(Color("#b7c7cf"), 0.38, 0.48)
	var wing_metal := _mat(Color("#405a6d"), 0.42, 0.62)
	var trim := _mat(Color("#d3a574"), 0.34, 0.72)
	var glass := _mat(Color("#52c4df"), 0.16, 0.32, true)
	_add_wing(ship, false, wing_metal, trim)
	_add_wing(ship, true, wing_metal, trim)
	_box(ship, Vector3(0, 0.97, 0.05), Vector3(0.10, 0.12, 1.35), Color("#dcae76"), 0.62)
	var cockpit := _sphere(ship, Vector3(0, 0.91, -0.67), Vector3(0.56, 0.30, 0.86), Color("#69d8e5"), true)
	cockpit.material_override = glass
	for side in [-1.0, 1.0]:
		var engine := _cylinder(ship, Vector3(side * 1.18, 0.46, 1.05), 0.31, 1.02, Color("#1d2e3b"))
		engine.rotation_degrees.x = 90
		var nozzle := _cylinder(ship, Vector3(side * 1.18, 0.46, 1.55), 0.24, 0.22, Color("#71828b"))
		nozzle.rotation_degrees.x = 90
		_sphere(ship, Vector3(side * 1.18, 0.46, 1.72), Vector3(0.18, 0.14, 0.10), Color("#7ce7ee"), true)
		_box(ship, Vector3(side * 1.16, 0.28, 0.20), Vector3(0.12, 0.12, 1.2), Color("#e2b77e"), 0.55)
		_box(ship, Vector3(side * 0.72, 0.38, 0.95), Vector3(0.64, 0.16, 0.44), Color("#8096a1"), 0.52)
		_sphere(ship, Vector3(side * 0.38, 0.39, 0.75), Vector3(0.08, 0.08, 0.08), Color("#ffbd76"), true)
	ship.scale = Vector3.ONE * 1.12
	add_child(player)

func _add_kepler_hull(parent: Node3D) -> void:
	var profiles: Array[Vector3] = [
		Vector3(0.10, 0.10, -2.35),
		Vector3(0.38, 0.22, -1.55),
		Vector3(0.54, 0.31, -0.35),
		Vector3(0.46, 0.28, 0.78),
		Vector3(0.30, 0.20, 1.38)
	]
	var sides := 8
	var rings: Array = []
	for profile in profiles:
		var ring: Array[Vector3] = []
		for side in range(sides):
			var angle := TAU * float(side) / float(sides) + PI / 8.0
			ring.append(Vector3(sin(angle) * profile.x, 0.58 + cos(angle) * profile.y, profile.z))
		rings.append(ring)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var nose := Vector3(0, 0.58, -2.66)
	var tail := Vector3(0, 0.58, 1.58)
	for side in range(sides):
		var next := (side + 1) % sides
		tool.add_vertex(nose)
		tool.add_vertex(rings[0][next])
		tool.add_vertex(rings[0][side])
		tool.add_vertex(tail)
		tool.add_vertex(rings[profiles.size() - 1][side])
		tool.add_vertex(rings[profiles.size() - 1][next])
	for section in range(profiles.size() - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			var a: Vector3 = rings[section][side]
			var b: Vector3 = rings[section][next]
			var d: Vector3 = rings[section + 1][side]
			var e: Vector3 = rings[section + 1][next]
			tool.add_vertex(a)
			tool.add_vertex(b)
			tool.add_vertex(e)
			tool.add_vertex(a)
			tool.add_vertex(e)
			tool.add_vertex(d)
	tool.generate_normals()
	var hull := MeshInstance3D.new()
	hull.name = "Faceted rescue fuselage"
	hull.mesh = tool.commit()
	var hull_material := _mat(Color("#9caeb9"), 0.34, 0.58)
	hull_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.material_override = hull_material
	parent.add_child(hull)

func _add_wing(parent: Node3D, mirrored: bool, material: StandardMaterial3D, trim: StandardMaterial3D) -> void:
	var sign := -1.0 if mirrored else 1.0
	var root_front := Vector3(sign * 0.42, 0.50, -0.62)
	var tip_front := Vector3(sign * 2.48, 0.26, 0.42)
	var tip_back := Vector3(sign * 2.05, 0.25, 1.42)
	var root_back := Vector3(sign * 0.44, 0.49, 1.18)
	var points := [root_front, tip_front, tip_back, root_back]
	var triangles: Array[Vector3] = [
		points[0], points[1], points[2], points[0], points[2], points[3],
		points[0] + Vector3(0, -0.14, 0), points[2] + Vector3(0, -0.14, 0), points[1] + Vector3(0, -0.14, 0),
		points[0] + Vector3(0, -0.14, 0), points[3] + Vector3(0, -0.14, 0), points[2] + Vector3(0, -0.14, 0)
	]
	var wing_mesh := _mesh_from_triangles(triangles)
	var wing := MeshInstance3D.new()
	wing.name = "Port rescue wing" if mirrored else "Starboard rescue wing"
	wing.mesh = wing_mesh
	wing.material_override = material
	parent.add_child(wing)
	var strip_start := Vector3(sign * 0.72, 0.35, 0.87)
	var strip_end := Vector3(sign * 1.98, 0.29, 1.18)
	var strip := _box(parent, (strip_start + strip_end) * 0.5, Vector3(0.08, 0.045, strip_start.distance_to(strip_end)), Color("#d3a574"), 0.72)
	strip.rotation.y = atan2(strip_end.x - strip_start.x, strip_end.z - strip_start.z)
	for index in range(2):
		var pad_x := sign * (0.92 + float(index) * 0.38)
		_box(parent, Vector3(pad_x, 0.43, 0.27), Vector3(0.16, 0.10, 0.36), Color("#263946"), 0.5)

func _mesh_from_triangles(vertices: Array[Vector3]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for vertex in vertices:
		tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()

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
	sound_button.text = "Звук: M — %s  ·  WASD/стрелки · Space рывок · F действие · Esc пауза" % ("вкл" if sound_enabled else "выкл")
	sound_button.flat = true
	sound_button.pressed.connect(_toggle_sound)
	stack.add_child(sound_button)

func _show(next_mode: int) -> void:
	mode = next_mode
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
		Mode.PAUSED:
			_show(Mode.PLAYING)
		Mode.LOST:
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
			campaign_completed = false
			campaign_started = true
			_save(0)
			_show(Mode.BRIEFING)

func _start_mission() -> void:
	lives = 3
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
	objective_kind = mission_index % 3
	objective_goal = 6 if objective_kind == Objective.RECOVER else (90 if objective_kind == Objective.DEFEND else 3 + _chapter())
	_clear_arena()
	_update_chapter_backdrop()
	_spawn_landmarks()
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

func _spawn_landmarks() -> void:
	var accent: Color = PALETTE[_chapter()]
	if _chapter() == 0:
		_build_relay_silhouette(arena, Vector3(-12, 0, -15), accent, true)
		_build_derelict_wreck(arena, Vector3(12, 1.5, -17))
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
	var relay := Node3D.new()
	relay.name = "Outer relay mast"
	relay.position = position
	parent.add_child(relay)
	_add_cylinder_y(relay, Vector3(0, 0.25, 0), 1.2 if flagship else 0.85, 0.5, Color("#344858"))
	_add_cylinder_y(relay, Vector3(0, 1.35, 0), 0.16, 2.2, Color("#758795"))
	_add_cylinder_y(relay, Vector3(0, 2.55, 0), 0.28, 0.22, Color("#b7c5c9"))
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.74 if flagship else 0.55
	ring_mesh.outer_radius = 0.88 if flagship else 0.68
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 2.15, 0)
	ring.rotation_degrees.x = 90
	ring.material_override = _mat(accent.lightened(0.15), 0.3, 0.4, true)
	relay.add_child(ring)
	for side in [-1.0, 1.0]:
		var panel := _box(relay, Vector3(side * 1.24, 1.05, 0), Vector3(0.92, 0.10, 0.68), Color("#293e55"), 0.62)
		panel.rotation.z = -side * 0.08
		for cell in range(3):
			_box(relay, Vector3(side * (0.98 + float(cell) * 0.25), 1.12, 0), Vector3(0.045, 0.025, 0.58), Color("#78aabd"), 0.35)
	_sphere(relay, Vector3(0, 2.76, 0), Vector3(0.20, 0.26, 0.20), accent, true)
	_add_cylinder_y(relay, Vector3(0, 3.15, 0), 0.045, 0.62, Color("#becbd0"))
	var cap := _sphere(relay, Vector3(0, 3.48, 0), Vector3(0.12, 0.12, 0.12), Color("#eff2dc"), true)
	cap.material_override = _mat(Color("#e5dfba"), 0.22, 0.2, true)

func _build_derelict_wreck(parent: Node3D, position: Vector3) -> void:
	var wreck := Node3D.new()
	wreck.name = "Stranded convoy fragment"
	wreck.position = position
	wreck.rotation.y = -0.48
	wreck.rotation.z = -0.16
	parent.add_child(wreck)
	_box(wreck, Vector3(0, 0.15, 0), Vector3(5.6, 0.58, 1.25), Color("#273948"), 0.62)
	_box(wreck, Vector3(0, 0.49, -0.45), Vector3(1.35, 0.18, 1.55), Color("#516778"), 0.58)
	for side in [-1.0, 1.0]:
		_box(wreck, Vector3(side * 1.4, 0.28, 0.22), Vector3(1.72, 0.10, 1.28), Color("#354a59"), 0.66)
		_box(wreck, Vector3(side * 2.2, 0.36, 0.10), Vector3(0.28, 0.08, 0.72), Color("#b57652"), 0.45)
		var engine_glow := _sphere(wreck, Vector3(side * 0.48, 0.19, 0.82), Vector3(0.16, 0.16, 0.12), Color("#f39a63"), true)
		engine_glow.material_override = _mat(Color("#d97451"), 0.3, 0.15, true)

func _add_cylinder_y(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.82
	mesh.height = height
	mesh.radial_segments = 8
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = _mat(color, 0.45, 0.55)
	parent.add_child(instance)
	return instance

func _spawn_obstacles(count: int) -> void:
	var chapter_one_layout: Array[Vector3] = [
		Vector3(-11, 1.1, -7), Vector3(-6, 2.2, 11), Vector3(9, 1.0, -8),
		Vector3(12, 2.5, 7), Vector3(-16, 1.3, 6), Vector3(3, 1.0, 15),
		Vector3(-4, 2.8, -12), Vector3(7, 1.6, 13), Vector3(16, 1.2, -10)
	]
	for i in range(count):
		var radius := rng.randf_range(0.9, 1.7)
		var rock := StaticBody3D.new()
		rock.name = "Faceted basalt fragment"
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = _make_asteroid_mesh(218900 + _chapter() * 100 + i)
		var rock_material := _mat(Color("#46535e").lerp(Color("#7b6d62"), rng.randf_range(0.05, 0.42)), 0.94, 0.12)
		rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_node.material_override = rock_material
		mesh_node.scale = Vector3(radius * rng.randf_range(0.82, 1.2), radius * rng.randf_range(0.76, 1.18), radius * rng.randf_range(0.82, 1.25))
		rock.add_child(mesh_node)
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius * 0.82
		collision.shape = sphere
		rock.add_child(collision)
		if _chapter() == 0 and i < chapter_one_layout.size():
			rock.position = chapter_one_layout[i]
		else:
			rock.position = Vector3(rng.randf_range(-17, 17), rng.randf_range(0.7, 2.8), rng.randf_range(-16, 16))
			if rock.position.length() < 5 or rock.position.distance_to(Vector3(15.5, 0, 0)) < 4:
				rock.position.x += 8
		rock.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5))
		arena.add_child(rock)

func _make_asteroid_mesh(seed_value: int) -> ArrayMesh:
	var mesh_rng := RandomNumberGenerator.new()
	mesh_rng.seed = seed_value
	var segment_count := 9
	var ring_angles: Array[float] = [0.55, 1.42, 2.28]
	var rings: Array = []
	for ring_index in range(ring_angles.size()):
		var ring: Array[Vector3] = []
		for segment in range(segment_count):
			var angle := TAU * float(segment) / float(segment_count) + float(ring_index % 2) * 0.12
			var radius := mesh_rng.randf_range(0.78, 1.18)
			var latitude: float = ring_angles[ring_index]
			ring.append(Vector3(sin(latitude) * cos(angle) * radius, cos(latitude) * radius, sin(latitude) * sin(angle) * radius))
		rings.append(ring)
	var top := Vector3(0, mesh_rng.randf_range(0.82, 1.14), 0)
	var bottom := Vector3(0, -mesh_rng.randf_range(0.82, 1.14), 0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for segment in range(segment_count):
		var next := (segment + 1) % segment_count
		tool.add_vertex(top)
		tool.add_vertex(rings[0][segment])
		tool.add_vertex(rings[0][next])
		for ring_index in range(rings.size() - 1):
			var upper_a: Vector3 = rings[ring_index][segment]
			var upper_b: Vector3 = rings[ring_index][next]
			var lower_a: Vector3 = rings[ring_index + 1][segment]
			var lower_b: Vector3 = rings[ring_index + 1][next]
			tool.add_vertex(upper_a)
			tool.add_vertex(lower_b)
			tool.add_vertex(upper_b)
			tool.add_vertex(upper_a)
			tool.add_vertex(lower_a)
			tool.add_vertex(lower_b)
		tool.add_vertex(bottom)
		tool.add_vertex(rings[rings.size() - 1][next])
		tool.add_vertex(rings[rings.size() - 1][segment])
	tool.generate_normals()
	return tool.commit()

func _spawn_objectives() -> void:
	if objective_kind == Objective.RECOVER:
		for i in range(objective_goal):
			var core := _area("MemoryCore", Vector3(rng.randf_range(-15, 14), 0.8, rng.randf_range(-14, 14)), 0.85)
			var crystal := Node3D.new()
			crystal.name = "Six-sided memory shard"
			crystal.rotation_degrees = Vector3(12, float(i) * 37.0, 18)
			core.add_child(crystal)
			var upper := CylinderMesh.new()
			upper.top_radius = 0.0
			upper.bottom_radius = 0.43
			upper.height = 0.72
			upper.radial_segments = 6
			var shard_a := MeshInstance3D.new()
			shard_a.mesh = upper
			shard_a.position.y = 0.30
			shard_a.material_override = _mat(PALETTE[_chapter()].lightened(0.22), 0.16, 0.1, true)
			crystal.add_child(shard_a)
			var lower := CylinderMesh.new()
			lower.top_radius = 0.43
			lower.bottom_radius = 0.0
			lower.height = 0.72
			lower.radial_segments = 6
			var shard_b := MeshInstance3D.new()
			shard_b.mesh = lower
			shard_b.position.y = -0.30
			shard_b.material_override = _mat(Color("#bdeaf1"), 0.12, 0.1, true)
			crystal.add_child(shard_b)
			var band := MeshInstance3D.new()
			var band_mesh := TorusMesh.new()
			band_mesh.inner_radius = 0.28
			band_mesh.outer_radius = 0.34
			band.mesh = band_mesh
			band.material_override = _mat(Color("#e8fcff"), 0.13, 0.1, true)
			crystal.add_child(band)
			cores.append(core)
	else:
		for i in range(objective_goal):
			var pos := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			if pos.length() < 5:
				pos.x += 9
			var target := _area("RelayNode", pos, 1.15)
			_build_relay_silhouette(target, Vector3.ZERO, PALETTE[_chapter()], false)
			targets.append(target)

func _spawn_enemies(count: int) -> void:
	for i in range(count):
		var enemy := Area3D.new()
		enemy.name = "Hunter" if i % 2 == 0 else "Wisp"
		enemy.position = Vector3(rng.randf_range(-15, 15), rng.randf_range(0.4, 1.2), rng.randf_range(-15, 15))
		if enemy.position.length() < 7:
			enemy.position.x += 11
		var collider := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.98
		collider.shape = sphere
		enemy.add_child(collider)
		_build_drone_model(enemy, enemy.name == "Wisp", i)
		arena.add_child(enemy)
		enemies.append({"node": enemy, "speed": 2.6 + float(_chapter()) * 0.5, "phase": rng.randf_range(0.0, TAU)})

func _build_drone_model(enemy: Area3D, wisp: bool, variant: int) -> void:
	var hull_color := Color("#704c55") if wisp else Color("#68747c")
	var sensor_color := Color("#ce9fff") if wisp else Color("#ffb36c")
	var core := _sphere(enemy, Vector3(0, 0.08, 0), Vector3(0.68, 0.52, 0.72), hull_color, false)
	core.material_override = _mat(hull_color, 0.54, 0.72)
	var eye := _sphere(enemy, Vector3(0, 0.14, -0.47), Vector3(0.28, 0.22, 0.20), sensor_color, true)
	eye.material_override = _mat(sensor_color, 0.18, 0.08, true)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.58 if wisp else 0.42
	ring_mesh.outer_radius = 0.72 if wisp else 0.54
	ring.mesh = ring_mesh
	ring.rotation_degrees.x = 90
	ring.rotation_degrees.z = float(variant) * 14.0
	ring.material_override = _mat(Color("#c295d6") if wisp else Color("#8696a0"), 0.28, 0.68)
	enemy.add_child(ring)
	for side in [-1.0, 1.0]:
		var arm := _box(enemy, Vector3(side * 0.70, -0.04, 0.20), Vector3(0.78, 0.16, 0.22), Color("#384853"), 0.72)
		arm.rotation.y = side * -0.24
		_box(enemy, Vector3(side * 1.04, -0.07, -0.02), Vector3(0.14, 0.48, 0.18), Color("#8a6b67"), 0.52)
		var claw := _cylinder(enemy, Vector3(side * 1.10, -0.24, -0.12), 0.08, 0.40, Color("#d3a983"))
		claw.rotation_degrees.x = 62
	if wisp:
		for spoke in range(3):
			var angle := TAU * float(spoke) / 3.0
			_box(enemy, Vector3(cos(angle) * 0.86, 0.16, sin(angle) * 0.86), Vector3(0.48, 0.10, 0.12), Color("#624d78"), 0.45).rotation.y = -angle

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
	var speed := DASH_SPEED + float(module_rank) * 2.0 if dash_remaining > 0 else PLAYER_SPEED + float(module_rank) * 0.75
	player.velocity.x = move_toward(player.velocity.x, move.x * speed, 35.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, move.y * speed, 35.0 * delta)
	if dash_remaining > 0:
		player.velocity.x = dash_direction.x * (DASH_SPEED + float(module_rank) * 2.0)
		player.velocity.z = dash_direction.z * (DASH_SPEED + float(module_rank) * 2.0)
	player.move_and_slide()
	if player.velocity.length_squared() > 0.2:
		ship.rotation.y = lerp_angle(ship.rotation.y, atan2(-player.velocity.x, -player.velocity.z), 8.0 * delta)
	camera.position = camera.position.lerp(player.position + Vector3(0, 21, 22), 4.0 * delta)
	camera.look_at(player.position + Vector3(player.velocity.x * 0.18, 0, -2.6 + player.velocity.z * 0.12), Vector3.UP)
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
	_pump_audio()
	if mode != Mode.PLAYING:
		return
	if _once(KEY_SPACE) and dash_cooldown <= 0:
		var move := Vector3(float(_down(KEY_D) or _down(KEY_RIGHT)) - float(_down(KEY_A) or _down(KEY_LEFT)), 0, float(_down(KEY_S) or _down(KEY_DOWN)) - float(_down(KEY_W) or _down(KEY_UP)))
		dash_direction = move.normalized() if move.length_squared() > 0.01 else Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
		dash_remaining = DASH_DURATION
		dash_cooldown = maxf(0.65, DASH_COOLDOWN - float(module_rank) * 0.1)
		_tone(590.0, 0.1)
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
			core.queue_free()
			cores.remove_at(i)
			objective_progress += 1
			score += 100
			_tone(470.0 + objective_progress * 35.0, 0.1)
		comms.text = "ЛИРА: «Фрагмент памяти %d из %d. В записи слышно дыхание экипажа»" % [objective_progress, objective_goal]
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
			_tone(660.0, 0.14)
			comms.text = "ЛИРА: «Узел отвечает. Я записала последние слова дежурного»"
			break
	if objective_progress >= objective_goal:
		_activate_gate()

func _activate_gate() -> void:
	if gate_active:
		return
	gate_active = true
	var mesh := gate.get_child(0) as MeshInstance3D
	mesh.material_override = _mat(Color("#84f3d9"), 0.15, 0, true)

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
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		campaign_completed = bool(cfg.get_value("campaign", "complete", false))
		mission_index = clampi(int(cfg.get_value("campaign", "checkpoint", 0)), 0, MISSION_COUNT - 1)
		score = int(cfg.get_value("campaign", "score", 0))
		best_score = int(cfg.get_value("campaign", "best_score", 0))
		module_rank = clampi(int(cfg.get_value("campaign", "module_rank", 0)), 0, 5)
		campaign_started = campaign_completed or mission_index > 0 or score > 0

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
