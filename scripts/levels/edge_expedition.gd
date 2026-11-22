extends Node3D

const SALVAGE_COST := 3
const TITLES := ["Корпус", "Двигатель", "Рывок", "Пушка", "Сканер"]
const LOGS := [
	"Надя: «Лира, запомни порядок импульсов. Станция начинает отвечать раньше, чем мы отправляем запрос.»",
	"Штурман Орлов: «В журнале был наш позывной. Голос зачитывал его за секунду до моего доклада.»",
	"Лира, резервная копия: «Надя оставила мне правила спасения. Эхо знало их ещё до первого контакта.»",
	"Техник Чен: «Предохранитель сгорел, но аппаратура продолжила передавать на резервной частоте.»",
	"Надя: «Орион слушает нас. Отключить его проще, чем понять, кого мы перестанем слышать.»",
	"Диспетчер: «Конвой ушёл на слепую орбиту. У них нет карты поля обломков. Передайте им нашу.»",
]

var flight
var alloy := 0
var cells := 0
var modules: Array[int] = [0, 0, 0, 0, 0]
var archive: Array[int] = []
var cargo: Array[Area3D] = []
var shots: Array[Dictionary] = []
var cooldown := 0.0
var scan_time := 0.0
var jam_time := 0.0
var uplink_time := 0.0
var aim_marker: MeshInstance3D
var relay: Area3D
var threats := 0

func setup(game) -> void:
	flight = game

func start_sector() -> void:
	cargo.clear()
	shots.clear()
	cooldown = 0.0
	scan_time = 0.0
	jam_time = 0.0
	uplink_time = 0.0
	relay = null
	var reticle := TorusMesh.new()
	reticle.inner_radius = 0.16
	reticle.outer_radius = 0.20
	aim_marker = MeshInstance3D.new()
	aim_marker.mesh = reticle
	aim_marker.material_override = flight._mat(Color("#8bffdf"), 0.18, 0.0, true)
	flight.arena.add_child(aim_marker)
	threats = 0
	if flight.mission_index == 0:
		spawn_cargo("cell", Vector3(-6, 0.4, -4))
		spawn_cargo("cell", Vector3(4, 0.4, -8))
		spawn_cargo("cell", Vector3(12, 0.4, -5))
	spawn_cargo("alloy", Vector3(-5, 0.4, 4), 3)
	spawn_cargo("alloy", Vector3(8, 0.4, 5), 2)
	spawn_cargo("cell", Vector3(-11, 0.4, 3))
	if flight.mission_index == 1:
		spawn_cargo("pod", Vector3(3, 0.5, -5))

func spawn_cargo(kind: String, point: Vector3, amount: int = 1) -> Area3D:
	var item: Area3D = flight._area("Cargo", point, 0.6)
	item.set_meta("kind", kind)
	item.set_meta("amount", amount)
	var color := Color("#efa65e") if kind == "alloy" else (Color("#6aebff") if kind == "cell" else Color("#d6ffd2"))
	var size := Vector3(0.85, 0.38, 0.48) if kind == "alloy" else Vector3(0.39, 0.75, 0.39)
	if kind == "alloy":
		flight._box(item, Vector3.ZERO, size, color)
		flight._box(item, Vector3(0, 0.22, 0), Vector3(0.56, 0.08, 0.4), Color("#342939"), 0.0)
	else:
		flight._cylinder(item, Vector3.ZERO, size.x, size.y, color)
		flight._sphere(item, Vector3(0, 0.1, -0.23), Vector3(0.23, 0.23, 0.23), color, true)
	var name_tag := Label3D.new()
	name_tag.text = "СПЛАВ · ремонт" if kind == "alloy" else ("ЯЧЕЙКА · питание" if kind == "cell" else "КАПСУЛА · аварийный сигнал")
	name_tag.name = "ScanTag"
	name_tag.position.y = 1.15
	name_tag.pixel_size = 0.009
	name_tag.font_size = 28
	name_tag.outline_size = 8
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.modulate = color
	name_tag.hide()
	item.add_child(name_tag)
	cargo.append(item)
	return item

func scan() -> void:
	if jam_time > 0:
		flight.comms.text = "ЛИРА: помеха Wisp. Выйди из поля или сбей дрон."
		return
	scan_time = 4.0 + float(modules[4])
	flight._tone(810.0, 0.16)
	pulse(flight.player.position, Color("#70eaff"), 2.8)
	if flight.mission_index == 0:
		for target: Area3D in flight.targets:
			if target.position.distance_to(flight.player.position) < 15.0 + 4.0 * modules[4]:
				target.set_meta("scanned", true)
				target.get_node("RelayMarker").show()
	flight.comms.text = "ЛИРА: контакты отмечены. Зайди в зону метки, чтобы подобрать груз."

