# Ball Platformer RL

A 3D ball platformer built in **Godot 4.7** where a PPO agent (Stable-Baselines3)
learns to play the game — training runs headless through a localhost TCP bridge.

## What's in the box

| Folder | What it is |
|---|---|
| `scripts/` | Gameplay: player ball, checkpoints, lava/slime/spike hazards, coins |
| `scripts/training/` | RL glue: `player_controller.gd` (observations/rewards), `rl_sync.gd` (TCP bridge) |
| `scenes/`, `Object/`, `Sprites/`, `Audio/` | Game assets |
| `training/` | Python side: `godot_env.py` (Gymnasium wrapper), `train_ppo.py` (PPO trainer) |
| `ckpts/` | PPO checkpoints (every 100k steps) |
| `TRAINING.md` | Full setup/run guide, observation-action-reward spec |

## Gameplay summary

- Rolling football-textured ball (`CharacterBody3D`), 3rd-person camera
- Slopes, moving/rotating platforms, patrolling slimes (stompable), rising spike
  traps, lava pits
- 3 checkpoints along the course; touching the last one wins the episode

## RL at a glance

- **Obs** (33 floats): velocity, on-floor, direction+distance to next checkpoint,
  progress, 16 obstacle rays, 8 ledge-edge rays
- **Action**: `MultiDiscrete([5, 2])` — move direction + jump
- **Reward**: potential-based progress toward the next checkpoint, +coins,
  +checkpoints, terminal goal +10 / death −1, small time penalty
- 8 parallel headless Godot envs, 4-frame action repeat

See [TRAINING.md](TRAINING.md) to run training and the design notes behind
fast in-place resets, the yaw-locked agent controls, and re-armable hazards.
