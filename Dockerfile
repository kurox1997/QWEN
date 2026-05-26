# ============================================================================
# Qwen-Rapid-AIO Serverless v5 (Multi-stage + deadsnakes Python 3.12)
#
# 変更点 (v4→v5): Ubuntu 22.04 デフォルトに python3.12 無い問題を deadsnakes PPA で解決
# ============================================================================

# =============================================================================
# Stage 1: SageAttention 2.x wheel ビルダー (nvcc + Python 3.12)
# =============================================================================
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04 AS sage-builder

ENV DEBIAN_FRONTEND=noninteractive

# まず PPA 追加に必要な最小ツールをインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common curl ca-certificates gnupg \
 && rm -rf /var/lib/apt/lists/*

# deadsnakes PPA を追加 (Python 3.12 を Ubuntu 22.04 で入れるため)
RUN add-apt-repository -y ppa:deadsnakes/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        python3.12 python3.12-dev python3.12-venv python3.12-distutils \
        git build-essential ninja-build \
 && rm -rf /var/lib/apt/lists/*

# pip を Python 3.12 用に手動インストール
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# nvcc 確認 (build時の早期失敗検出)
RUN nvcc --version && python3.12 --version

# main stage と同じ torch を入れる (ABI互換のため必須)
RUN python3.12 -m pip install --no-cache-dir \
        torch==2.10.0 \
        --index-url https://download.pytorch.org/whl/cu128

# setuptools 旧版 (SageAttention 公式推奨) + ビルド依存
RUN python3.12 -m pip install --no-cache-dir \
        "setuptools<=75.8.2" wheel packaging ninja

# SageAttention 2.x を wheel としてビルド
RUN git clone --depth=1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
 && cd /tmp/SageAttention \
 && MAX_JOBS=4 EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" \
    python3.12 setup.py bdist_wheel \
 && ls -la dist/ \
 && echo "=== Built SageAttention wheel ==="

# =============================================================================
# Stage 2: メインの worker-comfyui イメージ
# =============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ----- Step 1: Triton 最新版 -----
RUN pip install --break-system-packages --no-cache-dir -U triton

# ----- Step 2: ビルドした SageAttention wheel をコピー & インストール -----
COPY --from=sage-builder /tmp/SageAttention/dist/*.whl /tmp/
RUN ls /tmp/*.whl \
 && pip install --break-system-packages --no-cache-dir /tmp/sageattention*.whl \
 && rm /tmp/sageattention*.whl \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')"

# ----- Step 3: ComfyUI-KJNodes (Patch Sage Attention ノード提供) -----
RUN git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git \
        /comfyui/custom_nodes/ComfyUI-KJNodes \
 && if [ -f /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt; \
    fi

# ----- Step 4: Comfyui-QwenEditUtils -----
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# ----- Step 5: モデルパス、ワークフロー、起動スクリプト -----
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ----- Step 6: start.sh -----
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh