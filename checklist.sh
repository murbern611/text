#!/bin/bash
# ============================================================
# H20 GPU 部署 DeepSeek-V4 — 环境检查脚本
# 在部署前运行，快速排查常见问题
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

echo "=========================================="
echo "  H20 部署环境检查工具"
echo "=========================================="
echo ""

# ----- 1. 检查 NVIDIA 驱动 -----
echo "-------- [1/5] NVIDIA 驱动 --------"
if command -v nvidia-smi &> /dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1)
    echo -e " $PASS 驱动版本: $DRIVER_VER"
    echo -e " $PASS GPU 数量: $GPU_COUNT"
else
    echo -e " $FAIL nvidia-smi 未找到，驱动未安装"
fi
echo ""

# ----- 2. 检查 Docker -----
echo "-------- [2/5] Docker --------"
if command -v docker &> /dev/null; then
    echo -e " $PASS Docker 已安装 ($(docker --version))"
    if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
        echo -e " $PASS NVIDIA runtime 已配置"
    else
        echo -e " $WARN NVIDIA runtime 未配置（可能需要安装 Container Toolkit）"
    fi
else
    echo -e " $FAIL Docker 未安装"
fi
echo ""

# ----- 3. 检查 Container Toolkit -----
echo "-------- [3/5] NVIDIA Container Toolkit --------"
if systemctl status nvidia-container-toolkit &>/dev/null; then
    echo -e " $PASS nvidia-container-toolkit 服务运行中"
elif command -v nvidia-ctk &>/dev/null; then
    echo -e " $WARN nvidia-ctk 已安装但服务未运行"
else
    echo -e " $FAIL nvidia-container-toolkit 未安装"
fi
echo ""

# ----- 4. 检查 Fabric Manager -----
echo "-------- [4/5] NVIDIA Fabric Manager --------"
if systemctl status nvidia-fabricmanager &>/dev/null; then
    FM_VER=$(systemctl status nvidia-fabricmanager 2>/dev/null | grep -oP 'version \K[\d.]+' | head -1)
    echo -e " $PASS nvidia-fabricmanager 运行中 (version $FM_VER)"
else
    echo -e " $FAIL nvidia-fabricmanager 未运行"
    # 检查是否安装但版本不匹配
    if dpkg -l | grep -q fabricmanager 2>/dev/null; then
        INSTALLED_VER=$(dpkg -l | grep fabricmanager | awk '{print $3}')
        echo -e " $WARN  已安装版本: $INSTALLED_VER"
        echo -e " $WARN  可能和驱动版本不匹配，请检查！"
    fi
fi
echo ""

# ----- 5. 版本兼容检查 -----
echo "-------- [5/5] 版本兼容性 --------"
if command -v nvidia-smi &>/dev/null; then
    DRIVER_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)
    if [ "$DRIVER_MAJOR" -ge 570 ] 2>/dev/null; then
        echo -e " $PASS 驱动 ≥ 570，支持 CUDA 13.x 容器"
    elif [ "$DRIVER_MAJOR" -ge 550 ] 2>/dev/null; then
        echo -e " $WARN 驱动 550，仅支持 CUDA 12.x 容器"
    else
        echo -e " $FAIL 驱动版本过低，需要升级！"
    fi
fi
echo ""
echo "=========================================="
echo "  检查完成"
echo "=========================================="
