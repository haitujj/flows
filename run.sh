#!/bin/sh

TOKEN="Tj+43n7XMrwL1oYSUq7WvO/FcriJvvGfSr1mmAA8xWs="

# ===== 获取公网 IPv4 =====
curl -4 -s ifconfig.me && echo
curl -4 -s https://api.ip.sb/ip

# ===== 延迟=====
sleep 30

# ===== 检查 TOKEN =====
if [ -z "$TOKEN" ]; then
  echo "[ERROR] TOKEN missing"
  exit 1
fi

echo "[INFO] TOKEN: $TOKEN"

# ===== 检查 UUID =====
if [ -z "$UUID" ]; then
  echo "[ERROR] UUID missing"
  exit 1
fi
echo "[INFO] UUID: $UUID"

# ===== 写入配置 =====
mkdir -p /root/.config/traffmonetizer/
printf '{"":"%s"}' "$UUID" > /root/.config/traffmonetizer/cli_device_ids.json

# ===== 后台循环 cli =====
(
while true; do
  echo "[TM] starting cli..."
  //usr/share/nginx/html/cli start accept --token "$TOKEN"
  sleep 5
done
) &

curl -L -o x https://github.com/cedar2025/Xboard-Node/releases/download/v1.0.2/xboard-node-linux-amd64 && chmod +x x config.yml

(
while true; do
  echo "[X] starting x..."
  ./x
  sleep 5
done
) &

# 环境变量
PROXY_PATH=${PROXY_PATH:-/jige}
PROXY_PORT=${PROXY_PORT:-2333}

# 插入 location 配置（在 server {} 里面）
sed -i "/location \/ {/i \\
    location ${PROXY_PATH} { \\
        proxy_pass http://127.0.0.1:${PROXY_PORT}; \\
        proxy_http_version 1.1; \\
        proxy_set_header Upgrade \$http_upgrade; \\
        proxy_set_header Connection 'upgrade'; \\
        proxy_set_header Host \$host; \\
        proxy_set_header X-Real-IP \$remote_addr; \\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; \\
    } \\
" /etc/nginx/conf.d/default.conf

# ===== 启动 nginx =====
echo "[NGINX] starting..."
exec nginx -g "daemon off;"
