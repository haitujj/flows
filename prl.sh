#!/bin/bash

ALGO="pearlhash"
POOL="stratum+tcp://prl.kryptex.network:7048"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi
WALLET_WORKER="${WALLET}.${WORKER}"

DOWNLOAD_URL="https://github.com/Fl4sh9174/Fl4shMiner/releases/download/v1.3.4/fl4shminer-v1.3.4.tar.gz"
TARBALL="fl4shminer-v1.3.4.tar.gz"
EXTRACT_DIR="fl4shminer"
BINARY="$EXTRACT_DIR/fl4shminer"

MIN_HASHRATE=88
LOW_HASH_LIMIT=3
NO_HASH_LIMIT=12
LOW_COUNT=0
NO_HASH_COUNT=0
LAST_HASH_LINE=""
GPU_COUNT=0
GPU_NAME=""
REALLOCATE_ENABLED=0


# ============================================================
# Salad Reallocate
# ============================================================

send_reallocate() {

    echo
    echo "============================================================"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending Salad reallocate request..."
    echo "============================================================"

    RESPONSE=$(curl \
        --fail-with-body \
        -sS \
        -w "\nHTTP_STATUS:%{http_code}" \
        "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
        -X POST \
        -H 'accept: */*' \
        -H 'accept-language: zh-CN,zh;q=0.9' \
        -H 'content-length: 0' \
        -b "scid=$TK" \
        -H 'origin: https://portal.salad.com' \
        -H 'priority: u=1, i' \
        -H 'sec-ch-ua: "Chromium";v="148", "Google Chrome";v="148", "Not/A)Brand";v="99"' \
        -H 'sec-ch-ua-mobile: ?0' \
        -H 'sec-ch-ua-platform: "Windows"' \
        -H 'sec-fetch-dest: empty' \
        -H 'sec-fetch-mode: cors' \
        -H 'sec-fetch-site: same-site' \
        -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36' \
        2>&1
    )

    CURL_EXIT=$?

    echo "$RESPONSE"

    if [ "$CURL_EXIT" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reallocate request sent successfully."
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reallocate request failed. curl exit code: $CURL_EXIT"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exiting script."

    exit 1
}


# ============================================================
# GPU 检测
# ============================================================

check_gpu() {

    echo
    echo "============================================================"
    echo "GPU Detection"
    echo "============================================================"

    if ! command -v nvidia-smi >/dev/null 2>&1; then

        echo "nvidia-smi not found."
        echo "Reallocate disabled."

        REALLOCATE_ENABLED=0

        return
    fi


    # 获取 GPU 数量

    GPU_COUNT=$(nvidia-smi \
        --query-gpu=name \
        --format=csv,noheader \
        2>/dev/null | wc -l)


    echo "Detected GPU count: $GPU_COUNT"


    # ========================================================
    # 多 GPU
    # ========================================================

    if [ "$GPU_COUNT" -gt 1 ]; then

        echo "Multiple GPUs detected."

        echo "Reallocate disabled."

        REALLOCATE_ENABLED=0

        return
    fi


    # ========================================================
    # 没有 GPU
    # ========================================================

    if [ "$GPU_COUNT" -ne 1 ]; then

        echo "No NVIDIA GPU detected."

        echo "Reallocate disabled."

        REALLOCATE_ENABLED=0

        return
    fi


    # ========================================================
    # 获取 GPU 型号
    # ========================================================

    GPU_NAME=$(nvidia-smi \
        --query-gpu=name \
        --format=csv,noheader \
        2>/dev/null \
        | head -n 1 \
        | xargs)


    echo "Detected GPU: $GPU_NAME"


    # ========================================================
    # 判断目标 GPU
    # ========================================================

    case "$GPU_NAME" in

        *"RTX 3070 Laptop GPU"*|*"3060"*|*"2080"*)

            echo "Target GPU detected: $GPU_NAME"

            echo "Reallocate enabled."

            REALLOCATE_ENABLED=1

            ;;

        *)

            echo "GPU $GPU_NAME is not a target GPU."

            echo "Reallocate disabled."

            REALLOCATE_ENABLED=0

            ;;

    esac
}


# ============================================================
# Hashrate 检测
# ============================================================

