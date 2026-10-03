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

# ==================================================
# 检查 GPU 数量
# 如果环境变量 GPU_COUNTS 有值，且 GPU 数量小于 2
# 则一直执行 reallocate
# ==================================================
GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

echo "Detected GPU count: $GPU_COUNT"

if [ -n "$GPU_COUNTS" ] && [ "$GPU_COUNT" -lt 2 ]; then

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GPU count is ${GPU_COUNT}, less than 2. Triggering reallocate." 
    reallocate
    exit 1

fi

if [ -z "$GPU" ] && [ "$GPU_COUNT" -eq 1 ]; then

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

# ==================================================
# Kryptex PRL 自动选择最低延迟矿池
# ==================================================

# 日志显示矿工实际连接 8049 端口
POOL_PORT=8049

POOLS=(
    "qtc.kryptex.network"
    "qtc-eu.kryptex.network"
    "qtc-us.kryptex.network"
    "qtc-br.kryptex.network"
    "qtc-sg.kryptex.network"
    "qtc-hk.kryptex.network"
    "qtc-ru.kryptex.network"
    "qtc-ae.kryptex.network"
)

BEST_POOL=""
BEST_LATENCY=999999

echo "========================================"
echo "Testing Kryptex PRL pool latency..."
echo "========================================"

for HOST in "${POOLS[@]}"; do

    # TCP 连接测试
    START_TIME=$(date +%s%N)

    if timeout 3 bash -c "echo >/dev/tcp/$HOST/$POOL_PORT" 2>/dev/null; then

        END_TIME=$(date +%s%N)

        # 纳秒 -> 毫秒
        LATENCY=$(( (END_TIME - START_TIME) / 1000000 ))

        echo "$HOST:$POOL_PORT -> ${LATENCY} ms"

        if [ "$LATENCY" -lt "$BEST_LATENCY" ]; then
            BEST_LATENCY="$LATENCY"
            BEST_POOL="$HOST"
        fi

    else

        echo "$HOST:$POOL_PORT -> FAILED"

    fi

done


# ==================================================
# 选择最低延迟节点
# ==================================================

if [ -n "$BEST_POOL" ]; then

    POOL="stratum+ssl://${BEST_POOL}:${POOL_PORT}"

    echo "========================================"
    echo "Best Kryptex PRL pool:"
    echo "$POOL"
    echo "Latency: ${BEST_LATENCY} ms"
    echo "========================================"

else

    echo "ERROR: No Kryptex PRL pool is reachable."

    # 保底 Global
    POOL="stratum+ssl://qtc.kryptex.network:${POOL_PORT}"

    echo "Fallback pool:"
    echo "$POOL"

fi

echo "POOL=${POOL}"
# 固定参数
ALGO="quantus"
WALLET="qzodHryFjHjiy4w5TsXUzxPpVnHmwcgrCXB41DnmD2S1tz5Mr"


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

# 从 SALAD_MACHINE_ID 取前 8 位作为矿工名，若未设置则使用 "jige"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi

WALLET_WORKER="${WALLET}.${JNAME:-jige}"

# ==============================
# Hashrate 监控
# 每 2 秒检查一次
# 连续多次低于阈值 → 强制退出容器
# ==============================

# 单位：MH/s（可通过 HASHRATE 覆盖）
MIN_HASHRATE="${HASHRATE:-310}"

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
HEALTHY_THRESHOLD=999999999


