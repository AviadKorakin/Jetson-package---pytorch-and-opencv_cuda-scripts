#!/usr/bin/env bash
# install_torch_jp6.sh — Jetson JP6 (CUDA 12.6) PyTorch stack + CuDSS
# Installs: torch, torchvision, torchaudio from NVIDIA Jetson AI Lab index
# Requires: Ubuntu 22.04 on Jetson (aarch64), JP6.2 (CUDA 12.6)
set -euo pipefail

JETSON_INDEX="https://pypi.jetson-ai-lab.io/jp6/cu126"

echo "[i] Updating APT and installing prerequisites…"
sudo apt-get -y update
sudo apt-get install -y python3-pip libopenblas-dev

# Optional: ensure pip is recent
python3 -m pip install --upgrade pip setuptools wheel

echo "[i] Installing PyTorch, torchvision, torchaudio (JP6 / cu126)…"
# Pin versions that match JP6 wheels:
#   torch==2.8.0, torchvision==0.23.0, torchaudio==2.8.0
python3 -m pip install --force-reinstall \
  --index-url "${JETSON_INDEX}" \
  "torch==2.8.0" "torchvision==0.23.0" "torchaudio==2.8.0"




echo "[i] Verifying torch stack…"
python3 - <<'PY'
import torch, torchvision, torchaudio
print("torch      :", torch.__version__, "| CUDA:", torch.version.cuda)
print("torchvision:", torchvision.__version__)
print("torchaudio :", torchaudio.__version__)
print("torch.cuda.is_available():", torch.cuda.is_available())
try:
    print("cuDNN:", torch.backends.cudnn.version())
except Exception as e:
    print("cuDNN: n/a", e)
PY

echo "[✓] Done."
