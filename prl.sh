#!/bin/bash

# ============================================================
# PRL Fl4shMiner
# ============================================================

# ==============================
# GPU 判断
# 单 GPU 且为指定型号时立即退出
# 多 GPU 不处理
# ==============================

GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

echo "Detected GPU count: $GPU_COUNT"

if [ "$GPU_COUNT" -eq 1 ]; then

    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 | xargs)

    echo "Detected GPU: $GPU_NAME"

    case "$GPU_NAME" in

        *"RTX 3070 Laptop GPU"*|*"3060"*|*"2080"*|"NVIDIA GeForce RTX 3070")

            echo "Target GPU detected: $GPU_NAME"
            echo "Exiting container..."

            exit 1
            ;;

        *)

            echo "GPU $GPU_NAME is not a target GPU, continue mining."

            ;;

    esac

elif [ "$GPU_COUNT" -gt 1 ]; then

    echo "Multiple GPUs detected ($GPU_COUNT), reallocate disabled."

else

    echo "No NVIDIA GPU detected, continue."

fi


# ==============================
# 固定参数
# ==============================

ALGO="pearlhash"

POOL="stratum+tcp://prl.kryptex.network:7048"

WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"


# ==============================
# Worker
# ==============================

MACHINE_ID="${SALAD_MACHINE_ID:-}"

if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi

WALLET_WORKER="${WALLET}.${WORKER}"

echo "Worker: $WALLET_WORKER"


# ==============================
# 下载信息
# ==============================

DOWNLOAD_URL="https://github.com/Fl4sh9174/Fl4shMiner/releases/download/v1.3.4/fl4shminer-v1.3.4.tar.gz"

TARBALL="fl4shminer-v1.3.4.tar.gz"

EXTRACT_DIR="fl4shminer"

BINARY="$EXTRACT_DIR/fl4shminer"


# ==============================
# 下载矿工
# ==============================

if [ ! -d "$EXTRACT_DIR" ]; then

    echo "Downloading Fl4shMiner..."

    wget -q "$DOWNLOAD_URL" -O "$TARBALL"

    if [ $? -ne 0 ]; then
        echo "Failed to download Fl4shMiner."
        exit 1
    fi

    tar -xf "$TARBALL"

    if [ $? -ne 0 ]; then
        echo "Failed to extract Fl4shMiner."
        exit 1
    fi

    rm -f "$TARBALL"

fi


# ==============================
# 权限
# ==============================

chmod +x "$BINARY" 2>/dev/null


# ==============================
# 算力监控参数
# ==============================

MIN_HASHRATE=88

# 连续低于 88 TH/s 次数
LOW_COUNT=0

# 连续没有新的 hashRate 日志时间
NO_HASH_SECONDS=0

# 上一次 hashRate 日志
LAST_HASH_LINE=""


# ==============================
# 退出函数
# ==============================

shutdown_miner()
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping miner..."

    # 优先精确杀 Fl4shMiner
    pkill -9 -x fl4shminer 2>/dev/null || true

    sleep 1

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exiting prl.sh..."

    exit 1
}


# ==============================
# 启动矿工
# ==============================

cd "$EXTRACT_DIR" || exit 1

echo "Starting Fl4shMiner..."

./fl4shminer \
    -a "$ALGO" \
    -pool "$POOL" \
    -w "$WALLET_WORKER" \
    -pass x \
    2>&1 | tee -a /miner.log &

MINER_PIPE_PID=$!


# ==============================
# 等待矿工启动
# ==============================

sleep 2


# ==============================
# 算力监控
#
# 每 1 秒检查一次
#
# 规则：
#
# 1. 连续 3 个新的 hashRate < 88 TH/s
#    → 停止矿工
#    → exit 1
#
# 2. 连续 10 秒没有新的 hashRate
#    → 停止矿工
#    → exit 1
#
# 3. 同一条 hashRate 不重复计算
# ==============================

while true; do

    sleep 1


    # ==========================
    # 检查矿工是否还活着
    # ==========================

    if ! pgrep -x fl4shminer >/dev/null 2>&1; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fl4shMiner process not running."

        exit 1

    fi


    # ==========================
    # 获取最新 hashRate
    # ==========================

    HASH_LINE=$(grep 'hashRate:' /miner.log 2>/dev/null | tail -n 1)


    # ==========================
    # 没有 hashRate
    # ==========================

    if [ -z "$HASH_LINE" ]; then

        NO_HASH_SECONDS=$((NO_HASH_SECONDS + 1))

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_SECONDS}/10)"


        if [ "$NO_HASH_SECONDS" -ge 10 ]; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate for 10 seconds."

            shutdown_miner

        fi

        continue

    fi


    # ==========================
    # 检查是不是新的日志
    # ==========================

    if [ "$HASH_LINE" = "$LAST_HASH_LINE" ]; then

        NO_HASH_SECONDS=$((NO_HASH_SECONDS + 1))

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new hashrate (${NO_HASH_SECONDS}/10)"


        if [ "$NO_HASH_SECONDS" -ge 20 ]; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new hashrate for 10 seconds."

            shutdown_miner

        fi

        continue

    fi


    # ==========================
    # 获取到新的 hashRate
    # ==========================

    LAST_HASH_LINE="$HASH_LINE"

    NO_HASH_SECONDS=0


    # ==========================
    # 提取 TH/s
    # ==========================

    HASHRATE=$(echo "$HASH_LINE" | sed -n 's/.*hashRate: \([0-9.]*\) TH\/s.*/\1/p')


    if [ -z "$HASHRATE" ]; then
        continue
    fi


    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate: ${HASHRATE} TH/s"


    # ==========================
    # 判断算力
    # ==========================

    if awk "BEGIN {exit !($HASHRATE < $MIN_HASHRATE)}"; then

        LOW_COUNT=$((LOW_COUNT + 1))

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/3)"


        if [ "$LOW_COUNT" -ge 3 ]; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate too low 3 times."

            shutdown_miner

        fi

    else

        # 算力恢复正常
        LOW_COUNT=0

    fi

done
