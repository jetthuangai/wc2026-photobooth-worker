# Base on RunPod's officially-maintained ComfyUI worker image to escape the
# torch/CUDA/ComfyUI/python version-matrix hell. It ships:
#   - Python 3.12, uv + venv at /opt/venv
#   - ComfyUI installed via comfy-cli at /comfyui (with a matching torch/CUDA)
#   - runpod, requests, websocket-client preinstalled
# We keep our OWN handler.py (HTTP client to ComfyUI on 127.0.0.1:8188), so the
# frontend contract ({photo, teamId, kit}) does not change.
FROM runpod/worker-comfyui:5.8.5-base

# Use the base image's virtual environment for every subsequent pip/python call.
ENV PATH="/opt/venv/bin:${PATH}"
ENV COMFY_DIR=/comfyui \
    HF_HUB_ENABLE_HF_TRANSFER=1

# Bring ComfyUI core to the latest master for FLUX.2 Klein 9B support
# (comfy_kitchen / comfy_aimdo backends). torch is already installed and left
# unpinned by ComfyUI's requirements, so it is NOT downgraded here.
RUN cd ${COMFY_DIR} \
    && git fetch origin master \
    && git reset --hard FETCH_HEAD \
    && uv pip install -r requirements.txt

# Custom nodes (NH-Nodes) used by the workflow.
RUN git clone --depth 1 https://github.com/jetthuangai/NH-Nodes.git ${COMFY_DIR}/custom_nodes/NH-Nodes \
    && if [ -f ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt ]; then \
         uv pip install -r ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt; \
       fi

# Runtime deps our handler/downloader need on top of the base (Pillow for image
# encoding, hf_transfer for fast model pulls). requests/runpod already present.
RUN uv pip install Pillow "huggingface_hub[hf_transfer]"

# Our application code — override the base image's handler/start.sh with ours.
COPY workflow_api.json /workflow_api.json
COPY handler.py /handler.py
COPY download_models.py /download_models.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
