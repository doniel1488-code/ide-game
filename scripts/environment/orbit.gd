extends "res://scripts/visual_mesh.gd"

var world_environment: WorldEnvironment
var space_sky_material: PanoramaSkyMaterial
var planet_surface: MeshInstance3D
var planet_atmosphere: MeshInstance3D
var planet_material: StandardMaterial3D
var current_sky_chapter := -1
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1049
	world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	space_sky_material = PanoramaSkyMaterial.new()
	space_sky_material.filter = true
	sky.sky_material = space_sky_material
	env.sky = sky
	env.background_energy_multiplier = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#7584a5")
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color("#c4d4ff")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)

	_build_stars()
	_build_planet()

func _make_space_panorama(chapter: int, accent: Color) -> Texture2D:
	var width := 512
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var base := Color("#030713")
	var nebula_tint: Color = accent.lerp(Color("#8370bd"), 0.28)
	var dust := FastNoiseLite.new()
	dust.seed = 14317 + chapter * 31
	dust.frequency = 0.046
	dust.fractal_octaves = 4
	for y in range(height):
		var v := float(y) / float(height)
		for x in range(width):
			var u := float(x) / float(width)
			var band_center := 0.50 + 0.10 * sin(u * TAU * 2.0 + sin(u * TAU * 3.0) * 0.4)
			var broad_cloud := exp(-pow((v - band_center) / 0.16, 2.0))
			var azimuth := u * TAU
			var polar := v * PI
			var direction := Vector3(cos(azimuth) * sin(polar), cos(polar), sin(azimuth) * sin(polar))
			var gas := dust.get_noise_3dv(direction * 168.0)
			var grain := dust.get_noise_3dv(direction * 420.0 + Vector3(35, -71, 12))
			var cloud := broad_cloud * smoothstep(-0.16, 0.52, gas + grain * 0.28)
			var pixel := base.lerp(Color("#101629"), cloud * 0.55)
			pixel = pixel.lerp(nebula_tint, cloud * 0.34)
			image.set_pixel(x, y, pixel)
	var sky_rng := RandomNumberGenerator.new()
	sky_rng.seed = 6619 + chapter * 103
	for i in range(1450):
		var sx := sky_rng.randi_range(0, width - 1)
		var sy := sky_rng.randi_range(0, height - 1)
		var brightness := sky_rng.randf_range(0.15, 0.75)
		var tint := Color("#dce7ff").lerp(Color("#9bc9dc"), sky_rng.randf() * 0.65)
		image.set_pixel(sx, sy, tint * brightness)
		if i % 55 == 0:
			image.set_pixel((sx + 1) % width, sy, tint * brightness * 0.32)
	return ImageTexture.create_from_image(image)

func _make_planet_texture(chapter: int, accent: Color) -> Texture2D:
	var width := 512
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 93017 + chapter * 187
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	for y in range(height):
		var v := float(y) / float(height)
		var latitude_band := sin(v * TAU * 13.0 + sin(v * TAU * 3.0) * 0.55)
		for x in range(width):
			var theta := float(x) * TAU / float(width)
			var latitude := v * PI
			var cloud := noise.get_noise_3d(cos(theta) * sin(latitude) * 160.0, cos(latitude) * 160.0, sin(theta) * sin(latitude) * 160.0)
			var bands := latitude_band * 0.22 + cloud * 0.62
			var color := Color("#273d55").lerp(Color("#73859a"), clampf(0.46 + bands, 0.0, 1.0))
			color = color.lerp(accent.darkened(0.12), clampf(cloud * 0.20, 0.0, 0.20))
			var polar := clampf(absf(v - 0.5) * 2.0, 0.0, 1.0)
			color = color.lerp(Color("#a9c4d1"), smoothstep(0.80, 0.99, polar) * 0.72)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func set_chapter(chapter: int, accent: Color) -> void:
	if chapter == current_sky_chapter:
		return
	current_sky_chapter = chapter
	space_sky_material.panorama = _make_space_panorama(chapter, accent)
	planet_material.albedo_texture = _make_planet_texture(chapter, accent)
	var atmosphere_material := planet_atmosphere.material_override as StandardMaterial3D
	atmosphere_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.16)
	atmosphere_material.emission = accent.lightened(0.25)

func _build_stars() -> void:
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.045
	star_mesh.height = 0.09
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = star_mesh
	instances.instance_count = 360
	for i in range(instances.instance_count):
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.01:
			direction = Vector3.UP
		direction = direction.normalized()
		var distance := rng.randf_range(62.0, 118.0)
		var scale := rng.randf_range(0.65, 1.8)
		instances.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), direction * distance))
	var starfield := MultiMeshInstance3D.new()
	starfield.name = "NearStarfield"
	starfield.multimesh = instances
	starfield.material_override = _mat(Color("#a9c9e8"), 0.2, 0, true)
	add_child(starfield)

func _build_planet() -> void:
	var planet := Node3D.new()
	planet.name = "Nacre — distant moon"
	planet.position = Vector3(27, -34, -92)
	add_child(planet)
	planet_surface = MeshInstance3D.new()
	var globe := SphereMesh.new()
	globe.radius = 20.0
	globe.height = 40.0
	globe.radial_segments = 48
	globe.rings = 32
	planet_surface.mesh = globe
	planet_surface.name = "BandedOcean"
	planet_material = StandardMaterial3D.new()
	planet_material.albedo_color = Color("#537189")
	planet_material.roughness = 0.9
	planet_material.metallic = 0.04
	planet_material.emission_enabled = true
	planet_material.emission = Color("#243750")
	planet_material.emission_energy_multiplier = 0.16
	planet_surface.material_override = planet_material
	planet.add_child(planet_surface)
	planet_atmosphere = MeshInstance3D.new()
	var halo := SphereMesh.new()
	halo.radius = 20.8
	halo.height = 41.6
	halo.radial_segments = 48
	halo.rings = 32
	planet_atmosphere.mesh = halo
	planet_atmosphere.name = "BlueAtmosphere"
	var atmosphere_material := StandardMaterial3D.new()
	atmosphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	atmosphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmosphere_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	atmosphere_material.albedo_color = Color("#79bce9", 0.16)
	atmosphere_material.emission_enabled = true
	atmosphere_material.emission = Color("#427eb2")
	atmosphere_material.emission_energy_multiplier = 0.34
	planet_atmosphere.material_override = atmosphere_material
	planet.add_child(planet_atmosphere)
