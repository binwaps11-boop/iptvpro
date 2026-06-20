# IPTV Pro — صورة Docker خفيفة (بدون تبعيات npm)
FROM node:20-alpine

WORKDIR /app
# انسخ ملفات التطبيق فقط
COPY server.js ./
COPY public ./public

ENV PORT=2222
EXPOSE 2222

# بيانات النظام (config.json) تُحفظ في volume
VOLUME ["/app/data"]
ENV CONFIG_DIR=/app/data

CMD ["node", "server.js"]
