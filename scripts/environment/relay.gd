extends "res://scripts/visual_mesh.gd"

var accent := Color("#83dcf5")
var flagship := false
var emitter: MeshInstance3D

func activate() -> void:
	emitter.material_override = _mat(Color("#e9ffd1"), 0.3, 0.25, true)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.1, -0.9)
	light.light_color = Color("#b7ffbb")
	light.omni_range = 5.0
	light.light_energy = 1.4
	add_child(light)

func _ready() -> void:
	if flagship:
		scale = Vector3.ONE * 1.65
	emitter = _sphere(self, Vector3(0, 2.1, -0.78), Vector3(0.28, 0.28, 0.10), accent, true)
