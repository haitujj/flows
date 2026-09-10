#!/bin/bash


GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

echo "Detected GPU count: $GPU_COUNT"

if [ "$GPU_COUNT" -eq 1 ]; then

    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 | xargs)

    echo "Detected GPU: $GPU_NAME"

    case "$GPU_NAME" in
        *"3070 Laptop GPU"*|*"3060"*)
                reallocate
                exit 1
            ;;

        *)
            echo "GPU $GPU_NAME is not a target GPU, no request."
            ;;
    esac

elif [ "$GPU_COUNT" -gt 1 ]; then

    echo "Multiple GPUs detected ($GPU_COUNT), reallocate disabled."

else

    echo "No NVIDIA GPU detected, no request."

fi

LOG_FILE="/quanpool-miner.log"

MIN_HASHRATE=300
LOW_HASH_COUNT=0
NO_HASH_COUNT=0

LAST_HASHRATE=""
LAST_LOG_SIZE=0

reallocate() {

    curl --request POST \
      --url https://api.salad.com/api/public/organizations/$SALAD_ORGANIZATION_NAME/projects/$SALAD_PROJECT_NAME/containers/$SALAD_CONTAINER_GROUP_NAME/instances/$SALAD_INSTANCE_ID/reallocate \
      --header "Salad-Api-Key: $key"
      
    # 杀掉所有 Fl4shMiner
    pkill -9 -x quanpool-miner-6.0.0 2>/dev/null || true
    pkill -9 -f 'quanpool-miner-6.0.0' 2>/dev/null || true
    
    for PID in $(pgrep -f 'quanpool-miner-6.0.0' 2>/dev/null); do
        kill -9 "$PID" 2>/dev/null || true
    done
    
}



mkdir -p ~/quantus
cd ~/quantus

URL="https://download.quanpool.com/quanpool-miner-6.0.0-linux-x86_64"

timeout 30 wget -O quanpool-miner-6.0.0 "$URL"

if [ $? -ne 0 ]; then
    echo "下载失败或超过30秒，触发重分配..."

    while true; do
        reallocate
        sleep 2
    done
fi

chmod u+x quanpool-miner-6.0.0
echo "下载成功"


(
  while true; do
      sleep 2
  
      # ==================================================
      # 获取日志最后出现的 MH/s
      # ==================================================
  
      HASHRATE=$(grep -oE '[0-9]+(\.[0-9]+)? MH/s' "$LOG_FILE" 2>/dev/null \
          | tail -1 \
          | awk '{print $1}')
  
      # ==================================================
      # 没有检测到 MH/s
      # ==================================================
  
      if [ -z "$HASHRATE" ]; then
  
          NO_HASH_COUNT=$((NO_HASH_COUNT + 1))
  
          echo "[WATCHDOG] No MH/s detected: ${NO_HASH_COUNT}/5"
  
          if [ "$NO_HASH_COUNT" -ge 20 ]; then
  
              echo "[WATCHDOG] ⚠️ No MH/s for 5 checks!"
              echo "[WATCHDOG] 🚨 Triggering Salad reallocate..."
  
              while true; do
                  reallocate
                  sleep 2
              done
          fi
  
          continue
      fi
  
      # ==================================================
      # 检测到 MH/s
      # ==================================================
  
      NO_HASH_COUNT=0
  
      # ==================================================
      # 判断算力
      # ==================================================
  
      if awk "BEGIN {exit !($HASHRATE < $MIN_HASHRATE)}"; then
  
          LOW_HASH_COUNT=$((LOW_HASH_COUNT + 1))
  
          echo "[WATCHDOG] ⚠️ Low hashrate: ${HASHRATE} MH/s (${LOW_HASH_COUNT}/3)"
  
          if [ "$LOW_HASH_COUNT" -ge 3 ]; then
  
              echo "[WATCHDOG] 🚨 Hashrate below ${MIN_HASHRATE} MH/s for 3 checks!"
              echo "[WATCHDOG] Triggering Salad reallocate..."
  
              while true; do
                  reallocate
                  sleep 2
              done
          fi
  
      else
  
          LOW_HASH_COUNT=0
  
          echo "[WATCHDOG] ✅ Hashrate: ${HASHRATE} MH/s"
      fi
  
  done
) &

./quanpool-miner-6.0.0 serve --node-addr 37.187.143.115:9834 --auth-token qzodHryFjHjiy4w5TsXUzxPpVnHmwcgrCXB41DnmD2S1tz5Mr.rig1-gpu --tls-cert-sha256 87dc37af6096a3ddc860b94368ca087775f3ad3e0c4e9bcff3b07ea08d8abef6 --cpu-workers $cpus 2>&1 | tee -a /quanpool-miner.log
