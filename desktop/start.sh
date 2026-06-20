#!/usr/bin/env bash
# مُشغّل محلي سريع — يفتح لوحة الإدارة تلقائياً.
# ملاحظة: المنفذان 221/331 محجوزان محلياً ويحتاجان root؛ لذا نستخدم منافذ عالية محلياً.
cd "$(dirname "$0")"
export USER_PORT="${USER_PORT:-2221}"
export ADMIN_PORT="${ADMIN_PORT:-3331}"
URL="http://localhost:$ADMIN_PORT/admin"

( sleep 1.5
  if command -v xdg-open >/dev/null; then xdg-open "$URL"
  elif command -v open    >/dev/null; then open "$URL"
  fi ) &

node server.js
