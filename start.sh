#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/comfyui}"

# Better memory management (same as the RunPod base image start.sh).
TCMALLOC="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1 || true)"
[ -n "${TCMALLOC}" ] && export LD_PRELOAD="${TCMALLOC}"

# Models are baked into the image at ${COMFY_DIR}/models — no network volume,
# no download at startup.
echo "[start] Models (baked):"
ls -la "${COMFY_DIR}/models/diffusion_models/" "${COMFY_DIR}/models/text_encoders/" "${COMFY_DIR}/models/vae/" "${COMFY_DIR}/models/loras/" || true

echo "[start] Launching ComfyUI on 127.0.0.1:8188"
cd "${COMFY_DIR}"
python -u main.py --disable-auto-launch --disable-metadata --listen 127.0.0.1 --port 8188 &

echo "[start] Launching RunPod handler"
exec python -u /handler.py
