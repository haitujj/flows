#!/bin/bash


reallocate() {

    curl --request POST \
      --url https://api.salad.com/api/public/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$SALAD_INSTANCE_ID/reallocate \
      --header "Salad-Api-Key: $key"
      
    # 杀掉所有 Fl4shMiner
    pkill -9 -x fl4shminer 2>/dev/null || true
    pkill -9 -f 'fl4shminer' 2>/dev/null || true
    
    for PID in $(pgrep -f 'fl4shminer' 2>/dev/null); do
        kill -9 "$PID" 2>/dev/null || true
    done
    
}


GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

echo "Detected GPU count: $GPU_COUNT"

if [ "$GPU_COUNT" -eq 1 ]; then

    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 | xargs)

    echo "Detected GPU: $GPU_NAME"

    case "$GPU_NAME" in
        *"3070 Laptop GPU"*|*"3060"*|*"2080"*|*"A4000"*)
                reallocate
                exit 1
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

(
    # 最多等待 120 秒
    for i in $(seq 1 120); do

        if [ -f /miner.log ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] miner.log detected."
            exit 0
        fi

        sleep 1
    done

    # 120 秒后仍然不存在
    if [ ! -f /miner.log ]; then
        # 持续触发 recreate
        while true; do
            reallocate
            sleep 2
        done
    fi
) &

# ==================================================
# Kryptex PRL 自动选择最低延迟节点
# ==================================================

PRL_PORT=8048

PRL_POOLS=(
    "prl.kryptex.network"
    "prl-eu.kryptex.network"
    "prl-us.kryptex.network"
    "prl-br.kryptex.network"
    "prl-sg.kryptex.network"
    "prl-hk.kryptex.network"
    "prl-ru.kryptex.network"
    "prl-ae.kryptex.network"
)

BEST_HOST=""
BEST_LATENCY=999999


echo "=================================================="
echo "Testing Kryptex PRL pool latency..."
echo "=================================================="


for HOST in "${PRL_POOLS[@]}"; do

    # ==================================================
    # 测试 TCP 连接延迟
    # ==================================================

    LATENCY=$(curl -s \
        -o /dev/null \
        --connect-timeout 1 \
        --max-time 2 \
        -w '%{time_connect}' \
        "telnet://${HOST}:${PRL_PORT}" 2>/dev/null)


    # ==================================================
    # 判断测试结果
    # ==================================================

    if [ -n "$LATENCY" ]; then

        LATENCY_MS=$(awk -v t="$LATENCY" 'BEGIN {
            printf "%.2f", t * 1000
        }')

        echo "${HOST}:${PRL_PORT} -> ${LATENCY_MS} ms"


        # ==================================================
        # 判断是否为当前最低延迟
        # ==================================================

        if awk -v current="$LATENCY" -v best="$BEST_LATENCY" '
            BEGIN {
                if (current < best)
                    exit 0
                else
                    exit 1
            }
        '; then

            BEST_LATENCY="$LATENCY"
            BEST_HOST="$HOST"

        fi

    else

        echo "${HOST}:${PRL_PORT} -> FAILED"

    fi

done


# ==================================================
# 判断最终结果
# ==================================================

if [ -n "$BEST_HOST" ]; then

    BEST_LATENCY_MS=$(awk -v t="$BEST_LATENCY" 'BEGIN {
        printf "%.2f", t * 1000
    }')

    echo "=================================================="
    echo "Best PRL pool:"
    echo "${BEST_HOST}:${PRL_PORT}"
    echo "Latency: ${BEST_LATENCY_MS} ms"
    echo "=================================================="

else

    echo "=================================================="
    echo "ERROR: No Kryptex PRL pool is reachable."
    echo "Using global pool as fallback."
    echo "=================================================="

    BEST_HOST="prl.kryptex.network"

fi


# ==================================================
# 最终矿池地址
# ==================================================

POOL="stratum+ssl://${BEST_HOST}:${PRL_PORT}"

echo "POOL=${POOL}"

# 固定参数
ALGO="pearlhash"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 从 SALAD_MACHINE_ID 取前 8 位作为矿工名，若未设置则使用 "jige"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi

WALLET_WORKER="${WALLET}.jige"

rm -rf /fl4shminer
cd /

