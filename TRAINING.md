# Training the ball platformer with RL

PPO (Stable-Baselines3) driving the Godot game through a localhost TCP bridge.
Training mode is only active when the game is launched with `--training`;
normal play is completely unchanged.

## how it is wired

- `scripts/world.gd` — detects `--training`, attaches `scripts/training/player_controller.gd`
  to the player and `scripts/training/rl_sync.gd` (TCP server) to the world.
- `scripts/training/player_controller.gd` builds observations and rewards and
  writes `agent_input` into the player.
- `scripts/player.gd` — reads `agent_input` in agent mode, keeps keyboard/mouse
  otherwise, locks the ball's yaw during training.
- `scripts/checkpoint_manger.gd` — ordered checkpoints, in-place respawn on
  death (no `change_scene_to_file`), `reset_episode()` for RL resets.
- Hazards (lava / spikes / slimes) and coins all route through these hooks; in
  training nothing reloads the scene, nothing changes `Engine.time_scale`,
  slimes and coins are restored at every reset.

## interface

- **Observation** (33 floats): velocity (/10), on-floor flag, unit direction to
  next checkpoint (x,y,z), distance /30, checkpoint progress 0..1,
  16 horizontal obstacle rays (1 = free), 8 downward ledge rays (1 = edge).
- **Action**: `MultiDiscrete([5, 2])`
  `[move: 0 idle, 1 fwd, 2 back, 3 left, 4 right, jump: 0/1]`
  (world axes — the yaw is locked during training).
- **Reward** per decision (4 physics frames):
  `+0.05 * (prev_dist - new_dist)` to next checkpoint, `-0.005` time penalty,
  coin `+1`, checkpoint `+2`, final checkpoint (goal) `+10` + terminal,
  death `-1` + terminal, timeout `-0.5` (2000 decisions ≈ 2.2 min).
- One step = 4 physics frames → 15 agent steps/s at 60 Hz physics.

## run

1. Set up Python deps (Python 3.10+) in a virtualenv on D: to save C: space:
   ```
   python -m venv D:\rl_env
   $env:PIP_CACHE_DIR="D:\pip_cache"; $env:TMP="D:\pip_tmp"; $env:TEMP="D:\pip_tmp"
   D:\rl_env\Scripts\python.exe -m pip install -r training/requirements.txt
   ```
   (Training must then be run with `D:\rl_env\Scripts\python.exe` everywhere.)
2. Find our Godot 4 console executable (the same one that opens the project;
   on Windows the editor also works but `--headless` runs are much faster).
3. Train (8 parallel headless instances, ports 11000+):
   ```
   python training/train_ppo.py --godot "C:/path/to/godot.exe" --project "C:/Users/q/Desktop/game rpg" --n-envs 8 --total-steps 4000000
   ```
   - `--render` shows the game windows while training (slower).
   - Checkpoints save to `ckpts/`, final model to `models/ball_ppo.zip`.
   - Resume: add `--load models/ball_ppo` (or a ckpt path) and rerun.
4. Expect rough milestones:
   - ~100–300k steps: runs toward the first checkpoint, stops falling into lava
     everywhere.
   - ~1M steps: reaches checkpoints reliably, jumps over gaps.
   - 2–4M steps: whole course, decent coin collection.
   If it stalls: raise `PROGRESS_SCALE` in `player_controller.gd`, or reduce
   the episode spawn segment first (see curriculum tip in the plan).

## smoke test without training

`godot --path "C:/Users/q/Desktop/game rpg" --training` starts the game in
agent mode and prints `RL: waiting for training client on port 11000`.
With no client attached the ball just stands still — that is the intended
idle state.

## play a trained model in-engine (no Python)

The saved PPO model can be exported with stable-baselines3
(`PPO.load + policy.to_onnx`) and run from Godot via the ONNX runtime; that
is the next step once training looks good.

## knobs to know

- `scripts/training/player_controller.gd`: reward constants, `MAX_STEPS`,
  sensor ray counts/lengths.
- `scripts/training/rl_sync.gd`: `ACTION_REPEAT` (4 = 15 steps/s; lower gives
  finer control but more training steps, higher is faster but cruder).
- `training/train_ppo.py`: PPO hyperparameters, `--n-envs`.
