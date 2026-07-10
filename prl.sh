#!/bin/bash

# 固定参数
WALLET="btx1z3p8ahqamkurhgt3l68nwv4k8kg84agpzy5604a7fke35n953dd2qrffzhw"
POOL="ninjaraider.com:44920"
ALGO="btx"

# 获取主机名（若未设置则使用 "unknown"）
WORKER=$HOSTNAME
echo "矿工名将使用主机名: $WORKER"

# 矿工程序下载信息
MINER_URL="https://github.com/nr800/nekominer/releases/download/v0.11.55/nekominer"
MINER_BIN="./nekominer"

# 检查矿工是否存在，若不存在则下载
if [ ! -f "$MINER_BIN" ]; then
    echo "nekominer 未找到，开始下载..."
    wget "$MINER_URL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
else
    echo "nekominer 已存在，跳过下载"
fi

# 确保可执行
chmod +x "$MINER_BIN"

# 完整用户参数（钱包.主机名）
USER="${WALLET}.${WORKER}"
echo "启动参数: -a $ALGO --pool $POOL -u $USER"

# 启动挖矿
./nekominer -a "$ALGO" --pool "$POOL" -u "$USER"
