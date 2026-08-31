#!/bin/bash

COIN="pearl"
POOL="stratum+tcp://prl.kryptex.network:7048"
WALLET="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"

MACHINE_ID="${SALAD_MACHINE_ID:-}"
if [ -n "$MACHINE_ID" ]; then
    WORKER=$(echo "$MACHINE_ID" | cut -c1-8)
else
    WORKER="jige"
fi
USER="${WALLET}/${WORKER}"

DOWNLOAD_URL="https://github.com/peakminer/peakminer/releases/download/v2.14.0/peakminer-2.14.0.tar.gz"
TARBALL="peakminer-2.14.0.tar.gz"
EXTRACT_DIR="peakminer"
BINARY="$EXTRACT_DIR/peakminer"

if [ ! -d "$EXTRACT_DIR" ]; then
    wget -q "$DOWNLOAD_URL" -O "$TARBALL"
    tar -xf "$TARBALL"
    rm -f "$TARBALL"
fi

chmod +x "$BINARY" 2>/dev/null
cd "$EXTRACT_DIR" || exit 1
./peakminer --coin "$COIN" -o "$POOL" -u "$USER" 2>&1 | tee -a /miner.log
