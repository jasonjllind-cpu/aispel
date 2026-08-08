extends RefCounted
class_name BiomeMap

const BIOME_CATALOG := preload("res://scripts/world/biome_catalog.gd")

var temperature_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var transition_noise := FastNoiseLite.new()

func configure(seed_value: int) -> void:
	temperature_noise.seed = seed_value ^ 0x13579
	temperature_noise.frequency = 0.0038
	moisture_noise.seed = seed_value ^ 0x24680
	moisture_noise.frequency = 0.0044
	transition_noise.seed = seed_value ^ 0x5A17C
	transition_noise.frequency = 0.0085

func sample(world_x: float, world_z: float, preferred_biome: String = "green_highlands") -> Dictionary:
	var temperature: float = clamp((temperature_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5, 0.0, 1.0)
	var moisture: float = clamp((moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5, 0.0, 1.0)
	var candidate: String = _climate_biome(temperature, moisture)
	var transition: float = abs(transition_noise.get_noise_2d(world_x, world_z))
	var secondary: String = candidate
	if secondary == preferred_biome:
		secondary = _alternate_biome(preferred_biome, temperature, moisture)
	var blend: float = clamp((transition - 0.36) / 0.54, 0.0, 1.0) * 0.38
	return {
		"primary_id": preferred_biome,
		"secondary_id": secondary,
		"blend": blend,
		"temperature": temperature,
		"moisture": moisture
	}

func ground_color(sample_data: Dictionary) -> Color:
	var primary_id: String = str(sample_data.get("primary_id", "green_highlands"))
	var secondary_id: String = str(sample_data.get("secondary_id", primary_id))
	var blend: float = float(sample_data.get("blend", 0.0))
	var primary: Dictionary = BIOME_CATALOG.get_biome(primary_id)
	var secondary: Dictionary = BIOME_CATALOG.get_biome(secondary_id)
	var color_a: Color = primary.get("ground_color", Color("4f7545"))
	var color_b: Color = secondary.get("ground_color", color_a)
	return color_a.lerp(color_b, blend)

func _climate_biome(temperature: float, moisture: float) -> String:
	if moisture > 0.64 and temperature < 0.58:
		return "blackwood"
	if moisture < 0.38 and temperature > 0.48:
		return "windscar_highlands"
	if temperature < 0.38 and moisture < 0.58:
		return "veilmoor"
	return "green_highlands"

func _alternate_biome(preferred_biome: String, temperature: float, moisture: float) -> String:
	match preferred_biome:
		"blackwood":
			return "green_highlands" if temperature > 0.43 else "veilmoor"
		"windscar_highlands":
			return "green_highlands" if moisture > 0.32 else "veilmoor"
		"veilmoor":
			return "blackwood" if moisture > 0.57 else "windscar_highlands"
		_:
			return "blackwood" if moisture > 0.56 else "windscar_highlands"
