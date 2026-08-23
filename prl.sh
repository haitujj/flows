#!/bin/bash

# 固定参数
COIN="pearl"
POOL="stratum+tcp://prl.kryptex.network:7048"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

# 获取WORKER：从SALAD_MACHINE_ID取前8位
MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"  # fallback
fi
echo "矿工名: $WORKER"
USER="${WALLET}/${WORKER}"

# 下载信息
DOWNLOAD_URL="https://github.com/peakminer/peakminer/releases/download/v2.11.0/peakminer-2.11.0.tar.gz"
TARBALL="peakminer-2.11.0.tar.gz"
EXTRACT_DIR="peakminer"
BINARY="$EXTRACT_DIR/peakminer"

# 检查解压目录是否存在，若不存在则下载并解压
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "peakminer 未找到，开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压中..."
    tar xzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包
    rm -f "$TARBALL"
else
    echo "peakminer 已存在，跳过下载"
fi

# 确保二进制可执行
if [ ! -f "$BINARY" ]; then
    echo "错误：未找到 $BINARY，请检查解压是否完整"
    exit 1
fi
chmod +x "$BINARY"

# 启动挖矿
echo "启动 peakminer，矿工名: $WORKER"
cd "$EXTRACT_DIR" || exit 1
./peakminer --coin "$COIN" -o "$POOL" -u "$USER"
