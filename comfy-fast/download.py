from __future__ import annotations

import concurrent.futures
import json
import os
import time
from pathlib import Path

from huggingface_hub import HfApi, hf_hub_download
from safetensors import safe_open

from models import FILES, MODEL_REPO


BASE = Path(os.getenv("MODEL_DIR", "/workspace/LTX25/models/ltx-2.5"))
TOKEN = (os.getenv("HF_TOKEN") or "").strip() or None
WORKERS = max(1, min(8, int(os.getenv("DOWNLOAD_WORKERS", "5"))))


def valid(path: Path, expected: int) -> bool:
    if not path.is_file() or path.stat().st_size != expected:
        return False
    try:
        with safe_open(str(path), framework="pt", device="cpu") as handle:
            return bool(handle.keys())
    except Exception:
        return False


def human_size(size: int) -> str:
    return f"{size / 1_000_000_000:.2f} GB"


def human_duration(seconds: float) -> str:
    seconds = int(round(seconds))
    return f"{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def main() -> None:
    started = time.monotonic()
    BASE.mkdir(parents=True, exist_ok=True)
    info = HfApi(token=TOKEN).model_info(MODEL_REPO, files_metadata=True)
    metadata = {item.rfilename: item.size for item in info.siblings}
    missing = [name for name in FILES if not isinstance(metadata.get(name), int) or metadata[name] <= 0]
    if missing:
        raise RuntimeError(f"Upstream manifest is missing: {missing}")

    def download(relative: str) -> dict:
        destination = BASE / relative
        expected = int(metadata[relative])
        file_started = time.monotonic()
        if valid(destination, expected):
            print(f"CACHED {relative} | {human_size(expected)}", flush=True)
            return {"file": relative, "status": "cached", "size": expected, "seconds": 0}
        destination.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(1, 4):
            try:
                downloaded = Path(hf_hub_download(
                    repo_id=MODEL_REPO,
                    filename=relative,
                    local_dir=str(BASE),
                    token=TOKEN,
                    force_download=attempt > 1,
                ))
                if not valid(downloaded, expected):
                    raise RuntimeError("downloaded file failed size or safetensors validation")
                duration = time.monotonic() - file_started
                speed = expected / max(duration, 0.001) / 1_000_000
                print(
                    f"DOWNLOADED {relative} | {human_size(expected)} | "
                    f"{human_duration(duration)} | {speed:.1f} MB/s",
                    flush=True,
                )
                return {
                    "file": relative,
                    "status": "downloaded",
                    "size": expected,
                    "seconds": round(duration, 2),
                    "average_mbps": round(speed, 2),
                }
            except Exception as exc:
                print(f"RETRY {attempt}/3 {relative}: {exc}", flush=True)
                if attempt == 3:
                    raise
                time.sleep(3 * attempt)
        raise AssertionError("unreachable")

    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        results = list(pool.map(download, FILES))
    total = time.monotonic() - started
    report = {
        "engine": "comfyui",
        "total_size": sum(int(metadata[name]) for name in FILES),
        "total_seconds": round(total, 2),
        "files": results,
    }
    (BASE / "comfyui_download_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(
        f"ALL 7 COMFYUI MODELS READY | {human_size(report['total_size'])} | {human_duration(total)}",
        flush=True,
    )


if __name__ == "__main__":
    main()
