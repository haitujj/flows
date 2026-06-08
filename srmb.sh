sleep 30

MINER_DIR=/workspace
SRB_URL="https://github.com/kryptex-miners-org/kryptex-miners/releases/download/srbminer-3-3-5/SRBMiner-Multi-3-3-5-Linux.tar.gz"
SRB_BIN="/usr/local/bin/SRBMiner-MULTI"
LOG_DIR="${MINER_DIR}/logs"
POOL=${POOL:-prl.kryptex.network:7048}
WALLET=${WALLET:-prl1pxqqpx28r0kag2r9kh3dv083f6a2lmzwtfstmna2zveq8zlmxm5cqxt0wcm}
WORKER=${WORKER:-jige666}

mkdir -p $LOG_DIR

# 下载矿工
if [ ! -f "$SRB_BIN" ]; then
    echo "[$(date '+%F %T')] Downloading SRBMiner-MULTI..."
    curl -L $SRB_URL -o /tmp/SRBMiner.tar.gz
    tar -xzf /tmp/SRBMiner.tar.gz -C /usr/local/bin --strip-components=1
    chmod +x $SRB_BIN
    rm /tmp/SRBMiner.tar.gz
    echo "[$(date '+%F %T')] SRBMiner-MULTI installed."
fi

# 矿工守护循环（容器永不退出）
(
while true; do
    echo "[$(date '+%F %T')] Starting SRBMiner-MULTI..." | tee -a $LOG_DIR/srbminer.log
    $SRB_BIN \
        --disable-cpu \
        --algorithm pearlhash \
        --pool $POOL \
        --wallet $WALLET.$WORKER \
        --log-file $LOG_DIR/srbminer.log \
        --log-file-mode 1
    EXIT_CODE=$?
    echo "[$(date '+%F %T')] SRBMiner exited with code $EXIT_CODE" | tee -a $LOG_DIR/srbminer.log
    sleep 10
done
)
