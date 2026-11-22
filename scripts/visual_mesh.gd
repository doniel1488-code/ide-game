extends Node3D

func _mat(color: Color, roughness: float, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
	return material

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = _mat(color, 0.32, metallic)
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	instance.mesh = mesh
	instance.position = pos
	instance.scale = size
	instance.material_override = _mat(color, 0.24, 0.0, glow)
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.8
	mesh.height = height
	instance.mesh = mesh
	instance.position = pos
	instance.rotation_degrees.x = 90.0
	instance.material_override = _mat(color, 0.35, 0.35)
	parent.add_child(instance)
	return instance
