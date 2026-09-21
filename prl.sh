#!/bin/bash


reallocate() {

    curl --request POST \
      --url https://api.salad.com/api/public/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$SALAD_INSTANCE_ID/reallocate \
      --header "Salad-Api-Key: $key"
      
    # 杀掉所有 peakminer
    pkill -9 -x peakminer 2>/dev/null || true
    pkill -9 -f 'peakminer' 2>/dev/null || true
    
    for PID in $(pgrep -f 'peakminer' 2>/dev/null); do
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

POOL_PORT=8048

POOLS=(
    "prl.kryptex.network"
    "prl-eu.kryptex.network"
    "prl-us.kryptex.network"
    "prl-br.kryptex.network"
    "prl-sg.kryptex.network"
    "prl-hk.kryptex.network"
    "prl-ru.kryptex.network"
    "prl-ae.kryptex.network"
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
    POOL="stratum+ssl://prl.kryptex.network:${POOL_PORT}"

    echo "Fallback pool:"
    echo "$POOL"

fi

echo "POOL=${POOL}"
# 固定参数
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"


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

WALLET_WORKER="${WALLET}/${JNAME:-jige}"

# ==============================
# Hashrate 监控
# 每 5 秒检查
# 连续 3 次低于 8x TH/s
# 强制退出容器
# ==============================

MIN_HASHRATE="${HASHRATE:-78}"

NO_HASH_COUNT=0
LOW_COUNT=0
LAST_HASH_STATE=""

GPU_ERROR_COUNT=0
LAST_GPU_ERROR_LINE=""

# 连续正常次数
HEALTHY_COUNT=0


(
    # 初始化上次算力状态，用于避免重复输出
    LAST_HASH_STATE=""

    while true; do
        sleep 4

        # ==================================================
        # 获取所有 hashRate 日志
        # 支持 TH/s 和 PH/s，适配 peakminer 表格格式
        # ==================================================

        HASH_DATA=$(grep -E \
            '^[[:space:]]*[0-9]+[[:space:]]+.*[0-9.]+[[:space:]]+(TH|PH)/s' \
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

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 40 seconds."

                while true; do
                    reallocate
                    sleep 2
                done

            fi

            continue

        fi

        # ==================================================
        # 每个 Device 只取最后一次 hashRate
        # 解析 peakminer 表格格式
        # ==================================================

        HASH_STATE=$(echo "$HASH_DATA" | awk '
        {
            device = ""
            device_num = ""
            rate = ""
            unit = ""

            # 匹配 GPU 表格行开头的编号，例如：  0  RTX 3070 Ti ...
            if (match($0, /^[[:space:]]*[0-9]+/)) {
                device_num = substr($0, RSTART, RLENGTH)
                gsub(/[[:space:]]/, "", device_num)
                device = "Device [" device_num "]"
            }

            # 匹配 Hashrate 列，例如：88.3 TH/s 或 1.23 PH/s
            if (match($0, /[0-9.]+[[:space:]]+(TH|PH)\/s/)) {
                rate_text = substr($0, RSTART, RLENGTH)
                split(rate_text, parts, /[[:space:]]+/)
                rate = parts[1]
                unit = parts[2]
            }

            if (device != "" && rate != "" && unit != "") {
                latest_rate[device] = rate
                latest_unit[device] = unit
            }
        }

        END {
            total = 0
            has_ph = 0

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
        # 判断算力状态是否变化，只有变化时才输出
        # ==================================================

        if [ "$HASH_STATE" != "$LAST_HASH_STATE" ]; then
            SHOULD_PRINT=1
            LAST_HASH_STATE="$HASH_STATE"
        else
            SHOULD_PRINT=0
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

            if [ "$SHOULD_PRINT" -eq 1 ]; then
                echo "$HASH_STATE" | grep '^Device'
            fi

            NO_HASH_COUNT=0
            LOW_COUNT=0

            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))

            if [ "$SHOULD_PRINT" -eq 1 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] PH/s detected, hashrate is sufficient. Healthy: ${HEALTHY_COUNT}"
            fi

            continue

        fi

        # ==================================================
        # 输出 GPU 算力（仅当变化时）
        # ==================================================

        if [ "$SHOULD_PRINT" -eq 1 ]; then
            echo "$HASH_STATE" | grep '^Device'
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total Hashrate: ${TOTAL_HASHRATE} TH/s"
        fi

        # ==================================================
        # 判断总算力
        # ==================================================

        if awk "BEGIN {exit !($TOTAL_HASHRATE < $MIN_HASHRATE)}"; then

            # 算力低于阈值
            LOW_COUNT=$((LOW_COUNT + 1))

            # 不属于正常状态
            HEALTHY_COUNT=0

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Total hashrate ${TOTAL_HASHRATE} TH/s < ${MIN_HASHRATE} TH/s (${LOW_COUNT}/10)"

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

            if [ "$SHOULD_PRINT" -eq 1 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hashrate normal. Healthy: ${HEALTHY_COUNT}"
            fi

        fi

    done

) &

rm -f /miner.log
cd /peakminer || exit 1 
 
./peakminer --coin pearl -o "$POOL" -u "$WALLET_WORKER" 2>&1 | tee -a /miner.log
