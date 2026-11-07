extends StaticBody3D


# Spike blocks: killzone kills the ball, killarea triggers the spike rise.
# In training mode the spike stays attached, gets re-armed per episode
# and death is delegated to the checkpoint manager instead of a scene reload.

var armed := true
var home_position: Vector3


func _ready() -> void:
	add_to_group("spikes")
	home_position = position

func _on_killzone_body_entered(_body: Node3D) -> void:
	if Global.training_mode:
		var checkpoint_manager = get_tree().current_scene.get_node_or_null("Checkpoint_manager")
		if checkpoint_manager != null:
			checkpoint_manager.kill_player()
	else:
		get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_killarea_body_entered(_body: Node3D) -> void:
	if Global.training_mode:
		if not armed:
			return
		armed = false
		create_tween().tween_property(self, "position", Vector3(0.0, 1.5, 0.0), 0.2).as_relative()
		$Timer.start()
		return
	var tween = create_tween()
	tween.tween_property(self, "position", Vector3(0.0, 1.5, 0.0), 0.2).as_relative()
	$Timer.start()

func _on_timer_timeout() -> void:
	create_tween().tween_property(self, "position", Vector3(0.0, -1.5, 0.0), 0.2).as_relative()
	if Global.training_mode:
		return
	$killarea.queue_free()

func reset_self() -> void:
	armed = true
	position = home_position
