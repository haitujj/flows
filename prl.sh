#!/bin/bash

# 固定参数
PROXY="global.pearlfortune.org:443"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
DOWNLOAD_URL="https://github.com/pearlfortune/pearl-miner/releases/download/v1.2.3/pearlfortune-v1.2.3.tar.gz"
TARBALL="pearlfortune-v1.2.3.tar.gz"
EXTRACT_DIR="pearlfortune"
BINARY="$EXTRACT_DIR/miner-cuda13"

# 获取环境变量
MACHINE_ID="${SALAD_MACHINE_ID:-}"
echo "SALAD_MACHINE_ID = ${MACHINE_ID:-<未设置>}"

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
cd "$EXTRACT_DIR" || exit 1
./miner-cuda13 --proxy "$PROXY" --address "$WALLET" --worker "$MACHINE_ID" -gpu
