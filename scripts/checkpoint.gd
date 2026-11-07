extends Area3D

var checkpoint_manager: Node

func _ready() -> void:
	# In world.tscn checkpoints are children of Checkpoint_manager.
	if get_parent() != null and get_parent().has_method("on_checkpoint_reached"):
		checkpoint_manager = get_parent()
	else:
		checkpoint_manager = get_tree().root.find_child("Checkpoint_manager", true, false)

	if checkpoint_manager == null:
		print("ERROR: Checkpoint_manager node not found!")

func _on_body_entered(_body: Node3D) -> void:
	if _body.is_in_group("player"):
		if checkpoint_manager != null:
			checkpoint_manager.on_checkpoint_reached(self)
			$checkpoint/AnimationPlayer.play("Take 001")
		else:
			print("Checkpoint manager is missing!")
