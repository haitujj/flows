#!/bin/bash

GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

echo "Detected GPU count: $GPU_COUNT"

if [ "$GPU_COUNT" -eq 1 ]; then

    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 | xargs)

    echo "Detected GPU: $GPU_NAME"

    case "$GPU_NAME" in
        *"RNVIDIA GeForce RTX 3070 Laptop GPU"*|*"3060"*|*"2080"*|"NVIDIA GeForce RTX 3070")
            echo "Target GPU detected: $GPU_NAME"
            echo "Sending Salad reallocate request..."
            while true; do
                curl "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
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
                  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36'
            
                sleep 2
            done

            echo
            echo "Reallocate request sent."
            ;;

        *)
            echo "GPU $GPU_NAME is not a target GPU, no request."
            ;;
    esac

elif [ "$GPU_COUNT" -gt 1 ]; then

    echo "Multiple GPUs detected ($GPU_COUNT), reallocate disabled."

else

    echo "No NVIDIA GPU detected, no request."

fi

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

WALLET_WORKER="${WALLET}.jige"

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
NO_HASH_COUNT=0
LOW_COUNT=0
LAST_HASH_LINE=""

(
    while true; do
        sleep 1

        HASH_LINE=$(grep 'hashRate:' /miner.log 2>/dev/null | tail -n 1)

        # 没有获取到 hashRate
        if [ -z "$HASH_LINE" ]; then
            NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/40)"

            if [ "$NO_HASH_COUNT" -ge 40 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 10 consecutive checks, sending reallocate request..."
                while true; do
                    curl "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
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
                      -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36'
                
                    sleep 2
                done

            fi

            continue
        fi

        # 获取到了 hashRate，重置无算力计数
        NO_HASH_COUNT=0

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

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate too low 3 times, sending reallocate request..."

                while true; do
                    curl "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
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
                      -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36' 
                 
                    sleep 2 
                done 
                exit 1 
            fi 
 
        else 
            # 恢复正常 
            LOW_COUNT=0 
            exit 1
        fi 
 
    done 
) & 
 
 
# ============================== 
# 启动矿工 
# ============================== 
 
cd "$EXTRACT_DIR" || exit 1 
 
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
