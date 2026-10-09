FROM pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HF_HOME=/workspace/.cache/huggingface
RUN apt-get update && apt-get install -y --no-install-recommends git git-lfs ffmpeg tini ca-certificates openssh-server && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv==0.9.13
WORKDIR /opt
ARG LTX_REF=main
RUN git clone https://github.com/Lightricks/LTX-2.git /opt/LTX-2 && cd /opt/LTX-2 && git checkout "$LTX_REF"
WORKDIR /opt/LTX-2
RUN uv sync --extra natten || uv sync
RUN uv pip install --python /opt/LTX-2/.venv/bin/python fastapi uvicorn huggingface_hub hf-xet safetensors
COPY . /opt/mashhad/
RUN chmod +x /opt/mashhad/boot.sh /opt/mashhad/generate.sh && mkdir -p /workspace /run/sshd
ENV PATH=/opt/LTX-2/.venv/bin:$PATH
EXPOSE 8000
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["bash","/opt/mashhad/boot.sh"]
