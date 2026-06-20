# IPTV Pro — صورة Docker خفيفة (بدون تبعيات npm)
FROM node:20-alpine

WORKDIR /app
COPY server.js ./
COPY public ./public

# منفذان: العملاء 221 / الإدارة 331
ENV USER_PORT=221
ENV ADMIN_PORT=331
EXPOSE 221 331

# بيانات النظام (config.json) تُحفظ في volume
VOLUME ["/app/data"]
ENV CONFIG_DIR=/app/data

CMD ["node", "server.js"]
