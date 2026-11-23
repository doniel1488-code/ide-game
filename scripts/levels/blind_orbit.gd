extends "res://scripts/visual_mesh.gd"

const ROUTE := [Vector3(-5, 0, -7), Vector3(-15, 0, -15), Vector3(-5, 0, -22), Vector3(7, 0, -29), Vector3(16, 0, -36)]
const RECOVERY := [Vector3(-19, 0, -10), Vector3(17, 0, -21), Vector3(-10, 0, -30)]
const CONVOY := [Vector3(0, 0, -5), Vector3(-9, 0, -14), Vector3(6, 0, -25), Vector3(12, 0, -35)]
const CARGO_NAMES := ["Регистратор Вейл", "Блок отключения", "Навигационный пакет"]
const NAV := Color("#66e3ff")
const AMBER := Color("#ffbd75")
const RED := Color("#ff7768")
const HULL := Color("#283b54")

var flight
var scenario := 0
var markers: Array[Node3D] = []
var salvage: Array[Node3D] = []
var capsules: Array[Dictionary] = []
var raiders: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var found: Array[int] = []
var tow: Node3D
var tether: MeshInstance3D
var dock: Node3D
var route_step := 0
var leg := 0
var revealed := false
var warned := false
var interference := false
var cooldown := 0.0
var damage_cooldown := 0.0
var previous := Vector3.ZERO
var reticle: MeshInstance3D

func setup(game, index: int) -> void:
	flight = game
	scenario = index
	flight.gate.hide()
	flight.objective_goal = [ROUTE.size(), RECOVERY.size(), 3][scenario]
	match scenario:
		0:
			for i in ROUTE.size():
				var marker := _ring(ROUTE[i], 2.5, NAV, "СИГНАЛ %02d" % (i + 1))
				marker.hide()
				markers.append(marker)
			_rocks([Vector3(-9, 0, -9), Vector3(-11, 0, -12), Vector3(-17, 0, -20), Vector3(-9, 0, -23), Vector3(0, 0, -27), Vector3(3, 0, -30), Vector3(13, 0, -31)])
			flight.gate.position = Vector3(20, 0, -38)
		1:
			dock = _ring(Vector3(4, 0, 4), 3.2, NAV, "ПРИЁМ ГРУЗА")
			flight.gate.position = Vector3(11, 0, 6)
			for i in RECOVERY.size():
				var object := _pod(RECOVERY[i], AMBER, CARGO_NAMES[i], i)
				object.hide()
				salvage.append(object)
			var wreck: Node3D = preload("res://scenes/environment/wreck.tscn").instantiate()
			add_child(wreck)
			wreck.position = Vector3(0, 3, -20)
			_rocks([Vector3(-10, 0, -7), Vector3(5, 0, -13), Vector3(12, 0, -26), Vector3(-5, 0, -23), Vector3(-16, 0, -26)])
			for i in 3:
				var center := Vector3(-9 + i * 10, 0, -11 - i * 8)
				var hazard := _rock(center, i + 20, false)
				var warning := _ring(center, 4.2, RED, "ДРЕЙФ ОБЛОМКОВ")
				warning.rotation.x = -PI / 2
				debris.append({"node": hazard, "center": center, "phase": i * 1.8})
		2:
			flight.gate.position = Vector3(15, 0, -38)
			reticle = _sphere(self, Vector3.ZERO, Vector3(0.23, 0.23, 0.23), NAV, true)
			for i in 3:
				var pod := _pod(CONVOY[0] + Vector3((i - 1) * 3, 0, 0), NAV, "КАПСУЛА %d" % (i + 1), 0)
				capsules.append({"node": pod, "hp": 4, "slot": i, "hit": 0.0})
			_ring(CONVOY[3], 4.0, NAV, "ЗОНА ЭВАКУАЦИИ")
			_rocks([Vector3(6, 0, -8), Vector3(-16, 0, -12), Vector3(-15, 0, -21), Vector3(2, 0, -16), Vector3(14, 0, -23), Vector3(-3, 0, -29)])
			_wave()

