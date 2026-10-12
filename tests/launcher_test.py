"""Check menu routing and cross-mission locking without opening a desktop window."""
import fcntl
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

SOURCE = Path(__file__).resolve().parents[1] / "launch-holy-order.py"
spec = importlib.util.spec_from_file_location("holy_launcher", SOURCE)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        for name in ["tools/godot", "project.godot", "scenes/menu.tscn", "scripts/menu.gd",
                     "scenes/main.tscn", "scenes/ardennes.tscn", "scenes/omaha.tscn",
                     "scripts/game.gd", "scripts/ardennes/battle.gd", "scripts/omaha/battle.gd"]:
            file = self.base / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.touch()
        self.runtime = self.base / "runtime"
        self.patches = patch.multiple(launcher, BASE=self.base, ENGINE=self.base / "tools/godot", RUNTIME=self.runtime)
        self.patches.start()
        self.addCleanup(self.patches.stop)

    def test_every_legacy_shortcut_opens_same_menu(self):
        for mission in ("ardennes", "desert", "omaha"):
            child = Mock(pid=12345)
            child.wait.return_value = 0
            with patch("sys.argv", [str(SOURCE), "--mission", mission]), patch.object(launcher.subprocess, "Popen", return_value=child) as start:
                self.assertEqual(launcher.main(), 0)
            command = start.call_args.args[0]
            self.assertIn("res://scenes/menu.tscn", command)
            self.assertIn("--preferred-mission=" + mission, command)
            self.assertTrue((self.runtime / "main/process.json").exists())
            self.assertFalse((self.runtime / mission).exists())

    def test_second_shortcut_focuses_running_main_instead_of_loading_another_game(self):
        folder = self.runtime / "main"
        folder.mkdir(parents=True)
        with (folder / "launch.lock").open("a") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch("sys.argv", [str(SOURCE), "--mission", "desert"]), patch.object(launcher, "focus_existing") as focus, patch.object(launcher.subprocess, "Popen") as start:
                self.assertEqual(launcher.main(), 0)
                focus.assert_called_once_with(folder)
                start.assert_not_called()

    def test_running_pre_update_mission_is_also_respected(self):
        folder = self.runtime / "ardennes"
        folder.mkdir(parents=True)
        with (folder / "launch.lock").open("a") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch("sys.argv", [str(SOURCE)]), patch.object(launcher, "focus_existing") as focus, patch.object(launcher.subprocess, "Popen") as start:
                self.assertEqual(launcher.main(), 0)
                focus.assert_called_once_with(folder)
                start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
