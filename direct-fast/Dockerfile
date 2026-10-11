FROM pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime

ARG LTX_REF=2d6e71c88be37b55a2dd698c2dff447edfbe5898
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace/LTX25/.hf-cache \
    HF_HUB_DISABLE_XET=1 \
    HF_HUB_DOWNLOAD_TIMEOUT=120 \
    HF_HUB_ETAG_TIMEOUT=30 \
    PATH=/opt/LTX-2/.venv/bin:/opt/conda/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl ffmpeg git git-lfs openssh-server tini \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /workspace

RUN pip install --no-cache-dir uv==0.9.13
RUN git clone --filter=blob:none https://github.com/Lightricks/LTX-2.git /opt/LTX-2 \
 && git -C /opt/LTX-2 fetch --depth 1 origin "$LTX_REF" \
 && git -C /opt/LTX-2 checkout --detach "$LTX_REF"
WORKDIR /opt/LTX-2
RUN python -m venv --system-site-packages /opt/LTX-2/.venv \
 && /opt/LTX-2/.venv/bin/python -m pip install --disable-pip-version-check --no-deps \
      --index-url https://download.pytorch.org/whl/cu128 \
      "torchvision==0.24.1+cu128" "torchaudio==2.9.1+cu128" \
 && /opt/LTX-2/.venv/bin/python -m pip install --disable-pip-version-check \
      -e /opt/LTX-2/packages/ltx-core \
      -e /opt/LTX-2/packages/ltx-pipelines \
      "huggingface_hub>=0.34,<2" safetensors hf-xet \
 && /opt/LTX-2/.venv/bin/python -m pip install --disable-pip-version-check --no-deps \
      "natten==0.21.5+torch290cu128" --find-links https://whl.natten.org \
 && /opt/LTX-2/.venv/bin/python -c "import torch, torchvision, torchaudio; assert torch.__version__.startswith('2.9.1'); assert torchvision.__version__.startswith('0.24.1'); assert torchaudio.__version__.startswith('2.9.1'); assert (torch.version.cuda or '').startswith('12.8')"

COPY boot.sh download.py models.py /opt/mashhad/
RUN chmod +x /opt/mashhad/boot.sh

EXPOSE 22 8000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "/opt/mashhad/boot.sh"]