(
    while true; do
        sleep 2


        # ==================================================
        # GPU stopped / Watchdog restart failed 检测
        # 此检测永远执行，不受 OTHER_CHECKS_ENABLED 影响
        # ==================================================

        GPU_ERROR_LINE=$(grep -E \
            'Watchdog: GPU .* stopped|Watchdog restart failed:|retrying in 10s' \
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
        # 如果其他检查已经关闭
        # 后续只继续 GPU 错误检测
        # ==================================================

        if [ "$OTHER_CHECKS_ENABLED" -eq 0 ]; then
            continue
        fi



        # ==================================================
        # 获取所有 hashRate 日志
        # 支持 MH/s、TH/s 和 PH/s
        # ==================================================

        HASH_DATA=$(grep -E \
            'Device \[[0-9]+\] hashRate: [0-9.]+ (MH|TH|PH)/s' \
            /miner.log 2>/dev/null)


        # ==================================================
        # 没有任何 hashRate
        # ==================================================

        if [ -z "$HASH_DATA" ]; then

            NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

            # 无算力后，连续正常次数归零
            HEALTHY_COUNT=0

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/40)"


            if [ "$NO_HASH_COUNT" -ge 40 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 80 seconds."

                while true; do
                    reallocate
                    sleep 2
                done

            fi

            continue

        fi



        # ==================================================
        # 每个 Device 只取最后一次 hashRate
        # 全部换算为 MH/s 做汇总
        # ==================================================

        HASH_STATE=$(echo "$HASH_DATA" | awk '
        {
            device = ""
            rate = ""
            mult = 0

            if (match($0, /Device \[[0-9]+\]/)) {
                device = substr($0, RSTART, RLENGTH)
            }

            if (match($0, /hashRate: [0-9.]+/)) {
                rate_text = substr($0, RSTART, RLENGTH)
                sub("hashRate: ", "", rate_text)
                rate = rate_text
            }

            if ($0 ~ /PH\/s/) {
                mult = 1000000000
            } else if ($0 ~ /TH\/s/) {
                mult = 1000000
            } else if ($0 ~ /MH\/s/) {
                mult = 1
            }

            if (device != "" && rate != "" && mult > 0) {
                latest_rate[device] = rate
                latest_mult[device] = mult
            }
        }

        END {
            total_mh = 0
            has_high = 0

            for (i = 0; i <= 32; i++) {

                device = "Device [" i "]"

                if (device in latest_rate) {

                    rate = latest_rate[device]
                    mult = latest_mult[device]

                    if (mult > 1) {
                        has_high = 1
                    }

                    if (mult == 1000000000) {
                        printf "%s=%.2f PH/s\n", device, rate
                    } else if (mult == 1000000) {
                        printf "%s=%.2f TH/s\n", device, rate
                    } else {
                        printf "%s=%.2f MH/s\n", device, rate
                    }

                    total_mh += rate * mult
                }
            }

            printf "HAS_HIGH=%d\n", has_high
            printf "TOTAL_MH=%.2f\n", total_mh
        }
        ')


        if [ -z "$HASH_STATE" ]; then
            continue
        fi



        # ==================================================
        # 获取是否存在高单位（TH/s / PH/s）
        # ==================================================

        HAS_HIGH=$(echo "$HASH_STATE" | awk -F= '$1=="HAS_HIGH" {print $2}')


        # ==================================================
        # 获取总 MH/s
        # ==================================================

        TOTAL_HASHRATE_MH=$(echo "$HASH_STATE" | awk -F= '$1=="TOTAL_MH" {print $2}')


        if [ -z "$TOTAL_HASHRATE_MH" ]; then
            continue
        fi



        # ==================================================
        # TH/s / PH/s 直接认为正常
        # ==================================================

        if [ "$HAS_HIGH" = "1" ]; then

            echo "$HASH_STATE" | grep '^Device'

            NO_HASH_COUNT=0
            LOW_COUNT=0

            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] TH/s or PH/s detected, hashrate is sufficient. Healthy: ${HEALTHY_COUNT}/${HEALTHY_THRESHOLD}"


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

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total Hashrate: ${TOTAL_HASHRATE_MH} MH/s (threshold ${MIN_HASHRATE} MH/s)"



        # ==================================================
        # 判断总算力
        # ==================================================

        if awk "BEGIN {exit !($TOTAL_HASHRATE_MH < $MIN_HASHRATE)}"; then

            # 算力低于阈值
            LOW_COUNT=$((LOW_COUNT + 1))

            # 不属于正常状态
            HEALTHY_COUNT=0

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Total hashrate ${TOTAL_HASHRATE_MH} MH/s < ${MIN_HASHRATE} MH/s (${LOW_COUNT}/10)"


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


            if [ "$HEALTHY_COUNT" -ge "$HEALTHY_THRESHOLD" ]; then

                OTHER_CHECKS_ENABLED=0

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate has been healthy for ${HEALTHY_THRESHOLD} consecutive checks."
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Other hashrate checks disabled. GPU watchdog detection remains active."

            fi

        fi

    done

) &

rm -f /miner.log
cd /fl4shminer || exit 1 
 
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
