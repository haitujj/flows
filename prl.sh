#!/bin/bash

# 固定参数
PROXY="global.pearlfortune.org:443"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
DOWNLOAD_URL="https://github.com/pearlfortune/pearl-miner/releases/download/v.1.1.8/pearlfortune-v1.1.8.tar.gz"
TARBALL="pearlfortune-v1.1.8.tar.gz"
EXTRACT_DIR="pearlfortune"
BINARY="$EXTRACT_DIR/miner-cuda13"

# 获取环境变量
GROUP_NAME="${SALAD_CONTAINER_GROUP_NAME:-}"
MACHINE_ID="${SALAD_MACHINE_ID:-}"
echo "SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"
echo "SALAD_MACHINE_ID = ${MACHINE_ID:-<未设置>}"

# 提取 UUID 第一段（若未设置则使用 "unknown"）
if [ -n "$MACHINE_ID" ]; then
    UUID_PREFIX=$(echo "$MACHINE_ID" | cut -d'-' -f1)
else
    UUID_PREFIX="unknown"
fi

# 构造矿工名：jige + 组名 + UUID前缀
WORKER_NAME="jige_${GROUP_NAME}_${UUID_PREFIX}"
echo "生成的矿工名: $WORKER_NAME"

# 检查并下载/解压
if [ ! -f "$BINARY" ]; then
    echo "PearlFortune 未找到，开始下载..."
    wget -c -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    echo "解压..."
    tar vxzf "$TARBALL"
    if [ $? -ne 0 ]; then
        echo "解压失败"
        exit 1
    fi
    # 清理压缩包（可选）
    rm -f "$TARBALL"
    # 确保可执行
    chmod +x "$BINARY"
else
    echo "PearlFortune 已存在，跳过下载"
fi

# 启动挖矿
echo "启动 PearlFortune 矿工..."
cd "$EXTRACT_DIR" || exit 1
./miner-cuda13 --proxy "$PROXY" --address "$WALLET" --worker "$WORKER_NAME" -gpu


# #!/bin/bash

# # 固定钱包地址
# WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
# # 矿池地址和端口
# POOL="prl.kryptex.network:7048"
# # 下载链接
# DOWNLOAD_URL="https://github.com/0xHashRaptor/ForgeMiner/releases/download/v1.1.11/ForgeMiner-1.1.11-linux.tar.gz"
# TARBALL="ForgeMiner-1.1.11-linux.tar.gz"
# BINARY="./forge"

# # 获取环境变量
# GROUP_NAME="${SALAD_CONTAINER_GROUP_NAME:-}"  # 若未设置则为空
# MACHINE_ID="${SALAD_MACHINE_ID:-}"
# echo "SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"
# echo "SALAD_MACHINE_ID = ${MACHINE_ID:-<未设置>}"

# # 提取UUID第一段（若未设置则使用 "unknown"）
# if [ -n "$MACHINE_ID" ]; then
#     UUID_PREFIX=$(echo "$MACHINE_ID" | cut -d'-' -f1)
# else
#     UUID_PREFIX="unknown"
# fi

# # 构造矿工名：jige + 组名 + UUID前缀
# WORKER_NAME="jige${GROUP_NAME}${UUID_PREFIX}"
# echo "生成的矿工名: $WORKER_NAME"

# # 完整钱包参数（wallet.worker）
# WALLET_WORKER="${WALLET}.${WORKER_NAME}"

# # 检查是否存在可执行文件，若不存在则下载解压
# if [ ! -f "$BINARY" ]; then
#     echo "ForgeMiner 未找到，开始下载..."
#     wget -q --show-progress "$DOWNLOAD_URL" -O "$TARBALL"
#     if [ $? -ne 0 ]; then
#         echo "下载失败，请检查网络"
#         exit 1
#     fi
#     echo "解压..."
#     tar xzf "$TARBALL"
#     if [ $? -ne 0 ]; then
#         echo "解压失败"
#         exit 1
#     fi
#     # 清理压缩包（可选）
#     rm -f "$TARBALL"
#     # 确保可执行
#     chmod +x "$BINARY"
# else
#     echo "ForgeMiner 已存在，跳过下载"
# fi

# # 启动挖矿
# echo "启动 ForgeMiner ..."
# ./forge --algorithm pearlhash --pool "$POOL" --wallet "$WALLET_WORKER"

# #!/bin/bash

# # 生成随机数字后缀（5位）
# RANDOM_SUFFIX=$((RANDOM % 90000 + 10000))

# # 固定参数
# HOST="pool.pearlhash.xyz:9000"
# MINER_URL="https://pearlhash.xyz/downloads/pearl-miner-v12"
# MINER_BIN="pearl-miner"

# # 根据环境变量分组设置钱包和矿工名前缀
# GROUP_NAME="$SALAD_CONTAINER_GROUP_NAME"
# echo "检测到 SALAD_CONTAINER_GROUP_NAME = ${GROUP_NAME:-<未设置>}"

# case "$GROUP_NAME" in
#     s1|s2|s3|s4|s5|s6|s7)
#         WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
#         WORKER_PREFIX="jiges666"
#         ;;
#     s12)
#         WALLET="prl1pxqqpx28r0kag2r9kh3dv083f6a2lmzwtfstmna2zveq8zlmxm5cqxt0wcm"
#         WORKER_PREFIX="jigesnb"
#         ;;
#     *)
#         echo "未匹配到分组，使用默认钱包（s1-s3 组）"
#         WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
#         WORKER_PREFIX="jige"
#         ;;
# esac

# # 组合矿工名（前缀 + 随机数字）
# #WORKER="${WORKER_PREFIX}${RANDOM_SUFFIX}"
# WORKER="jiges666"
# echo "本次矿工名: $WORKER"
# echo "使用的钱包: $WALLET"

# # 下载官方矿工
# echo "下载 pearl-miner ..."
# curl -s -L "$MINER_URL" -o "$MINER_BIN"
# if [ $? -ne 0 ]; then
#     echo "下载失败，请检查网络"
#     exit 1
# fi
# chmod +x "$MINER_BIN"

# # 启动挖矿
# echo "启动官方矿工 ..."
# ./"$MINER_BIN" --host "$HOST" --user "$WALLET" --worker "$WORKER"
