#!/bin/bash

wget -O peakminer-2.11.0.tar.gz https://github.com/peakminer/peakminer/releases/download/v2.11.0/peakminer-2.11.0.tar.gz
tar xzf peakminer-2.11.0.tar.gz && cd peakminer
./peakminer --coin pearl -o stratum+tcp://prl.kryptex.network:7048 -u prl1pe2ae2q2j4nnhhx39z6548td6j765wsdy8n6mx0axpxmcqh6ef33sj32q4q/$SALAD_MACHINE_I
