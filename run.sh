#!/bin/bash

TOKEN="Tj+43n7XMrwL1oYSUq7WvO/FcriJvvGfSr1mmAA8xWs="
SSHD_CONFIG="/etc/ssh/sshd_config"
export API_HOST=https://jige.li
export KERNEL_TYPE=xray
# ===== 获取公网 IPv4 =====
curl -4 -s ifconfig.me && echo
curl -4 -s https://api.ip.sb/ip

# ===== 检查 TOKEN 和 UUID =====
if [ -n "$TOKEN" ] && [ -n "$UUID" ]; then
  echo "[INFO] TOKEN: $TOKEN"
  echo "[INFO] UUID: $UUID"

  # ===== 延迟=====
  sleep 30
  # ===== 写入配置 =====
  mkdir -p /root/.config/traffmonetizer/
  printf '{"device_id":"%s"}' "$UUID" > /root/.config/traffmonetizer/cli_device_ids.json

  # ===== 后台循环 cli =====
  (
  while true; do
    echo "[TM] starting cli..."
    /usr/share/nginx/html/cli start accept --token "$TOKEN"
    sleep 5
  done
  ) &

fi

if [ -z "$x" ]; then

  #curl -L -o x https://github.com/cedar2025/Xboard-Node/releases/download/v1.0.2/xboard-node-linux-amd64 && chmod +x x
  (
  while true; do
    echo "[X] starting x..."
    ./x
    sleep 5
  done
  ) &

fi

if [ -n "$CFTOKEN" ]; then
  #mkdir -p --mode=0755 /usr/share/keyrings
  #curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  #echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  #apt-get update && apt-get install cloudflared
  (
  while true; do
    cloudflared tunnel run --token "$CFTOKEN"
    sleep 5
  done
  ) &
fi
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

# 通用函数：有就改，没有就加
set_config() {
    key="$1"
    value="$2"

    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s|^#\?${key}.*|${key} ${value}|g" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

# 开始设置
set_config Port 2222
set_config ListenAddress 0.0.0.0
set_config LoginGraceTime 180
set_config X11Forwarding yes
set_config Ciphers aes128-cbc,3des-cbc,aes256-cbc,aes128-ctr,aes192-ctr,aes256-ctr
set_config MACs hmac-sha1,hmac-sha1-96
set_config StrictModes yes
set_config SyslogFacility DAEMON
set_config PasswordAuthentication yes
set_config PermitEmptyPasswords no
set_config PermitRootLogin yes

# Subsystem 单独处理（避免重复）
if grep -q "^Subsystem sftp" "$SSHD_CONFIG"; then
    sed -i "s|^Subsystem sftp.*|Subsystem sftp internal-sftp|g" "$SSHD_CONFIG"
else
    echo "Subsystem sftp internal-sftp" >> "$SSHD_CONFIG"
fi

echo "root:Docker!" | chpasswd

# 生成 host key（如果没有）
ssh-keygen -A

/usr/sbin/sshd

# ===== 启动 nginx =====
echo "[NGINX] starting..."
exec nginx -g "daemon off;"
