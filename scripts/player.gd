extends CharacterBody3D


var SPEED := 5.0
var rototion_speed := 2.0
const JUMP_VELOCITY = 6.0

# --- AI agent control -------------------------------------------------------
# When `use_agent_input` is true the player is driven by `agent_input`
# (written every decision step by scripts/training/player_controller.gd)
# instead of the keyboard/mouse. Normal play is untouched.
var agent_input := {"move": Vector2.ZERO, "jump": false, "sprint": false}
var use_agent_input := false
# Yaw is locked to this while Global.training_mode is on, so the AI
# always works in the same world-frame and never has to "aim" a camera.
var training_yaw := 0.0

@onready var camera_controller: SpringArm3D = $camera_controller

var _agent_jump_latched := false


func _unhandled_input(_event):
	if Global.training_mode:
		return
	if _event is InputEventMouseMotion:
		rotate_y(-_event.relative.x * .0015)
		camera_controller.rotate_x(-_event.relative.y * .0015)
		camera_controller.rotation.x = clamp(camera_controller.rotation.x, -PI/2, PI/2)

func _process(delta: float) -> void:
	if not Global.training_mode:
		if Input.is_action_just_pressed("cam1"):
			camera_controller.spring_length = 0.1
		if Input.is_action_just_pressed("cam2"):
			camera_controller.spring_length = 4.0
		if Input.is_action_just_pressed("esc"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Input.is_action_just_pressed("click"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Sprint.
	if use_agent_input:
		if agent_input.sprint:
			SPEED = 10.0
			rototion_speed = 4.0
		else:
			SPEED = 5.0
			rototion_speed = 2.0
	else:
		if Input.is_action_pressed("sprint"):
			SPEED = 10.0
			rototion_speed = 4.0
		else:
			SPEED = 5.0
			rototion_speed = 2.0

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump (agent edge-detects its own jump bit via the latch).
	if use_agent_input:
		if not agent_input.jump:
			_agent_jump_latched = false
		if agent_input.jump and is_on_floor() and not _agent_jump_latched:
			_agent_jump_latched = true
			velocity.y = JUMP_VELOCITY
	elif Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# Direction is relative to the body basis; in training the yaw is
	# locked to `training_yaw`, so axis actions map straight to world axes.
	var input_dir: Vector2
	if use_agent_input:
		input_dir = agent_input.move
	else:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if Global.training_mode:
		rotation.y = training_yaw

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = lerp(velocity.x, direction.x * SPEED, delta * 1.0)
		$MeshInstance3D.rotate_x(input_dir.y * delta * rototion_speed)
		velocity.z = lerp(velocity.z, direction.z * SPEED, delta * 1.0)
		$MeshInstance3D.rotate_z(-input_dir.x * delta * rototion_speed)
	else:
		velocity.x = lerp(velocity.x, direction.x, delta * 4.0)
		velocity.z = lerp(velocity.z, direction.z, delta * 4.0)

	move_and_slide()
