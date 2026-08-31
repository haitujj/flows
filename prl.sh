#!/bin/bash

# 固定参数
ALGO="pearlhash"
POOL="stratum+tcp://prl.kryptex.network:7048"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 从 SALAD_MACHINE_ID 取前 8 位作为矿工名，若未设置则使用 "jige"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi
WALLET_WORKER="${WALLET}.${WORKER}"

# 下载信息
DOWNLOAD_URL="https://github.com/Fl4sh9174/Fl4shMiner/releases/download/v1.3.4/fl4shminer-v1.3.4.tar.gz"
TARBALL="fl4shminer-v1.3.4.tar.gz"
EXTRACT_DIR="fl4shminer"
BINARY="$EXTRACT_DIR/fl4shminer"

# 若目录不存在则下载并解压（完全静默）
if [ ! -d "$EXTRACT_DIR" ]; then
    wget -q "$DOWNLOAD_URL" -O "$TARBALL"
    tar -xf "$TARBALL"
    rm -f "$TARBALL"
fi

# 确保可执行（无输出）
chmod +x "$BINARY" 2>/dev/null

# 启动矿工（输出保留，并同时写入 /miner.log）
cd "$EXTRACT_DIR" || exit 1
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | grep -i "TH/s" | tee -a /miner.log
