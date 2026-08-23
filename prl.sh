#!/bin/bash

# 固定参数
ALGO="pearlhash"
POOL="stratum+tcp://pool.pearlhash.xyz:9000"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 获取 WORKER：从 SALAD_MACHINE_ID 取前 8 位
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"   # 未设置时的默认值
fi
echo "矿工名: $WORKER"

# 下载信息
DOWNLOAD_URL="https://github.com/andru-kun/wildrig-multi/releases/download/0.50.3/wildrig-multi-linux-0.50.3.tar.gz"
TARBALL="wildrig-multi-linux-0.50.3.tar.gz"
BINARY="./wildrig-multi"

# 检查主程序是否存在，若不存在则下载并解压
if [ ! -f "$BINARY" ]; then
    echo "wildrig-multi 未找到，开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压中..."
    tar -xzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包
    rm -f "$TARBALL"
    # 确保可执行
    chmod +x "$BINARY"
else
    echo "wildrig-multi 已存在，跳过下载"
fi

# 启动挖矿
echo "启动 wildrig-multi，矿工名: $WORKER"
./wildrig-multi \
    --algo "$ALGO" \
    --url "$POOL" \
    --user "$WALLET" \
    --pass "x" \
    --worker "$WORKER"
