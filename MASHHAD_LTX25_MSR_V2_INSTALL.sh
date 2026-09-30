#!/usr/bin/env bash
set -Eeuo pipefail

START_TS=$(date +%s)
ROOT="/workspace/LTX25"
RUNTIME="$ROOT/.runtime"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/install_$(date +%Y%m%d_%H%M%S).log"

elapsed() {
  local now sec h m s
  now=$(date +%s); sec=$((now-START_TS))
  h=$((sec/3600)); m=$(((sec%3600)/60)); s=$((sec%60))
  printf "%02d:%02d:%02d" "$h" "$m" "$s"
}
trap 'rc=$?; echo; echo "ERROR at line $LINENO (exit $rc) after $(elapsed)."; echo "Log: $LOG"; exit $rc' ERR

exec > >(tee -a "$LOG") 2>&1

echo "=== LTX-2.5 FULL RECOVERY SETUP v3 + MSR V2 COMPLETE ==="
echo "Started: $(date)"
echo

# Safety: refuse temporary container storage.
SRC="$(findmnt -T /workspace -n -o SOURCE 2>/dev/null || true)"
if [[ -z "$SRC" || "$SRC" == "overlay" ]]; then
  echo "ERROR: /workspace is not a mounted Network Volume."
  exit 2
fi
echo "Network Volume OK: $SRC"
echo

mkdir -p "$ROOT"/{models,input,output,logs}
mkdir -p "$RUNTIME"/{bin,python,uv-cache}

echo "[1/7] System packages..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git git-lfs ffmpeg curl wget ca-certificates build-essential \
  python3 python3-venv python3-pip
git lfs install || true

echo "[2/7] Persistent uv + Python 3.12..."
if [[ ! -x "$RUNTIME/bin/uv" ]]; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$RUNTIME/bin" sh
fi
export PATH="$RUNTIME/bin:$PATH"
export UV_PYTHON_INSTALL_DIR="$RUNTIME/python"
export UV_CACHE_DIR="$RUNTIME/uv-cache"
uv python install 3.12

repair_venv () {
  local venv="$1"
  if [[ -e "$venv" && ! -x "$venv/bin/python" ]]; then
    echo "Repairing broken venv: $venv"
    rm -rf "$venv"
  fi
  [[ -x "$venv/bin/python" ]] || uv venv --python 3.12 "$venv"
}

echo "[3/7] ComfyUI..."
COMFY="$ROOT/ComfyUI"
if [[ ! -d "$COMFY/.git" ]]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
else
  git -C "$COMFY" pull --ff-only || true
fi

COMFY_VENV="$ROOT/.venv-comfy"
repair_venv "$COMFY_VENV"

uv pip install --python "$COMFY_VENV/bin/python" --upgrade \
  torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
uv pip install --python "$COMFY_VENV/bin/python" -r "$COMFY/requirements.txt"

