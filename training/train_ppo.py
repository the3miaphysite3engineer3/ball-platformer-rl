"""Train a PPO agent to play the ball platformer.

Usage example (adjust --godot to your Godot 4 console executable):
    python training/train_ppo.py --godot "C:/Godot/Godot_v4.7.exe" ^
        --project "C:/Users/q/Desktop/game rpg" --n-envs 8 --total-steps 4000000

Each env spawns its own headless Godot instance on port + rank.
"""

import argparse

from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import SubprocVecEnv

from godot_env import GodotEnv


def make_env(rank, args):
    def _init():
        env = GodotEnv(
            godot_bin=args.godot,
            project_dir=args.project,
            port=args.port + rank,
            headless=not args.render,
        )
        return Monitor(env)
    return _init


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", default="godot",
                    help="path to the Godot 4 console executable")
    ap.add_argument("--project", default=".",
                    help="path to the Godot project folder")
    ap.add_argument("--port", type=int, default=11000)
    ap.add_argument("--n-envs", type=int, default=8)
    ap.add_argument("--total-steps", type=int, default=4_000_000)
    ap.add_argument("--render", action="store_true",
                    help="show the Godot windows while training (slower)")
    ap.add_argument("--load", default=None,
                    help="resume from a saved PPO model file")
    return ap.parse_args()


def main():
    args = parse_args()
    print(f"Spawning {args.n_envs} Godot instance(s) starting at port {args.port}...")

    env = SubprocVecEnv([make_env(i, args) for i in range(args.n_envs)],
                        start_method="spawn")

    checkpoint_cb = CheckpointCallback(
        save_freq=max(100_000 // args.n_envs, 1),
        save_path="ckpts",
        name_prefix="ball_ppo",
    )

    if args.load:
        model = PPO.load(args.load, env=env)
    else:
        model = PPO(
            "MlpPolicy",
            env,
            verbose=1,
            n_steps=512,          # per env: 512 decisions ~= 34 in-game seconds
            batch_size=2048,
            gamma=0.995,
            gae_lambda=0.95,
            learning_rate=3e-4,
            ent_coef=0.01,        # stay curious early on
            policy_kwargs=dict(net_arch=[128, 128]),
        )

    try:
        model.learn(total_timesteps=args.total_steps, callback=checkpoint_cb)
    finally:
        import os
        os.makedirs("models", exist_ok=True)
        model.save("models/ball_ppo")
        env.close()
        print("Model saved to models/ball_ppo.zip")


if __name__ == "__main__":
    main()