func pulse(point: Vector3, color: Color, scale_factor: float) -> void:
	var effect: MeshInstance3D = flight._sphere(flight.arena, point, Vector3.ONE * 0.25, color, true)
	var tween := effect.create_tween()
	tween.tween_property(effect, "scale", Vector3.ONE * scale_factor, 0.22)
	tween.tween_callback(effect.queue_free)

func tick(delta: float) -> void:
	var direction := Vector3(-sin(flight.ship.rotation.y), 0, -cos(flight.ship.rotation.y))
	aim_marker.position = flight.player.position + direction * 4.2 + Vector3.UP * 0.25
	cooldown = maxf(0.0, cooldown - delta)
	scan_time = maxf(0.0, scan_time - delta)
	jam_time = maxf(0.0, jam_time - delta)
	for i in range(cargo.size() - 1, -1, -1):
		var item := cargo[i]
		if not is_instance_valid(item):
			cargo.remove_at(i)
			continue
		var distance: float = item.position.distance_to(flight.player.position)
		item.rotation.y += delta * 0.7
		item.get_node("ScanTag").visible = distance < 3.2 or (scan_time > 0 and jam_time <= 0 and distance < 15.0 + 4.0 * modules[4])
		if distance < 1.25:
			pickup(item)
			cargo.remove_at(i)
	tick_projectiles(delta)
	if is_instance_valid(relay):
		if relay.position.distance_to(flight.player.position) > 4.5:
			flight.comms.text = "ЛИРА: вернись к передатчику. Канал ждёт."
		elif jam_time <= 0:
			uplink_time -= delta
			if uplink_time <= 0:
				finish_uplink()

func pickup(item: Area3D) -> void:
	var kind: String = item.get_meta("kind")
	var amount: int = item.get_meta("amount")
	match kind:
		"alloy":
			alloy += amount
			flight.comms.text = "СПЛАВ +%d · R чинит корпус, 1–5 покупают модули у старта." % amount
		"cell":
			cells += amount
			flight.dash_cooldown = 0
			flight.comms.text = "ЯЧЕЙКА +%d · рывок готов. Ячейка питает маяк." % amount
		"pod":
			alloy += 2
			flight.comms.text = "ЛИРА: капсула пуста. Транспондер Орлова передан на «Кеплер»."
	flight._tone(940.0 if kind == "cell" else 440.0, 0.12)
	pulse(item.position, Color("#d2fff7"), 1.25)
	item.queue_free()

func remember(index: int) -> void:
	if index not in archive:
		archive.append(index)
	flight.comms.text = LOGS[index] + "  [J — журнал]"

func repair() -> void:
	if alloy >= 1 and flight.lives < hull():
		alloy -= 1
		flight.lives += 1
		flight._tone(612.0, 0.12)
		flight.comms.text = "Корпус восстановлен на 1. Потрачен 1 сплав."
	else:
		flight.comms.text = "Ремонт требует 1 сплав и повреждение корпуса."

func purchase(slot: int) -> void:
	if flight.player.position.length() > 4.5:
		flight.comms.text = "Модули устанавливаются в зоне старта."
		return
	if modules[slot] >= 2 or alloy < SALVAGE_COST:
		flight.comms.text = "%s: уровень %d/2, цена %d сплава." % [TITLES[slot], modules[slot], SALVAGE_COST]
		return
	alloy -= SALVAGE_COST
	modules[slot] += 1
	if slot == 0:
		flight.lives += 1
	flight._tone(720.0, 0.2)
	flight.comms.text = "%s: уровень %d → %d, потрачено %d сплава." % [TITLES[slot], modules[slot] - 1, modules[slot], SALVAGE_COST]

func hull() -> int:
	return 3 + modules[0]

func interact() -> void:
	if is_instance_valid(relay):
		flight.comms.text = "Передача: ещё %.1f с. Не отходи от маяка." % uplink_time
		return
	for target: Area3D in flight.targets:
		if target.position.distance_to(flight.player.position) >= 2.4:
			continue
		if flight.mission_index == 2 and threats < 2:
			flight.comms.text = "ОРИОН: сбей Hunter и Wisp, чтобы очистить канал."
			return
		if flight.mission_index == 0 and not target.get_meta("scanned", false):
			flight.comms.text = "ЛИРА: сначала Q — распознай сигнал маяка."
			return
		var phase: int = target.get_meta("power", 0)
		if flight.mission_index == 0 and phase == 0:
			if cells < 1:
				flight.comms.text = "Маяку нужна ячейка. Q отметит груз в секторе."
				return
			cells -= 1
			target.set_meta("power", 1)
			target.get_node("RelayMarker").text = "ПИТАНИЕ · F настроить канал"
			flight._tone(555.0, 0.13)
			flight.comms.text = "Ячейка подключена. F — синхронизировать частоту."
			return
		relay = target
		uplink_time = 2.0 if flight.mission_index == 0 else 6.0
		target.get_node("RelayMarker").text = "ПЕРЕДАЧА"
		flight.comms.text = "ЛИРА: удерживай позицию до завершения передачи."
		return

