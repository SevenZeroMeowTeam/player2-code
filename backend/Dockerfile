# 后端 Dockerfile (Debian bookworm-slim 基础)
FROM node:20-bookworm-slim AS deps
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM node:20-bookworm-slim
LABEL org.opencontainers.image.description="Player2 AI Backend (Debian)"
WORKDIR /app
ENV NODE_ENV=production
ENV TZ=Asia/Shanghai
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates tzdata \
 && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
 && echo "${TZ}" > /etc/timezone \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -r nodejs \
 && useradd -r -g nodejs -M -s /usr/sbin/nologin nodejs \
 && chown -R nodejs:nodejs /app
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs src ./src
COPY --chown=nodejs:nodejs package*.json ./
USER nodejs
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1
CMD ["node", "src/server.js"]
