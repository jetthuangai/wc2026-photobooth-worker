"""Idempotent model downloader. Runs at container startup; skips files already on the network volume."""
import os
import sys
from pathlib import Path

from huggingface_hub import hf_hub_download

VOLUME = Path(os.environ.get("MODELS_VOLUME", "/runpod-volume"))
MODELS_DIR = VOLUME / "models"

DOWNLOADS = [
    {
        "repo_id": "black-forest-labs/FLUX.2-klein-9B",
        "filename": "flux-2-klein-9b.safetensors",
        "subdir": "diffusion_models",
        "rename_to": None,
    },
    {
        "repo_id": "Comfy-Org/vae-text-encorder-for-flux-klein-9b",
        "filename": "split_files/text_encoders/qwen_3_8b.safetensors",
        "subdir": "text_encoders",
        "rename_to": "qwen_3_8b.safetensors",
    },
    {
        "repo_id": "black-forest-labs/FLUX.2-small-decoder",
        "filename": "full_encoder_small_decoder.safetensors",
        "subdir": "vae",
        "rename_to": "Flux2-small-decode.safetensors",
    },
    {
        "repo_id": "fal/flux-klein-9b-virtual-tryon-lora",
        "filename": "flux-klein-tryon-comfy.safetensors",
        "subdir": "loras",
        "rename_to": None,
    },
]


def _download(item: dict, token: str | None) -> None:
    dest_dir = MODELS_DIR / item["subdir"]
    dest_dir.mkdir(parents=True, exist_ok=True)
    target_name = item["rename_to"] or Path(item["filename"]).name
    target_path = dest_dir / target_name
    if target_path.exists() and target_path.stat().st_size > 1024 * 1024:
        print(f"[skip] {target_path}")
        return
    print(f"[get ] {item['repo_id']}/{item['filename']} -> {target_path}")
    downloaded = hf_hub_download(
        repo_id=item["repo_id"],
        filename=item["filename"],
        local_dir=str(dest_dir / "_hf_cache"),
        token=token,
    )
    Path(downloaded).replace(target_path)


def main() -> int:
    if not MODELS_DIR.parent.exists():
        print(f"[err ] Volume {VOLUME} not mounted, skipping downloads")
        return 0
    token = os.environ.get("HF_TOKEN")
    if not token:
        print("[warn] HF_TOKEN not set; gated repos may fail")
    for item in DOWNLOADS:
        _download(item, token)
    print("[done] All models present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
