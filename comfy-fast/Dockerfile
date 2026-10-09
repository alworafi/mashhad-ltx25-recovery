FROM pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime

ARG COMFYUI_REF=651ca296a73cd21c12a57eb8741d52e40dc6528f
ARG LTX_NODE_REF=bf2ca0264f706db64cb8931155695ca481fc9d91
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace/LTX25/.hf-cache \
    HF_HUB_DISABLE_XET=1 \
    HF_HUB_DOWNLOAD_TIMEOUT=120 \
    HF_HUB_ETAG_TIMEOUT=30 \
    PATH=/opt/ComfyUI/.venv/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl ffmpeg git git-lfs libgl1 libglib2.0-0 openssh-server tini \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /workspace

RUN pip install --no-cache-dir uv==0.9.13
RUN git clone --filter=blob:none https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && git -C /opt/ComfyUI fetch --depth 1 origin "$COMFYUI_REF" \
 && git -C /opt/ComfyUI checkout --detach "$COMFYUI_REF" \
 && git clone --filter=blob:none https://github.com/Lightricks/ComfyUI-LTXVideo.git /opt/ComfyUI/custom_nodes/ComfyUI-LTXVideo \
 && git -C /opt/ComfyUI/custom_nodes/ComfyUI-LTXVideo fetch --depth 1 origin "$LTX_NODE_REF" \
 && git -C /opt/ComfyUI/custom_nodes/ComfyUI-LTXVideo checkout --detach "$LTX_NODE_REF"

RUN uv venv --python "$(command -v python)" --system-site-packages /opt/ComfyUI/.venv \
 && uv pip install --python /opt/ComfyUI/.venv/bin/python -r /opt/ComfyUI/requirements.txt \
 && if [ -f /opt/ComfyUI/custom_nodes/ComfyUI-LTXVideo/requirements.txt ]; then \
      uv pip install --python /opt/ComfyUI/.venv/bin/python -r /opt/ComfyUI/custom_nodes/ComfyUI-LTXVideo/requirements.txt; \
    fi \
 && uv pip install --python /opt/ComfyUI/.venv/bin/python \
      "huggingface_hub>=0.34,<2" safetensors hf-xet \
 && /opt/ComfyUI/.venv/bin/python -c "import torch, aiohttp, safetensors, transformers; print(torch.__version__, torch.version.cuda)"

COPY boot.sh download.py models.py /opt/mashhad/
RUN chmod +x /opt/mashhad/boot.sh

EXPOSE 22 8000 8188
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "/opt/mashhad/boot.sh"]
