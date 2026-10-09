FROM pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime

ARG LTX_REF=2d6e71c88be37b55a2dd698c2dff447edfbe5898
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace/LTX25/.hf-cache \
    HF_HUB_DISABLE_XET=1 \
    HF_HUB_DOWNLOAD_TIMEOUT=120 \
    HF_HUB_ETAG_TIMEOUT=30 \
    PATH=/opt/LTX-2/.venv/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
RUN uv sync --no-dev --extra natten \
 && uv pip install --python /opt/LTX-2/.venv/bin/python \
      "huggingface_hub>=0.34,<2" safetensors hf-xet

COPY boot.sh download.py models.py /opt/mashhad/
RUN chmod +x /opt/mashhad/boot.sh

EXPOSE 22 8000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "/opt/mashhad/boot.sh"]
