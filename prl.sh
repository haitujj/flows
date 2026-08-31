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
