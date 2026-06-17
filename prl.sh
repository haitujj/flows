#!/bin/bash

# 通用配置（钱包和矿工名）
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
WORKER="jige666"

# 获取环境变量（若未设置则为空）
GROUP_NAME="$SALAD_CONTAINER_GROUP_NAME"
echo "检测到 SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"

# 根据环境变量决定使用哪个矿工程序
if [[ "$GROUP_NAME" == "s1" || "$GROUP_NAME" == "s2" || "$GROUP_NAME" == "s3" ]]; then
    echo "---- 使用官方 pearl-miner（s1-s3）----"
    # 官方矿工参数
    HOST="pool.pearlhash.xyz:9000"
    USER="$WALLET"
    WORKER="$WORKER"

    # 下载官方矿工（每次运行确保最新，也可判断存在性，但按需求直接下载覆盖）
    echo "下载 pearl-miner ..."
    curl -s -L "https://pearlhash.xyz/downloads/pearl-miner-v12" -o pearl-miner
    if [ $? -ne 0 ]; then
        echo "下载 pearl-miner 失败，请检查网络"
        exit 1
    fi
    chmod +x pearl-miner

    ./pearl-miner --host "$HOST" --user "$USER" --worker "$WORKER"
    exit 0
fi

# 否则（s4-s7 或未设置或其它）使用 SRBMiner-Multi
echo "---- 使用 SRBMiner-Multi（s4-s7 或默认）----"

# 以下为原 SRBMiner 逻辑（保留国家检测）
ALGORITHM="pearlhash"
PORT="3360"

DOWNLOAD_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/3.3.9/SRBMiner-Multi-3-3-9-Linux.tar.gz"
FILENAME="SRBMiner-Multi-3-3-9-Linux.tar.gz"
EXTRACT_DIR="SRBMiner-Multi-3-3-9"
BINARY="$EXTRACT_DIR/SRBMiner-MULTI"

# 默认池（美国东岸）
DEFAULT_POOL="pearl-us-east.luckypool.io"

# 获取国家代码（超时3秒）
COUNTRY=$(curl -s --max-time 3 "https://ipinfo.io/json" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)

if [ -z "$COUNTRY" ]; then
    echo "无法获取国家信息，使用默认池（美国）"
    POOL="$DEFAULT_POOL"
else
    echo "检测到国家代码: $COUNTRY"
    case "$COUNTRY" in
        "US")
            POOL="pearl-us-east.luckypool.io"   # 可改为 west 根据喜好
            ;;
        "SG")
            POOL="pearl-sg1.luckypool.io"
            ;;
        "RU")
            POOL="pearl-ru.luckypool.io"
            ;;
        "CA")
            POOL="pearl-ca1.luckypool.io"
            ;;
        "BR")
            POOL="pearl-br.luckypool.io"
            ;;
        # 欧洲主要国家
        "DE"|"FR"|"GB"|"IT"|"ES"|"NL"|"BE"|"PL"|"SE"|"NO"|"DK"|"FI"|"CH"|"AT"|"IE"|"PT"|"GR"|"CZ"|"HU"|"RO"|"BG"|"HR"|"SK"|"SI"|"LT"|"LV"|"EE"|"LU"|"MT"|"CY")
            POOL="pearl-eu1.luckypool.io"
            ;;
        *)
            echo "未匹配到专属区域，使用默认池（美国）"
            POOL="$DEFAULT_POOL"
            ;;
    esac
fi

FULL_POOL="${POOL}:${PORT}"
echo "选择的矿池: $FULL_POOL"

# 检查并下载/解压程序
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "下载 SRBMiner-Multi ..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压 ..."
    tar -xzf "$FILENAME"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    rm -f "$FILENAME"
fi

# 确保二进制可执行
if [ ! -f "$BINARY" ]; then
    echo "错误：找不到 $BINARY，请检查解压是否完整"
    exit 1
fi
chmod +x "$BINARY"

# 启动挖矿
cd "$EXTRACT_DIR" || exit 1
./SRBMiner-MULTI --algorithm "$ALGORITHM" --pool "$FULL_POOL" --wallet "$WALLET" --worker "$WORKER"