func finish_uplink() -> void:
	relay.get_node("relay").activate()
	var marker: Label3D = relay.get_node("RelayMarker")
	marker.text = "СВЯЗЬ ВОССТАНОВЛЕНА"
	marker.modulate = Color("#bbffd4")
	flight.targets.erase(relay)
	relay = null
	flight.objective_progress += 1
	flight.score += 150
	flight._tone(660.0, 0.15)
	if flight.targets.is_empty():
		flight._activate_gate()
		flight.comms.text = "ЛИРА: передача принята. Выход открыт."

func fire() -> void:
	if cooldown > 0:
		return
	cooldown = maxf(0.25, 0.48 - modules[3] * 0.08)
	var direction := Vector3(-sin(flight.ship.rotation.y), 0, -cos(flight.ship.rotation.y))
	var origin: Vector3 = flight.player.position + Vector3.UP * 0.5
	var length := 16.0
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, 1, [flight.player.get_rid()])
	var obstacle: Dictionary = flight.get_world_3d().direct_space_state.intersect_ray(ray)
	if not obstacle.is_empty():
		length = origin.distance_to(obstacle["position"])
	var best: Dictionary = {}
	for enemy in flight.enemies:
		if not enemy.has("hp") or not is_instance_valid(enemy["node"]):
			continue
		var offset: Vector3 = enemy["node"].position - origin
		var along := offset.dot(direction)
		if along > 0 and along < length and (offset - direction * along).length() < 1.25:
			length = along
			best = enemy
	var trace: MeshInstance3D = flight._box(flight.arena, origin + direction * length * 0.5, Vector3(0.065, 0.065, length), Color("#a9fff3"))
	trace.material_override = flight._mat(Color("#8bffdf"), 0.18, 0.0, true)
	trace.look_at(trace.global_position + direction, Vector3.UP)
	var tween := trace.create_tween()
	tween.tween_interval(0.12)
	tween.tween_callback(trace.queue_free)
	flight._tone(360.0, 0.09)
	if not best.is_empty():
		damage_enemy(best, 1 + modules[3])

func damage_enemy(enemy: Dictionary, damage: int) -> void:
	enemy["hp"] -= damage
	var node: Area3D = enemy["node"]
	pulse(node.position, Color("#ffc780"), 1.4)
	if enemy["hp"] <= 0:
		flight.enemies.erase(enemy)
		threats += 1
		flight.score += 200
		spawn_cargo("alloy", node.position, 1)
		node.queue_free()
		flight.comms.text = "Дрон уничтожен. В обломках остался сплав."
	else:
		node.get_node("Threat").text = "%s · %d" % [node.name, enemy["hp"]]

func update_enemy(record: Dictionary, delta: float) -> void:
	var node: Area3D = record["node"]
	var offset: Vector3 = flight.player.position - node.position
	offset.y = 0
	var distance := offset.length()
	if distance < 0.001:
		return
	var forward := offset / distance
	record["attack"] -= delta
	var marker: Label3D = node.get_node("Threat")
	if record["windup"] > 0:
		record["windup"] -= delta
		if record["windup"] <= 0:
			if node.name == "Wisp":
				spawn_threat(record["aim"], Vector3.ZERO, true)
			else:
				var aim: Vector3 = record["aim"] - node.position
				spawn_threat(node.position, aim.normalized() * 13.0, false)
			marker.text = "%s · %d" % [node.name, record["hp"]]
			record["attack"] = 3.2 if node.name == "Wisp" else 2.3
		return
	if record["attack"] <= 0 and distance < 14:
		record["windup"] = 0.8 if node.name == "Wisp" else 0.65
		record["aim"] = Vector3(flight.player.position.x, 0.4, flight.player.position.z)
		if node.name == "Wisp":
			var warning: MeshInstance3D = flight._sphere(flight.arena, record["aim"], Vector3(4.2, 0.055, 4.2), Color("#664483"), true)
			var fade := warning.create_tween()
			fade.tween_property(warning, "scale", Vector3(0.66, 1.0, 0.66), 0.78)
			fade.tween_callback(warning.queue_free)
		marker.text = "ПОМЕХА!" if node.name == "Wisp" else "ЗАЛП!"
		flight._tone(195.0, 0.12)
		pulse(node.position, Color("#ff925c"), 1.4)
		return
	var tangent := Vector3(forward.z, 0, -forward.x)
	var preferred := 8.0 if node.name == "Wisp" else 4.5
	var drive := clampf((distance - preferred) * 0.45, -1.0, 1.0)
	node.position += (forward * drive + tangent * (0.6 if node.name == "Wisp" else -0.42)) * 3.5 * delta
	node.rotation.y = atan2(-forward.x, -forward.z)