NODE_DIR="$COMFY/custom_nodes/ComfyUI-LTXVideo"
if [[ ! -d "$NODE_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git "$NODE_DIR"
else
  git -C "$NODE_DIR" pull --ff-only || true
fi
if [[ -f "$NODE_DIR/requirements.txt" ]]; then
  uv pip install --python "$COMFY_VENV/bin/python" -r "$NODE_DIR/requirements.txt"
fi

echo "[3b/7] LTX-2.5 MSR V2 + official workflow support nodes..."
install_custom_node () {
  local repo="$1"
  local dest="$2"
  if [[ ! -d "$dest/.git" ]]; then
    git clone --depth 1 "$repo" "$dest"
  else
    git -C "$dest" pull --ff-only || true
  fi
  if [[ -f "$dest/requirements.txt" ]]; then
    uv pip install --python "$COMFY_VENV/bin/python" -r "$dest/requirements.txt"
  fi
}

MSR_NODE="$COMFY/custom_nodes/ComfyUI-LTX2.5-MSR"
KJ_NODE="$COMFY/custom_nodes/ComfyUI-KJNodes"
RG3_NODE="$COMFY/custom_nodes/rgthree-comfy"
PROMPT_RELAY_NODE="$COMFY/custom_nodes/ComfyUI-PromptRelay"

install_custom_node "https://github.com/liconstudio/ComfyUI-LTX2.5-MSR.git" "$MSR_NODE"
install_custom_node "https://github.com/kijai/ComfyUI-KJNodes.git" "$KJ_NODE"
install_custom_node "https://github.com/rgthree/rgthree-comfy.git" "$RG3_NODE"
install_custom_node "https://github.com/kijai/ComfyUI-PromptRelay.git" "$PROMPT_RELAY_NODE"

echo "[4/7] LTX-2 official repo..."
LTX_REPO="$ROOT/LTX-2"
if [[ ! -d "$LTX_REPO/.git" ]]; then
  git clone --depth 1 https://github.com/Lightricks/LTX-2.git "$LTX_REPO"
else
  git -C "$LTX_REPO" pull --ff-only || true
fi
(
  cd "$LTX_REPO"
  export UV_PYTHON_INSTALL_DIR="$RUNTIME/python"
  export UV_CACHE_DIR="$RUNTIME/uv-cache"
  uv sync --extra natten
)

echo "[5/7] Hugging Face tools..."
TOOLS_VENV="$ROOT/.venv-tools"
repair_venv "$TOOLS_VENV"
uv pip install --python "$TOOLS_VENV/bin/python" --upgrade huggingface_hub hf_xet
HF="$TOOLS_VENV/bin/hf"

if [[ -z "${HF_TOKEN:-}" ]]; then
  echo
  echo "LTX-2.5 is gated. Make sure you already clicked Agree and Access on Hugging Face."
  read -rsp "Paste HF READ token: " HF_TOKEN
  echo
  HF_TOKEN="$(printf '%s' "$HF_TOKEN" | tr -d '\r\n')"
  export HF_TOKEN
fi

# Conservative transfer settings for Network Volumes.
# Disable Xet reconstruction during this install to reduce temporary disk pressure.
export HF_HOME="$ROOT/.hf-cache"
export HF_HUB_DISABLE_XET=1
export HF_HUB_DOWNLOAD_TIMEOUT=120
export HF_HUB_ETAG_TIMEOUT=30

MODEL_ROOT="$ROOT/models/ltx-2.5"
mkdir -p "$MODEL_ROOT"/{diffusion_models,text_encoders,vae,latent_upscale_models,loras}

download_one () {
  local repo="$1"
  local rel="$2"
  local dest="$3"
  local final="$dest/$rel"
  mkdir -p "$(dirname "$final")"

  if [[ -s "$final" ]]; then
    echo "SKIP existing: $rel"
    return 0
  fi

  echo
  echo "Downloading: $rel"
  "$HF" download "$repo" "$rel" --local-dir "$dest"

  # Delete only HF metadata/temp caches after a successful file.
  rm -rf "$dest/.cache/huggingface" 2>/dev/null || true
  rm -rf "$HF_HOME/xet" 2>/dev/null || true
}

echo "[6/7] LTX-2.5 BF16 production models (one file at a time)..."
download_one "Lightricks/LTX-2.5" \
  "diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors" "$MODEL_ROOT"
download_one "Lightricks/LTX-2.5" \
  "text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors" "$MODEL_ROOT"
download_one "Lightricks/LTX-2.5" \
  "vae/ltx-2.5-video-vae-bf16.safetensors" "$MODEL_ROOT"
download_one "Lightricks/LTX-2.5" \
  "vae/ltx-2.5-audio-vae-bf16.safetensors" "$MODEL_ROOT"
download_one "Lightricks/LTX-2.5" \
  "latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" "$MODEL_ROOT"
download_one "Lightricks/LTX-2.5" \
  "latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors" "$MODEL_ROOT"

download_one "Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler" \
  "ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors" "$MODEL_ROOT/loras"

echo
echo "[6b/7] ComfyUI FLF2V INT8 ConvRot models..."
download_one "comfyicu/LTX-2.5" \
  "diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" "$MODEL_ROOT"
download_one "comfyicu/LTX-2.5" \
  "text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" "$MODEL_ROOT"

echo
echo "[6c/7] Licon Multiple Subject Reference (MSR) V2 for LTX-2.5..."
MSR_LORA_DIR="$MODEL_ROOT/loras/ltx2.5"
MSR_WORKFLOW_DIR="$ROOT/workflows/MSR_V2"
mkdir -p "$MSR_LORA_DIR" "$MSR_WORKFLOW_DIR"
download_one "LiconStudio/LTX-2.5-Multiple-Subject-Reference" \
  "LTX-2.5-Licon-MSR-V2.safetensors" "$MSR_LORA_DIR"
download_one "LiconStudio/LTX-2.5-Multiple-Subject-Reference" \
  "LTX2.5-MSR-sample-workflow-V2.json" "$MSR_WORKFLOW_DIR"

echo "[7/7] Link models + health check..."
mkdir -p "$COMFY/models"/{diffusion_models,text_encoders,vae,latent_upscale_models,loras}

linkf () {
  [[ -f "$1" ]] || return 0
  ln -sfn "$1" "$2"
}
linkf "$MODEL_ROOT/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors" \
 "$COMFY/models/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors"
linkf "$MODEL_ROOT/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors" \
 "$COMFY/models/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors"
linkf "$MODEL_ROOT/vae/ltx-2.5-video-vae-bf16.safetensors" \
 "$COMFY/models/vae/ltx-2.5-video-vae-bf16.safetensors"
linkf "$MODEL_ROOT/vae/ltx-2.5-audio-vae-bf16.safetensors" \
 "$COMFY/models/vae/ltx-2.5-audio-vae-bf16.safetensors"
linkf "$MODEL_ROOT/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
 "$COMFY/models/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"
linkf "$MODEL_ROOT/latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors" \
 "$COMFY/models/latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors"
linkf "$MODEL_ROOT/loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors" \
 "$COMFY/models/loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors"
linkf "$MODEL_ROOT/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" \
 "$COMFY/models/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors"
linkf "$MODEL_ROOT/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" \
 "$COMFY/models/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors"

# MSR V2 LoRA path matches the official sample workflow model folder.
mkdir -p "$COMFY/models/loras/ltx2.5"
linkf "$MSR_LORA_DIR/LTX-2.5-Licon-MSR-V2.safetensors" \
 "$COMFY/models/loras/ltx2.5/LTX-2.5-Licon-MSR-V2.safetensors"

# Make the official MSR V2 sample workflow immediately visible in ComfyUI's user workflows.
mkdir -p "$COMFY/user/default/workflows"
linkf "$MSR_WORKFLOW_DIR/LTX2.5-MSR-sample-workflow-V2.json" \
 "$COMFY/user/default/workflows/LTX2.5-MSR-sample-workflow-V2.json"

cat > "$ROOT/START_COMFYUI.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/workspace/LTX25"
cd "$ROOT/ComfyUI"
exec "$ROOT/.venv-comfy/bin/python" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header
EOS
chmod +x "$ROOT/START_COMFYUI.sh"

cat > "$ROOT/RUNPOD_TEMPLATE_START_COMMAND.txt" <<'EOS'
HTTP Port:
8188

Container Start Command:
bash -lc 'until [ -x /workspace/LTX25/START_COMFYUI.sh ]; do sleep 2; done; exec /workspace/LTX25/START_COMFYUI.sh'
EOS

cat > "$ROOT/DOWNLOAD_DEV_FOR_TRAINING.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/workspace/LTX25"
export PATH="$ROOT/.runtime/bin:$PATH"
export UV_PYTHON_INSTALL_DIR="$ROOT/.runtime/python"
HF="$ROOT/.venv-tools/bin/hf"
MODEL_ROOT="$ROOT/models/ltx-2.5"
export HF_HOME="$ROOT/.hf-cache"
export HF_HUB_DISABLE_XET=1
export HF_HUB_DOWNLOAD_TIMEOUT=120
export HF_HUB_ETAG_TIMEOUT=30
if [[ -z "${HF_TOKEN:-}" ]]; then
  read -rsp "Paste HF READ token: " HF_TOKEN
  echo
  HF_TOKEN="$(printf '%s' "$HF_TOKEN" | tr -d '\r\n')"
  export HF_TOKEN
fi
for rel in \
  "diffusion_models/ltx-2.5-22b-dev-transformer-bf16.safetensors" \
  "loras/ltx-2.5-22b-distilled-lora-450-bf16.safetensors"
do
  if [[ -s "$MODEL_ROOT/$rel" ]]; then
    echo "SKIP existing: $rel"
  else
    "$HF" download Lightricks/LTX-2.5 "$rel" --local-dir "$MODEL_ROOT"
    rm -rf "$MODEL_ROOT/.cache/huggingface" "$HF_HOME/xet" 2>/dev/null || true
  fi
done
ln -sfn "$MODEL_ROOT/diffusion_models/ltx-2.5-22b-dev-transformer-bf16.safetensors" \
  "$ROOT/ComfyUI/models/diffusion_models/ltx-2.5-22b-dev-transformer-bf16.safetensors"
ln -sfn "$MODEL_ROOT/loras/ltx-2.5-22b-distilled-lora-450-bf16.safetensors" \
  "$ROOT/ComfyUI/models/loras/ltx-2.5-22b-distilled-lora-450-bf16.safetensors"
echo "DEV training files ready."
EOS
chmod +x "$ROOT/DOWNLOAD_DEV_FOR_TRAINING.sh"

echo
echo "=== VERIFY ==="
for f in \
 "$MODEL_ROOT/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors" \
 "$MODEL_ROOT/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors" \
 "$MODEL_ROOT/vae/ltx-2.5-video-vae-bf16.safetensors" \
 "$MODEL_ROOT/vae/ltx-2.5-audio-vae-bf16.safetensors" \
 "$MODEL_ROOT/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
 "$MODEL_ROOT/latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors" \
 "$MODEL_ROOT/loras/ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors" \
 "$MODEL_ROOT/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" \
 "$MODEL_ROOT/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" \
 "$MSR_LORA_DIR/LTX-2.5-Licon-MSR-V2.safetensors" \
 "$MSR_WORKFLOW_DIR/LTX2.5-MSR-sample-workflow-V2.json"
do
  [[ -s "$f" ]] && echo "OK: $(basename "$f")" || { echo "MISSING: $f"; exit 3; }
done

for d in \
 "$MSR_NODE" \
 "$KJ_NODE" \
 "$RG3_NODE" \
 "$PROMPT_RELAY_NODE"
do
  [[ -d "$d/.git" ]] && echo "OK node: $(basename "$d")" || { echo "MISSING NODE: $d"; exit 4; }
done

echo
du -sh "$ROOT" 2>/dev/null || true
echo "DONE in $(elapsed)"
echo "Start ComfyUI later with:"
echo "  /workspace/LTX25/START_COMFYUI.sh"
echo "MSR V2 is installed:"
echo "  LoRA: /workspace/LTX25/ComfyUI/models/loras/ltx2.5/LTX-2.5-Licon-MSR-V2.safetensors"
echo "  Workflow: /workspace/LTX25/ComfyUI/user/default/workflows/LTX2.5-MSR-sample-workflow-V2.json"
echo "For DEV/training weights later:"
echo "  /workspace/LTX25/DOWNLOAD_DEV_FOR_TRAINING.sh"
echo "RunPod template HTTP port: 8188"
echo "RunPod template Start Command:"
echo "  bash -lc 'until [ -x /workspace/LTX25/START_COMFYUI.sh ]; do sleep 2; done; exec /workspace/LTX25/START_COMFYUI.sh'"
echo "Log: $LOG"
