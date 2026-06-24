#!/bin/bash

# 固定钱包地址
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
# 矿池地址和端口
POOL="prl.kryptex.network:7048"
# 下载链接
DOWNLOAD_URL="https://github.com/0xHashRaptor/ForgeMiner/releases/download/v1.1.11/ForgeMiner-1.1.11-linux.tar.gz"
TARBALL="ForgeMiner-1.1.11-linux.tar.gz"
BINARY="./forge"

# 获取环境变量
GROUP_NAME="${SALAD_CONTAINER_GROUP_NAME:-}"  # 若未设置则为空
MACHINE_ID="${SALAD_MACHINE_ID:-}"
echo "SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"
echo "SALAD_MACHINE_ID = ${MACHINE_ID:-<未设置>}"

# 提取UUID第一段（若未设置则使用 "unknown"）
if [ -n "$MACHINE_ID" ]; then
    UUID_PREFIX=$(echo "$MACHINE_ID" | cut -d'-' -f1)
else
    UUID_PREFIX="unknown"
fi

# 构造矿工名：jige + 组名 + UUID前缀
WORKER_NAME="jige_${GROUP_NAME}_${UUID_PREFIX}"
echo "生成的矿工名: $WORKER_NAME"

# 完整钱包参数（wallet.worker）
WALLET_WORKER="${WALLET}.${WORKER_NAME}"

# 检查是否存在可执行文件，若不存在则下载解压
if [ ! -f "$BINARY" ]; then
    echo "ForgeMiner 未找到，开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压..."
    tar xzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包（可选）
    rm -f "$TARBALL"
    # 确保可执行
    chmod +x "$BINARY"
else
    echo "ForgeMiner 已存在，跳过下载"
fi

# 启动挖矿
echo "启动 ForgeMiner ..."
./forge --algorithm pearlhash --pool "$POOL" --wallet "$WALLET_WORKER"