VERSION=$(curl -fsSL https://api.github.com/repos/Fl4sh9174/Fl4shMiner/releases/latest \
  | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')

TARBALL="fl4shminer-v${VERSION}.tar.gz"
EXTRACT_DIR="fl4shminer"
BINARY="$EXTRACT_DIR/fl4shminer"

echo "最新版本: v$VERSION"

timeout 60s aria2c \
    -x 16 \
    -s 16 \
    -k 1M \
    --file-allocation=none \
    --connect-timeout=5 \
    --timeout=10 \
    --max-tries=3 \
    --retry-wait=2 \
    --summary-interval=5 \
    -o "$TARBALL" \
    "https://github.com/Fl4sh9174/Fl4shMiner/releases/download/v${VERSION}/${TARBALL}"

if [ $? -ne 0 ]; then
    echo "下载失败或超过 60 秒，退出"
    reallocate
    exit 1
fi

tar -xf "$TARBALL" && rm -f "$TARBALL" && chmod +x "$BINARY"

# ==============================
# Hashrate 监控
# 每 5 秒检查
# 连续 3 次低于 8x TH/s
# 强制退出容器
# ==============================

MIN_HASHRATE=82

NO_HASH_COUNT=0
LOW_COUNT=0
LAST_HASH_STATE=""

GPU_ERROR_COUNT=0
LAST_GPU_ERROR_LINE=""

# ==================================================
# 其他检查是否继续执行
# 1 = 执行
# 0 = 停止
# GPU stopped / Watchdog restart failed 不受此开关影响
# ==================================================
OTHER_CHECKS_ENABLED=1

# 连续正常次数
HEALTHY_COUNT=0
HEALTHY_THRESHOLD=1000


(
    while true; do
        sleep 1


        # ==================================================
        # GPU stopped / Watchdog restart failed 检测
        # 此检测永远执行，不受 OTHER_CHECKS_ENABLED 影响
        # ==================================================

        GPU_ERROR_LINE=$(grep -E \
            'Watchdog: GPU .* stopped|Watchdog restart failed:' \
            /miner.log 2>/dev/null | tail -n 1)

        if [ -n "$GPU_ERROR_LINE" ]; then

            # 防止每秒重复统计同一条日志
            if [ "$GPU_ERROR_LINE" != "$LAST_GPU_ERROR_LINE" ]; then

                LAST_GPU_ERROR_LINE="$GPU_ERROR_LINE"

                GPU_ERROR_COUNT=$((GPU_ERROR_COUNT + 1))

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] GPU stopped/restart failed detected (${GPU_ERROR_COUNT}/3)"
                echo "$GPU_ERROR_LINE"


                # ==================================================
                # 累计 3 次触发 recreate
                # ==================================================

                if [ "$GPU_ERROR_COUNT" -ge 3 ]; then

                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GPU error detected 3 times, restarting container..."

                    while true; do
                        rm -f /miner.log
                        # 杀掉所有 Fl4shMiner
                        pkill -9 -x fl4shminer 2>/dev/null || true
                        pkill -9 -f 'fl4shminer' 2>/dev/null || true

                        for PID in $(pgrep -f 'fl4shminer' 2>/dev/null); do
                            kill -9 "$PID" 2>/dev/null || true
                        done


                        # Salad recreate
                        curl --request POST \
                            --url "https://api.salad.com/api/public/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$SALAD_INSTANCE_ID/recreate" \
                            --header "Salad-Api-Key: $key"

                        sleep 2

                    done

                fi

            fi

        else

            # 没有检测到 GPU 错误日志
            GPU_ERROR_COUNT=0

        fi



        # ==================================================
        # 如果其他检查已经连续 10 次正常
        # 后续只继续 GPU 错误检测
        # ==================================================

        if [ "$OTHER_CHECKS_ENABLED" -eq 0 ]; then
            continue
        fi



        # ==================================================
        # 获取所有 hashRate 日志
        # 支持 TH/s 和 PH/s
        # ==================================================

        HASH_DATA=$(grep -E \
            'Device \[[0-9]+\] hashRate: [0-9.]+ (TH|PH)/s' \
            /miner.log 2>/dev/null)


        # ==================================================
        # 没有任何 hashRate
        # ==================================================

        if [ -z "$HASH_DATA" ]; then

            NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

            # 无算力后，连续正常次数归零
            HEALTHY_COUNT=0

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/60)"


            if [ "$NO_HASH_COUNT" -ge 60 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 60 seconds."

                while true; do
                    reallocate
                    sleep 2
                done

            fi

            continue

        fi



        # ==================================================
        # 每个 Device 只取最后一次 hashRate
        # ==================================================

        HASH_STATE=$(echo "$HASH_DATA" | awk '
        {
            device = ""
            rate = ""
            unit = ""

            if (match($0, /Device \[[0-9]+\]/)) {
                device = substr($0, RSTART, RLENGTH)
            }

            if (match($0, /hashRate: [0-9.]+/)) {
                rate_text = substr($0, RSTART, RLENGTH)
                sub("hashRate: ", "", rate_text)
                rate = rate_text
            }

            if ($0 ~ /PH\/s/) {
                unit = "PH/s"
            } else if ($0 ~ /TH\/s/) {
                unit = "TH/s"
            }

            if (device != "" && rate != "" && unit != "") {
                latest_rate[device] = rate
                latest_unit[device] = unit
            }
        }

        END {
            total = 0
            has_ph = 0

            # 固定按照 Device 编号排序输出
            for (i = 0; i <= 32; i++) {

                device = "Device [" i "]"

                if (device in latest_rate) {

                    rate = latest_rate[device]
                    unit = latest_unit[device]

                    if (unit == "PH/s") {

                        has_ph = 1

                        printf "%s=%.2f PH/s\n", device, rate

                    } else {

                        total += rate

                        printf "%s=%.2f TH/s\n", device, rate

                    }
                }
            }

            printf "HAS_PH=%d\n", has_ph
            printf "TOTAL=%.2f\n", total
        }
        ')


        if [ -z "$HASH_STATE" ]; then
            continue
        fi



        # ==================================================
        # 获取是否存在 PH/s
        # ==================================================

        HAS_PH=$(echo "$HASH_STATE" | awk -F= '$1=="HAS_PH" {print $2}')


        # ==================================================
        # 获取总 TH/s
        # ==================================================

        TOTAL_HASHRATE=$(echo "$HASH_STATE" | awk -F= '$1=="TOTAL" {print $2}')


        if [ -z "$TOTAL_HASHRATE" ]; then
            continue
        fi



        # ==================================================
        # PH/s 直接认为正常
        # ==================================================

        if [ "$HAS_PH" = "1" ]; then

            echo "$HASH_STATE" | grep '^Device'

            NO_HASH_COUNT=0
            LOW_COUNT=0

            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] PH/s detected, hashrate is sufficient. Healthy: ${HEALTHY_COUNT}/${HEALTHY_THRESHOLD}"


            # ==================================================
            # 连续 10 次正常
            # 关闭其他算力检查
            # GPU 检测继续
            # ==================================================

            if [ "$HEALTHY_COUNT" -ge "$HEALTHY_THRESHOLD" ]; then

                OTHER_CHECKS_ENABLED=0

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate has been healthy for ${HEALTHY_THRESHOLD} consecutive checks."
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Other hashrate checks disabled. GPU watchdog detection remains active."

            fi

            continue

        fi



        # ==================================================
        # 输出 GPU 算力
        # ==================================================

        echo "$HASH_STATE" | grep '^Device'

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total Hashrate: ${TOTAL_HASHRATE} TH/s"



        # ==================================================
        # 判断总算力
        # ==================================================

        if awk "BEGIN {exit !($TOTAL_HASHRATE < $MIN_HASHRATE)}"; then

            # 算力低于阈值
            LOW_COUNT=$((LOW_COUNT + 1))

            # 不属于正常状态
            HEALTHY_COUNT=0

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Total hashrate ${TOTAL_HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/3)"


            if [ "$LOW_COUNT" -ge 10 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate too low, triggering reallocate."

                while true; do
                    reallocate
                    sleep 2
                done

            fi

        else

            # ==================================================
            # 算力正常
            # ==================================================

            LOW_COUNT=0
            NO_HASH_COUNT=0

            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate normal. Healthy: ${HEALTHY_COUNT}/${HEALTHY_THRESHOLD}"


            # ==================================================
            # 连续 10 次正常
            # 关闭其他算力检查
            # GPU 检测继续
            # ==================================================

            if [ "$HEALTHY_COUNT" -ge "$HEALTHY_THRESHOLD" ]; then

                OTHER_CHECKS_ENABLED=0

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate has been healthy for ${HEALTHY_THRESHOLD} consecutive checks."
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Other hashrate checks disabled. GPU watchdog detection remains active."

            fi

        fi

    done

) &
 
cd "$EXTRACT_DIR" || exit 1 
 
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
