extends Node

# Ordered checkpoint waypoints + episode management.
# Also centralises death/respawn so normal play keeps the old behaviour
# while training mode does fast in-place resets (no scene reload).

var last_location: Vector3
var player: CharacterBody3D
var start_position: Vector3

# Checkpoint children of this node, in tree order (= course order).
var checkpoints: Array[Area3D] = []
# Index of the last checkpoint touched in order, -1 = none yet.
var highest_visited: int = -1


func _ready() -> void:
	player = get_parent().get_node("player")
	start_position = player.global_position
	last_location = player.global_position
	for child in get_children():
		if child is Area3D:
			checkpoints.append(child)


# Called by scripts/checkpoint.gd whenever the ball touches a checkpoint.
func on_checkpoint_reached(cp: Area3D) -> void:
	var idx := checkpoints.find(cp)
	if idx == -1:
		return
	# Any touched checkpoint becomes the respawn point (old behaviour).
	last_location = cp.global_position
	var reached_in_order := idx == highest_visited + 1
	if reached_in_order:
		highest_visited = idx
	var controller = player.get_node_or_null("ai_controller")
	if Global.training_mode and controller != null:
		if idx == checkpoints.size() - 1:
			# Final checkpoint of the course acts as the goal / win state.
			controller.on_goal()
		elif reached_in_order:
			controller.on_checkpoint()


# Position the agent is currently trying to reach.
func get_target() -> Vector3:
	var next := highest_visited + 1
	if next < checkpoints.size():
		return checkpoints[next].global_position
	if checkpoints.size() > 0:
		var last := checkpoints.size() - 1
		return checkpoints[last].global_position
	return start_position


# Central death handler used by lava, spikes and slimes.
func kill_player() -> void:
	if Global.training_mode:
		var controller = player.get_node_or_null("ai_controller")
		if controller != null:
			controller.on_death()
		player.velocity = Vector3.ZERO
		player.global_position = last_location
	else:
		get_tree().reload_current_scene()


# RL episode reset: teleport to spawn and restore the world actors.
func reset_episode() -> void:
	highest_visited = -1
	last_location = start_position
	for node in get_tree().get_nodes_in_group("slimes"):
		node.reset_self()
	for node in get_tree().get_nodes_in_group("spikes"):
		node.reset_self()
	for node in get_tree().get_nodes_in_group("coins"):
		node.reset_self()
	player.velocity = Vector3.ZERO
	player.global_position = start_position
	player.rotation.y = 0.0
	var controller = player.get_node_or_null("ai_controller")
	if controller != null:
		controller.on_episode_reset()
