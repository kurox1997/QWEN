# ============================================================================
# Qwen-Rapid-AIO Serverless v12 (Plan B-5 - Full Triton JIT Dependencies)
#
# v11 → v12 変更点:
#   - Triton JIT 用全依存を網羅的に追加 (繰り返し失敗を避けるため)
#   - Build時の動作確認を強化 (Python.h, nvcc, Triton import, libcuda)
#
# 期待効果: RTX 4090 で 60-90 秒/枚
# ============================================================================

# =============================================================================
# Stage 1: SageAttention 2.x wheel ビルダー
# =============================================================================
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS sage-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-dev python3-pip python3-venv \
        git build-essential ninja-build curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN nvcc --version && python3 --version

RUN python3 -m pip install --break-system-packages --no-cache-dir \
        torch==2.10.0 \
        --index-url https://download.pytorch.org/whl/cu128

RUN python3 -m pip install --break-system-packages --no-cache-dir \
        numpy "setuptools<=75.8.2" wheel packaging ninja

RUN git clone --depth=1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
 && cd /tmp/SageAttention \
 && export TORCH_CUDA_ARCH_LIST="8.9" \
 && export MAX_JOBS=4 \
 && export EXT_PARALLEL=4 \
 && export NVCC_APPEND_FLAGS="--threads 8" \
 && python3 setup.py bdist_wheel \
 && ls -la dist/ \
 && echo "=== Built SageAttention wheel ==="

# =============================================================================
# Stage 2: メインイメージ + 全 Triton JIT 依存
# =============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

ENV DEBIAN_FRONTEND=noninteractive

# ----- Step 1: Triton JIT 必須依存を網羅的にインストール -----
# gcc/g++:        Cコンパイラ (Triton JIT が cuda_utils.c をコンパイル)
# python3-dev:    /usr/include/python3.12/Python.h を提供
# libpython3-dev: libpython3.so 提供 (リンカーが要求)
# make/pkg-config: ビルドツール (一部のJITコンパイル用)
# zlib1g-dev:     Triton キャッシュ圧縮用
# libtinfo-dev:   LLVM 依存
# binutils:       ld/ar リンカー
# libssl-dev:     SSL (pip ビルド時に念のため)
# ca-certificates: HTTPS 証明書
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ \
        python3-dev libpython3-dev \
        make pkg-config \
        zlib1g-dev libtinfo-dev \
        binutils libssl-dev \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Build時の依存確認 (早期失敗検出)
RUN gcc --version | head -1 \
 && g++ --version | head -1 \
 && ls -la /usr/include/python3.12/Python.h \
 && ldconfig -p | grep -E "libpython3.12|libcuda|libcudart" | head -5 \
 && echo "✓ Step 1: All apt deps verified"

# ----- Step 2: CUDA Toolkit (nvcc) を Stage 1 から COPY -----
COPY --from=sage-builder /usr/local/cuda /usr/local/cuda

# CUDA 環境変数
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV CUDA_HOME=/usr/local/cuda
ENV CC=gcc
ENV CXX=g++

# nvcc 動作確認
RUN nvcc --version | tail -1 \
 && which nvcc \
 && ls /usr/local/cuda/bin/nvcc \
 && echo "✓ Step 2: CUDA Toolkit verified"

# ----- Step 3: Triton 最新版 + import 動作確認 -----
RUN pip install --break-system-packages --no-cache-dir -U triton \
 && python3 -c "import triton; print('Triton version:', triton.__version__)" \
 && ls /opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/lib/ \
 && ls /opt/venv/lib/python3.12/site-packages/triton/backends/nvidia/include/ \
 && echo "✓ Step 3: Triton installed & verified"

# ----- Step 4: SageAttention wheel を Stage 1 から COPY & インストール -----
COPY --from=sage-builder /tmp/SageAttention/dist/*.whl /tmp/
RUN ls /tmp/*.whl \
 && pip install --break-system-packages --no-cache-dir /tmp/sageattention*.whl \
 && rm /tmp/sageattention*.whl \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')" \
 && echo "✓ Step 4: SageAttention installed & verified"

# ----- Step 5: ComfyUI-KJNodes (Patch Sage Attention ノード提供) -----
RUN git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git \
        /comfyui/custom_nodes/ComfyUI-KJNodes \
 && if [ -f /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt; \
    fi \
 && echo "✓ Step 5: ComfyUI-KJNodes installed"

# ----- Step 6: Comfyui-QwenEditUtils -----
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi \
 && echo "✓ Step 6: Comfyui-QwenEditUtils installed"

# ----- Step 7: モデルパス、ワークフロー -----
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ----- Step 8: start.sh -----
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh

# 最終Build確認
RUN echo "=== Final verification ===" \
 && gcc --version | head -1 \
 && nvcc --version | tail -1 \
 && python3 -c "import triton; import sageattention; print('All systems go')" \
 && echo "✓ v12 Build complete"