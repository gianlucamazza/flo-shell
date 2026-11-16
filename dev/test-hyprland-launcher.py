#!/usr/bin/env python3
"""Exercise config selection without starting a compositor on the desktop."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.config = self.base / "config" / "flo-shell"
        self.config.mkdir(parents=True)
        for name, body in {
            "Hyprland": '#!/bin/sh\nif [ "$1" = --version ]; then\n printf "Hyprland %s built for test\\n" "$TEST_VERSION"\nelse\n printf "%s\\n" "$@"\nfi\n',
            "start-hyprland": '#!/bin/sh\nprintf "%s\\n" "$@"\n',
        }.items():
            p = self.bin / name
            p.write_text(body)
            p.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin",
                    "FLO_SHELL_DATA": str(ROOT), "XDG_CONFIG_HOME": str(self.base / "config")}
        for key in ("FLO_HYPRLAND_CONF", "FLO_GREETER_CONF"):
            self.env.pop(key, None)

    def launch(self, version, mode="session", **extra):
        return subprocess.run(["/bin/sh", str(ROOT / "session/flo-hyprland.in"), mode],
                              env={**self.env, "TEST_VERSION": version, **extra},
                              text=True, capture_output=True)

    def test_packaged_config_matches_compositor(self):
        for version, ext in [("0.54.3", "conf"), ("0.55.0", "lua"),
                             ("0.56.2", "lua"), ("0.57.0", "lua"), ("1.0.0", "lua")]:
            for mode, name in [("session", "hyprland"), ("greeter", "greeter-hyprland")]:
                with self.subTest(version=version, mode=mode):
                    r = self.launch(version, mode)
                    self.assertEqual(r.returncode, 0, r.stderr)
                    self.assertEqual(r.stdout.splitlines(), ["--", "-c", str(ROOT / f"session/{name}.{ext}")])

    def test_user_config_and_explicit_override(self):
        for ext, version in [("conf", "0.54.3"), ("lua", "0.57.0")]:
            p = self.config / f"hyprland.{ext}"
            p.touch()
            self.assertEqual(self.launch(version).stdout.splitlines()[-1], str(p))
        override = self.base / "custom config.lua"
        override.touch()
        for mode, key in [("session", "FLO_HYPRLAND_CONF"), ("greeter", "FLO_GREETER_CONF")]:
            self.assertEqual(self.launch("0.57.0", mode, **{key: str(override)}).stdout.splitlines()[-1], str(override))

    def test_legacy_user_config_is_not_silently_discarded(self):
        p = self.config / "hyprland.conf"
        p.touch()
        self.assertEqual(self.launch("0.56.2").stdout.splitlines()[-1], str(p))
        r = self.launch("0.57.0")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Lua", r.stderr)
        self.assertEqual(r.stdout, "")

    def test_missing_explicit_config_fails_before_compositor(self):
        r = self.launch("0.54.3", FLO_HYPRLAND_CONF=str(self.base / "missing.conf"))
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_unknown_version_fails_before_compositor(self):
        r = self.launch("unknown")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_direct_compositor_when_supervisor_unavailable(self):
        (self.bin / "start-hyprland").unlink()
        (self.bin / "sed").symlink_to("/usr/bin/sed")
        self.env["PATH"] = str(self.bin)
        r = self.launch("0.57.0")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["-c", str(ROOT / "session/hyprland.lua")])


if __name__ == "__main__":
    unittest.main()
