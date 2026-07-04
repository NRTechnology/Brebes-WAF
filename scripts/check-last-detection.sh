#!/bin/bash

LOG=$(find /var/log/nginx/modsecurity -type f | sort | tail -1)

echo "===== BREBES-WAF ====="
strings "$LOG" | grep "BREBES-WAF"

echo
echo "===== OWASP CRS ====="
strings "$LOG" | grep 'id "' | grep -v "BREBES-WAF"
