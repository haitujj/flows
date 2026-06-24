#!/bin/bash

# 固定钱包地址
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
HOST="pool.pearlhash.xyz:9000"
MINER_URL="https://pearlhash.xyz/downloads/pearl-miner-v12"
MINER_BIN="pearl-miner"

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

# 检查矿工是否存在，若不存在则下载
if [ ! -f "$MINER_BIN" ]; then
    echo "下载 pearl-miner ..."
    curl -s -L "$MINER_URL" -o "$MINER_BIN"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    chmod +x "$MINER_BIN"
else
    echo "pearl-miner 已存在，跳过下载"
fi

./"$MINER_BIN" --host "$HOST" --user "$WALLET" --worker "$WORKER_NAME"
