#!/bin/bash

# 固定参数
ALGO="pearlhash"
POOL="stratum+tcp://prl.kryptex.network:7048"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 获取 WORKER：从 SALAD_MACHINE_ID 取前 8 位
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"   # 未设置时的默认值
fi
echo "矿工名: $WORKER"
# Fl4shMiner 使用 -w 参数，格式为 钱包.矿工名
WALLET_WORKER="${WALLET}.${WORKER}"

# 下载信息
DOWNLOAD_URL="https://github.com/Fl4sh9174/Fl4shMiner/releases/download/v1.3.4/fl4shminer-v1.3.4.tar.gz"
TARBALL="fl4shminer-v1.3.4.tar.gz"
EXTRACT_DIR="fl4shminer"
BINARY="$EXTRACT_DIR/fl4shminer"

# 检查解压目录是否存在，若不存在则下载并解压
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "Fl4shMiner 未找到，开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压中..."
    tar xzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包
    rm -f "$TARBALL"
else
    echo "Fl4shMiner 已存在，跳过下载"
fi

# 确保二进制可执行
if [ ! -f "$BINARY" ]; then
    echo "错误：未找到 $BINARY，请检查解压是否完整"
    exit 1
fi
chmod +x "$BINARY"

# 启动挖矿
echo "启动 Fl4shMiner，矿工名: $WORKER"
cd "$EXTRACT_DIR" || exit 1
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
