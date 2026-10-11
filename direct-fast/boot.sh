#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${MASHHAD_LTX_ROOT:-/workspace/LTX25}"
MODEL_DIR="${LTX_MODELS_DIR:-$ROOT/models/ltx-2.5}"
STATE_DIR="$ROOT/.mashhad"
START_TS="$(date +%s)"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/install_direct_${RUN_ID}.log"

elapsed() {
  local seconds=$(( $(date +%s) - START_TS ))
  printf '%02d:%02d:%02d' "$((seconds/3600))" "$(((seconds%3600)/60))" "$((seconds%60))"
}

mkdir -p "$ROOT/logs" "$ROOT/inputs" "$ROOT/outputs" "$MODEL_DIR" "$STATE_DIR/engines" /run/sshd
exec > >(tee -a "$LOG") 2>&1
printf '%s\n' "$LOG" > "$ROOT/logs/current_install_log"
printf '%s\n' "$START_TS" > "$ROOT/logs/current_start_ts"
rm -f "$ROOT/.MASHHAD_READY_V4" "$STATE_DIR/engines/direct.ready"

echo "=== MASHHAD LTX-2.5 DIRECT DOCKER ==="
echo "Started: $(date -Is)"
echo "Runtime: baked into ghcr.io/alworafi/ltx25-direct-fast"
echo "Models:  $MODEL_DIR"

if [[ "${MASHHAD_PREPARE_ENGINES:-direct}" != "direct" ]]; then
  echo "ERROR: this image supports Direct Python only; select the Direct template." >&2
  exit 2
fi
if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "ERROR: HF_TOKEN is required to download LTX-2.5 models onto the Network Volume." >&2
  exit 2
fi

ssh-keygen -A >/dev/null 2>&1
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  install -dm700 /root/.ssh
  printf '%s\n' "$PUBLIC_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi
/usr/sbin/sshd

if [[ -L "$ROOT/LTX-2" ]]; then
  ln -sfn /opt/LTX-2 "$ROOT/LTX-2"
elif [[ ! -e "$ROOT/LTX-2" ]]; then
  ln -s /opt/LTX-2 "$ROOT/LTX-2"
else
  echo "[REUSE] Preserving the existing Volume checkout at $ROOT/LTX-2; the baked runtime remains at /opt/LTX-2."
fi
printf '%s\n' direct > "$STATE_DIR/prepared_engines"
printf '%s\n' direct > "$STATE_DIR/default_engine"
printf '%s\n' direct > "$STATE_DIR/active_engine"
printf '%s\n' 0 > "$STATE_DIR/comfyui_auto_start"

echo "[1/2] Downloading and validating the five Direct model files in parallel..."
MODEL_DIR="$MODEL_DIR" python /opt/mashhad/download.py

echo "[2/2] Validating the baked Direct runtime..."
/opt/LTX-2/.venv/bin/python - <<'PY'
import torch
import ltx_pipelines
print(f"Direct runtime ready: torch={torch.__version__} cuda={torch.version.cuda}")
PY

date -u +%FT%TZ > "$STATE_DIR/engines/direct.ready"
printf '%s\n' MASHHAD_LTX25_DIRECT_DOCKER_V2 > "$ROOT/.MASHHAD_READY_V4"
echo "INSTALL VERIFIED in $(elapsed)"
echo "Mashhad will now install and start its Worker automatically on port ${MASHHAD_WORKER_PORT:-8000}."

# Port 8000 intentionally remains free for the exact Worker version uploaded by
# the Mashhad control plane after it observes .MASHHAD_READY_V4 over SSH.
exec tail -f /dev/null
