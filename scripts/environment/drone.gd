extends "res://scripts/visual_mesh.gd"

var wisp := false
var variant := 0

func _ready() -> void:
	var hull_color := Color("#704c55") if wisp else Color("#68747c")
	var sensor_color := Color("#ce9fff") if wisp else Color("#ffb36c")
	var core := _sphere(self, Vector3(0, 0.08, 0), Vector3(0.68, 0.52, 0.72), hull_color, false)
	core.material_override = _mat(hull_color, 0.54, 0.72)
	var eye := _sphere(self, Vector3(0, 0.14, -0.47), Vector3(0.28, 0.22, 0.20), sensor_color, true)
	eye.material_override = _mat(sensor_color, 0.18, 0.08, true)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.58 if wisp else 0.42
	ring_mesh.outer_radius = 0.72 if wisp else 0.54
	ring.mesh = ring_mesh
	ring.rotation_degrees.x = 90
	ring.rotation_degrees.z = float(variant) * 14.0
	ring.material_override = _mat(Color("#c295d6") if wisp else Color("#8696a0"), 0.28, 0.68)
	add_child(ring)
	for side in [-1.0, 1.0]:
		var arm := _box(self, Vector3(side * 0.70, -0.04, 0.20), Vector3(0.78, 0.16, 0.22), Color("#384853"), 0.72)
		arm.rotation.y = side * -0.24
		_box(self, Vector3(side * 1.04, -0.07, -0.02), Vector3(0.14, 0.48, 0.18), Color("#8a6b67"), 0.52)
		var claw := _cylinder(self, Vector3(side * 1.10, -0.24, -0.12), 0.08, 0.40, Color("#d3a983"))
		claw.rotation_degrees.x = 62
	if wisp:
		for spoke in range(3):
			var angle := TAU * float(spoke) / 3.0
			_box(self, Vector3(cos(angle) * 0.86, 0.16, sin(angle) * 0.86), Vector3(0.48, 0.10, 0.12), Color("#624d78"), 0.45).rotation.y = -angle
