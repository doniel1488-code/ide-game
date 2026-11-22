extends "res://scripts/visual_mesh.gd"

var accent := Color("#83dcf5")

func _ready() -> void:
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.43
	upper.height = 0.72
	upper.radial_segments = 6
	var shard_a := MeshInstance3D.new()
	shard_a.mesh = upper
	shard_a.position.y = 0.30
	shard_a.material_override = _mat(accent.lightened(0.22), 0.16, 0.1, true)
	add_child(shard_a)
	var lower := CylinderMesh.new()
	lower.top_radius = 0.43
	lower.bottom_radius = 0.0
	lower.height = 0.72
	lower.radial_segments = 6
	var shard_b := MeshInstance3D.new()
	shard_b.mesh = lower
	shard_b.position.y = -0.30
	shard_b.material_override = _mat(Color("#bdeaf1"), 0.12, 0.1, true)
	add_child(shard_b)
	var band := MeshInstance3D.new()
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 0.28
	band_mesh.outer_radius = 0.34
	band.mesh = band_mesh
	band.material_override = _mat(Color("#e8fcff"), 0.13, 0.1, true)
	add_child(band)
