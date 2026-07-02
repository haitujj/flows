#!/bin/bash

# 固定参数
PROXY="global.pearlfortune.org:443"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
DOWNLOAD_URL="https://github.com/pearlfortune/pearl-miner/releases/download/v1.2.1/pearlfortune-v1.2.1.tar.gz"
TARBALL="pearlfortune-v1.2.1.tar.gz"
EXTRACT_DIR="pearlfortune"
BINARY="$EXTRACT_DIR/miner-cuda12"

# 获取环境变量
GROUP_NAME="${SALAD_CONTAINER_GROUP_NAME:-}"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
echo "SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"
echo "SALAD_MACHINE_ID = ${MACHINE_ID:-<未设置>}"

# 提取 UUID 第一段（若未设置则使用 "unknown"）
if [ -n "$MACHINE_ID" ]; then
    UUID_PREFIX=$(echo "$MACHINE_ID" | cut -d'-' -f1)
else
    UUID_PREFIX="unknown"
fi

# 构造矿工名：jige + 组名 + UUID前缀
WORKER_NAME="jige_${GROUP_NAME}_${UUID_PREFIX}"
echo "生成的矿工名: $WORKER_NAME"

# 检查并下载/解压
if [ ! -f "$BINARY" ]; then
    echo "PearlFortune 未找到，开始下载..."
    wget -c -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压..."
    tar vxzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包（可选）
    rm -f "$TARBALL"
    # 确保可执行
    chmod +x "$BINARY"
else
    echo "PearlFortune 已存在，跳过下载"
fi

# 启动挖矿
echo "启动 PearlFortune 矿工..."
cd "$EXTRACT_DIR" || exit 1
./miner-cuda12 --proxy "$PROXY" --address "$WALLET" --worker "$WORKER_NAME" -gpu
