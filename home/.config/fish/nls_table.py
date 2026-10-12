"""Style table headings and row numbers while preserving file/Git colors."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import struct
import shutil
import subprocess
import sys
import termios

executable = shutil.which("nls")
if executable is None:
    print("ls: nls is not installed", file=sys.stderr)
    sys.exit(127)
args = [executable, *sys.argv[1:]]
plain_flags = {"--no-color", "--plain", "--json", "--help", "--version", "-1", "-m"}
if not sys.stdout.isatty() or os.environ.get("NO_COLOR") or plain_flags.intersection(sys.argv[1:]):
    os.execv(args[0], args)

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from theme_utils import ansi_color, color, load_style

reset = "\033[0m"
ansi = re.compile(r"\x1b\[[0-9;]*m")
columns = []
try:
    style = load_style()
except (OSError, ValueError, KeyError, StopIteration, TypeError):
    style = {}
git_colors = {"92": color(style, "created", "#72f2d4"), "33": color(style, "modified", "#f0b16a")}
accent = ansi_color(color(style, "terminal.ansi.magenta", "#bda7e8"), bold=True)


def git_color(match):
    return ansi_color(git_colors[match[1]])


def highlight(match):
    return match[1] + accent + match[2] + reset + match[3]


def render(line):
    global columns
    plain = ansi.sub("", line)
    if re.match(r"^│\s*#\s*│", plain):
        columns = [cell.strip() for cell in plain.split("│")[1:-1]]
        line = re.sub(r"(│\s*)([^│\s][^│]*?)(\s*)(?=│)", highlight, plain)
    elif plain.startswith("│") and columns:
        cells = line.split("│")
        for index, column in enumerate(columns, 1):
            if index >= len(cells) - 1:
                break
            if column not in ("name", "git"):
                cells[index] = ansi.sub("", cells[index])
            if column == "name":
                cells[index] = re.sub(r"\x1b\[(92|33)m", git_color, cells[index])
                name = ansi.sub("", cells[index])
                if re.fullmatch(r"(?:[^\w\s]\s+)?target/?", name.strip()):
                    cells[index] = name
            if column == "#":
                cells[index] = re.sub(r"^(\s*)(\d+)(\s*)$", highlight, cells[index])
        line = "│".join(cells)
    elif plain.startswith(("╭", "├", "╰")):
        line = plain
    sys.stdout.write(line)


master, slave = pty.openpty()
size = os.get_terminal_size(sys.stdout.fileno())
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", size.lines, size.columns, 0, 0))
process = subprocess.Popen(args, stdout=slave)
os.close(slave)
pending = b""
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
        pending += chunk
        while b"\n" in pending:
            line, pending = pending.split(b"\n", 1)
            render(line.decode("utf-8", errors="replace").rstrip("\r") + "\n")
        sys.stdout.flush()
    if pending:
        render(pending.decode("utf-8", errors="replace"))
    sys.stdout.flush()
except KeyboardInterrupt:
    if process.poll() is None:
        process.terminate()
    process.wait()
    sys.exit(130)
finally:
    os.close(master)
sys.exit(process.wait())
