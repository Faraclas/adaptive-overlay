#!/usr/bin/env python3
import os
import select
import sys
import time
from pathlib import Path

MEASURE_INTERVAL_SECONDS = 5


def find_default_build_dir() -> Path | None:
    tmpdir = Path(os.environ.get("PORTAGE_TMPDIR", "/var/tmp"))
    base = tmpdir / "portage" / "app-editors"
    if not base.is_dir():
        return None
    candidates = sorted(
        [p for p in base.iterdir() if p.is_dir() and p.name.startswith("zed-")],
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def get_dir_size_bytes(path: Path) -> int:
    total = 0
    stack = [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as it:
                for entry in it:
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            stack.append(Path(entry.path))
                        elif entry.is_file(follow_symlinks=False):
                            total += entry.stat(follow_symlinks=False).st_size
                    except (FileNotFoundError, PermissionError):
                        continue
        except (FileNotFoundError, PermissionError):
            continue
    return total


def format_gib(bytes_value: int) -> str:
    gib = bytes_value / (1024**3)
    return f"{gib:.2f}G"


def get_ram_usage_bytes(target: Path) -> int:
    total = 0
    try:
        target_path = target.resolve()
    except OSError:
        target_path = target

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        proc_dir = Path("/proc") / pid
        match = False

        try:
            cwd = (proc_dir / "cwd").resolve()
            if str(cwd).startswith(str(target_path)):
                match = True
        except (FileNotFoundError, PermissionError, RuntimeError, OSError):
            pass

        if not match:
            try:
                cmdline = (proc_dir / "cmdline").read_text(errors="ignore")
                if str(target_path) in cmdline:
                    match = True
            except (FileNotFoundError, PermissionError, OSError):
                pass

        if not match:
            continue

        try:
            with open(proc_dir / "status", "r", encoding="utf-8") as handle:
                for line in handle:
                    if line.startswith("VmRSS:"):
                        rss_kb = int(line.split()[1])
                        total += rss_kb * 1024
                        break
        except (FileNotFoundError, PermissionError, OSError, ValueError):
            continue

    return total


def main() -> int:
    if len(sys.argv) > 1:
        target = Path(sys.argv[1]).expanduser()
    else:
        target = find_default_build_dir()

    if not target:
        print("Measuring <unknown>")
        print(
            "Could not locate a default build directory. Pass a path as the first argument."
        )
        return 1

    print(f"Measuring {target}")

    peak_bytes = 0
    peak_ram_bytes = 0
    has_output = False

    try:
        while True:
            if not target.exists():
                current_bytes = 0
            else:
                current_bytes = get_dir_size_bytes(target)

            current_ram_bytes = get_ram_usage_bytes(target)

            if current_bytes > peak_bytes:
                peak_bytes = current_bytes
            if current_ram_bytes > peak_ram_bytes:
                peak_ram_bytes = current_ram_bytes

            line1 = f"Using {format_gib(current_bytes)} of disk space, {format_gib(peak_bytes)} peak."
            line2 = f"Using {format_gib(current_ram_bytes)} of RAM, {format_gib(peak_ram_bytes)} peak."
            line3 = "(q)uit when ready."

            if has_output:
                print("\r\x1b[2A", end="")
            print(f"\x1b[2K{line1}")
            print(f"\x1b[2K{line2}")
            print(f"\x1b[2K{line3}", end="", flush=True)
            has_output = True

            start = time.time()
            while time.time() - start < MEASURE_INTERVAL_SECONDS:
                if select.select([sys.stdin], [], [], 0.1)[0]:
                    user_input = sys.stdin.readline().strip().lower()
                    if user_input == "q":
                        raise KeyboardInterrupt
    except KeyboardInterrupt:
        print()  # move to new line
        print(
            f"Peak usage: {format_gib(peak_bytes)} disk, {format_gib(peak_ram_bytes)} RAM"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