func intro() -> void:
	_say(["Орион оставил цепочку тихих сигналов. Нажми Q и веди «Кеплер» через ворота по порядку.", "Это «Меридиан». Q обнаружит груз поблизости, F зацепит его. Синий круг — приёмный док.", "Три капсулы ответили на запрос. Держись рядом с конвоем. Ctrl или ЛКМ — выстрел по курсу."][scenario])

func scan() -> void:
	var pilot: Vector3 = flight.player.position
	flight.expedition.pulse(pilot, NAV, 3.0)
	if flight.gate_active:
		return
	if scenario == 0:
		if interference:
			_say("В эфире всплеск. Подожди просвета и повтори сканирование.")
		elif pilot.distance_to(ROUTE[route_step]) <= 19.0 + flight.expedition.modules[4] * 4.0:
			revealed = true
			_say("Сигнал %d принят. Пройди через световой проём." % (route_step + 1))
		else:
			_say("Импульс слабый. Проверь пеленг на панели и подойди ближе.")
	elif scenario == 1:
		var detected := 0
		for i in salvage.size():
			if i not in found and pilot.distance_to(salvage[i].position) <= 15.0 + flight.expedition.modules[4] * 4.0:
				salvage[i].show()
				detected += 1
		_say("Отмечено находок: %d." % detected if detected else "Здесь одни обломки. Проверь пеленг другого сигнала.")
	else:
		_say("Телеметрия капсул на панели. Дроны подсвечивают цель перед залпом.")

func interact() -> void:
	if scenario != 1 or flight.gate_active:
		return
	if is_instance_valid(tow):
		_release()
		_say("Захват снят. Груз остался на месте.")
		return
	var nearest := 2.8
	for i in salvage.size():
		var item := salvage[i]
		var distance: float = item.position.distance_to(flight.player.position)
		if i not in found and item.visible and distance < nearest:
			nearest = distance
			tow = item
	if not is_instance_valid(tow):
		_say("Для захвата подойди к отмеченной находке.")
		return
	tether = _box(self, Vector3.ZERO, Vector3(0.05, 0.05, 1), NAV)
	tether.material_override = _mat(NAV, 0.2, 0.0, true)
	_say("Захват подтверждён. Управление тяжелее, рывок заблокирован. Веди груз к доку.")

func towing() -> bool:
	return is_instance_valid(tow)

func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	if is_instance_valid(reticle):
		reticle.position = flight.player.position + _heading() * 3.5 + Vector3.UP * 0.45
	if not flight.gate_active:
		match scenario:
			0: _navigate()
			1: _recover(delta)
			2: _escort(delta)
	previous = flight.player.position

func _navigate() -> void:
	var pilot: Vector3 = flight.player.position
	var angle: float = fmod(flight.mission_clock, 8.0)
	interference = angle >= 5.5
	var marker := markers[route_step]
	marker.visible = revealed and (not interference or int(flight.mission_clock * 7.0) % 4 == 0)
	if _crossed(pilot, ROUTE[route_step]):
		if not revealed:
			_say("Проём без подтверждённого сигнала. Вернись за линию ворот и просканируй.")
		else:
			marker.hide()
			route_step += 1
			revealed = false
			warned = false
			_advance(180)
			_say("Пояс пройден. По пеленгу вижу обломки «Меридиана»." if flight.gate_active else "Проход подтверждён. Сканируй следующий участок.")
			return
	for i in range(route_step + 1, ROUTE.size()):
		if not warned and _crossed(pilot, ROUTE[i]):
			warned = true
			_say("Ты пропустил ворота. Пеленг ведёт к предыдущему сигналу.")

func _crossed(pilot: Vector3, point: Vector3) -> bool:
	if previous.z < point.z or pilot.z >= point.z:
		return false
	var fraction := (point.z - previous.z) / (pilot.z - previous.z)
	return absf(lerpf(previous.x, pilot.x, fraction) - point.x) < 2.25

