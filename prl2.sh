#!/bin/bash

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
ALGO="pearlhash"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 从 SALAD_MACHINE_ID 取前 8 位作为矿工名，若未设置则使用 "jige"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi

WALLET_WORKER="${WALLET}/${JNAME:-jige_clore}"

rm -f /miner.log
cd /fl4shminer || exit 1 
 
./fl4shminer -a "$ALGO" -pool "$POOL" -w "$WALLET_WORKER" -pass x 2>&1 | tee -a /miner.log
