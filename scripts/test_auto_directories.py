#!/usr/bin/env python3
"""Check automatic directory abbreviations against a temporary directory tree."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FISH_CONFIG = ROOT / "home/.config/fish"
FISH = shutil.which("fish")
SETUP = '''
source "$argv[1]/conf.d/30-auto-directories.fish"
source "$argv[1]/functions/__auto_directory.fish"
set -g auto_directory_root "$argv[2]"
'''


@unittest.skipUnless(FISH, "Fish is required")
class AutoDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="auto-directory-test-")
        self.root = Path(self.directory.name).resolve()

    def tearDown(self):
        self.directory.cleanup()

    def fish(self, code, name):
        return subprocess.run(
            [FISH, "--no-config", "--interactive", "--command", SETUP + code,
             str(FISH_CONFIG), str(self.root), name],
            capture_output=True, text=True, env=dict(os.environ, TERM="xterm-256color"),
        )

    def lookup(self, name):
        return self.fish('__auto_directory "$argv[3]"; exit $status', name)

    def test_unique_path_is_escaped_and_enters_directory(self):
        destination = self.root / "parent with spaces & symbols" / "проект"
        destination.mkdir(parents=True)
        result = self.fish('''
set -l expansion (__auto_directory "$argv[3]"); or exit 1
eval "$expansion"; or exit 1
command /bin/pwd -P
''', "проект")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(destination))

    def test_created_renamed_and_deleted_after_loading(self):
        result = self.fish('''
__auto_directory "$argv[3]" >/dev/null; and exit 10
command /bin/mkdir "$argv[2]/$argv[3]"; or exit 11
__auto_directory "$argv[3]" >/dev/null; or exit 12
command /bin/mv "$argv[2]/$argv[3]" "$argv[2]/renamed-project"; or exit 13
__auto_directory "$argv[3]" >/dev/null; and exit 14
__auto_directory renamed-project >/dev/null; or exit 15
command /bin/rmdir "$argv[2]/renamed-project"; or exit 16
__auto_directory renamed-project >/dev/null; and exit 17
exit 0
''', "fresh-project")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_duplicate_names_do_not_choose_a_directory(self):
        for parent in ("first", "second"):
            (self.root / parent / "duplicate-project").mkdir(parents=True)
        result = self.lookup("duplicate-project")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("несколько папок", result.stderr)

    def test_commands_keywords_functions_and_manual_abbreviations_win(self):
        for name in ("git", "if", "manual-project", "custom-command"):
            (self.root / name).mkdir()
        self.assertNotEqual(self.lookup("git").returncode, 0)
        self.assertNotEqual(self.lookup("if").returncode, 0)
        result = self.fish('''
abbr --add manual-project 'echo manual'
__auto_directory "$argv[3]"; exit $status
''', "manual-project")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        result = self.fish('''
function custom-command; true; end
__auto_directory "$argv[3]"; exit $status
''', "custom-command")
        self.assertNotEqual(result.returncode, 0)

    def test_service_directories_and_symlinks_are_excluded(self):
        for parent in ("Library", "node_modules", "config-backups", ".hidden", "target", "Demo.app"):
            (self.root / parent / "service-project").mkdir(parents=True)
        self.assertNotEqual(self.lookup("service-project").returncode, 0)
        actual = self.root / "ordinary" / "service-project"
        actual.mkdir(parents=True)
        result = self.lookup("service-project")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(actual), result.stdout)
        (self.root / "linked-project").symlink_to(actual, target_is_directory=True)
        self.assertNotEqual(self.lookup("linked-project").returncode, 0)


if __name__ == "__main__":
    unittest.main()
