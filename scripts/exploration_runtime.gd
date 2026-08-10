extends "res://scripts/exploration_system.gd"

# The authored prototype exploration layer used fixed world coordinates and
# therefore overlaid the same camp, shrine, crypt, grove, enemies and discovery
# zones on every generated seed. The procedural exploration runtime now owns all
# client presentation and authoritative generated content.
var legacy_presentation_enabled: bool = false

func _ready() -> void:
	set_process(false)
