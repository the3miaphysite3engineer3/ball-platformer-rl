extends Node
## AI controller for the ball player.
##
## Drives the player via `agent_input`, builds the observation vector and
## accumulates shaped rewards. Values below are the core knobs if training
## is slow or reward-hacks something: raise PROGRESS_SCALE to value speed
## more, lower reward constants otherwise.

# Discrete move actions (same convention as Input.get_vector in player.gd:
# y = -1 is "up/forward" because the player basis maps it to -Z).
const DIR_ACTIONS: Array = [
	Vector2.ZERO,    # 0 idle
	Vector2(0, -1),  # 1 forward
	Vector2(0, 1),   # 2 back
	Vector2(-1, 0),  # 3 left
	Vector2(1, 0),   # 4 right
]

# Reward shaping.
const PROGRESS_SCALE := 0.05   # per decision step: 0.05 * (prev_dist - new_dist)
const TIME_PENALTY := 0.005    # per decision step
const REWARD_COIN := 1.0
const REWARD_CHECKPOINT := 2.0
const REWARD_GOAL := 10.0
const REWARD_DEATH := -1.0
const REWARD_TIMEOUT := -0.5

# Sensors.
const RAY_COUNT := 16          # horizontal rays (360 deg)
const RAY_LENGTH := 6.0
const LEDGE_RAYS := 8          # downward rays in a ring around the ball
const LEDGE_RADIUS := 0.9
const LEDGE_DEPTH := 3.0

# Max decisions per episode before a (truncated) timeout.
const MAX_STEPS := 2000

var player: CharacterBody3D
var manager: Node

var pending_reward := 0.0      # accumulated since last obs was sent
var done := false              # terminal: goal, death or timeout
var steps := 0                 # decisions taken this episode
var move_input := Vector2.ZERO

var last_target_dist := 0.0
var _last_dist_valid := false


func _ready() -> void:
	player = get_parent()
	manager = get_tree().current_scene.get_node_or_null("Checkpoint_manager")
	if manager == null:
		printerr("RL: Checkpoint_manager not found, observations will be blind.")
	player.use_agent_input = true


# --- Action interface --------------------------------------------------------

func set_action(action: Array) -> void:
	if action.is_empty():
		return
	var dir_i := clampi(int(action[0]), 0, DIR_ACTIONS.size() - 1)
	move_input = DIR_ACTIONS[dir_i]
	var jump := false
	if action.size() > 1:
		jump = int(action[1]) != 0
	player.agent_input.move = move_input
	player.agent_input.jump = jump
	player.agent_input.sprint = false


# --- Reward channels (called by coins / checkpoints / deaths) -----------------

func add_reward(amount: float) -> void:
	pending_reward += amount

func on_coin() -> void:
	add_reward(REWARD_COIN)

func on_checkpoint() -> void:
	add_reward(REWARD_CHECKPOINT)
	_last_dist_valid = false  # rebase progress shaping at the new checkpoint

func on_goal() -> void:
	add_reward(REWARD_GOAL)
	done = true

func on_death() -> void:
	add_reward(REWARD_DEATH)
	done = true

func on_episode_reset() -> void:
	pending_reward = 0.0
	done = false
	steps = 0
	_last_dist_valid = false
	move_input = Vector2.ZERO
	player.agent_input.move = Vector2.ZERO
	player.agent_input.jump = false
	player.agent_input.sprint = false


# --- Observation (called once per decision step by rl_sync.gd) ----------------

func get_obs() -> Array:
	var obs: Array = []
	var pos: Vector3 = player.global_position
	var target: Vector3 = manager.get_target() if manager != null else pos
	var to_target := target - pos
	var dist := to_target.length()

	# Potential-based progress shaping + time penalty.
	if _last_dist_valid and not done:
		add_reward(PROGRESS_SCALE * (last_target_dist - dist))
		add_reward(-TIME_PENALTY)
		steps += 1
		if steps >= MAX_STEPS:
			add_reward(REWARD_TIMEOUT)
			done = true  # truncation; env restarts at spawn
	last_target_dist = dist
	_last_dist_valid = true

	var dir_n := to_target.normalized() if dist > 0.0001 else Vector3.ONE * 0.0

	# 1..3 velocity (scaled by max speed 10)
	obs.append(player.velocity.x / 10.0)
	obs.append(player.velocity.y / 10.0)
	obs.append(player.velocity.z / 10.0)
	# 4 on floor
	obs.append(1.0 if player.is_on_floor() else 0.0)
	# 5..7 unit direction to target
	obs.append(dir_n.x)
	obs.append(dir_n.y)
	obs.append(dir_n.z)
	# 8 distance to target
	obs.append(dist / 30.0)
	# 9 checkpoint progress 0..1
	if manager != null and manager.checkpoints.size() > 0:
		obs.append(float(manager.highest_visited + 1) / float(manager.checkpoints.size()))
	else:
		obs.append(0.0)
	# 10..25 horizontal obstacle rays (1.0 = free, else hit distance / RAY_LENGTH)
	obs.append_array(_horizontal_rays())
	# 26..33 ledge ring rays (1.0 = no ground = edge!)
	obs.append_array(_ledge_rays())
	return obs


func _horizontal_rays() -> Array:
	var out: Array = []
	var origin: Vector3 = player.global_position + Vector3(0, 0.25, 0)
	for i in RAY_COUNT:
		var angle := TAU * float(i) / float(RAY_COUNT)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var hit := _cast_ray(origin, origin + dir * RAY_LENGTH)
		if not hit.is_empty():
			out.append(hit.position.distance_to(origin) / RAY_LENGTH)
		else:
			out.append(1.0)
	return out


func _ledge_rays() -> Array:
	var out: Array = []
	var pos: Vector3 = player.global_position
	for i in LEDGE_RAYS:
		var angle := TAU * (float(i) + 0.5) / float(LEDGE_RAYS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var from := pos + dir * LEDGE_RADIUS + Vector3(0, 1.0, 0)
		var to := from + Vector3(0, -(1.0 + LEDGE_DEPTH), 0)
		var hit := _cast_ray(from, to)
		if not hit.is_empty():
			out.append(clampf((from.y - hit.position.y) / (1.0 + LEDGE_DEPTH), 0.0, 1.0))
		else:
			out.append(1.0)
	return out


# Returns an empty Dictionary when there is no hit.
func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(params)
