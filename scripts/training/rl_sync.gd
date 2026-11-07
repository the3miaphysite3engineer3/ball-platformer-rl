extends Node
## Minimal TCP bridge between Godot and the Python RL trainer.
##
## Request/response protocol (one JSON line per message, localhost only):
##   Godot -> Python : {"type":"step","obs":[...],"reward":f,"done":b,"steps":i}
##   Python -> Godot : {"action":[dir_idx 0..4, jump 0/1]}
##   Python -> Godot : {"reset":true}   (start/reset a new episode)
##
## Godot sends one observation every ACTION_REPEAT physics frames; the
## trainer replies with an action; when the episode ends the trainer sends
## reset and the whole cycle repeats. No message is sent before the first
## reset, so requests and responses always match 1:1.

const ACTION_REPEAT := 4  # physics frames per decision step (60 Hz -> 15 Hz)

var port := 11000
var server: TCPServer
var client: StreamPeerTCP

var player: CharacterBody3D
var controller: Node
var manager: Node

var buffer := ""
var frames_left := 0
var awaiting_reply := false
var got_reset := false
# Set after the first real traffic so a client that just connected is not
# dropped while still in a transitional status (Godot 4 has STATUS_ERROR /
# STATUS_NONE / STATUS_CONNECTING / STATUS_CONNECTED, no STATUS_CLOSED).
var saw_traffic := false


func setup(p_player: CharacterBody3D, p_controller: Node, p_manager: Node) -> void:
	player = p_player
	controller = p_controller
	manager = p_manager
	var port_env := OS.get_environment("RL_PORT")
	if port_env != "":
		port = int(port_env)
	server = TCPServer.new()
	if server.listen(port, "127.0.0.1") != OK:
		printerr("RL: TCP listen failed on port %d" % port)
		server = null
	else:
		print("RL: waiting for training client on port %d ..." % port)


func _physics_process(_delta: float) -> void:
	if server == null:
		return
	if client == null:
		if server.is_connection_available():
			client = server.take_connection()
			print("RL: training client connected")
		return

	client.poll()
	var status := client.get_status()
	if saw_traffic and status != StreamPeerTCP.STATUS_CONNECTED:
		print("RL: client disconnected (status %d)" % status)
		client = null
		awaiting_reply = false
		return

	var available := client.get_available_bytes()
	if available > 0:
		saw_traffic = true
		buffer += client.get_string(available)
	while buffer.contains("\n"):
		var line := buffer.substr(0, buffer.find("\n"))
		buffer = buffer.substr(buffer.find("\n") + 1)
		var txt := line.strip_edges()
		if txt == "":
			continue
		var msg = JSON.parse_string(txt)
		if msg is Dictionary:
			_handle(msg)

	if frames_left > 0:
		frames_left -= 1
	# Don't drag out the action window when the episode ends early
	# (e.g. death hit between decision steps).
	if controller.done and frames_left > 0:
		frames_left = 0

	if got_reset and not awaiting_reply and (frames_left <= 0 or controller.done):
		_send_step()


func _handle(msg: Dictionary) -> void:
	if msg.has("reset"):
		manager.reset_episode()
		controller.pending_reward = 0.0
		controller.done = false
		got_reset = true
		awaiting_reply = false
		frames_left = 0
	elif msg.has("action"):
		controller.set_action(msg.get("action", [0, 0]))
		frames_left = ACTION_REPEAT
		awaiting_reply = false


func _send_step() -> void:
	var obs: Array = controller.get_obs()
	var msg := {
		"type": "step",
		"obs": obs,
		"reward": controller.pending_reward,
		"done": controller.done,
		"steps": controller.steps,
	}
	controller.pending_reward = 0.0  # drained
	_send(msg)
	awaiting_reply = true


func _send(msg: Dictionary) -> void:
	saw_traffic = true
	client.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _exit_tree() -> void:
	if client != null:
		client.close()
	if server != null:
		server.stop()
