extends "res://scripts/visual_mesh.gd"


func _ready() -> void:
	_box(self, Vector3(0, 0.15, 0), Vector3(5.6, 0.58, 1.25), Color("#273948"), 0.62)
	_box(self, Vector3(0, 0.49, -0.45), Vector3(1.35, 0.18, 1.55), Color("#516778"), 0.58)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 1.4, 0.28, 0.22), Vector3(1.72, 0.10, 1.28), Color("#354a59"), 0.66)
		_box(self, Vector3(side * 2.2, 0.36, 0.10), Vector3(0.28, 0.08, 0.72), Color("#b57652"), 0.45)
		var engine_glow := _sphere(self, Vector3(side * 0.48, 0.19, 0.82), Vector3(0.16, 0.16, 0.12), Color("#f39a63"), true)
		engine_glow.material_override = _mat(Color("#d97451"), 0.3, 0.15, true)
