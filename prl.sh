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
LAST_HASH_STATE=""

(
    while true; do
        sleep 1

        # ==================================================
        # 获取每张 GPU 最新一次 hashRate
        # 每个 Device 只保留最新值
        # ==================================================

        HASH_DATA=$(grep 'Device \[[0-9]\+\] hashRate:' /miner.log 2>/dev/null)

        if [ -z "$HASH_DATA" ]; then

            NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/40)"

            if [ "$NO_HASH_COUNT" -ge 40 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 40 seconds."

                # 这里执行你的 reallocate
                while true; do

                    curl "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
                      -X POST \
                      -H 'accept: */*' \
                      -H 'content-length: 0' \
                      -b "scid=$TK"

                    sleep 2

                done

            fi

            continue
        fi


        # ==================================================
        # 每个 Device 只取最后一次 hashRate
        # 然后计算所有 GPU 最新总算力
        # ==================================================

        HASH_STATE=$(echo "$HASH_DATA" | awk '
        {
            if (match($0, /Device \[[0-9]+\] hashRate: [0-9.]+ TH\/s/)) {

                line = substr($0, RSTART, RLENGTH)

                match(line, /Device \[[0-9]+\]/)
                device = substr(line, RSTART, RLENGTH)

                match(line, /hashRate: [0-9.]+/)
                rate = substr(line, RSTART + 10, RLENGTH - 10)

                latest[device] = rate
            }
        }

        END {
            total = 0

            for (device in latest) {
                total += latest[device]
                printf "%s=%s\n", device, latest[device]
            }

            printf "TOTAL=%.2f\n", total
        }
        ')


        if [ -z "$HASH_STATE" ]; then
            continue
        fi


        # ==================================================
        # 防止同一组数据重复判断
        # ==================================================

        if [ "$HASH_STATE" = "$LAST_HASH_STATE" ]; then
            continue
        fi

        LAST_HASH_STATE="$HASH_STATE"

        NO_HASH_COUNT=0


        # ==================================================
        # 提取总算力
        # ==================================================

        TOTAL_HASHRATE=$(echo "$HASH_STATE" | awk -F= '$1=="TOTAL" {print $2}')


        if [ -z "$TOTAL_HASHRATE" ]; then
            continue
        fi


        # ==================================================
        # 输出每张 GPU 最新算力
        # ==================================================

        echo "$HASH_STATE" | grep '^Device'


        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total Hashrate: ${TOTAL_HASHRATE} TH/s"


        # ==================================================
        # 判断总算力
        # ==================================================

        if awk "BEGIN {exit !($TOTAL_HASHRATE < $MIN_HASHRATE)}"; then

            LOW_COUNT=$((LOW_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Total hashrate ${TOTAL_HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/3)"


            if [ "$LOW_COUNT" -ge 3 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total hashrate too low 3 times, sending reallocate request..."

                while true; do

                    curl "https://portal-api.salad.com/api/portal/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$HOSTNAME/reallocate" \
                      -X POST \
                      -H 'accept: */*' \
                      -H 'content-length: 0' \
                      -b "scid=$TK"

                    sleep 2

                done

            fi

        else

            LOW_COUNT=0

        fi

    done
) &
 
 
# ============================== 
# 启动矿工 
# ============================== 
 
cd "$EXTRACT_DIR" || exit 1 
 
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
