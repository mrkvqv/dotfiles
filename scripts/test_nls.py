#!/usr/bin/env python3
"""Regression checks for Git colors, white target, plain output and exit status."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import shutil
import struct
import subprocess
import tempfile
import termios
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "home/.config/fish/nls_table.py"


def terminal_output(arguments, no_color=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
    environment = dict(os.environ, TERM="xterm-256color")
    environment.pop("NO_COLOR", None)
    if no_color:
        environment["NO_COLOR"] = "1"
    process = subprocess.Popen(["/usr/bin/python3", str(WRAPPER), *arguments], stdout=slave, stderr=slave, env=environment)
    os.close(slave)
    output = b""
    try:
        while True:
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output += chunk
    finally:
        os.close(master)
    if process.wait() != 0:
        raise AssertionError(output.decode())
    return output.decode()


@unittest.skipUnless(shutil.which("nls"), "nls is required")
class ListingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "changed.txt").write_text("before")
        (self.root / "clean.txt").write_text("unchanged")
        (self.root / ".gitignore").write_text("target/\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Config Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-qm", "Baseline"], check=True)
        (self.root / "changed.txt").write_text("after")
        (self.root / "new.txt").write_text("new")
        (self.root / "a target").write_text("new")
        (self.root / "target").mkdir()

    def tearDown(self):
        self.directory.cleanup()

    def test_git_colors_and_target(self):
        output = terminal_output([str(self.root)])
        self.assertRegex(output, r"\x1b\[38;2;240;177;106m[^\n]*changed\.txt")
        self.assertRegex(output, r"\x1b\[38;2;114;242;212m[^\n]*new\.txt")
        self.assertRegex(output, r"\x1b\[38;2;114;242;212m[^\n]*a target")
        row = next(line for line in output.splitlines() if re.search(r"\s+target\s*│", line))
        name = row.split("│")[2]
        self.assertNotIn("\x1b", name)
        self.assertIn("\x1b[1;38;2;189;167;232m", output)

    def test_no_color_option_and_environment(self):
        self.assertNotIn("\x1b", terminal_output(["--no-color", str(self.root)]))
        self.assertNotIn("\x1b", terminal_output([str(self.root)], no_color=True))

    def test_pipe_and_error_status(self):
        for arguments in [[str(self.root)], [str(self.root / "missing")]]:
            direct = subprocess.run([shutil.which("nls"), *arguments], capture_output=True)
            wrapped = subprocess.run(["/usr/bin/python3", str(WRAPPER), *arguments], capture_output=True)
            self.assertEqual(direct.returncode, wrapped.returncode)
            self.assertEqual(direct.stdout, wrapped.stdout)


if __name__ == "__main__":
    unittest.main()
