#!/bin/bash
# ============================================================
# SGLang + DeepSeek-V4 部署启动脚本（H20 8卡）
# ============================================================
set -e

# ====== 配置区（按需修改）======
MODEL_PATH="/home/DeepSeek-V4-Flash-FP8"
SERVED_MODEL_NAME="cct-1.4"
TP_SIZE=8
CACHE_DIR="/opt/sglang_cache"
PORT=30000

# ====== 预编译 DeepGEMM ======
echo "[1/2] 预编译 DeepGEMM 内核..."
export SGLANG_DG_CACHE_DIR="$CACHE_DIR"
mkdir -p "$CACHE_DIR"

python -m sglang.compile_deep_gemm \
    --model "$MODEL_PATH" \
    --tp "$TP_SIZE"

echo "✅ DeepGEMM 编译完成"
echo ""

# ====== 启动服务 ======
echo "[2/2] 启动 SGLang 服务..."
python -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --tp "$TP_SIZE" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --enable-torch-compile \
    --enable-metrics