func spawn_threat(point: Vector3, velocity: Vector3, jam: bool) -> void:
	var size := Vector3(3.8, 0.12, 3.8) if jam else Vector3(0.38, 0.38, 0.61)
	var model: MeshInstance3D = flight._sphere(flight.arena, point, size, Color("#ab67ec") if jam else Color("#ff7840"), true)
	shots.append({"node": model, "velocity": velocity, "ttl": 2.4 if jam else 1.65, "arm": 0.42 if jam else 0.0, "jam": jam})

func tick_projectiles(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var shot := shots[i]
		var node: MeshInstance3D = shot["node"]
		var before := node.position
		node.position += shot["velocity"] * delta
		shot["ttl"] -= delta
		if not shot["jam"] and not before.is_equal_approx(node.position):
			var ray := PhysicsRayQueryParameters3D.create(before, node.position, 1, [flight.player.get_rid()])
			if not flight.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				node.queue_free()
				shots.remove_at(i)
				continue
		shot["arm"] -= delta
		var distance: float = Geometry3D.get_closest_point_to_segment(flight.player.position + Vector3.UP * 0.35, before, node.position).distance_to(flight.player.position + Vector3.UP * 0.35) if before != node.position else node.position.distance_to(flight.player.position)
		if shot["arm"] <= 0 and distance < (2.1 if shot["jam"] else 0.95) and flight.invulnerability <= 0:
			if shot["jam"]:
				jam_time = 2.8
				flight.comms.text = "ПОМЕХА · сканер и передача временно отключены."
			else:
				flight._take_hit()
			shot["ttl"] = 0.0
		if shot["ttl"] <= 0:
			node.queue_free()
			shots.remove_at(i)

func hud_line() -> String:
	var action := "Q скан · Ctrl огонь · F маяк · R ремонт · J журнал · U модули"
	var nearest := INF
	var bearing := ""
	for target: Area3D in flight.targets:
		if target.get_meta("scanned", false) or flight.mission_index == 2:
			var offset: Vector3 = target.position - flight.player.position
			if offset.length() < nearest:
				nearest = offset.length()
				bearing = "↑" if offset.z < -2 else ("↓" if offset.z > 2 else "")
				bearing += "←" if offset.x < -2 else ("→" if offset.x > 2 else "")
	if is_instance_valid(relay):
		action = "ПЕРЕДАЧА %.1f с · стой рядом с маяком" % uplink_time
	elif nearest < INF:
		action += " · маяк %s %.0f м" % [bearing, nearest]
	if jam_time > 0:
		action += " · ПОМЕХА"
	return "СПЛАВ %d · ЯЧЕЙКИ %d · РЫВОК %s · ПУШКА %s\n%s" % [alloy, cells, "ГОТОВ" if flight.dash_cooldown <= 0 else "%.1f с" % flight.dash_cooldown, "ГОТОВА" if cooldown <= 0 else "%.1f с" % cooldown, action]

func save_to(cfg: ConfigFile) -> void:
	cfg.set_value("expedition", "alloy", alloy)
	cfg.set_value("expedition", "cells", cells)
	cfg.set_value("expedition", "modules", modules)
	cfg.set_value("expedition", "archive", archive)

func restore(cfg: ConfigFile) -> void:
	alloy = maxi(0, int(cfg.get_value("expedition", "alloy", 0)))
	cells = maxi(0, int(cfg.get_value("expedition", "cells", 0)))
	var saved_modules: Array = cfg.get_value("expedition", "modules", [])
	var saved_archive: Array = cfg.get_value("expedition", "archive", [])
	modules.fill(0)
	for i in range(mini(saved_modules.size(), modules.size())):
		modules[i] = clampi(int(saved_modules[i]), 0, 2)
	archive.clear()
	for index in saved_archive:
		if index is int and index >= 0 and index < LOGS.size() and index not in archive:
			archive.append(index)
