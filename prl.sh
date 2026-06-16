#!/bin/bash

# HOST="pool.pearlhash.xyz:9000"
# USER="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
# WORKER="jige666"

# curl https://pearlhash.xyz/downloads/pearl-miner-v12 -o pearl-miner && chmod +x pearl-miner

# ./pearl-miner --host $HOST --user $USER --worker $WORKER

#自动根据 IP 地区选择矿池并启动 SRBMiner-Multi

set -e  # 出错即退出

# ========== 配置 ==========
DOWNLOAD_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/3.3.9/SRBMiner-Multi-3-3-9-Linux.tar.gz"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q.jige666"
ALGORITHM="pearlhash"
MINER_DIR="SRBMiner-Multi-3-3-9"
MINER_BIN="./SRBMiner-MULTI"

# 亚洲国家代码列表（ISO 3166-1 alpha-2）
ASIA_COUNTRIES=(
    CN JP KR SG IN TW HK MO TH VN MY ID PH PK BD LK NP KH LA MM BN TL MN KP
    IR IQ SA YE OM AE KW QA BH LB JO IL CY TR GE AZ AM UZ KZ TM KG TJ AF
)

# ========== 函数：获取国家代码 ==========
get_country() {
    local country=""

    # 1. 尝试 ipinfo.io（需要外网访问）
    if command -v curl &>/dev/null; then
        country=$(curl -s --connect-timeout 5 "https://ipinfo.io/json" 2>/dev/null | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    elif command -v wget &>/dev/null; then
        country=$(wget -qO- --timeout=5 "https://ipinfo.io/json" 2>/dev/null | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    fi
    if [ -n "$country" ]; then
        echo "$country"
        return 0
    fi

    # 2. 备用：ip-api.com（无需 API key）
    if command -v curl &>/dev/null; then
        country=$(curl -s --connect-timeout 5 "http://ip-api.com/json/" 2>/dev/null | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
    elif command -v wget &>/dev/null; then
        country=$(wget -qO- --timeout=5 "http://ip-api.com/json/" 2>/dev/null | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
    fi
    if [ -n "$country" ]; then
        echo "$country"
        return 0
    fi

    # 所有 API 均失败，返回空
    return 1
}

# ========== 主流程 ==========
echo "===== SRBMiner-Multi 自动切换矿池脚本 ====="

# 1. 下载和解压矿机（如果尚未下载）
if [ ! -d "$MINER_DIR" ]; then
    echo "-> 下载 SRBMiner-Multi ..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress "$DOWNLOAD_URL" -O SRBMiner-Multi.tar.gz
    elif command -v curl &>/dev/null; then
        curl -L -o SRBMiner-Multi.tar.gz "$DOWNLOAD_URL"
    else
        echo "错误：未找到 wget 或 curl，请安装后再试。"
        exit 1
    fi
    echo "-> 解压中 ..."
    tar -xzf SRBMiner-Multi.tar.gz
    rm -f SRBMiner-Multi.tar.gz
else
    echo "-> 矿机目录已存在，跳过下载。"
fi

cd "$MINER_DIR" || { echo "无法进入目录 $MINER_DIR"; exit 1; }

# 2. 获取国家代码
echo "-> 正在检测地理位置 ..."
COUNTRY=$(get_country)
if [ -z "$COUNTRY" ]; then
    echo "警告：无法获取国家代码，将使用默认矿池（北美）。"
    POOL="us.nushypool.com:40015"
else
    echo "检测到国家代码：$COUNTRY"
    # 判断是否属于亚洲
    is_asia=0
    for c in "${ASIA_COUNTRIES[@]}"; do
        if [ "$COUNTRY" = "$c" ]; then
            is_asia=1
            break
        fi
    done

    if [ "$COUNTRY" = "US" ] || [ "$COUNTRY" = "CA" ] || [ "$COUNTRY" = "MX" ]; then
        POOL="us.nushypool.com:40015"
        echo "-> 选择北美矿池"
    elif [ $is_asia -eq 1 ]; then
        POOL="as.nushypool.com:40015"
        echo "-> 选择亚洲矿池"
    else
        POOL="nushypool.com:40015"
        echo "-> 选择欧洲/其他矿池"
    fi
fi

echo "-> 最终使用矿池：$POOL"

# 3. 启动挖矿
echo "-> 启动 SRBMiner-Multi ..."
exec "$MINER_BIN" --algorithm "$ALGORITHM" --pool "stratum+tcp://$POOL" --wallet "$WALLET"
