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

# 若目录不存在则下载并解压
if [ ! -d "$EXTRACT_DIR" ]; then
    wget -q "$DOWNLOAD_URL" -O "$TARBALL"
    tar -xf "$TARBALL"
    rm -f "$TARBALL"
fi

# 确保可执行
chmod +x "$BINARY" 2>/dev/null


# ==============================
# Hashrate 监控
# 每 5 秒检查
# 连续 3 次低于 88 TH/s
# 强制退出容器
# ==============================

MIN_HASHRATE=88
LOW_COUNT=0
LAST_HASH_LINE=""

(
    while true; do
        sleep 5

        HASH_LINE=$(grep 'hashRate:' /miner.log 2>/dev/null | tail -n 1)

        # 没有 hashRate
        if [ -z "$HASH_LINE" ]; then
            continue
        fi

        # 防止同一条日志被重复计算
        if [ "$HASH_LINE" = "$LAST_HASH_LINE" ]; then
            continue
        fi

        LAST_HASH_LINE="$HASH_LINE"

        # 提取 TH/s
        HASHRATE=$(echo "$HASH_LINE" | sed -n 's/.*hashRate: \([0-9.]*\) TH\/s.*/\1/p')

        if [ -z "$HASHRATE" ]; then
            continue
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate: ${HASHRATE} TH/s"

        # 低于 88
        if awk "BEGIN {exit !($HASHRATE < $MIN_HASHRATE)}"; then

            LOW_COUNT=$((LOW_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/3)"

            if [ "$LOW_COUNT" -ge 3 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate too low 3 times, killing container..."

                kill -9 1
                exit 1
            fi

        else
            # 恢复正常
            LOW_COUNT=0
        fi

    done
) &


# ==============================
# 启动矿工
# ==============================

cd "$EXTRACT_DIR" || exit 1

./fl4shminer \
    -a "$ALGO" \
    -pool "$POOL" \
    -w "$WALLET_WORKER" \
    -pass x \
    2>&1 | tee -a /miner.log
