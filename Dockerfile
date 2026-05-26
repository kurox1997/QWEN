FROM runpod/worker-comfyui:latest-base

# === カスタムノードのみインストール（QwenImageEditPlus用）===
RUN git clone https://github.com/lrzjason/Comfyui-QwenEditUtils.git /comfyui/custom_nodes/Comfyui-QwenEditUtils && \
    cd /comfyui/custom_nodes/Comfyui-QwenEditUtils && \
    pip install -r requirements.txt

# === Network VolumeのモデルをComfyUIが認識するための設定 ===
# extra_model_paths.yaml を配置
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# 起動時に /runpod-volume を /workspace にシンボリックリンク（RunPod Serverless標準）
RUN echo '#!/bin/bash\n\
[ ! -L /workspace ] && ln -s /runpod-volume /workspace\n\
exec /start.sh' > /start.sh && \
    chmod +x /start.sh

# ワークフローJSONを配置（API用）
COPY workflow_api.json /comfyui/workflow_api.json

CMD ["/start.sh"]