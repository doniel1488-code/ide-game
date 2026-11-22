extends "res://scripts/visual_mesh.gd"

var exhausts: Array[MeshInstance3D] = []
var thrust := 0.0

func set_thrust(speed: float, dashing: bool, delta: float) -> void:
	var desired := 1.65 if dashing else clampf(speed, 0.0, 1.0)
	thrust = lerpf(thrust, desired, 1.0 - exp(-11.0 * delta))
	for exhaust in exhausts:
		exhaust.scale.z = 0.19 + 0.65 * thrust
		exhaust.position.z = 2.12 + exhaust.scale.z * 0.42

func _ready() -> void:
	$Hull.scale = Vector3.ONE * 1.12
	for side in [-1.0, 1.0]:
		var exhaust := _sphere(self, Vector3(side * 1.51, 0.56, 2.20), Vector3(0.17, 0.13, 0.19), Color("#7ce7ee"), true)
		exhausts.append(exhaust)
