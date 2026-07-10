#!/bin/bash

# 固定参数
PAYOUT="btx1z3p8ahqamkurhgt3l68nwv4k8kg84agpzy5604a7fke35n953dd2qrffzhw"
POOL="global.btxpool.org:23333"
WORKER="$(HOSTNAME)"   # 使用主机名作为矿工名

# 下载信息
DOWNLOAD_URL="https://github.com/pearlfortune/btx-miner/releases/download/v2.7.0/btx-v2.7.0.tar.gz"
TARBALL="btx-v2.7.0.tar.gz"
EXTRACT_DIR="btx"

# 检查解压目录是否存在，若不存在则下载并解压
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "btx-miner 未找到，开始下载..."
    wget -c -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压中..."
    tar vxzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包
    rm -f "$TARBALL"
else
    echo "btx-miner 已存在，跳过下载"
fi

# 进入解压目录
cd "$EXTRACT_DIR" || exit 1

# 自动选择可用的 CUDA 版本（优先 cu13，若无则 cu12）
if [ -f "./btx-miner-cu13" ]; then
    BIN="./btx-miner-cu13"
    echo "使用 CUDA 13 版本"
elif [ -f "./btx-miner-cu12" ]; then
    BIN="./btx-miner-cu12"
    echo "使用 CUDA 12 版本"
else
    echo "错误：未找到 btx-miner 二进制文件"
    exit 1
fi

chmod +x "$BIN"

# 启动挖矿
echo "启动 btx-miner，矿工名: $WORKER"
$BIN -mode stratum -backend cuda -gpu-devices all -payout "$PAYOUT" -worker "$WORKER" -pool "$POOL"
