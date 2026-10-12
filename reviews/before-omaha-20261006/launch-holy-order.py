#!/usr/bin/env python3
"""Start Holy Order at its title screen, using the bundled local Godot engine."""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BASE = Path(__file__).resolve().parent
ENGINE = BASE / "tools/godot"
RUNTIME = BASE / "runtime"


def focus_existing(runtime):
    try:
        state = json.loads((runtime / "process.json").read_text())
        if not shutil.which("hyprctl"):
            return
        windows = json.loads(subprocess.check_output(["hyprctl", "-j", "clients"], text=True, timeout=3))
        for window in windows:
            if window.get("pid") == state.get("game_pid"):
                address = window["address"]
                if all(c in "0123456789abcdefx" for c in address):
                    subprocess.run(["hyprctl", "dispatch", 'hl.dsp.focus({window="address:' + address + '"})'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check required files without opening the game")
    parser.add_argument("--mission", choices=("ardennes", "desert"), default="ardennes", help="Choose the winter convoy or original desert mission")
    args = parser.parse_args()
    runtime = RUNTIME / args.mission
    scene = "scenes/ardennes.tscn" if args.mission == "ardennes" else "scenes/main.tscn"
    script = "scripts/ardennes/battle.gd" if args.mission == "ardennes" else "scripts/game.gd"
    required = [ENGINE, BASE / "project.godot", BASE / scene, BASE / script]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError("Required files are missing:\n" + "\n".join(missing))
    if args.check:
        result = subprocess.run([str(ENGINE), "--version"], capture_output=True, text=True, timeout=15, check=True)
        print("Holy Order / " + args.mission + ": ready\nEngine: " + result.stdout.strip() + "\nLaunch destination: start screen")
        return 0
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / "launch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            focus_existing(runtime)
            return 0
        logs = BASE / "logs"
        logs.mkdir(exist_ok=True)
        log_path = logs / ("play-" + args.mission + "-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + ".log")
        env = os.environ.copy()
        for kind in ("data", "config", "cache"):
            path = runtime / kind
            path.mkdir(exist_ok=True)
            env["XDG_" + kind.upper() + "_HOME"] = str(path)
        command = [str(ENGINE), "--path", str(BASE), "res://" + scene]
        if env.get("WAYLAND_DISPLAY"):
            command += ["--display-driver", "wayland"]
        with log_path.open("w") as log:
            process = subprocess.Popen(command, cwd=BASE, env=env, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT)
            state = {"wrapper_pid": os.getpid(), "game_pid": process.pid, "log": str(log_path),
                     "starts_at": "title", "mission": args.mission, "status": "running", "automatic_shutdown": False}
            (runtime / "process.json").write_text(json.dumps(state, indent=2) + "\n")
            result = process.wait()
            state.update(status="exited", exit_code=result)
            (runtime / "process.json").write_text(json.dumps(state, indent=2) + "\n")
        if result:
            raise RuntimeError("Holy Order stopped unexpectedly. The log is here:\n" + str(log_path))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        if shutil.which("zenity"):
            subprocess.run(["zenity", "--error", "--title=Holy Order", "--no-markup", "--text=" + str(error)])
        raise SystemExit(1)
