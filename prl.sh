#!/bin/bash


reallocate() {

    curl --request POST \
      --url https://api.salad.com/api/public/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$SALAD_INSTANCE_ID/reallocate \
      --header "Salad-Api-Key: $key"

    # 杀掉所有 wildrig-multi
    pkill -9 -x wildrig-multi 2>/dev/null || true
    pkill -9 -f 'wildrig-multi' 2>/dev/null || true

    for PID in $(pgrep -f 'wildrig-multi' 2>/dev/null); do
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


MIN_HASHRATE=75

NO_HASH_COUNT=0
LOW_COUNT=0
LAST_HASH_STATE=""

GPU_ERROR_COUNT=0
LAST_GPU_ERROR_LINE=""


(
    while true; do

        sleep 2


        # ==================================================
        # 获取 WildRig hashRate 日志
        #
        # WildRig 输出格式：
        #
        # #0 GeForce RTX 3070 Ti        84.14 TH/s  72C  75% ...
        #
        # 清除 ANSI 控制字符和 CR
        # ==================================================

        HASH_DATA=$(sed \
            -e 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' \
            -e 's/\r//g' \
            /miner.log 2>/dev/null | \
            grep -E '#[0-9]+[[:space:]].*[0-9]+([.][0-9]+)?[[:space:]]+(TH|PH)/s')


        # ==================================================
        # 没有任何 hashRate
        # ==================================================

        if [ -z "$HASH_DATA" ]; then

            NO_HASH_COUNT=$((NO_HASH_COUNT + 1))

            # 无算力时清空上次算力状态，恢复后重新输出
            LAST_HASH_STATE=""

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected (${NO_HASH_COUNT}/80)"


            if [ "$NO_HASH_COUNT" -ge 80 ]; then

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] No hashrate detected for 80 seconds."

                while true; do
                    reallocate
                    sleep 2
                done

            fi

            continue

        fi


        # ==================================================
        # WildRig 每个 GPU 只取最后一次 hashRate
        #
        # 例如：
        #
        # #0 GeForce RTX 3070 Ti 84.14 TH/s
        #
        # 转换：
        #
        # Device [0]=84.14 TH/s
        # ==================================================

        HASH_STATE=$(echo "$HASH_DATA" | awk '
        {
            device_num = ""
            rate = ""
            unit = ""

            # 查找 GPU 编号
            for (i = 1; i <= NF; i++) {

                if ($i ~ /^#[0-9]+$/) {
                    device_num = substr($i, 2)
                    break
                }

            }

            # 查找 TH/s 或 PH/s
            for (i = 1; i <= NF; i++) {

                if ($i == "TH/s" || $i == "PH/s") {

                    unit = $i

                    if (i > 1 && $(i-1) ~ /^[0-9]+([.][0-9]+)?$/) {
                        rate = $(i-1)
                    }

                    break
                }

            }

            # 保存最后一次出现的值
            if (device_num != "" && rate != "" && unit != "") {

                latest_rate[device_num] = rate
                latest_unit[device_num] = unit

            }
        }

        END {

            total = 0
            has_ph = 0

            # 固定按照 GPU 编号排序输出
            for (i = 0; i <= 32; i++) {

                if (i in latest_rate) {

                    rate = latest_rate[i]
                    unit = latest_unit[i]

                    if (unit == "PH/s") {

                        has_ph = 1

                        printf "Device [%d]=%.2f PH/s\n", i, rate

                    } else {

                        total += rate

                        printf "Device [%d]=%.2f TH/s\n", i, rate

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

            # 只有算力状态变化时才输出
            if [ "$HASH_STATE" != "$LAST_HASH_STATE" ]; then

                echo "$HASH_STATE" | grep '^Device'
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] PH/s detected, hashrate is sufficient."

                LAST_HASH_STATE="$HASH_STATE"

            fi

            NO_HASH_COUNT=0
            LOW_COUNT=0

            continue

        fi


        # ==================================================
        # 输出 GPU 算力
        # 只有算力状态变化时才输出，避免重复
        # ==================================================

        if [ "$HASH_STATE" != "$LAST_HASH_STATE" ]; then

            echo "$HASH_STATE" | grep '^Device'

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total Hashrate: ${TOTAL_HASHRATE} TH/s"

            LAST_HASH_STATE="$HASH_STATE"

        fi


        # ==================================================
        # 判断总算力
        # ==================================================

        if awk "BEGIN {exit !($TOTAL_HASHRATE < $MIN_HASHRATE)}"; then

            # 算力低于阈值
            LOW_COUNT=$((LOW_COUNT + 1))

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

        fi

    done

) &

# 从 SALAD_MACHINE_ID 取前 8 位作为矿工名，若未设置则使用 "jige"
MACHINE_ID="${SALAD_MACHINE_ID:-}"

if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi

./wildrig-multi \
    --algo pearlhash \
    --url pool.pearlhash.xyz:9000 \
    --user prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q \
    --worker "$SALAD_CONTAINER_GROUP_NAME"_"$WORKER" \
    2>&1 | tee -a /miner.log
