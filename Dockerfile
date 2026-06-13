# Worker image with models BAKED IN (production: faster cold-start model load
# from local disk vs network volume, and no datacenter lock from a volume).
# Base = RunPod's maintained ComfyUI image (Python 3.12 + uv venv + torch/CUDA).
#
# This image is ~40GB and must be built where there is enough disk (NOT GitHub
# Actions). Build locally with a BuildKit secret so the HF token is never baked
# into the image:
#   printf '%s' "<HF_TOKEN>" > hf_token.txt
#   DOCKER_BUILDKIT=1 docker build --secret id=hf_token,src=hf_token.txt \
#     -t ghcr.io/jetthuangai/wc2026-photobooth-worker:2.0.0 .
#   docker push ghcr.io/jetthuangai/wc2026-photobooth-worker:2.0.0
FROM runpod/worker-comfyui:5.8.5-base

ENV PATH="/opt/venv/bin:${PATH}"
ENV COMFY_DIR=/comfyui \
    HF_HUB_ENABLE_HF_TRANSFER=1

# Bring ComfyUI core to the latest master for FLUX.2 Klein 9B support
# (comfy_kitchen / comfy_aimdo backends). torch stays as the base provides it.
RUN cd ${COMFY_DIR} \
    && git fetch origin master \
    && git reset --hard FETCH_HEAD \
    && uv pip install -r requirements.txt

# Custom nodes (NH-Nodes) used by the workflow.
RUN git clone --depth 1 https://github.com/jetthuangai/NH-Nodes.git ${COMFY_DIR}/custom_nodes/NH-Nodes \
    && if [ -f ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt ]; then \
         uv pip install -r ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt; \
       fi

# Runtime deps for the handler/downloader.
RUN uv pip install Pillow "huggingface_hub[hf_transfer]"

# --- Bake models into the image (big, stable layer kept BEFORE app code so
#     editing handler.py does not re-download 32GB) ---
COPY download_models.py /download_models.py
RUN --mount=type=secret,id=hf_token \
    HF_TOKEN="$(cat /run/secrets/hf_token 2>/dev/null)" MODELS_VOLUME=${COMFY_DIR} \
    python /download_models.py \
    && rm -rf ${COMFY_DIR}/models/*/_hf_cache

# --- App code (changes often → placed after the model layer) ---
COPY workflow_api.json /workflow_api.json
COPY handler.py /handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
