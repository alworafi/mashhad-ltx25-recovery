#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${MASHHAD_LTX_ROOT:-/workspace/LTX25}"
MODEL_DIR="${LTX_MODELS_DIR:-$ROOT/models/ltx-2.5}"
STATE_DIR="$ROOT/.mashhad"
COMFY=/opt/ComfyUI
START_TS="$(date +%s)"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/install_comfyui_${RUN_ID}.log"

elapsed() {
  local seconds=$(( $(date +%s) - START_TS ))
  printf '%02d:%02d:%02d' "$((seconds/3600))" "$(((seconds%3600)/60))" "$((seconds%60))"
}

mkdir -p "$ROOT/logs" "$ROOT/inputs" "$ROOT/outputs" "$MODEL_DIR" "$STATE_DIR/engines" /run/sshd
exec > >(tee -a "$LOG") 2>&1
printf '%s\n' "$LOG" > "$ROOT/logs/current_install_log"
printf '%s\n' "$START_TS" > "$ROOT/logs/current_start_ts"
rm -f "$ROOT/.MASHHAD_READY_V4" "$STATE_DIR/engines/comfyui.ready"

hold_on_error() {
  local status=$?
  trap - ERR
  echo "ERROR: ComfyUI bootstrap stopped with exit code $status after $(elapsed)." >&2
  if [[ "${MASHHAD_HOLD_ON_ERROR:-1}" == "1" ]]; then
    echo "Container kept alive for SSH diagnosis; inspect $LOG and $STATE_DIR/comfyui.log." >&2
    exec sleep infinity
  fi
  exit "$status"
}
trap hold_on_error ERR

echo "=== MASHHAD LTX-2.5 COMFYUI DOCKER ==="
echo "Started: $(date -Is)"
echo "Runtime: baked into ghcr.io/alworafi/ltx25-comfy-fast"
echo "Models:  $MODEL_DIR"

ssh-keygen -A >/dev/null 2>&1
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  install -dm700 /root/.ssh
  printf '%s\n' "$PUBLIC_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi
/usr/sbin/sshd

if [[ "${MASHHAD_PREPARE_ENGINES:-comfyui}" != "comfyui" ]]; then
  echo "ERROR: this image supports ComfyUI only; select the ComfyUI template." >&2
  false
fi
if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "ERROR: HF_TOKEN is required to download LTX-2.5 models onto the Network Volume." >&2
  false
fi

ln -sfn "$COMFY" "$ROOT/ComfyUI"
printf '%s\n' comfyui > "$STATE_DIR/prepared_engines"
printf '%s\n' comfyui > "$STATE_DIR/default_engine"
printf '%s\n' comfyui > "$STATE_DIR/active_engine"
printf '%s\n' 1 > "$STATE_DIR/comfyui_auto_start"

echo "[1/3] Downloading and validating the seven ComfyUI model files in parallel..."
MODEL_DIR="$MODEL_DIR" "$COMFY/.venv/bin/python" /opt/mashhad/download.py

echo "[2/3] Linking persistent model files into the baked ComfyUI runtime..."
for relative in \
  diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors \
  text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors \
  vae/ltx-2.5-video-vae-bf16.safetensors \
  vae/ltx-2.5-audio-vae-bf16.safetensors \
  latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
  latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors \
  loras/ltx-2.5-22b-distilled-lora-450-bf16.safetensors
do
  mkdir -p "$COMFY/models/$(dirname "$relative")"
  ln -sfn "$MODEL_DIR/$relative" "$COMFY/models/$relative"
done

echo "[3/3] Starting ComfyUI and waiting for its API health check..."
nohup "$COMFY/.venv/bin/python" "$COMFY/main.py" --listen 127.0.0.1 --port 8188 \
  > "$STATE_DIR/comfyui.log" 2>&1 &
COMFY_PID=$!
printf '%s\n' "$COMFY_PID" > "$STATE_DIR/comfyui.pid"
for _ in $(seq 1 120); do
  if ! kill -0 "$COMFY_PID" 2>/dev/null; then
    echo "ERROR: ComfyUI stopped before becoming ready." >&2
    tail -100 "$STATE_DIR/comfyui.log" >&2 || true
    false
  fi
  if curl -fsS --max-time 3 http://127.0.0.1:8188/system_stats >/dev/null; then
    date -u +%FT%TZ > "$STATE_DIR/engines/comfyui.ready"
    printf '%s\n' MASHHAD_LTX25_COMFYUI_DOCKER_V1 > "$ROOT/.MASHHAD_READY_V4"
    echo "INSTALL VERIFIED in $(elapsed)"
    echo "ComfyUI is ready internally on port 8188; Mashhad Worker will be installed automatically on port ${MASHHAD_WORKER_PORT:-8000}."
    wait "$COMFY_PID"
    exit $?
  fi
  sleep 1
done

echo "ERROR: ComfyUI did not pass /system_stats within 120 seconds." >&2
tail -100 "$STATE_DIR/comfyui.log" >&2 || true
false
