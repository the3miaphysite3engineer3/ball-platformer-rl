"""single-process Gymnasium environment hosted by one headless Godot instance.

Protocol: one JSON line per message over localhost TCP (see rl_sync.gd):
    Godot -> Python : {"type":"step","obs":[...],"reward":f,"done":b,"steps":i}
    Python -> Godot : {"action":[dir_idx 0..4, jump 0/1]}
    Python -> Godot : {"reset":true}

Observation (33 floats, see scripts/training/player_controller.gd):
    vel.x, vel.y, vel.z (/10), on_floor, dir_to_target.x/y/z, dist/30,
    checkpoint_progress (0..1), 16 horizontal ray casts, 8 ledge rays.

Action: MultiDiscrete([5, 2]):
    dim 0: 0 idle, 1 forward, 2 back, 3 left, 4 right  (world axes, yaw locked)
    dim 1: 0 no jump, 1 jump
"""

import json
import os
import socket
import subprocess
import time

import gymnasium as gym
import numpy as np

OBS_SIZE = 33


class GodotEnv(gym.Env):
    """One step takes 4 physics frames inside Godot (ACTION_REPEAT)."""

    metadata = {"render_modes": []}

    def __init__(self, godot_bin="godot", project_dir=".", port=11000,
                 headless=True, connect_timeout=120.0):
        super().__init__()
        self.metadata = {"render_modes": []}
        self.action_space = gym.spaces.MultiDiscrete([5, 2])
        self.observation_space = gym.spaces.Box(
            low=-np.inf, high=np.inf, shape=(OBS_SIZE,), dtype=np.float32)

        cmd = [godot_bin, "--path", os.path.abspath(project_dir), "--training"]
        if headless:
            cmd.append("--headless")
        env = dict(os.environ)
        env["RL_PORT"] = str(port)
        self._proc = subprocess.Popen(
            cmd, cwd=project_dir, env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

        deadline = time.time() + connect_timeout
        self._sock = None
        while time.time() < deadline:
            if self._proc.poll() is not None:
                raise RuntimeError("Godot exited before opening the RL port "
                                   "(check that Godot console version supports --headless).")
            try:
                self._sock = socket.create_connection(("127.0.0.1", port), timeout=2.0)
                break
            except OSError:
                time.sleep(0.25)
        if self._sock is None:
            self.close()
            raise RuntimeError(f"Could not connect to Godot on port {port}.")
        self._sock.settimeout(60.0)
        self._reader = self._sock.makefile("r")
        self._last_steps = 0

    # --- protocol helpers ---------------------------------------------------

    def _send(self, msg):
        data = json.dumps(msg) + "\n"
        self._sock.sendall(data.encode("utf-8"))

    def _recv(self):
        line = self._reader.readline()
        if not line:
            raise RuntimeError("Godot closed the connection (godot process died?).")
        return json.loads(line)

    # --- gym API --------------------------------------------------------------

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        self._send({"reset": True})
        msg = self._recv()
        obs = np.asarray(msg["obs"], dtype=np.float32)
        if obs.shape[0] != OBS_SIZE:
            raise RuntimeError(
                f"Observation size changed: got {obs.shape[0]}, expected {OBS_SIZE}."
                " Update OBS_SIZE and scripts/training/player_controller.gd together.")
        self._last_steps = int(msg.get("steps", 0))
        return obs, {"steps": self._last_steps}

    def step(self, action):
        dir_idx = int(np.clip(action[0], 0, 4))
        jump = int(np.clip(action[1], 0, 1))
        self._send({"action": [dir_idx, jump]})
        msg = self._recv()
        obs = np.asarray(msg["obs"], dtype=np.float32)
        terminated = bool(msg.get("done", False))
        truncated = False
        self._last_steps = int(msg.get("steps", 0))
        return obs, float(msg.get("reward", 0.0)), terminated, truncated, {
            "steps": self._last_steps}

    def close(self):
        try:
            if getattr(self, "_sock", None) is not None:
                self._sock.close()
                self._sock = None
        finally:
            if getattr(self, "_proc", None) is not None and self._proc.poll() is None:
                self._proc.terminate()
                try:
                    self._proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
                self._proc = None
