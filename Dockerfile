FROM runpod/worker-comfyui:latest-base

# === カスタムノードインストール（requirements.txtがないのでシンプルに）===
RUN git clone https://github.com/lrzjason/Comfyui-QwenEditUtils.git /comfyui/custom_nodes/Comfyui-QwenEditUtils

# === 必須ファイルのコピー ===
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json /comfyui/workflow_api.json

# === start.sh作成（heredoc使用でparse error回避）===
RUN cat << 'EOF' > /start.sh
#!/bin/bash
echo "=== Qwen-Rapid-AIO Serverless Starting ==="

# Network Volumeを/workspaceにリンク
if [ ! -L /workspace ]; then
  ln -s /runpod-volume /workspace
  echo "Linked /runpod-volume -> /workspace"
fi

# 元のRunPod起動スクリプトを実行
exec /start.sh
EOF

RUN chmod +x /start.sh

CMD ["/start.sh"]
