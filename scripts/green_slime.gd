extends CharacterBody3D


const JUMP_VELOCITY = 6.0

const SPEED := 2.0
@export var direction: Vector3 = Vector3(0, 0, 1)  # Start moving along +Z
var turning := false
var xform: Transform3D

# Home state, restored on RL episode reset.
var home_position: Vector3
var home_direction: Vector3


func _ready() -> void:
	add_to_group("slimes")
	home_position = global_position
	home_direction = direction


func _process(_delta: float) -> void:
	# Move the enemy
	velocity.x = SPEED * direction.x
	velocity.z = SPEED * direction.z

	if is_on_floor():
		align_with_floor($RayCast3D.get_collision_normal())
		global_transform = xform

	if not is_on_floor():
		velocity += get_gravity() * _delta

	move_and_slide()


	# Reverse direction on collision
	if not $RayCast3D.is_colliding() and not turning:
		turn_around()

func turn_around() -> void:
	turning = true
	var dir = direction
	direction = Vector3.ZERO  # Stop movement temporarily
	var turn_tween = create_tween()
	turn_tween.tween_property(self, "rotation_degrees", Vector3(0, 180, 0), 0.6).as_relative()
	await get_tree().create_timer(0.6).timeout

	# Reverse direction — example: flip X and Y
	direction.x = dir.x * -1.0
	direction.z = dir.z * -1.0
	turning = false


func _on_killplayer_body_entered(_body: Node3D) -> void:
	if not _body.is_in_group("player"):
		return
	if Global.training_mode:
		# Fast in-place death: teleport to last checkpoint, no scene reload,
		# no time_scale hacks (they would corrupt RL timing).
		var checkpoint_manager = get_tree().current_scene.get_node_or_null("Checkpoint_manager")
		if checkpoint_manager != null:
			checkpoint_manager.kill_player()
		return
	Engine.time_scale = 0.5
	_body.get_node("CollisionShape3D").queue_free()
	$Timer.start()


func _on_killenemy_body_entered(_body: Node3D) -> void:
	if not _body.is_in_group("player"):
		return
	_body.velocity.y = 7.0
	if Global.training_mode:
		# Stomp survives in training: squash briefly, keep patrolling,
		# so later episodes see the same world.
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector3(1.2, 0.4, 1.2), 0.1)
		tween.tween_property(self, "scale", Vector3.ONE, 0.15)
		return
	direction = Vector3.ZERO
	var turn_tween = create_tween()
	turn_tween.tween_property(self, "scale", Vector3(0, -0.7, 0), 0.6).as_relative()
	await get_tree().create_timer(0.7).timeout
	queue_free()

func align_with_floor(floor_normal):
	xform = global_transform
	xform.basis.y = floor_normal
	xform.basis.x = -xform.basis.z.cross(floor_normal)
	xform.basis = xform.basis.orthonormalized()

func _on_timer_timeout() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func reset_self() -> void:
	direction = home_direction
	turning = false
	scale = Vector3.ONE
	velocity = Vector3.ZERO
	global_position = home_position
