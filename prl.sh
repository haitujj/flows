#!/bin/bash

# 固定参数
ALGO="pearlhash"
URL="stratum+tcp://pool.pearlhash.xyz:9000"
USER="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
PASS="x"
DOWNLOAD_URL="https://github.com/andru-kun/wildrig-multi/releases/download/0.49.2/wildrig-multi-linux-0.49.2.tar.gz"
TARBALL="wildrig-multi-linux-0.49.2.tar.gz"
BINARY="wildrig-multi"

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

# 检查可执行文件是否存在，若不存在则下载解压
if [ ! -f "$BINARY" ]; then
    echo "wildrig-multi 未找到，开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压..."
    tar -xzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    rm -f "$TARBALL"  # 清理压缩包
    chmod +x "$BINARY"
else
    echo "wildrig-multi 已存在，跳过下载"
fi

WORKER_NAME="jige_${GROUP_NAME}_${UUID_PREFIX}"
# 启动挖矿
echo "启动 wildrig-multi，矿工名: $WORKER_NAME"
cd "$EXTRACT_DIR" || exit 1
./wildrig-multi --algo "$ALGO" --url "$URL" --user "$USER" --pass "$PASS" --worker "$WORKER_NAME"
