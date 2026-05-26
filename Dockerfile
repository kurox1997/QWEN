# ========================================================================
# Qwen-Rapid-AIO Serverless v3 (heredoc廃止版)
# 期待効果: RTX 4090 で 60-90 秒/枚
#saisin =======================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ----- Step 1: Triton 最新版 -----
RUN pip install --break-system-packages --no-cache-dir -U triton

# ----- Step 2: SageAttention 2.x ソースビルド (10-15分) -----
RUN pip install --break-system-packages --no-cache-dir "setuptools<=75.8.2" --force-reinstall \
 && git clone --depth=1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
 && cd /tmp/SageAttention \
 && MAX_JOBS=4 pip install --break-system-packages --no-cache-dir --no-build-isolation . \
 && rm -rf /tmp/SageAttention \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')"

# ----- Step 3: ComfyUI-KJNodes -----
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

# ----- Step 6: start.sh を別ファイルから COPY (heredoc不使用、確実) -----
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh