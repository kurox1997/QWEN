# ============================================================================
# Qwen-Rapid-AIO Serverless v10 - Plan B-5 (SageAttention 2.x Full Runtime)
#
# 教訓: SageAttention 2.x は ランタイムに Triton JIT を使う
#       Triton JIT は gcc + nvcc を要求するため main image に CUDA Toolkit を COPY
#
# イメージサイズ: 約 22-25 GB (CUDA Toolkit 約6GB 追加)
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

RUN nvcc --version && python3 --version && python3 -m pip --version

RUN python3 -m pip install --break-system-packages --no-cache-dir \
        torch==2.10.0 \
        --index-url https://download.pytorch.org/whl/cu128

RUN python3 -m pip install --break-system-packages --no-cache-dir \
        numpy "setuptools<=75.8.2" wheel packaging ninja

# SageAttention 2.x ビルド (RTX 4090 = sm_89)
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
# Stage 2: メインイメージ + CUDA Toolkit + SageAttention runtime
# =============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ----- Step 1: Triton JIT 用 C コンパイラ追加 -----
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ \
 && rm -rf /var/lib/apt/lists/* \
 && gcc --version

# ----- Step 2: CUDA Toolkit (nvcc等) を Stage 1 から丸ごとコピー -----
# Triton JIT がランタイムで nvcc を呼ぶため必須
COPY --from=sage-builder /usr/local/cuda /usr/local/cuda

# CUDA 環境変数
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV CUDA_HOME=/usr/local/cuda
ENV CC=gcc
ENV CXX=g++

# nvcc/gcc 動作確認 (Build時の早期失敗検出)
RUN nvcc --version && gcc --version | head -1

# ----- Step 3: Triton 最新版 -----
RUN pip install --break-system-packages --no-cache-dir -U triton

# ----- Step 4: SageAttention wheel を Stage 1 から COPY & インストール -----
COPY --from=sage-builder /tmp/SageAttention/dist/*.whl /tmp/
RUN ls /tmp/*.whl \
 && pip install --break-system-packages --no-cache-dir /tmp/sageattention*.whl \
 && rm /tmp/sageattention*.whl \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')"

# ----- Step 5: ComfyUI-KJNodes (Patch Sage Attention ノード提供) -----
RUN git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git \
        /comfyui/custom_nodes/ComfyUI-KJNodes \
 && if [ -f /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt; \
    fi

# ----- Step 6: Comfyui-QwenEditUtils -----
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# ----- Step 7: モデルパス、ワークフロー、起動スクリプト -----
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ----- Step 8: start.sh -----
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh