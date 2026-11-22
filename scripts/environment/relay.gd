extends "res://scripts/visual_mesh.gd"

var accent := Color("#83dcf5")
var flagship := false
var emitter: MeshInstance3D

func activate() -> void:
	emitter.material_override = _mat(Color("#e9ffd1"), 0.3, 0.25, true)
	var light := OmniLight3D.new()
	light.position.y = 2.15
	light.light_color = Color("#b7ffbb")
	light.omni_range = 5.0
	light.light_energy = 1.4
	add_child(light)

func _ready() -> void:
	_add_cylinder_y(self, Vector3(0, 0.25, 0), 1.2 if flagship else 0.85, 0.5, Color("#344858"))
	_add_cylinder_y(self, Vector3(0, 1.35, 0), 0.16, 2.2, Color("#758795"))
	_add_cylinder_y(self, Vector3(0, 2.55, 0), 0.28, 0.22, Color("#b7c5c9"))
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.74 if flagship else 0.55
	ring_mesh.outer_radius = 0.88 if flagship else 0.68
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 2.15, 0)
	ring.rotation_degrees.x = 90
	ring.material_override = _mat(accent.lightened(0.15), 0.3, 0.4, true)
	add_child(ring)
	emitter = ring
	for side in [-1.0, 1.0]:
		var panel := _box(self, Vector3(side * 1.24, 1.05, 0), Vector3(0.92, 0.10, 0.68), Color("#293e55"), 0.62)
		panel.rotation.z = -side * 0.08
		for cell in range(3):
			_box(self, Vector3(side * (0.98 + float(cell) * 0.25), 1.12, 0), Vector3(0.045, 0.025, 0.58), Color("#78aabd"), 0.35)
	_sphere(self, Vector3(0, 2.76, 0), Vector3(0.20, 0.26, 0.20), accent, true)
	_add_cylinder_y(self, Vector3(0, 3.15, 0), 0.045, 0.62, Color("#becbd0"))
	var cap := _sphere(self, Vector3(0, 3.48, 0), Vector3(0.12, 0.12, 0.12), Color("#eff2dc"), true)
	cap.material_override = _mat(Color("#e5dfba"), 0.22, 0.2, true)

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
