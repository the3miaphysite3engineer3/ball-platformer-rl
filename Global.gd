extends Node

# Set to true when the game is launched with `--training` (see scripts/world.gd).
# In training mode:
#  - player movement is driven by the AI controller instead of keyboard/mouse
#  - deaths respawn the ball at the last checkpoint in-place (no scene reload)
#  - the ball's yaw is locked so the AI sees a stable world
var training_mode: bool = false

var checkpoint_pos: Vector3 = Vector3(-13.444, 4.799, -11.63)
var previous_checkpoint_node: CharacterBody3D = null


func _ready() -> void:
	pass # Replace with function body.


func _process(_delta: float) -> void:
	pass
