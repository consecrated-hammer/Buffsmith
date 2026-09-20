#!/usr/bin/env python3
"""Stage a runtime-only Buffsmith folder for local WoW testing."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tempfile
from pathlib import Path


RUNTIME_SUFFIXES = {".lua", ".xml", ".tga", ".blp", ".ogg", ".mp3", ".wav"}
EXCLUDED_PARTS = {".git", ".github", "tests", "tools", "docs", "data", "__pycache__"}


def copy_runtime(source: Path, destination: Path) -> None:
    for path in source.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(part.startswith(".") or part in EXCLUDED_PARTS for part in relative.parts):
            continue
        if path.suffix.lower() not in RUNTIME_SUFFIXES:
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    # Preserve client-specific names. Forever discovers Buffsmith_Camelot.toc,
    # not a Camelot TOC renamed to the generic Buffsmith.toc.
    for toc in source.glob("*.toc"):
        shutil.copy2(toc, destination / toc.name)


def dev_version(toc: Path, existing: Path) -> str:
    source = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8"), re.MULTILINE)
    if not source:
        raise SystemExit(f"TOC has no Version metadata: {toc}")
    base = re.sub(r"-dev-?\d+$", "", source.group(1))
    number = 1
    if existing.is_file():
        prior = re.search(r"^## Version:\s*" + re.escape(base) + r"-dev-?(\d+)\s*$",
                          existing.read_text(encoding="utf-8"), re.MULTILINE)
        if prior:
            number = int(prior.group(1)) + 1
    return f"{base}-dev{number}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--toc", default="Buffsmith_Camelot.toc")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    selected = source / args.toc
    if not selected.is_file() or selected.parent != source:
        raise SystemExit("--toc must name a top-level source TOC")
    output = args.output.resolve()
    if output == source or source in output.parents:
        raise SystemExit("--output must be outside the source repository")
    destination = output / "Buffsmith"
    output.mkdir(parents=True, exist_ok=True)
    stage_root = Path(tempfile.mkdtemp(prefix=".Buffsmith.stage-", dir=output))
    staged = stage_root / "Buffsmith"
    backup = output / ".Buffsmith.previous"
    try:
        staged.mkdir()
        copy_runtime(source, staged)
        staged_toc = staged / selected.name
        existing_toc = destination / selected.name
        disabled_toc = output / "Buffsmith.disabled" / selected.name
        if not existing_toc.is_file() and disabled_toc.is_file():
            existing_toc = disabled_toc
        version = dev_version(selected, existing_toc)
        staged_toc.write_text(re.sub(r"^## Version:\s*.+?$", f"## Version: {version}",
            staged_toc.read_text(encoding="utf-8"), flags=re.MULTILINE), encoding="utf-8")
        if backup.exists(): shutil.rmtree(backup)
        if destination.exists(): os.replace(destination, backup)
        try:
            os.replace(staged, destination)
        except BaseException:
            if backup.exists() and not destination.exists(): os.replace(backup, destination)
            raise
        if backup.exists(): shutil.rmtree(backup)
    finally:
        if stage_root.exists(): shutil.rmtree(stage_root)
    print(f"Staged Buffsmith at {destination} ({version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
