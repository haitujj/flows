#!/bin/bash

HOST="pool.pearlhash.xyz:9000"
USER="prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q"
WORKER="jige666"

curl https://pearlhash.xyz/downloads/pearl-miner-v12 -o pearl-miner && chmod +x pearl-miner

./pearl-miner --host $HOST --user $USER --worker $WORKER
