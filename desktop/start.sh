#!/usr/bin/env bash
# مُشغّل سريع — يفتح المتصفح تلقائياً بعد تشغيل الخادم
cd "$(dirname "$0")"
PORT="${PORT:-2222}"
URL="http://localhost:$PORT"

( sleep 1.5
  if command -v xdg-open >/dev/null; then xdg-open "$URL"
  elif command -v open    >/dev/null; then open "$URL"
  fi ) &

PORT="$PORT" node server.js