func _recover(delta: float) -> void:
	var pilot: Vector3 = flight.player.position
	for record in debris:
		var rock: Node3D = record["node"]
		var center: Vector3 = record["center"]
		rock.position = center + Vector3(sin(flight.mission_clock * 1.15 + record["phase"]) * 3.1, 0, 0)
		rock.rotate_y(delta * 0.8)
		if damage_cooldown <= 0 and (pilot.distance_to(rock.position) < 1.65 or (towing() and tow.position.distance_to(rock.position) < 1.65)):
			damage_cooldown = 1.3
			if towing():
				_release()
				flight._take_hit()
				if flight.mode == flight.Mode.PLAYING:
					_say("Обломок сорвал захват. Груз можно забрать снова.")
			else:
				flight._take_hit()
	if not towing() or flight.mode != flight.Mode.PLAYING:
		return
	var behind := Vector3(sin(flight.ship.rotation.y), 0, cos(flight.ship.rotation.y))
	tow.position = tow.position.move_toward(pilot + behind * 2.4, 8.0 * delta)
	var cable := tow.position - pilot
	tether.position = pilot + cable * 0.5 + Vector3.UP * 0.22
	tether.scale.z = cable.length()
	if cable.length_squared() > 0.01:
		tether.look_at(tether.global_position + cable)
	if tow.position.distance_to(dock.position) < 2.8 and pilot.distance_to(dock.position) < 4.6:
		var index := salvage.find(tow)
		tow.hide()
		_release()
		found.append(index)
		_advance(240)
		_say("%s принят. В архиве новая запись." % CARGO_NAMES[index])

func _release() -> void:
	tow = null
	if is_instance_valid(tether):
		tether.queue_free()

func commit_archive() -> void:
	for index in archive_entries():
		flight.expedition.remember(index)

func archive_entries() -> Array[int]:
	var entries: Array[int] = []
	for index in found:
		entries.append(6 + index)
	return entries

func _escort(delta: float) -> void:
	var pilot: Vector3 = flight.player.position
	var nearby := false
	for capsule in capsules:
		capsule["hit"] = maxf(0, float(capsule["hit"]) - delta)
		if capsule["hp"] > 0:
			var pod: Node3D = capsule["node"]
			nearby = nearby or pilot.distance_to(pod.position) < 13.0
	if nearby:
		var arrived := true
		for capsule in capsules:
			if capsule["hp"] <= 0:
				continue
			var pod: Node3D = capsule["node"]
			var target: Vector3 = CONVOY[leg + 1] + Vector3((capsule["slot"] - 1) * 3.0, 0, 0)
			pod.position = pod.position.move_toward(target, (2.0 + leg * 0.35) * delta)
			arrived = arrived and pod.position.distance_to(target) < 0.1
		if arrived and raiders.is_empty():
			leg += 1
			if leg == CONVOY.size() - 1:
				for capsule in capsules:
					if capsule["hp"] > 0:
						flight.objective_progress += 1
				found.append(3)
				flight._activate_gate()
				_say("Эвакуация подтверждена: %d из 3. В эфире люди, не повтор записи." % flight.objective_progress)
				return
			_say(["", "Первый поворот пройден. Два дрона заходят с разных сторон.", "Вижу док. Последняя группа идёт прямо на капсулы."][leg])
			_wave()
	for raider in raiders:
		_update_raider(raider, delta)

func _wave() -> void:
	var center: Vector3 = CONVOY[leg].lerp(CONVOY[leg + 1], 0.45)
	for i in leg + 1:
		var drone: Node3D = preload("res://scenes/environment/drone.tscn").instantiate()
		drone.wisp = i % 2 == 1
		add_child(drone)
		drone.position = center + Vector3((1 if i % 2 == 0 else -1) * (8.0 + i * 2.0), 0, -3.0 - i * 3.0)
		var lock := _ring(drone.position, 1.35, RED, "ЗАЛП")
		lock.hide()
		raiders.append({"node": drone, "lock": lock, "hp": 2 + int(i == 2), "windup": 0.0, "rearm": 0.0, "target": i})

