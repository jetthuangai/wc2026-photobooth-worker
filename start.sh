#!/usr/bin/env bash
set -euo pipefail

VOLUME="${MODELS_VOLUME:-/runpod-volume}"
MODELS_BASE="${VOLUME}/models"
COMFY_DIR="${COMFY_DIR:-/comfyui}"

# Better memory management (same as the RunPod base image start.sh).
TCMALLOC="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1 || true)"
[ -n "${TCMALLOC}" ] && export LD_PRELOAD="${TCMALLOC}"

echo "[start] Volume: ${VOLUME}"
if [ -d "${VOLUME}" ]; then
  python /download_models.py
else
  echo "[start] WARNING: ${VOLUME} not mounted; ComfyUI will look for models in the image."
fi

# Symlink models from the network volume into ComfyUI's model folders.
mkdir -p "${COMFY_DIR}/models/diffusion_models" "${COMFY_DIR}/models/text_encoders" "${COMFY_DIR}/models/vae" "${COMFY_DIR}/models/loras"
for sub in diffusion_models text_encoders vae loras; do
  if [ -d "${MODELS_BASE}/${sub}" ]; then
    for f in "${MODELS_BASE}/${sub}"/*; do
      [ -e "$f" ] || continue
      ln -sfn "$f" "${COMFY_DIR}/models/${sub}/$(basename "$f")"
    done
  fi
done

echo "[start] Symlinked models:"
ls -la "${COMFY_DIR}/models/diffusion_models/" "${COMFY_DIR}/models/text_encoders/" "${COMFY_DIR}/models/vae/" "${COMFY_DIR}/models/loras/" || true

echo "[start] Launching ComfyUI on 127.0.0.1:8188"
cd "${COMFY_DIR}"
python -u main.py --disable-auto-launch --disable-metadata --listen 127.0.0.1 --port 8188 &

echo "[start] Launching RunPod handler"
exec python -u /handler.py
