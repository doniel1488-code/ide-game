extends "res://scripts/visual_mesh.gd"

var exhausts: Array[MeshInstance3D] = []
var thrust := 0.0

func set_thrust(speed: float, dashing: bool, delta: float) -> void:
	var desired := 1.65 if dashing else clampf(speed, 0.0, 1.0)
	thrust = lerpf(thrust, desired, 1.0 - exp(-11.0 * delta))
	for exhaust in exhausts:
		exhaust.scale.z = 0.19 + 0.65 * thrust
		exhaust.position.z = 1.67 + exhaust.scale.z * 0.42

func _ready() -> void:
	_add_kepler_hull(self)
	var wing_metal := _mat(Color("#405a6d"), 0.42, 0.62)
	var glass := _mat(Color("#52c4df"), 0.16, 0.32, true)
	_add_wing(self, false, wing_metal)
	_add_wing(self, true, wing_metal)
	_box(self, Vector3(0, 0.97, 0.05), Vector3(0.10, 0.12, 1.35), Color("#dcae76"), 0.62)
	var cockpit := _sphere(self, Vector3(0, 0.91, -0.67), Vector3(0.56, 0.30, 0.86), Color("#69d8e5"), true)
	cockpit.material_override = glass
	for side in [-1.0, 1.0]:
		var engine := _cylinder(self, Vector3(side * 1.18, 0.46, 1.05), 0.31, 1.02, Color("#1d2e3b"))
		engine.rotation_degrees.x = 90
		var nozzle := _cylinder(self, Vector3(side * 1.18, 0.46, 1.55), 0.24, 0.22, Color("#71828b"))
		nozzle.rotation_degrees.x = 90
		var exhaust := _sphere(self, Vector3(side * 1.18, 0.46, 1.75), Vector3(0.18, 0.14, 0.19), Color("#7ce7ee"), true)
		exhausts.append(exhaust)
		_box(self, Vector3(side * 1.16, 0.28, 0.20), Vector3(0.12, 0.12, 1.2), Color("#e2b77e"), 0.55)
		_box(self, Vector3(side * 0.72, 0.38, 0.95), Vector3(0.64, 0.16, 0.44), Color("#8096a1"), 0.52)
		_sphere(self, Vector3(side * 0.38, 0.39, 0.75), Vector3(0.08, 0.08, 0.08), Color("#ffbd76"), true)
	self.scale = Vector3.ONE * 1.12

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

func _add_wing(parent: Node3D, mirrored: bool, material: StandardMaterial3D) -> void:
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
