extends Area3D

# Coins reward the agent (+1) when collected in training mode and are
# restored on each episode reset instead of being queue_freed.

var collected := false


func _ready() -> void:
	add_to_group("coins")

func _process(_delta: float) -> void:
	if collected:
		return
	rotate_y(deg_to_rad(100.0 * _delta))

func _on_body_entered(_body: Node3D) -> void:
	if Global.training_mode:
		if not collected and _body.is_in_group("player"):
			collected = true
			visible = false
			set_deferred("monitoring", false)
			var controller: Node = _body.get_node_or_null("ai_controller")
			if controller != null:
				controller.add_reward(1.0)
		return
	$AnimationPlayer.play("bounce")
	$GPUParticles3D.emitting = true
	await get_tree().create_timer(0.5).timeout
	queue_free()

func reset_self() -> void:
	collected = false
	visible = true
	set_deferred("monitoring", true)
