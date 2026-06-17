#!/bin/bash

# 固定参数
HOST="pool.pearlhash.xyz:9000"
MINER_URL="https://pearlhash.xyz/downloads/pearl-miner-v12"
MINER_BIN="pearl-miner"

# 根据环境变量分组设置钱包和矿工名
GROUP_NAME="$SALAD_CONTAINER_GROUP_NAME"
echo "检测到 SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"

case "$GROUP_NAME" in
    s1|s2|s3)
        WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
        WORKER="jige666"
        ;;
    s4|s5|s6)
        WALLET="prl1pxqqpx28r0kag2r9kh3dv083f6a2lmzwtfstmna2zveq8zlmxm5cqxt0wcm"
        WORKER="jigenb"
        ;;
    *)
        echo "未匹配到分组，使用默认配置（s1-s3 的钱包和矿工名）"
        WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
        WORKER="jige-primary"
        ;;
esac

echo "使用的钱包: $WALLET"
echo "使用的矿工名: $WORKER"

# 下载官方矿工（每次运行重新下载以确保最新）
echo "下载 pearl-miner ..."
curl -s -L "$MINER_URL" -o "$MINER_BIN"
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络"
    exit 1
fi
chmod +x "$MINER_BIN"

# 启动挖矿
echo "启动官方矿工 ..."
./"$MINER_BIN" --host "$HOST" --user "$WALLET" --worker "$WORKER"
