"""Live spectator: one VISIBLE Godot window playing the newest PPO checkpoint.

Run while train_ppo.py is training headless in the background. This process
periodically checks the ckpts/ folder; whenever a newer checkpoint appears it
swaps in the updated policy so you can watch the agent improve in real time.

    python training/play_live.py --godot <godot.exe> --project <project dir>

Close the Godot window (or Ctrl+C) to stop watching.
"""

import argparse
import glob
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from stable_baselines3 import PPO

from godot_env import GodotEnv


def latest_checkpoint(ckpt_dir):
    """Return (path, steps) of the newest checkpoint, or (None, -1)."""
    best = (None, -1)
    for path in glob.glob(os.path.join(ckpt_dir, "ball_ppo_*_steps.zip")):
        m = re.search(r"ball_ppo_(\d+)_steps", os.path.basename(path))
        if not m:
            continue
        try:
            steps = int(m.group(1))
        except ValueError:
            continue
        if steps > best[1]:
            best = (path, steps)
    return best


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--project", default=".")
    ap.add_argument("--ckpt-dir", default=None, help="defaults to <project>/ckpts")
    ap.add_argument("--port", type=int, default=11050)
    ap.add_argument("--poll-sec", type=float, default=30.0,
                    help="check for a newer checkpoint this often (wall clock)")
    args = ap.parse_args()

    ckpt_dir = args.ckpt_dir or os.path.join(args.project, "ckpts")
    cpath, csteps = latest_checkpoint(ckpt_dir)
    if cpath is None:
        print(f"No checkpoints found yet in {ckpt_dir}")
        return
    print(f"Spectator: showing checkpoint {csteps} ({os.path.basename(cpath)})")

    model = PPO.load(cpath, device="cpu")
    env = GodotEnv(godot_bin=args.godot, project_dir=args.project,
                   port=args.port, headless=False)
    obs, info = env.reset()
    last_check = time.time()

    try:
        while True:
            action, _ = model.predict(obs, deterministic=True)
            obs, _reward, terminated, _truncated, _info = env.step(action)
            if terminated:
                obs, info = env.reset()

            # Wall-clock poll for a newer checkpoint.
            if time.time() - last_check > args.poll_sec:
                last_check = time.time()
                path, steps = latest_checkpoint(ckpt_dir)
                fresh = path is not None and time.time() - os.path.getmtime(path) > 10.0
                if path is not None and steps > csteps and fresh:
                    print(f"Spectator: switching to checkpoint {steps} "
                          f"({os.path.basename(path)})")
                    model = PPO.load(path, device="cpu")
                    csteps = steps
    except KeyboardInterrupt:
        print("Spectator: stopped by user")
    finally:
        env.close()


if __name__ == "__main__":
    main()
