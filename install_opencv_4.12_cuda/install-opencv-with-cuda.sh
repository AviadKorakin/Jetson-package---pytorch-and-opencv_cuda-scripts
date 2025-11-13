#!/usr/bin/env bash
# OpenCV 4.12.0 from source with CUDA/cuDNN on Jetson (Ubuntu 22.04, JetPack 6.x)
# Safe to re-run. Cleans previous root-owned build dirs and uses correct CMake path.
set -euo pipefail

OPENCV_VERSION="4.12.0"
SRC_DIR="${HOME}/src"
OPENCV_DIR="${SRC_DIR}/opencv"
OPENCV_CONTRIB_DIR="${SRC_DIR}/opencv_contrib"

log() { printf "\n\033[1;36m[opencv]\033[0m %s\n" "$*"; }

# ---------- 0) Sanity ----------
if [[ "$(uname -m)" != "aarch64" ]]; then
  log "Warning: not on aarch64. This script is tuned for Jetson but will continue."
fi

# ---------- 1) Clean previous pip/apt/local installs (idempotent) ----------
log "Ensuring python3-pip exists"
sudo apt-get update -y
sudo apt-get install -y python3-pip

log "Removing pip OpenCV wheels if any (harmless if not present)"
pip3 uninstall -y opencv-python opencv-python-headless opencv-contrib-python || true

log "Removing prior /usr/local OpenCV installs (safe if used only for OpenCV)"
sudo rm -rf \
  /usr/local/lib/python3*/dist-packages/cv2* \
  /usr/local/lib/libopencv_* /usr/local/lib/libopencv*.so* \
  /usr/local/include/opencv4/opencv2 \
  /usr/local/share/opencv4 || true
sudo ldconfig

log "Purging apt OpenCV packages (if any)"
sudo apt-get purge -y 'libopencv*' || true
sudo apt-get autoremove -y || true

# ---------- 2) Build prerequisites ----------
log "Installing build deps and media I/O"
sudo apt-get update -y
sudo apt-get install -y \
  build-essential cmake git pkg-config \
  libgtk-3-dev python3-dev python3-numpy \
  libavcodec-dev libavformat-dev libswscale-dev \
  libtbb-dev libjpeg-turbo8-dev libpng-dev libtiff-dev libopenexr-dev \
  libopenblas-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
  gstreamer1.0-rtsp v4l-utils

# ---------- 3) Fresh sources ----------
log "Fixing ownership (in case a previous run used sudo)"
sudo chown -R "${USER}:${USER}" "${SRC_DIR}" 2>/dev/null || true

log "Fetching OpenCV ${OPENCV_VERSION} sources"
mkdir -p "${SRC_DIR}"
cd "${SRC_DIR}"
rm -rf "${OPENCV_DIR}" "${OPENCV_CONTRIB_DIR}"
git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git
git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv_contrib.git

# ---------- 4) Configure from the correct build directory ----------
log "Configuring CMake (Jetson Orin = SM 87)"
cd "${OPENCV_DIR}"
rm -rf build
mkdir build
cd build

PY3_EXE=$(python3 -c 'import sys; print(sys.executable)')
PY3_INC=$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')
PY3_PKGS=$(python3 -c 'import site; print(site.getsitepackages()[0])')
NP_INC=$(python3 -c 'import numpy; print(numpy.get_include())')

cmake -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_INSTALL_PREFIX=/usr/local \
  -D OPENCV_EXTRA_MODULES_PATH="${OPENCV_CONTRIB_DIR}/modules" \
  -D BUILD_EXAMPLES=OFF -D BUILD_TESTS=OFF -D BUILD_DOCS=OFF \
  -D BUILD_opencv_python2=OFF -D BUILD_opencv_python3=ON \
  -D PYTHON3_EXECUTABLE="${PY3_EXE}" \
  -D PYTHON3_INCLUDE_DIR="${PY3_INC}" \
  -D PYTHON3_PACKAGES_PATH="${PY3_PKGS}" \
  -D PYTHON3_NUMPY_INCLUDE_DIRS="${NP_INC}" \
  -D WITH_CUDA=ON -D WITH_CUDNN=ON -D OPENCV_DNN_CUDA=ON \
  -D CMAKE_CUDA_ARCHITECTURES=87 \
  -D ENABLE_FAST_MATH=ON -D CUDA_FAST_MATH=ON \
  -D WITH_TBB=ON \
  -D WITH_FFMPEG=ON -D WITH_GSTREAMER=ON -D WITH_V4L=ON -D WITH_LIBV4L=ON \
  -D WITH_OPENCL=OFF \
  -D OPENCV_GENERATE_PKGCONFIG=ON \
  -D OPENCV_ENABLE_NONFREE=OFF \
  -D OPENCV_FORCE_3RDPARTY_BUILD=ON \
  \
  -D OPENCV_DNN_TENSORRT=ON \
  -D TENSORRT_ROOT=/usr \
  -D TensorRT_DIR=/usr \
  -D TENSORRT_INCLUDE_DIRS=/usr/include/aarch64-linux-gnu \
  -D TENSORRT_LIBRARY=/usr/lib/aarch64-linux-gnu/libnvinfer.so \
  -D TENSORRT_LIBRARY_INFER=/usr/lib/aarch64-linux-gnu/libnvinfer.so \
  -D TENSORRT_LIBRARY_INFER_PLUGIN=/usr/lib/aarch64-linux-gnu/libnvinfer_plugin.so \
  -D TENSORRT_LIBRARY_PARSERS=/usr/lib/aarch64-linux-gnu/libnvonnxparser.so \
  ..

# ---------- 5) Build & install ----------
log "Building (this takes a while on first run)…"
make -j"$(nproc)"

log "Installing"
sudo make install
sudo ldconfig

# ---------- 6) Quick verification ----------
log "Verifying Python import and CUDA/GStreamer presence"
python3 - << 'PY'
import cv2, sys
print("OpenCV:", cv2.__version__)
info = cv2.getBuildInformation()
print("CUDA in build info? ", "CUDA" in info)
print("GStreamer in build info? ", "GStreamer" in info)
try:
    import cv2.dnn as dnn
    print("DNN module present:", hasattr(dnn, "readNet"))
except Exception as e:
    print("DNN check error:", e, file=sys.stderr)
PY

log "Done. You can also check:  pkg-config --modversion opencv4  &&  python3 -c 'import cv2; print(cv2.getBuildInformation())'"
