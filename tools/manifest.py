#!/usr/bin/env python3
"""Write <dump>/manifest.json: game version, date, device, and every file's size + sha256."""
import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dump", type=Path)
    ap.add_argument("--version", required=True)
    ap.add_argument("--device", required=True)
    ap.add_argument("--root", default="no")
    a = ap.parse_args()
    files = sorted(p for p in a.dump.rglob("*") if p.is_file() and p.name != "manifest.json")
    entries = [{"path": str(p.relative_to(a.dump)), "size": p.stat().st_size, "sha256": sha256(p)} for p in files]
    exts = Counter((p.suffix or p.name).lower() for p in files)
    manifest = {"game": "com.nintendo.zaba", "version": a.version, "device": a.device, "root": a.root == "yes",
                "dumped_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "files": len(entries), "bytes": sum(e["size"] for e in entries),
                "extensions": dict(exts.most_common()), "entries": entries}
    (a.dump / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"{len(entries)} files, {manifest['bytes'] / 1e9:.2f} GB -> {a.dump}/manifest.json")
    print("  " + ", ".join(f"{k} {v}" for k, v in exts.most_common(12)))


if __name__ == "__main__":
    main()