func _update_raider(raider: Dictionary, delta: float) -> void:
	var drone: Node3D = raider["node"]
	var lock: Node3D = raider["lock"]
	var target: Dictionary = capsules[raider["target"]]
	if target["hp"] <= 0:
		for candidate in capsules:
			if candidate["hp"] > 0:
				target = candidate
				raider["target"] = candidate["slot"]
				raider["windup"] = 0.0
				break
	if target["hp"] <= 0:
		return
	var pod: Node3D = target["node"]
	var distance := drone.position.distance_to(pod.position)
	if distance > 4.8:
		drone.position = drone.position.move_toward(pod.position, (3.2 + leg * 0.6) * delta)
		drone.look_at(pod.position)
	raider["rearm"] = maxf(0.0, float(raider["rearm"]) - delta)
	if distance <= 5.0 and raider["rearm"] <= 0.0:
		raider["windup"] += delta
		lock.position = pod.position
		lock.show()
		if raider["windup"] >= 1.6:
			lock.hide()
			raider["windup"] = 0.0
			raider["rearm"] = 2.5
			_trace(drone.position + Vector3.UP * 0.45, pod.position + Vector3.UP * 0.45, RED)
			target["hp"] -= 1
			target["hit"] = 0.8
			_say("Капсула %d под огнём. Остаток прочности: %d." % [int(target["slot"]) + 1, target["hp"]])
			if target["hp"] <= 0:
				pod.hide()
				var alive := 0
				for capsule in capsules:
					alive += int(capsule["hp"] > 0)
				if alive < 2:
					flight._show(flight.Mode.LOST)
					flight.ui_text.text = "Конвой потерян. Для эвакуации нужны хотя бы две капсулы."
	else:
		lock.hide()

func fire() -> void:
	if scenario != 2 or cooldown > 0:
		return
	cooldown = 0.37
	var origin: Vector3 = flight.player.position + Vector3.UP * 0.45
	var heading := _heading()
	var reach := 17.0
	var victim := -1
	var end := origin + heading * reach
	for i in raiders.size():
		var drone: Node3D = raiders[i]["node"]
		var aim := drone.position + Vector3.UP * 0.45
		var offset := aim - origin
		var query := PhysicsRayQueryParameters3D.create(origin, aim, 1, [flight.player.get_rid()])
		if offset.length() < reach and offset.normalized().dot(heading) > 0.82 and flight.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			victim = i
			reach = offset.length()
			end = aim
	_trace(origin, end, NAV)
	flight._tone(365, 0.08)
	if victim >= 0:
		var raider := raiders[victim]
		raider["hp"] -= 1 + flight.expedition.modules[3]
		flight.expedition.pulse(end, AMBER, 0.7)
		if raider["hp"] <= 0:
			raider["node"].queue_free()
			raider["lock"].queue_free()
			raiders.remove_at(victim)
			flight.score += 80

func _heading() -> Vector3:
	return Vector3(-sin(flight.ship.rotation.y), 0, -cos(flight.ship.rotation.y))

