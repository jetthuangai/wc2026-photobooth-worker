#!/usr/bin/env bash
set -euo pipefail

VOLUME="${MODELS_VOLUME:-/runpod-volume}"
MODELS_BASE="${VOLUME}/models"

echo "[start] Volume: ${VOLUME}"
if [ -d "${VOLUME}" ]; then
  python /download_models.py
else
  echo "[start] WARNING: ${VOLUME} not mounted; ComfyUI will look for models in the image."
fi

mkdir -p /ComfyUI/models/diffusion_models /ComfyUI/models/text_encoders /ComfyUI/models/vae /ComfyUI/models/loras
for sub in diffusion_models text_encoders vae loras; do
  if [ -d "${MODELS_BASE}/${sub}" ]; then
    for f in "${MODELS_BASE}/${sub}"/*; do
      [ -e "$f" ] || continue
      ln -sfn "$f" "/ComfyUI/models/${sub}/$(basename "$f")"
    done
  fi
done

echo "[start] Symlinked models:"
ls -la /ComfyUI/models/diffusion_models/ /ComfyUI/models/text_encoders/ /ComfyUI/models/vae/ /ComfyUI/models/loras/ || true

echo "[start] Launching ComfyUI on 127.0.0.1:8188"
cd /ComfyUI
python main.py --listen 127.0.0.1 --port 8188 --disable-auto-launch &

echo "[start] Launching RunPod handler"
exec python /handler.py
