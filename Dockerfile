FROM runpod/worker-comfyui:latest-base

# === カスタムノードインストール（requirements.txtがないので簡略化）===
RUN git clone https://github.com/lrzjason/Comfyui-QwenEditUtils.git /comfyui/custom_nodes/Comfyui-QwenEditUtils

# === Network Volumeのモデルを認識させる設定 ===
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# 起動時にNetwork Volumeをリンク
RUN echo '#!/bin/bash
[ ! -L /workspace ] && ln -s /runpod-volume /workspace
exec /start.sh' > /start.sh && \
    chmod +x /start.sh

# ワークフローJSON
COPY workflow_api.json /comfyui/workflow_api.json

CMD ["/start.sh"]