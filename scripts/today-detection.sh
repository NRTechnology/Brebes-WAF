#!/bin/bash

TODAY=$(date +%Y%m%d)

find /var/log/nginx/modsecurity/$TODAY -type f | while read LOG
do
    echo "=================================================="
    echo "Log File : $LOG"
    echo "=================================================="

    echo "===== BREBES-WAF ====="
    strings "$LOG" | grep "BREBES-WAF"

    echo
    echo "===== OWASP CRS ====="
    strings "$LOG" | grep 'id "' | grep -v "BREBES-WAF"

    echo
done
