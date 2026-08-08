extends RefCounted
class_name AuthoredLandmarkBuilder

const TEX_STONE := preload("res://assets/textures/stone.svg")

func build_landmark(parent: Node3D, region_id: String, biome: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoredLandmark"
	root.set_meta("region_id", region_id)
	root.add_to_group("authored_landmark")
	parent.add_child(root)
	match region_id:
		"blackwood":
			_build_fallen_chapel(root, biome)
		"windscar_highlands":
			_build_windscar_beacon(root, biome)
		"veilmoor":
			_build_pale_grave_ring(root, biome)
		_:
			root.queue_free()
			return null
	return root

func _build_fallen_chapel(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("494950"))
	var accent: Color = biome.get("accent", Color("7e9a75"))
	var base := Vector3(-12, 0, -17)
	_add_static_box(parent, base + Vector3(0, 0.25, 0), Vector3(17, 0.5, 24), stone.darkened(0.10))
	_add_static_box(parent, base + Vector3(-7.5, 3.2, 0), Vector3(1.2, 6.4, 24), stone)
	_add_static_box(parent, base + Vector3(7.5, 2.0, -5), Vector3(1.2, 4.0, 14), stone)
	_add_static_box(parent, base + Vector3(0, 3.0, -11.5), Vector3(16, 6.0, 1.2), stone.darkened(0.08))
	_add_static_box(parent, base + Vector3(0, 1.7, 7.0), Vector3(8, 3.4, 1.0), stone)
	_create_glow_orb(parent, base + Vector3(0, 2.0, -7), accent, 7.0)

func _build_windscar_beacon(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("77767d"))
	var accent: Color = biome.get("accent", Color("c4b98c"))
	var base := Vector3(14, 0, -15)
	_add_static_box(parent, base + Vector3(0, 1.0, 0), Vector3(12, 2.0, 12), stone.darkened(0.12))
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var p := base + Vector3(cos(angle) * 7.0, 3.3, sin(angle) * 7.0)
		_add_static_box(parent, p, Vector3(1.3, 6.6, 1.3), stone)
	_add_static_box(parent, base + Vector3(0, 5.5, 0), Vector3(2.0, 11.0, 2.0), stone.lightened(0.05))
	_create_glow_orb(parent, base + Vector3(0, 11.5, 0), accent, 10.0)

func _build_pale_grave_ring(parent: Node3D, biome: Dictionary) -> void:
	var stone: Color = biome.get("rock_color", Color("5e5b6d"))
	var accent: Color = biome.get("accent", Color("8c8be2"))
	var base := Vector3(0, 0, -11)
	for i in range(12):
		var angle: float = TAU * float(i) / 12.0
		var radius: float = 10.0 + (2.0 if i % 3 == 0 else 0.0)
		var p := base + Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		var grave := _add_static_box(parent, p, Vector3(1.0, 2.0 + float(i % 2) * 0.6, 0.45), stone)
		grave.rotation_degrees.y = rad_to_deg(-angle) + 90.0
	_add_static_box(parent, base + Vector3(0, 0.35, 0), Vector3(8, 0.7, 8), stone.darkened(0.15))
	_create_glow_orb(parent, base + Vector3(0, 1.4, 0), accent, 11.0)

func _add_static_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if DisplayServer.get_name() != "headless":
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _material(color)
		body.add_child(mesh_instance)
	parent.add_child(body)
	return body

func _create_glow_orb(parent: Node3D, pos: Vector3, color: Color, light_range: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var orb := MeshInstance3D.new()
	orb.name = "LandmarkGlow"
	orb.position = pos
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.84
	var material := _material(color, true)
	mesh.material = material
	orb.mesh = mesh
	parent.add_child(orb)
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = 1.45
	light.omni_range = light_range
	parent.add_child(light)

func _material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.albedo_texture = TEX_STONE
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material
