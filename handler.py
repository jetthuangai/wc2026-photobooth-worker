import base64
import copy
import io
import json
import os
import time
import uuid
from pathlib import Path

import requests
import runpod
from PIL import Image

COMFY_HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
# ComfyUI workspace is /comfyui in the RunPod base image (lowercase). Derive the
# input/output dirs from COMFY_DIR so the handler writes where ComfyUI reads.
COMFY_DIR = Path(os.environ.get("COMFY_DIR", "/comfyui"))
COMFY_INPUT_DIR = COMFY_DIR / "input"
COMFY_OUTPUT_DIR = COMFY_DIR / "output"
WORKFLOW_PATH = Path("/workflow_api.json")
KITS_BASE_URL = os.environ.get("KITS_BASE_URL", "https://wc2026booth.fun/kits")

USER_IMAGE_NODE = "76"
JERSEY_IMAGE_NODE = "121"
SEED_NODE = "163"

TEMPLATE = json.loads(WORKFLOW_PATH.read_text())


def _wait_for_comfy(timeout: int = 300) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{COMFY_HOST}/system_stats", timeout=2)
            if r.ok:
                return
        except requests.RequestException:
            pass
        time.sleep(1)
    raise RuntimeError(f"ComfyUI not ready after {timeout}s")


def _save_image_from_b64(b64_data: str, dest: Path) -> None:
    if "," in b64_data:
        b64_data = b64_data.split(",", 1)[1]
    raw = base64.b64decode(b64_data)
    img = Image.open(io.BytesIO(raw))
    if img.mode != "RGB":
        img = img.convert("RGB")
    img.save(dest, format="JPEG", quality=92)


_MANIFEST_CACHE = None


def _get_manifest() -> dict:
    global _MANIFEST_CACHE
    if _MANIFEST_CACHE is None:
        try:
            r = requests.get(f"{KITS_BASE_URL.rstrip('/')}/manifest.json", timeout=10)
            r.raise_for_status()
            _MANIFEST_CACHE = r.json().get("teams", {})
        except Exception:
            _MANIFEST_CACHE = {}
    return _MANIFEST_CACHE


def _fetch_jersey(team_id: str, kit: str, dest: Path) -> None:
    # Manifest áo có 4 đuôi (.webp chính, .jpg, .png, .avif) → không hardcode .jpg.
    # Đọc manifest.json để lấy đúng filename; fallback .jpg nếu không có entry.
    team_entry = _get_manifest().get(team_id, {})
    kit_path = team_entry.get(kit) or team_entry.get("home") or team_entry.get("away")
    if kit_path:
        filename = kit_path.split("/")[-1]
        url = f"{KITS_BASE_URL.rstrip('/')}/{filename}"
    else:
        url = f"{KITS_BASE_URL.rstrip('/')}/{team_id}_{kit}.jpg"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    img = Image.open(io.BytesIO(r.content))
    if img.mode != "RGB":
        img = img.convert("RGB")
    img.save(dest, format="JPEG", quality=92)


def _queue_prompt(prompt: dict) -> str:
    r = requests.post(f"{COMFY_HOST}/prompt", json={"prompt": prompt}, timeout=30)
    if not r.ok:
        # ComfyUI returns node_errors detail in the body on a 400 — surface it
        # instead of swallowing it behind raise_for_status().
        try:
            detail = json.dumps(r.json(), ensure_ascii=False)
        except Exception:
            detail = r.text
        raise RuntimeError(f"ComfyUI /prompt {r.status_code}: {detail}")
    return r.json()["prompt_id"]


def _wait_for_output(prompt_id: str, timeout: int = 600) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = requests.get(f"{COMFY_HOST}/history/{prompt_id}", timeout=5)
        if r.ok:
            data = r.json()
            if prompt_id in data:
                return data[prompt_id]
        time.sleep(1)
    raise RuntimeError(f"ComfyUI prompt {prompt_id} did not complete in {timeout}s")


def _read_output_image(history: dict) -> tuple[str, str]:
    outputs = history.get("outputs", {})
    for _node_id, out in outputs.items():
        for img_info in out.get("images", []):
            fname = img_info["filename"]
            subfolder = img_info.get("subfolder", "")
            path = COMFY_OUTPUT_DIR / subfolder / fname
            mime = "image/png" if fname.lower().endswith(".png") else "image/jpeg"
            return base64.b64encode(path.read_bytes()).decode("ascii"), mime
    raise RuntimeError("ComfyUI history contains no images")


def handler(event: dict) -> dict:
    payload = event.get("input") or {}
    photo = payload.get("photo")
    team_id = payload.get("teamId")
    kit = payload.get("kit", "home")

    if not photo or not team_id:
        return {"error": "Missing required input fields: photo, teamId"}

    job_uid = uuid.uuid4().hex[:12]
    user_filename = f"user_{job_uid}.jpg"
    jersey_filename = f"jersey_{job_uid}.jpg"

    COMFY_INPUT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        _save_image_from_b64(photo, COMFY_INPUT_DIR / user_filename)
        _fetch_jersey(team_id, kit, COMFY_INPUT_DIR / jersey_filename)
    except Exception as e:
        return {"error": f"Failed to prepare inputs: {e}"}

    prompt = copy.deepcopy(TEMPLATE)
    prompt[USER_IMAGE_NODE]["inputs"]["image"] = user_filename
    prompt[JERSEY_IMAGE_NODE]["inputs"]["image"] = jersey_filename
    prompt[SEED_NODE]["inputs"]["noise_seed"] = int.from_bytes(os.urandom(7), "big")

    try:
        prompt_id = _queue_prompt(prompt)
        history = _wait_for_output(prompt_id)
        image_b64, mime = _read_output_image(history)
    except Exception as e:
        return {"error": f"ComfyUI inference failed: {e}"}

    return {"imageBase64": image_b64, "mimeType": mime}


_wait_for_comfy(timeout=300)
runpod.serverless.start({"handler": handler})