check_hashrate() {

    # --------------------------------------------------------
    # GPU 不符合条件
    # --------------------------------------------------------

    if [ "$REALLOCATE_ENABLED" -ne 1 ]; then
        return
    fi


    # --------------------------------------------------------
    # 获取最后一条 hashRate
    # --------------------------------------------------------

    HASH_LINE=$(grep 'hashRate:' /miner.log 2>/dev/null | tail -n 1)


    # --------------------------------------------------------
    # 完全没有 hashRate
    # --------------------------------------------------------

    if [ -z "$HASH_LINE" ]; then

        NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/${NO_HASH_LIMIT})"


        if [ "$NO_HASH_COUNT" -ge "$NO_HASH_LIMIT" ]; then

            echo
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for ${NO_HASH_LIMIT} seconds."

            send_reallocate

        fi

        return
    fi


    # --------------------------------------------------------
    # 判断是不是新的 hashRate
    # --------------------------------------------------------

    if [ "$HASH_LINE" = "$LAST_HASH_LINE" ]; then

        NO_HASH_COUNT=$((NO_HASH_COUNT + 1))


        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new hashrate (${NO_HASH_COUNT}/${NO_HASH_LIMIT})"


        if [ "$NO_HASH_COUNT" -ge "$NO_HASH_LIMIT" ]; then

            echo
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new hashrate for ${NO_HASH_LIMIT} seconds."

            send_reallocate

        fi

        return
    fi


    # --------------------------------------------------------
    # 获取到新的 hashRate
    # --------------------------------------------------------

    LAST_HASH_LINE="$HASH_LINE"

    NO_HASH_COUNT=0


    # --------------------------------------------------------
    # 提取 TH/s
    # --------------------------------------------------------

    HASHRATE=$(echo "$HASH_LINE" | sed -n 's/.*hashRate: \([0-9.]*\) TH\/s.*/\1/p')


    if [ -z "$HASHRATE" ]; then
        return
    fi


    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate: ${HASHRATE} TH/s"


    # --------------------------------------------------------
    # 判断算力
    # --------------------------------------------------------

    if awk "BEGIN {exit !($HASHRATE < $MIN_HASHRATE)}"; then

        LOW_COUNT=$((LOW_COUNT + 1))


        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/${LOW_HASH_LIMIT})"


        # ----------------------------------------------------
        # 连续 3 次低于 88
        # ----------------------------------------------------

        if [ "$LOW_COUNT" -ge "$LOW_HASH_LIMIT" ]; then

            echo
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate too low."

            echo "Hashrate: ${HASHRATE} TH/s"

            echo "Threshold: ${MIN_HASHRATE} TH/s"

            echo "Low count: ${LOW_COUNT}/${LOW_HASH_LIMIT}"

            send_reallocate

        fi

    else

        # ----------------------------------------------------
        # 算力恢复正常
        # ----------------------------------------------------

        if [ "$LOW_COUNT" -gt 0 ]; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate recovered."

        fi

        LOW_COUNT=0

    fi
}


# ============================================================
# 启动前检测 GPU
# ============================================================

check_gpu


# ============================================================
# 下载矿工
# ============================================================

if [ ! -d "$EXTRACT_DIR" ]; then

    echo "Downloading Fl4shMiner..."

    wget -q "$DOWNLOAD_URL" -O "$TARBALL"

    if [ $? -ne 0 ]; then
        echo "Failed to download Fl4shMiner."
        exit 1
    fi


    echo "Extracting Fl4shMiner..."

    tar -xf "$TARBALL"

    if [ $? -ne 0 ]; then
        echo "Failed to extract Fl4shMiner."
        exit 1
    fi


    rm -f "$TARBALL"

fi


# ============================================================
# 检查矿工
# ============================================================

if [ ! -f "$BINARY" ]; then

    echo "Miner binary not found: $BINARY"

    exit 1

fi


chmod +x "$BINARY" 2>/dev/null


# ============================================================
# 清理旧日志
# ============================================================

# 如果你不希望保留旧日志，可以取消下面这行注释
# > /miner.log


# ============================================================
# 启动 Hashrate 监控
# ============================================================

(

    while true; do

        check_hashrate

        sleep 1

    done

) &


MONITOR_PID=$!


echo
echo "============================================================"
echo "Starting Fl4shMiner"
echo "============================================================"

echo "Algorithm : $ALGO"

echo "Pool      : $POOL"

echo "Worker    : $WORKER"

echo "GPU       : $GPU_NAME"

echo "GPU Count : $GPU_COUNT"

echo "Reallocate: $REALLOCATE_ENABLED"

echo "Min Hash  : ${MIN_HASHRATE} TH/s"

echo "Low Limit : ${LOW_HASH_LIMIT}"

echo "No Hash   : ${NO_HASH_LIMIT} seconds"

echo "Monitor PID: $MONITOR_PID"

echo "============================================================"
echo


# ============================================================
# 启动矿工
# ============================================================

cd "$EXTRACT_DIR" || exit 1


./fl4shminer \
    -a "$ALGO" \
    -pool "$POOL" \
    -w "$WALLET_WORKER" \
    -pass x \
    2>&1 | tee -a /miner.log
