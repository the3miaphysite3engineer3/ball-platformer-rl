extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# RL training mode: launched with `godot --path . --training`
	var training: bool = OS.get_cmdline_args().has("--training")
	Global.training_mode = training
	if not training:
		return

	var player: CharacterBody3D = $player
	var manager: Node = $Checkpoint_manager

	# Attach the AI controller to the player and the TCP bridge to the world.
	var controller: Node = load("res://scripts/training/player_controller.gd").new()
	controller.name = "ai_controller"
	player.add_child(controller)

	var sync_node: Node = load("res://scripts/training/rl_sync.gd").new()
	sync_node.name = "rl_sync"
	add_child(sync_node)
	sync_node.setup(player, controller, manager)


func _process(_delta: float) -> void:
	pass
