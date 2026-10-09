#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /workspace/logs /workspace/inputs /workspace/outputs
exec > >(tee -a "/workspace/logs/boot_$(date -u +%Y%m%d_%H%M%S).log") 2>&1
echo "BOOT_BEGIN=$(date -u +%FT%TZ)"
: "${DIRECT_API_TOKEN:?Set DIRECT_API_TOKEN as RunPod environment secret}"
if [ -n "${PUBLIC_KEY:-}" ]; then
 install -dm700 /root/.ssh
 printf '%s\n' "$PUBLIC_KEY" >/root/.ssh/authorized_keys
 chmod 600 /root/.ssh/authorized_keys
 /usr/sbin/sshd
fi
cd /opt/mashhad
python download.py
echo "MODELS_VERIFIED=$(date -u +%FT%TZ)"
exec uvicorn server:app --host 0.0.0.0 --port 8000 --workers 1
