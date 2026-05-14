#!/usr/bin/env bash
# Liveness probe. Exits 0 if the stack responds; otherwise non-zero.
set -e
URL="${1:-https://erp.example.com/up}"
curl -fsSL --max-time 10 "$URL" > /dev/null
echo "ok"
