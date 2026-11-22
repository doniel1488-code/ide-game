extends "res://scripts/visual_mesh.gd"

var seed_value := 218900
var tint := 0.2
var dimensions := Vector3.ONE

func _ready() -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = _make_asteroid_mesh(seed_value)
	var rock_material := _mat(Color("#46535e").lerp(Color("#7b6d62"), tint), 0.94, 0.12)
	rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node.material_override = rock_material
	mesh_node.scale = dimensions
	add_child(mesh_node)

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