func hud_line() -> String:
	if flight.gate_active:
		return "Лети к порталу · %s" % _bearing(flight.gate.position)
	match scenario:
		0:
			var state := "ПОМЕХИ" if interference else ("ПРОЙДИ ВОРОТА" if revealed else "Q · СКАНИРОВАТЬ")
			return "%s   |   Ворота %d/%d · %s" % [state, route_step + 1, ROUTE.size(), _bearing(ROUTE[route_step])]
		1:
			if towing():
				return "ГРУЗ НА ТРОСЕ · РЫВОК ОТКЛЮЧЁН   |   Док · %s" % _bearing(dock.position)
			var closest := Vector3.ZERO
			var distance := INF
			for i in salvage.size():
				if i not in found and salvage[i].position.distance_to(flight.player.position) < distance:
					closest = salvage[i].position
					distance = closest.distance_to(flight.player.position)
			return "Q · Поиск   F · Захват   |   Ближайший сигнал · %s" % _bearing(closest)
	var status := PackedStringArray()
	for capsule in capsules:
		status.append("%d/4" % capsule["hp"])
	var lead: Node3D = capsules[0]["node"]
	for capsule in capsules:
		if capsule["hp"] > 0:
			lead = capsule["node"]
			break
	return "МАРШРУТ %d/3 · КАПСУЛЫ %s · ДРОНЫ %d   |   Конвой · %s" % [leg + 1, "  ".join(status), raiders.size(), _bearing(lead.position)]

func _bearing(point: Vector3) -> String:
	var delta: Vector3 = point - flight.player.position
	var direction := "↑" if delta.z < -1.0 else ("↓" if delta.z > 1.0 else "")
	direction += "←" if delta.x < -1.0 else ("→" if delta.x > 1.0 else "")
	return "%s %.0f м" % [direction, delta.length()]

func _advance(points: int) -> void:
	flight.objective_progress += 1
	flight.score += points
	flight._tone(630, 0.14)
	if flight.objective_progress >= flight.objective_goal:
		flight._activate_gate()

func _say(message: String) -> void:
	flight.comms.text = "ЛИРА: «%s»" % message

func _trace(start: Vector3, end: Vector3, color: Color) -> void:
	var trace := _box(self, (start + end) * 0.5, Vector3(0.08, 0.08, start.distance_to(end)), color)
	trace.material_override = _mat(color, 0.15, 0.0, true)
	if start.distance_squared_to(end) > 0.001:
		trace.look_at(end)
	var tween := trace.create_tween()
	tween.tween_interval(0.14)
	tween.tween_callback(trace.queue_free)

func _ring(point: Vector3, radius: float, color: Color, title: String) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = point
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.14
	mesh.outer_radius = radius
	ring.mesh = mesh
	ring.rotation.x = PI / 2
	ring.material_override = _mat(color, 0.18, 0.5, true)
	root.add_child(ring)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side * radius, 0, 0), Vector3(0.36, 1.4, 0.6), HULL, 0.65)
		_box(root, Vector3(side * radius, -0.7, 0), Vector3(0.55, 0.2, 0.9), color, 0.45)
	_label(root, title, color, radius + 0.35)
	return root

func _pod(point: Vector3, color: Color, title: String, variant: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = point
	var body := _cylinder(root, Vector3.ZERO, 0.57 + variant * 0.09, 2.2 - variant * 0.18, HULL)
	body.scale.y = 1.1
	_sphere(root, Vector3(0, 0.1, -1.02), Vector3(1.02, 0.88, 0.98), Color("#3c6172"))
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side * 0.64, 0, 0.25), Vector3(0.26, 0.39, 1.45), HULL.lightened(0.2), 0.55)
		_sphere(root, Vector3(side * 0.63, 0.19, -0.45), Vector3(0.18, 0.22, 0.36), color, true)
	_box(root, Vector3(0, 0.48, 0.15), Vector3(0.32, 0.15, 1.0 - variant * 0.19), color, 0.3)
	_label(root, title, color, 1.15)
	return root

func _label(parent: Node3D, title: String, color: Color, height: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 34
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.position.y = height
	parent.add_child(label)

func _rocks(points: Array) -> void:
	for i in points.size():
		_rock(points[i], i, true)

func _rock(point: Vector3, index: int, solid: bool) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	add_child(root)
	root.position = point
	var visual: Node3D = preload("res://scenes/environment/asteroid.tscn").instantiate()
	visual.seed_value = 218998 + scenario * 100 + index
	visual.dimensions = Vector3(2.25, 1.55, 1.85)
	visual.tint = 0.28
	root.add_child(visual)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.15
		collision.shape = shape
		root.add_child(collision)
	return root
