extends Area3D


@export var scale_speed: float = 0.5
@export var max_y_scale: float = 100.0


func _on_body_entered(_body: Node3D) -> void:
	if _body.is_in_group("player"):
		killPlayer()

func killPlayer():
	# Both modes are handled centrally: training teleports to the last
	# checkpoint, normal play reloads the scene (see checkpoint_manger.gd).
	var checkpoint_manager = get_tree().current_scene.get_node_or_null("Checkpoint_manager")
	if checkpoint_manager != null:
		checkpoint_manager.kill_player()
	else:
		print("ERROR: Checkpoint_manager not found; can not respawn player.")

func _ready():
	pass

func increase_y_scale_slowly():
	var tween = create_tween()
	# Tween only the Y component of scale
	tween.tween_property(self, "scale", Vector3(scale.x, max_y_scale, scale.z), (max_y_scale - scale.y) / scale_speed)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
