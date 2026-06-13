FROM nvidia/cuda:13.0.3-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    COMFY_DIR=/ComfyUI

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3-pip git curl ca-certificates \
        ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python3

ARG COMFYUI_REF=master
RUN git clone --depth 1 --branch ${COMFYUI_REF} https://github.com/comfyanonymous/ComfyUI.git ${COMFY_DIR}

WORKDIR ${COMFY_DIR}
# Cài torch theo lệnh CHÍNH THỨC của ComfyUI (Comfy-Org/ComfyUI) cho NVIDIA:
# latest stable torch/torchvision/torchaudio build cho CUDA 13 (cu130).
# Base image phải là CUDA 13 (libcudart.so.13) để khớp — đây là root cause crash trước đó
# (base cu124 cũ + torchaudio mặc định PyPI build cho cu13 → mismatch).
# Cài torch TRƯỚC requirements.txt; ComfyUI để torch/vision/audio không pin nên sẽ giữ bản này.
RUN python -m pip install --upgrade pip \
    && python -m pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130 \
    && python -m pip install -r requirements.txt

RUN git clone --depth 1 https://github.com/jetthuangai/NH-Nodes.git ${COMFY_DIR}/custom_nodes/NH-Nodes \
    && if [ -f ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt ]; then \
         python -m pip install -r ${COMFY_DIR}/custom_nodes/NH-Nodes/requirements.txt; \
       fi

RUN python -m pip install runpod==1.7.7 requests Pillow "huggingface_hub[hf_transfer]"

COPY workflow_api.json /workflow_api.json
COPY handler.py /handler.py
COPY download_models.py /download_models.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENV PYTHONPATH=${COMFY_DIR}:${PYTHONPATH}

CMD ["/start.sh"]
