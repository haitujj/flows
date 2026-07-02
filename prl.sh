#!/bin/bash

# 固定参数
ALGO="pearlhash"
URL="stratum+tcp://pool.pearlhash.xyz:9000"
USER="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
PASS="x"
WORKER="jige"

DOWNLOAD_URL="https://github.com/andru-kun/wildrig-multi/releases/download/0.49.1/wildrig-multi-linux-0.49.1.tar.gz"
TARBALL="wildrig-multi-linux-0.49.1.tar.gz"
EXTRACT_DIR="wildrig-multi-linux-0.49.1"
BINARY="$EXTRACT_DIR/wildrig-multi"

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

# 启动挖矿
echo "启动 wildrig-multi，矿工名: $WORKER"
cd "$EXTRACT_DIR" || exit 1
./wildrig-multi --algo "$ALGO" --url "$URL" --user "$USER" --pass "$PASS" --worker "$WORKER"
